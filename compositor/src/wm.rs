//! Minimal workspace / toplevel roster for the Smithay spike.
//!
//! Pure state (no Space mutations). Compositor applies visibility / focus
//! after dispatch. JSON shapes mirror the hyprctl fields proteus-shell parses.
//!
//! Spaces are logical `1..=10` per output (per-monitor boards). Synced
//! `workspace N` sets every head; `workspace N,output:NAME` is local.
//! Physical band ids (`logical + index×10`) stay a script/UI convention.

use std::collections::HashMap;

use serde_json::{json, Value};

/// Parking workspace id for `special:minimized` (shell treats `< 0` as minimized).
pub const MINIMIZED_WORKSPACE: i64 = -99;

#[derive(Debug, Clone)]
pub struct ToplevelRecord {
    pub address: String,
    pub class: String,
    pub title: String,
    pub workspace: i64,
    pub fullscreen: bool,
    /// Fill work area (SSD maximize); distinct from xdg Fullscreen.
    pub maximized: bool,
    /// Geometry restored when leaving maximized (content origin + size).
    pub restore_x: i32,
    pub restore_y: i32,
    pub restore_w: i32,
    pub restore_h: i32,
    /// When true, skip tiling (move/resize grabs set this).
    pub floating: bool,
    /// `Output::name()` this window is assigned to; empty = primary (first output).
    pub output: String,
    /// Compositor-drawn SSD titlebar when true (xdg ServerSide).
    pub ssd: bool,
    pub loc_x: i32,
    pub loc_y: i32,
    /// Last known size (hypr-shaped `size`); live queries prefer Space geometry.
    pub size_w: i32,
    pub size_h: i32,
}

#[derive(Debug, Clone, PartialEq)]
pub enum WmOp {
    /// Raise + keyboard-focus this address (if mapped).
    Focus(String),
    /// Ask the client to close.
    Close(String),
    /// Remap windows for the active workspace (hide others).
    RefreshVisibility,
    /// Re-run active layout for tiled windows on the active workspace.
    Relayout,
    /// Warp seat toward named output (`Output::name()`).
    FocusOutput(String),
    /// Toggle or set fullscreen configure on address.
    ConfigureFullscreen { address: String, enabled: bool },
    /// Set fractional scale on named output.
    OutputScale { name: String, scale: f64 },
    /// Map output to logical position.
    OutputPos { name: String, x: i32, y: i32 },
    /// Request mode WxH[@Hz] on named output (DRM best-effort).
    OutputMode {
        name: String,
        width: u32,
        height: u32,
        refresh_hz: Option<f64>,
    },
}

/// Tiling algorithm for non-floating windows on each output.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum LayoutKind {
    Equal,
    #[default]
    Dwindle,
    Master,
}

impl LayoutKind {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Equal => "equal",
            Self::Dwindle => "dwindle",
            Self::Master => "master",
        }
    }

    pub fn parse(raw: &str) -> Option<Self> {
        match raw.trim().to_ascii_lowercase().as_str() {
            "equal" | "equalcolumn" | "columns" => Some(Self::Equal),
            "dwindle" => Some(Self::Dwindle),
            "master" => Some(Self::Master),
            _ => None,
        }
    }
}

#[derive(Debug)]
pub struct Wm {
    /// Active Space on the focused output (hypr-shaped `activeworkspace`).
    pub active_workspace: i64,
    /// Default Space for outputs not yet in `active_by_output` (synced writes).
    pub default_active: i64,
    /// Per-output active Space (`Output::name()` → `1..=10`).
    pub active_by_output: HashMap<String, i64>,
    /// Last focused output name (`focusoutput` / pointer); drives local goto.
    pub focused_output: Option<String>,
    pub layout: LayoutKind,
    /// Outer gap around the work area (logical px).
    pub gaps_out: i32,
    /// Uniform inset on every tile after layout (logical px).
    pub gaps_in: i32,
    /// When true, a single tiled window uses effective gaps 0/0.
    pub smart_gaps: bool,
    /// Master column width fraction for `LayoutKind::Master` (`0.1..=0.9`).
    pub master_factor: f64,
    pub toplevels: Vec<ToplevelRecord>,
    pub focused: Option<String>,
    next_id: u64,
    cascade: i32,
}

