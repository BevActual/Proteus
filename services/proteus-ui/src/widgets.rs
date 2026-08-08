//! Reusable iced view helpers for Proteus chrome.

use crate::theme::{contrasting_text, darken, fade, lighten, Theme};
use iced::widget::button::Status as ButtonStatus;
use iced::widget::{button, column, container, row, slider, text, text_input, toggler, Space};
use iced::{Alignment, Background, Border, Color, Element, Length};

/// Squircle corner ratio from the QML chrome (`Theme.squircleCornerRatio`).
pub const SQUIRCLE_RATIO: f32 = 0.2237;

fn solid(color: Color) -> Background {
    Background::Color(color)
}

/// Frosted panel with rounded corners and a translucent fill.
pub fn glass_plate<'a, Message: Clone + 'a>(
    theme: &'a Theme,
    content: impl Into<Element<'a, Message>>,
) -> Element<'a, Message> {
    let base = theme.bg_panel;
    let alpha = if theme.mode == crate::theme::ChromeMode::Dark {
        0.72
    } else {
        0.88
    };
    let fill = Color::from_rgba(base.r, base.g, base.b, alpha);
    let border = fade(theme.border, 0.65);
    let radius = theme.radius_lg;

    container(content)
        .padding([theme.space_md, theme.space_lg])
        .style(move |_theme| container::Style {
            background: Some(solid(fill)),
            border: Border {
                radius: radius.into(),
                width: 1.0,
                color: border,
            },
            ..Default::default()
        })
        .into()
}

/// Menu bar plate — wallpaper-first clearer curve (`menuBarAlpha`-class).
/// `rounding` 0 = edge-to-edge square (default); higher = floating pill strip.
pub fn menu_bar_plate<'a, Message: Clone + 'a>(
    theme: &'a Theme,
    rounding: f32,
    content: impl Into<Element<'a, Message>>,
) -> Element<'a, Message> {
    let base = theme.bg_panel;
    let alpha = theme.menu_bar_alpha;
    let fill = Color::from_rgba(base.r, base.g, base.b, alpha);
    let hair = if theme.mode == crate::theme::ChromeMode::Dark {
        Color::from_rgba(1.0, 1.0, 1.0, 0.10)
    } else {
        Color::from_rgba(0.0, 0.0, 0.0, 0.08)
    };
    let radius = rounding.max(0.0);

    container(content)
        .width(Length::Fill)
        .padding([theme.space_xs, theme.space_md])
        .style(move |_t| container::Style {
            background: Some(solid(fill)),
            border: Border {
                width: 1.0,
                color: hair,
                radius: radius.into(),
            },
            ..Default::default()
        })
        .into()
}

/// Dock continuous frost — richer floor than menu bar (`glassAlpha` / dock plate).
/// Soft accent-tinted rim loops the full rounded plate (`dockEdgeGlow`); outer
/// 1px edge pad lifts the shelf so the glow isn't clipped at the surface edge.
///
/// `plate_extent` is the rest glass thickness (height for bottom docks, width for
/// side docks). `span` fills the edge; otherwise the plate hugs icon content.
pub fn dock_plate<'a, Message: Clone + 'a>(
    theme: &'a Theme,
    plate_extent: f32,
    rounding: f32,
    span: bool,
    vertical: bool,
    content: impl Into<Element<'a, Message>>,
) -> Element<'a, Message> {
    let base = theme.bg_panel;
    let alpha = theme.glass_alpha;
    let fill = Color::from_rgba(base.r, base.g, base.b, alpha);
    let border = fade(theme.border, 0.45);
    let glow = fade(theme.accent, 0.18);
    let radius = rounding.max(0.0);
    let edge = Color::from_rgba(
        (border.r * 0.55 + glow.r * 0.45).min(1.0),
        (border.g * 0.55 + glow.g * 0.45).min(1.0),
        (border.b * 0.55 + glow.b * 0.45).min(1.0),
        (border.a * 0.7 + glow.a).min(0.55),
    );
    let extent = plate_extent.max(1.0);
    let plate_style = move |_t: &iced::Theme| container::Style {
        background: Some(solid(fill)),
        border: Border {
            radius: radius.into(),
            width: 1.0,
            color: edge,
        },
        ..Default::default()
    };
    let icons = container(content).padding([theme.space_sm, theme.space_md]);

    // Simple padded frost around icons (pre-layout-rewrite). Stack+Fill glass
    // under Shrink parents collapsed the shelf to 0 height after reboot.
    if vertical {
        container(icons)
            .width(Length::Fixed(extent))
            .height(if span {
                Length::Fill
            } else {
                Length::Shrink
            })
            .align_x(Alignment::Center)
            .align_y(if span {
                Alignment::Start
            } else {
                Alignment::Center
            })
            .style(plate_style)
            .into()
    } else {
        container(icons)
            .height(Length::Fixed(extent))
            .width(if span {
                Length::Fill
            } else {
                Length::Shrink
            })
            .align_y(Alignment::Center)
            .align_x(if span {
                Alignment::Start
            } else {
                Alignment::Center
            })
            .style(plate_style)
            .into()
    }
}

