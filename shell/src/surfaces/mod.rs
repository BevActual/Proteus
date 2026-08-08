//! Shared chrome kit — bar, dock, beacon, CC, lock, widgets.
//! Session faces (desktop / console / host) compose this kit under [`crate::faces`].

mod bar;
mod beacon;
mod control_center;
mod dock;
mod hub;
mod hud;
mod lock;
mod privacy;
mod toast;
mod wallpaper;
mod widgets;

pub use bar::{bar_exclusive, bar_view, BAR_EXCLUSIVE, BAR_ICON};
pub use beacon::beacon_view;
pub use control_center::control_center_view;
pub use dock::{
    dock_active_dot_index, dock_dot_count, dock_icon_hover_size, dock_pins_from_settings,
    dock_plate_h, dock_running_windows, dock_strip_h, dock_transients, dock_view, persist_dock_pins,
    remove_dock_pin, reorder_dock_pins, DockLayout,
    DOCK_BOUNCE_SCALE, DOCK_BOUNCE_TIMEOUT_MS, DOCK_CELL_SPACING, DOCK_HOVER_SCALE, DOCK_ICON_REST,
    DOCK_LAYER_H, DOCK_LEAVE_DELAY_MS, DOCK_PEEK_SLIDE, DOCK_PREVIEW_DWELL_MS, DOCK_STRIP_H,
};
pub use hub::{center_hub_view, weather_glance_view};
pub use hud::hud_view;
pub use lock::lock_view;
pub use privacy::privacy_ask_view;
pub use toast::toast_view;
pub use wallpaper::wallpaper_view;
pub use widgets::{desktop_widgets_view, widgets_view};

use iced::widget::{container, Space};
use iced::{Color, Element, Length};

use proteus_ui::theme::Theme;

#[derive(Debug, Clone)]
pub enum Message {
    ToggleLauncher,
    ToggleControlCenter,
    ToggleCalendar,
    ToggleWeather,
    /// Notification Center (center menu-bar hub).
    ToggleNotifications,
    /// Open center hub to tab (0=Calendar, 1=Notifications) without toggle-off.
    CenterTab(usize),
    /// Close center hub (calendar / notifications / weather).
    CloseCenterHub,
    /// Spaces overview (full-screen).
    ToggleSpaces,
    /// Scroll over the bar Spaces icon (±1 within visible set).
    SpacesCycle(i32),
    /// Menu-bar Scratchpad ◇ — park/restore via `special:scratch`.
    ScratchToggle,
    SpacesSelect(i64, Option<String>),
    SpacesAdd,
    SpacesRenameStart(i64),
    SpacesRenameInput(String),
    SpacesRenameCommit,
    SpacesDragStart(String),
    SpacesDragHover(i64, Option<String>),
    SpacesDrop(i64, Option<String>),
    /// Release on a window thumb — focus if not dropped elsewhere.
    SpacesThumbRelease(String),
    SpacesEscape,
    BeaconInput(String),
    BeaconLaunch(String),
    /// Keyboard selection move (±1).
    BeaconNav(i32),
    /// Launch the keyboard-selected hit (Enter).
    BeaconSubmit,
    /// Esc — clear query first, close when already empty.
    BeaconEscape,
    Workspace(i64),
    DockLaunch(String),
    HudDismiss,
    ToastDismiss(u32),
    NotifDismiss(u32),
    NotifClearAll,
    /// Appearance Dark (0) / Light (1).
    AppearanceMode(usize),
    WifiRadioToggle,
    BtRadioToggle,
    Screenshot(String),
    OpenSettingsPage(String),
    /// Wallpaper press — arm hold-to-Customize.
    DesktopPress,
    DesktopRelease,
    CustomizeDesktop,
    PrivacyAllow,
    PrivacyDeny,
    Lock,
    Unlock,
    PinEntry(String),
    WidgetAdd(String),
    WidgetRemove(String),
    WidgetSelect(String),
    WidgetDragStart(String),
    WidgetDrag(f32, f32),
    WidgetDragEnd,
    WidgetNudge(f32, f32),
    WidgetSnapToggle,
    WidgetCustomizeDone,
    /// Widget click outside Customize (kind → chrome action).
    WidgetActivate(String),
    FaceSelect(usize),
    Refresh,
    CcRefresh,
    OpenSettings,
    OpenWorkloads,
    OpenPrivacy,
    ToggleFloating,
    BrightnessSet(u8),
    BrightnessStep(i8),
    VolumeStep(i8),
    VolumeSet(u8),
    VolumeMute,
    MediaPlayPause(String),
    MediaNext(String),
    MediaPrev(String),
    PowerProfile(usize),
    LaunchGame(String),
    HostTab(usize),
    ToggleDnd,
    WifiConnect(String),
    BtConnect(String),
    OpenMediaPath,
    LaunchConsoleApp(String),
    ToggleFocus,
    FocusProfile(String),
    OpenConsoleSettingsPage(String),
    LockReveal,
    /// First keystroke while the lock is idle — reveal and keep the character.
    LockWakeChar(char),
    LockPinDigit(char),
    LockPinBackspace,
    LockPinClear,
    LockUsePassword,
    LockUsePin,
    LockCustomizeAdd(String),
    LockCustomizeRemove(String),
    LockCustomizeMove(String, i32),
    LockCustomizeDone,
    DockHover(String),
    /// Pointer entered the dock plate / hot edge (autohide reveal).
    DockEdgeEnter,
    /// Pointer entered the menu bar (autohide reveal).
    BarEdgeEnter,
    /// Pointer left the menu bar.
    BarLeave,
    /// Pointer left a dock cell / shelf — main schedules a short leave delay.
    DockLeave,
    /// Pointer entered the dwell preview card (cancel leave delay).
    DockPreviewEnter,
    /// Focus / restore a window from the dock preview card.
    DockPreviewFocus(String),
    /// Close a window from the dock preview card (✕).
    DockPreviewClose(String),
    /// Press on a dock pin — arms long-press edit or drag (edit mode).
    DockPress(String),
    /// Release on a dock pin — short tap launch or drop reorder.
    DockRelease(String),
    /// Exit dock edit mode and persist `dockPins`.
    DockEditDone,
    /// Remove a pin while in dock edit mode (persists on Done).
    DockUnpin(String),
    /// Hover a pin slot while dragging (pinned index only).
    DockDragHover(usize),
}

