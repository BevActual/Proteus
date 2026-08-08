//! Desktop widget placement — free-place + optional snap-to-grid.
//! Persist shape matches `desktopWidgets[]` in settings.json.

use serde_json::{json, Value};

use proteus_shell_core::facts::{config_base, read_settings, write_settings};

pub const GRID: f32 = 16.0;
pub const HOLD_MS: u64 = 450;

#[derive(Debug, Clone, PartialEq)]
pub struct PlacedWidget {
    pub id: String,
    pub kind: String,
    pub x: f32,
    pub y: f32,
    pub w: f32,
    pub h: f32,
}

impl PlacedWidget {
    pub fn default_size(kind: &str) -> (f32, f32) {
        match kind {
            "Clock" | "WorldClock" => (180.0, 96.0),
            "Calendar" => (220.0, 200.0),
            "Weather" => (160.0, 100.0),
            "Media" => (240.0, 88.0),
            "Battery" | "System" => (160.0, 88.0),
            "Notes" => (200.0, 140.0),
            _ => (160.0, 96.0),
        }
    }
}

#[derive(Debug, Clone, Default)]
pub struct DesktopWidgetsState {
    pub items: Vec<PlacedWidget>,
    pub selected: Option<String>,
    pub dragging: Option<String>,
    pub drag_off: (f32, f32),
    pub guides: Vec<(f32, bool)>, // (pos, is_vertical)
    pub dirty: bool,
}

impl DesktopWidgetsState {
    pub fn load() -> Self {
        let base = config_base();
        let settings = read_settings(&base);
        let mut items = Vec::new();
        if let Some(arr) = settings.get("desktopWidgets").and_then(|v| v.as_array()) {
            for (i, v) in arr.iter().enumerate() {
                let kind = v
                    .get("kind")
                    .and_then(|k| k.as_str())
                    .unwrap_or("")
                    .trim();
                if kind.is_empty() {
                    continue;
                }
                let (dw, dh) = PlacedWidget::default_size(kind);
                let id = v
                    .get("id")
                    .and_then(|x| x.as_str())
                    .map(|s| s.to_string())
                    .unwrap_or_else(|| format!("{kind}-{i}"));
                let x = v.get("x").and_then(|x| x.as_f64()).unwrap_or(48.0 + i as f64 * 24.0)
                    as f32;
                let y = v.get("y").and_then(|x| x.as_f64()).unwrap_or(80.0 + i as f64 * 24.0)
                    as f32;
                let w = v.get("w").and_then(|x| x.as_f64()).unwrap_or(dw as f64) as f32;
                let h = v.get("h").and_then(|x| x.as_f64()).unwrap_or(dh as f64) as f32;
                items.push(PlacedWidget {
                    id,
                    kind: kind.into(),
                    x,
                    y,
                    w,
                    h,
                });
            }
        }
        Self {
            items,
            ..Default::default()
        }
    }

    pub fn kinds(&self) -> Vec<String> {
        self.items.iter().map(|w| w.kind.clone()).collect()
    }

    pub fn persist(&mut self) -> Result<(), String> {
        let arr: Vec<Value> = self
            .items
            .iter()
            .map(|w| {
                json!({
                    "id": w.id,
                    "kind": w.kind,
                    "x": w.x,
                    "y": w.y,
                    "w": w.w,
                    "h": w.h,
                })
            })
            .collect();
        let base = config_base();
        write_settings(&base, &json!({ "desktopWidgets": arr }))?;
        self.dirty = false;
        Ok(())
    }

    pub fn add(&mut self, kind: &str) {
        let (w, h) = PlacedWidget::default_size(kind);
        let n = self.items.len();
        let id = format!(
            "{kind}-{}-{}",
            chrono::Local::now().timestamp_millis(),
            n
        );
        self.items.push(PlacedWidget {
            id: id.clone(),
            kind: kind.into(),
            x: 64.0 + (n as f32 % 4.0) * (w + 16.0),
            y: 96.0 + (n as f32 / 4.0).floor() * (h + 16.0),
            w,
            h,
        });
        self.selected = Some(id);
        self.dirty = true;
    }

    pub fn remove(&mut self, id: &str) {
        self.items.retain(|w| w.id != id);
        if self.selected.as_deref() == Some(id) {
            self.selected = None;
        }
        self.dirty = true;
    }

