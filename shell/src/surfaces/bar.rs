//! Menu bar (top chrome).


#![allow(unused_imports)]

use iced::widget::{button, column, container, mouse_area, row, scrollable, text, text_input, Space};
use iced::{Alignment, Background, Border, Color, Element, Length, Padding};

use proteus_ui::theme::Theme;
use proteus_ui::widgets::{
    chrome_tile, dock_plate, elevated_chip, glass_plate, menu_bar_plate, segmented_control,
};

use crate::ctl::ChromeState;
use crate::platform::{
    MprisPlayer, Notification, PowerStatus, PrivacyDots, WallpaperState, WeatherGlance,
};
use crate::wm_ipc::WmState;

use super::{
    bar_clock_now, is_beacon_pin, light_font, pin_label, pin_matches, semibold, BarClock,
    DockPreview, DockPreviewWin, Message,
};

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
    _wm: &'a WmState,
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

    // Spaces control — overview icon; wheel cycles Spaces.
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
