//! Status HUD chip (volume / brightness).


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
