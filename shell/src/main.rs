//! proteus-shell — owned iced layer-shell session.
//!
//! Starts control socket + platform stubs, then opens concurrent layer-shell
//! surfaces (bar, dock, Beacon, control center, HUD) via `iced_layershell::daemon`.
//! Use `--headless` for smoke/ctl-only. `PROTEUS_SHELL_NAMESPACE` forces a single
//! surface (dev hook).

use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant, SystemTime};

use iced::widget::{column, container, Space};
use iced::window;
use iced::{Alignment, Color, Element, Length, Task};
use iced_layershell::actions::ActionCallback;
use iced_layershell::build_pattern::daemon;
use iced_layershell::reexport::{
    Anchor, KeyboardInteractivity, Layer, NewLayerShellSettings, OutputOption,
};
use iced_layershell::settings::{LayerShellSettings, Settings, StartMode};
use iced_layershell::to_layer_message;

use proteus_shell::anim::{self, AnimatedValue, Easing};
use proteus_shell::ctl::{self, ChromeState, SharedChrome};
use proteus_shell::engine;
use proteus_shell::wm_ipc::{self, WmState};
use proteus_shell::layers;
use proteus_shell::lock_ui::LockUiState;
use proteus_shell::platform::{self, ConsoleGame, MprisPlayer, Notification, PowerStatus, PrivacyDots, SharedNotifs, SharedTray};
use proteus_shell::faces;
use proteus_shell::surfaces::{self, Message as SurfaceMsg};
use proteus_ui::theme::{ChromeMode, Theme};

/// Bumped by ctl on chrome mutations so the UI can poll faster than heavy sensors.
pub type ChromeEpoch = Arc<AtomicU64>;

fn usage() -> ! {
    eprintln!(
        "usage: proteus-shell [--headless] [--face desktop|console|host]\n\
         \n\
         Owned iced shell (OWNED-STACK rung 1). Default session engine remains\n\
         Quickshell until PROTEUS_SHELL_ENGINE=owned (Wave 4 swap gate).\n\
         Multi-layer boot: all layers::all() namespaces via NewLayerShell (face-aware)."
    );
    std::process::exit(2);
}

/// Desktop face: all QS-parity namespaces (bar is the primary daemon window).
const BOOT_LAYERS_DESKTOP: &[&str] = &[
    layers::DOCK,
    layers::LAUNCHER,
    layers::CONTROL_CENTER,
    layers::SPACES,
    layers::HUD,
    layers::BG,
    layers::DESKTOP_WIDGETS,
    layers::TOAST,
    layers::PRIVACY_ASK,
    layers::LOCK,
];

/// Console/host: no dock/widgets; keep overlays + lock.
const BOOT_LAYERS_LEAN: &[&str] = &[
    layers::LAUNCHER,
    layers::CONTROL_CENTER,
    layers::SPACES,
    layers::HUD,
    layers::BG,
    layers::TOAST,
    layers::PRIVACY_ASK,
    layers::LOCK,
];

fn boot_layers_for_face(face: &str) -> &'static [&'static str] {
    match face {
        "console" | "host" => BOOT_LAYERS_LEAN,
        _ => BOOT_LAYERS_DESKTOP,
    }
}

/// Chrome motion state — QML parity timings (see anim.rs header).
struct Anims {
    /// Control Center open progress 0→1 (200ms OutCubic).
    cc: AnimatedValue,
    /// Beacon open progress 0→1 (180ms OutCubic).
    beacon: AnimatedValue,
    /// HUD visibility 0→1 (160ms OutCubic fade).
    hud: AnimatedValue,
    /// Toast visibility 0→1 (160ms OutCubic fade).
    toast: AnimatedValue,
    /// Dock per-icon hover scale engagement 0→1 (70ms OutCubic).
    dock_hover: AnimatedValue,
    /// Dock autohide reveal 0→1 (180ms OutCubic); 1 = fully shown.
    dock_slide: AnimatedValue,
    /// Menu bar autohide reveal 0→1 (180ms OutCubic).
    bar_slide: AnimatedValue,
    /// Spaces overview open fade 0→1 (180ms OutCubic).
    spaces: AnimatedValue,
}

impl Anims {
    fn active(&self) -> bool {
        self.cc.animating()
            || self.beacon.animating()
            || self.hud.animating()
            || self.toast.animating()
            || self.dock_hover.animating()
            || self.dock_slide.animating()
            || self.bar_slide.animating()
            || self.spaces.animating()
    }
}

impl Default for Anims {
    fn default() -> Self {
        Self {
            cc: AnimatedValue::default(),
            beacon: AnimatedValue::default(),
            hud: AnimatedValue::default(),
            toast: AnimatedValue::default(),
            dock_hover: AnimatedValue::default(),
            dock_slide: AnimatedValue::new(1.0),
            bar_slide: AnimatedValue::new(1.0),
            spaces: AnimatedValue::default(),
        }
    }
}

/// Any chrome motion in flight (kit anims + lock shake + launch bounce + leave bridge).
fn motion_active(app: &App) -> bool {
    app.anims.active()
        || app.lock_ui.shake_active()
        || !app.dock_bounce.is_empty()
        || app.dock_leave_at.is_some()
}

/// Snapshot of everything gathered via subprocesses. Filled by a background
/// worker thread; `update()` only copies it. Subprocess helpers MUST NEVER
/// run on the UI thread — a hung child (e.g. `bluetoothctl` with no bluez)
/// blocks `Command::output()` forever and freezes the whole event loop.
#[derive(Default)]
struct HeavySnapshot {
    power: PowerStatus,
    privacy: PrivacyDots,
    dnd: bool,
    volume: Option<u8>,
    brightness: Option<u8>,
    mpris: Vec<MprisPlayer>,
    wifi: Vec<platform::WifiHit>,
    bt: Vec<platform::BtHit>,
    focus_on: bool,
    focus_profiles: Vec<platform::FocusProfile>,
    focus_active_id: String,
    console_games: Vec<ConsoleGame>,
    console_media_path: String,
    console_apps: Vec<(String, String)>,
    host_glance: platform::HostGlance,
}

struct HeavyShared {
    snap: Mutex<HeavySnapshot>,
    /// Worker polls wifi/bt/focus only while the Control Center is open.
    cc_open: AtomicBool,
}

fn spawn_heavy_worker(face: String, shared: Arc<HeavyShared>) {
    thread::Builder::new()
        .name("heavy-refresh".into())
        .spawn(move || loop {
            let cc = shared.cc_open.load(Ordering::Relaxed);
            let mut s = HeavySnapshot {
                power: platform::power_status(),
                privacy: platform::privacy_dots(),
                dnd: platform::notifications_dnd_fact(),
                volume: platform::volume_get(),
                brightness: platform::brightness_get(),
                mpris: platform::mpris_players(),
                ..Default::default()
            };
            if cc {
                s.wifi = platform::wifi_list_thin();
                s.bt = platform::bt_list_thin();
                s.focus_on = platform::focus_active();
                s.focus_profiles = platform::focus_profiles();
                s.focus_active_id = platform::focus_active_profile_id();
            }
            if face == "console" {
                s.console_games = platform::console_games_list();
                s.console_media_path = platform::console_media_path();
                s.console_apps = platform::console_apps_thin(32);
            }
            if face == "host" {
                s.host_glance = platform::host_glance();
            }
            if let Ok(mut guard) = shared.snap.lock() {
                if !cc {
                    // Keep the last-seen network state while CC is closed.
                    s.wifi = std::mem::take(&mut guard.wifi);
                    s.bt = std::mem::take(&mut guard.bt);
                    s.focus_on = guard.focus_on;
                    s.focus_profiles = std::mem::take(&mut guard.focus_profiles);
                    s.focus_active_id = std::mem::take(&mut guard.focus_active_id);
                }
                *guard = s;
            }
            thread::sleep(Duration::from_millis(1600));
        })
        .expect("spawn heavy-refresh worker");
}

struct App {
    theme: Theme,
    chrome: SharedChrome,
    chrome_epoch: ChromeEpoch,
    last_epoch: u64,
    notifs: SharedNotifs,
    tray: SharedTray,
    tray_items: Vec<platform::TrayItem>,
    chrome_snap: ChromeState,
    hypr: WmState,
    wm_shared: wm_ipc::SharedWm,
    /// Last copied `WmShared.gen` — skip clone when unchanged.
    wm_gen: u64,
    power: PowerStatus,
    privacy_dots: PrivacyDots,
    dnd: bool,
    volume: Option<u8>,
    console_games: Vec<ConsoleGame>,
    console_media_path: String,
    console_apps: Vec<(String, String)>,
    host_tab: usize,
    host_glance: platform::HostGlance,
    wifi_hits: Vec<platform::WifiHit>,
    bt_hits: Vec<platform::BtHit>,
    brightness: Option<u8>,
    mpris: Vec<MprisPlayer>,
    pins: Vec<String>,
    beacon_hits: Vec<String>,
    lock_ui: LockUiState,
    focus_on: bool,
    focus_profiles: Vec<platform::FocusProfile>,
    focus_active_id: String,
    face: String,
    /// Initial daemon window namespace (usually bar). Extra layers live in `windows`.
    primary_namespace: String,
    wallpaper: platform::WallpaperState,
    wallpaper_handle: Option<(String, iced::widget::image::Handle)>,
    windows: HashMap<window::Id, String>,
    layer_input_applied: HashMap<window::Id, (u8, u8)>,
    dock_preview: Option<surfaces::DockPreview>,
    single_surface: bool,
    tick_n: u64,
    launcher_open: bool,
    cc_open: bool,
    /// Center hub (calendar / notifications / weather) open.
    hub_open: bool,
    spaces_open: bool,
    /// Manual minimum visible Space end (overview "+").
    spaces_floor: i64,
    workspace_names: Vec<String>,
    spaces_thumbs: HashMap<String, proteus_shell::spaces::SpaceWinThumb>,
    spaces_rename_id: Option<i64>,
    spaces_rename_buf: String,
    spaces_drag: Option<String>,
    spaces_drag_target: Option<i64>,
    /// Capture grim thumbs next tick/update after overview opens.
    spaces_need_thumbs: bool,
    /// Focus rename field after ✎ (next update).
    spaces_rename_focus_pending: bool,
    /// Focus lock password field after reveal / wake keystroke.
    lock_password_focus_pending: bool,
    /// Debounce identical lock keystrokes (multi-window Interaction duplicates).
    lock_key_debounce: Option<(String, Instant)>,
    locked: bool,
    hud_kind: String,
    hud_value: f32,
    privacy_ask: Option<String>,
    beacon_query: String,
    toast: Option<Notification>,
    notif_items: Vec<Notification>,
    widget_kinds: Vec<String>,
    widget_gallery: Vec<String>,
    desktop_widgets: proteus_shell::desktop_widgets::DesktopWidgetsState,
    /// Wallpaper / empty-desktop hold-to-Customize arm time.
    desktop_hold_at: Option<Instant>,
    weather: platform::WeatherGlance,
    wifi_radio_on: bool,
    bt_radio_on: bool,
    wifi_err: String,
    bt_err: String,
    anims: Anims,
    icon_cache: proteus_shell::icons::IconCache,
    /// Hovered dock pin (hover scale + preview target).
    dock_hover_pin: Option<String>,
    /// Debounced CC slider targets (last value wins; flushed off-thread).
    pending_volume: Option<u8>,
    pending_brightness: Option<u8>,
    slider_flush_at: Option<Instant>,
    /// Pending leave — cleared if hover/preview-enter arrives first.
    dock_leave_at: Option<Instant>,
    /// Hover start for dwell preview (`DOCK_PREVIEW_DWELL_MS`).
    dock_dwell: Option<(String, Instant)>,
    /// Launch bounce until matching window / timeout (`pin → start`).
    dock_bounce: HashMap<String, Instant>,
    /// Cached bounce strengths for the dock view (updated on AnimTick).
    dock_bounce_strengths: Vec<(String, f32)>,
    /// `dockIconSize` Fact (rest icon px).
    dock_icon_size: f32,
    dock_layout: surfaces::DockLayout,
    dock_rounding: f32,
    dock_enabled: bool,
    dock_autohide: bool,
    /// True while pointer is in the hot edge / dock (autohide reveal).
    dock_edge_armed: bool,
    bar_height: u32,
    bar_rounding: f32,
    bar_autohide: bool,
    bar_edge_armed: bool,
    /// Last applied dock exclusive zone — push on change.
    dock_exclusive_zone: Option<i32>,
    bar_exclusive_zone: Option<i32>,
    /// Re-anchor dock layer when layout flips (center/span/left/right).
    dock_geom_dirty: bool,
    /// Last `settings.json` mtime — skip theme/pin/wallpaper reload when unchanged.
    settings_mtime: Option<SystemTime>,
    /// Keyboard-selected Beacon hit index.
    beacon_selected: usize,
    hud_deadline: Option<anim::Deadline>,
    /// (notification id, deadline) for toast auto-dismiss.
    toast_deadline: Option<(u32, anim::Deadline)>,
    /// Toast id already auto-hidden (stays in the CC notification list).
    toast_hidden_id: Option<u32>,
    /// Bar clock strings, refreshed on the slow tick (never in view).
    clock: surfaces::BarClock,
    /// Focus the Beacon input on the next update after opening.
    beacon_focus_pending: bool,
    /// Background subprocess-poll worker output (never gathered on UI thread).
    heavy: Arc<HeavyShared>,
}