/// Elevated chip for Status HUD / toast language (`elevatedFill` / `hudFill`).
pub fn elevated_chip<'a, Message: Clone + 'a>(
    theme: &'a Theme,
    content: impl Into<Element<'a, Message>>,
) -> Element<'a, Message> {
    let base = theme.bg_elevated;
    let alpha = if theme.mode == crate::theme::ChromeMode::Dark {
        0.88
    } else {
        0.94
    };
    let fill = Color::from_rgba(base.r, base.g, base.b, alpha);
    let border = fade(theme.border, 0.5);
    let radius = theme.radius_pill;

    container(content)
        .padding([theme.space_sm, theme.space_lg])
        .style(move |_t| container::Style {
            background: Some(solid(fill)),
            border: Border {
                radius: radius.into(),
                width: 1.0,
                color: border,
            },
            ..Default::default()
        })
        .into()
}

/// Soft Control Center tile cell.
pub fn chrome_tile<'a, Message: Clone + 'a>(
    theme: &'a Theme,
    content: impl Into<Element<'a, Message>>,
) -> Element<'a, Message> {
    let base = theme.bg_elevated;
    let alpha = if theme.mode == crate::theme::ChromeMode::Dark {
        0.55
    } else {
        0.85
    };
    let fill = Color::from_rgba(base.r, base.g, base.b, alpha);
    let border = fade(theme.border, 0.45);
    let radius = theme.radius_md;

    container(content)
        .padding(theme.space_md)
        .width(Length::Fill)
        .style(move |_t| container::Style {
            background: Some(solid(fill)),
            border: Border {
                radius: radius.into(),
                width: 1.0,
                color: border,
            },
            ..Default::default()
        })
        .into()
}

/// Horizontal segmented control — one segment selected at a time.
pub fn segmented_control<'a, Message: Clone + 'a, F>(
    theme: &'a Theme,
    labels: &[&'a str],
    selected: usize,
    on_select: F,
) -> Element<'a, Message>
where
    F: Fn(usize) -> Message + Copy + 'a,
{
    let track_bg = theme.bg_panel;
    let radius = theme.radius_pill;
    let mut track = row![].spacing(2.0);
    for (index, label) in labels.iter().enumerate() {
        let is_selected = index == selected;
        let segment = button(text(*label))
            .padding([theme.space_xs, theme.space_md])
            .on_press(on_select(index))
            .style(move |_t, status| segment_button_style(theme, is_selected, status));
        track = track.push(segment);
    }

    container(track)
        .padding(3.0)
        .style(move |_t| container::Style {
            background: Some(solid(track_bg)),
            border: Border {
                radius: radius.into(),
                width: 0.0,
                color: Color::TRANSPARENT,
            },
            ..Default::default()
        })
        .into()
}

/// Settings-style row: label left, control trailing right (System Settings).
pub fn form_row<'a, Message: Clone + 'a>(
    theme: &'a Theme,
    label: &'a str,
    content: Element<'a, Message>,
) -> Element<'a, Message> {
    settings_row(theme, label.to_string(), None, content)
}

fn chrome_semibold() -> iced::Font {
    iced::Font {
        weight: iced::font::Weight::Semibold,
        ..iced::Font::DEFAULT
    }
}

/// Large content title (~30pt) — System Settings posture.
pub fn large_title<'a, Message: 'a>(
    theme: &'a Theme,
    title: impl Into<String>,
) -> Element<'a, Message> {
    text(title.into())
        .size(30.0)
        .font(chrome_semibold())
        .style(theme.body_text_style())
        .into()
}

