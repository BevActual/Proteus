//! Pointer / touchpad / tablet Facts from `~/.config/proteus/settings.json`.
//!
//! Loaded at compositor start; live-reloaded via `dispatch input-reload`
//! (`proteus-settings-apply input`). Sensitivity + natural scroll + scroll
//! factor affect event routing in [`crate::input`]. Tap / accel / DWT are
//! held for libinput device config (DRM path) — nested winit has no libinput.
//! Tablet pressure: linear min/max then tip/eraser piecewise-linear curves.

use std::path::PathBuf;

use serde_json::Value;

/// Control point for a tablet pressure curve (`{x,y}` in 0‥1).
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct CurvePoint {
    pub x: f64,
    pub y: f64,
}

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
    /// `tabletPressureMin` (`-1` = unset / driver default).
    pub tablet_pressure_min: f64,
    /// `tabletPressureMax` (`-1` = unset / driver default).
    pub tablet_pressure_max: f64,
    /// `tabletTipPressureCurve` — empty = identity.
    pub tip_pressure_curve: Vec<CurvePoint>,
    /// `tabletEraserPressureCurve` — empty = identity.
    pub eraser_pressure_curve: Vec<CurvePoint>,
    /// Active-area crop origin (mm). Size 0×0 = unset.
    pub tablet_active_area_pos_x: f64,
    pub tablet_active_area_pos_y: f64,
    pub tablet_active_area_size_x: f64,
    pub tablet_active_area_size_y: f64,
    /// `0` = hardware eraser tip; `1` = map eraser tip → button.
    pub tablet_eraser_button_mode: i64,
    /// Button code when mode=1 (`0` → BTN_STYLUS2 / 331).
    pub tablet_eraser_button_override: u32,
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
            tablet_pressure_min: -1.0,
            tablet_pressure_max: -1.0,
            tip_pressure_curve: Vec::new(),
            eraser_pressure_curve: Vec::new(),
            tablet_active_area_pos_x: 0.0,
            tablet_active_area_pos_y: 0.0,
            tablet_active_area_size_x: 0.0,
            tablet_active_area_size_y: 0.0,
            tablet_eraser_button_mode: 0,
            tablet_eraser_button_override: 0,
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

    /// Remap raw tablet pressure (0‥1) via min/max then tip or eraser curve.
    pub fn remap_tablet_pressure(&self, raw: f64, eraser: bool) -> f64 {
        let curve = if eraser {
            &self.eraser_pressure_curve
        } else {
            &self.tip_pressure_curve
        };
        remap_pressure(
            raw,
            self.tablet_pressure_min,
            self.tablet_pressure_max,
            curve,
        )
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
        if let Some(s) = real_field(v, "tabletPressureMin") {
            cfg.tablet_pressure_min = s;
        }
        if let Some(s) = real_field(v, "tabletPressureMax") {
            cfg.tablet_pressure_max = s;
        }
        cfg.tip_pressure_curve = parse_curve(v.get("tabletTipPressureCurve"));
        cfg.eraser_pressure_curve = parse_curve(v.get("tabletEraserPressureCurve"));
        if let Some(s) = real_field(v, "tabletActiveAreaPosX") {
            cfg.tablet_active_area_pos_x = s.max(0.0);
        }
        if let Some(s) = real_field(v, "tabletActiveAreaPosY") {
            cfg.tablet_active_area_pos_y = s.max(0.0);
        }
        if let Some(s) = real_field(v, "tabletActiveAreaSizeX") {
            cfg.tablet_active_area_size_x = s.max(0.0);
        }
        if let Some(s) = real_field(v, "tabletActiveAreaSizeY") {
            cfg.tablet_active_area_size_y = s.max(0.0);
        }
        if let Some(i) = v.get("tabletEraserButtonMode").and_then(|x| x.as_i64()) {
            cfg.tablet_eraser_button_mode = i.clamp(0, 1);
        }
        if let Some(i) = v
            .get("tabletEraserButtonOverride")
            .and_then(|x| x.as_i64().or_else(|| x.as_u64().map(|u| u as i64)))
        {
            cfg.tablet_eraser_button_override = i.max(0) as u32;
        }
        cfg
    }

    pub fn active_area_set(&self) -> bool {
        self.tablet_active_area_size_x > 0.0 && self.tablet_active_area_size_y > 0.0
    }

    /// Map full-pad normalized (0‥1) coords through the active-area crop.
    pub fn apply_active_area_norm(&self, fx: f64, fy: f64) -> (f64, f64) {
        if !self.active_area_set() {
            return (fx.clamp(0.0, 1.0), fy.clamp(0.0, 1.0));
        }
        let px = self.tablet_active_area_pos_x.max(0.0);
        let py = self.tablet_active_area_pos_y.max(0.0);
        let sx = self.tablet_active_area_size_x;
        let sy = self.tablet_active_area_size_y;
        let pad_w = (px + sx).max(sx);
        let pad_h = (py + sy).max(sy);
        let x_mm = fx.clamp(0.0, 1.0) * pad_w;
        let y_mm = fy.clamp(0.0, 1.0) * pad_h;
        let nx = ((x_mm - px) / sx).clamp(0.0, 1.0);
        let ny = ((y_mm - py) / sy).clamp(0.0, 1.0);
        (nx, ny)
    }

    pub fn eraser_as_button(&self) -> bool {
        self.tablet_eraser_button_mode != 0
    }

    pub fn eraser_button_code(&self) -> u32 {
        if self.tablet_eraser_button_override > 0 {
            self.tablet_eraser_button_override
        } else {
            331 // BTN_STYLUS2
        }
    }
}

