//! Notification toast surface.


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
