//! Control Center quick-settings surface.


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
