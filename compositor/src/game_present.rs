//! Game-present Fact + policy for owned compositor (Gamescope interim retire).
//!
//! Path: `~/.config/proteus/game-present` (JSON). Knobs apply when a toplevel
//! is tagged into game-present mode via `dispatch game-present …`.

use serde_json::Value;
use std::path::PathBuf;

/// Destination rectangle (logical px) for a game-present buffer in an output.
///
/// - **integer** — largest integer scale that fits; centered letterbox
/// - **stretch** — fill output (may non-uniform scale)
/// - **fill** — cover output preserving aspect (may crop); v1 = same as stretch
///   until crop path lands
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct PresentDst {
    pub x: i32,
    pub y: i32,
    pub w: i32,
    pub h: i32,
    /// Uniform scale applied to source for integer mode; stretch/fill use
    /// independent axes (`sx`/`sy` via w/src_w).
    pub scale: f64,
}

pub fn present_dst_rect(
    src_w: i32,
    src_h: i32,
    out_w: i32,
    out_h: i32,
    mode: ScaleMode,
) -> PresentDst {
    let src_w = src_w.max(1);
    let src_h = src_h.max(1);
    let out_w = out_w.max(1);
    let out_h = out_h.max(1);
    match mode {
        ScaleMode::Integer => {
            let sx = (out_w / src_w).max(1);
            let sy = (out_h / src_h).max(1);
            let s = sx.min(sy).max(1);
            let w = src_w * s;
            let h = src_h * s;
            PresentDst {
                x: (out_w - w) / 2,
                y: (out_h - h) / 2,
                w,
                h,
                scale: f64::from(s),
            }
        }
        ScaleMode::Stretch | ScaleMode::Fill => PresentDst {
            x: 0,
            y: 0,
            w: out_w,
            h: out_h,
            scale: f64::from(out_w) / f64::from(src_w),
        },
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum ScaleMode {
    #[default]
    Integer,
    Stretch,
    Fill,
}

impl ScaleMode {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Integer => "integer",
            Self::Stretch => "stretch",
            Self::Fill => "fill",
        }
    }

    pub fn parse(raw: &str) -> Option<Self> {
        match raw.trim().to_ascii_lowercase().as_str() {
            "integer" | "int" | "nearest-int" => Some(Self::Integer),
            "stretch" => Some(Self::Stretch),
            "fill" | "cover" => Some(Self::Fill),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum PresentFilter {
    #[default]
    Nearest,
    Linear,
}

impl PresentFilter {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Nearest => "nearest",
            Self::Linear => "linear",
        }
    }

    pub fn parse(raw: &str) -> Option<Self> {
        match raw.trim().to_ascii_lowercase().as_str() {
            "nearest" | "point" | "none" => Some(Self::Nearest),
            "linear" | "bilinear" => Some(Self::Linear),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct GamePresentPolicy {
    pub scale_mode: ScaleMode,
    pub fps_limit: u32,
    pub filter: PresentFilter,
}

impl Default for GamePresentPolicy {
    fn default() -> Self {
        Self {
            scale_mode: ScaleMode::Integer,
            fps_limit: 0,
            filter: PresentFilter::Nearest,
        }
    }
}

pub fn game_present_fact_path() -> PathBuf {
    if let Ok(xdg) = std::env::var("XDG_CONFIG_HOME") {
        return PathBuf::from(xdg).join("proteus/game-present");
    }
    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".into());
    PathBuf::from(home).join(".config/proteus/game-present")
}

/// Load policy from Fact file; missing/invalid → defaults.
pub fn load_game_present_fact() -> GamePresentPolicy {
    let path = game_present_fact_path();
    let Ok(raw) = std::fs::read_to_string(&path) else {
        return GamePresentPolicy::default();
    };
    parse_game_present_json(&raw).unwrap_or_default()
}

pub fn parse_game_present_json(raw: &str) -> Option<GamePresentPolicy> {
    let v: Value = serde_json::from_str(raw).ok()?;
    let mut p = GamePresentPolicy::default();
    if let Some(s) = v.get("scale_mode").and_then(|x| x.as_str()) {
        if let Some(m) = ScaleMode::parse(s) {
            p.scale_mode = m;
        }
    }
    if let Some(n) = v.get("fps_limit").and_then(|x| x.as_u64()) {
        p.fps_limit = n.min(u64::from(u32::MAX)) as u32;
    }
    if let Some(s) = v.get("filter").and_then(|x| x.as_str()) {
        if let Some(f) = PresentFilter::parse(s) {
            p.filter = f;
        }
    }
    Some(p)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_defaults_and_overrides() {
        let p = parse_game_present_json(
            r#"{"scale_mode":"stretch","fps_limit":60,"filter":"linear"}"#,
        )
        .unwrap();
        assert_eq!(p.scale_mode, ScaleMode::Stretch);
        assert_eq!(p.fps_limit, 60);
        assert_eq!(p.filter, PresentFilter::Linear);
    }

    #[test]
    fn present_dst_integer_letterbox() {
        let d = present_dst_rect(320, 200, 1280, 720, ScaleMode::Integer);
        assert_eq!(d.scale, 3.0); // 320*3=960 < 1280, 200*3=600 < 720; 4 would overflow height
        assert_eq!(d.w, 960);
        assert_eq!(d.h, 600);
        assert_eq!(d.x, (1280 - 960) / 2);
        assert_eq!(d.y, (720 - 600) / 2);
    }

    #[test]
    fn present_dst_stretch_fills() {
        let d = present_dst_rect(320, 200, 1280, 720, ScaleMode::Stretch);
        assert_eq!((d.x, d.y, d.w, d.h), (0, 0, 1280, 720));
    }
}
