//! Chrome surfaces — bar, dock, beacon, CC, lock, widgets.
//! Session faces (desktop / console / host) live under [`crate::faces`].

use iced::widget::{button, column, container, row, scrollable, text, text_input, Space};
use iced::{Alignment, Background, Border, Color, Element, Length, Padding};

use proteus_ui::theme::Theme;
use proteus_ui::widgets::{
    chrome_tile, dock_plate, elevated_chip, glass_plate, menu_bar_plate, segmented_control,
};

use crate::ctl::ChromeState;
use crate::wm_ipc::WmState;
use crate::platform::{MprisPlayer, Notification, PowerStatus, PrivacyDots};

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
    /// Mission Control Spaces overview.
    ToggleSpaces,
    /// Scroll over the bar Spaces icon (±1 within visible set).
    SpacesCycle(i32),
    SpacesSelect(i64),
    SpacesAdd,
    SpacesRenameStart(i64),
    SpacesRenameInput(String),
    SpacesRenameCommit,
    SpacesDragStart(String),
    SpacesDragHover(i64),
    SpacesDrop(i64),
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

/// Bar hover chip — hover is brightness, active is soft accent (QML TopBar).
fn bar_chip_style(
    theme: &Theme,
    active: bool,
) -> impl Fn(&iced::Theme, button::Status) -> button::Style + Copy {
    let hover = if theme.mode == proteus_ui::theme::ChromeMode::Dark {
        Color::from_rgba(1.0, 1.0, 1.0, 0.12)
    } else {
        Color::from_rgba(0.0, 0.0, 0.0, 0.07)
    };
    let active_fill = theme.accent_soft;
    let text_color = theme.text;
    move |_t, status| {
        let background = if active {
            Some(Background::Color(active_fill))
        } else {
            match status {
                button::Status::Hovered | button::Status::Pressed => {
                    Some(Background::Color(hover))
                }
                _ => None,
            }
        };
        button::Style {
            background,
            text_color,
            border: Border {
                radius: 6.0.into(),
                width: 0.0,
                color: Color::TRANSPARENT,
            },
            ..Default::default()
        }
    }
}

/// Menu-bar chrome glyphs (Spaces, CC, privacy, battery, …).
pub const BAR_ICON: f32 = 18.0;
/// Default exclusive zone / layer height for the top menu bar.
pub const BAR_EXCLUSIVE: u32 = 38;

pub fn bar_exclusive(height: u32) -> u32 {
    height.clamp(28, 48)
}

pub fn bar_view<'a>(
    theme: &'a Theme,
    chrome: &'a ChromeState,
    _hypr: &'a WmState,
    power: &'a PowerStatus,
    tray: &'a [crate::platform::TrayItem],
    privacy: &'a PrivacyDots,
    dnd: bool,
    clock: &'a BarClock,
    weather: &'a crate::platform::WeatherGlance,
    notif_count: usize,
    rounding: f32,
) -> Element<'a, Message> {
    // Window close / min / max + title live on compositor SSD chrome (Windows-style),
    // not in the menu bar.

    // Spaces control — Mission Control icon (overview), wheel cycles Spaces.
    let spaces_open = chrome.spaces_open;
    let accent = theme.accent;
    let spaces_glyph = crate::icons::glyph_view(
        "spaces",
        BAR_ICON,
        if spaces_open { accent } else { theme.text_dim },
    );
    let spaces_btn = button(spaces_glyph)
        .padding(Padding::new(4.0).left(8.0).right(8.0))
        .style(move |_t, status| {
            let hover = matches!(
                status,
                button::Status::Hovered | button::Status::Pressed
            );
            button::Style {
                background: if spaces_open {
                    Some(Background::Color(theme.accent_soft))
                } else if hover {
                    Some(Background::Color(theme.text_mute.scale_alpha(0.12)))
                } else {
                    None
                },
                text_color: if spaces_open { accent } else { theme.text_dim },
                border: Border {
                    radius: 8.0.into(),
                    ..Default::default()
                },
                ..Default::default()
            }
        })
        .on_press(Message::ToggleSpaces);
    let ws: Element<'a, Message> = iced::widget::mouse_area(spaces_btn)
        .on_scroll(|delta| {
            let y = match delta {
                iced::mouse::ScrollDelta::Lines { y, .. } => y,
                iced::mouse::ScrollDelta::Pixels { y, .. } => y / 40.0,
            };
            if y > 0.1 {
                Message::SpacesCycle(-1)
            } else if y < -0.1 {
                Message::SpacesCycle(1)
            } else {
                Message::SpacesCycle(0)
            }
        })
        .into();

    let mut tray_row = row![].spacing(4).align_y(Alignment::Center);
    for t in tray.iter().take(6) {
        tray_row = tray_row.push(
            text(t.title.chars().take(8).collect::<String>())
                .size(10)
                .color(theme.text_mute),
        );
    }

    // Privacy indicators — semantic glyphs, one hover chip each.
    let mut privacy_row = row![].spacing(2).align_y(Alignment::Center);
    for (on, glyph, color) in [
        (privacy.mic, "mic", theme.privacy_mic),
        (privacy.camera, "camera", theme.privacy_cam),
        (privacy.screen, "screen", theme.privacy_screen),
    ] {
        if on {
            privacy_row = privacy_row.push(
                button(crate::icons::glyph_view(glyph, BAR_ICON, color))
                    .padding(3)
                    .style(bar_chip_style(theme, false))
                    .on_press(Message::OpenPrivacy),
            );
        }
    }

    let dnd_chip: Element<'a, Message> = if dnd {
        crate::icons::glyph_view("moon", BAR_ICON, theme.accent)
    } else {
        Space::new().width(Length::Fixed(0.0)).into()
    };

    // Center cluster — date · time · weather · notif badge (Notification Center).
    let hub_open = chrome.calendar_open || chrome.notifications_open;
    let weather_open = chrome.weather_open;
    let clock_btn = button(
        row![
            text(clock.date.clone()).size(13).color(theme.text_dim),
            text(clock.time.clone())
                .size(13)
                .font(semibold())
                .color(theme.text),
        ]
        .spacing(6)
        .align_y(Alignment::Center),
    )
    .padding(Padding::new(3.0).left(8.0).right(8.0))
    .style(bar_chip_style(theme, hub_open && chrome.calendar_open))
    .on_press(Message::ToggleCalendar);

    let weather_label = if weather.temp_label.is_empty() {
        "—".into()
    } else {
        weather.temp_label.clone()
    };
    let weather_chip = button(
        row![
            crate::icons::glyph_view("sun", BAR_ICON, theme.text_dim),
            text(weather_label).size(12).color(theme.text_dim),
        ]
        .spacing(4)
        .align_y(Alignment::Center),
    )
    .padding(Padding::new(3.0).left(6.0).right(6.0))
    .style(bar_chip_style(theme, weather_open))
    .on_press(Message::ToggleWeather);

    let badge: Element<'a, Message> = if notif_count > 0 || chrome.notifications_open {
        let label = if notif_count > 9 {
            "9+".into()
        } else if notif_count == 0 {
            "·".into()
        } else {
            notif_count.to_string()
        };
        button(
            text(label)
                .size(11)
                .font(semibold())
                .color(if chrome.notifications_open {
                    theme.accent
                } else {
                    theme.text
                }),
        )
        .padding(Padding::new(2.0).left(7.0).right(7.0))
        .style(bar_chip_style(theme, chrome.notifications_open))
        .on_press(Message::ToggleNotifications)
        .into()
    } else {
        button(crate::icons::glyph_view("dot", 8.0, theme.text_mute))
            .padding(4)
            .style(bar_chip_style(theme, false))
            .on_press(Message::ToggleNotifications)
            .into()
    };

    let clock_el = row![clock_btn, weather_chip, badge]
        .spacing(4)
        .align_y(Alignment::Center);

    // Battery — glyph + % only with a real battery (honest facts).
    let bat: Element<'a, Message> = if power.percent > 0 {
        row![
            crate::icons::glyph_view("battery", BAR_ICON, theme.text_dim),
            text(format!("{}%", power.percent))
                .size(12)
                .color(theme.text_dim),
        ]
        .spacing(4)
        .align_y(Alignment::Center)
        .into()
    } else {
        Space::new().width(Length::Fixed(0.0)).into()
    };

    // Quieter Apple-like bar: status detail lives in Control Center.
    let cc_color = if chrome.control_center_open {
        theme.accent
    } else {
        theme.text_dim
    };
    let cc = button(crate::icons::glyph_view("cc", BAR_ICON, cc_color))
        .padding(Padding::new(3.0).left(7.0).right(7.0))
        .style(bar_chip_style(theme, chrome.control_center_open))
        .on_press(Message::ToggleControlCenter);

    // Clock centered visually: left cluster · fill · clock · fill · right cluster
    let left = row![ws].spacing(10).align_y(Alignment::Center);
    let right = row![privacy_row, tray_row, dnd_chip, bat, cc]
        .spacing(theme.space_sm)
        .align_y(Alignment::Center);

    menu_bar_plate(
        theme,
        rounding,
        row![
            container(left).width(Length::Fill),
            clock_el,
            container(right).width(Length::Fill).align_x(Alignment::End),
        ]
        .spacing(theme.space_sm)
        .align_y(Alignment::Center)
        .padding(Padding::new(5.0).left(14.0).right(14.0)),
    )
}

/// Dock surface height and the input-opaque shelf strip at its bottom.
/// Preview band above the strip is click-through until a dwell preview opens
/// (then reconcile_layer_input expands to `DockPreview`).
/// Tall enough for one dwell card + tip + magnified shelf without flex-crushing icons.
pub const DOCK_LAYER_H: u32 = 320;
pub const DOCK_STRIP_H: u32 = 72;
/// Hover-dwell before capturing window thumbnails (ms).
pub const DOCK_PREVIEW_DWELL_MS: u64 = 350;
/// Launch bounce timeout (ms) if no matching window appears.
pub const DOCK_BOUNCE_TIMEOUT_MS: u64 = 3200;
/// Delay before clearing hover/preview so the pointer can reach the card.
pub const DOCK_LEAVE_DELAY_MS: u64 = 140;

/// Dock geometry defaults (iconSize=48).
pub const DOCK_ICON_REST: f32 = 48.0;
/// Per-icon hover scale (Windows-style — no neighbor magnify).
pub const DOCK_HOVER_SCALE: f32 = 1.12;
/// Launch bounce amplitude relative to rest size.
pub const DOCK_BOUNCE_SCALE: f32 = 0.18;
/// Gap between dock cells.
pub const DOCK_CELL_SPACING: f32 = 7.0;
/// Hot-edge peek fraction while autohidden (partial reveal).
pub const DOCK_PEEK_SLIDE: f32 = 0.30;

/// Dock edge layout from `dockLayout` Fact.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum DockLayout {
    #[default]
    Center,
    Span,
    Left,
    Right,
}

impl DockLayout {
    pub fn parse(s: &str) -> Self {
        match s {
            "span" => Self::Span,
            "left" => Self::Left,
            "right" => Self::Right,
            _ => Self::Center,
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Self::Center => "center",
            Self::Span => "span",
            Self::Left => "left",
            Self::Right => "right",
        }
    }

    pub fn vertical(self) -> bool {
        matches!(self, Self::Left | Self::Right)
    }

