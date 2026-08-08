//! Dock shelf + dwell previews.


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

/// Dock surface height and the input-opaque shelf strip at its bottom.
/// Preview band above the strip is click-through until a dwell preview opens
/// (then reconcile_layer_input expands to `DockPreview`).
/// Tall enough for one dwell card + tip + magnified shelf without flex-crushing icons.
pub const DOCK_LAYER_H: u32 = 320;
pub const DOCK_STRIP_H: u32 = 72;
/// Hover-dwell before capturing window thumbnails (ms).
pub const DOCK_PREVIEW_DWELL_MS: u64 = 350;
/// Launch bounce timeout (ms) if no matching window appears.
pub const DOCK_BOUNCE_TIMEOUT_MS: u64 = 3200;
/// Delay before clearing hover/preview so the pointer can reach the card.
pub const DOCK_LEAVE_DELAY_MS: u64 = 140;

/// Dock geometry defaults (iconSize=48).
pub const DOCK_ICON_REST: f32 = 48.0;
/// Per-icon hover scale (Windows-style — no neighbor magnify).
pub const DOCK_HOVER_SCALE: f32 = 1.12;
/// Launch bounce amplitude relative to rest size.
pub const DOCK_BOUNCE_SCALE: f32 = 0.18;
/// Gap between dock cells.
pub const DOCK_CELL_SPACING: f32 = 7.0;
/// Hot-edge peek fraction while autohidden (partial reveal).
pub const DOCK_PEEK_SLIDE: f32 = 0.30;

/// Dock edge layout from `dockLayout` Fact.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum DockLayout {
    #[default]
    Center,
    Span,
    Left,
    Right,
}

impl DockLayout {
    pub fn parse(s: &str) -> Self {
        match s {
            "span" => Self::Span,
            "left" => Self::Left,
            "right" => Self::Right,
            _ => Self::Center,
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Self::Center => "center",
            Self::Span => "span",
            Self::Left => "left",
            Self::Right => "right",
        }
    }

    pub fn vertical(self) -> bool {
        matches!(self, Self::Left | Self::Right)
    }

    pub fn span_edge(self) -> bool {
        matches!(self, Self::Span | Self::Left | Self::Right)
    }
}

/// Rest-thickness frosted plate (pads + icon + running indicator).
pub fn dock_plate_h(rest: f32, pad_v: f32) -> f32 {
    pad_v * 2.0 + rest + 10.0
}

/// Layer input / exclusive strip size for a rest icon size (no magnify headroom).
pub fn dock_strip_h(rest: f32) -> u32 {
    (dock_plate_h(rest, 6.0) + 8.0).clamp(52.0, 96.0) as u32
}

/// Hairline divider thickness.
pub fn dock_divider_width(_icon_rest: f32) -> f32 {
    1.0
}

/// Hovered icon size (rest × hover scale × engagement).
pub fn dock_icon_hover_size(rest: f32, hover_t: f32) -> f32 {
    let t = hover_t.clamp(0.0, 1.0);
    rest * (1.0 + (DOCK_HOVER_SCALE - 1.0) * t)
}

/// Non-minimized toplevels matching a dock pin (Beacon → empty).
pub fn dock_running_windows<'a>(pin: &str, wm: &'a WmState) -> Vec<&'a crate::wm_ipc::Toplevel> {
    if is_beacon_pin(pin) {
        return Vec::new();
    }
    wm.toplevels
        .iter()
        .filter(|t| t.workspace >= 0 && pin_matches(pin, &t.class, &t.title))
        .collect()
}

/// Visible running-dot count (cap 3).
pub fn dock_dot_count(running: usize) -> usize {
    running.min(3)
}

/// Accented dot index among `dot_count` dots when the pin is focused.
pub fn dock_active_dot_index(pin: &str, wm: &WmState, running: &[&crate::wm_ipc::Toplevel]) -> Option<usize> {
    if running.is_empty() {
        return None;
    }
    let focused = !wm.active_class.is_empty()
        && pin_matches(pin, &wm.active_class, &wm.active_title);
    if !focused {
        return None;
    }
    let idx = running
        .iter()
        .position(|t| t.address == wm.active_address)
        .unwrap_or(0);
    Some(idx.min(dock_dot_count(running.len()).saturating_sub(1)))
}

