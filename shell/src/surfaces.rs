//! Chrome surfaces — bar, dock, beacon, CC, lock, widgets.
//! Session faces (desktop / console / host) live under [`crate::faces`].

use iced::widget::{button, column, container, row, scrollable, text, text_input, Space};
use iced::{Alignment, Background, Border, Color, Element, Length, Padding};

use proteus_ui::theme::Theme;
use proteus_ui::widgets::{
    chrome_tile, dock_plate, elevated_chip, glass_plate, menu_bar_plate, segmented_control,
};

use crate::ctl::ChromeState;
use crate::hypr::HyprState;
use crate::platform::{MprisPlayer, Notification, PowerStatus, PrivacyDots};

#[derive(Debug, Clone)]
pub enum Message {
    ToggleLauncher,
    ToggleControlCenter,
    ToggleCalendar,
    ToggleWeather,
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
    PrivacyAllow,
    PrivacyDeny,
    Lock,
    Unlock,
    PinEntry(String),
    WidgetAdd(String),
    FaceSelect(usize),
    Refresh,
    OpenSettings,
    OpenWorkloads,
    OpenPrivacy,
    BrightnessSet(u8),
    BrightnessStep(i8),
    VolumeStep(i8),
    VolumeSet(u8),
    MediaPlayPause(String),
    MediaNext(String),
    MediaPrev(String),
    PowerProfile(usize),
    WindowClose,
    WindowMinimize,
    WindowMaximize,
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
    DockLeave,
}

/// Dock pin ↔ running toplevel match (shared by running dots + previews).
pub fn pin_matches(pin: &str, class: &str, title: &str) -> bool {
    let c = class.to_lowercase();
    let p = pin.to_lowercase();
    c.contains(&p) || p.contains(&c) || title.to_lowercase().contains(&p)
}

/// Cached bar clock strings — refreshed on the slow tick, never in view
/// (spawning `date` per frame would wreck the 60fps anim loop).
#[derive(Debug, Clone, Default, PartialEq)]
pub struct BarClock {
    pub date: String,
    pub time: String,
}

/// One `date` spawn for both strings (QML `"ddd MMM d"` + `"h:mm AP"`).
pub fn bar_clock_now() -> BarClock {
    let raw = std::process::Command::new("date")
        .args(["+%a %b %-d|%-I:%M %p"])
        .output()
        .ok()
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .map(|s| s.trim().to_string())
        .unwrap_or_default();
    match raw.split_once('|') {
        Some((d, t)) => BarClock {
            date: d.to_string(),
            time: t.to_string(),
        },
        None => BarClock {
            date: "Today".into(),
            time: "--:--".into(),
        },
    }
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

/// 12×12 traffic-light disc; glyph appears on hover only (QML TopBar parity).
fn traffic_light<'a>(color: Color, glyph: &'a str, msg: Message) -> Element<'a, Message> {
    button(
        container(text(glyph).size(9).font(semibold()))
            .width(Length::Fill)
            .height(Length::Fill)
            .align_x(Alignment::Center)
            .align_y(Alignment::Center),
    )
    .width(Length::Fixed(12.0))
    .height(Length::Fixed(12.0))
    .padding(0)
    .on_press(msg)
    .style(move |_t, status| {
        let hovered = matches!(status, button::Status::Hovered | button::Status::Pressed);
        button::Style {
            background: Some(Background::Color(color)),
            text_color: if hovered {
                Color::from_rgba(0.0, 0.0, 0.0, 0.55)
            } else {
                Color::TRANSPARENT
            },
            border: Border {
                radius: 6.0.into(),
                width: 0.0,
                color: Color::TRANSPARENT,
            },
            ..Default::default()
        }
    })
    .into()
}