    pub fn span_edge(self) -> bool {
        matches!(self, Self::Span | Self::Left | Self::Right)
    }
}

/// Rest-thickness frosted plate (pads + icon + running indicator).
pub fn dock_plate_h(rest: f32, pad_v: f32) -> f32 {
    pad_v * 2.0 + rest + 10.0
}

/// Layer input / exclusive strip size for a rest icon size (no magnify headroom).
pub fn dock_strip_h(rest: f32) -> u32 {
    (dock_plate_h(rest, 6.0) + 8.0).clamp(52.0, 96.0) as u32
}

/// Hairline divider thickness.
pub fn dock_divider_width(_icon_rest: f32) -> f32 {
    1.0
}

/// Hovered icon size (rest × hover scale × engagement).
pub fn dock_icon_hover_size(rest: f32, hover_t: f32) -> f32 {
    let t = hover_t.clamp(0.0, 1.0);
    rest * (1.0 + (DOCK_HOVER_SCALE - 1.0) * t)
}

/// Non-minimized toplevels matching a dock pin (Beacon → empty).
pub fn dock_running_windows<'a>(pin: &str, hypr: &'a WmState) -> Vec<&'a crate::wm_ipc::Toplevel> {
    if is_beacon_pin(pin) {
        return Vec::new();
    }
    hypr.toplevels
        .iter()
        .filter(|t| t.workspace >= 0 && pin_matches(pin, &t.class, &t.title))
        .collect()
}

/// Visible running-dot count (cap 3).
pub fn dock_dot_count(running: usize) -> usize {
    running.min(3)
}

/// Accented dot index among `dot_count` dots when the pin is focused.
pub fn dock_active_dot_index(pin: &str, hypr: &WmState, running: &[&crate::wm_ipc::Toplevel]) -> Option<usize> {
    if running.is_empty() {
        return None;
    }
    let focused = !hypr.active_class.is_empty()
        && pin_matches(pin, &hypr.active_class, &hypr.active_title);
    if !focused {
        return None;
    }
    let idx = running
        .iter()
        .position(|t| t.address == hypr.active_address)
        .unwrap_or(0);
    Some(idx.min(dock_dot_count(running.len()).saturating_sub(1)))
}

/// Unpinned running apps (class keys) for the transient dock section.
pub fn dock_transients(pins: &[String], hypr: &WmState) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    for t in &hypr.toplevels {
        if t.class.is_empty() {
            continue;
        }
        let pinned = pins
            .iter()
            .any(|p| pin_matches(p.as_str(), &t.class, &t.title));
        if pinned {
            continue;
        }
        if out
            .iter()
            .any(|k| pin_matches(k.as_str(), &t.class, &t.title))
        {
            continue;
        }
        out.push(t.class.clone());
    }
    out
}

/// Resolve dock pins from settings.json `dockPins` (Beacon always present).
pub fn dock_pins_from_settings(settings: &serde_json::Value) -> Vec<String> {
    let raw = settings
        .get("dockPins")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .trim();
    let mut pins = if raw.is_empty() {
        vec![
            "proteus-launcher".into(),
            "proteus-settings".into(),
            "proteus-workloads".into(),
            "com.mitchellh.ghostty".into(),
            "org.gnome.Nautilus".into(),
        ]
    } else if raw == "-" {
        vec!["proteus-launcher".into(), "proteus-settings".into()]
    } else {
        raw.split(',')
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
            .collect()
    };
    if !pins.iter().any(|p| is_beacon_pin(p)) {
        pins.insert(0, "proteus-launcher".into());
    }
    pins
}

/// Icon element for a dock pin — real app icon or initials on a squircle plate.
fn dock_icon<'a>(
    theme: &'a Theme,
    icons: &'a crate::icons::IconCache,
    pin: &str,
    size: f32,
) -> Element<'a, Message> {
    match icons.get(pin) {
        Some(handle) => {
            proteus_ui::widgets::squircle_plate(theme, size, handle.view(size * 0.78))
        }
        None => {
            let initials: String = pin_label(pin)
                .chars()
                .take(2)
                .collect::<String>()
                .to_uppercase();
            proteus_ui::widgets::squircle_plate(
                theme,
                size,
                text(initials)
                    .size(size * 0.34)
                    .font(semibold())
                    .color(theme.text_dim),
            )
        }
    }
}

fn dock_indicator_dot<'a>(color: Color, w: f32, h: f32) -> Element<'a, Message> {
    container(
        Space::new()
            .width(Length::Fixed(w))
            .height(Length::Fixed(h)),
    )
    .style(move |_t| container::Style {
        background: Some(Background::Color(color)),
        border: Border {
            radius: (h / 2.0).into(),
            ..Default::default()
        },
        ..Default::default()
    })
    .into()
}

fn dock_running_indicator<'a>(
    theme: &'a Theme,
    pin: &str,
    hypr: &'a WmState,
    beacon_open: bool,
) -> Element<'a, Message> {
    let accent = theme.accent;
    let dim = theme.text_mute;
    if is_beacon_pin(pin) {
        let color = if beacon_open {
            accent
        } else {
            Color::TRANSPARENT
        };
        return dock_indicator_dot(color, 8.0, 3.0);
    }
    let running = dock_running_windows(pin, hypr);
    let n = dock_dot_count(running.len());
    if n == 0 {
        return dock_indicator_dot(Color::TRANSPARENT, 4.0, 4.0);
    }
    let active_idx = dock_active_dot_index(pin, hypr, &running);
    // Single focused window keeps the accent pill; multi-window → dots.
    if n == 1 && active_idx.is_some() {
        return dock_indicator_dot(accent, 8.0, 3.0);
    }
    if n == 1 {
        return dock_indicator_dot(dim, 4.0, 4.0);
    }
    let mut dots = row![].spacing(3).align_y(Alignment::Center);
    for i in 0..n {
        let color = if active_idx == Some(i) { accent } else { dim };
        dots = dots.push(dock_indicator_dot(color, 4.0, 4.0));
    }
    dots.into()
}

fn dock_cell<'a>(
    theme: &'a Theme,
    icons: &'a crate::icons::IconCache,
    hypr: &'a WmState,
    pin: &str,
    size: f32,
    bounce_s: f32,
    beacon_open: bool,
) -> Element<'a, Message> {
    let id = pin.to_string();
    let max_lift = size * 0.12;
    let pad_top = max_lift * (1.0 - bounce_s.clamp(0.0, 1.0));
    let indicator = dock_running_indicator(theme, pin, hypr, beacon_open);
    let icon = container(
        button(dock_icon(theme, icons, pin, size))
            .padding(0)
            .style(|_t, _s| button::Style {
                background: None,
                text_color: Color::TRANSPARENT,
                border: Border::default(),
                ..Default::default()
            })
            .on_press(Message::DockLaunch(id)),
    )
    .padding(Padding::new(0.0).top(pad_top));

    let cell = column![icon, indicator]
        .align_x(Alignment::Center)
        .spacing(3);
    let hover_pin_msg = pin.to_string();
    // Enter only — leave is shelf-scoped so cell→cell / shelf→preview don't dip mag.
    iced::widget::mouse_area(cell)
        .on_enter(Message::DockHover(hover_pin_msg))
        .into()
}

/// Hairline divider between pins and running transients.
fn dock_divider(theme: &Theme, icon_rest: f32) -> Element<'_, Message> {
    let hair = theme.hairline;
    let h = (icon_rest * 0.75).clamp(28.0, 56.0);
    container(
        Space::new()
            .width(Length::Fixed(dock_divider_width(icon_rest)))
            .height(Length::Fixed(h)),
    )
    .padding(Padding::new(0.0).top(4.0).bottom(10.0))
    .style(move |_t| container::Style {
        background: Some(Background::Color(hair)),
        border: Border {
            radius: 1.0.into(),
            ..Default::default()
        },
        ..Default::default()
    })
    .into()
}

