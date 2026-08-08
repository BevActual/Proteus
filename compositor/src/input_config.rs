//! Pointer / touchpad Facts from `~/.config/proteus/settings.json`.
//!
//! Loaded at compositor start; live-reloaded via `dispatch input-reload`
//! (`proteus-settings-apply input`). Sensitivity + natural scroll + scroll
//! factor affect event routing in [`crate::input`]. Tap / accel / DWT are
//! held for libinput device config (DRM path) — nested winit has no libinput.

use std::path::PathBuf;

use serde_json::Value;

/// Live input preferences from settings.json.
#[derive(Debug, Clone, PartialEq)]
pub struct InputConfig {
    /// `mouseSensitivity` — typical −1‥1 (default 0).
    pub sensitivity: f64,
    /// `mouseAccelFlat` when present.
    pub accel_flat: bool,
    /// `mouseAccelProfile` when present (`flat` / `adaptive` / …).
    pub accel_profile: Option<String>,
    pub natural_scroll: bool,
    pub tap_to_click: bool,
    pub disable_while_typing: bool,
    /// `touchpadScrollFactor` (default 1.0).
    pub scroll_factor: f64,
}

impl Default for InputConfig {
    fn default() -> Self {
        Self {
            sensitivity: 0.0,
            accel_flat: false,
            accel_profile: None,
            natural_scroll: false,
            tap_to_click: true,
            disable_while_typing: true,
            scroll_factor: 1.0,
        }
    }
}

impl InputConfig {
    /// Multiplier for pointer deltas: `1.0 + sensitivity`, clamped.
    ///
    /// Fact range is usually −1‥1 → scale 0.05‥2.0; values up to 2 map to ≤3.
    pub fn sensitivity_scale(&self) -> f64 {
        let s = if self.sensitivity.is_finite() {
            self.sensitivity.clamp(-1.0, 2.0)
        } else {
            0.0
        };
        (1.0 + s).clamp(0.05, 3.0)
    }

    pub fn scroll_scale(&self) -> f64 {
        if self.scroll_factor.is_finite() {
            self.scroll_factor.clamp(0.1, 3.0)
        } else {
            1.0
        }
    }

    pub fn settings_fact_path() -> PathBuf {
        if let Ok(xdg) = std::env::var("XDG_CONFIG_HOME") {
            if !xdg.is_empty() {
                return PathBuf::from(xdg).join("proteus/settings.json");
            }
        }
        let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".into());
        PathBuf::from(home).join(".config/proteus/settings.json")
    }

    pub fn load() -> Self {
        let path = Self::settings_fact_path();
        let Ok(raw) = std::fs::read_to_string(&path) else {
            return Self::default();
        };
        Self::from_settings_json(&raw)
    }

    pub fn reload(&mut self) {
        *self = Self::load();
    }

    pub fn from_settings_json(raw: &str) -> Self {
        let Ok(v) = serde_json::from_str::<Value>(raw) else {
            eprintln!("proteus-compositor: settings.json: invalid JSON (input)");
            return Self::default();
        };
        Self::from_value(&v)
    }

    pub fn from_value(v: &Value) -> Self {
        let mut cfg = Self::default();
        if let Some(s) = real_field(v, "mouseSensitivity") {
            cfg.sensitivity = s;
        }
        if let Some(b) = v.get("mouseAccelFlat").and_then(|x| x.as_bool()) {
            cfg.accel_flat = b;
        }
        if let Some(p) = v.get("mouseAccelProfile").and_then(|x| x.as_str()) {
            let p = p.trim();
            if !p.is_empty() {
                cfg.accel_profile = Some(p.to_string());
            }
        }
        // Flat toggle implies flat profile when profile key absent.
        if cfg.accel_flat && cfg.accel_profile.is_none() {
            cfg.accel_profile = Some("flat".into());
        }
        if let Some(b) = v.get("touchpadNaturalScroll").and_then(|x| x.as_bool()) {
            cfg.natural_scroll = b;
        }
        if let Some(b) = v.get("touchpadTapToClick").and_then(|x| x.as_bool()) {
            cfg.tap_to_click = b;
        }
        if let Some(b) = v
            .get("touchpadDisableWhileTyping")
            .and_then(|x| x.as_bool())
        {
            cfg.disable_while_typing = b;
        }
        if let Some(s) = real_field(v, "touchpadScrollFactor") {
            cfg.scroll_factor = s;
        }
        cfg
    }
}

fn real_field(v: &Value, key: &str) -> Option<f64> {
    v.get(key)
        .and_then(|x| x.as_f64().or_else(|| x.as_i64().map(|i| i as f64)))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sensitivity_scale_default() {
        let c = InputConfig::default();
        assert!((c.sensitivity_scale() - 1.0).abs() < 1e-9);
    }

    #[test]
    fn sensitivity_scale_ends() {
        let mut c = InputConfig::default();
        c.sensitivity = -1.0;
        assert!((c.sensitivity_scale() - 0.05).abs() < 1e-9);
        c.sensitivity = 1.0;
        assert!((c.sensitivity_scale() - 2.0).abs() < 1e-9);
    }

    #[test]
    fn from_settings_keys() {
        let raw = r#"{
          "mouseSensitivity": 0.5,
          "mouseAccelFlat": true,
          "touchpadNaturalScroll": true,
          "touchpadTapToClick": false,
          "touchpadDisableWhileTyping": false,
          "touchpadScrollFactor": 1.5
        }"#;
        let c = InputConfig::from_settings_json(raw);
        assert!((c.sensitivity - 0.5).abs() < 1e-9);
        assert!(c.accel_flat);
        assert_eq!(c.accel_profile.as_deref(), Some("flat"));
        assert!(c.natural_scroll);
        assert!(!c.tap_to_click);
        assert!(!c.disable_while_typing);
        assert!((c.scroll_factor - 1.5).abs() < 1e-9);
        assert!((c.sensitivity_scale() - 1.5).abs() < 1e-9);
    }
}
