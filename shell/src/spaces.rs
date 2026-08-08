//! Spaces Mission Control — visible-set helpers + overview surface.
//!
//! Compositor-next exposes fixed workspaces 1..=10. Grow/shrink is a shell
//! visible-set rule (occupied ∪ active + one trailing empty). Names live in
//! the `workspaceNames` Fact (chrome SoT until compositor rename exists).

use iced::widget::{button, column, container, row, text, text_input, Space};
use iced::{Alignment, Background, Border, Color, Element, Length, Padding};
use std::collections::{BTreeSet, HashMap};

use proteus_ui::theme::Theme;

use crate::surfaces::{semibold, Message};
use crate::wm_ipc::{Toplevel, WmState};

pub const SPACE_MIN: i64 = 1;
pub const SPACE_MAX: i64 = 10;

/// Equal landscape card geometry (Mission Control strip).
const CARD_W: f32 = 280.0;
const CARD_H: f32 = 200.0;
const STAGE_H: f32 = 140.0;
const MOSAIC_GAP: f32 = 4.0;

/// Thumbnail payload for one window in the overview.
#[derive(Debug, Clone)]
pub struct SpaceWinThumb {
    pub address: String,
    pub title: String,
    pub workspace: i64,
    pub handle: iced::widget::image::Handle,
}

/// Non-minimized toplevel workspace ids in 1..=10.
pub fn occupied_space_ids(hypr: &WmState) -> BTreeSet<i64> {
    hypr.toplevels
        .iter()
        .filter(|t| t.workspace >= SPACE_MIN && t.workspace <= SPACE_MAX)
        .map(|t| t.workspace)
        .collect()
}

/// Contiguous visible Spaces: through max(active, highest occupied), plus
/// exactly one trailing empty when that end slot is occupied (cap 10).
/// `floor` is a manual minimum end from the overview "+" control.
pub fn visible_space_ids(active: i64, occupied: &BTreeSet<i64>, floor: i64) -> Vec<i64> {
    let active = active.clamp(SPACE_MIN, SPACE_MAX);
    let floor = floor.clamp(SPACE_MIN, SPACE_MAX);
    let mut end = occupied
        .iter()
        .copied()
        .max()
        .unwrap_or(0)
        .max(active)
        .max(SPACE_MIN);
    if occupied.contains(&end) && end < SPACE_MAX {
        end += 1;
    }
    end = end.max(floor).min(SPACE_MAX);
    (SPACE_MIN..=end).collect()
}

/// Next/prev within the visible set (wraps).
pub fn cycle_visible(visible: &[i64], active: i64, dir: i32) -> Option<i64> {
    if visible.is_empty() {
        return None;
    }
    let idx = visible
        .iter()
        .position(|&id| id == active)
        .unwrap_or(0);
    let n = visible.len() as i32;
    let next = (idx as i32 + dir).rem_euclid(n) as usize;
    Some(visible[next])
}

/// Resolve display name for Space `id` (1-based) from `workspaceNames`.
pub fn space_name(names: &[String], id: i64) -> String {
    let idx = (id - SPACE_MIN) as usize;
    names
        .get(idx)
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| format!("Space {id}"))
}

pub fn parse_workspace_names(settings: &serde_json::Value) -> Vec<String> {
    let mut out = vec![String::new(); SPACE_MAX as usize];
    if let Some(arr) = settings.get("workspaceNames").and_then(|v| v.as_array()) {
        for (i, v) in arr.iter().enumerate().take(SPACE_MAX as usize) {
            out[i] = v.as_str().unwrap_or("").to_string();
        }
    }
    out
}

/// Patch a single name into a 10-slot list for settings write.
pub fn names_with_rename(names: &[String], id: i64, name: &str) -> Vec<String> {
    let mut out = vec![String::new(); SPACE_MAX as usize];
    for (i, n) in names.iter().enumerate().take(SPACE_MAX as usize) {
        out[i] = n.clone();
    }
    let idx = (id - SPACE_MIN) as usize;
    if idx < out.len() {
        out[idx] = name.trim().to_string();
    }
    out
}

pub fn windows_on_space<'a>(hypr: &'a WmState, id: i64) -> Vec<&'a Toplevel> {
    hypr.toplevels
        .iter()
        .filter(|t| t.workspace == id)
        .collect()
}

/// Cell sizes for an n-window mosaic inside the fixed stage (1 / 2 / 3–4).
pub fn mosaic_cell_size(n: usize) -> (f32, f32) {
    let inner_w = CARD_W - 24.0; // card padding
    let inner_h = STAGE_H;
    match n {
        0 => (inner_w, inner_h),
        1 => (inner_w, inner_h),
        2 => ((inner_w - MOSAIC_GAP) / 2.0, inner_h),
        _ => (
            (inner_w - MOSAIC_GAP) / 2.0,
            (inner_h - MOSAIC_GAP) / 2.0,
        ),
    }
}

