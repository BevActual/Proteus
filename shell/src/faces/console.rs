//! Console face — lean-back list IA (Games · Media · Apps · Search · Settings).
//! Thin Hypr path today; rebuild here later (gamescope console-home not swapped).

use iced::widget::{button, column, row, text};
use iced::{Alignment, Element, Length, Padding};

use proteus_ui::theme::Theme;
use proteus_ui::widgets::{glass_plate, segmented_control};

use crate::ctl::ChromeState;
use crate::surfaces::{semibold, Message};

/// Console list IA (Games · Media · Apps · Search · Settings) — Hypr path;
/// gamescope console-home not swapped.
pub fn console_face_view<'a>(
    theme: &'a Theme,
    chrome: &'a ChromeState,
    games: &'a [crate::platform::ConsoleGame],
    media_path: &'a str,
    apps: &'a [(String, String)],
) -> Element<'a, Message> {
    const TABS: &[&str] = &["Games", "Media", "Apps", "Search", "Settings"];
    let sel = chrome.console_tab.min(TABS.len().saturating_sub(1));
    let body: Element<'a, Message> = match sel {
        0 => {
            let mut list = column![
                text("Installed titles").size(14).color(theme.text),
                text("proteus-console-games.py · launch via proteus-console-seat when present")
                    .size(12)
                    .color(theme.text_dim),
                button(text("Refresh library").size(12))
                    .on_press(Message::Refresh)
                    .padding(Padding::new(6.0).left(12.0).right(12.0))
                    .style(theme.ghost_button_style()),
            ]
            .spacing(8);
            if games.is_empty() {
                list = list.push(
                    text("No titles (set PROTEUS_CONSOLE_GAMES_FIXTURE=1 for smoke data)")
                        .size(12)
                        .color(theme.text_mute),
                );
            } else {
                for g in games.iter().take(24) {
                    let key = g.launch_key.clone();
                    list = list.push(
                        row![
                            text(format!("{} · {}", g.source, g.name))
                                .size(13)
                                .color(theme.text)
                                .width(Length::Fill),
                            button(text("Play").size(11))
                                .on_press(Message::LaunchGame(key))
                                .padding(Padding::new(4.0).left(14.0).right(14.0))
                                .style(theme.accent_button_style()),
                        ]
                        .spacing(8)
                        .align_y(Alignment::Center),
                    );
                }
            }
            list.into()
        }
        1 => {
            let path_label = if media_path.is_empty() {
                "No last path (Fact consoleLastMediaPath)".to_string()
            } else {
                media_path.to_string()
            };
            let mut col = column![
                text("Media").size(14).color(theme.text),
                text("Last folder · Fact consoleLastMediaPath · open via proteus-open / xdg")
                    .size(12)
                    .color(theme.text_dim),
                text(path_label).size(13).color(theme.text),
            ]
            .spacing(8);
            if !media_path.is_empty() {
                col = col.push(
                    button(text("Open folder").size(12))
                        .on_press(Message::OpenMediaPath)
                        .padding(Padding::new(6.0).left(12.0).right(12.0))
                        .style(theme.ghost_button_style()),
                );
            }
            col.into()
        }
        2 => {
            let mut list = column![
                text("Apps").size(14).color(theme.text),
                text("Beacon .desktop subset · lean-back launch")
                    .size(12)
                    .color(theme.text_dim),
                button(text("Open Beacon").size(12))
                    .on_press(Message::ToggleLauncher)
                    .padding(Padding::new(6.0).left(12.0).right(12.0))
                    .style(theme.ghost_button_style()),
            ]
            .spacing(8);
            if apps.is_empty() {
                list = list.push(
                    text("No desktop apps enumerated")
                        .size(12)
                        .color(theme.text_mute),
                );
            } else {
                for (name, id) in apps.iter().take(24) {
                    let id = id.clone();
                    list = list.push(
                        row![
                            text(name.as_str())
                                .size(13)
                                .color(theme.text)
                                .width(Length::Fill),
                            button(text("Open").size(11))
                                .on_press(Message::LaunchConsoleApp(id))
                                .padding(Padding::new(4.0).left(12.0).right(12.0))
                                .style(theme.ghost_button_style()),
                        ]
                        .spacing(8)
                        .align_y(Alignment::Center),
                    );
                }
            }
            list.into()
        }
        3 => column![
            text("Search").size(14).color(theme.text),
            text("Universal search → Beacon.")
                .size(12)
                .color(theme.text_dim),
            button(text("Search…").size(12))
                .on_press(Message::ToggleLauncher)
                .padding(Padding::new(6.0).left(12.0).right(12.0))
                .style(theme.ghost_button_style()),
        ]
        .spacing(8)
        .into(),
        _ => column![
            text("Console Settings").size(14).color(theme.text),
            text("Thin face · posture · Wi‑Fi / Sound / Privacy · full Settings escape")
                .size(12)
                .color(theme.text_dim),
            row![
                button(text("Desktop posture").size(12))
                    .on_press(Message::OpenConsoleSettingsPage("about".into()))
                    .padding(Padding::new(6.0).left(12.0).right(12.0))
                    .style(theme.ghost_button_style()),
                button(text("Control Center").size(12))
                    .on_press(Message::ToggleControlCenter)
                    .padding(Padding::new(6.0).left(12.0).right(12.0))
                    .style(theme.ghost_button_style()),
            ]
            .spacing(8),
            row![
                button(text("Wi‑Fi").size(12))
                    .on_press(Message::OpenConsoleSettingsPage("network-wifi".into()))
                    .padding(Padding::new(6.0).left(12.0).right(12.0))
                    .style(theme.ghost_button_style()),
                button(text("Sound").size(12))
                    .on_press(Message::OpenConsoleSettingsPage("sound".into()))
                    .padding(Padding::new(6.0).left(12.0).right(12.0))
                    .style(theme.ghost_button_style()),
                button(text("Privacy").size(12))
                    .on_press(Message::OpenConsoleSettingsPage("privacy".into()))
                    .padding(Padding::new(6.0).left(12.0).right(12.0))
                    .style(theme.ghost_button_style()),
            ]
            .spacing(8),
            button(text("Open full Settings").size(12))
                .on_press(Message::OpenSettings)
                .padding(Padding::new(6.0).left(12.0).right(12.0))
                .style(theme.ghost_button_style()),
            text("gamescope console-home not swapped")
                .size(11)
                .color(theme.text_mute),
        ]
        .spacing(8)
        .into(),
    };
    let nav_hint = if chrome.console_nav_open {
        "Nav open · Guide IPC consoleNav / consoleTab"
    } else {
        "Nav hidden · proteus-shellctl chrome consoleNav"
    };
    glass_plate(
        theme,
        column![
            text("Console").size(20).font(semibold()).color(theme.text),
            text(nav_hint).size(12).color(theme.text_dim),
            segmented_control(theme, TABS, sel, Message::FaceSelect),
            body,
            if chrome.console_switcher_open {
                text("App switcher open").size(12).color(theme.accent)
            } else {
                text("").size(1).color(theme.text_mute)
            },
        ]
        .spacing(14),
    )
}
