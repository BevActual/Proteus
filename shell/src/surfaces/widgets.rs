//! Desktop widgets surface + gallery helper.


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