/// Unpinned running apps (class keys) for the transient dock section.
pub fn dock_transients(pins: &[String], wm: &WmState) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    for t in &wm.toplevels {
        if t.class.is_empty() {
            continue;
        }
        let pinned = pins
            .iter()
            .any(|p| pin_matches(p.as_str(), &t.class, &t.title));
        if pinned {
            continue;
        }
        if out
            .iter()
            .any(|k| pin_matches(k.as_str(), &t.class, &t.title))
        {
            continue;
        }
        out.push(t.class.clone());
    }
    out
}

/// Resolve dock pins from settings.json `dockPins` (Beacon always present).
pub fn dock_pins_from_settings(settings: &serde_json::Value) -> Vec<String> {
    let raw = settings
        .get("dockPins")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .trim();
    let mut pins = if raw.is_empty() {
        vec![
            "proteus-launcher".into(),
            "proteus-settings".into(),
            "proteus-workloads".into(),
            "com.mitchellh.ghostty".into(),
            "org.gnome.Nautilus".into(),
        ]
    } else if raw == "-" {
        vec!["proteus-launcher".into(), "proteus-settings".into()]
    } else {
        raw.split(',')
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
            .collect()
    };
    if !pins.iter().any(|p| is_beacon_pin(p)) {
        pins.insert(0, "proteus-launcher".into());
    }
    pins
}

/// Reorder pinned cells — index 0 (Beacon) is fixed.
pub fn reorder_dock_pins(pins: &mut Vec<String>, from: usize, to: usize) -> bool {
    if from == to || from >= pins.len() || to >= pins.len() || from == 0 || to == 0 {
        return false;
    }
    let item = pins.remove(from);
    pins.insert(to, item);
    true
}

/// Remove a pin in edit mode — Beacon is fixed; returns whether anything changed.
pub fn remove_dock_pin(pins: &mut Vec<String>, id: &str) -> bool {
    if is_beacon_pin(id) {
        return false;
    }
    let before = pins.len();
    pins.retain(|p| p != id);
    if pins.is_empty() {
        pins.push("proteus-launcher".into());
    } else if !pins.iter().any(|p| is_beacon_pin(p)) {
        pins.insert(0, "proteus-launcher".into());
    }
    pins.len() != before
}

/// Persist pinned ids to settings.json `dockPins` (comma-joined).
pub fn persist_dock_pins(pins: &[String]) -> Result<(), String> {
    let raw = pins.join(",");
    let base = proteus_shell_core::facts::config_base();
    proteus_shell_core::facts::write_settings(&base, &serde_json::json!({ "dockPins": raw }))
        .map_err(|e| e.to_string())
        .map(|_| ())
}

/// Icon element for a dock pin — real app icon or initials on a squircle plate.
fn dock_icon<'a>(
    theme: &'a Theme,
    icons: &'a crate::icons::IconCache,
    pin: &str,
    size: f32,
) -> Element<'a, Message> {
    match icons.get(pin) {
        Some(handle) => {
            proteus_ui::widgets::squircle_plate(theme, size, handle.view(size * 0.78))
        }
        None => {
            let initials: String = pin_label(pin)
                .chars()
                .take(2)
                .collect::<String>()
                .to_uppercase();
            proteus_ui::widgets::squircle_plate(
                theme,
                size,
                text(initials)
                    .size(size * 0.34)
                    .font(semibold())
                    .color(theme.text_dim),
            )
        }
    }
}

fn dock_indicator_dot<'a>(color: Color, w: f32, h: f32) -> Element<'a, Message> {
    container(
        Space::new()
            .width(Length::Fixed(w))
            .height(Length::Fixed(h)),
    )
    .style(move |_t| container::Style {
        background: Some(Background::Color(color)),
        border: Border {
            radius: (h / 2.0).into(),
            ..Default::default()
        },
        ..Default::default()
    })
    .into()
}

