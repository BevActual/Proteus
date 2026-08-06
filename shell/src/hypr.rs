//! Hyprland IPC bridge — socket2 events + hyprctl dispatch.
//!
//! Mirrors what Quickshell.Hyprland + ConfigHypr provided: workspaces,
//! toplevels, active window, and keyword dispatch.

use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::UnixStream;
use std::path::PathBuf;
use std::process::Command;

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
pub struct HyprState {
    pub workspaces: Vec<Workspace>,
    pub toplevels: Vec<Toplevel>,
    pub active_workspace: i64,
    pub active_title: String,
    pub active_class: String,
    pub active_address: String,
}

pub fn his_socket() -> Option<PathBuf> {
    let sig = std::env::var("HYPRLAND_INSTANCE_SIGNATURE").ok()?;
    let rt = std::env::var("XDG_RUNTIME_DIR").ok()?;
    let p = PathBuf::from(rt).join("hypr").join(&sig).join(".socket.sock");
    if p.exists() {
        Some(p)
    } else {
        // Legacy path
        let legacy = PathBuf::from("/tmp/hypr").join(&sig).join(".socket.sock");
        if legacy.exists() {
            Some(legacy)
        } else {
            Some(p)
        }
    }
}

pub fn his_socket2() -> Option<PathBuf> {
    his_socket().map(|p| p.with_file_name(".socket2.sock"))
}

/// Run `hyprctl -j <cmd>` and parse JSON.
pub fn hyprctl_json(args: &[&str]) -> Result<serde_json::Value, String> {
    let mut cmd = Command::new("hyprctl");
    cmd.arg("-j");
    cmd.args(args);
    let out = cmd.output().map_err(|e| format!("hyprctl: {e}"))?;
    if !out.status.success() {
        return Err(format!(
            "hyprctl {:?}: {}",
            args,
            String::from_utf8_lossy(&out.stderr)
        ));
    }
    serde_json::from_slice(&out.stdout).map_err(|e| format!("hyprctl json: {e}"))
}

pub fn dispatch(dispatcher: &str) -> Result<(), String> {
    let status = Command::new("hyprctl")
        .args(["dispatch", dispatcher])
        .status()
        .map_err(|e| e.to_string())?;
    if status.success() {
        Ok(())
    } else {
        Err(format!("hyprctl dispatch {dispatcher} failed"))
    }
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
pub fn dock_activate(pin: &str, hypr: &HyprState) -> DockAction {
    let pin_l = pin.to_lowercase();
    if pin_matches(&pin_l, &hypr.active_class, &hypr.active_title) {
        let _ = window_minimize();
        return DockAction::Minimized;
    }
    // Restore from special:minimized — clients on special workspaces
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

pub fn refresh_state() -> HyprState {
    let mut state = HyprState::default();
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

pub type SharedHypr = std::sync::Arc<std::sync::Mutex<HyprState>>;

/// Spawn socket2 event reader; refreshes SharedHypr on workspace/activewindow events.
pub fn spawn_socket2_listener(shared: SharedHypr) {
    std::thread::spawn(move || {
        let Some(path) = his_socket2() else {
            return;
        };
        loop {
            match UnixStream::connect(&path) {
                Ok(stream) => {
                    let reader = BufReader::new(stream);
                    for line in reader.lines().flatten() {
                        if line.starts_with("workspace")
                            || line.starts_with("focusedmon")
                            || line.starts_with("activewindow")
                            || line.starts_with("openwindow")
                            || line.starts_with("closewindow")
                        {
                            let next = refresh_state();
                            if let Ok(mut g) = shared.lock() {
                                *g = next;
                            }
                        }
                    }
                }
                Err(_) => {
                    std::thread::sleep(std::time::Duration::from_secs(2));
                }
            }
            std::thread::sleep(std::time::Duration::from_millis(500));
        }
    });
}

/// Write a command to the Hyprland IPC socket (when hyprctl is unavailable).
pub fn socket_command(cmd: &str) -> Result<String, String> {
    let path = his_socket().ok_or("HYPRLAND_INSTANCE_SIGNATURE unset")?;
    let mut stream = UnixStream::connect(&path).map_err(|e| format!("{}: {e}", path.display()))?;
    stream
        .write_all(cmd.as_bytes())
        .map_err(|e| e.to_string())?;
    let mut reader = BufReader::new(stream);
    let mut resp = String::new();
    reader.read_line(&mut resp).map_err(|e| e.to_string())?;
    Ok(resp)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn socket_paths_tolerant() {
        // Without Hyprland env, still returns a constructed path or None.
        let _ = his_socket();
        let _ = his_socket2();
    }
}
