//! Control socket — `proteus-shellctl` ↔ running `proteus-shell`.
//!
//! Wire protocol: one JSON request line, one JSON response line.
//! Targets/verbs match Quickshell IpcHandler (`lock`, `chrome`, `widgets`, `hud`).

use std::collections::VecDeque;
use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::Path;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;

use serde::{Deserialize, Serialize};
use serde_json::json;

use crate::engine;
use crate::ipc_targets;
use crate::platform;

pub type ChromeEpoch = Arc<AtomicU64>;

fn bump(epoch: &ChromeEpoch) {
    epoch.fetch_add(1, Ordering::Relaxed);
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Request {
    pub target: String,
    pub method: String,
    #[serde(default)]
    pub args: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Response {
    pub ok: bool,
    #[serde(default)]
    pub error: String,
    #[serde(default)]
    pub result: serde_json::Value,
}

/// Shared chrome FSM — what Quickshell ShellState tracked for overlays.
#[derive(Debug, Default)]
pub struct ChromeState {
    pub launcher_open: bool,
    pub control_center_open: bool,
    pub calendar_open: bool,
    pub weather_open: bool,
    pub locked: bool,
    pub session_start_lock_pending: bool,
    /// True when ext-session-lock helper owns the lock surface (overlay lock hidden).
    pub protocol_lock: bool,
    pub hud_kind: String,
    pub hud_value: f32,
    pub toast_queue: VecDeque<String>,
    pub privacy_ask: Option<String>,
    pub widgets_customize: bool,
    /// Customize Lock Screen edit chrome on the lock layer.
    pub lock_customize: bool,
    pub widgets: Vec<String>,
    pub widgets_snap: bool,
    pub face: String, // desktop | console | host
    pub beacon_query: String,
    pub console_nav_open: bool,
    pub console_switcher_open: bool,
    /// Console list-IA tab: Games · Media · Apps · Search · Settings
    pub console_tab: usize,
}

impl ChromeState {
    pub fn snapshot(&self) -> serde_json::Value {
        json!({
            "launcher": self.launcher_open,
            "controlCenter": self.control_center_open,
            "calendar": self.calendar_open,
            "weather": self.weather_open,
            "locked": self.locked,
            "sessionStartLockPending": self.session_start_lock_pending,
            "protocolLock": self.protocol_lock,
            "hud": { "kind": self.hud_kind, "value": self.hud_value },
            "face": self.face,
            "beaconQuery": self.beacon_query,
            "consoleNav": self.console_nav_open,
            "consoleSwitcher": self.console_switcher_open,
            "consoleTab": self.console_tab,
            "widgetsCustomize": self.widgets_customize,
            "lockCustomize": self.lock_customize,
            "widgets": self.widgets,
            "widgetsSnap": self.widgets_snap,
            "privacyAsk": self.privacy_ask,
            "engine": "owned",
            "layers": crate::layers::all(),
            "targets": ipc_targets::all(),
        })
    }
}

pub type SharedChrome = Arc<Mutex<ChromeState>>;

fn overlays_blocked(s: &ChromeState) -> bool {
    s.locked || s.session_start_lock_pending
}

fn overlay_denied() -> Response {
    Response {
        ok: false,
        error: "overlays blocked while locked".into(),
        result: json!({"blocked": true}),
    }
}

pub fn handle_request(state: &SharedChrome, epoch: &ChromeEpoch, req: &Request) -> Response {
    let mut s = match state.lock() {
        Ok(g) => g,
        Err(_) => {
            return Response {
                ok: false,
                error: "state poisoned".into(),
                result: json!(null),
            }
        }
    };
    let target = req.target.as_str();
    let method = req.method.as_str();
    let resp = match (target, method) {
        (ipc_targets::LOCK, "lock") => {
            let (mode, fb) = engine::activate_session_lock(engine::resolve_session_lock());
            let mut protocol = false;
            if mode == engine::SessionLockMode::Protocol {
                match engine::spawn_protocol_lock() {
                    Ok(true) => protocol = true,
                    Ok(false) => {
                        eprintln!(
                            "proteus-shell: protocol lock helper missing; overlay fallback"
                        );
                    }
                    Err(e) => {
                        eprintln!("proteus-shell: protocol lock spawn failed: {e}; overlay fallback");
                    }
                }
            } else if let Some(r) = fb {
                eprintln!("proteus-shell: session_lock: {r}");
            }
            s.locked = true;
            s.protocol_lock = protocol;
            s.launcher_open = false;
            s.control_center_open = false;
            s.calendar_open = false;
            s.weather_open = false;
            bump(epoch);
            Response {
                ok: true,
                error: String::new(),
                result: json!({"locked": true, "protocolLock": protocol}),
            }
        }
        (ipc_targets::LOCK, "customize") => {
            s.lock_customize = !s.lock_customize;
            bump(epoch);
            Response {
                ok: true,
                error: String::new(),
                result: json!({"lockCustomize": s.lock_customize}),
            }
        }
        (ipc_targets::LOCK, "unlock") => {
            s.locked = false;
            s.protocol_lock = false;
            s.session_start_lock_pending = false;
            bump(epoch);
            Response {
                ok: true,
                error: String::new(),
                result: json!({"locked": false}),
            }
        }
        (ipc_targets::CHROME, "state") => Response {
            ok: true,
            error: String::new(),
            result: s.snapshot(),
        },
        (ipc_targets::CHROME, "launcher" | "beacon") => {
            if overlays_blocked(&s) {
                return overlay_denied();
            }
            s.launcher_open = !s.launcher_open;
            if s.launcher_open {
                s.control_center_open = false;
            }
            bump(epoch);
            Response {
                ok: true,
                error: String::new(),
                result: json!({"launcher": s.launcher_open}),
            }
        }
        (ipc_targets::CHROME, "beaconState") => Response {
            ok: true,
            error: String::new(),
            result: json!({"open": s.launcher_open, "query": s.beacon_query}),
        },
        (ipc_targets::CHROME, "controlCenter") => {
            if overlays_blocked(&s) {
                return overlay_denied();
            }
            s.control_center_open = !s.control_center_open;
            if s.control_center_open {
                s.launcher_open = false;
            }
            bump(epoch);
            Response {
                ok: true,
                error: String::new(),
                result: json!({"controlCenter": s.control_center_open}),
            }
        }
        (ipc_targets::CHROME, "calendar") => {
            if overlays_blocked(&s) {
                return overlay_denied();
            }
            s.calendar_open = !s.calendar_open;
            bump(epoch);
            Response {
                ok: true,
                error: String::new(),
                result: json!({"calendar": s.calendar_open}),
            }
        }
        (ipc_targets::CHROME, "weather") => {
            if overlays_blocked(&s) {
                return overlay_denied();
            }
            s.weather_open = !s.weather_open;
            bump(epoch);
            Response {
                ok: true,
                error: String::new(),
                result: json!({"weather": s.weather_open}),
            }
        }
        (ipc_targets::CHROME, "pad") => {
            let pad = req.args.first().cloned().unwrap_or_default();
            Response {
                ok: true,
                error: String::new(),
                result: json!({"pad": pad}),
            }
        }
        (ipc_targets::CHROME, "customizeDesktop") => {
            if overlays_blocked(&s) {
                return overlay_denied();
            }
            s.widgets_customize = !s.widgets_customize;
            bump(epoch);
            Response {
                ok: true,
                error: String::new(),
                result: json!({"customize": s.widgets_customize}),
            }
        }
        (ipc_targets::CHROME, "dockLaunch") => {
            let id = req.args.first().cloned().unwrap_or_default();
            let arg = if id.to_lowercase().contains("workload") {
                "workloads"
            } else {
                "settings"
            };
            let _ = std::process::Command::new("proteus-open").arg(arg).spawn();
            Response {
                ok: true,
                error: String::new(),
                result: json!({"launched": id}),
            }
        }
        (ipc_targets::CHROME, "focusCycle") => {
            let _ = crate::hypr::dispatch("cyclenext");
            Response {
                ok: true,
                error: String::new(),
                result: json!({"ok": true}),
            }
        }
        (ipc_targets::CHROME, "consoleNav") => {
            s.console_nav_open = !s.console_nav_open;
            bump(epoch);
            Response {
                ok: true,
                error: String::new(),
                result: json!({"consoleNav": s.console_nav_open}),
            }
        }
        (ipc_targets::CHROME, "consoleHide") => {
            s.console_nav_open = false;
            s.console_switcher_open = false;
            bump(epoch);
            Response {
                ok: true,
                error: String::new(),
                result: json!({"hidden": true}),
            }
        }
        (ipc_targets::CHROME, "consoleSwitcher") => {
            s.console_switcher_open = !s.console_switcher_open;
            bump(epoch);
            Response {
                ok: true,
                error: String::new(),
                result: json!({"switcher": s.console_switcher_open}),
            }
        }
        (ipc_targets::CHROME, "consoleCC") => {
            s.control_center_open = !s.control_center_open;
            bump(epoch);
            Response {
                ok: true,
                error: String::new(),
                result: json!({"controlCenter": s.control_center_open}),
            }
        }
        (ipc_targets::CHROME, "consoleTab") => {
            let tab = req
                .args
                .first()
                .and_then(|a| a.parse::<usize>().ok())
                .unwrap_or(0)
                .min(4);
            s.console_tab = tab;
            s.console_nav_open = true;
            bump(epoch);
            Response {
                ok: true,
                error: String::new(),
                result: json!({"consoleTab": s.console_tab}),
            }
        }
        (ipc_targets::CHROME, "privacyAsk") => {
            s.privacy_ask = req.args.first().cloned();
            bump(epoch);
            Response {
                ok: true,
                error: String::new(),
                result: json!({"privacyAsk": s.privacy_ask}),
            }
        }
        (ipc_targets::HUD, "ping" | "hide") => {
            if method == "hide" {
                s.hud_kind.clear();
                bump(epoch);
            }
            Response {
                ok: true,
                error: String::new(),
                result: json!({"hud": s.hud_kind}),
            }
        }
        (ipc_targets::HUD, "volume" | "brightness") => {
            s.hud_kind = method.into();
            if let Some(v) = req.args.first().and_then(|a| a.parse::<f32>().ok()) {
                s.hud_value = v;
                if method == "brightness" {
                    let _ = platform::brightness_set(v.clamp(0.0, 100.0) as u8);
                } else {
                    let _ = platform::volume_set(v.clamp(0.0, 150.0) as u8);
                }
            } else if method == "brightness" {
                if let Some(v) = platform::brightness_get() {
                    s.hud_value = f32::from(v);
                }
            } else if let Some(v) = platform::volume_get() {
                s.hud_value = f32::from(v);
            }
            bump(epoch);
            Response {
                ok: true,
                error: String::new(),
                result: json!({"kind": s.hud_kind, "value": s.hud_value}),
            }
        }
        (ipc_targets::HUD, "volumeUp") => {
            let v = platform::volume_step(5).unwrap_or(0);
            s.hud_kind = "volume".into();
            s.hud_value = f32::from(v);
            bump(epoch);
            Response {
                ok: true,
                error: String::new(),
                result: json!({"kind": "volume", "value": v}),
            }
        }
        (ipc_targets::HUD, "volumeDown") => {
            let v = platform::volume_step(-5).unwrap_or(0);
            s.hud_kind = "volume".into();
            s.hud_value = f32::from(v);
            bump(epoch);
            Response {
                ok: true,
                error: String::new(),
                result: json!({"kind": "volume", "value": v}),
            }
        }
        (ipc_targets::HUD, "volumeMute" | "mute") => {
            let muted = platform::volume_mute_toggle().unwrap_or(false);
            s.hud_kind = "volume".into();
            bump(epoch);
            Response {
                ok: true,
                error: String::new(),
                result: json!({"muted": muted}),
            }
        }
        (ipc_targets::HUD, "brightnessUp") => {
            let v = platform::brightness_step(5).unwrap_or(0);
            s.hud_kind = "brightness".into();
            s.hud_value = f32::from(v);
            bump(epoch);
            Response {
                ok: true,
                error: String::new(),
                result: json!({"kind": "brightness", "value": v}),
            }
        }
        (ipc_targets::HUD, "brightnessDown") => {
            let v = platform::brightness_step(-5).unwrap_or(0);
            s.hud_kind = "brightness".into();
            s.hud_value = f32::from(v);
            bump(epoch);
            Response {
                ok: true,
                error: String::new(),
                result: json!({"kind": "brightness", "value": v}),
            }
        }
        (ipc_targets::HUD, "step") => Response {
            ok: true,
            error: String::new(),
            result: json!({"method": method, "args": req.args}),
        },
        (ipc_targets::WIDGETS, "state") => Response {
            ok: true,
            error: String::new(),
            result: json!({
                "customize": s.widgets_customize,
                "widgets": s.widgets,
                "snap": s.widgets_snap,
            }),
        },
        (ipc_targets::WIDGETS, "add") => {
            if let Some(kind) = req.args.first() {
                if !s.widgets.iter().any(|w| w == kind) {
                    s.widgets.push(kind.clone());
                }
            }
            bump(epoch);
            Response {
                ok: true,
                error: String::new(),
                result: json!({"widgets": s.widgets}),
            }
        }
        (ipc_targets::WIDGETS, "remove") => {
            if let Some(kind) = req.args.first() {
                s.widgets.retain(|w| w != kind);
            }
            bump(epoch);
            Response {
                ok: true,
                error: String::new(),
                result: json!({"widgets": s.widgets}),
            }
        }
        (ipc_targets::WIDGETS, "move") => {
            // args: from_idx to_idx — best-effort reorder
            if req.args.len() >= 2 {
                if let (Ok(from), Ok(to)) = (req.args[0].parse::<usize>(), req.args[1].parse::<usize>()) {
                    if from < s.widgets.len() && to < s.widgets.len() {
                        let item = s.widgets.remove(from);
                        s.widgets.insert(to, item);
                    }
                }
            }
            bump(epoch);
            Response {
                ok: true,
                error: String::new(),
                result: json!({"widgets": s.widgets}),
            }
        }
        (ipc_targets::WIDGETS, "setSnap") => {
            if let Some(v) = req.args.first() {
                s.widgets_snap = v == "1" || v.eq_ignore_ascii_case("true");
            } else {
                s.widgets_snap = !s.widgets_snap;
            }
            bump(epoch);
            Response {
                ok: true,
                error: String::new(),
                result: json!({"snap": s.widgets_snap}),
            }
        },
        _ => Response {
            ok: false,
            error: format!("unknown {target}.{method}"),
            result: json!(null),
        },
    };
    resp
}

pub fn call(req: &Request) -> Result<Response, String> {
    let path = engine::control_socket_path();
    let mut stream =
        UnixStream::connect(&path).map_err(|e| format!("{}: {e}", path.display()))?;
    let line = serde_json::to_string(req).map_err(|e| e.to_string())?;
    writeln!(stream, "{line}").map_err(|e| e.to_string())?;
    let mut reader = BufReader::new(stream);
    let mut resp = String::new();
    reader.read_line(&mut resp).map_err(|e| e.to_string())?;
    serde_json::from_str(resp.trim()).map_err(|e| format!("bad response: {e}"))
}

/// Spawn accept loop on `path`. Returns immediately; serves until process exit.
pub fn serve(path: &Path, state: SharedChrome, epoch: ChromeEpoch) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    let _ = std::fs::remove_file(path);
    let listener = UnixListener::bind(path).map_err(|e| format!("{}: {e}", path.display()))?;
    thread::spawn(move || {
        for stream in listener.incoming().flatten() {
            let state = Arc::clone(&state);
            let epoch = Arc::clone(&epoch);
            thread::spawn(move || {
                let mut reader = BufReader::new(&stream);
                let mut line = String::new();
                if reader.read_line(&mut line).is_err() {
                    return;
                }
                let req: Request = match serde_json::from_str(line.trim()) {
                    Ok(r) => r,
                    Err(e) => {
                        let _ = writeln!(
                            &mut (&stream),
                            "{}",
                            json!({"ok": false, "error": e.to_string(), "result": null})
                        );
                        return;
                    }
                };
                let resp = handle_request(&state, &epoch, &req);
                let _ = writeln!(
                    &mut (&stream),
                    "{}",
                    serde_json::to_string(&resp).unwrap_or_default()
                );
            });
        }
    });
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn chrome_toggle() {
        let state = Arc::new(Mutex::new(ChromeState::default()));
        let epoch = Arc::new(AtomicU64::new(0));
        let r = handle_request(
            &state,
            &epoch,
            &Request {
                target: "chrome".into(),
                method: "launcher".into(),
                args: vec![],
            },
        );
        assert!(r.ok);
        assert!(state.lock().unwrap().launcher_open);
        assert!(epoch.load(Ordering::Relaxed) > 0);
    }

    #[test]
    fn lock_roundtrip() {
        let state = Arc::new(Mutex::new(ChromeState::default()));
        let epoch = Arc::new(AtomicU64::new(0));
        handle_request(
            &state,
            &epoch,
            &Request {
                target: "lock".into(),
                method: "lock".into(),
                args: vec![],
            },
        );
        assert!(state.lock().unwrap().locked);
        handle_request(
            &state,
            &epoch,
            &Request {
                target: "lock".into(),
                method: "unlock".into(),
                args: vec![],
            },
        );
        assert!(!state.lock().unwrap().locked);
    }
}
