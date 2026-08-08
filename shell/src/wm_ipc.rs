//! Window-manager IPC bridge — owned compositor only
//! (`PROTEUS_COMPOSITOR_SOCK`). Hyprland / hyprctl purged.
//!
//! Replaces the old Quickshell.Hyprland + ConfigHypr path: workspaces,
//! toplevels, active window, and keyword dispatch via compositorctl JSON.

use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::UnixStream;
use std::path::PathBuf;
use std::time::Duration;

use serde::Serialize;

#[derive(Debug, Clone, Default, Serialize)]
pub struct Workspace {
    pub id: i64,
    pub name: String,
    pub active: bool,
}

#[derive(Debug, Clone, Default, Serialize)]
pub struct Toplevel {
    pub address: String,
    pub class: String,
    pub title: String,
    pub workspace: i64,
    /// Output name from compositor clients JSON (empty when unknown).
    #[serde(default)]
    pub output: String,
}

#[derive(Debug, Clone, Default, Serialize)]
pub struct Monitor {
    pub name: String,
    pub focused: bool,
    pub active_workspace: i64,
}

#[derive(Debug, Clone, Default, Serialize)]
pub struct WmState {
    pub workspaces: Vec<Workspace>,
    pub toplevels: Vec<Toplevel>,
    pub monitors: Vec<Monitor>,
    pub active_workspace: i64,
    pub active_title: String,
    pub active_class: String,
    pub active_address: String,
}

pub fn compositor_sock() -> Option<PathBuf> {
    if let Ok(p) = std::env::var("PROTEUS_COMPOSITOR_SOCK") {
        let path = PathBuf::from(p);
        if path.exists() {
            return Some(path);
        }
    }
    let wd = std::env::var("WAYLAND_DISPLAY").ok()?;
    let runtime = std::env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| "/tmp".into());
    let safe = wd.replace('/', "_");
    let path = PathBuf::from(runtime).join(format!("proteus-compositor-{safe}.sock"));
    if path.exists() {
        Some(path)
    } else {
        None
    }
}

/// One-shot line request against the owned compositor control socket.
fn smithay_request(line: &str) -> Result<String, String> {
    let path = compositor_sock().ok_or("PROTEUS_COMPOSITOR_SOCK unset")?;
    let mut stream =
        UnixStream::connect(&path).map_err(|e| format!("{}: {e}", path.display()))?;
    stream
        .set_read_timeout(Some(Duration::from_secs(2)))
        .ok();
    stream
        .set_write_timeout(Some(Duration::from_secs(2)))
        .ok();
    writeln!(stream, "{line}").map_err(|e| e.to_string())?;
    let mut reader = BufReader::new(stream);
    let mut resp = String::new();
    reader.read_line(&mut resp).map_err(|e| e.to_string())?;
    Ok(resp)
}

fn smithay_json(cmd: &str) -> Result<serde_json::Value, String> {
    let resp = smithay_request(cmd)?;
    serde_json::from_str(resp.trim()).map_err(|e| format!("smithay ctl json: {e}"))
}

/// Compositor ctl query (hypr-shaped JSON for migration parity).
pub fn compositorctl_json(args: &[&str]) -> Result<serde_json::Value, String> {
    let cmd = args.join(" ");
    smithay_json(&cmd)
}

pub fn dispatch(dispatcher: &str) -> Result<(), String> {
    let v = smithay_json(&format!("dispatch {dispatcher}"))?;
    if v.get("ok").and_then(|o| o.as_bool()) == Some(false) {
        return Err(v
            .get("error")
            .and_then(|e| e.as_str())
            .unwrap_or("dispatch failed")
            .to_string());
    }
    Ok(())
}

/// Close focused toplevel.
pub fn window_close() -> Result<(), String> {
    dispatch("killactive")
}

/// Park focused toplevel on scratch special (QS minimize path).
pub fn window_minimize() -> Result<(), String> {
    dispatch("movetoworkspacesilent special:minimized")
}

/// Scratchpad park id (`special:scratch`) — distinct from dock minimize (-99).
pub const SCRATCH_WORKSPACE: i64 = -98;

