//! Proteus chrome theme — iced colors derived from shell-core tokens.

use iced::widget::{button, container, text};
use iced::{Background, Border, Color};
use proteus_shell_core::tokens::{self, ModeSurfaces, ACCENT_DEFAULT, DANGER, RADIUS, SPACE};

/// Light or dark chrome mode.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ChromeMode {
    Light,
    Dark,
}

impl ChromeMode {
    fn from_str(mode: &str) -> Self {
        match mode.trim().to_lowercase().as_str() {
            "light" => Self::Light,
            _ => Self::Dark,
        }
    }
}

/// Runtime chrome palette for iced renderers.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Theme {
    pub mode: ChromeMode,
    pub space_xs: f32,
    pub space_sm: f32,
    pub space_md: f32,
    pub space_lg: f32,
    pub space_xl: f32,
    pub radius_sm: f32,
    pub radius: f32,
    pub radius_md: f32,
    pub radius_lg: f32,
    pub radius_xl: f32,
    pub radius_pill: f32,
    pub danger: Color,
    pub accent: Color,
    /// Soft selection wash — accent @ 14% light / 22% dark (CHROME.md §4).
    pub accent_soft: Color,
    pub bg: Color,
    pub bg_panel: Color,
    pub bg_elevated: Color,
    pub bg_hover: Color,
    pub border: Color,
    pub separator: Color,
    pub text: Color,
    pub text_dim: Color,
    pub text_mute: Color,
    /// Dim-overlay scrim (`scrimFill`) — bg @ 28% light / 45% dark.
    pub scrim: Color,
    /// Hairline on glass chrome (`chromeHairline`).
    pub hairline: Color,
    /// Traffic lights — close / minimize / maximize (QML TopBar parity).
    pub light_close: Color,
    pub light_min: Color,
    pub light_max: Color,
    /// Privacy semantics — mic / camera / screen-share indicator colors.
    pub privacy_mic: Color,
    pub privacy_cam: Color,
    pub privacy_screen: Color,
    /// Default squircle icon plate fill (`iconPlateDefault`).
    pub icon_plate: Color,
    /// Dock frost amount (`glassAlpha`) — richer floor from `chromeOpacity`.
    pub glass_alpha: f32,
    /// Menu bar frost (`menuBarAlpha`) — clearer curve from `chromeOpacity`.
    pub menu_bar_alpha: f32,
    /// Raw `chromeOpacity` Fact (0..=1).
    pub chrome_opacity: f32,
}

impl Default for Theme {
    fn default() -> Self {
        Self::from_mode("dark", None)
    }
}

impl Theme {
    /// Build a theme from chrome mode and an optional `#rrggbb` accent override.
    pub fn from_mode(mode: &str, accent: Option<&str>) -> Self {
        let chrome_mode = ChromeMode::from_str(mode);
        let surfaces = match chrome_mode {
            ChromeMode::Light => &tokens::LIGHT,
            ChromeMode::Dark => &tokens::DARK,
        };
        let accent_color = accent
            .filter(|s| !s.trim().is_empty())
            .and_then(parse_hex)
            .unwrap_or_else(|| parse_hex(ACCENT_DEFAULT).expect("default accent"));

        Self::from_surfaces(chrome_mode, surfaces, accent_color)
    }

    /// Build a theme from Proteus settings JSON (`chromeMode`, `accentCustom`,
    /// `accentCustomEnabled`, `chromeOpacity`).
    pub fn from_settings(settings: &serde_json::Value) -> Self {
        let mode = settings
            .get("chromeMode")
            .and_then(|v| v.as_str())
            .unwrap_or("dark");

        let accent = if settings
            .get("accentCustomEnabled")
            .and_then(|v| v.as_bool())
            .unwrap_or(false)
        {
            settings
                .get("accentCustom")
                .and_then(|v| v.as_str())
        } else {
            None
        };

        let mut theme = Self::from_mode(mode, accent);
        let opacity = settings
            .get("chromeOpacity")
            .and_then(|v| v.as_f64())
            .unwrap_or(0.28) as f32;
        theme.apply_chrome_opacity(opacity);
        theme
    }