/// Inset grouped list: optional section caption above one elevated plate;
/// rows separated by hairline `separator` (not a stack of cards).
pub fn settings_group<'a, Message: Clone + 'a>(
    theme: &'a Theme,
    title: Option<String>,
    rows: Vec<Element<'a, Message>>,
) -> Element<'a, Message> {
    let sep = theme.separator;
    let mut body = column![].spacing(0.0);
    for (i, row_el) in rows.into_iter().enumerate() {
        if i > 0 {
            body = body.push(
                container(Space::new().width(Length::Fill).height(1.0))
                    .padding([0.0, theme.space_md])
                    .style(move |_t| container::Style {
                        background: Some(solid(sep)),
                        ..Default::default()
                    }),
            );
        }
        body = body.push(
            container(row_el)
                .padding([theme.space_sm + 2.0, theme.space_md])
                .width(Length::Fill),
        );
    }
    let plate_fill = theme.bg_elevated;
    let border = fade(theme.border, 0.55);
    let radius = theme.radius_md;
    let plate = container(body)
        .width(Length::Fill)
        .style(move |_t| container::Style {
            background: Some(solid(plate_fill)),
            border: Border {
                radius: radius.into(),
                width: 1.0,
                color: border,
            },
            ..Default::default()
        });

    if let Some(t) = title {
        column![
            text(t)
                .size(12.0)
                .font(chrome_semibold())
                .style(theme.dim_text_style()),
            plate,
        ]
        .spacing(theme.space_sm)
        .width(Length::Fill)
        .into()
    } else {
        plate.into()
    }
}

/// Form row with optional mute caption under the label; control trailing.
pub fn settings_row<'a, Message: Clone + 'a>(
    theme: &'a Theme,
    label: String,
    caption: Option<String>,
    content: Element<'a, Message>,
) -> Element<'a, Message> {
    let label_col: Element<'a, Message> = if let Some(cap) = caption {
        column![
            text(label).size(14.0).style(theme.body_text_style()),
            text(cap).size(11.0).style(theme.dim_text_style()),
        ]
        .spacing(2.0)
        .width(Length::Fill)
        .into()
    } else {
        text(label)
            .size(14.0)
            .style(theme.body_text_style())
            .width(Length::Fill)
            .into()
    };
    // Label takes leftover space; trailing hugs content (Shrink). Compact buttons
    // must not sit in a Fill slot or hover wash reads as a full-width strip.
    // Wide controls (sliders) should set their own Fixed/Fill width.
    row![
        container(label_col)
            .width(Length::Fill)
            .align_y(Alignment::Center),
        container(content)
            .width(Length::Shrink)
            .align_x(Alignment::End)
            .align_y(Alignment::Center),
    ]
    .spacing(theme.space_md)
    .align_y(Alignment::Center)
    .width(Length::Fill)
    .into()
}

/// Hub › leaf navigation row — inset list row with trailing chevron (not a CTA).
/// Full-width inside `settings_group`; transparent at rest; hover/focus wash only
/// on this row (never a full-column accent strip).
pub fn hub_row<'a, Message: Clone + 'a>(
    theme: &'a Theme,
    label: String,
    focused: bool,
    message: Message,
) -> Element<'a, Message> {
    let hover = theme.bg_hover;
    let accent_soft = theme.accent_soft;
    let accent = theme.accent;
    let text_c = theme.text;
    let chevron_c = theme.text_dim;
    let radius = theme.radius_sm;
    button(
        row![
            text(label).size(14.0).color(text_c).width(Length::Fill),
            text("›")
                .size(22.0)
                .color(chevron_c)
                .font(chrome_semibold()),
        ]
        .align_y(Alignment::Center)
        .spacing(theme.space_sm),
    )
    .width(Length::Fill)
    // ~44pt hit target with group horizontal padding; no filled slab at rest.
    .padding([theme.space_sm, theme.space_xs])
    .on_press(message)
    .style(move |_t, status| {
        let background = if focused {
            Some(solid(accent_soft))
        } else {
            match status {
                ButtonStatus::Hovered | ButtonStatus::Pressed => Some(solid(hover)),
                _ => None,
            }
        };
        button::Style {
            background,
            text_color: text_c,
            border: Border {
                radius: radius.into(),
                width: if focused { 1.0 } else { 0.0 },
                color: if focused { accent } else { Color::TRANSPARENT },
            },
            ..Default::default()
        }
    })
    .into()
}