/// Toggle Scratchpad: park focused window on `special:scratch`, or restore
/// when the focused window is already on the scratch pad.
pub fn scratch_toggle(wm: &WmState) -> Result<(), String> {
    let focused_ws = wm
        .toplevels
        .iter()
        .find(|t| t.address == wm.active_address)
        .map(|t| t.workspace)
        .unwrap_or(wm.active_workspace);
    if focused_ws == SCRATCH_WORKSPACE {
        let restore = wm.active_workspace.max(1);
        dispatch(&format!("movetoworkspacesilent {restore}"))
    } else {
        if wm.active_address.is_empty() {
            return Err("no focused window".into());
        }
        dispatch("movetoworkspacesilent special:scratch")
    }
}

pub fn toplevel_on_scratch(t: &Toplevel) -> bool {
    t.workspace == SCRATCH_WORKSPACE
}

/// Toggle maximize (fullscreen 1) on focused toplevel.
pub fn window_maximize() -> Result<(), String> {
    dispatch("fullscreen 1")
}

pub fn focus_window_address(address: &str) -> Result<(), String> {
    let addr = address.trim();
    if addr.is_empty() {
        return Err("empty address".into());
    }
    dispatch(&format!("focuswindow address:{addr}"))
}

fn pin_matches(pin: &str, class: &str, title: &str) -> bool {
    let p = pin.to_lowercase();
    let c = class.to_lowercase();
    let t = title.to_lowercase();
    (!c.is_empty() && (c.contains(&p) || p.contains(&c)))
        || (!t.is_empty() && t.contains(&p))
}

fn toplevel_minimized(t: &Toplevel) -> bool {
    // Dock minimize park only — Scratchpad (-98) is a separate special.
    t.workspace < 0 && t.workspace != SCRATCH_WORKSPACE
}

/// Pure dock click decision (no compositor I/O) — unit-tested.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DockPlan {
    Minimize,
    Cycle(String),
    Restore(String),
    Focus(String),
    Launch,
}

impl DockPlan {
    pub fn action(&self) -> DockAction {
        match self {
            DockPlan::Minimize => DockAction::Minimized,
            DockPlan::Cycle(_) => DockAction::Cycled,
            DockPlan::Restore(_) => DockAction::Restored,
            DockPlan::Focus(_) => DockAction::Focused,
            DockPlan::Launch => DockAction::Launch,
        }
    }
}

/// Decide dock click outcome from current WM snapshot.
pub fn dock_activate_plan(pin: &str, wm: &WmState) -> DockPlan {
    let pin_l = pin.to_lowercase();
    let running: Vec<&Toplevel> = wm
        .toplevels
        .iter()
        .filter(|t| !toplevel_minimized(t) && pin_matches(&pin_l, &t.class, &t.title))
        .collect();
    let focused_match = pin_matches(&pin_l, &wm.active_class, &wm.active_title);

    // Multi-window: cycle among non-minimized matches instead of minimizing.
    if focused_match && running.len() >= 2 {
        let idx = running
            .iter()
            .position(|t| t.address == wm.active_address)
            .unwrap_or(0);
        let next = running[(idx + 1) % running.len()];
        if next.address != wm.active_address {
            return DockPlan::Cycle(next.address.clone());
        }
    }

    if focused_match {
        return DockPlan::Minimize;
    }
    if let Some(t) = wm
        .toplevels
        .iter()
        .find(|t| toplevel_minimized(t) && pin_matches(&pin_l, &t.class, &t.title))
    {
        return DockPlan::Restore(t.address.clone());
    }
    if let Some(t) = running.first() {
        return DockPlan::Focus(t.address.clone());
    }
    DockPlan::Launch
}

/// Dock click: cycle multi-window focused match · minimize single · restore ·
/// focus running · else launch.
pub fn dock_activate(pin: &str, wm: &WmState) -> DockAction {
    match dock_activate_plan(pin, wm) {
        DockPlan::Minimize => {
            let _ = window_minimize();
            DockAction::Minimized
        }
        DockPlan::Cycle(addr) => {
            if focus_window_address(&addr).is_ok() {
                DockAction::Cycled
            } else {
                DockAction::Launch
            }
        }
        DockPlan::Restore(addr) => {
            let _ = dock_focus_or_restore(&addr, wm);
            DockAction::Restored
        }
        DockPlan::Focus(addr) => {
            if focus_window_address(&addr).is_ok() {
                DockAction::Focused
            } else {
                DockAction::Launch
            }
        }
        DockPlan::Launch => DockAction::Launch,
    }
}

