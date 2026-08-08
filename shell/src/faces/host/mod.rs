//! Host face — Glance · Storage · Network (thin HexOS-style cards).
//! Thin stub today; Storage/Network escape to Workloads.
//! Shared chrome kit stays in [`crate::surfaces`]; this module owns lean layers + exclusive UI.

use iced::widget::{button, column, text};
use iced::{Element, Padding};

use proteus_ui::theme::Theme;
use proteus_ui::widgets::{glass_plate, tab_bar};

use crate::surfaces::{semibold, Message};

pub fn host_face_view<'a>(
    theme: &'a Theme,
    host_tab: usize,
    glance: &'a crate::platform::HostGlance,
) -> Element<'a, Message> {
    const TABS: &[&str] = &["Glance", "Storage", "Network"];
    let sel = host_tab.min(2);
    let body = match sel {
        0 => {
            let mut cards = column![
                text("Glance").size(14).color(theme.text),
                text("HexOS-style cards · proteus-host-metrics.py")
                    .size(12)
                    .color(theme.text_dim),
            ]
            .spacing(8);
            if glance.cards.is_empty() {
                cards = cards.push(
                    text(format!("Summary · {}", glance.cpu))
                        .size(13)
                        .color(theme.text),
                );
            } else {
                for (title, body) in glance.cards.iter().take(8) {
                    cards = cards.push(
                        column![
                            text(title.as_str()).size(12).color(theme.text_dim),
                            text(body.as_str()).size(13).color(theme.text),
                        ]
                        .spacing(2),
                    );
                }
            }
            cards = cards.push(
                button(text("Refresh metrics").size(12))
                    .on_press(Message::Refresh)
                    .padding(Padding::new(6.0).left(12.0).right(12.0))
                    .style(theme.ghost_button_style()),
            );
            cards = cards.push(
                button(text("Open Workloads").size(12))
                    .on_press(Message::OpenWorkloads)
                    .padding(Padding::new(6.0).left(12.0).right(12.0))
                    .style(theme.ghost_button_style()),
            );
            cards
        }
        1 => column![
            text("Storage").size(14).color(theme.text),
            text("Shares / disks → Workloads Storage tab.")
                .size(12)
                .color(theme.text_dim),
            button(text("Open Storage").size(12))
                .on_press(Message::OpenWorkloads)
                .padding(Padding::new(6.0).left(12.0).right(12.0))
                .style(theme.ghost_button_style()),
        ]
        .spacing(8),
        _ => column![
            text("Network").size(14).color(theme.text),
            text("Host networking → Workloads Network / shares.")
                .size(12)
                .color(theme.text_dim),
            button(text("Open Network").size(12))
                .on_press(Message::OpenWorkloads)
                .padding(Padding::new(6.0).left(12.0).right(12.0))
                .style(theme.ghost_button_style()),
        ]
        .spacing(8),
    };
    glass_plate(
        theme,
        column![
            text("Host").size(20).font(semibold()).color(theme.text),
            text("VMs · Containers · Shares")
                .size(13)
                .color(theme.text_dim),
            tab_bar(theme, TABS, sel, Message::HostTab),
            body,
        ]
        .spacing(14),
    )
}