impl Default for Wm {
    fn default() -> Self {
        Self::new()
    }
}

impl Wm {
    pub fn new() -> Self {
        Self {
            active_workspace: 1,
            default_active: 1,
            active_by_output: HashMap::new(),
            focused_output: None,
            layout: LayoutKind::Dwindle,
            gaps_out: 10,
            gaps_in: 6,
            smart_gaps: true,
            master_factor: 0.5,
            toplevels: Vec::new(),
            focused: None,
            next_id: 1,
            cascade: 0,
        }
    }

    /// Register an output so local/synced boards stay coherent.
    pub fn ensure_output(&mut self, name: &str) {
        if name.is_empty() {
            return;
        }
        self.active_by_output
            .entry(name.to_string())
            .or_insert(self.default_active);
        if self.focused_output.is_none() {
            self.focused_output = Some(name.to_string());
            self.sync_active_workspace();
        }
    }

    pub fn active_for_output(&self, output: &str) -> i64 {
        if output.is_empty() {
            return self.default_active;
        }
        self.active_by_output
            .get(output)
            .copied()
            .unwrap_or(self.default_active)
    }

    pub fn sync_active_workspace(&mut self) {
        let id = match &self.focused_output {
            Some(name) => self.active_for_output(name),
            None => self.default_active,
        };
        self.active_workspace = id;
    }

    /// Window is on its output's currently active board.
    pub fn window_on_active_board(&self, t: &ToplevelRecord, primary: &str) -> bool {
        if t.workspace <= 0 {
            return false;
        }
        let out = self.effective_output(t, primary);
        t.workspace == self.active_for_output(out)
    }

    fn clamp_workspace(id: i64) -> Result<i64, String> {
        if (1..=10).contains(&id) {
            Ok(id)
        } else {
            Err(format!("workspace out of range: {id}"))
        }
    }

    fn set_workspace_synced(&mut self, id: i64) {
        self.default_active = id;
        for v in self.active_by_output.values_mut() {
            *v = id;
        }
        self.sync_active_workspace();
    }

    fn set_workspace_local(&mut self, id: i64, output: &str) {
        self.ensure_output(output);
        if let Some(v) = self.active_by_output.get_mut(output) {
            *v = id;
        }
        self.focused_output = Some(output.to_string());
        self.sync_active_workspace();
    }

    fn focus_candidate_for_workspace(&self, id: i64, output: Option<&str>) -> Option<String> {
        self.toplevels
            .iter()
            .rev()
            .find(|t| {
                t.workspace == id
                    && t.workspace > 0
                    && match output {
                        Some(name) => t.output.is_empty() || t.output == name,
                        None => true,
                    }
            })
            .map(|t| t.address.clone())
    }

    pub fn alloc_address(&mut self) -> String {
        let id = self.next_id;
        self.next_id = self.next_id.wrapping_add(1).max(1);
        format!("0x{id:x}")
    }

    pub fn next_cascade_loc(&mut self) -> (i32, i32) {
        let n = self.cascade;
        self.cascade = (self.cascade + 1) % 12;
        (48 + n * 28, 48 + n * 28)
    }

    pub fn add_toplevel(
        &mut self,
        address: String,
        class: String,
        title: String,
        loc: (i32, i32),
    ) {
        self.add_toplevel_on(address, class, title, loc, String::new());
    }

    pub fn add_toplevel_on(
        &mut self,
        address: String,
        class: String,
        title: String,
        loc: (i32, i32),
        output: String,
    ) {
        // Default CSD; xdg-decoration handler enables SSD only when requested.
        self.add_toplevel_ssd(address, class, title, loc, output, false);
    }

