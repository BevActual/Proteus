//! proteus-shell — owned iced layer-shell session.
//!
//! Starts control socket + platform stubs, then opens concurrent layer-shell
//! surfaces via `iced_layershell::daemon`. Application logic lives in [`app`].

mod app;

use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicU64};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

use iced::Task;
use iced_layershell::build_pattern::daemon;
#[cfg(test)]
use iced_layershell::reexport::{Anchor, KeyboardInteractivity, Layer};
use iced_layershell::settings::Settings;

use proteus_shell::ctl::{self, ChromeState, SharedChrome};
use proteus_shell::engine;
use proteus_shell::faces::Face;
use proteus_shell::layers;
use proteus_shell::lock_ui::LockUiState;
use proteus_shell::platform::{self, PowerStatus, PrivacyDots};
use proteus_shell::surfaces;
use proteus_shell::wm_ipc::{self, WmState};
use proteus_ui::theme::Theme;

use app::*;

fn usage() -> ! {
    eprintln!(
        "usage: proteus-shell [--headless] [--face desktop|console|host]\n\
         \n\
         Owned iced shell (OWNED-STACK rung 1). Face selects layer set +\n\
         exclusive UI under shell/src/faces/ (shared chrome in surfaces)."
    );
    std::process::exit(2);
}

fn run_headless() -> ! {
    eprintln!("proteus-shell: headless — ctl only (no layer windows)");
    loop {
        thread::sleep(Duration::from_secs(3600));
    }
}


