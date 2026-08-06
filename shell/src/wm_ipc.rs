//! Window-manager IPC bridge — owned compositor-next only
//! (`PROTEUS_COMPOSITOR_SOCK`). Hyprland / hyprctl purged.
//!
//! Mirrors what Quickshell.Hyprland + ConfigHypr provided: workspaces,
//! toplevels, active window, and keyword dispatch.

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
}

#[derive(Debug, Clone, Default, Serialize)]
pub struct WmState {
    pub workspaces: Vec<Workspace>,
    pub toplevels: Vec<Toplevel>,
    pub active_workspace: i64,
    pub active_title: String,
    pub active_class: String,
    pub active_address: String,
}

/// One-release alias after Hyprland purge rename.
pub type HyprState = WmState;

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

/// Compositor ctl query (hypr-shaped JSON). Name kept for call-site stability.
pub fn hyprctl_json(args: &[&str]) -> Result<serde_json::Value, String> {
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
    t.workspace < 0
}

/// Dock click: minimize focused match · restore minimized · focus running · else launch.
pub fn dock_activate(pin: &str, hypr: &WmState) -> DockAction {
    let pin_l = pin.to_lowercase();
    if pin_matches(&pin_l, &hypr.active_class, &hypr.active_title) {
        let _ = window_minimize();
        return DockAction::Minimized;
    }
    if let Ok(clients) = hyprctl_json(&["clients"]) {
        if let Some(arr) = clients.as_array() {
            for c in arr {
                let class = c["class"].as_str().unwrap_or("");
                let title = c["title"].as_str().unwrap_or("");
                let addr = c["address"].as_str().unwrap_or("");
                let ws_name = c["workspace"]["name"].as_str().unwrap_or("");
                let minimized = ws_name.contains("minimized") || ws_name.contains("special");
                if minimized && pin_matches(&pin_l, class, title) && !addr.is_empty() {
                    let _ = focus_window_address(addr);
                    let _ = dispatch(&format!(
                        "movetoworkspacesilent {}",
                        hypr.active_workspace
                    ));
                    let _ = focus_window_address(addr);
                    return DockAction::Restored;
                }
            }
        }
    }
    for t in &hypr.toplevels {
        if !toplevel_minimized(t) && pin_matches(&pin_l, &t.class, &t.title) {
            if focus_window_address(&t.address).is_ok() {
                return DockAction::Focused;
            }
        }
    }
    DockAction::Launch
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DockAction {
    Minimized,
    Restored,
    Focused,
    Launch,
}

pub fn refresh_state() -> WmState {
    let mut state = WmState::default();
    if let Ok(ws) = hyprctl_json(&["workspaces"]) {
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
    if let Ok(active) = hyprctl_json(&["activeworkspace"]) {
        state.active_workspace = active["id"].as_i64().unwrap_or(0);
        for w in &mut state.workspaces {
            w.active = w.id == state.active_workspace;
        }
    }
    if let Ok(clients) = hyprctl_json(&["clients"]) {
        if let Some(arr) = clients.as_array() {
            for c in arr {
                state.toplevels.push(Toplevel {
                    address: c["address"].as_str().unwrap_or("").into(),
                    class: c["class"].as_str().unwrap_or("").into(),
                    title: c["title"].as_str().unwrap_or("").into(),
                    workspace: c["workspace"]["id"].as_i64().unwrap_or(0),
                });
            }
        }
    }
    if let Ok(win) = hyprctl_json(&["activewindow"]) {
        state.active_title = win["title"].as_str().unwrap_or("").into();
        state.active_class = win["class"].as_str().unwrap_or("").into();
        state.active_address = win["address"].as_str().unwrap_or("").into();
    }
    state
}

pub type SharedWm = std::sync::Arc<std::sync::Mutex<WmState>>;
/// One-release alias after Hyprland purge rename.
pub type SharedHypr = SharedWm;

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
                            *g = next;
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

    #[test]
    fn compositor_sock_tolerant() {
        let _ = compositor_sock();
    }

    #[test]
    fn engine_always_smithay_ipc() {
        assert_eq!(crate::engine::resolve_compositor_engine(), "smithay");
    }
}
