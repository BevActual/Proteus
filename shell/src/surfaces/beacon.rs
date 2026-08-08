//! Beacon (system search / launcher) surface.


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
    if let Some(path) = hit.strip_prefix("Place · ") {
        let name = path.rsplit('/').next().unwrap_or(path);
        return (name.to_string(), path.to_string(), BeaconIcon::Glyph("folder"));
    }
    if let Some(path) = hit.strip_prefix("Recent · ") {
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
    let query_input = text_input("Search apps, settings, files, clipboard…", &chrome.beacon_query)
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