    pub fn add_toplevel_ssd(
        &mut self,
        address: String,
        class: String,
        title: String,
        loc: (i32, i32),
        output: String,
        ssd: bool,
    ) {
        let out = if output.is_empty() {
            self.focused_output.clone().unwrap_or_default()
        } else {
            output
        };
        if !out.is_empty() {
            self.ensure_output(&out);
        }
        let ws = if out.is_empty() {
            self.active_workspace
        } else {
            self.active_for_output(&out)
        };
        self.toplevels.push(ToplevelRecord {
            address: address.clone(),
            class,
            title,
            workspace: ws,
            fullscreen: false,
            maximized: false,
            restore_x: 0,
            restore_y: 0,
            restore_w: 0,
            restore_h: 0,
            floating: false,
            output: out,
            ssd,
            loc_x: loc.0,
            loc_y: loc.1,
            size_w: 0,
            size_h: 0,
        });
        self.focused = Some(address);
    }

    pub fn set_ssd(&mut self, address: &str, ssd: bool) {
        if let Some(t) = self.find_mut(address) {
            t.ssd = ssd;
        }
    }

    /// Resolve effective output name (empty tag → `primary`).
    pub fn effective_output<'a>(&'a self, t: &'a ToplevelRecord, primary: &'a str) -> &'a str {
        if t.output.is_empty() {
            primary
        } else {
            &t.output
        }
    }

    pub fn set_output(&mut self, address: &str, output: String) {
        if let Some(t) = self.find_mut(address) {
            t.output = output;
        }
    }

    pub fn set_floating(&mut self, address: &str, floating: bool) {
        if let Some(t) = self.find_mut(address) {
            t.floating = floating;
        }
    }

    pub fn set_geometry(&mut self, address: &str, loc: (i32, i32), size: (i32, i32)) {
        if let Some(t) = self.find_mut(address) {
            t.loc_x = loc.0;
            t.loc_y = loc.1;
            t.size_w = size.0;
            t.size_h = size.1;
        }
    }

    pub fn remove_toplevel(&mut self, address: &str) {
        self.toplevels.retain(|t| t.address != address);
        if self.focused.as_deref() == Some(address) {
            let ws = self.active_workspace;
            let out = self.focused_output.clone();
            self.focused = self.focus_candidate_for_workspace(ws, out.as_deref());
        }
    }

    pub fn find_mut(&mut self, address: &str) -> Option<&mut ToplevelRecord> {
        self.toplevels.iter_mut().find(|t| t.address == address)
    }

    pub fn find(&self, address: &str) -> Option<&ToplevelRecord> {
        self.toplevels.iter().find(|t| t.address == address)
    }

    pub fn set_title(&mut self, address: &str, title: String) {
        if let Some(t) = self.find_mut(address) {
            t.title = title;
        }
    }

    pub fn set_class(&mut self, address: &str, class: String) {
        if let Some(t) = self.find_mut(address) {
            t.class = class;
        }
    }

    /// Ensure workspaces 1..=10 exist in listings (create-on-use semantics).
    pub fn workspaces_json(&self) -> Value {
        let mut out = Vec::new();
        for id in 1..=10 {
            let name = id.to_string();
            out.push(json!({
                "id": id,
                "name": name,
            }));
        }
        // Include minimized pseudo-workspace if any parked clients.
        if self.toplevels.iter().any(|t| t.workspace < 0) {
            out.push(json!({
                "id": MINIMIZED_WORKSPACE,
                "name": "special:minimized",
            }));
        }
        Value::Array(out)
    }

    pub fn activeworkspace_json(&self) -> Value {
        json!({
            "id": self.active_workspace,
            "name": self.active_workspace.to_string(),
        })
    }

    pub fn clients_json(&self) -> Value {
        let arr: Vec<Value> = self
            .toplevels
            .iter()
            .map(|t| {
                let (ws_id, ws_name) = if t.workspace < 0 {
                    (t.workspace, "special:minimized".to_string())
                } else {
                    (t.workspace, t.workspace.to_string())
                };
                json!({
                    "address": t.address,
                    "class": t.class,
                    "title": t.title,
                    "workspace": {
                        "id": ws_id,
                        "name": ws_name,
                    },
                    "output": t.output,
                    "at": [t.loc_x, t.loc_y],
                    "size": [t.size_w, t.size_h],
                })
            })
            .collect();
        Value::Array(arr)
    }

    pub fn activewindow_json(&self) -> Value {
        if let Some(addr) = &self.focused {
            if let Some(t) = self.find(addr) {
                return json!({
                    "address": t.address,
                    "class": t.class,
                    "title": t.title,
                    "workspace": {
                        "id": t.workspace,
                        "name": if t.workspace < 0 {
                            "special:minimized".to_string()
                        } else {
                            t.workspace.to_string()
                        },
                    },
                });
            }
        }
        json!({
            "address": "",
            "class": "",
            "title": "",
        })
    }

    pub fn query(&self, cmd: &str) -> Result<Value, String> {
        match cmd.trim() {
            "workspaces" => Ok(self.workspaces_json()),
            "activeworkspace" => Ok(self.activeworkspace_json()),
            "clients" => Ok(self.clients_json()),
            "activewindow" => Ok(self.activewindow_json()),
            other => Err(format!("unknown query: {other}")),
        }
    }

    /// Apply a hypr-shaped dispatch verb. Returns Space/focus ops for the compositor.
    pub fn dispatch(&mut self, verb: &str) -> Result<Vec<WmOp>, String> {
        let verb = verb.trim();
        if verb.is_empty() {
            return Err("empty dispatch".into());
        }

        if let Some(rest) = verb.strip_prefix("workspace ") {
            let rest = rest.trim();
            // Forms: `N` (synced all heads) | `N,output:NAME` (local board)
            let (id_tok, out_opt) = if let Some((id, out)) = rest.split_once(",output:") {
                (id.trim(), Some(out.trim()))
            } else {
                (rest, None)
            };
            let id: i64 = id_tok
                .parse()
                .map_err(|_| format!("bad workspace id: {id_tok}"))?;
            let id = Self::clamp_workspace(id)?;
            let (focus_out, local) = if let Some(name) = out_opt {
                if name.is_empty() {
                    return Err("workspace output: requires a name".into());
                }
                self.set_workspace_local(id, name);
                (Some(name.to_string()), true)
            } else {
                self.set_workspace_synced(id);
                (self.focused_output.clone(), false)
            };
            let focus = self.focus_candidate_for_workspace(id, focus_out.as_deref());
            self.focused = focus.clone();
            let mut ops = vec![WmOp::RefreshVisibility];
            // Local goto warps seat; synced Super+N keeps pointer put.
            if local {
                if let Some(name) = focus_out {
                    ops.push(WmOp::FocusOutput(name));
                }
            }
            if let Some(addr) = focus {
                ops.push(WmOp::Focus(addr));
            }
            return Ok(ops);
        }

        if let Some(rest) = verb.strip_prefix("focuswindow ") {
            let addr = rest
                .trim()
                .strip_prefix("address:")
                .unwrap_or(rest.trim())
                .to_string();
            if self.find(&addr).is_none() {
                return Err(format!("no such window: {addr}"));
            }
            // If minimized, leave workspace as-is; caller may move first.
            self.focused = Some(addr.clone());
            return Ok(vec![WmOp::Focus(addr), WmOp::RefreshVisibility]);
        }

        if verb == "killactive" {
            let Some(addr) = self.focused.clone() else {
                return Ok(vec![]);
            };
            return Ok(vec![WmOp::Close(addr)]);
        }

        if verb == "cyclenext" {
            let primary = self
                .focused_output
                .clone()
                .or_else(|| self.active_by_output.keys().next().cloned())
                .unwrap_or_default();
            let visible: Vec<String> = self
                .toplevels
                .iter()
                .filter(|t| self.window_on_active_board(t, &primary))
                .map(|t| t.address.clone())
                .collect();
            if visible.is_empty() {
                return Ok(vec![]);
            }
            let next = match &self.focused {
                Some(cur) => {
                    let idx = visible.iter().position(|a| a == cur).unwrap_or(0);
                    visible[(idx + 1) % visible.len()].clone()
                }
                None => visible[0].clone(),
            };
            self.focused = Some(next.clone());
            return Ok(vec![WmOp::Focus(next)]);
        }

        if let Some(rest) = verb.strip_prefix("movetoworkspacesilent ") {
            let target = rest.trim();
            // Forms: `N` | `special:…` | `N,address:0x…` | `special:…,address:0x…`
            let (ws_tok, addr_opt) = if let Some((ws, addr)) = target.split_once(",address:") {
                (ws.trim(), Some(addr.trim().to_string()))
            } else {
                (target, None)
            };
            let addr = match addr_opt.or_else(|| self.focused.clone()) {
                Some(a) => a,
                None => return Ok(vec![]),
            };
            let ws = if ws_tok == "special:minimized" || ws_tok.starts_with("special:") {
                MINIMIZED_WORKSPACE
            } else {
                ws_tok
                    .parse::<i64>()
                    .map_err(|_| format!("bad move target: {ws_tok}"))?
            };
            if let Some(t) = self.find_mut(&addr) {
                t.workspace = ws;
            }
            return Ok(vec![WmOp::RefreshVisibility]);
        }

        if verb == "fullscreen 1" || verb.starts_with("fullscreen ") {
            let Some(addr) = self.focused.clone() else {
                return Ok(vec![]);
            };
            let enabled = if let Some(t) = self.find_mut(&addr) {
                t.fullscreen = !t.fullscreen;
                t.fullscreen
            } else {
                return Ok(vec![]);
            };
            return Ok(vec![
                WmOp::ConfigureFullscreen {
                    address: addr,
                    enabled,
                },
                WmOp::Relayout,
            ]);
        }

        if verb == "togglefloating" {
            let Some(addr) = self.focused.clone() else {
                return Ok(vec![]);
            };
            if let Some(t) = self.find_mut(&addr) {
                t.floating = !t.floating;
            } else {
                return Ok(vec![]);
            }
            return Ok(vec![WmOp::Relayout]);
        }

        if let Some(rest) = verb.strip_prefix("layout ") {
            let name = rest.trim();
            let Some(kind) = LayoutKind::parse(name) else {
                return Err(format!(
                    "unsupported layout (want equal|dwindle|master): {name}"
                ));
            };
            self.layout = kind;
            return Ok(vec![WmOp::Relayout]);
        }

        // gapsout N | gaps out N
        if let Some(rest) = verb
            .strip_prefix("gapsout ")
            .or_else(|| verb.strip_prefix("gaps out "))
        {
            let n: i32 = rest
                .trim()
                .parse()
                .map_err(|_| format!("bad gapsout value: {rest}"))?;
            if n < 0 {
                return Err("gapsout must be >= 0".into());
            }
            self.gaps_out = n;
            return Ok(vec![WmOp::Relayout]);
        }

        // gapsin N | gaps in N
        if let Some(rest) = verb
            .strip_prefix("gapsin ")
            .or_else(|| verb.strip_prefix("gaps in "))
        {
            let n: i32 = rest
                .trim()
                .parse()
                .map_err(|_| format!("bad gapsin value: {rest}"))?;
            if n < 0 {
                return Err("gapsin must be >= 0".into());
            }
            self.gaps_in = n;
            return Ok(vec![WmOp::Relayout]);
        }

        // smartgaps on|off|toggle
        if let Some(rest) = verb.strip_prefix("smartgaps ") {
            let arg = rest.trim().to_ascii_lowercase();
            match arg.as_str() {
                "on" | "1" | "true" => self.smart_gaps = true,
                "off" | "0" | "false" => self.smart_gaps = false,
                "toggle" => self.smart_gaps = !self.smart_gaps,
                _ => {
                    return Err(format!(
                        "unsupported smartgaps (want on|off|toggle): {arg}"
                    ));
                }
            }
            return Ok(vec![WmOp::Relayout]);
        }
        if verb == "smartgaps" {
            self.smart_gaps = !self.smart_gaps;
            return Ok(vec![WmOp::Relayout]);
        }

        if let Some(rest) = verb.strip_prefix("masterfactor ") {
            let f: f64 = rest
                .trim()
                .parse()
                .map_err(|_| format!("bad masterfactor value: {rest}"))?;
            if !(0.1..=0.9).contains(&f) {
                return Err(format!("masterfactor must be in 0.1..=0.9, got {f}"));
            }
            self.master_factor = f;
            return Ok(vec![WmOp::Relayout]);
        }

        if let Some(rest) = verb.strip_prefix("movewindow ") {
            let rest = rest.trim();
            let Some(name) = rest.strip_prefix("output:") else {
                return Err(format!(
                    "unsupported movewindow target (want output:<name>): {rest}"
                ));
            };
            let name = name.trim().to_string();
            if name.is_empty() {
                return Err("movewindow output: requires a name".into());
            }
            let Some(addr) = self.focused.clone() else {
                return Ok(vec![]);
            };
            if self.find(&addr).is_none() {
                return Ok(vec![]);
            }
            self.set_output(&addr, name);
            return Ok(vec![WmOp::Relayout, WmOp::Focus(addr)]);
        }

        if let Some(rest) = verb.strip_prefix("focusoutput ") {
            let name = rest.trim().to_string();
            if name.is_empty() {
                return Err("focusoutput requires an output name".into());
            }
            self.ensure_output(&name);
            self.focused_output = Some(name.clone());
            self.sync_active_workspace();
            let ws = self.active_workspace;
            let focus = self.focus_candidate_for_workspace(ws, Some(&name));
            self.focused = focus.clone();
            let mut ops = vec![WmOp::FocusOutput(name)];
            if let Some(addr) = focus {
                ops.push(WmOp::Focus(addr));
            }
            return Ok(ops);
        }

        if verb == "reloadbinds" || verb == "reload keybinds" {
            // Handled on CompositorNext (needs BindsState) — emit no-op here;
            // ctl apply path special-cases before wm.dispatch when needed.
            return Ok(vec![]);
        }

        if verb == "input-reload" || verb == "reload input" {
            // Handled on CompositorNext (needs InputConfig) — ctl special-cases.
            return Ok(vec![]);
        }

        // output <name> scale <f> | pos|position <x> <y> | mode <WxH[@Hz]>
        if let Some(rest) = verb.strip_prefix("output ") {
            let rest = rest.trim();
            let mut parts = rest.split_whitespace();
            let name = parts
                .next()
                .ok_or_else(|| "output requires a name".to_string())?
                .to_string();
            let action = parts
                .next()
                .ok_or_else(|| "output requires scale|pos|mode".to_string())?;
            match action {
                "scale" => {
                    let s = parts
                        .next()
                        .ok_or_else(|| "output scale requires a value".to_string())?;
                    let scale: f64 = s
                        .parse()
                        .map_err(|_| format!("bad output scale: {s}"))?;
                    let scale = crate::displays::clamp_scale(scale);
                    return Ok(vec![WmOp::OutputScale { name, scale }]);
                }
                "pos" | "position" => {
                    let xs = parts
                        .next()
                        .ok_or_else(|| "output pos requires x y".to_string())?;
                    let ys = parts
                        .next()
                        .ok_or_else(|| "output pos requires x y".to_string())?;
                    let x: i32 = xs.parse().map_err(|_| format!("bad output x: {xs}"))?;
                    let y: i32 = ys.parse().map_err(|_| format!("bad output y: {ys}"))?;
                    return Ok(vec![WmOp::OutputPos { name, x, y }]);
                }
                "mode" => {
                    let spec = parts
                        .next()
                        .ok_or_else(|| "output mode requires WxH[@Hz]".to_string())?;
                    let (width, height, refresh_hz) = crate::displays::parse_mode_spec(spec)?;
                    return Ok(vec![WmOp::OutputMode {
                        name,
                        width,
                        height,
                        refresh_hz,
                    }]);
                }
                other => {
                    return Err(format!(
                        "unsupported output action (want scale|pos|mode): {other}"
                    ));
                }
            }
        }

        Err(format!("unsupported dispatch: {verb}"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn workspace_switch_and_json() {
        let mut wm = Wm::new();
        assert_eq!(wm.active_workspace, 1);
        let ops = wm.dispatch("workspace 2").unwrap();
        assert_eq!(wm.active_workspace, 2);
        assert_eq!(wm.default_active, 2);
        assert!(ops.contains(&WmOp::RefreshVisibility));
        let ws = wm.workspaces_json();
        assert_eq!(ws.as_array().unwrap().len(), 10);
        assert_eq!(wm.activeworkspace_json()["id"], 2);
    }

    #[test]
    fn per_output_local_vs_synced() {
        let mut wm = Wm::new();
        wm.ensure_output("eDP-1");
        wm.ensure_output("HDMI-A-1");
        wm.dispatch("focusoutput eDP-1").unwrap();
        wm.dispatch("workspace 2").unwrap();
        assert_eq!(wm.active_for_output("eDP-1"), 2);
        assert_eq!(wm.active_for_output("HDMI-A-1"), 2);

        wm.dispatch("workspace 5,output:HDMI-A-1").unwrap();
        assert_eq!(wm.active_for_output("HDMI-A-1"), 5);
        assert_eq!(wm.active_for_output("eDP-1"), 2);
        assert_eq!(wm.focused_output.as_deref(), Some("HDMI-A-1"));
        assert_eq!(wm.active_workspace, 5);

        wm.dispatch("focusoutput eDP-1").unwrap();
        assert_eq!(wm.active_workspace, 2);

        let a = wm.alloc_address();
        wm.add_toplevel_on(a.clone(), "a".into(), "A".into(), (0, 0), "eDP-1".into());
        assert_eq!(wm.find(&a).unwrap().workspace, 2);
        let b = wm.alloc_address();
        wm.add_toplevel_on(b.clone(), "b".into(), "B".into(), (0, 0), "HDMI-A-1".into());
        // New window on HDMI joins that head's active board (5).
        assert_eq!(wm.find(&b).unwrap().workspace, 5);
        assert!(wm.window_on_active_board(wm.find(&a).unwrap(), "eDP-1"));
        assert!(wm.window_on_active_board(wm.find(&b).unwrap(), "eDP-1"));
    }

    #[test]
    fn clients_and_minimize() {
        let mut wm = Wm::new();
        let addr = wm.alloc_address();
        wm.add_toplevel(addr.clone(), "foot".into(), "term".into(), (10, 10));
        assert_eq!(wm.clients_json().as_array().unwrap().len(), 1);
        wm.set_geometry(&addr, (10, 20), (640, 480));
        let clients = wm.clients_json();
        assert_eq!(clients[0]["at"], json!([10, 20]));
        assert_eq!(clients[0]["size"], json!([640, 480]));
        wm.dispatch("movetoworkspacesilent special:minimized")
            .unwrap();
        assert_eq!(wm.find(&addr).unwrap().workspace, MINIMIZED_WORKSPACE);
        let clients = wm.clients_json();
        assert!(clients[0]["workspace"]["name"]
            .as_str()
            .unwrap()
            .contains("minimized"));
        assert!(clients[0].get("at").is_some());
        assert!(clients[0].get("size").is_some());
    }

    #[test]
    fn cyclenext_and_focus() {
        let mut wm = Wm::new();
        let a = wm.alloc_address();
        wm.add_toplevel(a.clone(), "a".into(), "A".into(), (0, 0));
        let b = wm.alloc_address();
        wm.add_toplevel(b.clone(), "b".into(), "B".into(), (0, 0));
        assert_eq!(wm.focused.as_deref(), Some(b.as_str()));
        wm.dispatch("cyclenext").unwrap();
        assert_eq!(wm.focused.as_deref(), Some(a.as_str()));
        wm.dispatch(&format!("focuswindow address:{b}")).unwrap();
        assert_eq!(wm.focused.as_deref(), Some(b.as_str()));
    }

    #[test]
    fn killactive_emits_close() {
        let mut wm = Wm::new();
        let a = wm.alloc_address();
        wm.add_toplevel(a.clone(), "a".into(), "A".into(), (0, 0));
        let ops = wm.dispatch("killactive").unwrap();
        assert_eq!(ops, vec![WmOp::Close(a)]);
    }

    #[test]
    fn togglefloating_flips_and_relayouts() {
        let mut wm = Wm::new();
        let a = wm.alloc_address();
        wm.add_toplevel(a.clone(), "a".into(), "A".into(), (0, 0));
        assert!(!wm.find(&a).unwrap().floating);
        let ops = wm.dispatch("togglefloating").unwrap();
        assert!(wm.find(&a).unwrap().floating);
        assert!(ops.contains(&WmOp::Relayout));
        wm.dispatch("togglefloating").unwrap();
        assert!(!wm.find(&a).unwrap().floating);
    }

    #[test]
    fn movewindow_output_and_focusoutput() {
        let mut wm = Wm::new();
        let a = wm.alloc_address();
        wm.add_toplevel_on(a.clone(), "a".into(), "A".into(), (0, 0), "eDP-1".into());
        assert_eq!(wm.find(&a).unwrap().output, "eDP-1");
        let ops = wm.dispatch("movewindow output:HDMI-A-1").unwrap();
        assert_eq!(wm.find(&a).unwrap().output, "HDMI-A-1");
        assert!(ops.contains(&WmOp::Relayout));
        assert!(ops.contains(&WmOp::Focus(a.clone())));
        let ops = wm.dispatch("focusoutput HDMI-A-1").unwrap();
        assert!(ops.contains(&WmOp::FocusOutput("HDMI-A-1".into())));
        assert!(ops.contains(&WmOp::Focus(a)));
    }

    #[test]
    fn layout_dispatch_defaults_dwindle() {
        let mut wm = Wm::new();
        assert_eq!(wm.layout, LayoutKind::Dwindle);
        let ops = wm.dispatch("layout equal").unwrap();
        assert_eq!(wm.layout, LayoutKind::Equal);
        assert!(ops.contains(&WmOp::Relayout));
        wm.dispatch("layout master").unwrap();
        assert_eq!(wm.layout, LayoutKind::Master);
        wm.dispatch("layout dwindle").unwrap();
        assert_eq!(wm.layout, LayoutKind::Dwindle);
        assert!(wm.dispatch("layout spiral").is_err());
    }

    #[test]
    fn output_scale_pos_mode_dispatch() {
        let mut wm = Wm::new();
        let ops = wm.dispatch("output DP-1 scale 1.5").unwrap();
        assert_eq!(
            ops,
            vec![WmOp::OutputScale {
                name: "DP-1".into(),
                scale: 1.5,
            }]
        );
        let ops = wm.dispatch("output DP-1 pos 100 200").unwrap();
        assert_eq!(
            ops,
            vec![WmOp::OutputPos {
                name: "DP-1".into(),
                x: 100,
                y: 200,
            }]
        );
        let ops = wm.dispatch("output DP-1 mode 1920x1080@60").unwrap();
        assert_eq!(
            ops,
            vec![WmOp::OutputMode {
                name: "DP-1".into(),
                width: 1920,
                height: 1080,
                refresh_hz: Some(60.0),
            }]
        );
        assert!(wm.dispatch("output DP-1 rotate 90").is_err());
    }

    #[test]
    fn gaps_and_masterfactor_dispatch() {
        let mut wm = Wm::new();
        assert_eq!(wm.gaps_out, 10);
        assert_eq!(wm.gaps_in, 6);
        assert!((wm.master_factor - 0.5).abs() < f64::EPSILON);
        wm.dispatch("gapsout 12").unwrap();
        assert_eq!(wm.gaps_out, 12);
        wm.dispatch("gaps in 2").unwrap();
        assert_eq!(wm.gaps_in, 2);
        wm.dispatch("masterfactor 0.65").unwrap();
        assert!((wm.master_factor - 0.65).abs() < f64::EPSILON);
        assert!(wm.dispatch("masterfactor 1.5").is_err());
    }

    #[test]
    fn smartgaps_dispatch_defaults_on() {
        let mut wm = Wm::new();
        assert!(wm.smart_gaps);
        wm.dispatch("smartgaps off").unwrap();
        assert!(!wm.smart_gaps);
        wm.dispatch("smartgaps toggle").unwrap();
        assert!(wm.smart_gaps);
        wm.dispatch("smartgaps").unwrap();
        assert!(!wm.smart_gaps);
        wm.dispatch("smartgaps on").unwrap();
        assert!(wm.smart_gaps);
    }
}