#[to_layer_message(multi)]
#[derive(Debug, Clone)]
enum Message {
    Surface(SurfaceMsg),
    Tick,
    /// Fast redraw tick (~30fps), alive only while animations run.
    AnimTick,
    WindowClosed(window::Id),
    /// Raw keyboard for lock wake / PIN (filtered in update).
    LockKey {
        key: iced::keyboard::Key,
        text: Option<String>,
        captured: bool,
        /// Wayland key-repeat — ignore so lag can't insert ghost characters.
        repeat: bool,
        /// Daemon delivers Interaction events per window; only the lock layer
        /// may handle wake/PIN (other layers would double-insert).
        window: window::Id,
    },
    /// Grim thumbnails finished off the UI thread.
    DockPreviewReady {
        pin: String,
        /// (address, title, hidden, png bytes)
        rows: Vec<(String, String, bool, Vec<u8>)>,
    },
    /// Grim thumbnails for Mission Control (address, title, workspace, png).
    SpacesThumbsReady(Vec<(String, String, i64, Vec<u8>)>),
}

fn sync_snapshots(app: &mut App) {
    let was_launcher = app.launcher_open;
    let was_cc = app.cc_open;
    let was_hub = app.hub_open;
    let was_spaces = app.spaces_open;
    let had_hud = !app.hud_kind.is_empty();
    let prev_hud = app.hud_kind.clone();
    let prev_hud_value = app.hud_value;
    let prev_toast_id = app.toast.as_ref().map(|t| t.id);
    if let Ok(c) = app.chrome.lock() {
        app.launcher_open = c.launcher_open;
        app.cc_open = c.control_center_open;
        app.hub_open = c.calendar_open || c.notifications_open || c.weather_open;
        app.spaces_open = c.spaces_open;
        app.locked = c.locked || c.session_start_lock_pending;
        app.hud_kind = c.hud_kind.clone();
        app.hud_value = c.hud_value;
        app.privacy_ask = c.privacy_ask.clone();
        app.beacon_query = c.beacon_query.clone();
        app.widget_kinds = c.widgets.clone();
        // IPC `widgets add` only updates kind list — place any missing.
        for kind in app.widget_kinds.clone() {
            if !app.desktop_widgets.items.iter().any(|w| w.kind == kind) {
                app.desktop_widgets.add(&kind);
            }
        }
        if app.lock_ui.customize != c.lock_customize {
            app.lock_ui.customize = c.lock_customize;
            if c.lock_customize {
                let mpris = app.mpris.clone();
                let power = app.power.clone();
                app.lock_ui.refresh_applets(&mpris, &power);
            }
        }
        app.chrome_snap = ChromeState {
            launcher_open: c.launcher_open,
            control_center_open: c.control_center_open,
            calendar_open: c.calendar_open,
            weather_open: c.weather_open,
            notifications_open: c.notifications_open,
            spaces_open: c.spaces_open,
            locked: c.locked,
            session_start_lock_pending: c.session_start_lock_pending,
            protocol_lock: c.protocol_lock,
            hud_kind: c.hud_kind.clone(),
            hud_value: c.hud_value,
            toast_queue: c.toast_queue.clone(),
            privacy_ask: c.privacy_ask.clone(),
            widgets_customize: c.widgets_customize,
            lock_customize: c.lock_customize,
            widgets: c.widgets.clone(),
            widgets_snap: c.widgets_snap,
            face: c.face.clone(),
            beacon_query: c.beacon_query.clone(),
            console_nav_open: c.console_nav_open,
            console_switcher_open: c.console_switcher_open,
            console_tab: c.console_tab,
        };
    }
    if let Ok(n) = app.notifs.lock() {
        app.toast = n.items.last().cloned();
        app.notif_items = n.items.clone();
    }
    if let Ok(t) = app.tray.lock() {
        app.tray_items = t.items.clone();
    }
    // WM state is pulled via pull_wm() — avoid double-clone here.
    app.last_epoch = app.chrome_epoch.load(Ordering::Relaxed);

    // Motion transitions (QML parity timings).
    if app.launcher_open != was_launcher {
        app.anims.beacon.animate_to(
            if app.launcher_open { 1.0 } else { 0.0 },
            180,
            Easing::OutCubic,
        );
        if app.launcher_open {
            app.beacon_selected = 0;
            app.beacon_focus_pending = true;
        }
    }
    if app.cc_open != was_cc || app.hub_open != was_hub {
        let open = app.cc_open || app.hub_open;
        let was_open = was_cc || was_hub;
        if open != was_open {
            app.anims
                .cc
                .animate_to(if open { 1.0 } else { 0.0 }, 200, Easing::OutCubic);
        }
    }
    if app.spaces_open && !was_spaces {
        app.spaces_need_thumbs = true;
        app.spaces_rename_id = None;
        app.spaces_drag = None;
        app.spaces_drag_target = None;
        app.anims.spaces.set(0.0);
        app.anims.spaces.animate_to(1.0, 180, Easing::OutCubic);
    }
    if !app.spaces_open && was_spaces {
        app.spaces_thumbs.clear();
        app.spaces_rename_id = None;
        app.spaces_rename_buf.clear();
        app.spaces_drag = None;
        app.spaces_drag_target = None;
        app.spaces_need_thumbs = false;
        app.anims.spaces.set(0.0);
    }
    let has_hud = !app.hud_kind.is_empty();
    if has_hud && (!had_hud || app.hud_kind != prev_hud || app.hud_value != prev_hud_value) {
        if !had_hud {
            app.anims.hud.animate_to(1.0, 160, Easing::OutCubic);
        }
        app.hud_deadline = Some(anim::Deadline::after_ms(1500));
    } else if !has_hud && had_hud {
        app.anims.hud.set(0.0);
        app.hud_deadline = None;
    }
    let toast_id = app.toast.as_ref().map(|t| t.id);
    if toast_id != prev_toast_id {
        match toast_id {
            Some(id) => {
                app.anims.toast.animate_to(1.0, 160, Easing::OutCubic);
                app.toast_deadline = Some((id, anim::Deadline::after_ms(4500)));
            }
            None => {
                app.anims.toast.set(0.0);
                app.toast_deadline = None;
            }
        }
    }
}

/// Cheap WM pull from the socket listener — never blocks on compositor ctl.
/// Returns true when the UI snapshot actually changed (`gen` advanced).
fn pull_wm(app: &mut App) -> bool {
    let Ok(h) = app.wm_shared.try_lock() else {
        return false;
    };
    if h.gen == app.wm_gen {
        return false;
    }
    app.wm_gen = h.gen;
    app.hypr = h.state.clone();
    true
}

/// Coalesce dock scrub samples — sub-pixel spam rebuilt the whole shelf.

/// Flush debounced CC volume / brightness to helpers off the UI thread.
fn flush_pending_sliders(app: &mut App) {
    let Some(at) = app.slider_flush_at else {
        return;
    };
    if Instant::now() < at {
        return;
    }
    app.slider_flush_at = None;
    if let Some(v) = app.pending_volume.take() {
        thread::spawn(move || {
            let _ = platform::volume_set(v);
        });
    }
    if let Some(b) = app.pending_brightness.take() {
        thread::spawn(move || {
            let _ = platform::brightness_set(b);
        });
    }
}

fn refresh_heavy(app: &mut App) {
    let _ = pull_wm(app);
    // Copy the worker-gathered snapshot. Never block: skip if the worker
    // holds the lock right now — next tick picks it up.
    app.heavy.cc_open.store(app.cc_open || app.hub_open, Ordering::Relaxed);
    if let Ok(s) = app.heavy.snap.try_lock() {
        app.power = s.power.clone();
        app.privacy_dots = s.privacy.clone();
        app.dnd = s.dnd;
        app.volume = s.volume;
        app.brightness = s.brightness;
        app.mpris = s.mpris.clone();
        if app.cc_open {
            app.wifi_hits = s.wifi.clone();
            app.bt_hits = s.bt.clone();
            app.focus_on = s.focus_on;
            app.focus_profiles = s.focus_profiles.clone();
            app.focus_active_id = s.focus_active_id.clone();
        }
        if app.face == "console" {
            app.console_games = s.console_games.clone();
            app.console_media_path = s.console_media_path.clone();
            app.console_apps = s.console_apps.clone();
        }
        if app.face == "host" {
            app.host_glance = s.host_glance.clone();
        }
    }
    apply_settings_if_changed(app);
    if app.locked {
        // Values only — widgets list is cached (reload on Customize / settings).
        app.lock_ui.refresh_applets(&app.mpris, &app.power);
    }
}

/// Reload theme / dock pins / wallpaper only when settings.json mtime changes.
fn apply_settings_if_changed(app: &mut App) {
    let base = proteus_shell_core::facts::config_base();
    let path = base.join("proteus/settings.json");
    let mtime = std::fs::metadata(&path).and_then(|m| m.modified()).ok();
    if mtime.is_some() && mtime == app.settings_mtime {
        return;
    }
    app.settings_mtime = mtime;
    let settings = proteus_shell_core::facts::read_settings(&base);
    app.theme = Theme::from_settings(&settings);
    let next_icon = settings
        .get("dockIconSize")
        .and_then(|v| v.as_i64())
        .unwrap_or(48)
        .clamp(32, 72) as f32;
    let next_layout = surfaces::DockLayout::parse(
        settings
            .get("dockLayout")
            .and_then(|v| v.as_str())
            .unwrap_or("center"),
    );
    let next_rounding = settings
        .get("dockRounding")
        .and_then(|v| v.as_i64())
        .unwrap_or(16)
        .clamp(0, 28) as f32;
    let next_enabled = settings
        .get("dockEnabled")
        .and_then(|v| v.as_bool())
        .unwrap_or(true);
    let next_autohide = settings
        .get("dockAutoHide")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    let next_bar_h = surfaces::bar_exclusive(
        settings
            .get("barHeight")
            .and_then(|v| v.as_i64())
            .unwrap_or(38)
            .clamp(28, 48) as u32,
    );
    let next_bar_r = settings
        .get("barRounding")
        .and_then(|v| v.as_i64())
        .unwrap_or(0)
        .clamp(0, 24) as f32;
    let next_bar_ah = settings
        .get("barAutoHide")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    let geom_dirty = (next_icon - app.dock_icon_size).abs() > f32::EPSILON
        || next_layout != app.dock_layout
        || next_enabled != app.dock_enabled
        || next_bar_h != app.bar_height;
    app.dock_icon_size = next_icon;
    if next_layout != app.dock_layout {
        app.dock_geom_dirty = true;
    }
    app.dock_layout = next_layout;
    app.dock_rounding = next_rounding;
    app.dock_enabled = next_enabled;
    app.dock_autohide = next_autohide;
    app.bar_height = next_bar_h;
    app.bar_rounding = next_bar_r;
    app.bar_autohide = next_bar_ah;
    if !next_autohide {
        app.anims.dock_slide.set(1.0);
        app.dock_edge_armed = true;
    }
    if !next_bar_ah {
        app.anims.bar_slide.set(1.0);
        app.bar_edge_armed = true;
    }
    if geom_dirty {
        app.layer_input_applied.retain(|id, _| {
            app.windows
                .get(id)
                .map(|ns| ns.as_str() != layers::DOCK && ns.as_str() != layers::BAR)
                .unwrap_or(true)
        });
        app.dock_exclusive_zone = None;
        app.bar_exclusive_zone = None;
    }
    app.workspace_names = proteus_shell::spaces::parse_workspace_names(&settings);
    let pins = surfaces::dock_pins_from_settings(&settings);
    if pins != app.pins {
        app.pins = pins;
        warm_icons(app);
    }
    refresh_wallpaper_from(app, &settings);
    // Lock strip layout may have changed with settings.
    if app.locked || app.lock_ui.customize {
        app.lock_ui.reload_widgets();
    }
}

