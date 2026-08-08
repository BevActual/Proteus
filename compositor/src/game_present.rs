//! Game-present Fact + policy for owned compositor (Gamescope interim retire).
//!
//! Path: `~/.config/proteus/game-present` (JSON). Knobs apply when a toplevel
//! is tagged into game-present mode via `dispatch game-present …`.

use serde_json::Value;
use std::path::PathBuf;

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
}