fn dock_running_indicator<'a>(
    theme: &'a Theme,
    pin: &str,
    wm: &'a WmState,
    beacon_open: bool,
) -> Element<'a, Message> {
    let accent = theme.accent;
    let dim = theme.text_mute;
    if is_beacon_pin(pin) {
        let color = if beacon_open {
            accent
        } else {
            Color::TRANSPARENT
        };
        return dock_indicator_dot(color, 8.0, 3.0);
    }
    let running = dock_running_windows(pin, wm);
    let n = dock_dot_count(running.len());
    if n == 0 {
        return dock_indicator_dot(Color::TRANSPARENT, 4.0, 4.0);
    }
    let active_idx = dock_active_dot_index(pin, wm, &running);
    // Single focused window keeps the accent pill; multi-window → dots.
    if n == 1 && active_idx.is_some() {
        return dock_indicator_dot(accent, 8.0, 3.0);
    }
    if n == 1 {
        return dock_indicator_dot(dim, 4.0, 4.0);
    }
    let mut dots = row![].spacing(3).align_y(Alignment::Center);
    for i in 0..n {
        let color = if active_idx == Some(i) { accent } else { dim };
        dots = dots.push(dock_indicator_dot(color, 4.0, 4.0));
    }
    dots.into()
}

fn dock_cell<'a>(
    theme: &'a Theme,
    icons: &'a crate::icons::IconCache,
    wm: &'a WmState,
    pin: &str,
    pin_index: Option<usize>,
    size: f32,
    bounce_s: f32,
    beacon_open: bool,
    edit_mode: bool,
    dragging: bool,
    drop_target: bool,
    wiggle: f32,
) -> Element<'a, Message> {
    let id = pin.to_string();
    let max_lift = size * 0.12;
    let pad_top = max_lift * (1.0 - bounce_s.clamp(0.0, 1.0));
    let indicator = dock_running_indicator(theme, pin, wm, beacon_open);
    let wiggle_x = if edit_mode && !is_beacon_pin(pin) {
        wiggle * 2.5
    } else {
        0.0
    };
    let icon_el = dock_icon(theme, icons, pin, size);
    let icon = container(icon_el)
        .padding(
            Padding::new(0.0)
                .top(pad_top)
                .left(wiggle_x.max(0.0))
                .right((-wiggle_x).max(0.0)),
        );

    let cell = column![icon, indicator]
        .align_x(Alignment::Center)
        .spacing(3);
    let hover_pin_msg = pin.to_string();

    if edit_mode {
        let idx = pin_index.unwrap_or(0);
        let can_drag = !is_beacon_pin(pin);
        let border_c = if dragging {
            theme.accent
        } else if drop_target {
            theme.accent.scale_alpha(0.55)
        } else {
            Color::TRANSPARENT
        };
        let wrapped = container(cell)
            .padding(Padding::from([2, 4]))
            .style(move |_t| container::Style {
                background: Some(Background::Color(theme.bg_elevated.scale_alpha(
                    if dragging { 0.55 } else { 0.38 },
                ))),
                border: Border {
                    radius: 10.0.into(),
                    width: if dragging || drop_target { 2.0 } else { 0.0 },
                    color: border_c,
                },
                ..Default::default()
            });
        let press_id = id.clone();
        let mut area = iced::widget::mouse_area(wrapped);
        if can_drag {
            area = area
                .on_press(Message::DockPress(press_id))
                .on_release(Message::DockRelease(id.clone()))
                .on_enter(Message::DockDragHover(idx));
        }
        if !can_drag {
            return area.into();
        }
        // (−) sits above the drag mouse_area so remove doesn't start a reorder.
        let unpin_id = id;
        let badge = button(text("−").size(14).font(semibold()).color(theme.text))
            .padding(Padding::new(0.0).left(6.0).right(6.0).top(1.0).bottom(2.0))
            .style(move |_t, status| {
                let bg = match status {
                    iced::widget::button::Status::Hovered => theme.danger.scale_alpha(0.85),
                    _ => theme.danger.scale_alpha(0.72),
                };
                iced::widget::button::Style {
                    background: Some(Background::Color(bg)),
                    text_color: theme.text,
                    border: Border {
                        radius: 10.0.into(),
                        ..Default::default()
                    },
                    ..Default::default()
                }
            })
            .on_press(Message::DockUnpin(unpin_id));
        return iced::widget::stack![
            area,
            container(badge)
                .width(Length::Fill)
                .height(Length::Fill)
                .align_x(Alignment::End)
                .align_y(Alignment::Start),
        ]
        .into();
    }

    // Normal mode — short tap launch, long-press arms edit (handled in update tick).
    iced::widget::mouse_area(cell)
        .on_press(Message::DockPress(id))
        .on_release(Message::DockRelease(hover_pin_msg.clone()))
        .on_enter(Message::DockHover(hover_pin_msg))
        .into()
}