fn main() -> Result<(), iced_layershell::Error> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.iter().any(|a| a == "-h" || a == "--help") {
        usage();
    }
    let headless = args.iter().any(|a| a == "--headless");
    let face = Face::parse(
        args
            .iter()
            .position(|a| a == "--face")
            .and_then(|i| args.get(i + 1))
            .map(|s| s.as_str())
            .unwrap_or("desktop"),
    );

    let chrome: SharedChrome = Arc::new(Mutex::new(ChromeState {
        face: face.as_str().to_string(),
        ..Default::default()
    }));
    // Cold-boot lock when settings ask for it
    {
        let base = proteus_shell_core::facts::config_base();
        let settings = proteus_shell_core::facts::read_settings(&base);
        let lock_on = settings
            .get("lockOnSessionStart")
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        if lock_on {
            if let Ok(mut s) = chrome.lock() {
                s.locked = true;
                s.session_start_lock_pending = true;
            }
        }
        // Seed widgets from settings.json desktopWidgets if present
        if let Some(arr) = settings.get("desktopWidgets").and_then(|v| v.as_array()) {
            if let Ok(mut s) = chrome.lock() {
                s.widgets = arr
                    .iter()
                    .filter_map(|v| v.get("kind").and_then(|k| k.as_str()).map(|s| s.to_string()))
                    .collect();
            }
        }
    }
    let chrome_epoch: ChromeEpoch = Arc::new(AtomicU64::new(0));
    let notifs = platform::start_local_notifd();
    let tray = platform::start_tray_watcher();
    let wm_shared = wm_ipc::shared_from_state(wm_ipc::refresh_state());
    wm_ipc::spawn_socket2_listener(Arc::clone(&wm_shared));
    let sock = engine::control_socket_path();
    if let Err(e) = ctl::serve(&sock, Arc::clone(&chrome), Arc::clone(&chrome_epoch)) {
        eprintln!("proteus-shell: control socket: {e}");
        std::process::exit(1);
    }
    let lock_req = engine::resolve_session_lock();
    let (lock_mode, lock_fb) = engine::activate_session_lock(lock_req);
    if let Some(reason) = lock_fb {
        eprintln!("proteus-shell: session-lock fallback: {reason}");
    }
    eprintln!(
        "proteus-shell: engine=owned face={} compositor={} session_lock={} (req={}) socket={} audio_mix={}",
        face.as_str(),
        engine::resolve_compositor_engine(),
        lock_mode.as_str(),
        lock_req.as_str(),
        sock.display(),
        platform::audio_mix_available()
    );

    {
        thread::spawn(move || {
            let base = proteus_shell_core::facts::config_base();
            let mut watch = proteus_shell_core::subscribe::FactsWatch::new(base);
            loop {
                let _ = watch.poll();
                thread::sleep(Duration::from_millis(500));
            }
        });
    }

    thread::spawn(proteus_shell::beacon::warm_file_index);

    if headless
        || (std::env::var_os("WAYLAND_DISPLAY").is_none()
            && std::env::var_os("WAYLAND_SOCKET").is_none())
    {
        if !headless {
            eprintln!("proteus-shell: no WAYLAND_DISPLAY — falling back to --headless");
        }
        run_headless();
    }

    let single = std::env::var("PROTEUS_SHELL_NAMESPACE").ok();
    let primary = single
        .clone()
        .unwrap_or_else(|| layers::BAR.to_string());
    let single_surface = single.is_some();
    let ns_for_settings = primary.clone();
    let theme = {
        let base = proteus_shell_core::facts::config_base();
        Theme::from_settings(&proteus_shell_core::facts::read_settings(&base))
    };

    let chrome_boot = Arc::clone(&chrome);
    let epoch_boot = Arc::clone(&chrome_epoch);
    let notifs_boot = Arc::clone(&notifs);
    let tray_boot = Arc::clone(&tray);
    let wm_boot = Arc::clone(&wm_shared);
    let face_boot = face;
    let primary_boot = primary.clone();
    let ns_name = primary.clone();

    // All subprocess polling lives on this worker; the UI thread only copies
    // its snapshot (a hung child process must never freeze the shell).
    let heavy_shared = Arc::new(HeavyShared {
        snap: Mutex::new(HeavySnapshot::default()),
        cc_open: AtomicBool::new(false),
    });
    spawn_heavy_worker(face_boot, Arc::clone(&heavy_shared));
    let heavy_boot = Arc::clone(&heavy_shared);

    daemon(
        move || {
            let desktop_widgets =
                proteus_shell::desktop_widgets::DesktopWidgetsState::load();
            let widget_seed = desktop_widgets.kinds();
            if let Ok(mut c) = chrome_boot.lock() {
                c.widgets = widget_seed.clone();
            }
            let pins = load_dock_pins();
            let dock_icon_size = {
                let base = proteus_shell_core::facts::config_base();
                proteus_shell_core::facts::read_settings(&base)
                    .get("dockIconSize")
                    .and_then(|v| v.as_i64())
                    .unwrap_or(48)
                    .clamp(32, 72) as f32
            };
            let mut app = App {
                theme,
                chrome: Arc::clone(&chrome_boot),
                chrome_epoch: Arc::clone(&epoch_boot),
                last_epoch: 0,
                notifs: Arc::clone(&notifs_boot),
                tray: Arc::clone(&tray_boot),
                tray_items: Vec::new(),
                chrome_snap: ChromeState {
                    face: face_boot.as_str().to_string(),
                    ..Default::default()
                },
                wm: WmState::default(),
                wm_gen: 0,
                wm_shared: Arc::clone(&wm_boot),
                // Live values arrive from the heavy worker within a tick or
                // two — boot must not block on subprocesses.
                power: PowerStatus::default(),
                privacy_dots: PrivacyDots::default(),
                dnd: false,
                volume: None,
                console_games: Vec::new(),
                console_media_path: String::new(),
                console_apps: Vec::new(),
                host_tab: 0,
                host_glance: platform::HostGlance::default(),
                wifi_hits: Vec::new(),
                bt_hits: Vec::new(),
                brightness: None,
                mpris: Vec::new(),
                pins,
                beacon_hits: default_beacon_hits(),
                lock_ui: LockUiState::default(),
                focus_on: false,
                focus_schedule_last: None,
                focus_profiles: Vec::new(),
                focus_active_id: String::new(),
                face: face_boot,
                primary_namespace: primary_boot.clone(),
                wallpaper: platform::WallpaperState::default(),
                wallpaper_handle: None,
                windows: HashMap::new(),
                layer_input_applied: HashMap::new(),
                dock_preview: None,
                single_surface,
                tick_n: 0,
                launcher_open: false,
                cc_open: false,
                hub_open: false,
                spaces_open: false,
                spaces_floor: 1,
                workspace_names: vec![String::new(); 10],
                workspace_mode: "synced".into(),
                spaces_thumbs: HashMap::new(),
                spaces_rename_id: None,
                spaces_rename_buf: String::new(),
                spaces_drag: None,
                spaces_drag_output: None,
                spaces_drag_target: None,
                spaces_drag_target_output: None,
                spaces_need_thumbs: false,
                spaces_rename_focus_pending: false,
                lock_password_focus_pending: false,
                lock_key_debounce: None,
                locked: false,
                hud_kind: String::new(),
                hud_value: 0.0,
                privacy_ask: None,
                privacy_ask_app: None,
                privacy_enforce_at: None,
                beacon_query: String::new(),
                toast: None,
                notif_items: Vec::new(),
                widget_kinds: widget_seed,
                widget_gallery: vec![
                    "Clock".into(),
                    "Weather".into(),
                    "Notes".into(),
                    "Media".into(),
                    "Calendar".into(),
                    "System".into(),
                    "Battery".into(),
                    "WorldClock".into(),
                ],
                desktop_widgets,
                desktop_hold_at: None,
                weather: platform::WeatherGlance::default(),
                wifi_radio_on: true,
                bt_radio_on: false,
                wifi_err: String::new(),
                bt_err: String::new(),
                anims: Anims::default(),
                icon_cache: proteus_shell::icons::IconCache::default(),
                dock_hover_pin: None,
                pending_volume: None,
                pending_brightness: None,
                slider_flush_at: None,
                dock_leave_at: None,
                dock_dwell: None,
                dock_edit: false,
                dock_context: None,
                dock_hold_at: None,
                dock_drag: None,
                dock_drag_target: None,
                dock_drag_off: false,
                dock_bounce: HashMap::new(),
                dock_bounce_strengths: Vec::new(),
                dock_icon_size,
                dock_layout: surfaces::DockLayout::Center,
                dock_rounding: 16.0,
                dock_enabled: true,
                dock_autohide: false,
                dock_edge_armed: true,
                bar_height: surfaces::BAR_EXCLUSIVE,
                bar_rounding: 0.0,
                bar_autohide: false,
                bar_edge_armed: true,
                dock_exclusive_zone: None,
                bar_exclusive_zone: None,
                dock_geom_dirty: false,
                settings_mtime: None,
                beacon_selected: 0,
                hud_deadline: None,
                toast_deadline: None,
                toast_hidden_id: None,
                clock: surfaces::bar_clock_now(),
                beacon_focus_pending: false,
                heavy: Arc::clone(&heavy_boot),
            };
            let _ = pull_wm(&mut app);
            sync_snapshots(&mut app);
            apply_settings_if_changed(&mut app);
            app.weather = platform::weather_glance();
            warm_icons(&mut app);
            let layers_task = boot_extra_layers(&mut app);
            (
                app,
                Task::batch([Task::done(Message::Tick), layers_task]),
            )
        },
        move || ns_name.clone(),
        update,
        view_real,
    )
    .subscription(|app: &App| subscription(app))
    .style(style)
    .theme(iced_theme)
    .settings(Settings {
        layer_settings: layer_settings(&ns_for_settings),
        id: Some(format!("dev.proteus.shell.{ns_for_settings}")),
        ..Default::default()
    })
    .run()
}