/// Re-resolve wallpaper; reload the image handle only when the path changes
/// so the texture uploads once (not per view).
fn refresh_wallpaper_from(app: &mut App, settings: &serde_json::Value) {
    let wp = platform::wallpaper_from_settings(settings);
    if wp == app.wallpaper && app.wallpaper_handle.is_some() == wp.path.is_some() {
        return;
    }
    app.wallpaper_handle = match &wp.path {
        Some(p) => {
            let keep = app
                .wallpaper_handle
                .take()
                .filter(|(cached, _)| cached == p);
            keep.or_else(|| {
                Some((
                    p.clone(),
                    iced::widget::image::Handle::from_path(p),
                ))
            })
        }
        None => None,
    };
    app.wallpaper = wp;
}

fn namespace_for(app: &App, id: window::Id) -> &str {
    app.windows
        .get(&id)
        .map(|s| s.as_str())
        .unwrap_or(app.primary_namespace.as_str())
}

fn boot_extra_layers(app: &mut App) -> Task<Message> {
    if app.single_surface {
        return Task::none();
    }
    let mut tasks = Vec::new();
    for ns in boot_layers_for_face(&app.face) {
        let id = window::Id::unique();
        app.windows.insert(id, (*ns).to_string());
        let settings = new_layer_settings(ns);
        tasks.push(Task::done(Message::NewLayerShell { settings, id }));
    }
    Task::batch(tasks)
}

/// When locked, chrome overlays empty out (QS sessionStartLockPending / sessionLocked).
fn session_chrome_suppressed(app: &App) -> bool {
    app.locked
}

/// Focus the Beacon search input right after the launcher opens.
fn take_beacon_focus(app: &mut App) -> Task<Message> {
    if app.beacon_focus_pending {
        app.beacon_focus_pending = false;
        iced::widget::operation::focus("beacon-input")
    } else {
        Task::none()
    }
}

fn take_spaces_rename_focus(app: &mut App) -> Task<Message> {
    if app.spaces_rename_focus_pending {
        app.spaces_rename_focus_pending = false;
        iced::widget::operation::focus("spaces-rename-input")
    } else {
        Task::none()
    }
}

fn take_lock_password_focus(app: &mut App) -> Task<Message> {
    if app.lock_password_focus_pending {
        app.lock_password_focus_pending = false;
        iced::widget::operation::focus("lock-password-input")
    } else {
        Task::none()
    }
}

fn lock_pin_mode(app: &App) -> bool {
    app.lock_ui.pin_configured && !app.lock_ui.use_password
}

/// Kick grim thumbnails for every visible overview window (off UI thread).
fn capture_spaces_thumbs(app: &mut App) -> Task<Message> {
    if !app.spaces_open || app.locked {
        return Task::none();
    }
    let occupied = proteus_shell::spaces::occupied_space_ids(&app.hypr);
    let visible = proteus_shell::spaces::visible_space_ids(
        app.hypr.active_workspace,
        &occupied,
        app.spaces_floor,
    );
    let mut jobs = Vec::new();
    for t in &app.hypr.toplevels {
        if !visible.contains(&t.workspace) {
            continue;
        }
        jobs.push((t.address.clone(), t.title.clone(), t.workspace));
        if jobs.len() >= 24 {
            break;
        }
    }
    if jobs.is_empty() {
        app.spaces_thumbs.clear();
        return Task::none();
    }
    Task::perform(
        async move {
            tokio::task::spawn_blocking(move || {
                let mut rows = Vec::new();
                for (address, title, workspace) in jobs {
                    let bytes = platform::dock_preview_capture(&address).unwrap_or_default();
                    rows.push((address, title, workspace, bytes));
                }
                rows
            })
            .await
            .unwrap_or_default()
        },
        Message::SpacesThumbsReady,
    )
}

fn take_spaces_thumbs_task(app: &mut App) -> Task<Message> {
    if app.spaces_need_thumbs {
        app.spaces_need_thumbs = false;
        capture_spaces_thumbs(app)
    } else {
        Task::none()
    }
}

/// Kick grim thumbnail capture off the UI thread (dwell preview).
fn capture_dock_preview(app: &mut App, pin: &str) -> Task<Message> {
    if app.locked {
        app.dock_preview = None;
        return Task::none();
    }
    let mut jobs = Vec::new();
    for t in &app.hypr.toplevels {
        if !surfaces::pin_matches(pin, &t.class, &t.title) {
            continue;
        }
        jobs.push((
            t.address.clone(),
            t.title.clone(),
            t.workspace < 0,
        ));
        if jobs.len() >= 4 {
            break;
        }
    }
    if jobs.is_empty() {
        app.dock_preview = None;
        return Task::none();
    }
    let pin = pin.to_string();
    Task::perform(
        async move {
            tokio::task::spawn_blocking(move || {
                let mut rows = Vec::new();
                for (address, title, hidden) in jobs {
                    let bytes = platform::dock_preview_capture(&address).unwrap_or_default();
                    rows.push((address, title, hidden, bytes));
                }
                (pin, rows)
            })
            .await
            .unwrap_or_else(|_| (String::new(), Vec::new()))
        },
        |(pin, rows)| Message::DockPreviewReady { pin, rows },
    )
}

/// Drop finished launch bounces and refresh view strengths (~30fps via AnimTick).
fn dock_bounce_tick(app: &mut App) {
    if app.dock_bounce.is_empty() {
        if !app.dock_bounce_strengths.is_empty() {
            app.dock_bounce_strengths.clear();
        }
        return;
    }
    let timeout = Duration::from_millis(surfaces::DOCK_BOUNCE_TIMEOUT_MS);
    app.dock_bounce.retain(|pin, start| {
        if start.elapsed() >= timeout {
            return false;
        }
        let appeared = app
            .hypr
            .toplevels
            .iter()
            .any(|t| surfaces::pin_matches(pin, &t.class, &t.title));
        !appeared
    });
    app.dock_bounce_strengths = app
        .dock_bounce
        .iter()
        .map(|(pin, start)| {
            let t = start.elapsed().as_secs_f32();
            // Scale + lift share this envelope (view applies Y pad from strength).
            // Stronger Windows-style launch pulse (was ×14 / 2.5s).
            let strength = (t * 16.0).sin().abs();
            (pin.clone(), strength)
        })
        .collect();
}

/// Apply delayed dock leave once the bridge window expires.
fn dock_leave_tick(app: &mut App) {
    let Some(at) = app.dock_leave_at else {
        return;
    };
    if Instant::now() < at {
        return;
    }
    app.dock_leave_at = None;
    app.dock_preview = None;
    app.dock_dwell = None;
    app.dock_edge_armed = false;
    app.anims.dock_hover.animate_to(0.0, 70, Easing::OutCubic);
    app.dock_hover_pin = None;
    if app.dock_autohide {
        app.anims
            .dock_slide
            .animate_to(0.0, 180, Easing::OutCubic);
    }
}

fn cancel_dock_leave(app: &mut App) {
    app.dock_leave_at = None;
}

/// Resolve app icons for dock pins + current Beacon hits (memoized).
fn warm_icons(app: &mut App) {
    let keys: Vec<String> = app
        .pins
        .iter()
        .cloned()
        .chain(
            surfaces::dock_transients(&app.pins, &app.hypr)
                .into_iter(),
        )
        .chain(app.beacon_hits.iter().filter_map(|h| {
            h.rsplit(" · ")
                .next()
                .filter(|tail| tail.ends_with(".desktop"))
                .map(|s| s.to_string())
        }))
        .collect();
    for key in keys {
        app.icon_cache.ensure(&key);
    }
}

/// Auto-hide deadlines — HUD 1500ms, toast 4500ms (QML StatusHud / toast).
fn expire_overlays(app: &mut App) {
    if let Some(d) = app.hud_deadline {
        if d.expired() && !app.hud_kind.is_empty() {
            if let Ok(mut s) = app.chrome.lock() {
                s.hud_kind.clear();
            }
            app.chrome_epoch.fetch_add(1, Ordering::Relaxed);
            app.hud_deadline = None;
            app.hud_kind.clear();
            app.anims.hud.animate_to(0.0, 160, Easing::OutCubic);
        }
    }
    if let Some((id, d)) = app.toast_deadline {
        if d.expired() {
            app.toast_hidden_id = Some(id);
            app.toast_deadline = None;
            app.anims.toast.animate_to(0.0, 140, Easing::InCubic);
        }
    }
}