fn thumb_tile<'a>(
    theme: &'a Theme,
    t: &Toplevel,
    thumbs: &'a HashMap<String, SpaceWinThumb>,
    drag_addr: Option<&'a str>,
    cell_w: f32,
    cell_h: f32,
) -> Element<'a, Message> {
    let accent = theme.accent;
    let mute = theme.text_mute;
    let addr = t.address.clone();
    let dragging = drag_addr == Some(addr.as_str());
    let img: Element<'a, Message> = if let Some(th) = thumbs.get(&addr) {
        iced::widget::image(th.handle.clone())
            .width(Length::Fixed(cell_w))
            .height(Length::Fixed(cell_h))
            .content_fit(iced::ContentFit::Cover)
            .into()
    } else {
        container(Space::new().width(Length::Fill).height(Length::Fill))
            .width(Length::Fixed(cell_w))
            .height(Length::Fixed(cell_h))
            .style(move |_t| container::Style {
                background: Some(Background::Color(mute.scale_alpha(0.14))),
                border: Border {
                    radius: 8.0.into(),
                    ..Default::default()
                },
                ..Default::default()
            })
            .into()
    };
    let cell = container(img)
        .width(Length::Fixed(cell_w))
        .height(Length::Fixed(cell_h))
        .style(move |_t| container::Style {
            background: Some(Background::Color(mute.scale_alpha(0.08))),
            border: Border {
                radius: 8.0.into(),
                width: if dragging { 1.5 } else { 0.0 },
                color: accent,
            },
            ..Default::default()
        });
    let addr_press = addr.clone();
    let addr_release = addr;
    iced::widget::mouse_area(cell)
        .on_press(Message::SpacesDragStart(addr_press))
        .on_release(Message::SpacesThumbRelease(addr_release))
        .into()
}

fn preview_stage<'a>(
    theme: &'a Theme,
    wins: &[&Toplevel],
    thumbs: &'a HashMap<String, SpaceWinThumb>,
    drag_addr: Option<&'a str>,
    space_id: i64,
) -> Element<'a, Message> {
    let mute = theme.text_mute;
    let hair = theme.hairline;
    let stage_style = move |_t: &iced::Theme| container::Style {
        background: Some(Background::Color(mute.scale_alpha(0.06))),
        border: Border {
            radius: 12.0.into(),
            width: 1.0,
            color: hair,
        },
        ..Default::default()
    };

    if wins.is_empty() {
        return button(
            container(
                text("Empty")
                    .size(13)
                    .color(mute),
            )
            .width(Length::Fill)
            .height(Length::Fixed(STAGE_H))
            .center_x(Length::Fill)
            .center_y(Length::Fixed(STAGE_H))
            .style(stage_style),
        )
        .padding(0)
        .style(|_t, _s| button::Style {
            background: None,
            text_color: Color::TRANSPARENT,
            border: Border::default(),
            ..Default::default()
        })
        .on_press(Message::SpacesSelect(space_id))
        .into();
    }

    let n = wins.len().min(4);
    let (cw, ch) = mosaic_cell_size(n);
    let mosaic: Element<'a, Message> = match n {
        1 => thumb_tile(theme, wins[0], thumbs, drag_addr, cw, ch),
        2 => row![
            thumb_tile(theme, wins[0], thumbs, drag_addr, cw, ch),
            thumb_tile(theme, wins[1], thumbs, drag_addr, cw, ch),
        ]
        .spacing(MOSAIC_GAP)
        .into(),
        3 => column![
            row![
                thumb_tile(theme, wins[0], thumbs, drag_addr, cw, ch),
                thumb_tile(theme, wins[1], thumbs, drag_addr, cw, ch),
            ]
            .spacing(MOSAIC_GAP),
            thumb_tile(theme, wins[2], thumbs, drag_addr, cw, ch),
        ]
        .spacing(MOSAIC_GAP)
        .into(),
        _ => column![
            row![
                thumb_tile(theme, wins[0], thumbs, drag_addr, cw, ch),
                thumb_tile(theme, wins[1], thumbs, drag_addr, cw, ch),
            ]
            .spacing(MOSAIC_GAP),
            row![
                thumb_tile(theme, wins[2], thumbs, drag_addr, cw, ch),
                thumb_tile(theme, wins[3], thumbs, drag_addr, cw, ch),
            ]
            .spacing(MOSAIC_GAP),
        ]
        .spacing(MOSAIC_GAP)
        .into(),
    };

    container(mosaic)
        .width(Length::Fill)
        .height(Length::Fixed(STAGE_H))
        .padding(6)
        .center_x(Length::Fill)
        .center_y(Length::Fixed(STAGE_H))
        .style(stage_style)
        .into()
}

