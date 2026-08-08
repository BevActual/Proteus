//! Privacy Ask prompt surface.


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

pub fn privacy_ask_view<'a>(
    theme: &'a Theme,
    category: &'a str,
    app_id: Option<&'a str>,
) -> Element<'a, Message> {
    // Category icon disc in its semantic privacy color.
    let (glyph, color) = match category {
        "mic" | "microphone" => ("mic", theme.privacy_mic),
        "camera" | "cam" => ("camera", theme.privacy_cam),
        "screen" | "screenshare" => ("screen", theme.privacy_screen),
        _ => ("dot", theme.accent),
    };
    let subtitle = match app_id {
        Some(app) if !app.is_empty() => format!("Allow {category} for {app}?"),
        _ => format!("Allow {category} access?"),
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
                    text(subtitle)
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
                button(text("Allow once").size(13))
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