fn update(app: &mut App, message: Message) -> Task<Message> {
    if std::env::var_os("PROTEUS_SHELL_TRACE").is_some() {
        match &message {
            Message::Tick => eprintln!("[trace] tick"),
            Message::AnimTick => {}
            m => eprintln!("[trace] msg {:?}", std::mem::discriminant(m)),
        }
    }
    match message {
        Message::Tick => {
            app.tick_n = app.tick_n.wrapping_add(1);
            app.lock_ui.clear_expired_cooldown();
            // Lock auth path: keep the UI thread light so password keystrokes
            // aren't delayed into key-repeat bunches (desktop peek + lag).
            if app.locked {
                let epoch = app.chrome_epoch.load(Ordering::Relaxed);
                let epoch_dirty = epoch != app.last_epoch;
                if epoch_dirty {
                    sync_snapshots(app);
                }
                // Settings mtime only — no WM/sensor/applet spam while typing.
                if app.tick_n % 10 == 0 {
                    apply_settings_if_changed(app);
                }
                expire_overlays(app);
                let input_task = if epoch_dirty || app.tick_n < 12 {
                    reconcile_layer_input(app)
                } else {
                    Task::none()
                };
                return Task::batch([input_task, take_lock_password_focus(app)]);
            }
            flush_pending_sliders(app);
            // WM from socket listener — clone only when gen advances.
            let wm_dirty = pull_wm(app);
            // In-process clock ~every 3s (was a `date` subprocess).
            if app.tick_n % 15 == 1 {
                app.clock = surfaces::bar_clock_now();
            }
            // Weather glance ~every 60s (curl Open-Meteo off UI when due).
            if app.tick_n % 120 == 2 {
                app.weather = platform::weather_glance();
            }
            // Hold empty wallpaper → Customize (~450ms).
            if let Some(start) = app.desktop_hold_at {
                if start.elapsed()
                    >= Duration::from_millis(proteus_shell::desktop_widgets::HOLD_MS)
                {
                    app.desktop_hold_at = None;
                    if !app.chrome_snap.widgets_customize {
                        let _ = ctl::handle_request(
                            &app.chrome,
                            &app.chrome_epoch,
                            &ctl::Request {
                                target: "chrome".into(),
                                method: "customizeDesktop".into(),
                                args: vec![],
                            },
                        );
                    }
                }
            }
            let epoch = app.chrome_epoch.load(Ordering::Relaxed);
            let epoch_dirty = epoch != app.last_epoch;
            // Chrome/notifs/tray: on epoch change, else ~every 4s.
            if epoch_dirty || app.tick_n % 20 == 0 {
                sync_snapshots(app);
            }
            // Sensors / settings: ~every 2s.
            if app.tick_n % 10 == 0 {
                refresh_heavy(app);
            }
            // Dock hover dwell → capture preview thumbnails (desktop only).
            let mut preview_task = Task::none();
            dock_leave_tick(app);
            let dock_busy = app.dock_hover_pin.is_some()
                || app.dock_leave_at.is_some()
                || app.dock_dwell.is_some()
                || app.dock_preview.is_some();
            if let Some((pin, start)) = app.dock_dwell.clone() {
                if start.elapsed() >= Duration::from_millis(surfaces::DOCK_PREVIEW_DWELL_MS)
                {
                    app.dock_dwell = None;
                    if app.dock_hover_pin.as_deref() == Some(pin.as_str())
                        && app.dock_leave_at.is_none()
                    {
                        preview_task = capture_dock_preview(app, &pin);
                    }
                }
            }
            expire_overlays(app);
            let spaces_task = take_spaces_thumbs_task(app);
            // Skip input reconcile when idle + stable — applied map already matches.
            // Do not force reconcile every tick while locked (handled above).
            let need_input = dock_busy
                || wm_dirty
                || epoch_dirty
                || app.launcher_open
                || app.cc_open
                || app.hub_open
                || app.spaces_open
                || app.chrome_snap.widgets_customize
                || !app.hud_kind.is_empty()
                || app.toast.is_some()
                || app.tick_n < 12
                || app.tick_n % 25 == 0;
            let input_task = if need_input {
                reconcile_layer_input(app)
            } else {
                Task::none()
            };
            let focus_task = Task::batch([
                take_beacon_focus(app),
                take_spaces_rename_focus(app),
                take_lock_password_focus(app),
            ]);
            Task::batch([preview_task, spaces_task, input_task, focus_task])
        }
        Message::AnimTick => {
            // Frame ticks arrive via a timer subscription while motion runs;
            // the message itself is enough to trigger a redraw.
            flush_pending_sliders(app);
            if !app.locked {
                dock_bounce_tick(app);
                dock_leave_tick(app);
            }
            if !motion_active(app) && app.lock_ui.shake.as_ref().is_some_and(|k| k.done()) {
                app.lock_ui.shake = None;
            }
            Task::none()
        }
        Message::LockKey {
            key,
            text,
            captured,
            repeat,
            window,
        } => {
            if !app.locked || app.chrome_snap.protocol_lock || captured || repeat {
                return Task::none();
            }
            // iced daemon: only the lock layer may consume wake/PIN keys.
            if namespace_for(app, window) != layers::LOCK {
                return Task::none();
            }
            let revealed = app.lock_ui.reveal;
            let pin_mode = lock_pin_mode(app);
            // Password field owns keys once revealed — never double-append.
            if revealed && !pin_mode {
                return Task::none();
            }
            let fingerprint = format!("{key:?}|{text:?}");
            if let Some((prev, at)) = &app.lock_key_debounce {
                if prev == &fingerprint && at.elapsed() < Duration::from_millis(40) {
                    return Task::none();
                }
            }
            app.lock_key_debounce = Some((fingerprint, Instant::now()));
            let task = if matches!(
                key.as_ref(),
                iced::keyboard::Key::Named(iced::keyboard::key::Named::Enter)
            ) {
                if revealed {
                    Task::none()
                } else {
                    handle_surface(app, SurfaceMsg::LockReveal)
                }
            } else if matches!(
                key.as_ref(),
                iced::keyboard::Key::Named(iced::keyboard::key::Named::Backspace)
            ) {
                if pin_mode {
                    handle_surface(app, SurfaceMsg::LockPinBackspace)
                } else {
                    Task::none()
                }
            } else {
                let Some(ch) = text
                    .as_ref()
                    .and_then(|t| t.chars().next())
                    .or_else(|| match key.as_ref() {
                        iced::keyboard::Key::Character(c) => c.chars().next(),
                        _ => None,
                    })
                else {
                    return Task::none();
                };
                if !revealed {
                    handle_surface(app, SurfaceMsg::LockWakeChar(ch))
                } else if pin_mode && ch.is_ascii_digit() {
                    handle_surface(app, SurfaceMsg::LockPinDigit(ch))
                } else {
                    Task::none()
                }
            };
            Task::batch([task, take_lock_password_focus(app)])
        }
        Message::DockPreviewReady { pin, rows } => {
            if app.dock_hover_pin.as_deref() != Some(pin.as_str()) || app.locked {
                return Task::none();
            }
            let wins: Vec<surfaces::DockPreviewWin> = rows
                .into_iter()
                .map(|(address, title, hidden, bytes)| {
                    let handle = if bytes.is_empty() {
                        iced::widget::image::Handle::from_rgba(1, 1, vec![0, 0, 0, 0])
                    } else {
                        iced::widget::image::Handle::from_bytes(bytes)
                    };
                    surfaces::DockPreviewWin {
                        address,
                        title,
                        hidden,
                        handle,
                    }
                })
                .collect();
            app.dock_preview = if wins.is_empty() {
                None
            } else {
                Some((pin, wins))
            };
            reconcile_layer_input(app)
        }
        Message::SpacesThumbsReady(rows) => {
            if !app.spaces_open || app.locked {
                return Task::none();
            }
            app.spaces_thumbs.clear();
            for (address, title, workspace, bytes) in rows {
                let handle = if bytes.is_empty() {
                    iced::widget::image::Handle::from_rgba(1, 1, vec![0, 0, 0, 0])
                } else {
                    iced::widget::image::Handle::from_bytes(bytes)
                };
                app.spaces_thumbs.insert(
                    address.clone(),
                    proteus_shell::spaces::SpaceWinThumb {
                        address,
                        title,
                        workspace,
                        handle,
                    },
                );
            }
            Task::none()
        }
        Message::WindowClosed(id) => {
            app.windows.remove(&id);
            app.layer_input_applied.remove(&id);
            Task::none()
        }
        Message::Surface(m) => {
            // Hover / PIN / nav spam must not re-clone chrome+wm+tray every event.
            // Unlock / LockCustomizeDone still sync (or epoch bump from auto-unlock).
            let skip_sync = matches!(
                m,
                SurfaceMsg::DockHover(_)
                    | SurfaceMsg::DockEdgeEnter
                    | SurfaceMsg::BarEdgeEnter
                    | SurfaceMsg::BarLeave
                    | SurfaceMsg::DockLeave
                    | SurfaceMsg::DockPreviewEnter
                    | SurfaceMsg::DockPreviewFocus(_)
                    | SurfaceMsg::DockPreviewClose(_)
                    | SurfaceMsg::SpacesCycle(_)
                    | SurfaceMsg::SpacesRenameInput(_)
                    | SurfaceMsg::SpacesDragStart(_)
                    | SurfaceMsg::SpacesDragHover(_)
                    | SurfaceMsg::BeaconNav(_)
                    | SurfaceMsg::PinEntry(_)
                    | SurfaceMsg::LockReveal
                    | SurfaceMsg::LockWakeChar(_)
                    | SurfaceMsg::LockPinDigit(_)
                    | SurfaceMsg::LockPinBackspace
                    | SurfaceMsg::LockPinClear
                    | SurfaceMsg::LockUsePassword
                    | SurfaceMsg::LockUsePin
                    | SurfaceMsg::LockCustomizeAdd(_)
                    | SurfaceMsg::LockCustomizeRemove(_)
                    | SurfaceMsg::LockCustomizeMove(_, _)
                    | SurfaceMsg::VolumeSet(_)
                    | SurfaceMsg::BrightnessSet(_)
            );
            // Pointer scrub / cell hover never changes input regions — Tick
            // expands DockPreview after dwell. Skip reconcile on the hot path.
            let skip_reconcile = matches!(
                m,
                SurfaceMsg::DockEdgeEnter
                    | SurfaceMsg::BarEdgeEnter
                    | SurfaceMsg::BarLeave
                    | SurfaceMsg::DockHover(_)
                    | SurfaceMsg::DockLeave
                    | SurfaceMsg::DockPreviewEnter
                    | SurfaceMsg::BeaconNav(_)
                    | SurfaceMsg::VolumeSet(_)
                    | SurfaceMsg::BrightnessSet(_)
                    | SurfaceMsg::SpacesRenameInput(_)
                    | SurfaceMsg::SpacesDragHover(_)
                    | SurfaceMsg::PinEntry(_)
                    | SurfaceMsg::LockWakeChar(_)
                    | SurfaceMsg::LockPinDigit(_)
                    | SurfaceMsg::LockPinBackspace
                    | SurfaceMsg::LockPinClear
                    | SurfaceMsg::LockReveal
                    | SurfaceMsg::LockUsePassword
                    | SurfaceMsg::LockUsePin
            );
            let epoch_before = app.chrome_epoch.load(Ordering::Relaxed);
            let task = handle_surface(app, m);
            let epoch_after = app.chrome_epoch.load(Ordering::Relaxed);
            if !skip_sync || epoch_after != epoch_before {
                sync_snapshots(app);
            }
            let spaces_task = take_spaces_thumbs_task(app);
            let input_task = if skip_reconcile {
                Task::none()
            } else {
                reconcile_layer_input(app)
            };
            let focus_task = Task::batch([
                take_beacon_focus(app),
                take_spaces_rename_focus(app),
                take_lock_password_focus(app),
            ]);
            Task::batch([task, spaces_task, input_task, focus_task])
        }
        Message::AnchorChange { .. }
        | Message::SetInputRegion { .. }
        | Message::AnchorSizeChange { .. }
        | Message::LayerChange { .. }
        | Message::MarginChange { .. }
        | Message::SizeChange { .. }
        | Message::ExclusiveZoneChange { .. }
        | Message::KeyboardInteractivityChange { .. }
        | Message::VirtualKeyboardPressed { .. }
        | Message::NewLayerShell { .. }
        | Message::NewBaseWindow { .. }
        | Message::NewPopUp { .. }
        | Message::NewMenu { .. }
        | Message::NewInputPanel { .. }
        | Message::RemoveWindow(_)
        | Message::ForgetLastOutput => Task::none(),
    }
}