pub fn bar_view<'a>(
    theme: &'a Theme,
    chrome: &'a ChromeState,
    hypr: &'a HyprState,
    power: &'a PowerStatus,
    tray: &'a [crate::platform::TrayItem],
    privacy: &'a PrivacyDots,
    dnd: bool,
    clock: &'a BarClock,
) -> Element<'a, Message> {
    let has_focus = !hypr.active_class.is_empty() || !hypr.active_title.is_empty();
    let lights: Element<'a, Message> = if has_focus {
        row![
            traffic_light(theme.light_close, "×", Message::WindowClose),
            traffic_light(theme.light_min, "−", Message::WindowMinimize),
            traffic_light(theme.light_max, "+", Message::WindowMaximize),
        ]
        .spacing(7)
        .align_y(Alignment::Center)
        .into()
    } else {
        Space::new().width(Length::Fixed(0.0)).into()
    };

    let title = text(hypr.active_title.chars().take(28).collect::<String>())
        .size(13)
        .font(semibold())
        .color(theme.text_dim);

    // Workspace strip — pill track, soft-accent focus, hover brightness.
    let track_bg = if theme.mode == proteus_ui::theme::ChromeMode::Dark {
        Color::from_rgba(1.0, 1.0, 1.0, 0.08)
    } else {
        Color::from_rgba(0.0, 0.0, 0.0, 0.05)
    };
    let cell_hover = if theme.mode == proteus_ui::theme::ChromeMode::Dark {
        Color::from_rgba(1.0, 1.0, 1.0, 0.08)
    } else {
        Color::from_rgba(0.0, 0.0, 0.0, 0.06)
    };
    let mut cells = row![].spacing(2).align_y(Alignment::Center);
    for w in &hypr.workspaces {
        let active = w.active;
        let id = w.id;
        let accent = theme.accent;
        let accent_soft = theme.accent_soft;
        let dim = theme.text_dim;
        let label = if w.name.is_empty() {
            format!("{id}")
        } else {
            w.name.clone()
        };
        let label_text = if active {
            text(label).size(11).font(semibold()).color(accent)
        } else {
            text(label).size(11).color(dim)
        };
        cells = cells.push(
            button(label_text)
                .padding(Padding::new(3.0).left(9.0).right(9.0))
                .style(move |_t, status| {
                    let background = if active {
                        Some(Background::Color(accent_soft))
                    } else {
                        match status {
                            button::Status::Hovered | button::Status::Pressed => {
                                Some(Background::Color(cell_hover))
                            }
                            _ => None,
                        }
                    };
                    button::Style {
                        background,
                        text_color: if active { accent } else { dim },
                        border: Border {
                            radius: 10.0.into(),
                            width: 0.0,
                            color: Color::TRANSPARENT,
                        },
                        ..Default::default()
                    }
                })
                .on_press(Message::Workspace(id)),
        );
    }
    let ws: Element<'a, Message> = if hypr.workspaces.is_empty() {
        Space::new().width(Length::Fixed(0.0)).into()
    } else {
        container(cells)
            .padding(2)
            .style(move |_t| container::Style {
                background: Some(Background::Color(track_bg)),
                border: Border {
                    radius: 12.0.into(),
                    width: 0.0,
                    color: Color::TRANSPARENT,
                },
                ..Default::default()
            })
            .into()
    };

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
                button(crate::icons::glyph_view(glyph, 12.0, color))
                    .padding(4)
                    .style(bar_chip_style(theme, false))
                    .on_press(Message::OpenPrivacy),
            );
        }
    }

    let dnd_chip: Element<'a, Message> = if dnd {
        crate::icons::glyph_view("moon", 12.0, theme.accent)
    } else {
        Space::new().width(Length::Fixed(0.0)).into()
    };

    // Center clock — date dim, time DemiBold (QML Time.qml formats).
    let clock_el = row![
        text(clock.date.clone()).size(12).color(theme.text_dim),
        text(clock.time.clone())
            .size(12)
            .font(semibold())
            .color(theme.text),
    ]
    .spacing(6)
    .align_y(Alignment::Center);

    // Battery — glyph + % only with a real battery (honest facts).
    let bat: Element<'a, Message> = if power.percent > 0 {
        row![
            crate::icons::glyph_view("battery", 14.0, theme.text_dim),
            text(format!("{}%", power.percent))
                .size(11)
                .color(theme.text_dim),
        ]
        .spacing(3)
        .align_y(Alignment::Center)
        .into()
    } else {
        Space::new().width(Length::Fixed(0.0)).into()
    };

    let cc_color = if chrome.control_center_open {
        theme.accent
    } else {
        theme.text_dim
    };
    let cc = button(crate::icons::glyph_view("cc", 14.0, cc_color))
        .padding(Padding::new(4.0).left(7.0).right(7.0))
        .style(bar_chip_style(theme, chrome.control_center_open))
        .on_press(Message::ToggleControlCenter);

    // Clock centered visually: left cluster · fill · clock · fill · right cluster
    let left = row![lights, title, ws]
        .spacing(10)
        .align_y(Alignment::Center);
    let right = row![privacy_row, tray_row, dnd_chip, bat, cc]
        .spacing(theme.space_sm)
        .align_y(Alignment::Center);

    menu_bar_plate(
        theme,
        row![
            container(left).width(Length::Fill),
            clock_el,
            container(right).width(Length::Fill).align_x(Alignment::End),
        ]
        .spacing(theme.space_sm)
        .align_y(Alignment::Center)
        .padding(Padding::new(4.0).left(14.0).right(14.0)),
    )
}