    /// Derive `glass_alpha` / `menu_bar_alpha` from `chromeOpacity` (CHROME §5).
    /// Dark default 0.28 → glass ≈0.90, menu ≈0.40 (dock richer, bar clearer).
    pub fn apply_chrome_opacity(&mut self, opacity: f32) {
        let op = opacity.clamp(0.0, 1.0);
        self.chrome_opacity = op;
        // Liquid Glass v1: dock richer frost; menu bar clearer (wallpaper-first).
        match self.mode {
            ChromeMode::Dark => {
                self.glass_alpha = (op * 1.65 + 0.44).min(0.97);
                self.menu_bar_alpha = (op * 0.85 + 0.16).min(0.82);
            }
            ChromeMode::Light => {
                self.glass_alpha = (op * 1.25 + 0.62).min(0.98);
                self.menu_bar_alpha = (op * 0.75 + 0.42).min(0.90);
            }
        }
    }

    /// Page background color.
    pub fn background_color(&self) -> Color {
        self.bg
    }

    /// Primary body text color.
    pub fn text_color(&self) -> Color {
        self.text
    }

    /// Accent / action color.
    pub fn accent_color(&self) -> Color {
        self.accent
    }

    /// Destructive action color.
    pub fn danger_color(&self) -> Color {
        self.danger
    }

    /// Elevated panel background for containers.
    pub fn panel_style(&self) -> impl Fn(&iced::Theme) -> container::Style + Copy {
        let bg = self.bg_elevated;
        let border = self.border;
        let radius = self.radius;
        move |_theme| container::Style {
            background: Some(Background::Color(bg)),
            border: Border {
                radius: radius.into(),
                width: 1.0,
                color: border,
            },
            ..Default::default()
        }
    }

    /// Primary filled button style using the accent color.
    pub fn accent_button_style(
        &self,
    ) -> impl Fn(&iced::Theme, button::Status) -> button::Style + Copy {
        let accent = self.accent;
        let hover = lighten(accent, 0.08);
        let pressed = darken(accent, 0.08);
        move |_theme, status| {
            let background = match status {
                button::Status::Active => accent,
                button::Status::Hovered => hover,
                button::Status::Pressed => pressed,
                button::Status::Disabled => fade(accent, 0.45),
            };
            button::Style {
                background: Some(Background::Color(background)),
                text_color: contrasting_text(background),
                border: Border {
                    radius: 8.0.into(),
                    width: 0.0,
                    color: Color::TRANSPARENT,
                },
                ..Default::default()
            }
        }
    }

    /// Quiet chrome button — transparent at rest, brightness on hover
    /// (hover is brightness, never accent — CHROME.md §9).
    pub fn ghost_button_style(
        &self,
    ) -> impl Fn(&iced::Theme, button::Status) -> button::Style + Copy {
        let hover = self.bg_hover;
        let pressed = self.bg_elevated;
        let text_color = self.text;
        let radius = self.radius;
        move |_theme, status| {
            let background = match status {
                button::Status::Hovered => Some(Background::Color(hover)),
                button::Status::Pressed => Some(Background::Color(pressed)),
                _ => None,
            };
            button::Style {
                background,
                text_color,
                border: Border {
                    radius: radius.into(),
                    width: 0.0,
                    color: Color::TRANSPARENT,
                },
                ..Default::default()
            }
        }
    }

    /// Compact Settings control (Advanced… / Night Shift… posture) — hairline,
    /// shrink-to-label. Fill only on hover/press so highlight means the button.
    pub fn compact_button_style(
        &self,
    ) -> impl Fn(&iced::Theme, button::Status) -> button::Style + Copy {
        let hover = self.bg_hover;
        let pressed = lighten(self.bg_hover, 0.04);
        let text_color = self.text;
        let border = self.border;
        let radius = self.radius_md;
        move |_theme, status| {
            let (background, border_c) = match status {
                button::Status::Hovered => (Some(Background::Color(hover)), border),
                button::Status::Pressed => (Some(Background::Color(pressed)), border),
                button::Status::Disabled => (None, fade(border, 0.45)),
                button::Status::Active => (None, border),
            };
            button::Style {
                background,
                text_color,
                border: Border {
                    radius: radius.into(),
                    width: 1.0,
                    color: border_c,
                },
                ..Default::default()
            }
        }
    }