fn handle_surface(app: &mut App, m: SurfaceMsg) -> Task<Message> {
    match m {
        SurfaceMsg::ToggleLauncher => {
            let _ = ctl::handle_request(
                &app.chrome,
                &app.chrome_epoch,
                &ctl::Request {
                    target: "chrome".into(),
                    method: "launcher".into(),
                    args: vec![],
                },
            );
        }
        SurfaceMsg::ToggleControlCenter => {
            let _ = ctl::handle_request(
                &app.chrome,
                &app.chrome_epoch,
                &ctl::Request {
                    target: "chrome".into(),
                    method: "controlCenter".into(),
                    args: vec![],
                },
            );
        }
        SurfaceMsg::ToggleCalendar => {
            let _ = ctl::handle_request(
                &app.chrome,
                &app.chrome_epoch,
                &ctl::Request {
                    target: "chrome".into(),
                    method: "calendar".into(),
                    args: vec![],
                },
            );
        }
        SurfaceMsg::ToggleWeather => {
            let _ = ctl::handle_request(
                &app.chrome,
                &app.chrome_epoch,
                &ctl::Request {
                    target: "chrome".into(),
                    method: "weather".into(),
                    args: vec![],
                },
            );
            app.weather = platform::weather_glance();
        }
        SurfaceMsg::ToggleNotifications => {
            let _ = ctl::handle_request(
                &app.chrome,
                &app.chrome_epoch,
                &ctl::Request {
                    target: "chrome".into(),
                    method: "notifications".into(),
                    args: vec![],
                },
            );
        }
        SurfaceMsg::CenterTab(i) => {
            if let Ok(mut s) = app.chrome.lock() {
                if i == 0 {
                    s.calendar_open = true;
                    s.notifications_open = false;
                } else {
                    s.notifications_open = true;
                    s.calendar_open = false;
                }
                s.weather_open = false;
                s.control_center_open = false;
                s.launcher_open = false;
            }
            app.chrome_epoch.fetch_add(1, Ordering::Relaxed);
        }
        SurfaceMsg::CloseCenterHub => {
            if let Ok(mut s) = app.chrome.lock() {
                s.calendar_open = false;
                s.notifications_open = false;
                s.weather_open = false;
            }
            app.chrome_epoch.fetch_add(1, Ordering::Relaxed);
        }
        SurfaceMsg::DesktopPress => {
            if !app.chrome_snap.widgets_customize {
                app.desktop_hold_at = Some(Instant::now());
            }
        }
        SurfaceMsg::DesktopRelease => {
            app.desktop_hold_at = None;
        }
        SurfaceMsg::CustomizeDesktop => {
            let _ = ctl::handle_request(
                &app.chrome,
                &app.chrome_epoch,
                &ctl::Request {
                    target: "chrome".into(),
                    method: "customizeDesktop".into(),
                    args: vec![],
                },
            );
        }
        SurfaceMsg::BeaconInput(q) => {
            if let Ok(mut s) = app.chrome.lock() {
                s.beacon_query = q.clone();
            }
            app.chrome_epoch.fetch_add(1, Ordering::Relaxed);
            app.beacon_hits = proteus_shell::beacon::filter_beacon_hits(&q, 24, &app.hypr.toplevels);
            app.beacon_selected = 0;
            warm_icons(app);
        }
        SurfaceMsg::BeaconLaunch(id) => {
            proteus_shell::beacon::launch_hit(&id);
            if let Ok(mut s) = app.chrome.lock() {
                s.launcher_open = false;
            }
            app.chrome_epoch.fetch_add(1, Ordering::Relaxed);
        }
        SurfaceMsg::BeaconNav(delta) => {
            let count = app.beacon_hits.len().min(12);
            if count > 0 {
                let cur = app.beacon_selected as i32;
                app.beacon_selected =
                    (cur + delta).rem_euclid(count as i32) as usize;
            }
        }
        SurfaceMsg::BeaconSubmit => {
            if let Some(hit) = app.beacon_hits.get(app.beacon_selected).cloned() {
                return handle_surface(app, SurfaceMsg::BeaconLaunch(hit));
            }
        }
        SurfaceMsg::BeaconEscape => {
            let clear_query = !app.beacon_query.is_empty();
            if let Ok(mut s) = app.chrome.lock() {
                if clear_query {
                    s.beacon_query.clear();
                } else {
                    s.launcher_open = false;
                }
            }
            app.chrome_epoch.fetch_add(1, Ordering::Relaxed);
            if clear_query {
                app.beacon_hits = default_beacon_hits();
                app.beacon_selected = 0;
            }
        }
        SurfaceMsg::ToggleSpaces => {
            let _ = ctl::handle_request(
                &app.chrome,
                &app.chrome_epoch,
                &ctl::Request {
                    target: "chrome".into(),
                    method: "spaces".into(),
                    args: vec![],
                },
            );
        }
        SurfaceMsg::SpacesEscape => {
            if let Ok(mut c) = app.chrome.lock() {
                if c.spaces_open {
                    c.spaces_open = false;
                    app.chrome_epoch.fetch_add(1, Ordering::Relaxed);
                }
            }
        }
        SurfaceMsg::SpacesCycle(dir) => {
            if dir == 0 {
                return Task::none();
            }
            let occupied = proteus_shell::spaces::occupied_space_ids(&app.hypr);
            let visible = proteus_shell::spaces::visible_space_ids(
                app.hypr.active_workspace,
                &occupied,
                app.spaces_floor,
            );
            if let Some(next) =
                proteus_shell::spaces::cycle_visible(&visible, app.hypr.active_workspace, dir)
            {
                let _ = wm_ipc::dispatch(&format!("workspace {next}"));
            }
        }
        SurfaceMsg::SpacesSelect(id) => {
            if app.spaces_drag.is_some() {
                return Task::none();
            }
            let _ = wm_ipc::dispatch(&format!("workspace {id}"));
            if let Ok(mut c) = app.chrome.lock() {
                c.spaces_open = false;
            }
            app.chrome_epoch.fetch_add(1, Ordering::Relaxed);
        }
        SurfaceMsg::SpacesAdd => {
            let occupied = proteus_shell::spaces::occupied_space_ids(&app.hypr);
            let visible = proteus_shell::spaces::visible_space_ids(
                app.hypr.active_workspace,
                &occupied,
                app.spaces_floor,
            );
            let end = visible.last().copied().unwrap_or(1);
            if end < proteus_shell::spaces::SPACE_MAX {
                app.spaces_floor = (end + 1).max(app.spaces_floor);
            }
        }
        SurfaceMsg::SpacesRenameStart(id) => {
            app.spaces_rename_id = Some(id);
            app.spaces_rename_buf = proteus_shell::spaces::space_name(&app.workspace_names, id);
            if app.spaces_rename_buf.starts_with("Space ") {
                app.spaces_rename_buf.clear();
            }
            app.spaces_rename_focus_pending = true;
        }
        SurfaceMsg::SpacesRenameInput(s) => {
            app.spaces_rename_buf = s;
        }
        SurfaceMsg::SpacesRenameCommit => {
            if let Some(id) = app.spaces_rename_id.take() {
                let names = proteus_shell::spaces::names_with_rename(
                    &app.workspace_names,
                    id,
                    &app.spaces_rename_buf,
                );
                let base = proteus_shell_core::facts::config_base();
                let patch = serde_json::json!({ "workspaceNames": names });
                if proteus_shell_core::facts::write_settings(&base, &patch).is_ok() {
                    app.workspace_names = names;
                    app.settings_mtime = None; // force reload next heavy tick
                }
            }
            app.spaces_rename_buf.clear();
        }
        SurfaceMsg::SpacesDragStart(addr) => {
            app.spaces_drag = Some(addr);
            app.spaces_drag_target = None;
        }
        SurfaceMsg::SpacesDragHover(id) => {
            if app.spaces_drag.is_some() {
                app.spaces_drag_target = Some(id);
            }
        }
        SurfaceMsg::SpacesDrop(id) => {
            if let Some(addr) = app.spaces_drag.take() {
                let src = app
                    .hypr
                    .toplevels
                    .iter()
                    .find(|t| t.address == addr)
                    .map(|t| t.workspace);
                if src != Some(id) {
                    let _ = wm_ipc::move_window_to_workspace(&addr, id);
                    app.spaces_need_thumbs = true;
                }
            }
            app.spaces_drag_target = None;
        }
        SurfaceMsg::SpacesThumbRelease(addr) => {
            let drag = app.spaces_drag.clone();
            if drag.as_deref() != Some(addr.as_str()) {
                return Task::none();
            }
            let target = app.spaces_drag_target;
            let src = app
                .hypr
                .toplevels
                .iter()
                .find(|t| t.address == addr)
                .map(|t| t.workspace);
            app.spaces_drag = None;
            app.spaces_drag_target = None;
            if let Some(dest) = target.filter(|d| Some(*d) != src) {
                let _ = wm_ipc::move_window_to_workspace(&addr, dest);
                app.spaces_need_thumbs = true;
                return Task::none();
            }
            // Focus window and leave overview.
            let _ = wm_ipc::dock_focus_or_restore(&addr, &app.hypr);
            if let Ok(mut c) = app.chrome.lock() {
                c.spaces_open = false;
            }
            app.chrome_epoch.fetch_add(1, Ordering::Relaxed);
        }
        SurfaceMsg::Workspace(id) => {
            let _ = wm_ipc::dispatch(&format!("workspace {id}"));
        }
        SurfaceMsg::DockLaunch(id) => {
            if surfaces::is_beacon_pin(&id) {
                return handle_surface(app, SurfaceMsg::ToggleLauncher);
            }
            match wm_ipc::dock_activate(&id, &app.hypr) {
                wm_ipc::DockAction::Launch => {
                    app.dock_bounce.insert(id.clone(), Instant::now());
                    launch_open(&id);
                }
                _ => {}
            }
        }
        SurfaceMsg::DockHover(pin) => {
            cancel_dock_leave(app);
            app.dock_edge_armed = true;
            app.anims
                .dock_slide
                .animate_to(1.0, 180, Easing::OutCubic);
            let same = app.dock_hover_pin.as_deref() == Some(pin.as_str());
            app.dock_hover_pin = Some(pin.clone());
            app.anims.dock_hover.animate_to(1.0, 70, Easing::OutCubic);
            // Dwell before grim capture (immediate tip only until then).
            // Beacon pin has no windows — tip only. Skip reset when re-entering
            // the same pin (bridge cancel / cell jitter).
            if !same {
                app.dock_preview = None;
                if surfaces::is_beacon_pin(&pin) {
                    app.dock_dwell = None;
                } else {
                    app.dock_dwell = Some((pin, Instant::now()));
                }
            } else if surfaces::is_beacon_pin(&pin) {
                app.dock_dwell = None;
            } else if app.dock_dwell.is_none() && app.dock_preview.is_none() {
                app.dock_dwell = Some((pin, Instant::now()));
            }
        }
        SurfaceMsg::DockEdgeEnter => {
            cancel_dock_leave(app);
            app.dock_edge_armed = true;
            app.anims
                .dock_slide
                .animate_to(1.0, 180, Easing::OutCubic);
        }
        SurfaceMsg::BarEdgeEnter => {
            app.bar_edge_armed = true;
            app.anims.bar_slide.animate_to(1.0, 180, Easing::OutCubic);
        }
        SurfaceMsg::BarLeave => {
            if app.bar_autohide {
                app.bar_edge_armed = false;
                app.anims.bar_slide.animate_to(0.0, 180, Easing::OutCubic);
            }
        }
        SurfaceMsg::DockLeave => {
            // Bridge: allow the pointer to reach the preview card / next cell.
            app.dock_leave_at = Some(
                Instant::now() + Duration::from_millis(surfaces::DOCK_LEAVE_DELAY_MS),
            );
        }
        SurfaceMsg::DockPreviewEnter => {
            cancel_dock_leave(app);
        }
        SurfaceMsg::DockPreviewFocus(addr) => {
            let _ = wm_ipc::dock_focus_or_restore(&addr, &app.hypr);
            app.dock_preview = None;
            app.dock_dwell = None;
            app.dock_leave_at = None;
            app.anims.dock_hover.animate_to(0.0, 70, Easing::OutCubic);
        }
        SurfaceMsg::DockPreviewClose(addr) => {
            cancel_dock_leave(app);
            let _ = wm_ipc::window_close_address(&addr);
            if let Some((pin, mut wins)) = app.dock_preview.take() {
                wins.retain(|w| w.address != addr);
                if wins.is_empty() {
                    app.dock_preview = None;
                } else {
                    app.dock_preview = Some((pin, wins));
                }
            }
        }
        SurfaceMsg::HudDismiss => {
            let _ = ctl::handle_request(
                &app.chrome,
                &app.chrome_epoch,
                &ctl::Request {
                    target: "hud".into(),
                    method: "hide".into(),
                    args: vec![],
                },
            );
        }
        SurfaceMsg::ToastDismiss(id) => {
            if let Ok(mut n) = app.notifs.lock() {
                n.items.retain(|x| x.id != id);
            }
        }
        SurfaceMsg::PrivacyAllow | SurfaceMsg::PrivacyDeny => {
            if let Ok(mut s) = app.chrome.lock() {
                s.privacy_ask = None;
            }
            app.chrome_epoch.fetch_add(1, Ordering::Relaxed);
        }
        SurfaceMsg::Lock => {
            let _ = ctl::handle_request(
                &app.chrome,
                &app.chrome_epoch,
                &ctl::Request {
                    target: "lock".into(),
                    method: "lock".into(),
                    args: vec![],
                },
            );
        }
        SurfaceMsg::Unlock => {
            app.lock_ui.clear_expired_cooldown();
            if app.lock_ui.cooldown_secs() > 0 {
                let left = app.lock_ui.cooldown_secs().max(1);
                app.lock_ui.status = format!("Cooldown · {left}s");
                return Task::none();
            }
            match platform::try_unlock(&app.lock_ui.pin) {
                Ok(()) => {
                    let _ = ctl::handle_request(
                        &app.chrome,
                        &app.chrome_epoch,
                        &ctl::Request {
                            target: "lock".into(),
                            method: "unlock".into(),
                            args: vec![],
                        },
                    );
                    if let Ok(mut s) = app.chrome.lock() {
                        s.session_start_lock_pending = false;
                    }
                    app.lock_ui.on_success();
                }
                Err(e) => {
                    eprintln!("proteus-shell: unlock failed: {e}");
                    app.lock_ui.on_fail();
                }
            }
        }
        SurfaceMsg::PinEntry(p) => {
            if !app.lock_ui.reveal {
                app.lock_ui.reveal = true;
            }
            app.lock_ui.pin = p;
        }
        SurfaceMsg::LockReveal => {
            app.lock_ui.reveal = true;
            if !lock_pin_mode(app) {
                app.lock_password_focus_pending = true;
            }
        }
        SurfaceMsg::LockWakeChar(ch) => {
            // Idle lock: keep the wake keystroke (password seed or PIN digit).
            app.lock_ui.reveal = true;
            if lock_pin_mode(app) {
                if app.lock_ui.push_digit(ch) {
                    return handle_surface(app, SurfaceMsg::Unlock);
                }
            } else if !ch.is_control() {
                app.lock_ui.pin.push(ch);
                app.lock_password_focus_pending = true;
            } else {
                app.lock_password_focus_pending = true;
            }
        }
        SurfaceMsg::LockPinDigit(ch) => {
            if app.lock_ui.push_digit(ch) {
                return handle_surface(app, SurfaceMsg::Unlock);
            }
        }
        SurfaceMsg::LockPinBackspace => {
            app.lock_ui.pin.pop();
        }
        SurfaceMsg::LockPinClear => {
            app.lock_ui.pin.clear();
        }
        SurfaceMsg::LockUsePassword => {
            app.lock_ui.use_password = true;
            app.lock_ui.pin.clear();
            app.lock_ui.reveal = true;
            app.lock_password_focus_pending = true;
        }
        SurfaceMsg::LockUsePin => {
            app.lock_ui.use_password = false;
            app.lock_ui.pin.clear();
            app.lock_ui.reveal = true;
        }
        SurfaceMsg::LockCustomizeAdd(kind) => {
            app.lock_ui.customize_add(&kind);
        }
        SurfaceMsg::LockCustomizeRemove(id) => {
            app.lock_ui.customize_remove(&id);
        }
        SurfaceMsg::LockCustomizeMove(id, delta) => {
            app.lock_ui.customize_move(&id, delta);
        }
        SurfaceMsg::LockCustomizeDone => {
            let _ = ctl::handle_request(
                &app.chrome,
                &app.chrome_epoch,
                &ctl::Request {
                    target: "lock".into(),
                    method: "customize".into(),
                    args: vec![],
                },
            );
            app.lock_ui.reload_widgets();
        }
        SurfaceMsg::WidgetAdd(kind) => {
            app.desktop_widgets.add(&kind);
            app.widget_kinds = app.desktop_widgets.kinds();
            if let Ok(mut s) = app.chrome.lock() {
                s.widgets = app.widget_kinds.clone();
                if !s.widgets_customize {
                    s.widgets_customize = true;
                }
            }
            app.chrome_epoch.fetch_add(1, Ordering::Relaxed);
            let _ = app.desktop_widgets.persist();
        }
        SurfaceMsg::WidgetRemove(id) => {
            app.desktop_widgets.remove(&id);
            app.widget_kinds = app.desktop_widgets.kinds();
            if let Ok(mut s) = app.chrome.lock() {
                s.widgets = app.widget_kinds.clone();
            }
            app.chrome_epoch.fetch_add(1, Ordering::Relaxed);
            let _ = app.desktop_widgets.persist();
        }
        SurfaceMsg::WidgetSelect(id) => {
            app.desktop_widgets.select(&id);
        }
        SurfaceMsg::WidgetDragStart(id) => {
            app.desktop_widgets.start_drag(&id);
        }
        SurfaceMsg::WidgetDrag(x, y) => {
            let snap = app.chrome_snap.widgets_snap;
            app.desktop_widgets.drag_to(x, y, snap, (1920.0, 1080.0));
        }
        SurfaceMsg::WidgetDragEnd => {
            app.desktop_widgets.end_drag();
            let _ = app.desktop_widgets.persist();
        }
        SurfaceMsg::WidgetNudge(dx, dy) => {
            let snap = app.chrome_snap.widgets_snap;
            app.desktop_widgets.nudge(dx, dy, snap);
            let _ = app.desktop_widgets.persist();
        }
        SurfaceMsg::WidgetSnapToggle => {
            let _ = ctl::handle_request(
                &app.chrome,
                &app.chrome_epoch,
                &ctl::Request {
                    target: "widgets".into(),
                    method: "setSnap".into(),
                    args: vec![],
                },
            );
        }
        SurfaceMsg::WidgetCustomizeDone => {
            let _ = app.desktop_widgets.persist();
            if let Ok(mut s) = app.chrome.lock() {
                s.widgets_customize = false;
            }
            app.chrome_epoch.fetch_add(1, Ordering::Relaxed);
        }
        SurfaceMsg::WidgetActivate(kind) => match kind.as_str() {
            "Clock" | "Calendar" | "WorldClock" => {
                return handle_surface(app, SurfaceMsg::ToggleCalendar);
            }
            "Weather" => {
                return handle_surface(app, SurfaceMsg::ToggleWeather);
            }
            "Battery" => {
                return handle_surface(
                    app,
                    SurfaceMsg::OpenSettingsPage("power".into()),
                );
            }
            "System" => {
                return handle_surface(app, SurfaceMsg::ToggleSpaces);
            }
            _ => {}
        },
        SurfaceMsg::CcRefresh => {
            app.wifi_hits = platform::wifi_list_thin();
            app.bt_hits = platform::bt_list_thin();
            app.wifi_radio_on = platform::wifi_radio_enabled();
            app.bt_radio_on = platform::bt_radio_enabled();
        }
        SurfaceMsg::WifiRadioToggle => {
            match platform::wifi_radio_toggle() {
                Ok(on) => {
                    app.wifi_radio_on = on;
                    app.wifi_err.clear();
                    if on {
                        app.wifi_hits = platform::wifi_list_thin();
                    }
                }
                Err(e) => app.wifi_err = e,
            }
        }
        SurfaceMsg::BtRadioToggle => {
            match platform::bt_radio_toggle() {
                Ok(on) => {
                    app.bt_radio_on = on;
                    app.bt_err.clear();
                    if on {
                        app.bt_hits = platform::bt_list_thin();
                    }
                }
                Err(e) => app.bt_err = e,
            }
        }
        SurfaceMsg::AppearanceMode(i) => {
            let mode = if i == 1 { "light" } else { "dark" };
            if platform::set_chrome_mode(mode).is_ok() {
                let base = proteus_shell_core::facts::config_base();
                app.theme =
                    Theme::from_settings(&proteus_shell_core::facts::read_settings(&base));
            }
        }
        SurfaceMsg::Screenshot(kind) => {
            if let Err(e) = platform::screenshot(&kind) {
                eprintln!("proteus-shell: screenshot: {e}");
            }
        }
        SurfaceMsg::OpenSettingsPage(page) => {
            let _ = std::process::Command::new("proteus-open")
                .args(["settings", &format!("--page={page}")])
                .spawn();
        }
        SurfaceMsg::NotifClearAll => {
            if let Ok(mut n) = app.notifs.lock() {
                n.items.clear();
            }
        }
        SurfaceMsg::FaceSelect(i) => {
            let tab = i.min(4);
            let _ = ctl::handle_request(
                &app.chrome,
                &app.chrome_epoch,
                &ctl::Request {
                    target: "chrome".into(),
                    method: "consoleTab".into(),
                    args: vec![tab.to_string()],
                },
            );
            if tab == 3 {
                return handle_surface(app, SurfaceMsg::ToggleLauncher);
            }
            if tab == 4 {
                let _ = std::process::Command::new("proteus-open")
                    .arg("settings")
                    .spawn();
            }
        }
        SurfaceMsg::Refresh => {
            refresh_heavy(app);
            if app.face == "console" {
                app.console_games = platform::console_games_list();
                app.console_media_path = platform::console_media_path();
                app.console_apps = platform::console_apps_thin(32);
            }
            if app.face == "host" {
                app.host_glance = platform::host_glance();
            }
        }
        SurfaceMsg::BrightnessSet(pct) => {
            // Optimistic UI; pactl/brightnessctl flush off-thread (debounced).
            app.brightness = Some(pct);
            app.pending_brightness = Some(pct);
            app.slider_flush_at =
                Some(Instant::now() + Duration::from_millis(40));
            let _ = ctl::handle_request(
                &app.chrome,
                &app.chrome_epoch,
                &ctl::Request {
                    target: "hud".into(),
                    method: "brightness".into(),
                    args: vec![pct.to_string()],
                },
            );
        }
        SurfaceMsg::BrightnessStep(delta) => {
            let cur = app.brightness.or_else(platform::brightness_get).unwrap_or(50);
            let next = (cur as i16 + delta as i16).clamp(0, 100) as u8;
            let _ = platform::brightness_set(next);
            app.brightness = Some(next);
            let _ = ctl::handle_request(
                &app.chrome,
                &app.chrome_epoch,
                &ctl::Request {
                    target: "hud".into(),
                    method: "brightness".into(),
                    args: vec![next.to_string()],
                },
            );
        }
        SurfaceMsg::OpenSettings => {
            let _ = std::process::Command::new("proteus-open")
                .arg("settings")
                .spawn();
        }
        SurfaceMsg::OpenPrivacy => {
            let _ = std::process::Command::new("proteus-open")
                .args(["settings", "--page=privacy-activity"])
                .spawn();
        }
        SurfaceMsg::PowerProfile(idx) => {
            let _ = platform::power_set_profile_index(idx);
            app.power = platform::power_status();
        }
        SurfaceMsg::ToggleFloating => {
            let _ = wm_ipc::dispatch("togglefloating");
        }
        SurfaceMsg::VolumeMute => {
            let _ = ctl::handle_request(
                &app.chrome,
                &app.chrome_epoch,
                &ctl::Request {
                    target: "hud".into(),
                    method: "volumeMute".into(),
                    args: vec![],
                },
            );
            app.volume = platform::volume_get().or(app.volume);
        }
        SurfaceMsg::VolumeStep(delta) => {
            if delta != 0 {
                if let Some(v) = platform::volume_step(delta) {
                    app.volume = Some(v);
                    let _ = ctl::handle_request(
                        &app.chrome,
                        &app.chrome_epoch,
                        &ctl::Request {
                            target: "hud".into(),
                            method: "volume".into(),
                            args: vec![v.to_string()],
                        },
                    );
                }
            }
        }
        SurfaceMsg::VolumeSet(pct) => {
            app.volume = Some(pct);
            app.pending_volume = Some(pct);
            app.slider_flush_at =
                Some(Instant::now() + Duration::from_millis(40));
        }
        SurfaceMsg::MediaPlayPause(bus) => {
            if let Err(e) = platform::mpris_control(&bus, "PlayPause") {
                eprintln!("proteus-shell: {e}");
            }
            app.mpris = platform::mpris_players();
        }
        SurfaceMsg::MediaNext(bus) => {
            if let Err(e) = platform::mpris_control(&bus, "Next") {
                eprintln!("proteus-shell: {e}");
            }
            app.mpris = platform::mpris_players();
        }
        SurfaceMsg::MediaPrev(bus) => {
            if let Err(e) = platform::mpris_control(&bus, "Previous") {
                eprintln!("proteus-shell: {e}");
            }
            app.mpris = platform::mpris_players();
        }
        SurfaceMsg::NotifDismiss(id) => {
            if let Ok(mut n) = app.notifs.lock() {
                n.items.retain(|x| x.id != id);
            }
        }
        SurfaceMsg::LaunchGame(key) => {
            if let Err(e) = platform::console_launch_game(&key) {
                eprintln!("proteus-shell: launch game: {e}");
            }
        }
        SurfaceMsg::HostTab(i) => {
            app.host_tab = i.min(2);
        }
        SurfaceMsg::ToggleDnd => {
            let next = !app.dnd;
            if platform::set_notifications_dnd(next).is_ok() {
                app.dnd = next;
                if let Ok(mut n) = app.notifs.lock() {
                    n.dnd = next;
                }
            }
        }
        SurfaceMsg::WifiConnect(ssid) => {
            match platform::wifi_connect(&ssid) {
                Ok(()) => {
                    app.wifi_err.clear();
                    app.wifi_hits = platform::wifi_list_thin();
                }
                Err(e) => app.wifi_err = e,
            }
        }
        SurfaceMsg::BtConnect(mac) => {
            match platform::bt_connect(&mac) {
                Ok(()) => {
                    app.bt_err.clear();
                    app.bt_hits = platform::bt_list_thin();
                }
                Err(e) => app.bt_err = e,
            }
        }
        SurfaceMsg::OpenMediaPath => {
            let path = app.console_media_path.clone();
            if let Err(e) = platform::open_path(&path) {
                eprintln!("proteus-shell: open media: {e}");
            }
        }
        SurfaceMsg::LaunchConsoleApp(id) => {
            let hit = if id.contains(".desktop") {
                id
            } else {
                format!("{id}.desktop")
            };
            proteus_shell::beacon::launch_hit(&hit);
        }
        SurfaceMsg::ToggleFocus => {
            let next = if app.focus_on { "off" } else { "indefinite" };
            if platform::set_focus_mode(next).is_ok() {
                app.focus_on = platform::focus_active();
            }
        }
        SurfaceMsg::FocusProfile(id) => {
            if platform::set_focus_active_profile(&id).is_ok() {
                app.focus_active_id = id;
                app.focus_profiles = platform::focus_profiles();
            }
        }
        SurfaceMsg::OpenConsoleSettingsPage(page) => {
            let _ = std::process::Command::new("proteus-open")
                .arg("settings")
                .arg(format!("--page={page}"))
                .spawn()
                .or_else(|_| {
                    std::process::Command::new("proteus-open")
                        .arg("settings")
                        .spawn()
                });
        }
        SurfaceMsg::OpenWorkloads => {
            let tab = match app.host_tab {
                1 => "shares",
                2 => "apps",
                _ => "workloads",
            };
            let _ = std::process::Command::new("proteus-workloads")
                .arg(tab)
                .spawn()
                .or_else(|_| {
                    std::process::Command::new("proteus-open")
                        .arg("workloads")
                        .spawn()
                });
        }
    }
    Task::none()
}