/// Sidebar hub pill — selected uses `accent_soft` + accent label.
/// `focused` is the keyboard caret (arrow-key nav); may differ from `selected`.
pub fn sidebar_item<'a, Message: Clone + 'a>(
    theme: &'a Theme,
    label: String,
    badge: Option<&'a str>,
    selected: bool,
    focused: bool,
    message: Message,
) -> Element<'a, Message> {
    let accent = theme.accent;
    let accent_soft = theme.accent_soft;
    let hover = theme.bg_hover;
    let text_c = if selected || focused { accent } else { theme.text };
    let dim = theme.text_dim;
    let badge_el: Element<'a, Message> = match badge {
        Some(b) if !b.is_empty() => text(b.to_string()).size(11.0).color(dim).into(),
        _ => Space::new().width(0.0).into(),
    };
    button(
        row![
            text(label).size(14.0).color(text_c).width(Length::Fill),
            badge_el,
        ]
        .align_y(Alignment::Center)
        .spacing(theme.space_sm),
    )
    .width(Length::Fill)
    .padding([theme.space_sm, theme.space_md])
    .on_press(message)
    .style(move |_t, status| {
        let bg = if selected || focused {
            Some(solid(accent_soft))
        } else {
            match status {
                ButtonStatus::Hovered | ButtonStatus::Pressed => Some(solid(hover)),
                _ => None,
            }
        };
        button::Style {
            background: bg,
            text_color: text_c,
            border: Border {
                radius: theme.radius_md.into(),
                width: if focused && !selected { 1.0 } else { 0.0 },
                color: if focused && !selected {
                    accent
                } else {
                    Color::TRANSPARENT
                },
            },
            ..Default::default()
        }
    })
    .into()
}

/// Toggle-style button that reads visually on/off.
pub fn toggle_button<'a, Message: Clone + 'a>(
    theme: &'a Theme,
    label: &'a str,
    on: bool,
    message: Message,
) -> Element<'a, Message> {
    button(text(label))
        .padding([theme.space_xs, theme.space_md])
        .width(Length::Shrink)
        .on_press(message)
        .style(move |_t, status| toggle_button_style(theme, on, status))
        .into()
}

