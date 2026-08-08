//! App state, messages, heavy-refresh worker.

use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant, SystemTime};

use iced::window;
use iced_layershell::to_layer_message;

use proteus_shell::anim::{self, AnimatedValue};
use proteus_shell::ctl::{ChromeState, SharedChrome};
use proteus_shell::faces::Face;
use proteus_shell::lock_ui::LockUiState;
use proteus_shell::platform::{
    self, ConsoleGame, MprisPlayer, Notification, PowerStatus, PrivacyDots, SharedNotifs,
    SharedTray,
};
use proteus_shell::surfaces::{self, Message as SurfaceMsg};
use proteus_shell::wm_ipc::{self, WmState};
use proteus_ui::theme::Theme;

/// Bumped by ctl on chrome mutations so the UI can poll faster than heavy sensors.
pub(crate) type ChromeEpoch = Arc<AtomicU64>;

/// Chrome motion state — QML parity timings (see anim.rs header).
pub(crate) struct Anims {
    /// Control Center open progress 0→1 (200ms OutCubic).
    pub(crate) cc: AnimatedValue,
    /// Beacon open progress 0→1 (180ms OutCubic).
    pub(crate) beacon: AnimatedValue,
    /// HUD visibility 0→1 (160ms OutCubic fade).
    pub(crate) hud: AnimatedValue,
    /// Toast visibility 0→1 (160ms OutCubic fade).
    pub(crate) toast: AnimatedValue,
    /// Dock per-icon hover scale engagement 0→1 (70ms OutCubic).
    pub(crate) dock_hover: AnimatedValue,
    /// Dock autohide reveal 0→1 (180ms OutCubic); 1 = fully shown.
    pub(crate) dock_slide: AnimatedValue,
    /// Menu bar autohide reveal 0→1 (180ms OutCubic).
    pub(crate) bar_slide: AnimatedValue,
    /// Spaces overview open fade 0→1 (180ms OutCubic).
    pub(crate) spaces: AnimatedValue,
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
pub(crate) fn motion_active(app: &App) -> bool {
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
pub(crate) struct HeavySnapshot {
    pub(crate) power: PowerStatus,
    pub(crate) privacy: PrivacyDots,
    pub(crate) dnd: bool,
    pub(crate) volume: Option<u8>,
    pub(crate) brightness: Option<u8>,
    pub(crate) mpris: Vec<MprisPlayer>,
    pub(crate) wifi: Vec<platform::WifiHit>,
    pub(crate) bt: Vec<platform::BtHit>,
    pub(crate) focus_on: bool,
    pub(crate) focus_profiles: Vec<platform::FocusProfile>,
    pub(crate) focus_active_id: String,
    pub(crate) console_games: Vec<ConsoleGame>,
    pub(crate) console_media_path: String,
    pub(crate) console_apps: Vec<(String, String)>,
    pub(crate) host_glance: platform::HostGlance,
}

pub(crate) struct HeavyShared {
    pub(crate) snap: Mutex<HeavySnapshot>,
    /// Worker polls wifi/bt/focus only while the Control Center is open.
    pub(crate) cc_open: AtomicBool,
}

pub(crate) fn spawn_heavy_worker(face: Face, shared: Arc<HeavyShared>) {
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
            if face == Face::Console {
                s.console_games = platform::console_games_list();
                s.console_media_path = platform::console_media_path();
                s.console_apps = platform::console_apps_thin(32);
            }
            if face == Face::Host {
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

pub(crate) struct App {
    pub(crate) theme: Theme,
    pub(crate) chrome: SharedChrome,
    pub(crate) chrome_epoch: ChromeEpoch,
    pub(crate) last_epoch: u64,
    pub(crate) notifs: SharedNotifs,
    pub(crate) tray: SharedTray,
    pub(crate) tray_items: Vec<platform::TrayItem>,
    pub(crate) chrome_snap: ChromeState,
    pub(crate) wm: WmState,
    pub(crate) wm_shared: wm_ipc::SharedWm,
    /// Last copied `WmShared.gen` — skip clone when unchanged.
    pub(crate) wm_gen: u64,
    pub(crate) power: PowerStatus,
    pub(crate) privacy_dots: PrivacyDots,
    pub(crate) dnd: bool,
    pub(crate) volume: Option<u8>,
    pub(crate) console_games: Vec<ConsoleGame>,
    pub(crate) console_media_path: String,
    pub(crate) console_apps: Vec<(String, String)>,
    pub(crate) host_tab: usize,
    pub(crate) host_glance: platform::HostGlance,
    pub(crate) wifi_hits: Vec<platform::WifiHit>,
    pub(crate) bt_hits: Vec<platform::BtHit>,
    pub(crate) brightness: Option<u8>,
    pub(crate) mpris: Vec<MprisPlayer>,
    pub(crate) pins: Vec<String>,
    pub(crate) beacon_hits: Vec<String>,
    pub(crate) lock_ui: LockUiState,
    pub(crate) focus_on: bool,
    /// Last Focus schedule window membership (`None` = schedule inactive).
    pub(crate) focus_schedule_last: Option<bool>,
    pub(crate) focus_profiles: Vec<platform::FocusProfile>,
    pub(crate) focus_active_id: String,
    pub(crate) face: Face,
    /// Initial daemon window namespace (usually bar). Extra layers live in `windows`.
    pub(crate) primary_namespace: String,
    pub(crate) wallpaper: platform::WallpaperState,
    pub(crate) wallpaper_handle: Option<(String, iced::widget::image::Handle)>,
    pub(crate) windows: HashMap<window::Id, String>,
    pub(crate) layer_input_applied: HashMap<window::Id, (u8, u8)>,
    pub(crate) dock_preview: Option<surfaces::DockPreview>,
    pub(crate) single_surface: bool,
    pub(crate) tick_n: u64,
    pub(crate) launcher_open: bool,
    pub(crate) cc_open: bool,
    /// Center hub (calendar / notifications / weather) open.
    pub(crate) hub_open: bool,
    pub(crate) spaces_open: bool,
    /// Manual minimum visible Space end (overview "+").
    pub(crate) spaces_floor: i64,
    pub(crate) workspace_names: Vec<String>,
    /// Settings `workspaceMode` Fact (`synced` | `perDisplay`).
    pub(crate) workspace_mode: String,
    pub(crate) spaces_thumbs: HashMap<String, proteus_shell::spaces::SpaceWinThumb>,
    pub(crate) spaces_rename_id: Option<i64>,
    pub(crate) spaces_rename_buf: String,
    pub(crate) spaces_drag: Option<String>,
    pub(crate) spaces_drag_output: Option<String>,
    pub(crate) spaces_drag_target: Option<i64>,
    pub(crate) spaces_drag_target_output: Option<String>,
    /// Capture grim thumbs next tick/update after overview opens.
    pub(crate) spaces_need_thumbs: bool,
    /// Focus rename field after ✎ (next update).
    pub(crate) spaces_rename_focus_pending: bool,
    /// Focus lock password field after reveal / wake keystroke.
    pub(crate) lock_password_focus_pending: bool,
    /// Debounce identical lock keystrokes (multi-window Interaction duplicates).
    pub(crate) lock_key_debounce: Option<(String, Instant)>,
    pub(crate) locked: bool,
    pub(crate) hud_kind: String,
    pub(crate) hud_value: f32,
    pub(crate) privacy_ask: Option<String>,
    pub(crate) privacy_ask_app: Option<String>,
    /// Throttle for mid-session `enforce-capture` while privacy dots are lit.
    pub(crate) privacy_enforce_at: Option<Instant>,
    pub(crate) beacon_query: String,
    pub(crate) toast: Option<Notification>,
    pub(crate) notif_items: Vec<Notification>,
    pub(crate) widget_kinds: Vec<String>,
    pub(crate) widget_gallery: Vec<String>,
    pub(crate) desktop_widgets: proteus_shell::desktop_widgets::DesktopWidgetsState,
    /// Wallpaper / empty-desktop hold-to-Customize arm time.
    pub(crate) desktop_hold_at: Option<Instant>,
    pub(crate) weather: platform::WeatherGlance,
    pub(crate) wifi_radio_on: bool,
    pub(crate) bt_radio_on: bool,
    pub(crate) wifi_err: String,
    pub(crate) bt_err: String,
    pub(crate) anims: Anims,
    pub(crate) icon_cache: proteus_shell::icons::IconCache,
    /// Hovered dock pin (hover scale + preview target).
    pub(crate) dock_hover_pin: Option<String>,
    /// Debounced CC slider targets (last value wins; flushed off-thread).
    pub(crate) pending_volume: Option<u8>,
    pub(crate) pending_brightness: Option<u8>,
    pub(crate) slider_flush_at: Option<Instant>,
    /// Pending leave — cleared if hover/preview-enter arrives first.
    pub(crate) dock_leave_at: Option<Instant>,
    /// Hover start for dwell preview (`DOCK_PREVIEW_DWELL_MS`).
    pub(crate) dock_dwell: Option<(String, Instant)>,
    /// Long-press edit mode — reorder pinned cells only.
    pub(crate) dock_edit: bool,
    /// `(pin, press start)` while waiting for hold threshold.
    pub(crate) dock_hold_at: Option<(String, Instant)>,
    /// Pin id being dragged in edit mode.
    pub(crate) dock_drag: Option<String>,
    /// Drop target index among pinned cells.
    pub(crate) dock_drag_target: Option<usize>,
    /// Pointer over the drag-off strip while dragging in edit mode.
    pub(crate) dock_drag_off: bool,
    /// Launch bounce until matching window / timeout (`pin → start`).
    pub(crate) dock_bounce: HashMap<String, Instant>,
    /// Cached bounce strengths for the dock view (updated on AnimTick).
    pub(crate) dock_bounce_strengths: Vec<(String, f32)>,
    /// `dockIconSize` Fact (rest icon px).
    pub(crate) dock_icon_size: f32,
    pub(crate) dock_layout: surfaces::DockLayout,
    pub(crate) dock_rounding: f32,
    pub(crate) dock_enabled: bool,
    pub(crate) dock_autohide: bool,
    /// True while pointer is in the hot edge / dock (autohide reveal).
    pub(crate) dock_edge_armed: bool,
    pub(crate) bar_height: u32,
    pub(crate) bar_rounding: f32,
    pub(crate) bar_autohide: bool,
    pub(crate) bar_edge_armed: bool,
    /// Last applied dock exclusive zone — push on change.
    pub(crate) dock_exclusive_zone: Option<i32>,
    pub(crate) bar_exclusive_zone: Option<i32>,
    /// Re-anchor dock layer when layout flips (center/span/left/right).
    pub(crate) dock_geom_dirty: bool,
    /// Last `settings.json` mtime — skip theme/pin/wallpaper reload when unchanged.
    pub(crate) settings_mtime: Option<SystemTime>,
    /// Keyboard-selected Beacon hit index.
    pub(crate) beacon_selected: usize,
    pub(crate) hud_deadline: Option<anim::Deadline>,
    /// (notification id, deadline) for toast auto-dismiss.
    pub(crate) toast_deadline: Option<(u32, anim::Deadline)>,
    /// Toast id already auto-hidden (stays in the CC notification list).
    pub(crate) toast_hidden_id: Option<u32>,
    /// Bar clock strings, refreshed on the slow tick (never in view).
    pub(crate) clock: surfaces::BarClock,
    /// Focus the Beacon input on the next update after opening.
    pub(crate) beacon_focus_pending: bool,
    /// Background subprocess-poll worker output (never gathered on UI thread).
    pub(crate) heavy: Arc<HeavyShared>,
}

#[to_layer_message(multi)]
#[derive(Debug, Clone)]
pub(crate) enum Message {
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
    /// Grim thumbnails for Spaces overview (address, title, workspace, png).
    SpacesThumbsReady(Vec<(String, String, i64, Vec<u8>)>),
}
