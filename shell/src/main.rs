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
use std::time::Duration;

use iced::widget::container;
use iced::window;
use iced::{Color, Element, Length, Task};
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
use proteus_shell::hypr::{self, HyprState};
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
#[derive(Default)]
struct Anims {
    /// Control Center open progress 0→1 (200ms OutCubic).
    cc: AnimatedValue,
    /// Beacon open progress 0→1 (180ms OutCubic).
    beacon: AnimatedValue,
    /// HUD visibility 0→1 (160ms OutCubic fade).
    hud: AnimatedValue,
    /// Toast visibility 0→1 (160ms OutCubic fade).
    toast: AnimatedValue,
    /// Dock hover magnify strength 0→1 (70ms OutCubic).
    dock_mag: AnimatedValue,
}

impl Anims {
    fn active(&self) -> bool {
        self.cc.animating()
            || self.beacon.animating()
            || self.hud.animating()
            || self.toast.animating()
            || self.dock_mag.animating()
    }
}

/// Any chrome motion in flight (kit anims + lock shake).
fn motion_active(app: &App) -> bool {
    app.anims.active() || app.lock_ui.shake_active()
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
    hypr: HyprState,
    hypr_shared: hypr::SharedHypr,
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
    dock_preview: Option<(String, iced::widget::image::Handle)>,
    single_surface: bool,
    tick_n: u64,
    launcher_open: bool,
    cc_open: bool,
    locked: bool,
    hud_kind: String,
    hud_value: f32,
    privacy_ask: Option<String>,
    beacon_query: String,
    toast: Option<Notification>,
    notif_items: Vec<Notification>,
    widget_kinds: Vec<String>,
    widget_gallery: Vec<String>,
    anims: Anims,
    icon_cache: proteus_shell::icons::IconCache,
    /// Hovered dock pin (magnify + preview target).
    dock_hover_pin: Option<String>,
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
    /// Fast (~60fps) redraw tick, alive only while animations run.
    AnimTick,
    WindowClosed(window::Id),
}