/// Hairline divider between pins and running transients.
fn dock_divider(theme: &Theme, icon_rest: f32) -> Element<'_, Message> {
    let hair = theme.hairline;
    let h = (icon_rest * 0.75).clamp(28.0, 56.0);
    container(
        Space::new()
            .width(Length::Fixed(dock_divider_width(icon_rest)))
            .height(Length::Fixed(h)),
    )
    .padding(Padding::new(0.0).top(4.0).bottom(10.0))
    .style(move |_t| container::Style {
        background: Some(Background::Color(hair)),
        border: Border {
            radius: 1.0.into(),
            ..Default::default()
        },
        ..Default::default()
    })
    .into()
}

pub fn dock_view<'a>(
    theme: &'a Theme,
    pins: &'a [String],
    wm: &'a WmState,
    preview: Option<&'a DockPreview>,
    icons: &'a crate::icons::IconCache,
    hover_pin: Option<&'a str>,
    hover_t: f32,
    slide: f32,
    icon_rest: f32,
    layout: DockLayout,
    rounding: f32,
    // pin → bounce phase strength 0..=1 (sin envelope from launch).
    bounce: &'a [(String, f32)],
    beacon_open: bool,
    edit_mode: bool,
    dock_drag: Option<&str>,
    dock_drag_target: Option<usize>,
    wiggle_phase: f32,
) -> Element<'a, Message> {
    let transients = dock_transients(pins, wm);
    let has_divider = !pins.is_empty() && !transients.is_empty();
    let vertical = layout.vertical();
    let span = layout.span_edge();
    let slide = slide.clamp(0.0, 1.0);

    let cell_size = |pin: &str| -> (f32, f32) {
        let bounce_s = bounce
            .iter()
            .find(|(p, _)| p == pin)
            .map(|(_, s)| *s)
            .unwrap_or(0.0);
        let hovered = hover_pin == Some(pin);
        let base = if hovered {
            dock_icon_hover_size(icon_rest, hover_t)
        } else {
            icon_rest
        };
        (base + icon_rest * DOCK_BOUNCE_SCALE * bounce_s, bounce_s)
    };

    let mut cells: Vec<Element<'a, Message>> = Vec::new();
    for (i, pin) in pins.iter().enumerate() {
        let (size, bounce_s) = cell_size(pin);
        let dragging = dock_drag == Some(pin.as_str());
        let drop_target = dock_drag_target == Some(i);
        cells.push(dock_cell(
            theme,
            icons,
            wm,
            pin,
            Some(i),
            size,
            bounce_s,
            beacon_open,
            edit_mode,
            dragging,
            drop_target,
            wiggle_phase,
        ));
    }
    if has_divider && !edit_mode {
        cells.push(dock_divider(theme, icon_rest));
    }
    if !edit_mode {
        for pin in transients.iter() {
            let (size, bounce_s) = cell_size(pin);
            cells.push(dock_cell(
                theme,
                icons,
                wm,
                pin,
                None,
                size,
                bounce_s,
                false,
                false,
                false,
                false,
                0.0,
            ));
        }
    }

    let icons_el: Element<'a, Message> = if vertical {
        let mut c = column![].spacing(DOCK_CELL_SPACING).align_x(Alignment::Center);
        for cell in cells {
            c = c.push(cell);
        }
        c.into()
    } else {
        let mut r = row![].spacing(DOCK_CELL_SPACING).align_y(Alignment::End);
        for cell in cells {
            r = r.push(cell);
        }
        r.into()
    };

    let plate_h = dock_plate_h(icon_rest, theme.space_sm);
    let shelf = iced::widget::mouse_area(dock_plate(
        theme,
        plate_h,
        rounding,
        span,
        vertical,
        icons_el,
    ))
    .on_enter(Message::DockEdgeEnter)
    .on_exit(Message::DockLeave);

    // Hover tip + interactive preview (bottom docks only; vertical Out this pass).
    let preview_card: Element<'a, Message> = if edit_mode {
        let bar = container(
            row![
                text("Edit Dock — drag to reorder · (−) to remove")
                    .size(13)
                    .font(semibold())
                    .color(theme.text)
                    .width(Length::Fill),
                button(text("Done").size(12).font(semibold()))
                    .padding(Padding::new(4.0).left(14.0).right(14.0))
                    .style(theme.ghost_button_style())
                    .on_press(Message::DockEditDone),
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
        bar.into()
    } else if let Some(pin) = hover_pin.filter(|_| !vertical && hover_t > 0.05)
    {
        let title = pin_label(pin);
        let tip = elevated_chip(
            theme,
            text(title).size(11).font(semibold()).color(theme.text),
        );
        let card: Element<'a, Message> = match preview {
            Some((ppin, wins)) if ppin == pin && !wins.is_empty() => {
                let mut rows = column![].spacing(6);
                // Cap height — stacked thumbs used to crush the shelf in the layer.
                for w in wins.iter().take(2) {
                    let addr = w.address.clone();
                    let addr_close = w.address.clone();
                    let danger = theme.danger;
                    let mute = theme.text_mute;
                    let mut title_row = row![
                        text(
                            if w.title.is_empty() {
                                "Window".into()
                            } else {
                                w.title.chars().take(36).collect::<String>()
                            }
                        )
                        .size(11)
                        .font(semibold())
                        .color(theme.text),
                    ]
                    .spacing(6)
                    .align_y(Alignment::Center);
                    if w.hidden {
                        title_row = title_row.push(
                            container(
                                text("Hidden")
                                    .size(9)
                                    .font(semibold())
                                    .color(theme.text_mute),
                            )
                            .padding(Padding::from([2, 6]))
                            .style(move |_t| container::Style {
                                background: Some(Background::Color(mute.scale_alpha(0.35))),
                                border: Border {
                                    radius: 6.0.into(),
                                    ..Default::default()
                                },
                                ..Default::default()
                            }),
                        );
                    }
                    let thumb = iced::widget::image(w.handle.clone())
                        .width(Length::Fixed(180.0))
                        .height(Length::Fixed(100.0))
                        .content_fit(iced::ContentFit::Contain);
                    let close_btn = button(text("✕").size(12).color(danger))
                        .padding(Padding::from([2, 6]))
                        .style(move |_t, s| button::Style {
                            background: match s {
                                button::Status::Hovered | button::Status::Pressed => {
                                    Some(Background::Color(danger.scale_alpha(0.18)))
                                }
                                _ => None,
                            },
                            text_color: danger,
                            border: Border {
                                radius: 6.0.into(),
                                ..Default::default()
                            },
                            ..Default::default()
                        })
                        .on_press(Message::DockPreviewClose(addr_close));
                    let body = column![title_row, thumb].spacing(4);
                    rows = rows.push(
                        row![
                            button(body)
                                .padding(6)
                                .style(move |_t, s| {
                                    let bg = match s {
                                        button::Status::Hovered | button::Status::Pressed => {
                                            Some(Background::Color(mute.scale_alpha(0.2)))
                                        }
                                        _ => None,
                                    };
                                    button::Style {
                                        background: bg,
                                        text_color: Color::WHITE,
                                        border: Border {
                                            radius: 10.0.into(),
                                            ..Default::default()
                                        },
                                        ..Default::default()
                                    }
                                })
                                .on_press(Message::DockPreviewFocus(addr)),
                            close_btn,
                        ]
                        .spacing(4)
                        .align_y(Alignment::Start),
                    );
                }
                column![
                    container(rows).padding(8).style(theme.panel_style()),
                    tip,
                ]
                .spacing(6)
                .align_x(Alignment::Center)
                .into()
            }
            _ => tip,
        };
        iced::widget::mouse_area(card)
            .on_enter(Message::DockPreviewEnter)
            .into()
    } else {
        Space::new().height(Length::Fixed(0.0)).into()
    };

    // Preview + shelf share a Shrink column (end-aligned). Tall dwell cards
    // used to crush icons when both competed for Fill — tip/card stay Shrink.
    let hide = (1.0 - slide) * plate_h;
    if vertical {
        let shelf = container(shelf)
            .width(Length::Shrink)
            .height(if span { Length::Fill } else { Length::Shrink });
        let peek_pad = Space::new().width(Length::Fixed(hide));
        let body = match layout {
            DockLayout::Left => row![shelf, peek_pad],
            DockLayout::Right => row![peek_pad, shelf],
            _ => row![shelf],
        }
        .height(Length::Fill)
        .align_y(Alignment::Center);
        container(body)
            .width(Length::Fill)
            .height(Length::Fill)
            .align_x(match layout {
                DockLayout::Right => Alignment::End,
                _ => Alignment::Start,
            })
            .align_y(Alignment::Center)
            .into()
    } else {
        // Shrink column (preview + shelf + autohide pad), end-aligned in the
        // layer — same as the pre-layout-rewrite dock. A Fill-height preview
        // band inside this column made iced resolve the shelf to 0 height.
        let shelf = container(shelf)
            .height(Length::Shrink)
            .width(if span { Length::Fill } else { Length::Shrink })
            .align_x(if span {
                Alignment::Start
            } else {
                Alignment::Center
            });
        let stack = column![
            preview_card,
            shelf,
            Space::new().height(Length::Fixed(hide)),
        ]
        .spacing(8)
        .width(Length::Fill)
        .align_x(if span {
            Alignment::Start
        } else {
            Alignment::Center
        });
        container(stack)
            .width(Length::Fill)
            .height(Length::Fill)
            .align_x(if span {
                Alignment::Start
            } else {
                Alignment::Center
            })
            .align_y(Alignment::End)
            .into()
    }
}

