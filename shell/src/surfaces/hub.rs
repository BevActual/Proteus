//! Center menu-bar hub (calendar / notifications) + weather glance.


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
