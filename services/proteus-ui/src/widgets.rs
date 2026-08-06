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
pub fn menu_bar_plate<'a, Message: Clone + 'a>(
    theme: &'a Theme,
    content: impl Into<Element<'a, Message>>,
) -> Element<'a, Message> {
    let base = theme.bg_panel;
    let alpha = if theme.mode == crate::theme::ChromeMode::Dark {
        0.55
    } else {
        0.78
    };
    let fill = Color::from_rgba(base.r, base.g, base.b, alpha);
    let hair = if theme.mode == crate::theme::ChromeMode::Dark {
        Color::from_rgba(1.0, 1.0, 1.0, 0.10)
    } else {
        Color::from_rgba(0.0, 0.0, 0.0, 0.08)
    };

    container(content)
        .width(Length::Fill)
        .padding([theme.space_xs, theme.space_md])
        .style(move |_t| container::Style {
            background: Some(solid(fill)),
            border: Border {
                width: 1.0,
                color: hair,
                radius: 0.0.into(),
            },
            ..Default::default()
        })
        .into()
}

/// Dock continuous frost — richer floor than menu bar (`glassAlpha` / dock plate).
pub fn dock_plate<'a, Message: Clone + 'a>(
    theme: &'a Theme,
    content: impl Into<Element<'a, Message>>,
) -> Element<'a, Message> {
    let base = theme.bg_panel;
    let alpha = if theme.mode == crate::theme::ChromeMode::Dark {
        0.82
    } else {
        0.92
    };
    let fill = Color::from_rgba(base.r, base.g, base.b, alpha);
    let border = fade(theme.border, 0.55);
    let glow = fade(theme.accent, 0.12);
    let radius = theme.radius_xl;

    container(content)
        .padding([theme.space_sm, theme.space_md])
        .style(move |_t| container::Style {
            background: Some(solid(fill)),
            border: Border {
                radius: radius.into(),
                width: 1.0,
                color: Color::from_rgba(
                    (border.r * 0.7 + glow.r * 0.3).min(1.0),
                    (border.g * 0.7 + glow.g * 0.3).min(1.0),
                    (border.b * 0.7 + glow.b * 0.3).min(1.0),
                    border.a.max(glow.a),
                ),
            },
            ..Default::default()
        })
        .into()
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

/// Settings-style row: fixed-width label on the left, control on the right.
pub fn form_row<'a, Message: Clone + 'a>(
    theme: &'a Theme,
    label: &'a str,
    content: Element<'a, Message>,
) -> Element<'a, Message> {
    row![
        container(text(label).style(theme.dim_text_style()))
            .width(Length::Fixed(148.0))
            .align_x(Alignment::Start)
            .align_y(Alignment::Center),
        container(content)
            .width(Length::Fill)
            .align_x(Alignment::Start)
            .align_y(Alignment::Center),
    ]
    .spacing(theme.space_md)
    .align_y(Alignment::Center)
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