/// Mission Control overview. `open_t` is 0→1 open fade (OutCubic).
pub fn overview_view<'a>(
    theme: &'a Theme,
    hypr: &'a WmState,
    names: &'a [String],
    spaces_floor: i64,
    thumbs: &'a HashMap<String, SpaceWinThumb>,
    rename_id: Option<i64>,
    rename_buf: &'a str,
    drag_addr: Option<&'a str>,
    drag_target: Option<i64>,
    open_t: f32,
) -> Element<'a, Message> {
    let accent = theme.accent;
    let accent_soft = theme.accent_soft;
    let mute = theme.text_mute;
    let hair = theme.hairline;
    let elevated = theme.bg_elevated;
    let occupied = occupied_space_ids(hypr);
    let visible = visible_space_ids(hypr.active_workspace, &occupied, spaces_floor);
    let t = open_t.clamp(0.0, 1.0);

    let mut cards = row![].spacing(16).align_y(Alignment::Center);
    for &id in &visible {
        let active = id == hypr.active_workspace;
        let wins = windows_on_space(hypr, id);
        let is_drop = drag_addr.is_some() && drag_target == Some(id);
        let border_c = if is_drop {
            accent
        } else if active {
            accent
        } else {
            hair
        };
        let border_w = if is_drop {
            1.5
        } else if active {
            1.0
        } else {
            1.0
        };
        let bg = if active {
            accent_soft
        } else {
            elevated.scale_alpha(0.94)
        };

        let header: Element<'a, Message> = if rename_id == Some(id) {
            text_input("Space name", rename_buf)
                .id("spaces-rename-input")
                .size(13)
                .padding(6)
                .on_input(Message::SpacesRenameInput)
                .on_submit(Message::SpacesRenameCommit)
                .width(Length::Fill)
                .into()
        } else {
            let label = space_name(names, id);
            let switch_id = id;
            row![
                button(
                    row![
                        text(format!("{id}"))
                            .size(11)
                            .color(if active { accent } else { mute }),
                        text(label)
                            .size(14)
                            .font(semibold())
                            .color(theme.text),
                    ]
                    .spacing(8)
                    .align_y(Alignment::Center),
                )
                .padding(Padding::from([2, 4]))
                .style(move |_t, s| button::Style {
                    background: match s {
                        button::Status::Hovered | button::Status::Pressed => {
                            Some(Background::Color(mute.scale_alpha(0.12)))
                        }
                        _ => None,
                    },
                    text_color: theme.text,
                    border: Border {
                        radius: 6.0.into(),
                        ..Default::default()
                    },
                    ..Default::default()
                })
                .on_press(Message::SpacesSelect(switch_id)),
                button(crate::icons::glyph_view("pencil", 12.0, mute))
                    .padding(Padding::from([4, 6]))
                    .style(move |_t, s| button::Style {
                        background: match s {
                            button::Status::Hovered | button::Status::Pressed => {
                                Some(Background::Color(mute.scale_alpha(0.15)))
                            }
                            _ => None,
                        },
                        text_color: mute,
                        border: Border {
                            radius: 6.0.into(),
                            ..Default::default()
                        },
                        ..Default::default()
                    })
                    .on_press(Message::SpacesRenameStart(id)),
            ]
            .spacing(6)
            .align_y(Alignment::Center)
            .into()
        };

        let stage = preview_stage(theme, &wins, thumbs, drag_addr, id);
        let card_body = column![header, stage]
            .spacing(10)
            .width(Length::Fixed(CARD_W - 24.0));
        let card = container(card_body)
            .width(Length::Fixed(CARD_W))
            .height(Length::Fixed(CARD_H))
            .padding(12)
            .style(move |_t| container::Style {
                background: Some(Background::Color(bg)),
                border: Border {
                    radius: 16.0.into(),
                    width: border_w,
                    color: border_c,
                },
                ..Default::default()
            });

        let id_enter = id;
        let id_release = id;
        cards = cards.push(
            iced::widget::mouse_area(card)
                .on_enter(Message::SpacesDragHover(id_enter))
                .on_release(Message::SpacesDrop(id_release)),
        );
    }

    let can_add = visible.last().copied().unwrap_or(SPACE_MIN) < SPACE_MAX;
    if can_add {
        let plus = button(
            container(text("+").size(28).color(theme.text_dim))
                .width(Length::Fill)
                .height(Length::Fill)
                .center_x(Length::Fill)
                .center_y(Length::Fill),
        )
        .width(Length::Fixed(72.0))
        .height(Length::Fixed(CARD_H))
        .padding(0)
        .style(move |_t, s| button::Style {
            background: Some(Background::Color(match s {
                button::Status::Hovered | button::Status::Pressed => mute.scale_alpha(0.16),
                _ => mute.scale_alpha(0.06),
            })),
            text_color: theme.text_dim,
            border: Border {
                radius: 16.0.into(),
                width: 1.0,
                color: hair,
            },
            ..Default::default()
        })
        .on_press(Message::SpacesAdd);
        cards = cards.push(plus);
    }

    let title = text("Spaces")
        .size(20)
        .font(semibold())
        .color(theme.text);

    let strip = scrollable_if_needed(cards);

    let content = column![title, strip]
        .spacing(20)
        .align_x(Alignment::Center);

    // Stronger scrim so underlying apps recede (CHROME overlay floor).
    // open_t ramps opacity on open (180ms OutCubic from main).
    let scrim = theme.scrim.scale_alpha((0.55 + 0.35 * t).min(0.92));
    let scrim_btn = button(Space::new().width(Length::Fill).height(Length::Fill))
        .padding(0)
        .style(|_t, _s| button::Style {
            background: None,
            text_color: Color::TRANSPARENT,
            border: Border::default(),
            ..Default::default()
        })
        .on_press(Message::ToggleSpaces);

    let body = container(content)
        .width(Length::Fill)
        .height(Length::Fill)
        .center_x(Length::Fill)
        .center_y(Length::Fill)
        .padding(40);

    container(iced::widget::stack![scrim_btn, body])
        .width(Length::Fill)
        .height(Length::Fill)
        .style(move |_t| container::Style {
            background: Some(Background::Color(scrim)),
            ..Default::default()
        })
        .into()
}