#[cfg(test)]
mod dock_tests {
    use super::*;
    use crate::wm_ipc::{Toplevel, WmState};

    fn tl(class: &str, workspace: i64) -> Toplevel {
        Toplevel {
            address: format!("0x{class}"),
            class: class.into(),
            title: class.into(),
            workspace,
            output: String::new(),
        }
    }

    #[test]
    fn beacon_pin_ids() {
        assert!(is_beacon_pin("proteus-launcher"));
        assert!(is_beacon_pin("Beacon"));
        assert!(is_beacon_pin("launcher"));
        assert!(!is_beacon_pin("proteus-settings"));
    }

    #[test]
    fn beacon_never_matches_toplevels() {
        assert!(!pin_matches(
            "proteus-launcher",
            "proteus-launcher",
            "Beacon"
        ));
    }

    #[test]
    fn dock_transients_skip_pins_and_dedupe() {
        let pins = vec!["ghostty".into()];
        let wm = WmState {
            toplevels: vec![
                tl("ghostty", 1),
                tl("firefox", 1),
                tl("firefox", 1),
                tl("org.gnome.Nautilus", 1),
            ],
            ..Default::default()
        };
        let t = dock_transients(&pins, &wm);
        assert_eq!(t, vec!["firefox".to_string(), "org.gnome.Nautilus".into()]);
    }

