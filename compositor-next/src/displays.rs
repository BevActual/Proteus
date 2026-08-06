//! Displays Fact (`~/.config/proteus/displays.json`) — load + parse helpers.
//!
//! Schema matches Settings `DisplayMonitor` (camelCase). Missing file → empty.

use std::path::PathBuf;

use serde_json::Value;

/// One monitor entry from the Displays Fact.
#[derive(Debug, Clone)]
pub struct DisplayFact {
    pub name: String,
    pub width: u32,
    pub height: u32,
    pub refresh_rate: f64,
    pub x: i32,
    pub y: i32,
    pub scale: f64,
}

/// Resolve Fact path: `$XDG_CONFIG_HOME/proteus/displays.json` or `~/.config/...`.
pub fn displays_fact_path() -> PathBuf {
    if let Ok(xdg) = std::env::var("XDG_CONFIG_HOME") {
        if !xdg.is_empty() {
            return PathBuf::from(xdg).join("proteus/displays.json");
        }
    }
    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".into());
    PathBuf::from(home).join(".config/proteus/displays.json")
}

/// Load Fact; missing / invalid → empty vec (no hard fail).
pub fn load_displays_fact() -> Vec<DisplayFact> {
    let path = displays_fact_path();
    let Ok(raw) = std::fs::read_to_string(&path) else {
        return Vec::new();
    };
    parse_displays_fact(&raw)
}

pub fn parse_displays_fact(raw: &str) -> Vec<DisplayFact> {
    let Ok(v) = serde_json::from_str::<Value>(raw) else {
        eprintln!("proteus-compositor-next: displays.json: invalid JSON");
        return Vec::new();
    };
    let Some(arr) = v.as_array() else {
        eprintln!("proteus-compositor-next: displays.json: expected array");
        return Vec::new();
    };
    arr.iter()
        .filter_map(|m| {
            let name = m.get("name")?.as_str()?.to_string();
            if name.is_empty() {
                return None;
            }
            Some(DisplayFact {
                name,
                width: m.get("width").and_then(|x| x.as_u64()).unwrap_or(0) as u32,
                height: m.get("height").and_then(|x| x.as_u64()).unwrap_or(0) as u32,
                refresh_rate: m
                    .get("refreshRate")
                    .and_then(|x| x.as_f64())
                    .unwrap_or(60.0),
                x: m.get("x").and_then(|x| x.as_i64()).unwrap_or(0) as i32,
                y: m.get("y").and_then(|x| x.as_i64()).unwrap_or(0) as i32,
                scale: m.get("scale").and_then(|x| x.as_f64()).unwrap_or(1.0),
            })
        })
        .collect()
}

/// Clamp fractional scale for Wayland outputs.
pub fn clamp_scale(s: f64) -> f64 {
    if !s.is_finite() {
        return 1.0;
    }
    s.clamp(0.5, 4.0)
}

/// Parse `1920x1080` or `1920x1080@60` / `1920x1080@59.94`.
pub fn parse_mode_spec(spec: &str) -> Result<(u32, u32, Option<f64>), String> {
    let spec = spec.trim();
    let (wh, hz) = match spec.split_once('@') {
        Some((a, b)) => (a.trim(), Some(b.trim())),
        None => (spec, None),
    };
    let (w_s, h_s) = wh
        .split_once('x')
        .or_else(|| wh.split_once('X'))
        .ok_or_else(|| format!("bad mode (want WxH[@Hz]): {spec}"))?;
    let w: u32 = w_s
        .trim()
        .parse()
        .map_err(|_| format!("bad mode width: {w_s}"))?;
    let h: u32 = h_s
        .trim()
        .parse()
        .map_err(|_| format!("bad mode height: {h_s}"))?;
    if w == 0 || h == 0 {
        return Err(format!("mode dimensions must be > 0: {spec}"));
    }
    let refresh = match hz {
        None => None,
        Some(s) => Some(
            s.parse::<f64>()
                .map_err(|_| format!("bad mode refresh: {s}"))?,
        ),
    };
    Ok((w, h, refresh))
}

/// True when Fact lists a position for every name in `output_names` (non-empty).
pub fn facts_cover_all_outputs(facts: &[DisplayFact], output_names: &[String]) -> bool {
    if output_names.is_empty() || facts.is_empty() {
        return false;
    }
    output_names
        .iter()
        .all(|n| facts.iter().any(|f| f.name == *n))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn clamp_scale_bounds() {
        assert_eq!(clamp_scale(1.0), 1.0);
        assert_eq!(clamp_scale(0.1), 0.5);
        assert_eq!(clamp_scale(10.0), 4.0);
        assert_eq!(clamp_scale(f64::NAN), 1.0);
    }

    #[test]
    fn parse_mode_spec_ok() {
        assert_eq!(parse_mode_spec("1920x1080").unwrap(), (1920, 1080, None));
        assert_eq!(
            parse_mode_spec("2560x1440@144").unwrap(),
            (2560, 1440, Some(144.0))
        );
        assert_eq!(
            parse_mode_spec("1920X1080@59.94").unwrap(),
            (1920, 1080, Some(59.94))
        );
    }

    #[test]
    fn parse_displays_fact_camel() {
        let raw = r#"[
          {"name":"DP-1","width":1920,"height":1080,"refreshRate":60.0,
           "x":100,"y":50,"scale":1.25,"transform":0}
        ]"#;
        let v = parse_displays_fact(raw);
        assert_eq!(v.len(), 1);
        assert_eq!(v[0].name, "DP-1");
        assert_eq!(v[0].x, 100);
        assert!((v[0].scale - 1.25).abs() < 1e-9);
    }

    #[test]
    fn facts_cover_all() {
        let facts = vec![DisplayFact {
            name: "a".into(),
            width: 1,
            height: 1,
            refresh_rate: 60.0,
            x: 0,
            y: 0,
            scale: 1.0,
        }];
        assert!(!facts_cover_all_outputs(&facts, &["a".into(), "b".into()]));
        assert!(facts_cover_all_outputs(&facts, &["a".into()]));
    }
}