pub fn dock_view<'a>(
    theme: &'a Theme,
    pins: &'a [String],
    hypr: &'a WmState,
    preview: Option<&'a DockPreview>,
    icons: &'a crate::icons::IconCache,
    hover_pin: Option<&'a str>,
    hover_t: f32,
    slide: f32,
    icon_rest: f32,
    layout: DockLayout,
    rounding: f32,
    // pin → bounce phase strength 0..=1 (sin envelope from launch).
    bounce: &'a [(String, f32)],
    beacon_open: bool,
) -> Element<'a, Message> {
    let transients = dock_transients(pins, hypr);
    let has_divider = !pins.is_empty() && !transients.is_empty();
    let vertical = layout.vertical();
    let span = layout.span_edge();
    let slide = slide.clamp(0.0, 1.0);

    let cell_size = |pin: &str| -> (f32, f32) {
        let bounce_s = bounce
            .iter()
            .find(|(p, _)| p == pin)
            .map(|(_, s)| *s)
            .unwrap_or(0.0);
        let hovered = hover_pin == Some(pin);
        let base = if hovered {
            dock_icon_hover_size(icon_rest, hover_t)
        } else {
            icon_rest
        };
        (base + icon_rest * DOCK_BOUNCE_SCALE * bounce_s, bounce_s)
    };

    let mut cells: Vec<Element<'a, Message>> = Vec::new();
    for pin in pins.iter() {
        let (size, bounce_s) = cell_size(pin);
        cells.push(dock_cell(
            theme,
            icons,
            hypr,
            pin,
            size,
            bounce_s,
            beacon_open,
        ));
    }
    if has_divider {
        cells.push(dock_divider(theme, icon_rest));
    }
    for pin in transients.iter() {
        let (size, bounce_s) = cell_size(pin);
        cells.push(dock_cell(
            theme, icons, hypr, pin, size, bounce_s, false,
        ));
    }

    let icons_el: Element<'a, Message> = if vertical {
        let mut c = column![].spacing(DOCK_CELL_SPACING).align_x(Alignment::Center);
        for cell in cells {
            c = c.push(cell);
        }
        c.into()
    } else {
        let mut r = row![].spacing(DOCK_CELL_SPACING).align_y(Alignment::End);
        for cell in cells {
            r = r.push(cell);
        }
        r.into()
    };

    let plate_h = dock_plate_h(icon_rest, theme.space_sm);
    let shelf = iced::widget::mouse_area(dock_plate(
        theme,
        plate_h,
        rounding,
        span,
        vertical,
        icons_el,
    ))
    .on_enter(Message::DockEdgeEnter)
    .on_exit(Message::DockLeave);

    // Hover tip + interactive preview (bottom docks only; vertical Out this pass).
    let preview_card: Element<'a, Message> = if let Some(pin) =
        hover_pin.filter(|_| !vertical && hover_t > 0.05)
    {
        let title = pin_label(pin);
        let tip = elevated_chip(
            theme,
            text(title).size(11).font(semibold()).color(theme.text),
        );
        let card: Element<'a, Message> = match preview {
            Some((ppin, wins)) if ppin == pin && !wins.is_empty() => {
                let mut rows = column![].spacing(6);
                // Cap height — stacked thumbs used to crush the shelf in the layer.
                for w in wins.iter().take(2) {
                    let addr = w.address.clone();
                    let addr_close = w.address.clone();
                    let danger = theme.danger;
                    let mute = theme.text_mute;
                    let mut title_row = row![
                        text(
                            if w.title.is_empty() {
                                "Window".into()
                            } else {
                                w.title.chars().take(36).collect::<String>()
                            }
                        )
                        .size(11)
                        .font(semibold())
                        .color(theme.text),
                    ]
                    .spacing(6)
                    .align_y(Alignment::Center);
                    if w.hidden {
                        title_row = title_row.push(
                            container(
                                text("Hidden")
                                    .size(9)
                                    .font(semibold())
                                    .color(theme.text_mute),
                            )
                            .padding(Padding::from([2, 6]))
                            .style(move |_t| container::Style {
                                background: Some(Background::Color(mute.scale_alpha(0.35))),
                                border: Border {
                                    radius: 6.0.into(),
                                    ..Default::default()
                                },
                                ..Default::default()
                            }),
                        );
                    }
                    let thumb = iced::widget::image(w.handle.clone())
                        .width(Length::Fixed(180.0))
                        .height(Length::Fixed(100.0))
                        .content_fit(iced::ContentFit::Contain);
                    let close_btn = button(text("✕").size(12).color(danger))
                        .padding(Padding::from([2, 6]))
                        .style(move |_t, s| button::Style {
                            background: match s {
                                button::Status::Hovered | button::Status::Pressed => {
                                    Some(Background::Color(danger.scale_alpha(0.18)))
                                }
                                _ => None,
                            },
                            text_color: danger,
                            border: Border {
                                radius: 6.0.into(),
                                ..Default::default()
                            },
                            ..Default::default()
                        })
                        .on_press(Message::DockPreviewClose(addr_close));
                    let body = column![title_row, thumb].spacing(4);
                    rows = rows.push(
                        row![
                            button(body)
                                .padding(6)
                                .style(move |_t, s| {
                                    let bg = match s {
                                        button::Status::Hovered | button::Status::Pressed => {
                                            Some(Background::Color(mute.scale_alpha(0.2)))
                                        }
                                        _ => None,
                                    };
                                    button::Style {
                                        background: bg,
                                        text_color: Color::WHITE,
                                        border: Border {
                                            radius: 10.0.into(),
                                            ..Default::default()
                                        },
                                        ..Default::default()
                                    }
                                })
                                .on_press(Message::DockPreviewFocus(addr)),
                            close_btn,
                        ]
                        .spacing(4)
                        .align_y(Alignment::Start),
                    );
                }
                column![
                    container(rows).padding(8).style(theme.panel_style()),
                    tip,
                ]
                .spacing(6)
                .align_x(Alignment::Center)
                .into()
            }
            _ => tip,
        };
        iced::widget::mouse_area(card)
            .on_enter(Message::DockPreviewEnter)
            .into()
    } else {
        Space::new().height(Length::Fixed(0.0)).into()
    };

    // Preview + shelf share a Shrink column (end-aligned). Tall dwell cards
    // used to crush icons when both competed for Fill — tip/card stay Shrink.
    let hide = (1.0 - slide) * plate_h;
    if vertical {
        let shelf = container(shelf)
            .width(Length::Shrink)
            .height(if span { Length::Fill } else { Length::Shrink });
        let peek_pad = Space::new().width(Length::Fixed(hide));
        let body = match layout {
            DockLayout::Left => row![shelf, peek_pad],
            DockLayout::Right => row![peek_pad, shelf],
            _ => row![shelf],
        }
        .height(Length::Fill)
        .align_y(Alignment::Center);
        container(body)
            .width(Length::Fill)
            .height(Length::Fill)
            .align_x(match layout {
                DockLayout::Right => Alignment::End,
                _ => Alignment::Start,
            })
            .align_y(Alignment::Center)
            .into()
    } else {
        // Shrink column (preview + shelf + autohide pad), end-aligned in the
        // layer — same as the pre-layout-rewrite dock. A Fill-height preview
        // band inside this column made iced resolve the shelf to 0 height.
        let shelf = container(shelf)
            .height(Length::Shrink)
            .width(if span { Length::Fill } else { Length::Shrink })
            .align_x(if span {
                Alignment::Start
            } else {
                Alignment::Center
            });
        let stack = column![
            preview_card,
            shelf,
            Space::new().height(Length::Fixed(hide)),
        ]
        .spacing(8)
        .width(Length::Fill)
        .align_x(if span {
            Alignment::Start
        } else {
            Alignment::Center
        });
        container(stack)
            .width(Length::Fill)
            .height(Length::Fill)
            .align_x(if span {
                Alignment::Start
            } else {
                Alignment::Center
            })
            .align_y(Alignment::End)
            .into()
    }
}

/// Split a Beacon hit label into title / subtitle / icon key.
fn beacon_hit_parts(hit: &str) -> (String, String, BeaconIcon) {
    if let Some(rest) = hit.strip_prefix("Window · ") {
        let title = rest.rsplit_once(" · ").map(|(t, _)| t).unwrap_or(rest);
        return (title.to_string(), "Window".into(), BeaconIcon::Glyph("screen"));
    }
    if let Some(path) = hit.strip_prefix("File · ") {
        let name = path.rsplit('/').next().unwrap_or(path);
        return (name.to_string(), path.to_string(), BeaconIcon::Glyph("note"));
    }
    if let Some(leaf) = hit.strip_prefix("Settings · ") {
        return (
            leaf.to_string(),
            "Settings".into(),
            BeaconIcon::App("proteus-settings".into()),
        );
    }
    match hit {
        "Settings" => (
            hit.into(),
            "App".into(),
            BeaconIcon::App("proteus-settings".into()),
        ),
        "Workloads" => (
            hit.into(),
            "App".into(),
            BeaconIcon::App("proteus-workloads".into()),
        ),
        "Lock screen" => (hit.into(), "Action".into(), BeaconIcon::Glyph("power")),
        _ => {
            // "Name · id.desktop" app rows.
            if let Some((name, id)) = hit.rsplit_once(" · ") {
                if id.ends_with(".desktop") {
                    return (name.to_string(), "App".into(), BeaconIcon::App(id.into()));
                }
            }
            (hit.to_string(), String::new(), BeaconIcon::Glyph("dot"))
        }
    }
}

enum BeaconIcon {
    App(String),
    Glyph(&'static str),
}

pub fn beacon_view<'a>(
    theme: &'a Theme,
    chrome: &'a ChromeState,
    hits: &'a [String],
    selected: usize,
    icons: &'a crate::icons::IconCache,
    open_t: f32,
) -> Element<'a, Message> {
    // Search row — 52px, glyph + transparent input on the card.
    let value_c = theme.text;
    let mute_c = theme.text_mute;
    let selection_c = theme.accent_soft;
    let query_input = text_input("Search apps, settings, files…", &chrome.beacon_query)
        .id("beacon-input")
        .on_input(Message::BeaconInput)
        .on_submit(Message::BeaconSubmit)
        .padding(Padding::new(12.0).left(6.0))
        .size(20)
        .style(move |_t, _s| iced::widget::text_input::Style {
            background: Background::Color(Color::TRANSPARENT),
            border: Border::default(),
            icon: Color::TRANSPARENT,
            placeholder: mute_c,
            value: value_c,
            selection: selection_c,
        });
    let search_row = row![
        crate::icons::glyph_view("search", 18.0, theme.text_mute),
        query_input,
    ]
    .spacing(8)
    .align_y(Alignment::Center)
    .padding(Padding::new(0.0).left(18.0).right(14.0));

    let hairline = theme.hairline;
    let divider = container(Space::new().width(Length::Fill).height(1))
        .style(move |_t| container::Style {
            background: Some(Background::Color(hairline)),
            ..Default::default()
        });

    // Result rows — 52px: squircle icon 34, title 15 / subtitle 11, soft-accent
    // selection (keyboard) + brightness hover.
    let mut list = column![].spacing(2);
    for (i, h) in hits.iter().take(12).enumerate() {
        let id = h.clone();
        let is_selected = i == selected;
        let hover = theme.bg_hover;
        let accent_soft = theme.accent_soft;
        let text_c = theme.text;
        let (title, subtitle, icon_key) = beacon_hit_parts(h);
        let icon_el: Element<'a, Message> = match &icon_key {
            BeaconIcon::App(key) => match icons.get(key) {
                Some(handle) => {
                    proteus_ui::widgets::squircle_plate(theme, 34.0, handle.view(26.0))
                }
                None => proteus_ui::widgets::squircle_plate(
                    theme,
                    34.0,
                    crate::icons::glyph_view("dot", 16.0, theme.text_mute),
                ),
            },
            BeaconIcon::Glyph(g) => proteus_ui::widgets::squircle_plate(
                theme,
                34.0,
                crate::icons::glyph_view(g, 18.0, theme.text_dim),
            ),
        };
        let mut labels = column![text(title).size(15).color(theme.text)].spacing(1);
        if !subtitle.is_empty() {
            labels = labels.push(
                text(subtitle.chars().take(52).collect::<String>())
                    .size(11)
                    .color(theme.text_mute),
            );
        }
        list = list.push(
            button(
                row![icon_el, labels]
                    .spacing(12)
                    .align_y(Alignment::Center),
            )
            .width(Length::Fill)
            .padding(Padding::new(9.0).left(12.0).right(12.0))
            .style(move |_t, s| {
                let bg = if is_selected {
                    Some(accent_soft)
                } else if matches!(s, button::Status::Hovered | button::Status::Pressed) {
                    Some(hover)
                } else {
                    None
                };
                button::Style {
                    background: bg.map(Background::Color),
                    text_color: text_c,
                    border: Border {
                        radius: 12.0.into(),
                        ..Default::default()
                    },
                    ..Default::default()
                }
            })
            .on_press(Message::BeaconLaunch(id)),
        );
    }
    let body: Element<'a, Message> = if hits.is_empty() {
        container(
            column![
                crate::icons::glyph_view("search", 26.0, theme.text_mute),
                text("No results").size(14).color(theme.text_mute),
            ]
            .spacing(8)
            .align_x(Alignment::Center),
        )
        .width(Length::Fill)
        .padding(32)
        .align_x(Alignment::Center)
        .into()
    } else {
        scrollable(list.padding(Padding::new(8.0)))
            .height(Length::Fixed(360.0))
            .into()
    };

    // Card — 680 wide, soft sheet radius (Spotlight rhythm).
    let card_fill = if theme.mode == proteus_ui::theme::ChromeMode::Dark {
        Color::from_rgba(0.16, 0.16, 0.17, 0.92)
    } else {
        Color::from_rgba(1.0, 1.0, 1.0, 0.95)
    };
    let card_border = theme.hairline;
    let card_radius = theme.radius_xl;
    let card = container(column![search_row, divider, body].spacing(0))
        .width(Length::Fixed(680.0))
        .style(move |_t| container::Style {
            background: Some(Background::Color(card_fill)),
            border: Border {
                radius: card_radius.into(),
                width: 1.0,
                color: card_border,
            },
            ..Default::default()
        });

    // Open motion: scrim fades in, card slides down 14px (180ms OutCubic).
    let scrim = proteus_ui::theme::fade(theme.scrim, theme.scrim.a * open_t.clamp(0.0, 1.0));
    let top_pad = 96.0 + 14.0 * (1.0 - open_t.clamp(0.0, 1.0));
    container(card)
        .width(Length::Fill)
        .height(Length::Fill)
        .align_x(Alignment::Center)
        .padding(Padding::new(0.0).top(top_pad))
        .style(move |_t| container::Style {
            background: Some(Background::Color(scrim)),
            ..Default::default()
        })
        .into()
}