/// Dock surface height and the input-opaque shelf strip at its bottom. The
/// area above the strip hosts hover previews and stays click-through
/// (reconcile_layer_input restricts the input region to the strip).
pub const DOCK_LAYER_H: u32 = 200;
pub const DOCK_STRIP_H: u32 = 72;

/// Dock geometry (QML parity at iconSize=48).
pub const DOCK_ICON_REST: f32 = 48.0;
pub const DOCK_ICON_PEAK: f32 = 70.0;
/// Cell distance over which magnification falls off (cosine curve).
const DOCK_MAG_CELLS: f32 = 2.5;

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

pub fn dock_view<'a>(
    theme: &'a Theme,
    pins: &'a [String],
    hypr: &'a HyprState,
    preview: Option<(&'a str, &'a iced::widget::image::Handle)>,
    icons: &'a crate::icons::IconCache,
    hover_pin: Option<&'a str>,
    mag: f32,
) -> Element<'a, Message> {
    let hovered_idx = hover_pin.and_then(|hp| pins.iter().position(|p| p == hp));
    let mut r = row![].spacing(7).align_y(Alignment::End);
    for (i, pin) in pins.iter().enumerate() {
        let id = pin.clone();
        let accent = theme.accent;
        let dim = theme.text_mute;
        // Cosine magnify falloff around the hovered cell (QML Dock curve).
        let strength = hovered_idx
            .map(|h| {
                let d = (i as f32 - h as f32).abs();
                if d >= DOCK_MAG_CELLS {
                    0.0
                } else {
                    ((std::f32::consts::PI * d / DOCK_MAG_CELLS).cos() + 1.0) / 2.0
                }
            })
            .unwrap_or(0.0)
            * mag;
        let size = DOCK_ICON_REST + (DOCK_ICON_PEAK - DOCK_ICON_REST) * strength;

        let is_run = hypr
            .toplevels
            .iter()
            .any(|t| pin_matches(pin, &t.class, &t.title));
        let is_active = is_run
            && !hypr.active_class.is_empty()
            && pin_matches(pin, &hypr.active_class, &hypr.active_title);

        // Running indicator — active pill 8×3 accent, running disc 4×4.
        let (ind_w, ind_h, ind_color) = if is_active {
            (8.0, 3.0, accent)
        } else if is_run {
            (4.0, 4.0, dim)
        } else {
            (4.0, 4.0, Color::TRANSPARENT)
        };
        let indicator = container(
            Space::new()
                .width(Length::Fixed(ind_w))
                .height(Length::Fixed(ind_h)),
        )
        .style(move |_t| container::Style {
            background: Some(Background::Color(ind_color)),
            border: Border {
                radius: (ind_h / 2.0).into(),
                ..Default::default()
            },
            ..Default::default()
        });

        let cell = column![
            button(dock_icon(theme, icons, pin, size))
                .padding(0)
                .style(|_t, _s| button::Style {
                    background: None,
                    text_color: Color::TRANSPARENT,
                    border: Border::default(),
                    ..Default::default()
                })
                .on_press(Message::DockLaunch(id)),
            indicator,
        ]
        .align_x(Alignment::Center)
        .spacing(3);
        let hover_pin_msg = pin.clone();
        r = r.push(
            iced::widget::mouse_area(cell)
                .on_enter(Message::DockHover(hover_pin_msg))
                .on_exit(Message::DockLeave),
        );
    }
    let shelf = dock_plate(theme, r);

    // Hover tip + preview card float above the shelf (visual only; click-through).
    // Gated on magnify strength so the tip fades with the ease-out on leave.
    let preview_card: Element<'a, Message> = if let Some(pin) = hover_pin.filter(|_| mag > 0.05) {
        let title = pin_label(pin);
        let tip = elevated_chip(
            theme,
            text(title).size(11).font(semibold()).color(theme.text),
        );
        match preview {
            Some((ppin, handle)) if ppin == pin => column![
                container(
                    column![
                        iced::widget::image(handle.clone())
                            .width(Length::Fixed(200.0))
                            .height(Length::Fixed(112.0))
                            .content_fit(iced::ContentFit::Contain),
                    ]
                    .spacing(4)
                    .align_x(Alignment::Center)
                )
                .padding(8)
                .style(theme.panel_style()),
                tip,
            ]
            .spacing(6)
            .align_x(Alignment::Center)
            .into(),
            _ => tip,
        }
    } else {
        Space::new().height(Length::Fixed(0.0)).into()
    };

    container(
        column![preview_card, shelf]
            .spacing(8)
            .align_x(Alignment::Center),
    )
    .width(Length::Fill)
    .height(Length::Fill)
    .align_x(Alignment::Center)
    .align_y(Alignment::End)
    .into()
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

    // Card — 680 wide, radius 22, elevated fill over a scrim.
    let card_fill = if theme.mode == proteus_ui::theme::ChromeMode::Dark {
        Color::from_rgba(0.16, 0.16, 0.17, 0.92)
    } else {
        Color::from_rgba(1.0, 1.0, 1.0, 0.95)
    };
    let card_border = theme.hairline;
    let card = container(column![search_row, divider, body].spacing(0))
        .width(Length::Fixed(680.0))
        .style(move |_t| container::Style {
            background: Some(Background::Color(card_fill)),
            border: Border {
                radius: 22.0.into(),
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
    notifs: &'a [Notification],
    dnd: bool,
    wifi: &'a [crate::platform::WifiHit],
    bt: &'a [crate::platform::BtHit],
    focus_on: bool,
    focus_profiles: &'a [crate::platform::FocusProfile],
    focus_active_id: &'a str,
    open_t: f32,
) -> Element<'a, Message> {
    // ---- Notifications (top, QML order) ------------------------------------
    let mut nlist = column![].spacing(6);
    for n in notifs.iter().rev().take(6) {
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
                text(n.body.chars().take(90).collect::<String>())
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
    let notif_section: Element<'a, Message> = if notifs.is_empty() {
        container(
            text("No notifications")
                .size(12)
                .color(theme.text_mute),
        )
        .width(Length::Fill)
        .padding(12)
        .align_x(Alignment::Center)
        .into()
    } else {
        scrollable(nlist).height(Length::Shrink).into()
    };

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
    let toggles = row![
        toggle_tile("moon", "Do Not Disturb", dnd, Message::ToggleDnd),
        toggle_tile("focus", "Focus", focus_on, Message::ToggleFocus),
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

    let mut wifi_col = column![row![
        crate::icons::glyph_view("wifi", 13.0, theme.text_dim),
        text("Wi-Fi").size(12).color(theme.text_dim),
    ]
    .spacing(6)
    .align_y(Alignment::Center)]
    .spacing(4);
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

    let mut bt_col = column![row![
        crate::icons::glyph_view("bluetooth", 13.0, theme.text_dim),
        text("Bluetooth").size(12).color(theme.text_dim),
    ]
    .spacing(6)
    .align_y(Alignment::Center)]
    .spacing(4);
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

    // ---- Calendar / weather stubs (only when open) --------------------------
    let cal: Element<'a, Message> = if chrome.calendar_open {
        chrome_tile(
            theme,
            column![
                row![
                    crate::icons::glyph_view("calendar", 13.0, theme.text_dim),
                    text("Calendar").size(12).color(theme.text_dim),
                ]
                .spacing(6)
                .align_y(Alignment::Center),
                text(chrono_date_stub()).size(13).color(theme.text),
            ]
            .spacing(4),
        )
    } else {
        Space::new().height(Length::Fixed(0.0)).into()
    };

    // ---- Shortcuts row -------------------------------------------------------
    let shortcut = |label: &'a str, msg: Message| {
        button(text(label).size(12))
            .padding(Padding::new(6.0).left(12.0).right(12.0))
            .style(theme.ghost_button_style())
            .on_press(msg)
    };
    let shortcuts = row![
        shortcut("Settings", Message::OpenSettings),
        shortcut("Workloads", Message::OpenWorkloads),
        shortcut("Calendar", Message::ToggleCalendar),
        shortcut("Weather", Message::ToggleWeather),
    ]
    .spacing(4);

    let hairline = theme.hairline;
    let divider = container(Space::new().width(Length::Fill).height(1))
        .style(move |_t| container::Style {
            background: Some(Background::Color(hairline)),
            ..Default::default()
        });

    let panel_body = column![
        notif_section,
        divider,
        media_card,
        text("Quick Settings")
            .size(12)
            .font(semibold())
            .color(theme.text_dim),
        sliders,
        toggles,
        focus_section,
        power_tile,
        chrome_tile(theme, wifi_col),
        chrome_tile(theme, bt_col),
        cal,
        shortcuts,
    ]
    .spacing(theme.space_md);

    // ---- Panel — 360 wide, radius 16, anchored top-right; scrim closes ------
    let panel_fill = if theme.mode == proteus_ui::theme::ChromeMode::Dark {
        proteus_ui::theme::fade(theme.bg_panel, 0.88)
    } else {
        proteus_ui::theme::fade(theme.bg_panel, 0.94)
    };
    let panel_border = theme.hairline;
    let panel = container(scrollable(panel_body).height(Length::Shrink))
        .width(Length::Fixed(360.0))
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

/// Full-bleed lock overlay — maps shared [`crate::lock_ui`] into shell messages.
pub fn lock_view<'a>(
    theme: &'a Theme,
    st: &'a crate::lock_ui::LockUiState,
) -> Element<'a, Message> {
    use crate::lock_ui::LockMsg;
    crate::lock_ui::lock_screen_view(theme, st).map(|m| match m {
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
    })
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
/// solid-color fallback. Handle is cached in App so the texture uploads once.
pub fn wallpaper_view<'a>(
    theme: &'a Theme,
    wp: &'a crate::platform::WallpaperState,
    handle: Option<&'a iced::widget::image::Handle>,
) -> Element<'a, Message> {
    if let Some(h) = handle {
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
        let under = parse_wallpaper_color(&wp.color, theme.bg);
        return container(img)
            .width(Length::Fill)
            .height(Length::Fill)
            .clip(true)
            .style(move |_t| container::Style {
                background: Some(Background::Color(under)),
                ..Default::default()
            })
            .into();
    }
    let bg = parse_wallpaper_color(&wp.color, theme.bg);
    container(Space::new().width(Length::Fill).height(Length::Fill))
        .width(Length::Fill)
        .height(Length::Fill)
        .style(move |_t| container::Style {
            background: Some(Background::Color(bg)),
            ..Default::default()
        })
        .into()
}

pub fn widgets_view<'a>(theme: &'a Theme, kinds: &'a [String]) -> Element<'a, Message> {
    let mut grid = row![].spacing(12);
    for k in kinds {
        let id = k.clone();
        let glyph = match k.as_str() {
            "Clock" | "WorldClock" => "calendar",
            "Media" => "note",
            "Battery" => "battery",
            "System" => "cc",
            "Notes" => "note",
            _ => "dot",
        };
        grid = grid.push(glass_plate(
            theme,
            column![
                row![
                    crate::icons::glyph_view(glyph, 13.0, theme.text_dim),
                    text(k.as_str())
                        .size(13)
                        .font(semibold())
                        .color(theme.text),
                ]
                .spacing(6)
                .align_y(Alignment::Center),
                text("widget").size(11).color(theme.text_mute),
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
    pin.rsplit(&['.', '-'][..])
        .next()
        .unwrap_or(pin)
        .chars()
        .take(10)
        .collect()
}

fn chrono_date_stub() -> String {
    std::process::Command::new("date")
        .args(["+%a %b %-d"])
        .output()
        .ok()
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "Today".into())
}