    pub fn select(&mut self, id: &str) {
        self.selected = Some(id.into());
    }

    pub fn start_drag(&mut self, id: &str) {
        if self.items.iter().any(|w| w.id == id) {
            self.drag_off = (f32::NAN, f32::NAN);
            self.dragging = Some(id.into());
            self.selected = Some(id.into());
        }
    }

    pub fn drag_to(&mut self, px: f32, py: f32, snap: bool, surface: (f32, f32)) {
        let Some(id) = self.dragging.clone() else {
            return;
        };
        let Some(idx) = self.items.iter().position(|w| w.id == id) else {
            return;
        };
        if self.drag_off.0.is_nan() {
            self.drag_off = (px - self.items[idx].x, py - self.items[idx].y);
        }
        let mut x = (px - self.drag_off.0).max(0.0);
        let mut y = (py - self.drag_off.1).max(0.0);
        let (sw, sh) = surface;
        let w = self.items[idx].w;
        let h = self.items[idx].h;
        x = x.min((sw - w).max(0.0));
        y = y.min((sh - h).max(0.0));

        self.guides.clear();
        // Magnetize to surface centre + neighbour edges (10px).
        let cx = x + w * 0.5;
        let cy = y + h * 0.5;
        let thresh = 10.0;
        let mut magnets_x = vec![sw * 0.5];
        let mut magnets_y = vec![sh * 0.5];
        for other in &self.items {
            if other.id == id {
                continue;
            }
            magnets_x.push(other.x);
            magnets_x.push(other.x + other.w);
            magnets_x.push(other.x + other.w * 0.5);
            magnets_y.push(other.y);
            magnets_y.push(other.y + other.h);
            magnets_y.push(other.y + other.h * 0.5);
        }
        for m in magnets_x {
            if (cx - m).abs() < thresh {
                x = m - w * 0.5;
                self.guides.push((m, true));
                break;
            }
            if (x - m).abs() < thresh {
                x = m;
                self.guides.push((m, true));
                break;
            }
            if ((x + w) - m).abs() < thresh {
                x = m - w;
                self.guides.push((m, true));
                break;
            }
        }
        for m in magnets_y {
            if (cy - m).abs() < thresh {
                y = m - h * 0.5;
                self.guides.push((m, false));
                break;
            }
            if (y - m).abs() < thresh {
                y = m;
                self.guides.push((m, false));
                break;
            }
            if ((y + h) - m).abs() < thresh {
                y = m - h;
                self.guides.push((m, false));
                break;
            }
        }

        if snap {
            x = (x / GRID).round() * GRID;
            y = (y / GRID).round() * GRID;
        }
        self.items[idx].x = x.max(0.0);
        self.items[idx].y = y.max(0.0);
        self.dirty = true;
    }

    pub fn end_drag(&mut self) {
        self.dragging = None;
        self.guides.clear();
    }

    pub fn nudge(&mut self, dx: f32, dy: f32, snap: bool) {
        let Some(id) = self.selected.clone() else {
            return;
        };
        if let Some(w) = self.items.iter_mut().find(|w| w.id == id) {
            let step = if snap { GRID } else { dx.abs().max(dy.abs()).max(8.0) };
            w.x = (w.x + dx.signum() * if dx != 0.0 { step } else { 0.0 }).max(0.0);
            w.y = (w.y + dy.signum() * if dy != 0.0 { step } else { 0.0 }).max(0.0);
            if snap {
                w.x = (w.x / GRID).round() * GRID;
                w.y = (w.y / GRID).round() * GRID;
            }
            self.dirty = true;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn add_places_unique_ids() {
        let mut s = DesktopWidgetsState::default();
        s.add("Clock");
        s.add("Clock");
        assert_eq!(s.items.len(), 2);
        assert_ne!(s.items[0].id, s.items[1].id);
    }

    #[test]
    fn snap_drag_lattices() {
        let mut s = DesktopWidgetsState::default();
        s.add("Battery");
        let id = s.items[0].id.clone();
        s.start_drag(&id);
        s.drag_to(100.0, 100.0, true, (1920.0, 1080.0));
        assert_eq!(s.items[0].x % GRID, 0.0);
        assert_eq!(s.items[0].y % GRID, 0.0);
    }
}