/// Restore a parked (`special:minimized`) window, or focus a visible one.
pub fn dock_focus_or_restore(address: &str, wm: &WmState) -> Result<(), String> {
    let addr = address.trim();
    if addr.is_empty() {
        return Err("empty address".into());
    }
    let minimized = wm
        .toplevels
        .iter()
        .find(|t| t.address == addr)
        .map(toplevel_minimized)
        .unwrap_or(false);
    if minimized {
        focus_window_address(addr)?;
        dispatch(&format!(
            "movetoworkspacesilent {}",
            wm.active_workspace
        ))?;
    }
    focus_window_address(addr)
}

/// Close a toplevel by address (focus then killactive).
pub fn window_close_address(address: &str) -> Result<(), String> {
    focus_window_address(address)?;
    window_close()
}

/// Move a toplevel to workspace `ws` without following focus (Spaces overview drag).
pub fn move_window_to_workspace(address: &str, ws: i64) -> Result<(), String> {
    focus_window_address(address)?;
    let target = if ws == SCRATCH_WORKSPACE {
        "special:scratch".to_string()
    } else {
        ws.to_string()
    };
    dispatch(&format!("movetoworkspacesilent {target}"))
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DockAction {
    Minimized,
    Restored,
    Focused,
    Cycled,
    Launch,
}

/// Parse hypr-shaped `monitors` JSON array (focused heads first).
pub fn parse_monitors_json(arr: &[serde_json::Value]) -> Vec<Monitor> {
    let mut monitors: Vec<Monitor> = arr
        .iter()
        .map(|m| Monitor {
            name: m["name"].as_str().unwrap_or("").into(),
            focused: m["focused"].as_bool().unwrap_or(false),
            active_workspace: m["activeWorkspace"]["id"]
                .as_i64()
                .unwrap_or(1),
        })
        .collect();
    monitors.sort_by(|a, b| b.focused.cmp(&a.focused));
    monitors
}

/// Focused monitor when multi-head data is present.
pub fn focused_monitor<'a>(wm: &'a WmState) -> Option<&'a Monitor> {
    wm.monitors
        .iter()
        .find(|m| m.focused)
        .or(wm.monitors.first())
}

pub fn refresh_state() -> WmState {
    let mut state = WmState::default();
    if let Ok(monitors) = compositorctl_json(&["monitors"]) {
        if let Some(arr) = monitors.as_array() {
            state.monitors = parse_monitors_json(arr);
        }
    }
    if let Ok(ws) = compositorctl_json(&["workspaces"]) {
        if let Some(arr) = ws.as_array() {
            for w in arr {
                state.workspaces.push(Workspace {
                    id: w["id"].as_i64().unwrap_or(0),
                    name: w["name"].as_str().unwrap_or("").into(),
                    active: false,
                });
            }
        }
    }
    if let Ok(active) = compositorctl_json(&["activeworkspace"]) {
        state.active_workspace = active["id"].as_i64().unwrap_or(0);
        for w in &mut state.workspaces {
            w.active = w.id == state.active_workspace;
        }
    }
    if let Ok(clients) = compositorctl_json(&["clients"]) {
        if let Some(arr) = clients.as_array() {
            for c in arr {
                state.toplevels.push(Toplevel {
                    address: c["address"].as_str().unwrap_or("").into(),
                    class: c["class"].as_str().unwrap_or("").into(),
                    title: c["title"].as_str().unwrap_or("").into(),
                    workspace: c["workspace"]["id"].as_i64().unwrap_or(0),
                    output: c["output"].as_str().unwrap_or("").into(),
                });
            }
        }
    }
    if let Ok(win) = compositorctl_json(&["activewindow"]) {
        state.active_title = win["title"].as_str().unwrap_or("").into();
        state.active_class = win["class"].as_str().unwrap_or("").into();
        state.active_address = win["address"].as_str().unwrap_or("").into();
    }
    state
}

/// Shared WM snapshot + generation (UI clones only when `gen` advances).
#[derive(Debug, Clone, Default)]
pub struct WmShared {
    pub state: WmState,
    pub gen: u64,
}

pub type SharedWm = std::sync::Arc<std::sync::Mutex<WmShared>>;

pub fn shared_from_state(state: WmState) -> SharedWm {
    std::sync::Arc::new(std::sync::Mutex::new(WmShared { state, gen: 1 }))
}

/// Spawn event listener on PROTEUS_COMPOSITOR_SOCK `subscribe`.
pub fn spawn_socket2_listener(shared: SharedWm) {
    std::thread::spawn(move || smithay_subscribe_loop(shared));
}