    /// Destructive filled button using the danger color.
    pub fn danger_button_style(
        &self,
    ) -> impl Fn(&iced::Theme, button::Status) -> button::Style + Copy {
        let danger = self.danger;
        let hover = lighten(danger, 0.08);
        let pressed = darken(danger, 0.08);
        move |_theme, status| {
            let background = match status {
                button::Status::Active => danger,
                button::Status::Hovered => hover,
                button::Status::Pressed => pressed,
                button::Status::Disabled => fade(danger, 0.45),
            };
            button::Style {
                background: Some(Background::Color(background)),
                text_color: contrasting_text(background),
                border: Border {
                    radius: 8.0.into(),
                    width: 0.0,
                    color: Color::TRANSPARENT,
                },
                ..Default::default()
            }
        }
    }

    /// Body text style helper for [`text`].
    pub fn body_text_style(&self) -> impl Fn(&iced::Theme) -> text::Style + Copy {
        let color = self.text;
        move |_theme| text::Style { color: Some(color) }
    }

    /// Dimmed label text style helper for [`text`].
    pub fn dim_text_style(&self) -> impl Fn(&iced::Theme) -> text::Style + Copy {
        let color = self.text_dim;
        move |_theme| text::Style { color: Some(color) }
    }

    fn from_surfaces(mode: ChromeMode, surfaces: &ModeSurfaces, accent: Color) -> Self {
        let bg = parse_css_color(surfaces.bg);
        let (accent_soft_a, scrim_a) = match mode {
            ChromeMode::Light => (0.14, 0.28),
            ChromeMode::Dark => (0.22, 0.45),
        };
        let hairline = match mode {
            ChromeMode::Light => Color::from_rgba(0.0, 0.0, 0.0, 0.10),
            ChromeMode::Dark => Color::from_rgba(1.0, 1.0, 1.0, 0.08),
        };
        let icon_plate = match mode {
            ChromeMode::Light => Color::from_rgba(0.86, 0.87, 0.90, 0.92),
            ChromeMode::Dark => Color::from_rgba(0.18, 0.19, 0.22, 0.88),
        };
        let mut theme = Self {
            mode,
            accent_soft: fade(accent, accent_soft_a),
            scrim: fade(bg, scrim_a),
            hairline,
            light_close: Color::from_rgb8(0xff, 0x5f, 0x57),
            light_min: Color::from_rgb8(0xfe, 0xbc, 0x2e),
            light_max: Color::from_rgb8(0x28, 0xc8, 0x40),
            privacy_mic: Color::from_rgb(1.0, 0.55, 0.10),
            privacy_cam: Color::from_rgb(0.20, 0.75, 0.35),
            privacy_screen: Color::from_rgb(0.55, 0.35, 0.85),
            icon_plate,
            glass_alpha: 0.82,
            menu_bar_alpha: 0.55,
            chrome_opacity: 0.28,
            space_xs: token_px(&SPACE, "spaceXs"),
            space_sm: token_px(&SPACE, "spaceSm"),
            space_md: token_px(&SPACE, "spaceMd"),
            space_lg: token_px(&SPACE, "spaceLg"),
            space_xl: token_px(&SPACE, "spaceXl"),
            radius_sm: token_px(&RADIUS, "radiusSm"),
            radius: token_px(&RADIUS, "radius"),
            radius_md: token_px(&RADIUS, "radiusMd"),
            radius_lg: token_px(&RADIUS, "radiusLg"),
            radius_xl: token_px(&RADIUS, "radiusXl"),
            radius_pill: token_px(&RADIUS, "radiusPill"),
            danger: parse_css_color(DANGER),
            accent,
            bg,
            bg_panel: parse_css_color(surfaces.bg_panel),
            bg_elevated: parse_css_color(surfaces.bg_elevated),
            bg_hover: parse_css_color(surfaces.bg_hover),
            border: parse_css_color(surfaces.border),
            separator: parse_css_color(surfaces.separator),
            text: parse_css_color(surfaces.text),
            text_dim: parse_css_color(surfaces.text_dim),
            text_mute: parse_css_color(surfaces.text_mute),
        };
        theme.apply_chrome_opacity(0.28);
        theme
    }
}

fn token_px(table: &[(&str, u32)], key: &str) -> f32 {
    table
        .iter()
        .find(|(k, _)| *k == key)
        .map(|(_, v)| *v as f32)
        .unwrap_or(0.0)
}

/// Parse `#rrggbb` or `#rgb`.
pub fn parse_hex(s: &str) -> Option<Color> {
    s.trim().parse::<Color>().ok()
}