pub fn control_center_view<'a>(
    theme: &'a Theme,
    chrome: &'a ChromeState,
    power: &'a PowerStatus,
    brightness: Option<u8>,
    volume: Option<u8>,
    mpris: &'a [MprisPlayer],
    dnd: bool,
    wifi: &'a [crate::platform::WifiHit],
    bt: &'a [crate::platform::BtHit],
    wifi_on: bool,
    bt_on: bool,
    wifi_err: &'a str,
    bt_err: &'a str,
    focus_on: bool,
    focus_profiles: &'a [crate::platform::FocusProfile],
    focus_active_id: &'a str,
    open_t: f32,
) -> Element<'a, Message> {
    // Notifications live in the center menu-bar hub — not here.

    // ---- Now Playing (media card + transport) ------------------------------
    let media_card: Element<'a, Message> = if let Some(p) = mpris.first() {
        let bus = p.name.clone();
        let title = if p.title.is_empty() {
            p.name
                .trim_start_matches("org.mpris.MediaPlayer2.")
                .to_string()
        } else {
            p.title.clone()
        };
        chrome_tile(
            theme,
            row![
                proteus_ui::widgets::squircle_plate(
                    theme,
                    40.0,
                    crate::icons::glyph_view("note", 20.0, theme.text_dim),
                ),
                column![
                    text(title.chars().take(28).collect::<String>())
                        .size(13)
                        .font(semibold())
                        .color(theme.text),
                    text(p.artist.chars().take(32).collect::<String>())
                        .size(11)
                        .color(theme.text_dim),
                ]
                .spacing(1)
                .width(Length::Fill),
                proteus_ui::widgets::circle_button(
                    theme,
                    28.0,
                    proteus_ui::widgets::CircleStyle::Ghost,
                    crate::icons::glyph_view("prev", 12.0, theme.text),
                    Some(Message::MediaPrev(bus.clone())),
                ),
                proteus_ui::widgets::circle_button(
                    theme,
                    28.0,
                    proteus_ui::widgets::CircleStyle::Ghost,
                    crate::icons::glyph_view(
                        if p.playing { "pause" } else { "play" },
                        12.0,
                        theme.text,
                    ),
                    Some(Message::MediaPlayPause(bus.clone())),
                ),
                proteus_ui::widgets::circle_button(
                    theme,
                    28.0,
                    proteus_ui::widgets::CircleStyle::Ghost,
                    crate::icons::glyph_view("next", 12.0, theme.text),
                    Some(Message::MediaNext(bus)),
                ),
            ]
            .spacing(8)
            .align_y(Alignment::Center),
        )
    } else {
        Space::new().height(Length::Fixed(0.0)).into()
    };

    // ---- Sliders — brightness / volume (icon disc + accent slider + %) -----
    let slider_row = |glyph: &'static str,
                      value: Option<u8>,
                      on_change: fn(f32) -> Message|
     -> Element<'a, Message> {
        let v = value.unwrap_or(0) as f32;
        row![
            container(crate::icons::glyph_view(glyph, 15.0, theme.text_dim))
                .width(Length::Fixed(30.0))
                .height(Length::Fixed(30.0))
                .align_x(Alignment::Center)
                .align_y(Alignment::Center)
                .style({
                    let fill = theme.accent_soft;
                    move |_t| container::Style {
                        background: Some(Background::Color(fill)),
                        border: Border {
                            radius: 15.0.into(),
                            ..Default::default()
                        },
                        ..Default::default()
                    }
                }),
            proteus_ui::widgets::theme_slider(theme, 0.0..=100.0, v, on_change),
            text(format!("{:.0}%", v))
                .size(12)
                .color(theme.text_dim)
                .width(Length::Fixed(38.0)),
        ]
        .spacing(10)
        .align_y(Alignment::Center)
        .into()
    };
    let sliders = chrome_tile(
        theme,
        column![
            slider_row("sun", brightness, |v| Message::BrightnessSet(v as u8)),
            slider_row("volume", volume, |v| Message::VolumeSet(v as u8)),
        ]
        .spacing(10),
    );

    // ---- Toggle tiles — DND / Focus (icon disc + label + switch) ------------
    let toggle_tile = |glyph: &'static str,
                       label: &'a str,
                       on: bool,
                       msg: Message|
     -> Element<'a, Message> {
        let disc = if on { theme.accent } else { theme.bg_hover };
        let glyph_c = if on {
            proteus_ui::theme::contrasting_text(theme.accent)
        } else {
            theme.text_dim
        };
        chrome_tile(
            theme,
            row![
                container(crate::icons::glyph_view(glyph, 15.0, glyph_c))
                    .width(Length::Fixed(30.0))
                    .height(Length::Fixed(30.0))
                    .align_x(Alignment::Center)
                    .align_y(Alignment::Center)
                    .style(move |_t| container::Style {
                        background: Some(Background::Color(disc)),
                        border: Border {
                            radius: 15.0.into(),
                            ..Default::default()
                        },
                        ..Default::default()
                    }),
                text(label)
                    .size(13)
                    .font(semibold())
                    .color(theme.text)
                    .width(Length::Fill),
                proteus_ui::widgets::theme_switch(theme, on, {
                    let msg = msg.clone();
                    move |_| msg.clone()
                }),
            ]
            .spacing(10)
            .align_y(Alignment::Center),
        )
    };
    // Large CC module — glyph disc + label + trailing switch (2-col grid).
    let module_tile = |glyph: &'static str,
                       label: &'a str,
                       sub: String,
                       on: bool,
                       msg: Message|
     -> Element<'a, Message> {
        let disc = if on { theme.accent } else { theme.bg_hover };
        let glyph_c = if on {
            proteus_ui::theme::contrasting_text(theme.accent)
        } else {
            theme.text_dim
        };
        chrome_tile(
            theme,
            column![
                row![
                    container(crate::icons::glyph_view(glyph, 16.0, glyph_c))
                        .width(Length::Fixed(34.0))
                        .height(Length::Fixed(34.0))
                        .align_x(Alignment::Center)
                        .align_y(Alignment::Center)
                        .style(move |_t| container::Style {
                            background: Some(Background::Color(disc)),
                            border: Border {
                                radius: 17.0.into(),
                                ..Default::default()
                            },
                            ..Default::default()
                        }),
                    Space::new().width(Length::Fill),
                    proteus_ui::widgets::theme_switch(theme, on, {
                        let msg = msg.clone();
                        move |_| msg.clone()
                    }),
                ]
                .align_y(Alignment::Center),
                text(label)
                    .size(13)
                    .font(semibold())
                    .color(theme.text),
                text(sub).size(11).color(theme.text_mute),
            ]
            .spacing(6),
        )
    };

    let wifi_active = wifi.iter().find(|w| w.active).map(|w| w.ssid.as_str());
    let wifi_sub = if !wifi_on {
        "Off".into()
    } else if let Some(ssid) = wifi_active {
        ssid.chars().take(18).collect()
    } else {
        "Not connected".into()
    };
    let bt_sub = if !bt_on {
        "Off".into()
    } else if let Some(b) = bt.iter().find(|b| b.connected) {
        b.name.chars().take(18).collect()
    } else {
        "Not connected".into()
    };

    let modules = column![
        row![
            module_tile(
                "wifi",
                "Wi-Fi",
                wifi_sub,
                wifi_on,
                Message::WifiRadioToggle
            ),
            module_tile(
                "bluetooth",
                "Bluetooth",
                bt_sub,
                bt_on,
                Message::BtRadioToggle
            ),
        ]
        .spacing(theme.space_sm),
        row![
            module_tile(
                "moon",
                "Do Not Disturb",
                if dnd { "On".into() } else { "Off".into() },
                dnd,
                Message::ToggleDnd
            ),
            module_tile(
                "focus",
                "Focus",
                if focus_on {
                    "On".into()
                } else {
                    "Off".into()
                },
                focus_on,
                Message::ToggleFocus
            ),
        ]
        .spacing(theme.space_sm),
    ]
    .spacing(theme.space_sm);

    // Focus profile chips (soft-accent active pill).
    let mut focus_chips = row![].spacing(6);
    for p in focus_profiles.iter().take(4) {
        let id = p.id.clone();
        let active = p.id == focus_active_id;
        let accent = theme.accent;
        let accent_soft = theme.accent_soft;
        let hover = theme.bg_hover;
        let dim = theme.text_dim;
        focus_chips = focus_chips.push(
            button(
                text(p.name.clone())
                    .size(11)
                    .color(if active { accent } else { dim }),
            )
            .padding(Padding::new(4.0).left(10.0).right(10.0))
            .style(move |_t, status| button::Style {
                background: Some(Background::Color(if active {
                    accent_soft
                } else {
                    match status {
                        button::Status::Hovered | button::Status::Pressed => hover,
                        _ => Color::TRANSPARENT,
                    }
                })),
                text_color: if active { accent } else { dim },
                border: Border {
                    radius: 11.0.into(),
                    ..Default::default()
                },
                ..Default::default()
            })
            .on_press(Message::FocusProfile(id)),
        );
    }
    let focus_section: Element<'a, Message> = if focus_profiles.is_empty() {
        Space::new().height(Length::Fixed(0.0)).into()
    } else {
        focus_chips.into()
    };

    // ---- Power profile ------------------------------------------------------
    let profile_idx = crate::platform::power_profile_index(&power.profile);
    let power_tile = chrome_tile(
        theme,
        column![
            row![
                crate::icons::glyph_view("power", 13.0, theme.text_dim),
                text("Power").size(12).color(theme.text_dim),
            ]
            .spacing(6)
            .align_y(Alignment::Center),
            segmented_control(
                theme,
                &["Performance", "Balanced", "Power saver"],
                profile_idx,
                Message::PowerProfile,
            ),
        ]
        .spacing(theme.space_sm),
    );

    // ---- Networks / Bluetooth ------------------------------------------------
    let radio_row = |label: String, sub: String, active: bool, msg: Message| {
        let accent = theme.accent;
        let hover = theme.bg_hover;
        let text_c = if active { accent } else { theme.text };
        let mut labels = row![text(label).size(12).color(text_c).width(Length::Fill)]
            .spacing(6)
            .align_y(Alignment::Center);
        if !sub.is_empty() {
            labels = labels.push(text(sub).size(11).color(theme.text_mute));
        }
        button(labels)
            .width(Length::Fill)
            .padding(Padding::new(6.0).left(8.0).right(8.0))
            .style(move |_t, status| button::Style {
                background: match status {
                    button::Status::Hovered | button::Status::Pressed => {
                        Some(Background::Color(hover))
                    }
                    _ => None,
                },
                text_color: text_c,
                border: Border {
                    radius: 8.0.into(),
                    ..Default::default()
                },
                ..Default::default()
            })
            .on_press(msg)
    };

    let wifi_header = row![
        crate::icons::glyph_view("wifi", 13.0, theme.text_dim),
        text("Wi-Fi").size(12).color(theme.text_dim).width(Length::Fill),
        proteus_ui::widgets::theme_switch(theme, wifi_on, |_| Message::WifiRadioToggle),
        button(text("↻").size(12))
            .padding(4)
            .style(theme.ghost_button_style())
            .on_press(Message::CcRefresh),
        button(text("…").size(12))
            .padding(4)
            .style(theme.ghost_button_style())
            .on_press(Message::OpenSettingsPage("network-wifi".into())),
    ]
    .spacing(6)
    .align_y(Alignment::Center);
    let mut wifi_col = column![wifi_header].spacing(4);
    if !wifi_err.is_empty() {
        wifi_col = wifi_col.push(text(wifi_err.to_string()).size(11).color(theme.danger));
    }
    if wifi_on {
        for w in wifi.iter().take(5) {
            wifi_col = wifi_col.push(radio_row(
                w.ssid.clone(),
                format!("{}%", w.signal),
                w.active,
                Message::WifiConnect(w.ssid.clone()),
            ));
        }
        if wifi.is_empty() {
            wifi_col = wifi_col.push(text("No networks").size(11).color(theme.text_mute));
        }
    } else {
        wifi_col = wifi_col.push(text("Wi-Fi off").size(11).color(theme.text_mute));
    }

    let bt_header = row![
        crate::icons::glyph_view("bluetooth", 13.0, theme.text_dim),
        text("Bluetooth")
            .size(12)
            .color(theme.text_dim)
            .width(Length::Fill),
        proteus_ui::widgets::theme_switch(theme, bt_on, |_| Message::BtRadioToggle),
        button(text("…").size(12))
            .padding(4)
            .style(theme.ghost_button_style())
            .on_press(Message::OpenSettingsPage("network-bluetooth".into())),
    ]
    .spacing(6)
    .align_y(Alignment::Center);
    let mut bt_col = column![bt_header].spacing(4);
    if !bt_err.is_empty() {
        bt_col = bt_col.push(text(bt_err.to_string()).size(11).color(theme.danger));
    }
    if bt_on {
        for b in bt.iter().take(5) {
            bt_col = bt_col.push(radio_row(
                b.name.clone(),
                String::new(),
                b.connected,
                Message::BtConnect(b.mac.clone()),
            ));
        }
        if bt.is_empty() {
            bt_col = bt_col.push(text("No devices").size(11).color(theme.text_mute));
        }
    } else {
        bt_col = bt_col.push(text("Bluetooth off").size(11).color(theme.text_mute));
    }

    let appearance_idx = if theme.mode == proteus_ui::theme::ChromeMode::Light {
        1
    } else {
        0
    };
    let appearance_tile = chrome_tile(
        theme,
        column![
            row![
                crate::icons::glyph_view("cc", 13.0, theme.text_dim),
                text("Appearance").size(12).color(theme.text_dim),
            ]
            .spacing(6)
            .align_y(Alignment::Center),
            segmented_control(
                theme,
                &["Dark", "Light"],
                appearance_idx,
                Message::AppearanceMode,
            ),
        ]
        .spacing(theme.space_sm),
    );

    let mute_on = volume == Some(0);
    let mute_tile = toggle_tile(
        "volume",
        if mute_on { "Muted" } else { "Mute" },
        mute_on,
        Message::VolumeMute,
    );

    let shot_row = row![
        button(text("Region").size(12))
            .padding(Padding::new(6.0).left(12.0).right(12.0))
            .style(theme.ghost_button_style())
            .on_press(Message::Screenshot("region".into())),
        button(text("Screen").size(12))
            .padding(Padding::new(6.0).left(12.0).right(12.0))
            .style(theme.ghost_button_style())
            .on_press(Message::Screenshot("screen".into())),
    ]
    .spacing(4);
    let shot_tile = chrome_tile(
        theme,
        column![
            row![
                crate::icons::glyph_view("screen", 13.0, theme.text_dim),
                text("Screenshot").size(12).color(theme.text_dim),
            ]
            .spacing(6)
            .align_y(Alignment::Center),
            shot_row,
        ]
        .spacing(theme.space_sm),
    );

    // ---- Shortcuts row -------------------------------------------------------
    let shortcut = |label: &'a str, msg: Message| {
        button(text(label).size(12))
            .padding(Padding::new(6.0).left(12.0).right(12.0))
            .style(theme.ghost_button_style())
            .on_press(msg)
    };
    let shortcuts = row![
        shortcut("Settings", Message::OpenSettings),
        shortcut("Network", Message::OpenSettingsPage("network-wifi".into())),
        shortcut("Display", Message::OpenSettingsPage("displays".into())),
        shortcut("Workloads", Message::OpenWorkloads),
    ]
    .spacing(4);

    let _ = chrome; // reserved for future CC chrome flags

    // Apple-like CC: 2-col modules → sliders → media → secondary tiles.
    let secondary = row![appearance_tile, mute_tile]
        .spacing(theme.space_sm);
    let shot_power = row![shot_tile, power_tile]
        .spacing(theme.space_sm);

    let panel_body = column![
        modules,
        sliders,
        media_card,
        focus_section,
        secondary,
        shot_power,
        chrome_tile(theme, wifi_col),
        chrome_tile(theme, bt_col),
        shortcuts,
    ]
    .spacing(theme.space_sm);

    // ---- Panel — ~380 wide for 2-col modules; scrim closes ------------------
    let panel_fill = if theme.mode == proteus_ui::theme::ChromeMode::Dark {
        proteus_ui::theme::fade(theme.bg_panel, 0.90)
    } else {
        proteus_ui::theme::fade(theme.bg_panel, 0.96)
    };
    let panel_border = theme.hairline;
    let panel = container(scrollable(panel_body).height(Length::Shrink))
        .width(Length::Fixed(380.0))
        .max_height(760.0)
        .padding(theme.space_md)
        .style(move |_t| container::Style {
            background: Some(Background::Color(panel_fill)),
            border: Border {
                radius: 16.0.into(),
                width: 1.0,
                color: panel_border,
            },
            ..Default::default()
        });

    // Open motion (200ms OutCubic): slide down 14px + scrim fade.
    let t = open_t.clamp(0.0, 1.0);
    let scrim = proteus_ui::theme::fade(theme.scrim, theme.scrim.a * 0.6 * t);
    let top_pad = 44.0 - 14.0 * (1.0 - t);
    let scrim_button = button(Space::new().width(Length::Fill).height(Length::Fill))
        .padding(0)
        .style(|_t, _s| button::Style {
            background: None,
            text_color: Color::TRANSPARENT,
            border: Border::default(),
            ..Default::default()
        })
        .on_press(Message::ToggleControlCenter);

    container(iced::widget::stack![
        scrim_button,
        container(panel)
            .width(Length::Fill)
            .height(Length::Fill)
            .align_x(Alignment::End)
            .padding(Padding::new(0.0).top(top_pad).right(12.0)),
    ])
    .width(Length::Fill)
    .height(Length::Fill)
    .style(move |_t| container::Style {
        background: Some(Background::Color(scrim)),
        ..Default::default()
    })
    .into()
}