fn launch_open(id: &str) {
    proteus_shell::beacon::launch_hit(id);
}

fn view_real(app: &App, id: window::Id) -> Element<'_, Message> {
    let ns = namespace_for(app, id);
    let suppressed = session_chrome_suppressed(app);
    let body = match ns {
        n if n == layers::LOCK => {
            if app.locked && !app.chrome_snap.protocol_lock {
                surfaces::lock_view(
                    &app.theme,
                    &app.lock_ui,
                    &app.wallpaper,
                    app.wallpaper_handle.as_ref().map(|(_, h)| h),
                )
            } else {
                surfaces::empty_layer(&app.theme)
            }
        }
        n if n == layers::BAR => {
            if suppressed {
                surfaces::empty_layer(&app.theme)
            } else {
                let bar = surfaces::bar_view(
                    &app.theme,
                    &app.chrome_snap,
                    &app.hypr,
                    &app.power,
                    &app.tray_items,
                    &app.privacy_dots,
                    app.dnd,
                    &app.clock,
                    &app.weather,
                    app.notif_items.len(),
                    app.bar_rounding,
                );
                let slide = app.anims.bar_slide.value();
                let hide = (1.0 - slide) * app.bar_height as f32;
                iced::widget::mouse_area(
                    container(column![
                        Space::new().height(Length::Fixed(hide)),
                        bar,
                    ])
                    .width(Length::Fill)
                    .height(Length::Fill)
                    .align_y(Alignment::Start),
                )
                .on_enter(SurfaceMsg::BarEdgeEnter)
                .on_exit(SurfaceMsg::BarLeave)
                .into()
            }
        }
        n if n == layers::DOCK => {
            if suppressed || !app.dock_enabled {
                surfaces::empty_layer(&app.theme)
            } else {
                let slide = if app.dock_autohide {
                    let v = app.anims.dock_slide.value();
                    if !app.dock_edge_armed && v < 0.05 {
                        // Hot-edge peek while fully stowed.
                        surfaces::DOCK_PEEK_SLIDE
                    } else {
                        v
                    }
                } else {
                    1.0
                };
                surfaces::dock_view(
                    &app.theme,
                    &app.pins,
                    &app.hypr,
                    app.dock_preview.as_ref(),
                    &app.icon_cache,
                    app.dock_hover_pin.as_deref(),
                    app.anims.dock_hover.value(),
                    slide,
                    app.dock_icon_size,
                    app.dock_layout,
                    app.dock_rounding,
                    &app.dock_bounce_strengths,
                    app.launcher_open,
                )
            }
        }
        n if n == layers::SPACES => {
            if suppressed || !app.spaces_open {
                surfaces::empty_layer(&app.theme)
            } else {
                proteus_shell::spaces::overview_view(
                    &app.theme,
                    &app.hypr,
                    &app.workspace_names,
                    app.spaces_floor,
                    &app.spaces_thumbs,
                    app.spaces_rename_id,
                    &app.spaces_rename_buf,
                    app.spaces_drag.as_deref(),
                    app.spaces_drag_target,
                    app.anims.spaces.value(),
                )
            }
        }
        n if n == layers::LAUNCHER => {
            if suppressed || !app.launcher_open {
                surfaces::empty_layer(&app.theme)
            } else {
                surfaces::beacon_view(
                    &app.theme,
                    &app.chrome_snap,
                    &app.beacon_hits,
                    app.beacon_selected,
                    &app.icon_cache,
                    app.anims.beacon.value(),
                )
            }
        }
        n if n == layers::CONTROL_CENTER => {
            if suppressed {
                surfaces::empty_layer(&app.theme)
            } else if app.cc_open {
                surfaces::control_center_view(
                    &app.theme,
                    &app.chrome_snap,
                    &app.power,
                    app.brightness,
                    app.volume,
                    &app.mpris,
                    app.dnd,
                    &app.wifi_hits,
                    &app.bt_hits,
                    app.wifi_radio_on,
                    app.bt_radio_on,
                    &app.wifi_err,
                    &app.bt_err,
                    app.focus_on,
                    &app.focus_profiles,
                    &app.focus_active_id,
                    app.anims.cc.value(),
                )
            } else if app.chrome_snap.calendar_open || app.chrome_snap.notifications_open {
                surfaces::center_hub_view(
                    &app.theme,
                    &app.chrome_snap,
                    &app.notif_items,
                    app.anims.cc.value(),
                )
            } else if app.chrome_snap.weather_open {
                surfaces::weather_glance_view(
                    &app.theme,
                    &app.weather,
                    app.anims.cc.value(),
                )
            } else {
                surfaces::empty_layer(&app.theme)
            }
        }
        n if n == layers::HUD => {
            if suppressed || app.hud_kind.is_empty() || app.cc_open {
                surfaces::empty_layer(&app.theme)
            } else {
                surfaces::hud_view(&app.theme, &app.chrome_snap, app.anims.hud.value())
            }
        }
        n if n == layers::BG => surfaces::wallpaper_view(
            &app.theme,
            &app.wallpaper,
            app.wallpaper_handle.as_ref().map(|(_, h)| h),
        ),
        n if n == layers::DESKTOP_WIDGETS => {
            if suppressed {
                surfaces::empty_layer(&app.theme)
            } else if app.chrome_snap.widgets_customize
                || !app.desktop_widgets.items.is_empty()
            {
                surfaces::desktop_widgets_view(
                    &app.theme,
                    &app.desktop_widgets,
                    &app.widget_gallery,
                    app.chrome_snap.widgets_customize,
                    app.chrome_snap.widgets_snap,
                    &app.clock,
                    &app.weather,
                    &app.power,
                )
            } else {
                surfaces::empty_layer(&app.theme)
            }
        }
        n if n == layers::TOAST => {
            if suppressed || app.cc_open {
                surfaces::empty_layer(&app.theme)
            } else {
                match &app.toast {
                    Some(t) => {
                        let fade = app.anims.toast.value();
                        let hidden =
                            app.toast_hidden_id == Some(t.id) && fade <= 0.01;
                        if hidden {
                            surfaces::empty_layer(&app.theme)
                        } else {
                            surfaces::toast_view(&app.theme, t, fade)
                        }
                    }
                    None => surfaces::empty_layer(&app.theme),
                }
            }
        }
        n if n == layers::PRIVACY_ASK => match &app.privacy_ask {
            Some(cat) if !suppressed => surfaces::privacy_ask_view(&app.theme, cat),
            _ => surfaces::empty_layer(&app.theme),
        },
        _ if app.face == "console" && !suppressed => {
            faces::console_face_view(
                &app.theme,
                &app.chrome_snap,
                &app.console_games,
                &app.console_media_path,
                &app.console_apps,
            )
        }
        _ if app.face == "host" && !suppressed => {
            faces::host_face_view(&app.theme, app.host_tab, &app.host_glance)
        }
        _ => surfaces::empty_layer(&app.theme),
    };
    container(body.map(Message::Surface))
        .width(Length::Fill)
        .height(Length::Fill)
        .into()
}