fn real_field(v: &Value, key: &str) -> Option<f64> {
    v.get(key)
        .and_then(|x| x.as_f64().or_else(|| x.as_i64().map(|i| i as f64)))
}

fn parse_curve(v: Option<&Value>) -> Vec<CurvePoint> {
    let Some(arr) = v.and_then(|x| x.as_array()) else {
        return Vec::new();
    };
    let mut pts: Vec<CurvePoint> = arr
        .iter()
        .filter_map(|p| {
            let x = p
                .get("x")
                .and_then(|n| n.as_f64().or_else(|| n.as_i64().map(|i| i as f64)))?;
            let y = p
                .get("y")
                .and_then(|n| n.as_f64().or_else(|| n.as_i64().map(|i| i as f64)))?;
            if !x.is_finite() || !y.is_finite() {
                return None;
            }
            Some(CurvePoint {
                x: x.clamp(0.0, 1.0),
                y: y.clamp(0.0, 1.0),
            })
        })
        .collect();
    pts.sort_by(|a, b| a.x.partial_cmp(&b.x).unwrap_or(std::cmp::Ordering::Equal));
    pts.dedup_by(|a, b| (a.x - b.x).abs() < 1e-9);
    pts
}

/// Linear min/max (≥0 applies) then piecewise-linear through curve (empty = id).
pub fn remap_pressure(raw: f64, min: f64, max: f64, curve: &[CurvePoint]) -> f64 {
    let mut p = if raw.is_finite() {
        raw.clamp(0.0, 1.0)
    } else {
        0.0
    };
    if min >= 0.0 || max >= 0.0 {
        let lo = if min >= 0.0 {
            min.clamp(0.0, 1.0)
        } else {
            0.0
        };
        let mut hi = if max >= 0.0 {
            max.clamp(0.0, 1.0)
        } else {
            1.0
        };
        if hi < lo {
            hi = lo;
        }
        if (hi - lo).abs() < 1e-9 {
            p = if p >= lo { 1.0 } else { 0.0 };
        } else {
            p = ((p - lo) / (hi - lo)).clamp(0.0, 1.0);
        }
    }
    if curve.is_empty() {
        return p;
    }
    apply_curve(p, curve)
}