fn smithay_subscribe_loop(shared: SharedWm) {
    loop {
        let Some(path) = compositor_sock() else {
            std::thread::sleep(Duration::from_secs(2));
            continue;
        };
        match UnixStream::connect(&path) {
            Ok(mut stream) => {
                if writeln!(stream, "subscribe").is_err() {
                    std::thread::sleep(Duration::from_secs(1));
                    continue;
                }
                let reader = BufReader::new(stream);
                for line in reader.lines().flatten() {
                    if line.starts_with("workspace")
                        || line.starts_with("activewindow")
                        || line.starts_with("openwindow")
                        || line.starts_with("closewindow")
                        || line.starts_with("dispatch")
                    {
                        let next = refresh_state();
                        if let Ok(mut g) = shared.lock() {
                            g.state = next;
                            g.gen = g.gen.wrapping_add(1);
                        }
                    }
                }
            }
            Err(_) => {
                std::thread::sleep(Duration::from_secs(2));
            }
        }
        std::thread::sleep(Duration::from_millis(500));
    }
}

/// Write a command to the compositor control socket.
pub fn socket_command(cmd: &str) -> Result<String, String> {
    smithay_request(cmd)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tl(addr: &str, class: &str, title: &str, workspace: i64) -> Toplevel {
        Toplevel {
            address: addr.into(),
            class: class.into(),
            title: title.into(),
            workspace,
            output: String::new(),
        }
    }

    #[test]
    fn parse_monitors_focused_first() {
        let arr = serde_json::json!([
            {"name": "HDMI-A-1", "focused": false, "activeWorkspace": {"id": 2}},
            {"name": "eDP-1", "focused": true, "activeWorkspace": {"id": 5}},
        ]);
        let mons = parse_monitors_json(arr.as_array().unwrap());
        assert_eq!(mons.len(), 2);
        assert!(mons[0].focused);
        assert_eq!(mons[0].name, "eDP-1");
        assert_eq!(mons[0].active_workspace, 5);
        assert_eq!(mons[1].name, "HDMI-A-1");
    }

    #[test]
    fn compositor_sock_tolerant() {
        let _ = compositor_sock();
    }

    #[test]
    fn engine_always_smithay_ipc() {
        assert_eq!(crate::engine::resolve_compositor_engine(), "smithay");
    }

    #[test]
    fn dock_plan_launch_when_nothing_running() {
        let wm = WmState::default();
        assert_eq!(
            dock_activate_plan("ghostty", &wm),
            DockPlan::Launch
        );
    }

    #[test]
    fn dock_plan_minimize_single_focused() {
        let wm = WmState {
            toplevels: vec![tl("0x1", "ghostty", "term", 1)],
            active_workspace: 1,
            active_class: "ghostty".into(),
            active_title: "term".into(),
            active_address: "0x1".into(),
            ..Default::default()
        };
        assert_eq!(
            dock_activate_plan("ghostty", &wm),
            DockPlan::Minimize
        );
    }

    #[test]
    fn dock_plan_cycle_multi_focused() {
        let wm = WmState {
            toplevels: vec![
                tl("0x1", "ghostty", "a", 1),
                tl("0x2", "ghostty", "b", 1),
            ],
            active_workspace: 1,
            active_class: "ghostty".into(),
            active_title: "a".into(),
            active_address: "0x1".into(),
            ..Default::default()
        };
        assert_eq!(
            dock_activate_plan("ghostty", &wm),
            DockPlan::Cycle("0x2".into())
        );
    }

    #[test]
    fn dock_plan_restore_minimized() {
        let wm = WmState {
            toplevels: vec![tl("0x9", "ghostty", "parked", -1)],
            active_workspace: 2,
            active_class: String::new(),
            active_title: String::new(),
            active_address: String::new(),
            ..Default::default()
        };
        assert_eq!(
            dock_activate_plan("ghostty", &wm),
            DockPlan::Restore("0x9".into())
        );
    }

    #[test]
    fn dock_plan_focus_running_unfocused() {
        let wm = WmState {
            toplevels: vec![tl("0x3", "org.gnome.Nautilus", "Home", 1)],
            active_workspace: 1,
            active_class: "ghostty".into(),
            active_title: "term".into(),
            active_address: "0x1".into(),
            ..Default::default()
        };
        assert_eq!(
            dock_activate_plan("org.gnome.Nautilus", &wm),
            DockPlan::Focus("0x3".into())
        );
    }
}