/// Center menu-bar hub — Calendar | Notifications tabs (not Control Center).
pub fn center_hub_view<'a>(
    theme: &'a Theme,
    chrome: &'a ChromeState,
    notifs: &'a [Notification],
    open_t: f32,
) -> Element<'a, Message> {
    let notif_tab = chrome.notifications_open;
    let tab_bar = segmented_control(
        theme,
        &["Calendar", "Notifications"],
        if notif_tab { 1 } else { 0 },
        Message::CenterTab,
    );

    let body: Element<'a, Message> = if notif_tab {
        let mut nlist = column![].spacing(6);
        for n in notifs.iter().rev().take(12) {
            let id = n.id;
            let card_bg = proteus_ui::theme::fade(theme.bg_elevated, 0.85);
            let hairline = theme.hairline;
            let mut body_col = column![
                text(n.app_name.clone()).size(11).color(theme.text_dim),
                text(n.summary.clone())
                    .size(13)
                    .font(semibold())
                    .color(theme.text),
            ]
            .spacing(2);
            if !n.body.is_empty() {
                body_col = body_col.push(
                    text(n.body.chars().take(120).collect::<String>())
                        .size(12)
                        .color(theme.text_mute),
                );
            }
            nlist = nlist.push(
                container(
                    row![
                        body_col.width(Length::Fill),
                        proteus_ui::widgets::circle_button(
                            theme,
                            18.0,
                            proteus_ui::widgets::CircleStyle::Ghost,
                            crate::icons::glyph_view("close", 9.0, theme.text_mute),
                            Some(Message::NotifDismiss(id)),
                        ),
                    ]
                    .spacing(8)
                    .align_y(Alignment::Center),
                )
                .padding(10)
                .width(Length::Fill)
                .style(move |_t| container::Style {
                    background: Some(Background::Color(card_bg)),
                    border: Border {
                        radius: 12.0.into(),
                        width: 1.0,
                        color: hairline,
                    },
                    ..Default::default()
                }),
            );
        }
        let list: Element<'a, Message> = if notifs.is_empty() {
            container(
                text("No notifications")
                    .size(12)
                    .color(theme.text_mute),
            )
            .width(Length::Fill)
            .padding(24)
            .align_x(Alignment::Center)
            .into()
        } else {
            scrollable(nlist).height(Length::Fixed(360.0)).into()
        };
        column![
            row![
                text("Notifications")
                    .size(13)
                    .font(semibold())
                    .color(theme.text)
                    .width(Length::Fill),
                button(text("Clear").size(11))
                    .padding(Padding::new(4.0).left(10.0).right(10.0))
                    .style(theme.ghost_button_style())
                    .on_press(Message::NotifClearAll),
            ]
            .align_y(Alignment::Center),
            list,
        ]
        .spacing(8)
        .into()
    } else {
        calendar_month_view(theme).into()
    };

    let panel_fill = if theme.mode == proteus_ui::theme::ChromeMode::Dark {
        proteus_ui::theme::fade(theme.bg_panel, 0.90)
    } else {
        proteus_ui::theme::fade(theme.bg_panel, 0.96)
    };
    let panel_border = theme.hairline;
    let panel = container(
        column![tab_bar, body].spacing(theme.space_md),
    )
    .width(Length::Fixed(380.0))
    .max_height(520.0)
    .padding(theme.space_md)
    .style(move |_t| container::Style {
        background: Some(Background::Color(panel_fill)),
        border: Border {
            radius: 16.0.into(),
            width: 1.0,
            color: panel_border,
        },
        ..Default::default()
    });

    let t = open_t.clamp(0.0, 1.0);
    let scrim = proteus_ui::theme::fade(theme.scrim, theme.scrim.a * 0.45 * t);
    let top_pad = 44.0 - 10.0 * (1.0 - t);
    let scrim_button = button(Space::new().width(Length::Fill).height(Length::Fill))
        .padding(0)
        .style(|_t, _s| button::Style {
            background: None,
            text_color: Color::TRANSPARENT,
            border: Border::default(),
            ..Default::default()
        })
        .on_press(Message::CloseCenterHub);

    container(iced::widget::stack![
        scrim_button,
        container(panel)
            .width(Length::Fill)
            .height(Length::Fill)
            .align_x(Alignment::Center)
            .padding(Padding::new(0.0).top(top_pad)),
    ])
    .width(Length::Fill)
    .height(Length::Fill)
    .style(move |_t| container::Style {
        background: Some(Background::Color(scrim)),
        ..Default::default()
    })
    .into()
}