fn sync_snapshots(app: &mut App) {
    let was_launcher = app.launcher_open;
    let was_cc = app.cc_open;
    let had_hud = !app.hud_kind.is_empty();
    let prev_hud = app.hud_kind.clone();
    let prev_hud_value = app.hud_value;
    let prev_toast_id = app.toast.as_ref().map(|t| t.id);
    if let Ok(c) = app.chrome.lock() {
        app.launcher_open = c.launcher_open;
        app.cc_open = c.control_center_open;
        app.locked = c.locked || c.session_start_lock_pending;
        app.hud_kind = c.hud_kind.clone();
        app.hud_value = c.hud_value;
        app.privacy_ask = c.privacy_ask.clone();
        app.beacon_query = c.beacon_query.clone();
        app.widget_kinds = c.widgets.clone();
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
    if let Ok(h) = app.hypr_shared.lock() {
        app.hypr = h.clone();
    }
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
    if app.cc_open != was_cc {
        app.anims
            .cc
            .animate_to(if app.cc_open { 1.0 } else { 0.0 }, 200, Easing::OutCubic);
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

fn refresh_heavy(app: &mut App) {
    // Prefer socket2-shared state; fall back to poll.
    if let Ok(h) = app.hypr_shared.lock() {
        if !h.workspaces.is_empty() {
            app.hypr = h.clone();
        } else {
            drop(h);
            app.hypr = hypr::refresh_state();
        }
    } else {
        app.hypr = hypr::refresh_state();
    }
    // Copy the worker-gathered snapshot. Never block: skip if the worker
    // holds the lock right now — next tick picks it up.
    app.heavy.cc_open.store(app.cc_open, Ordering::Relaxed);
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
    let base = proteus_shell_core::facts::config_base();
    app.theme = Theme::from_settings(&proteus_shell_core::facts::read_settings(&base));
    refresh_wallpaper(app);
    if app.locked {
        app.lock_ui.refresh_applets(&app.mpris, &app.power);
    }
}

/// Re-resolve wallpaper; reload the image handle only when the path changes
/// so the texture uploads once (not per view).
fn refresh_wallpaper(app: &mut App) {
    let wp = platform::wallpaper_state();
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

/// Resolve app icons for dock pins + current Beacon hits (memoized).
fn warm_icons(app: &mut App) {
    let keys: Vec<String> = app
        .pins
        .iter()
        .cloned()
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
            if app.tick_n % 5 == 1 {
                app.clock = surfaces::bar_clock_now();
            }
            let epoch = app.chrome_epoch.load(Ordering::Relaxed);
            if epoch != app.last_epoch || app.tick_n % 8 == 0 {
                sync_snapshots(app);
            }
            if app.tick_n % 8 == 0 {
                refresh_heavy(app);
            }
            expire_overlays(app);
            let input_task = reconcile_layer_input(app);
            let focus_task = take_beacon_focus(app);
            Task::batch([input_task, focus_task])
        }
        Message::AnimTick => {
            // Frame ticks arrive via a timer subscription while motion runs;
            // the message itself is enough to trigger a redraw.
            if !motion_active(app) && app.lock_ui.shake.as_ref().is_some_and(|k| k.done()) {
                app.lock_ui.shake = None;
            }
            Task::none()
        }
        Message::WindowClosed(id) => {
            app.windows.remove(&id);
            app.layer_input_applied.remove(&id);
            Task::none()
        }
        Message::Surface(m) => {
            let task = handle_surface(app, m);
            sync_snapshots(app);
            let input_task = reconcile_layer_input(app);
            let focus_task = take_beacon_focus(app);
            Task::batch([task, input_task, focus_task])
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
        SurfaceMsg::Workspace(id) => {
            let _ = hypr::dispatch(&format!("workspace {id}"));
        }
        SurfaceMsg::DockLaunch(id) => {
            match hypr::dock_activate(&id, &app.hypr) {
                hypr::DockAction::Launch => launch_open(&id),
                _ => {}
            }
        }
        SurfaceMsg::DockHover(pin) => {
            app.dock_hover_pin = Some(pin.clone());
            app.anims.dock_mag.animate_to(1.0, 70, Easing::OutCubic);
            // No capture while locked (privacy); solid degrade when grim absent.
            if !app.locked {
                let addr = app
                    .hypr
                    .toplevels
                    .iter()
                    .find(|t| surfaces::pin_matches(&pin, &t.class, &t.title))
                    .map(|t| t.address.clone());
                if let Some(addr) = addr {
                    if let Some(bytes) = platform::dock_preview_capture(&addr) {
                        app.dock_preview =
                            Some((pin, iced::widget::image::Handle::from_bytes(bytes)));
                        return Task::none();
                    }
                }
            }
            app.dock_preview = None;
        }
        SurfaceMsg::DockLeave => {
            app.dock_preview = None;
            // Keep the pin while the magnify eases out; view gates the tip on mag.
            app.anims.dock_mag.animate_to(0.0, 70, Easing::OutCubic);
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
        }
        SurfaceMsg::WidgetAdd(kind) => {
            let _ = ctl::handle_request(
                &app.chrome,
                &app.chrome_epoch,
                &ctl::Request {
                    target: "widgets".into(),
                    method: "add".into(),
                    args: vec![kind],
                },
            );
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
            let _ = platform::brightness_set(pct);
            app.brightness = platform::brightness_get();
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
        SurfaceMsg::WindowClose => {
            let _ = hypr::window_close();
        }
        SurfaceMsg::WindowMinimize => {
            let _ = hypr::window_minimize();
        }
        SurfaceMsg::WindowMaximize => {
            let _ = hypr::window_maximize();
        }
        SurfaceMsg::PowerProfile(idx) => {
            let _ = platform::power_set_profile_index(idx);
            app.power = platform::power_status();
        }
        SurfaceMsg::VolumeStep(delta) => {
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
        SurfaceMsg::VolumeSet(pct) => {
            let _ = platform::volume_set(pct);
            app.volume = Some(pct);
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
            let _ = platform::wifi_connect(&ssid);
            app.wifi_hits = platform::wifi_list_thin();
        }
        SurfaceMsg::BtConnect(mac) => {
            let _ = platform::bt_connect(&mac);
            app.bt_hits = platform::bt_list_thin();
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
                surfaces::lock_view(&app.theme, &app.lock_ui)
            } else {
                surfaces::empty_layer(&app.theme)
            }
        }
        n if n == layers::BAR => {
            if suppressed {
                surfaces::empty_layer(&app.theme)
            } else {
                surfaces::bar_view(
                    &app.theme,
                    &app.chrome_snap,
                    &app.hypr,
                    &app.power,
                    &app.tray_items,
                    &app.privacy_dots,
                    app.dnd,
                    &app.clock,
                )
            }
        }
        n if n == layers::DOCK => {
            if suppressed {
                surfaces::empty_layer(&app.theme)
            } else {
                surfaces::dock_view(
                    &app.theme,
                    &app.pins,
                    &app.hypr,
                    app.dock_preview
                        .as_ref()
                        .map(|(pin, h)| (pin.as_str(), h)),
                    &app.icon_cache,
                    app.dock_hover_pin.as_deref(),
                    app.anims.dock_mag.value(),
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
            if suppressed || !app.cc_open {
                surfaces::empty_layer(&app.theme)
            } else {
                surfaces::control_center_view(
                    &app.theme,
                    &app.chrome_snap,
                    &app.power,
                    app.brightness,
                    app.volume,
                    &app.mpris,
                    &app.notif_items,
                    app.dnd,
                    &app.wifi_hits,
                    &app.bt_hits,
                    app.focus_on,
                    &app.focus_profiles,
                    &app.focus_active_id,
                    app.anims.cc.value(),
                )
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
            } else if app.chrome_snap.widgets_customize {
                // Customize mode — full catalog picker.
                surfaces::widgets_view(&app.theme, &app.widget_gallery)
            } else if !app.widget_kinds.is_empty() {
                surfaces::widgets_view(&app.theme, &app.widget_kinds)
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
    let settings = proteus_shell_core::facts::read_settings(&base);
    let raw = settings
        .get("dockPins")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .trim();
    if raw.is_empty() {
        return vec![
            "proteus-settings".into(),
            "proteus-workloads".into(),
            "com.mitchellh.ghostty".into(),
            "org.gnome.Nautilus".into(),
        ];
    }
    if raw == "-" {
        return vec!["proteus-settings".into()];
    }
    raw.split(',')
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .collect()
}

fn default_beacon_hits() -> Vec<String> {
    proteus_shell::beacon::filter_beacon_hits("", 24, &[])
}

fn layer_settings(namespace: &str) -> LayerShellSettings {
    // Layer-shell protocol: width 0 requires Left+Right anchor, height 0 requires
    // Top+Bottom. Violations are a compositor protocol error that kills the client
    // at boot (khronos-egl panic) — guarded by layer_geometry_tests below.
    let full = Anchor::Top | Anchor::Bottom | Anchor::Left | Anchor::Right;
    let (anchor, size) = match namespace {
        // QML barHeight parity (34).
        n if n == layers::BAR => (Anchor::Top | Anchor::Left | Anchor::Right, Some((0, 34))),
        // Dock surface is taller than the shelf: the strip above hosts hover
        // previews and is excluded from the input region (BottomStrip shape).
        n if n == layers::DOCK => (
            Anchor::Bottom | Anchor::Left | Anchor::Right,
            Some((0, surfaces::DOCK_LAYER_H)),
        ),
        // HUD / toast are top-right chips (CHROME.md), not full-screen overlays.
        n if n == layers::HUD => (Anchor::Top | Anchor::Right, Some((320, 56))),
        n if n == layers::TOAST => (Anchor::Top | Anchor::Right, Some((360, 132))),
        _ => (full, None),
    };
    let layer = match namespace {
        n if n == layers::BG => Layer::Background,
        n if n == layers::DESKTOP_WIDGETS => Layer::Bottom,
        n if n == layers::BAR || n == layers::DOCK => Layer::Top,
        _ => Layer::Overlay,
    };
    let margin = match namespace {
        n if n == layers::HUD => (8, 12, 0, 12),
        n if n == layers::TOAST => (52, 12, 0, 12),
        _ => (0, 0, 0, 0),
    };
    LayerShellSettings {
        anchor,
        layer,
        exclusive_zone: if namespace == layers::BAR { 34 } else { 0 },
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
            if app.cc_open {
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
            if app.chrome_snap.widgets_customize {
                InputShape::Full
            } else {
                InputShape::Empty
            },
            Ki::None,
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
        n if n == layers::DOCK => (InputShape::DockStrip, Ki::None),
        // Bar / wallpaper stay pointer-interactive, no keyboard grab.
        _ => (InputShape::Full, Ki::None),
    }
}

fn shape_code(shape: InputShape) -> u8 {
    match shape {
        InputShape::Empty => 0,
        InputShape::Full => 1,
        InputShape::DockStrip => 2,
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
    for (id, ns) in entries {
        let (shape, ki) = overlay_desired(app, &ns);
        let want = (shape_code(shape), ki_code(ki));
        if app.layer_input_applied.get(&id) == Some(&want) {
            continue;
        }
        app.layer_input_applied.insert(id, want);
        let callback = ActionCallback::new(move |region| match shape {
            InputShape::Empty => {}
            InputShape::Full => region.add(0, 0, i32::MAX, i32::MAX),
            InputShape::DockStrip => region.add(
                0,
                (surfaces::DOCK_LAYER_H - surfaces::DOCK_STRIP_H) as i32,
                i32::MAX,
                surfaces::DOCK_STRIP_H as i32,
            ),
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
    let hypr_shared: hypr::SharedHypr = Arc::new(Mutex::new(hypr::refresh_state()));
    hypr::spawn_socket2_listener(Arc::clone(&hypr_shared));
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
    let hypr_boot = Arc::clone(&hypr_shared);
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
            let widget_seed = chrome_boot
                .lock()
                .map(|c| c.widgets.clone())
                .unwrap_or_default();
            let pins = load_dock_pins();
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
                hypr: HyprState::default(),
                hypr_shared: Arc::clone(&hypr_boot),
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
                anims: Anims::default(),
                icon_cache: proteus_shell::icons::IconCache::default(),
                dock_hover_pin: None,
                beacon_selected: 0,
                hud_deadline: None,
                toast_deadline: None,
                toast_hidden_id: None,
                clock: surfaces::bar_clock_now(),
                beacon_focus_pending: false,
                heavy: Arc::clone(&heavy_boot),
            };
            sync_snapshots(&mut app);
            refresh_wallpaper(&mut app);
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
        let mut subs = vec![
            iced::window::close_events().map(Message::WindowClosed),
            // Housekeeping cadence — snapshot sync, clock, overlay expiry.
            iced::time::every(Duration::from_millis(200)).map(|_| Message::Tick),
        ];
        // ~60fps frame ticks only while motion is in flight.
        if motion_active(app) {
            subs.push(iced::time::every(Duration::from_millis(16)).map(|_| Message::AnimTick));
        }
        // Beacon keyboard nav — ↑↓ move, Esc clears then closes (QML parity).
        // Enter is handled by the input's on_submit.
        if app.launcher_open && !app.locked {
            subs.push(iced::event::listen_with(|event, _status, _id| {
                if let iced::Event::Keyboard(iced::keyboard::Event::KeyPressed {
                    key, ..
                }) = event
                {
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
                } else {
                    None
                }
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
}