fn apply_curve(p: f64, curve: &[CurvePoint]) -> f64 {
    if p <= curve[0].x {
        return curve[0].y;
    }
    if let Some(last) = curve.last() {
        if p >= last.x {
            return last.y;
        }
    }
    for w in curve.windows(2) {
        let a = w[0];
        let b = w[1];
        if p >= a.x && p <= b.x {
            let span = b.x - a.x;
            if span.abs() < 1e-9 {
                return b.y;
            }
            let t = (p - a.x) / span;
            return (a.y + t * (b.y - a.y)).clamp(0.0, 1.0);
        }
    }
    p
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
    fn active_area_crop_and_eraser_button() {
        let mut c = InputConfig::default();
        assert!(!c.active_area_set());
        assert!(!c.eraser_as_button());
        c.tablet_active_area_pos_x = 10.0;
        c.tablet_active_area_size_x = 90.0;
        c.tablet_active_area_size_y = 50.0;
        // pad = 100×50; mid of crop → ~0.5
        let (nx, ny) = c.apply_active_area_norm(0.55, 0.5);
        assert!((nx - 0.5).abs() < 1e-9);
        assert!((ny - 0.5).abs() < 1e-9);
        c.tablet_eraser_button_mode = 1;
        assert!(c.eraser_as_button());
        assert_eq!(c.eraser_button_code(), 331);
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
          "touchpadScrollFactor": 1.5,
          "tabletPressureMin": 0.1,
          "tabletPressureMax": 0.9,
          "tabletTipPressureCurve": [{"x":0,"y":0},{"x":1,"y":1}],
          "tabletEraserPressureCurve": [{"x":0,"y":0},{"x":0.5,"y":0.2},{"x":1,"y":1}]
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
        assert!((c.tablet_pressure_min - 0.1).abs() < 1e-9);
        assert!((c.tablet_pressure_max - 0.9).abs() < 1e-9);
        assert_eq!(c.tip_pressure_curve.len(), 2);
        assert_eq!(c.eraser_pressure_curve.len(), 3);
    }

    #[test]
    fn remap_identity_empty_curve() {
        let c = InputConfig::default();
        assert!((c.remap_tablet_pressure(0.42, false) - 0.42).abs() < 1e-9);
        assert!((c.remap_tablet_pressure(0.42, true) - 0.42).abs() < 1e-9);
    }

    #[test]
    fn remap_min_max_then_hard_curve() {
        let c = InputConfig {
            tablet_pressure_min: 0.0,
            tablet_pressure_max: 1.0,
            tip_pressure_curve: vec![
                CurvePoint { x: 0.0, y: 0.0 },
                CurvePoint { x: 0.5, y: 0.1 },
                CurvePoint { x: 1.0, y: 1.0 },
            ],
            ..Default::default()
        };
        let mid = c.remap_tablet_pressure(0.5, false);
        assert!((mid - 0.1).abs() < 1e-9);
        let soft = InputConfig {
            eraser_pressure_curve: vec![
                CurvePoint { x: 0.0, y: 0.0 },
                CurvePoint { x: 0.5, y: 0.8 },
                CurvePoint { x: 1.0, y: 1.0 },
            ],
            ..Default::default()
        };
        assert!((soft.remap_tablet_pressure(0.5, true) - 0.8).abs() < 1e-9);
    }

    #[test]
    fn remap_pressure_range_clamps() {
        let c = InputConfig {
            tablet_pressure_min: 0.25,
            tablet_pressure_max: 0.75,
            ..Default::default()
        };
        assert!((c.remap_tablet_pressure(0.0, false) - 0.0).abs() < 1e-9);
        assert!((c.remap_tablet_pressure(0.25, false) - 0.0).abs() < 1e-9);
        assert!((c.remap_tablet_pressure(0.5, false) - 0.5).abs() < 1e-9);
        assert!((c.remap_tablet_pressure(0.75, false) - 1.0).abs() < 1e-9);
        assert!((c.remap_tablet_pressure(1.0, false) - 1.0).abs() < 1e-9);
    }
}