/// Underline tab bar for section navigation.
pub fn tab_bar<'a, Message: Clone + 'a, F>(
    theme: &'a Theme,
    labels: &[&'a str],
    selected: usize,
    on_select: F,
) -> Element<'a, Message>
where
    F: Fn(usize) -> Message + Copy + 'a,
{
    let mut tabs = row![].spacing(theme.space_sm);
    for (index, label) in labels.iter().enumerate() {
        let is_selected = index == selected;
        let underline = if is_selected {
            theme.accent
        } else {
            Color::TRANSPARENT
        };

        let cell = column![
            button(text(*label))
                .padding([theme.space_sm, theme.space_md])
                .on_press(on_select(index))
                .style(move |_t, status| tab_button_style(theme, is_selected, status)),
            container(Space::new().width(Length::Fill).height(2))
                .width(Length::Fill)
                .style(move |_t| container::Style {
                    background: Some(solid(underline)),
                    ..Default::default()
                }),
        ]
        .spacing(0.0);
        tabs = tabs.push(cell);
    }
    tabs.into()
}

/// Accent slider — 4px track, 18px white knob (ThemeSlider parity).
pub fn theme_slider<'a, Message: Clone + 'a, F>(
    theme: &'a Theme,
    range: std::ops::RangeInclusive<f32>,
    value: f32,
    on_change: F,
) -> Element<'a, Message>
where
    F: Fn(f32) -> Message + 'a,
{
    let accent = theme.accent;
    let track = if theme.mode == crate::theme::ChromeMode::Dark {
        Color::from_rgba(1.0, 1.0, 1.0, 0.18)
    } else {
        Color::from_rgba(0.0, 0.0, 0.0, 0.12)
    };
    let hairline = theme.hairline;

    slider(range, value, on_change)
        .height(22.0)
        .style(move |_t, status| {
            let knob = match status {
                slider::Status::Dragged => Color::from_rgb(0.94, 0.94, 0.96),
                _ => Color::WHITE,
            };
            slider::Style {
                rail: slider::Rail {
                    backgrounds: (solid(accent), solid(track)),
                    width: 4.0,
                    border: Border {
                        radius: 2.0.into(),
                        width: 0.0,
                        color: Color::TRANSPARENT,
                    },
                },
                handle: slider::Handle {
                    shape: slider::HandleShape::Circle { radius: 9.0 },
                    background: solid(knob),
                    border_width: 1.0,
                    border_color: hairline,
                },
            }
        })
        .into()
}

/// Accent switch — pill track, white thumb (ThemeSwitch parity).
pub fn theme_switch<'a, Message: Clone + 'a, F>(
    theme: &'a Theme,
    on: bool,
    on_toggle: F,
) -> Element<'a, Message>
where
    F: Fn(bool) -> Message + 'a,
{
    let accent = theme.accent;
    let off_track = if theme.mode == crate::theme::ChromeMode::Dark {
        Color::from_rgba(1.0, 1.0, 1.0, 0.16)
    } else {
        Color::from_rgba(0.0, 0.0, 0.0, 0.14)
    };
    let hairline = theme.hairline;

    toggler(on)
        .on_toggle(on_toggle)
        .size(26.0)
        .style(move |_t, status| {
            let track = if on {
                match status {
                    toggler::Status::Hovered { .. } => lighten(accent, 0.06),
                    _ => accent,
                }
            } else {
                match status {
                    toggler::Status::Hovered { .. } => lighten(off_track, 0.04),
                    _ => off_track,
                }
            };
            toggler::Style {
                background: solid(track),
                background_border_width: 1.0,
                background_border_color: hairline,
                foreground: solid(Color::WHITE),
                foreground_border_width: 0.0,
                foreground_border_color: Color::TRANSPARENT,
                text_color: None,
                border_radius: None,
                // 20px thumb in a 26px track (ThemeSwitch inset 3).
                padding_ratio: 0.115,
            }
        })
        .into()
}

/// Visual role of a [`circle_button`].
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CircleStyle {
    /// Translucent glass key (lock PIN pad).
    Glass,
    /// Quieter glass (backspace / secondary keys).
    GlassDim,
    /// Accent-filled action.
    Accent,
    /// Transparent, hover-brightness only (transport controls).
    Ghost,
}

/// Fixed-diameter circular button (PIN keys, media transport).
pub fn circle_button<'a, Message: Clone + 'a>(
    theme: &'a Theme,
    diameter: f32,
    style: CircleStyle,
    content: impl Into<Element<'a, Message>>,
    message: Option<Message>,
) -> Element<'a, Message> {
    let accent = theme.accent;
    let hover_bg = theme.bg_hover;
    let text_color = theme.text;
    let mut b = button(
        container(content)
            .width(Length::Fill)
            .height(Length::Fill)
            .align_x(Alignment::Center)
            .align_y(Alignment::Center),
    )
    .width(Length::Fixed(diameter))
    .height(Length::Fixed(diameter))
    .padding(0)
    .style(move |_t, status| {
        let (fill, fg) = match style {
            CircleStyle::Glass => {
                let base = Color::from_rgba(1.0, 1.0, 1.0, 0.16);
                let fill = match status {
                    ButtonStatus::Hovered => Color::from_rgba(1.0, 1.0, 1.0, 0.24),
                    ButtonStatus::Pressed => Color::from_rgba(1.0, 1.0, 1.0, 0.32),
                    _ => base,
                };
                (Some(fill), Color::WHITE)
            }
            CircleStyle::GlassDim => {
                let fill = match status {
                    ButtonStatus::Hovered => Color::from_rgba(1.0, 1.0, 1.0, 0.18),
                    ButtonStatus::Pressed => Color::from_rgba(1.0, 1.0, 1.0, 0.26),
                    _ => Color::from_rgba(1.0, 1.0, 1.0, 0.10),
                };
                (Some(fill), Color::WHITE)
            }
            CircleStyle::Accent => {
                let fill = match status {
                    ButtonStatus::Hovered => lighten(accent, 0.08),
                    ButtonStatus::Pressed => darken(accent, 0.08),
                    ButtonStatus::Disabled => fade(accent, 0.45),
                    _ => accent,
                };
                (Some(fill), contrasting_text(accent))
            }
            CircleStyle::Ghost => {
                let fill = match status {
                    ButtonStatus::Hovered => Some(hover_bg),
                    ButtonStatus::Pressed => Some(fade(hover_bg, 0.8)),
                    _ => None,
                };
                (fill, text_color)
            }
        };
        button::Style {
            background: fill.map(solid),
            text_color: fg,
            border: Border {
                radius: (diameter / 2.0).into(),
                width: 0.0,
                color: Color::TRANSPARENT,
            },
            ..Default::default()
        }
    });
    if let Some(message) = message {
        b = b.on_press(message);
    }
    b.into()
}