#[cfg(test)]
mod layer_geometry_tests {
    use super::*;

    /// wlr-layer-shell: width 0 requires Left+Right anchor; height 0 requires
    /// Top+Bottom. A violation is a compositor protocol error that kills the
    /// client at boot (the wl_surface "x == 0 but anchor doesn't have left and
    /// right" / khronos-egl panic class).
    #[test]
    fn layer_sizes_respect_anchor_protocol() {
        for ns in layers::all() {
            let ls = layer_settings(ns);
            match ls.size {
                None => {
                    assert!(
                        ls.anchor.contains(Anchor::Left)
                            && ls.anchor.contains(Anchor::Right)
                            && ls.anchor.contains(Anchor::Top)
                            && ls.anchor.contains(Anchor::Bottom),
                        "{ns}: size None requires full anchor"
                    );
                }
                Some((w, h)) => {
                    if w == 0 {
                        assert!(
                            ls.anchor.contains(Anchor::Left) && ls.anchor.contains(Anchor::Right),
                            "{ns}: width 0 requires Left+Right anchor"
                        );
                    }
                    if h == 0 {
                        assert!(
                            ls.anchor.contains(Anchor::Top) && ls.anchor.contains(Anchor::Bottom),
                            "{ns}: height 0 requires Top+Bottom anchor"
                        );
                    }
                    assert!(w != 0 || h != 0, "{ns}: zero-area surface");
                }
            }
        }
    }

    /// Only the lock may start with a keyboard grab; everything else gets
    /// Exclusive dynamically via reconcile_layer_input when opened.
    #[test]
    fn only_lock_boots_with_keyboard_grab() {
        for ns in layers::all() {
            let ls = layer_settings(ns);
            if *ns == layers::LOCK {
                assert!(matches!(
                    ls.keyboard_interactivity,
                    KeyboardInteractivity::Exclusive
                ));
            } else {
                assert!(
                    matches!(ls.keyboard_interactivity, KeyboardInteractivity::None),
                    "{ns}: must not boot with a keyboard grab"
                );
            }
        }
    }

    #[test]
    fn wallpaper_and_lock_are_dont_care_exclusive() {
        assert_eq!(layer_settings(layers::BG).exclusive_zone, -1);
        assert_eq!(layer_settings(layers::LOCK).exclusive_zone, -1);
    }

    #[test]
    fn dock_top_with_shelf_exclusive_zone() {
        let ls = layer_settings(layers::DOCK);
        assert!(matches!(ls.layer, Layer::Top));
        assert_eq!(
            ls.exclusive_zone,
            surfaces::dock_strip_h(surfaces::DOCK_ICON_REST) as i32
        );
        assert!(ls.anchor.contains(Anchor::Bottom));
    }

    #[test]
    fn bar_top_with_menu_exclusive_zone() {
        let ls = layer_settings(layers::BAR);
        assert!(matches!(ls.layer, Layer::Top));
        assert_eq!(ls.exclusive_zone, surfaces::BAR_EXCLUSIVE as i32);
    }
}