fn calendar_month_view(theme: &Theme) -> Element<'_, Message> {
    use chrono::{Datelike, Local};
    let now = Local::now();
    let year = now.year();
    let month = now.month();
    let today = now.day();
    let first = chrono::NaiveDate::from_ymd_opt(year, month, 1).unwrap_or(now.date_naive());
    let start_wd = first.weekday().num_days_from_sunday() as i32; // 0=Sun
    let days_in_month = match month {
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        4 | 6 | 9 | 11 => 30,
        2 if year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) => 29,
        2 => 28,
        _ => 30,
    };
    let title = now.format("%B %Y").to_string();
    let mut grid = column![].spacing(4);
    let mut hdr = row![].spacing(4);
    for d in ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"] {
        hdr = hdr.push(
            container(text(d).size(11).color(theme.text_mute))
                .width(Length::Fixed(36.0))
                .align_x(Alignment::Center),
        );
    }
    grid = grid.push(hdr);
    let mut day = 1i32;
    for week in 0..6 {
        if day > days_in_month {
            break;
        }
        let mut row_el = row![].spacing(4);
        for col in 0..7 {
            let cell_idx = week * 7 + col;
            if cell_idx < start_wd || day > days_in_month {
                row_el = row_el.push(Space::new().width(Length::Fixed(36.0)).height(28.0));
            } else {
                let is_today = day as u32 == today;
                let label = text(format!("{day}"))
                    .size(12)
                    .color(if is_today {
                        proteus_ui::theme::contrasting_text(theme.accent)
                    } else {
                        theme.text
                    });
                let accent = theme.accent;
                let cell = container(label)
                    .width(Length::Fixed(36.0))
                    .height(Length::Fixed(28.0))
                    .align_x(Alignment::Center)
                    .align_y(Alignment::Center)
                    .style(move |_t| container::Style {
                        background: if is_today {
                            Some(Background::Color(accent))
                        } else {
                            None
                        },
                        border: Border {
                            radius: 14.0.into(),
                            ..Default::default()
                        },
                        ..Default::default()
                    });
                row_el = row_el.push(cell);
                day += 1;
            }
        }
        grid = grid.push(row_el);
    }
    column![
        row![
            crate::icons::glyph_view("calendar", 14.0, theme.text_dim),
            text(title).size(14).font(semibold()).color(theme.text),
        ]
        .spacing(8)
        .align_y(Alignment::Center),
        text(now.format("%A · %-d %B").to_string())
            .size(12)
            .color(theme.text_dim),
        grid,
    ]
    .spacing(10)
    .into()
}

/// Weather glance popover (center cluster chip).
pub fn weather_glance_view<'a>(
    theme: &'a Theme,
    weather: &'a crate::platform::WeatherGlance,
    open_t: f32,
) -> Element<'a, Message> {
    let body = if !weather.enabled {
        column![
            text("Weather muted").size(13).color(theme.text_dim),
            text("Enable in Privacy & security")
                .size(11)
                .color(theme.text_mute),
            button(text("Open Privacy").size(12))
                .padding(Padding::new(6.0).left(12.0).right(12.0))
                .style(theme.ghost_button_style())
                .on_press(Message::OpenSettingsPage("privacy-activity".into())),
        ]
        .spacing(8)
    } else if !weather.has_location {
        column![
            text("No location").size(13).color(theme.text_dim),
            text(weather.error.clone()).size(11).color(theme.text_mute),
            button(text("Open Weather settings").size(12))
                .padding(Padding::new(6.0).left(12.0).right(12.0))
                .style(theme.ghost_button_style())
                .on_press(Message::OpenSettingsPage("datetime".into())),
        ]
        .spacing(8)
    } else {
        column![
            text(if weather.name.is_empty() {
                "Weather".into()
            } else {
                weather.name.clone()
            })
            .size(13)
            .font(semibold())
            .color(theme.text),
            text(weather.temp_label.clone())
                .size(28)
                .font(semibold())
                .color(theme.text),
            text(if weather.condition.is_empty() {
                weather.error.clone()
            } else {
                weather.condition.clone()
            })
            .size(12)
            .color(theme.text_dim),
            button(text("Open Weather").size(12))
                .padding(Padding::new(6.0).left(12.0).right(12.0))
                .style(theme.ghost_button_style())
                .on_press(Message::OpenSettingsPage("datetime".into())),
        ]
        .spacing(6)
    };

    let panel_fill = proteus_ui::theme::fade(theme.bg_panel, 0.92);
    let panel_border = theme.hairline;
    let panel = container(body)
        .width(Length::Fixed(280.0))
        .padding(theme.space_md)
        .style(move |_t| container::Style {
            background: Some(Background::Color(panel_fill)),
            border: Border {
                radius: 16.0.into(),
                width: 1.0,
                color: panel_border,
            },
            ..Default::default()
        });

    let t = open_t.clamp(0.0, 1.0);
    let scrim = proteus_ui::theme::fade(theme.scrim, theme.scrim.a * 0.4 * t);
    let top_pad = 44.0 - 10.0 * (1.0 - t);
    let scrim_button = button(Space::new().width(Length::Fill).height(Length::Fill))
        .padding(0)
        .style(|_t, _s| button::Style {
            background: None,
            text_color: Color::TRANSPARENT,
            border: Border::default(),
            ..Default::default()
        })
        .on_press(Message::CloseCenterHub);

    container(iced::widget::stack![
        scrim_button,
        container(panel)
            .width(Length::Fill)
            .height(Length::Fill)
            .align_x(Alignment::Center)
            .padding(Padding::new(0.0).top(top_pad)),
    ])
    .width(Length::Fill)
    .height(Length::Fill)
    .style(move |_t| container::Style {
        background: Some(Background::Color(scrim)),
        ..Default::default()
    })
    .into()
}

/// Status HUD — 196×56 chip: icon plate, kind label, 4px meter, value
/// (QML StatusHud parity). `t` is the fade progress 0→1.
pub fn hud_view<'a>(theme: &'a Theme, chrome: &'a ChromeState, t: f32) -> Element<'a, Message> {
    let t = t.clamp(0.0, 1.0);
    let kind = chrome.hud_kind.as_str();
    let glyph = match kind {
        "volume" | "mute" => "volume",
        "brightness" => "sun",
        _ => "dot",
    };
    let value = chrome.hud_value.clamp(0.0, 100.0);

    let icon_plate = container(crate::icons::glyph_view(
        glyph,
        14.0,
        proteus_ui::theme::fade(theme.accent, t),
    ))
    .width(Length::Fixed(28.0))
    .height(Length::Fixed(28.0))
    .align_x(Alignment::Center)
    .align_y(Alignment::Center)
    .style({
        let fill = proteus_ui::theme::fade(theme.accent_soft, theme.accent_soft.a * t);
        move |_t| container::Style {
            background: Some(Background::Color(fill)),
            border: Border {
                radius: 10.0.into(),
                ..Default::default()
            },
            ..Default::default()
        }
    });

    // 4px meter — proportional accent fill + dim track.
    let track_c = proteus_ui::theme::fade(theme.bg_hover, 0.9 * t);
    let fill_c = proteus_ui::theme::fade(theme.accent, t);
    let filled = value.round().max(0.0) as u16;
    let empty = (100u16).saturating_sub(filled);
    let mut meter_row = row![].spacing(0);
    meter_row = meter_row.push(
        container(
            Space::new()
                .width(Length::FillPortion(filled.max(1)))
                .height(Length::Fixed(4.0)),
        )
        .style(move |_t| container::Style {
            background: Some(Background::Color(fill_c)),
            border: Border {
                radius: 2.0.into(),
                ..Default::default()
            },
            ..Default::default()
        }),
    );
    if empty > 0 {
        meter_row = meter_row.push(
            container(
                Space::new()
                    .width(Length::FillPortion(empty))
                    .height(Length::Fixed(4.0)),
            )
            .style(move |_t| container::Style {
                background: Some(Background::Color(track_c)),
                border: Border {
                    radius: 2.0.into(),
                    ..Default::default()
                },
                ..Default::default()
            }),
        );
    }

    let label = if kind.is_empty() { "status" } else { kind };
    let body = row![
        icon_plate,
        column![
            text(label.to_string())
                .size(11)
                .color(proteus_ui::theme::fade(theme.text_dim, t)),
            meter_row,
        ]
        .spacing(6)
        .width(Length::Fill),
        text(format!("{value:.0}%"))
            .size(13)
            .font(semibold())
            .color(proteus_ui::theme::fade(theme.text, t)),
    ]
    .spacing(10)
    .align_y(Alignment::Center);

    let chip_fill = proteus_ui::theme::fade(
        theme.bg_elevated,
        (if theme.mode == proteus_ui::theme::ChromeMode::Dark {
            0.88
        } else {
            0.94
        }) * t,
    );
    let chip_border = proteus_ui::theme::fade(theme.border, 0.5 * t);
    let chip = button(
        container(body)
            .width(Length::Fixed(196.0))
            .height(Length::Fixed(56.0))
            .padding(Padding::new(10.0).left(12.0).right(14.0))
            .style(move |_t| container::Style {
                background: Some(Background::Color(chip_fill)),
                border: Border {
                    radius: 16.0.into(),
                    width: 1.0,
                    color: chip_border,
                },
                ..Default::default()
            }),
    )
    .padding(0)
    .on_press(Message::HudDismiss)
    .style(|_t, _s| button::Style {
        background: None,
        border: Border::default(),
        text_color: Color::TRANSPARENT,
        ..Default::default()
    });

    // Right-align within the HUD layer strip.
    container(chip)
        .width(Length::Fill)
        .height(Length::Fill)
        .align_x(Alignment::End)
        .align_y(Alignment::Start)
        .into()
}

/// Notification toast — elevated card, radius 16, app chip + summary/body,
/// ghost dismiss. `t` is the fade progress 0→1 (auto-hide fades out).
pub fn toast_view<'a>(theme: &'a Theme, n: &'a Notification, t: f32) -> Element<'a, Message> {
    let t = t.clamp(0.0, 1.0);
    let id = n.id;
    let app_chip = container(
        text(
            n.app_name
                .chars()
                .next()
                .map(|c| c.to_uppercase().to_string())
                .unwrap_or_else(|| "•".into()),
        )
        .size(10)
        .font(semibold())
        .color(proteus_ui::theme::fade(theme.accent, t)),
    )
    .width(Length::Fixed(18.0))
    .height(Length::Fixed(18.0))
    .align_x(Alignment::Center)
    .align_y(Alignment::Center)
    .style({
        let fill = proteus_ui::theme::fade(theme.accent_soft, theme.accent_soft.a * t);
        move |_t| container::Style {
            background: Some(Background::Color(fill)),
            border: Border {
                radius: 5.0.into(),
                ..Default::default()
            },
            ..Default::default()
        }
    });

    let mut body_col = column![
        row![
            app_chip,
            text(n.app_name.as_str())
                .size(11)
                .color(proteus_ui::theme::fade(theme.text_dim, t)),
        ]
        .spacing(6)
        .align_y(Alignment::Center),
        text(n.summary.as_str())
            .size(13)
            .font(semibold())
            .color(proteus_ui::theme::fade(theme.text, t)),
    ]
    .spacing(4);
    if !n.body.is_empty() {
        body_col = body_col.push(
            text(n.body.chars().take(120).collect::<String>())
                .size(12)
                .color(proteus_ui::theme::fade(theme.text_mute, t)),
        );
    }

    let card_fill = proteus_ui::theme::fade(
        theme.bg_elevated,
        (if theme.mode == proteus_ui::theme::ChromeMode::Dark {
            0.88
        } else {
            0.94
        }) * t,
    );
    let card_border = proteus_ui::theme::fade(theme.border, 0.5 * t);
    let card = container(
        row![
            body_col.width(Length::Fill),
            proteus_ui::widgets::circle_button(
                theme,
                18.0,
                proteus_ui::widgets::CircleStyle::Ghost,
                crate::icons::glyph_view(
                    "close",
                    9.0,
                    proteus_ui::theme::fade(theme.text_mute, t)
                ),
                Some(Message::ToastDismiss(id)),
            ),
        ]
        .spacing(8),
    )
    .width(Length::Fixed(340.0))
    .padding(12)
    .style(move |_t| container::Style {
        background: Some(Background::Color(card_fill)),
        border: Border {
            radius: 16.0.into(),
            width: 1.0,
            color: card_border,
        },
        ..Default::default()
    });

    // Right-align within the toast layer strip.
    container(card)
        .width(Length::Fill)
        .align_x(Alignment::End)
        .into()
}