/// Fixed-size squircle icon plate (`SquircleIcon` parity — radius = size × 0.2237).
pub fn squircle_plate<'a, Message: Clone + 'a>(
    theme: &'a Theme,
    size: f32,
    content: impl Into<Element<'a, Message>>,
) -> Element<'a, Message> {
    let fill = theme.icon_plate;
    let hairline = theme.hairline;
    container(content)
        .width(Length::Fixed(size))
        .height(Length::Fixed(size))
        .align_x(Alignment::Center)
        .align_y(Alignment::Center)
        .style(move |_t| container::Style {
            background: Some(solid(fill)),
            border: Border {
                radius: (size * SQUIRCLE_RATIO).into(),
                width: 1.0,
                color: hairline,
            },
            ..Default::default()
        })
        .into()
}

/// Themed style closure for [`text_input`] — elevated fill, accent focus ring.
pub fn text_input_style(
    theme: &Theme,
) -> impl Fn(&iced::Theme, text_input::Status) -> text_input::Style + Copy {
    let accent = theme.accent;
    let accent_soft = theme.accent_soft;
    let bg = fade(theme.bg_elevated, 0.85);
    let bg_hover = fade(theme.bg_elevated, 0.95);
    let border = fade(theme.border, 0.6);
    let value = theme.text;
    let placeholder = theme.text_mute;
    let icon = theme.text_dim;
    let radius = theme.radius_md;
    move |_t, status| {
        let (background, border_color, border_width) = match status {
            text_input::Status::Focused { .. } => (bg_hover, accent, 1.5),
            text_input::Status::Hovered => (bg_hover, border, 1.0),
            text_input::Status::Disabled => (fade(bg, 0.5), border, 1.0),
            text_input::Status::Active => (bg, border, 1.0),
        };
        text_input::Style {
            background: solid(background),
            border: Border {
                radius: radius.into(),
                width: border_width,
                color: border_color,
            },
            icon,
            placeholder,
            value,
            selection: accent_soft,
        }
    }
}

fn segment_button_style(theme: &Theme, selected: bool, status: ButtonStatus) -> button::Style {
    let (background, text_color) = if selected {
        (
            Some(solid(match status {
                ButtonStatus::Hovered => lighten(theme.accent, 0.06),
                ButtonStatus::Pressed => darken(theme.accent, 0.06),
                _ => theme.accent,
            })),
            contrasting_text(theme.accent),
        )
    } else {
        (
            match status {
                ButtonStatus::Hovered => Some(solid(theme.bg_hover)),
                ButtonStatus::Pressed => Some(solid(theme.bg_elevated)),
                _ => None,
            },
            theme.text,
        )
    };

    button::Style {
        background,
        text_color,
        border: Border {
            radius: theme.radius_pill.into(),
            width: 0.0,
            color: Color::TRANSPARENT,
        },
        ..Default::default()
    }
}

fn toggle_button_style(theme: &Theme, on: bool, status: ButtonStatus) -> button::Style {
    if on {
        let accent = match status {
            ButtonStatus::Hovered => lighten(theme.accent, 0.06),
            ButtonStatus::Pressed => darken(theme.accent, 0.06),
            ButtonStatus::Disabled => fade(theme.accent, 0.45),
            _ => theme.accent,
        };
        button::Style {
            background: Some(solid(accent)),
            text_color: contrasting_text(accent),
            border: Border {
                radius: theme.radius.into(),
                width: 0.0,
                color: Color::TRANSPARENT,
            },
            ..Default::default()
        }
    } else {
        let background = match status {
            ButtonStatus::Hovered => Some(solid(theme.bg_hover)),
            ButtonStatus::Pressed => Some(solid(theme.bg_elevated)),
            _ => Some(solid(theme.bg_panel)),
        };
        button::Style {
            background,
            text_color: theme.text_dim,
            border: Border {
                radius: theme.radius.into(),
                width: 1.0,
                color: theme.border,
            },
            ..Default::default()
        }
    }
}

fn tab_button_style(theme: &Theme, selected: bool, status: ButtonStatus) -> button::Style {
    let text_color = if selected {
        theme.text
    } else {
        match status {
            ButtonStatus::Hovered => theme.text_dim,
            _ => theme.text_mute,
        }
    };

    button::Style {
        background: match status {
            ButtonStatus::Hovered if !selected => Some(solid(theme.bg_hover)),
            _ => None,
        },
        text_color,
        border: Border::default(),
        ..Default::default()
    }
}