fn style(_app: &App, theme: &iced::Theme) -> iced::theme::Style {
    iced::theme::Style {
        background_color: Color::TRANSPARENT,
        text_color: theme.palette().text,
    }
}

fn iced_theme(app: &App, _id: window::Id) -> iced::Theme {
    match app.theme.mode {
        ChromeMode::Light => iced::Theme::Light,
        ChromeMode::Dark => iced::Theme::Dark,
    }
}

fn load_dock_pins() -> Vec<String> {
    let base = proteus_shell_core::facts::config_base();
    surfaces::dock_pins_from_settings(&proteus_shell_core::facts::read_settings(&base))
}

fn default_beacon_hits() -> Vec<String> {
    proteus_shell::beacon::filter_beacon_hits("", 24, &[])
}

fn dock_layer_geom(layout: surfaces::DockLayout) -> (Anchor, (u32, u32)) {
    match layout {
        surfaces::DockLayout::Left => (
            Anchor::Left | Anchor::Top | Anchor::Bottom,
            (surfaces::DOCK_LAYER_H, 0),
        ),
        surfaces::DockLayout::Right => (
            Anchor::Right | Anchor::Top | Anchor::Bottom,
            (surfaces::DOCK_LAYER_H, 0),
        ),
        _ => (
            Anchor::Bottom | Anchor::Left | Anchor::Right,
            (0, surfaces::DOCK_LAYER_H),
        ),
    }
}

fn layer_settings(namespace: &str) -> LayerShellSettings {
    // Layer-shell protocol: width 0 requires Left+Right anchor, height 0 requires
    // Top+Bottom. Violations are a compositor protocol error that kills the client
    // at boot (khronos-egl panic) — guarded by layer_geometry_tests below.
    let full = Anchor::Top | Anchor::Bottom | Anchor::Left | Anchor::Right;
    let (anchor, size) = match namespace {
        n if n == layers::BAR => (
            Anchor::Top | Anchor::Left | Anchor::Right,
            Some((0, surfaces::BAR_EXCLUSIVE)),
        ),
        // Dock surface hosts shelf + preview band; layout Fact re-anchors later.
        n if n == layers::DOCK => {
            let (a, s) = dock_layer_geom(surfaces::DockLayout::Center);
            (a, Some(s))
        }
        // HUD / toast are top-right chips (CHROME.md), not full-screen overlays.
        n if n == layers::HUD => (Anchor::Top | Anchor::Right, Some((320, 56))),
        n if n == layers::TOAST => (Anchor::Top | Anchor::Right, Some((360, 132))),
        _ => (full, None),
    };
    let layer = match namespace {
        n if n == layers::BG => Layer::Background,
        n if n == layers::DESKTOP_WIDGETS => Layer::Bottom,
        // Dock stays Top (above wallpaper) with a shelf exclusive_zone so
        // windows lay out above it — Bottom put it under widgets / invisible.
        n if n == layers::BAR || n == layers::DOCK => Layer::Top,
        _ => Layer::Overlay,
    };
    let margin = match namespace {
        n if n == layers::HUD => (8, 12, 0, 12),
        // Clear the taller menu bar (BAR_EXCLUSIVE + small gap).
        n if n == layers::TOAST => (surfaces::BAR_EXCLUSIVE as i32 + 14, 12, 0, 12),
        _ => (0, 0, 0, 0),
    };
    LayerShellSettings {
        anchor,
        layer,
        // Bar/dock exclusive zones reserve window work-area. Full-bleed
        // surfaces (wallpaper + lock) must be DontCare (-1) so smithay sizes
        // them to the full output — Neutral (0) after exclusives gets a
        // clipped rect (black under dock / desktop wallpaper bleeding under lock).
        exclusive_zone: match namespace {
            n if n == layers::BAR => surfaces::BAR_EXCLUSIVE as i32,
            // Boot default = rest 48; settings reload pushes ExclusiveZoneChange.
            n if n == layers::DOCK => {
                surfaces::dock_strip_h(surfaces::DOCK_ICON_REST) as i32
            }
            n if n == layers::BG || n == layers::LOCK => -1,
            _ => 0,
        },
        size,
        margin,
        // Only the lock starts with a keyboard grab (session-start lock pending).
        // Launcher/CC get Exclusive dynamically when opened (reconcile_layer_input);
        // a permanently-Exclusive overlay would starve app windows of keyboard.
        keyboard_interactivity: if namespace == layers::LOCK {
            KeyboardInteractivity::Exclusive
        } else {
            KeyboardInteractivity::None
        },
        start_mode: StartMode::Active,
        ..Default::default()
    }
}

/// Pointer input shape for a layer surface.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum InputShape {
    /// Click-through everywhere.
    Empty,
    /// Whole surface interactive.
    Full,
    /// Only the bottom dock strip is interactive (preview area click-through).
    DockStrip,
    /// Dock strip + preview band interactive (dwell card open).
    DockPreview,
}