pub fn privacy_ask_view<'a>(theme: &'a Theme, category: &'a str) -> Element<'a, Message> {
    // Category icon disc in its semantic privacy color.
    let (glyph, color) = match category {
        "mic" | "microphone" => ("mic", theme.privacy_mic),
        "camera" | "cam" => ("camera", theme.privacy_cam),
        "screen" | "screenshare" => ("screen", theme.privacy_screen),
        _ => ("dot", theme.accent),
    };
    let disc = container(crate::icons::glyph_view(glyph, 18.0, color))
        .width(Length::Fixed(40.0))
        .height(Length::Fixed(40.0))
        .align_x(Alignment::Center)
        .align_y(Alignment::Center)
        .style({
            let fill = proteus_ui::theme::fade(color, 0.16);
            move |_t| container::Style {
                background: Some(Background::Color(fill)),
                border: Border {
                    radius: 20.0.into(),
                    ..Default::default()
                },
                ..Default::default()
            }
        });

    let card = glass_plate(
        theme,
        column![
            row![
                disc,
                column![
                    text("Privacy")
                        .size(14)
                        .font(semibold())
                        .color(theme.text),
                    text(format!("Allow {category} access?"))
                        .size(13)
                        .color(theme.text_dim),
                ]
                .spacing(2),
            ]
            .spacing(12)
            .align_y(Alignment::Center),
            row![
                button(text("Deny").size(13))
                    .on_press(Message::PrivacyDeny)
                    .padding(Padding::new(8.0).left(20.0).right(20.0))
                    .style(theme.ghost_button_style()),
                button(text("Allow").size(13))
                    .on_press(Message::PrivacyAllow)
                    .padding(Padding::new(8.0).left(20.0).right(20.0))
                    .style(theme.accent_button_style()),
            ]
            .spacing(8),
        ]
        .spacing(14),
    );

    container(card)
        .width(Length::Fill)
        .height(Length::Fill)
        .align_x(Alignment::Center)
        .align_y(Alignment::Center)
        .into()
}

/// Opaque lock floor — wallpaper (or solid) painted *into* the Overlay surface
/// so windows under the lock cannot peek through a translucent scrim.
fn lock_backdrop<'a>(
    theme: &'a Theme,
    wp: &'a crate::platform::WallpaperState,
    handle: Option<&'a iced::widget::image::Handle>,
) -> Element<'a, Message> {
    let color = parse_wallpaper_color(&wp.color, theme.bg);
    // Force opaque — layer clear color is transparent; floor must seal the desktop.
    let floor = Color {
        r: color.r,
        g: color.g,
        b: color.b,
        a: 1.0,
    };
    if let Some(h) = handle {
        let fit = match wp.mode.as_str() {
            "fit" => iced::ContentFit::Contain,
            "stretch" => iced::ContentFit::Fill,
            "center" => iced::ContentFit::None,
            _ => iced::ContentFit::Cover,
        };
        container(
            iced::widget::image(h.clone())
                .width(Length::Fill)
                .height(Length::Fill)
                .content_fit(fit),
        )
        .width(Length::Fill)
        .height(Length::Fill)
        .clip(true)
        .style(move |_t| container::Style {
            background: Some(Background::Color(floor)),
            ..Default::default()
        })
        .into()
    } else {
        container(Space::new().width(Length::Fill).height(Length::Fill))
            .width(Length::Fill)
            .height(Length::Fill)
            .style(move |_t| container::Style {
                background: Some(Background::Color(floor)),
                ..Default::default()
            })
            .into()
    }
}

/// Full-bleed lock overlay — opaque wallpaper floor + shared lock UI.
/// Maps [`crate::lock_ui`] into shell messages.
pub fn lock_view<'a>(
    theme: &'a Theme,
    st: &'a crate::lock_ui::LockUiState,
    wp: &'a crate::platform::WallpaperState,
    handle: Option<&'a iced::widget::image::Handle>,
) -> Element<'a, Message> {
    use crate::lock_ui::LockMsg;
    let ui = crate::lock_ui::lock_screen_view(theme, st).map(|m| match m {
        LockMsg::Reveal => Message::LockReveal,
        LockMsg::PinDigit(c) => Message::LockPinDigit(c),
        LockMsg::PinBackspace => Message::LockPinBackspace,
        LockMsg::PinClear => Message::LockPinClear,
        LockMsg::UsePassword => Message::LockUsePassword,
        LockMsg::UsePin => Message::LockUsePin,
        LockMsg::PinEntry(s) => Message::PinEntry(s),
        LockMsg::Unlock => Message::Unlock,
        LockMsg::CustomizeAdd(k) => Message::LockCustomizeAdd(k),
        LockMsg::CustomizeRemove(id) => Message::LockCustomizeRemove(id),
        LockMsg::CustomizeMove(id, d) => Message::LockCustomizeMove(id, d),
        LockMsg::CustomizeDone => Message::LockCustomizeDone,
    });
    iced::widget::stack![lock_backdrop(theme, wp, handle), ui]
        .width(Length::Fill)
        .height(Length::Fill)
        .into()
}

fn parse_wallpaper_color(hex: &str, fallback: Color) -> Color {
    let s = hex.trim().trim_start_matches('#');
    if s.len() != 6 {
        return fallback;
    }
    let Ok(v) = u32::from_str_radix(s, 16) else {
        return fallback;
    };
    Color::from_rgb8(
        ((v >> 16) & 0xff) as u8,
        ((v >> 8) & 0xff) as u8,
        (v & 0xff) as u8,
    )
}

/// Owned wallpaper — image from settings.json (QS BgConfig parity) with
/// solid-color fallback. Hold empty wallpaper → Customize (via press/release).
pub fn wallpaper_view<'a>(
    theme: &'a Theme,
    wp: &'a crate::platform::WallpaperState,
    handle: Option<&'a iced::widget::image::Handle>,
) -> Element<'a, Message> {
    let under = if let Some(h) = handle {
        let fit = match wp.mode.as_str() {
            "fit" => iced::ContentFit::Contain,
            "stretch" => iced::ContentFit::Fill,
            "center" => iced::ContentFit::None,
            _ => iced::ContentFit::Cover,
        };
        let img = iced::widget::image(h.clone())
            .width(Length::Fill)
            .height(Length::Fill)
            .content_fit(fit);
        let color = parse_wallpaper_color(&wp.color, theme.bg);
        container(img)
            .width(Length::Fill)
            .height(Length::Fill)
            .clip(true)
            .style(move |_t| container::Style {
                background: Some(Background::Color(color)),
                ..Default::default()
            })
    } else {
        let bg = parse_wallpaper_color(&wp.color, theme.bg);
        container(Space::new().width(Length::Fill).height(Length::Fill))
            .width(Length::Fill)
            .height(Length::Fill)
            .style(move |_t| container::Style {
                background: Some(Background::Color(bg)),
                ..Default::default()
            })
    };
    iced::widget::mouse_area(under)
        .on_press(Message::DesktopPress)
        .on_release(Message::DesktopRelease)
        .into()
}

/// Desktop widgets surface — placed cards + Customize chrome.
pub fn desktop_widgets_view<'a>(
    theme: &'a Theme,
    state: &'a crate::desktop_widgets::DesktopWidgetsState,
    gallery: &'a [String],
    customize: bool,
    snap: bool,
    clock: &'a BarClock,
    weather: &'a crate::platform::WeatherGlance,
    power: &'a PowerStatus,
) -> Element<'a, Message> {
    let mut stack = iced::widget::Stack::new()
        .width(Length::Fill)
        .height(Length::Fill);

    // Empty-desktop hold → Customize (same as wallpaper when this layer is Full).
    if !customize {
        let hold = iced::widget::mouse_area(
            Space::new().width(Length::Fill).height(Length::Fill),
        )
        .on_press(Message::DesktopPress)
        .on_release(Message::DesktopRelease);
        stack = stack.push(hold);
    } else {
        // Scrim + chrome bar in Customize.
        let bar = container(
            row![
                text("Customize Desktop")
                    .size(13)
                    .font(semibold())
                    .color(theme.text)
                    .width(Length::Fill),
                button(
                    text(if snap { "Snap: On" } else { "Snap: Off" })
                        .size(11),
                )
                .padding(Padding::new(4.0).left(10.0).right(10.0))
                .style(theme.ghost_button_style())
                .on_press(Message::WidgetSnapToggle),
                button(text("Done").size(12).font(semibold()))
                    .padding(Padding::new(4.0).left(14.0).right(14.0))
                    .style(theme.ghost_button_style())
                    .on_press(Message::WidgetCustomizeDone),
            ]
            .spacing(8)
            .align_y(Alignment::Center),
        )
        .width(Length::Fill)
        .padding(Padding::new(10.0).left(16.0).right(16.0))
        .style(move |_t| container::Style {
            background: Some(Background::Color(proteus_ui::theme::fade(
                theme.bg_panel,
                0.92,
            ))),
            ..Default::default()
        });
        stack = stack.push(
            container(bar)
                .width(Length::Fill)
                .height(Length::Fill)
                .align_y(Alignment::Start)
                .padding(Padding::new(0.0).top(48.0)),
        );

        // Add Widget gallery (bottom strip).
        let mut gallery_row = row![].spacing(8);
        for k in gallery {
            let id = k.clone();
            gallery_row = gallery_row.push(
                button(
                    column![
                        crate::icons::glyph_view(widget_glyph(k), 14.0, theme.text_dim),
                        text(k.as_str()).size(11).color(theme.text),
                    ]
                    .spacing(4)
                    .align_x(Alignment::Center),
                )
                .padding(8)
                .style(theme.ghost_button_style())
                .on_press(Message::WidgetAdd(id)),
            );
        }
        let gallery_panel = container(
            column![
                text("Add Widget").size(12).font(semibold()).color(theme.text_dim),
                scrollable(gallery_row).height(Length::Shrink),
            ]
            .spacing(6),
        )
        .padding(12)
        .width(Length::Fill)
        .style(move |_t| container::Style {
            background: Some(Background::Color(proteus_ui::theme::fade(
                theme.bg_elevated,
                0.9,
            ))),
            border: Border {
                radius: 12.0.into(),
                width: 1.0,
                color: theme.hairline,
            },
            ..Default::default()
        });
        stack = stack.push(
            container(gallery_panel)
                .width(Length::Fill)
                .height(Length::Fill)
                .align_y(Alignment::End)
                .padding(Padding::new(16.0).bottom(96.0).left(24.0).right(24.0)),
        );
    }

    // Alignment guides while dragging.
    for (pos, vertical) in &state.guides {
        let accent = theme.accent;
        let guide = if *vertical {
            container(Space::new().width(1).height(Length::Fill))
                .width(Length::Fixed(1.0))
                .height(Length::Fill)
                .style(move |_t| container::Style {
                    background: Some(Background::Color(accent)),
                    ..Default::default()
                })
        } else {
            container(Space::new().width(Length::Fill).height(1))
                .width(Length::Fill)
                .height(Length::Fixed(1.0))
                .style(move |_t| container::Style {
                    background: Some(Background::Color(accent)),
                    ..Default::default()
                })
        };
        stack = stack.push(
            container(guide)
                .width(Length::Fill)
                .height(Length::Fill)
                .padding(if *vertical {
                    Padding::new(0.0).left(*pos)
                } else {
                    Padding::new(0.0).top(*pos)
                }),
        );
    }

    for w in &state.items {
        let selected = state.selected.as_deref() == Some(w.id.as_str());
        let card = widget_card(theme, w, clock, weather, power, customize, selected);
        stack = stack.push(
            container(card)
                .width(Length::Fill)
                .height(Length::Fill)
                .padding(Padding::new(0.0).left(w.x).top(w.y)),
        );
    }

    container(stack)
        .width(Length::Fill)
        .height(Length::Fill)
        .into()
}