/// One window row in the dock hover preview card.
#[derive(Debug, Clone)]
pub struct DockPreviewWin {
    pub address: String,
    pub title: String,
    pub hidden: bool,
    pub handle: iced::widget::image::Handle,
}

/// Dock hover preview payload (pin id → window rows).
pub type DockPreview = (String, Vec<DockPreviewWin>);

/// Dock pin ↔ running toplevel match (shared by running dots + previews).
pub fn pin_matches(pin: &str, class: &str, title: &str) -> bool {
    if is_beacon_pin(pin) {
        return false;
    }
    let c = class.to_lowercase();
    let p = pin.to_lowercase();
    c.contains(&p) || p.contains(&c) || title.to_lowercase().contains(&p)
}

/// Beacon (system search) dock pin — toggles the launcher, never launches a window.
pub fn is_beacon_pin(pin: &str) -> bool {
    let p = pin.to_lowercase();
    p == "proteus-launcher" || p == "beacon" || p == "launcher"
}

/// Cached bar clock strings — refreshed on the slow tick, never in view
/// (spawning `date` per frame would wreck the 60fps anim loop).
#[derive(Debug, Clone, Default, PartialEq)]
pub struct BarClock {
    pub date: String,
    pub time: String,
}

/// Local wall clock for the menu bar (in-process — never spawn `date`).
/// Call sparingly from the slow tick — never per-frame.
pub fn bar_clock_now() -> BarClock {
    use chrono::{Datelike, Local, Timelike};
    let now = Local::now();
    let date = format!(
        "{} {} {}",
        weekday_short(now.weekday().num_days_from_sunday()),
        month_short(now.month()),
        now.day()
    );
    let (h12, ampm) = match now.hour() {
        0 => (12, "AM"),
        h @ 1..=11 => (h, "AM"),
        12 => (12, "PM"),
        h => (h - 12, "PM"),
    };
    let time = format!("{h12}:{:02} {ampm}", now.minute());
    BarClock { date, time }
}

fn weekday_short(sun0: u32) -> &'static str {
    ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][(sun0 as usize) % 7]
}

fn month_short(m: u32) -> &'static str {
    [
        "", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ][(m as usize).clamp(1, 12)]
}

/// DemiBold face for emphasized chrome labels.
pub fn semibold() -> iced::Font {
    iced::Font {
        weight: iced::font::Weight::Semibold,
        ..iced::Font::DEFAULT
    }
}

/// Light face for the lock clock.
pub fn light_font() -> iced::Font {
    iced::Font {
        weight: iced::font::Weight::Light,
        ..iced::Font::DEFAULT
    }
}


pub(crate) fn pin_label(pin: &str) -> String {
    if is_beacon_pin(pin) {
        return "Beacon".into();
    }
    pin.rsplit(&['.', '-'][..])
        .next()
        .unwrap_or(pin)
        .chars()
        .take(10)
        .collect()
}



/// Transparent placeholder for suppressed / idle layers.
pub fn empty_layer<'a>(theme: &'a Theme) -> Element<'a, Message> {
    let _ = theme;
    container(Space::new().width(Length::Fill).height(Length::Fill))
        .width(Length::Fill)
        .height(Length::Fill)
        .style(move |_| container::Style {
            background: Some(iced::Background::Color(Color::TRANSPARENT)),
            ..Default::default()
        })
        .into()
}