    #[test]
    fn dock_pins_defaults_include_beacon_first() {
        let pins = dock_pins_from_settings(&serde_json::json!({}));
        assert_eq!(pins.first().map(String::as_str), Some("proteus-launcher"));
        assert!(pins.iter().any(|p| p == "proteus-settings"));
    }

    #[test]
    fn dock_pins_prepend_beacon_when_missing() {
        let pins = dock_pins_from_settings(&serde_json::json!({
            "dockPins": "ghostty,org.gnome.Nautilus"
        }));
        assert_eq!(pins[0], "proteus-launcher");
        assert!(pins.iter().any(|p| p == "ghostty"));
    }

    #[test]
    fn dock_pins_dash_keeps_beacon_and_settings() {
        let pins = dock_pins_from_settings(&serde_json::json!({ "dockPins": "-" }));
        assert_eq!(
            pins,
            vec!["proteus-launcher".to_string(), "proteus-settings".into()]
        );
    }

    #[test]
    fn bar_clock_in_process_nonempty() {
        let c = bar_clock_now();
        assert!(!c.date.is_empty());
        assert!(c.time.contains(':'), "{}", c.time);
    }

    #[test]
    fn dock_icon_geometry_rest_strip() {
        assert!((dock_plate_h(48.0, 6.0) - (12.0 + 48.0 + 10.0)).abs() < f32::EPSILON);
        assert!(
            dock_plate_h(48.0, 6.0) <= dock_strip_h(48.0) as f32,
            "plate must fit inside exclusive strip"
        );
        assert_eq!(dock_strip_h(48.0), 78); // plate 70 + 8
        assert_eq!(dock_strip_h(32.0), 62); // plate 54 + 8
        assert!((dock_icon_hover_size(48.0, 1.0) - 48.0 * DOCK_HOVER_SCALE).abs() < 1e-4);
        assert!((dock_icon_hover_size(48.0, 0.0) - 48.0).abs() < 1e-4);
    }