/// Desired pointer/keyboard interactivity per layer given current chrome state.
/// Idle full-screen overlays must be click-through or they swallow app input.
fn overlay_desired(app: &App, ns: &str) -> (InputShape, KeyboardInteractivity) {
    use KeyboardInteractivity as Ki;
    match ns {
        n if n == layers::LAUNCHER => {
            if app.launcher_open {
                (InputShape::Full, Ki::Exclusive)
            } else {
                (InputShape::Empty, Ki::None)
            }
        }
        n if n == layers::CONTROL_CENTER => {
            if app.cc_open || app.hub_open {
                (InputShape::Full, Ki::Exclusive)
            } else {
                (InputShape::Empty, Ki::None)
            }
        }
        n if n == layers::SPACES => {
            if app.spaces_open {
                (InputShape::Full, Ki::Exclusive)
            } else {
                (InputShape::Empty, Ki::None)
            }
        }
        n if n == layers::LOCK => {
            let active = app.locked && !app.chrome_snap.protocol_lock;
            if active {
                (InputShape::Full, Ki::Exclusive)
            } else {
                (InputShape::Empty, Ki::None)
            }
        }
        n if n == layers::PRIVACY_ASK => (
            if app.privacy_ask.is_some() {
                InputShape::Full
            } else {
                InputShape::Empty
            },
            Ki::None,
        ),
        n if n == layers::DESKTOP_WIDGETS => (
            if app.chrome_snap.widgets_customize || !app.desktop_widgets.items.is_empty() {
                InputShape::Full
            } else {
                InputShape::Empty
            },
            if app.chrome_snap.widgets_customize {
                Ki::OnDemand
            } else {
                Ki::None
            },
        ),
        n if n == layers::TOAST => (
            // Auto-hidden toasts are click-through (still in the CC list).
            match &app.toast {
                Some(t) if app.toast_hidden_id != Some(t.id) => InputShape::Full,
                _ => InputShape::Empty,
            },
            Ki::None,
        ),
        n if n == layers::HUD => (
            if app.hud_kind.is_empty() {
                InputShape::Empty
            } else {
                InputShape::Full
            },
            Ki::None,
        ),
        n if n == layers::DOCK => {
            if !app.dock_enabled {
                (InputShape::Empty, Ki::None)
            } else if app.dock_preview.is_some() && app.anims.dock_hover.value() > 0.05 {
                (InputShape::DockPreview, Ki::None)
            } else {
                (InputShape::DockStrip, Ki::None)
            }
        }
        // Bar / wallpaper stay pointer-interactive, no keyboard grab.
        _ => (InputShape::Full, Ki::None),
    }
}

fn shape_code(shape: InputShape) -> u8 {
    match shape {
        InputShape::Empty => 0,
        InputShape::Full => 1,
        InputShape::DockStrip => 2,
        InputShape::DockPreview => 3,
    }
}

fn ki_code(ki: KeyboardInteractivity) -> u8 {
    match ki {
        KeyboardInteractivity::None => 0,
        KeyboardInteractivity::OnDemand => 1,
        KeyboardInteractivity::Exclusive => 2,
        _ => 3,
    }
}

/// Push input-region + keyboard-interactivity changes for layers whose desired
/// state drifted (open/close, lock, toast). Early ticks force a re-apply since
/// surfaces map asynchronously after NewLayerShell.
fn reconcile_layer_input(app: &mut App) -> Task<Message> {
    if app.tick_n == 10 {
        app.layer_input_applied.clear();
    }
    let mut tasks = Vec::new();
    let entries: Vec<(window::Id, String)> = app
        .windows
        .iter()
        .map(|(id, ns)| (*id, ns.clone()))
        .collect();
    let dock_shown = app.dock_enabled
        && (!app.dock_autohide || app.anims.dock_slide.value() > 0.05 || app.dock_edge_armed);
    let want_zone = if !app.dock_enabled {
        0
    } else if app.dock_autohide && !dock_shown {
        1 // hot-edge peek reservation
    } else {
        surfaces::dock_strip_h(app.dock_icon_size) as i32
    };
    let want_bar_zone = if app.bar_autohide && app.anims.bar_slide.value() < 0.05 {
        1
    } else {
        app.bar_height as i32
    };
    if app.dock_geom_dirty {
        for (id, ns) in &entries {
            if ns.as_str() == layers::DOCK {
                let (anchor, size) = dock_layer_geom(app.dock_layout);
                tasks.push(Task::done(Message::AnchorSizeChange {
                    id: *id,
                    anchor,
                    size,
                }));
            }
        }
        app.dock_geom_dirty = false;
        app.layer_input_applied.retain(|id, _| {
            app.windows
                .get(id)
                .map(|ns| ns.as_str() != layers::DOCK)
                .unwrap_or(true)
        });
    }
    if app.dock_exclusive_zone != Some(want_zone) {
        for (id, ns) in &entries {
            if ns.as_str() == layers::DOCK {
                tasks.push(Task::done(Message::ExclusiveZoneChange {
                    id: *id,
                    zone_size: want_zone,
                }));
            }
        }
        app.dock_exclusive_zone = Some(want_zone);
    }
    if app.bar_exclusive_zone != Some(want_bar_zone) {
        for (id, ns) in &entries {
            if ns.as_str() == layers::BAR {
                tasks.push(Task::done(Message::ExclusiveZoneChange {
                    id: *id,
                    zone_size: want_bar_zone,
                }));
                tasks.push(Task::done(Message::SizeChange {
                    id: *id,
                    size: (0, app.bar_height),
                }));
            }
        }
        app.bar_exclusive_zone = Some(want_bar_zone);
    }
    for (id, ns) in entries {
        let (shape, ki) = overlay_desired(app, &ns);
        let want = (shape_code(shape), ki_code(ki));
        if app.layer_input_applied.get(&id) == Some(&want) {
            continue;
        }
        app.layer_input_applied.insert(id, want);
        let strip_h = surfaces::dock_strip_h(app.dock_icon_size);
        let vertical = app.dock_layout.vertical();
        let callback = ActionCallback::new(move |region| match shape {
            InputShape::Empty => {}
            InputShape::Full => region.add(0, 0, i32::MAX, i32::MAX),
            InputShape::DockStrip if vertical => {
                region.add(0, 0, strip_h as i32, i32::MAX);
            }
            InputShape::DockStrip => region.add(
                0,
                (surfaces::DOCK_LAYER_H - strip_h) as i32,
                i32::MAX,
                strip_h as i32,
            ),
            InputShape::DockPreview => region.add(0, 0, i32::MAX, i32::MAX),
        });
        tasks.push(Task::done(Message::SetInputRegion { id, callback }));
        tasks.push(Task::done(Message::KeyboardInteractivityChange {
            id,
            keyboard_interactivity: ki,
        }));
    }
    if tasks.is_empty() {
        Task::none()
    } else {
        Task::batch(tasks)
    }
}

fn new_layer_settings(namespace: &str) -> NewLayerShellSettings {
    let ls = layer_settings(namespace);
    NewLayerShellSettings {
        size: ls.size,
        layer: ls.layer,
        anchor: ls.anchor,
        exclusive_zone: Some(ls.exclusive_zone),
        margin: Some(ls.margin),
        keyboard_interactivity: ls.keyboard_interactivity,
        output_option: OutputOption::Active,
        events_transparent: false,
        namespace: Some(namespace.to_string()),
    }
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
    let face = args
        .iter()
        .position(|a| a == "--face")
        .and_then(|i| args.get(i + 1))
        .map(|s| s.as_str())
        .unwrap_or("desktop")
        .to_string();

    let chrome: SharedChrome = Arc::new(Mutex::new(ChromeState {
        face: face.clone(),
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
        "proteus-shell: engine=owned face={face} compositor={} session_lock={} (req={}) socket={} audio_mix={}",
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
    let hypr_boot = Arc::clone(&wm_shared);
    let face_boot = face.clone();
    let primary_boot = primary.clone();
    let ns_name = primary.clone();

    // All subprocess polling lives on this worker; the UI thread only copies
    // its snapshot (a hung child process must never freeze the shell).
    let heavy_shared = Arc::new(HeavyShared {
        snap: Mutex::new(HeavySnapshot::default()),
        cc_open: AtomicBool::new(false),
    });
    spawn_heavy_worker(face.clone(), Arc::clone(&heavy_shared));
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
                    face: face_boot.clone(),
                    ..Default::default()
                },
                hypr: WmState::default(),
                wm_gen: 0,
                wm_shared: Arc::clone(&hypr_boot),
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
                focus_profiles: Vec::new(),
                focus_active_id: String::new(),
                face: face_boot.clone(),
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
                spaces_thumbs: HashMap::new(),
                spaces_rename_id: None,
                spaces_rename_buf: String::new(),
                spaces_drag: None,
                spaces_drag_target: None,
                spaces_need_thumbs: false,
                spaces_rename_focus_pending: false,
                lock_password_focus_pending: false,
                lock_key_debounce: None,
                locked: false,
                hud_kind: String::new(),
                hud_value: 0.0,
                privacy_ask: None,
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
    .subscription(|app: &App| {
        // Idle desktop: 500ms. Busy chrome: 200ms. Locked auth: 1s (cooldown UI
        // only) — faster ticks redraw every layer and bunch key-repeat.
        let tick_ms = if app.locked && !motion_active(app) {
            1000
        } else if app.dock_hover_pin.is_some()
            || app.dock_preview.is_some()
            || app.cc_open
            || app.launcher_open
            || app.spaces_open
            || app.slider_flush_at.is_some()
            || motion_active(app)
        {
            200
        } else {
            500
        };
        let mut subs = vec![
            iced::window::close_events().map(Message::WindowClosed),
            iced::time::every(Duration::from_millis(tick_ms)).map(|_| Message::Tick),
        ];
        // ~30fps frame ticks only while motion is in flight (magnify / CC /
        // Beacon / shake). Full multi-layer redraw at 60fps was a main lag source.
        if motion_active(app) {
            subs.push(iced::time::every(Duration::from_millis(33)).map(|_| Message::AnimTick));
        }
        // Beacon keyboard nav — ↑↓ move, Esc clears then closes (QML parity).
        // Enter is handled by the input's on_submit.
        if app.launcher_open && !app.locked {
            subs.push(iced::event::listen_with(|event, status, _id| {
                if matches!(status, iced::event::Status::Captured) {
                    return None;
                }
                let iced::Event::Keyboard(iced::keyboard::Event::KeyPressed {
                    key,
                    repeat,
                    ..
                }) = event
                else {
                    return None;
                };
                if repeat {
                    return None;
                }
                match key.as_ref() {
                    iced::keyboard::Key::Named(iced::keyboard::key::Named::ArrowDown) => {
                        Some(Message::Surface(SurfaceMsg::BeaconNav(1)))
                    }
                    iced::keyboard::Key::Named(iced::keyboard::key::Named::ArrowUp) => {
                        Some(Message::Surface(SurfaceMsg::BeaconNav(-1)))
                    }
                    iced::keyboard::Key::Named(iced::keyboard::key::Named::Escape) => {
                        Some(Message::Surface(SurfaceMsg::BeaconEscape))
                    }
                    _ => None,
                }
            }));
        }
        if app.spaces_open && !app.locked {
            subs.push(iced::event::listen_with(|event, _status, _id| {
                if let iced::Event::Keyboard(iced::keyboard::Event::KeyPressed {
                    key, ..
                }) = event
                {
                    match key.as_ref() {
                        iced::keyboard::Key::Named(iced::keyboard::key::Named::Escape) => {
                            Some(Message::Surface(SurfaceMsg::SpacesEscape))
                        }
                        _ => None,
                    }
                } else {
                    None
                }
            }));
        }
        // Lock keyboard wake / PIN digits. Filtering happens in Message::LockKey
        // (listen_with cannot capture reveal/pin_mode). Password text_input uses
        // Captured status so those keys are ignored here — no double-insert.
        // Window id is required: daemon Interaction events are per-surface.
        if app.locked && !app.chrome_snap.protocol_lock {
            subs.push(iced::event::listen_with(|event, status, id| {
                let iced::Event::Keyboard(iced::keyboard::Event::KeyPressed {
                    key,
                    text,
                    repeat,
                    ..
                }) = event
                else {
                    return None;
                };
                Some(Message::LockKey {
                    key,
                    text: text.map(|s| s.to_string()),
                    captured: matches!(status, iced::event::Status::Captured),
                    repeat,
                    window: id,
                })
            }));
        }
        iced::Subscription::batch(subs)
    })
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