fn parse_css_color(s: &str) -> Color {
    if let Some(color) = parse_hex(s) {
        return color;
    }
    let s = s.trim();
    if let Some(inner) = s
        .strip_prefix("rgba(")
        .and_then(|rest| rest.strip_suffix(')'))
    {
        let parts: Vec<&str> = inner.split(',').map(str::trim).collect();
        if parts.len() == 4 {
            if let (Ok(r), Ok(g), Ok(b), Ok(a)) = (
                parts[0].parse::<f32>(),
                parts[1].parse::<f32>(),
                parts[2].parse::<f32>(),
                parts[3].parse::<f32>(),
            ) {
                return Color::from_rgba(r / 255.0, g / 255.0, b / 255.0, a);
            }
        }
    }
    Color::BLACK
}

/// Additively brighten a color (hover feedback).
pub fn lighten(color: Color, amount: f32) -> Color {
    Color::from_rgba(
        (color.r + amount).min(1.0),
        (color.g + amount).min(1.0),
        (color.b + amount).min(1.0),
        color.a,
    )
}

/// Additively darken a color (pressed feedback).
pub fn darken(color: Color, amount: f32) -> Color {
    Color::from_rgba(
        (color.r - amount).max(0.0),
        (color.g - amount).max(0.0),
        (color.b - amount).max(0.0),
        color.a,
    )
}

/// Same color at a different alpha.
pub fn fade(color: Color, alpha: f32) -> Color {
    Color::from_rgba(color.r, color.g, color.b, alpha)
}

/// Black or white, whichever reads on the given background.
pub fn contrasting_text(background: Color) -> Color {
    let luminance = 0.2126 * background.r + 0.7152 * background.g + 0.0722 * background.b;
    if luminance > 0.55 {
        Color::BLACK
    } else {
        Color::WHITE
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn from_mode_light_and_dark_have_distinct_backgrounds() {
        let light = Theme::from_mode("light", None);
        let dark = Theme::from_mode("dark", None);
        assert_ne!(light.background_color(), dark.background_color());
        assert_eq!(light.mode, ChromeMode::Light);
        assert_eq!(dark.mode, ChromeMode::Dark);
    }

    #[test]
    fn accent_hex_override_parses_rrggbb() {
        let theme = Theme::from_mode("dark", Some("#ff00aa"));
        assert!((theme.accent.r - 1.0).abs() < f32::EPSILON);
        assert!(theme.accent.g.abs() < f32::EPSILON);
        assert!((theme.accent.b - 0.6666667).abs() < 0.001);
    }

    #[test]
    fn from_settings_reads_chrome_and_custom_accent() {
        let settings = serde_json::json!({
            "chromeMode": "light",
            "accentCustomEnabled": true,
            "accentCustom": "#112233"
        });
        let theme = Theme::from_settings(&settings);
        assert_eq!(theme.mode, ChromeMode::Light);
        assert!((theme.accent.r - 0.06666667).abs() < 0.001);
        assert!((theme.accent.g - 0.13333334).abs() < 0.001);
        assert!((theme.accent.b - 0.2).abs() < 0.001);
    }

    #[test]
    fn from_settings_derives_glass_alpha_from_chrome_opacity() {
        let settings = serde_json::json!({
            "chromeMode": "dark",
            "chromeOpacity": 0.28
        });
        let theme = Theme::from_settings(&settings);
        assert!((theme.glass_alpha - 0.90).abs() < 0.03);
        assert!((theme.menu_bar_alpha - 0.40).abs() < 0.03);
        assert!(theme.glass_alpha > theme.menu_bar_alpha);
    }

    #[test]
    fn semantic_tokens_track_mode() {
        let light = Theme::from_mode("light", None);
        let dark = Theme::from_mode("dark", None);
        assert!((light.accent_soft.a - 0.14).abs() < 0.001);
        assert!((dark.accent_soft.a - 0.22).abs() < 0.001);
        assert!(dark.scrim.a > light.scrim.a);
        assert_ne!(light.hairline, dark.hairline);
        // Traffic lights are mode-independent.
        assert_eq!(light.light_close, dark.light_close);
        assert!((light.light_close.r - 1.0).abs() < 0.01);
    }

    #[test]
    fn from_settings_ignores_custom_accent_when_disabled() {
        let settings = serde_json::json!({
            "chromeMode": "dark",
            "accentCustomEnabled": false,
            "accentCustom": "#ff00aa"
        });
        let theme = Theme::from_settings(&settings);
        let default = Theme::from_mode("dark", None);
        assert_eq!(theme.accent, default.accent);
    }
}