fn widget_glyph(kind: &str) -> &'static str {
    match kind {
        "Clock" | "WorldClock" | "Calendar" => "calendar",
        "Media" | "Notes" => "note",
        "Battery" => "battery",
        "System" => "cc",
        "Weather" => "sun",
        _ => "dot",
    }
}

fn widget_card<'a>(
    theme: &'a Theme,
    w: &'a crate::desktop_widgets::PlacedWidget,
    clock: &'a BarClock,
    weather: &'a crate::platform::WeatherGlance,
    power: &'a PowerStatus,
    customize: bool,
    selected: bool,
) -> Element<'a, Message> {
    let body: Element<'a, Message> = match w.kind.as_str() {
        "Clock" | "WorldClock" => column![
            text(clock.time.clone())
                .size(22)
                .font(semibold())
                .color(theme.text),
            text(clock.date.clone()).size(12).color(theme.text_dim),
        ]
        .spacing(2)
        .into(),
        "Weather" => column![
            text(weather.temp_label.clone())
                .size(22)
                .font(semibold())
                .color(theme.text),
            text(if weather.condition.is_empty() {
                weather.error.clone()
            } else {
                weather.condition.clone()
            })
            .size(11)
            .color(theme.text_dim),
        ]
        .spacing(2)
        .into(),
        "Battery" => column![
            text(if power.percent > 0 {
                format!("{}%", power.percent)
            } else {
                "AC".into()
            })
            .size(20)
            .font(semibold())
            .color(theme.text),
            text(power.profile.clone()).size(11).color(theme.text_dim),
        ]
        .spacing(2)
        .into(),
        "Calendar" => column![
            text(clock.date.clone())
                .size(14)
                .font(semibold())
                .color(theme.text),
            text("Today").size(11).color(theme.text_dim),
        ]
        .spacing(2)
        .into(),
        other => column![
            text(other).size(13).font(semibold()).color(theme.text),
            text("widget").size(11).color(theme.text_mute),
        ]
        .spacing(2)
        .into(),
    };

    let mut inner = column![
        row![
            crate::icons::glyph_view(widget_glyph(&w.kind), 12.0, theme.text_dim),
            text(w.kind.as_str())
                .size(11)
                .color(theme.text_mute)
                .width(Length::Fill),
        ]
        .spacing(6)
        .align_y(Alignment::Center),
        body,
    ]
    .spacing(6);

    if customize {
        let id = w.id.clone();
        inner = inner.push(
            button(text("Remove").size(10))
                .padding(Padding::new(2.0).left(8.0).right(8.0))
                .style(theme.ghost_button_style())
                .on_press(Message::WidgetRemove(id)),
        );
    }

    let border_c = if selected {
        theme.accent
    } else {
        theme.hairline
    };
    let plate = container(inner)
        .width(Length::Fixed(w.w))
        .height(Length::Fixed(w.h))
        .padding(12)
        .style(move |_t| container::Style {
            background: Some(Background::Color(proteus_ui::theme::fade(
                theme.bg_elevated,
                0.88,
            ))),
            border: Border {
                radius: 14.0.into(),
                width: if selected { 2.0 } else { 1.0 },
                color: border_c,
            },
            ..Default::default()
        });

    let id = w.id.clone();
    let kind = w.kind.clone();
    if customize {
        iced::widget::mouse_area(plate)
            .on_press(Message::WidgetDragStart(id))
            .on_move(move |p| Message::WidgetDrag(p.x, p.y))
            .on_release(Message::WidgetDragEnd)
            .into()
    } else {
        button(plate)
            .padding(0)
            .style(|_t, _s| button::Style {
                background: None,
                text_color: Color::TRANSPARENT,
                border: Border::default(),
                ..Default::default()
            })
            .on_press(Message::WidgetActivate(kind))
            .into()
    }
}

/// Gallery-only helper kept for tests / thin callers.
pub fn widgets_view<'a>(theme: &'a Theme, kinds: &'a [String]) -> Element<'a, Message> {
    let mut grid = row![].spacing(12);
    for k in kinds {
        let id = k.clone();
        grid = grid.push(glass_plate(
            theme,
            column![
                row![
                    crate::icons::glyph_view(widget_glyph(k), 13.0, theme.text_dim),
                    text(k.as_str())
                        .size(13)
                        .font(semibold())
                        .color(theme.text),
                ]
                .spacing(6)
                .align_y(Alignment::Center),
                button(text("Add").size(11))
                    .on_press(Message::WidgetAdd(id))
                    .padding(Padding::new(4.0).left(12.0).right(12.0))
                    .style(theme.ghost_button_style()),
            ]
            .spacing(6),
        ));
    }
    column![
        text("Desktop widgets")
            .size(14)
            .font(semibold())
            .color(theme.text),
        grid,
    ]
    .spacing(10)
    .into()
}

pub fn empty_layer<'a>(theme: &'a Theme) -> Element<'a, Message> {
    container(text("").size(1).color(theme.text_mute))
        .width(Length::Fill)
        .height(Length::Fill)
        .into()
}

fn pin_label(pin: &str) -> String {
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

#[cfg(test)]
mod dock_tests {
    use super::*;
    use crate::wm_ipc::{Toplevel, WmState};

    fn tl(class: &str, workspace: i64) -> Toplevel {
        Toplevel {
            address: format!("0x{class}"),
            class: class.into(),
            title: class.into(),
            workspace,
        }
    }

    #[test]
    fn beacon_pin_ids() {
        assert!(is_beacon_pin("proteus-launcher"));
        assert!(is_beacon_pin("Beacon"));
        assert!(is_beacon_pin("launcher"));
        assert!(!is_beacon_pin("proteus-settings"));
    }

    #[test]
    fn beacon_never_matches_toplevels() {
        assert!(!pin_matches(
            "proteus-launcher",
            "proteus-launcher",
            "Beacon"
        ));
    }

    #[test]
    fn dock_transients_skip_pins_and_dedupe() {
        let pins = vec!["ghostty".into()];
        let hypr = WmState {
            toplevels: vec![
                tl("ghostty", 1),
                tl("firefox", 1),
                tl("firefox", 1),
                tl("org.gnome.Nautilus", 1),
            ],
            ..Default::default()
        };
        let t = dock_transients(&pins, &hypr);
        assert_eq!(t, vec!["firefox".to_string(), "org.gnome.Nautilus".into()]);
    }

    #[test]
    fn dock_pins_defaults_include_beacon_first() {
        let pins = dock_pins_from_settings(&serde_json::json!({}));
        assert_eq!(pins.first().map(String::as_str), Some("proteus-launcher"));
        assert!(pins.iter().any(|p| p == "proteus-settings"));
    }

    #[test]
    fn dock_pins_prepend_beacon_when_missing() {
        let pins = dock_pins_from_settings(&serde_json::json!({
            "dockPins": "ghostty,org.gnome.Nautilus"
        }));
        assert_eq!(pins[0], "proteus-launcher");
        assert!(pins.iter().any(|p| p == "ghostty"));
    }

    #[test]
    fn dock_pins_dash_keeps_beacon_and_settings() {
        let pins = dock_pins_from_settings(&serde_json::json!({ "dockPins": "-" }));
        assert_eq!(
            pins,
            vec!["proteus-launcher".to_string(), "proteus-settings".into()]
        );
    }

    #[test]
    fn bar_clock_in_process_nonempty() {
        let c = bar_clock_now();
        assert!(!c.date.is_empty());
        assert!(c.time.contains(':'), "{}", c.time);
    }

    #[test]
    fn dock_icon_geometry_rest_strip() {
        assert!((dock_plate_h(48.0, 6.0) - (12.0 + 48.0 + 10.0)).abs() < f32::EPSILON);
        assert!(
            dock_plate_h(48.0, 6.0) <= dock_strip_h(48.0) as f32,
            "plate must fit inside exclusive strip"
        );
        assert_eq!(dock_strip_h(48.0), 78); // plate 70 + 8
        assert_eq!(dock_strip_h(32.0), 62); // plate 54 + 8
        assert!((dock_icon_hover_size(48.0, 1.0) - 48.0 * DOCK_HOVER_SCALE).abs() < 1e-4);
        assert!((dock_icon_hover_size(48.0, 0.0) - 48.0).abs() < 1e-4);
    }

    #[test]
    fn dock_layout_parse() {
        assert_eq!(DockLayout::parse("span"), DockLayout::Span);
        assert_eq!(DockLayout::parse("left"), DockLayout::Left);
        assert!(DockLayout::Left.vertical());
        assert!(DockLayout::Span.span_edge());
        assert!(!DockLayout::Center.span_edge());
    }

    #[test]
    fn dock_running_dots_cap_and_active() {
        let hypr = WmState {
            toplevels: vec![
                tl("ghostty", 1),
                Toplevel {
                    address: "0xb".into(),
                    class: "ghostty".into(),
                    title: "b".into(),
                    workspace: 1,
                },
                Toplevel {
                    address: "0xc".into(),
                    class: "ghostty".into(),
                    title: "c".into(),
                    workspace: 1,
                },
                Toplevel {
                    address: "0xd".into(),
                    class: "ghostty".into(),
                    title: "d".into(),
                    workspace: 1,
                },
            ],
            active_workspace: 1,
            active_class: "ghostty".into(),
            active_title: "b".into(),
            active_address: "0xb".into(),
            ..Default::default()
        };
        let running = dock_running_windows("ghostty", &hypr);
        assert_eq!(running.len(), 4);
        assert_eq!(dock_dot_count(running.len()), 3);
        assert_eq!(dock_active_dot_index("ghostty", &hypr, &running), Some(1));
        assert_eq!(dock_running_windows("proteus-launcher", &hypr).len(), 0);
    }
}