    #[test]
    fn dock_layout_parse() {
        assert_eq!(DockLayout::parse("span"), DockLayout::Span);
        assert_eq!(DockLayout::parse("left"), DockLayout::Left);
        assert!(DockLayout::Left.vertical());
        assert!(DockLayout::Span.span_edge());
        assert!(!DockLayout::Center.span_edge());
    }

    #[test]
    fn reorder_dock_pins_keeps_beacon_first() {
        let mut pins = vec![
            "proteus-launcher".into(),
            "a".into(),
            "b".into(),
            "c".into(),
        ];
        assert!(!reorder_dock_pins(&mut pins, 0, 2));
        assert!(!reorder_dock_pins(&mut pins, 2, 0));
        assert!(reorder_dock_pins(&mut pins, 1, 3));
        assert_eq!(pins[0], "proteus-launcher");
        assert_eq!(pins, vec!["proteus-launcher", "b", "c", "a"]);
    }

    #[test]
    fn remove_dock_pin_skips_beacon() {
        let mut pins = vec![
            "proteus-launcher".into(),
            "a".into(),
            "b".into(),
        ];
        assert!(!remove_dock_pin(&mut pins, "proteus-launcher"));
        assert!(remove_dock_pin(&mut pins, "a"));
        assert_eq!(pins, vec!["proteus-launcher", "b"]);
        assert!(!remove_dock_pin(&mut pins, "missing"));
    }

    #[test]
    fn dock_running_dots_cap_and_active() {
        let wm = WmState {
            toplevels: vec![
                tl("ghostty", 1),
                Toplevel {
                    address: "0xb".into(),
                    class: "ghostty".into(),
                    title: "b".into(),
                    workspace: 1,
                    output: String::new(),
                },
                Toplevel {
                    address: "0xc".into(),
                    class: "ghostty".into(),
                    title: "c".into(),
                    workspace: 1,
                    output: String::new(),
                },
                Toplevel {
                    address: "0xd".into(),
                    class: "ghostty".into(),
                    title: "d".into(),
                    workspace: 1,
                    output: String::new(),
                },
            ],
            active_workspace: 1,
            active_class: "ghostty".into(),
            active_title: "b".into(),
            active_address: "0xb".into(),
            ..Default::default()
        };
        let running = dock_running_windows("ghostty", &wm);
        assert_eq!(running.len(), 4);
        assert_eq!(dock_dot_count(running.len()), 3);
        assert_eq!(dock_active_dot_index("ghostty", &wm, &running), Some(1));
        assert_eq!(dock_running_windows("proteus-launcher", &wm).len(), 0);
    }
}