fn scrollable_if_needed(cards: iced::widget::Row<'_, Message>) -> Element<'_, Message> {
    iced::widget::scrollable(cards)
        .direction(iced::widget::scrollable::Direction::Horizontal(
            iced::widget::scrollable::Scrollbar::new(),
        ))
        .into()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::wm_ipc::{Toplevel, WmState};

    fn tl(ws: i64) -> Toplevel {
        Toplevel {
            address: format!("0x{ws}"),
            class: "app".into(),
            title: "t".into(),
            workspace: ws,
        }
    }

    #[test]
    fn visible_trailing_empty_when_occupied() {
        let occ: BTreeSet<i64> = [1, 2].into_iter().collect();
        assert_eq!(visible_space_ids(2, &occ, 1), vec![1, 2, 3]);
    }

    #[test]
    fn visible_active_empty_is_trailing() {
        let occ: BTreeSet<i64> = [1].into_iter().collect();
        assert_eq!(visible_space_ids(2, &occ, 1), vec![1, 2]);
    }

    #[test]
    fn visible_floor_and_cap() {
        let occ: BTreeSet<i64> = BTreeSet::new();
        assert_eq!(visible_space_ids(1, &occ, 4), vec![1, 2, 3, 4]);
        let full: BTreeSet<i64> = (1..=10).collect();
        assert_eq!(visible_space_ids(10, &full, 1).len(), 10);
    }

    #[test]
    fn cycle_wraps() {
        let v = vec![1, 2, 3];
        assert_eq!(cycle_visible(&v, 3, 1), Some(1));
        assert_eq!(cycle_visible(&v, 1, -1), Some(3));
    }

    #[test]
    fn names_rename_and_fallback() {
        let names = parse_workspace_names(&serde_json::json!({
            "workspaceNames": ["Desk", "", "Code"]
        }));
        assert_eq!(space_name(&names, 1), "Desk");
        assert_eq!(space_name(&names, 2), "Space 2");
        assert_eq!(space_name(&names, 3), "Code");
        let patched = names_with_rename(&names, 2, "  Mail  ");
        assert_eq!(space_name(&patched, 2), "Mail");
    }

    #[test]
    fn occupied_skips_minimized() {
        let hypr = WmState {
            toplevels: vec![
                tl(1),
                Toplevel {
                    address: "0xm".into(),
                    class: "x".into(),
                    title: "m".into(),
                    workspace: -1,
                },
            ],
            ..Default::default()
        };
        assert_eq!(occupied_space_ids(&hypr), BTreeSet::from([1]));
    }

    #[test]
    fn mosaic_cell_sizes_cover_layouts() {
        let (w1, h1) = mosaic_cell_size(1);
        assert!(w1 > h1 * 0.5);
        let (w2, _) = mosaic_cell_size(2);
        assert!(w2 < w1);
        let (w4, h4) = mosaic_cell_size(4);
        assert!((w4 - (CARD_W - 24.0 - MOSAIC_GAP) / 2.0).abs() < 0.01);
        assert!((h4 - (STAGE_H - MOSAIC_GAP) / 2.0).abs() < 0.01);
    }
}
