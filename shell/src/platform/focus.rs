use std::process::Command;

use serde::Serialize;

#[derive(Debug, Clone, Default, Serialize)]
pub struct FocusProfile {
    pub id: String,
    pub name: String,
}

pub fn set_chrome_mode(mode: &str) -> Result<(), String> {
    let base = proteus_shell_core::facts::config_base();
    let patch = serde_json::json!({ "chromeMode": mode });
    proteus_shell_core::facts::write_settings(&base, &patch).map(|_| ())
}

pub fn screenshot(kind: &str) -> Result<(), String> {
    let arg = match kind {
        "screen" | "full" => "screen",
        _ => "region",
    };
    Command::new("proteus-screenshot")
        .arg(arg)
        .spawn()
        .map_err(|e| format!("proteus-screenshot: {e}"))?;
    Ok(())
}

/// Focus Mode thin: profiles from Fact + active mode via `~/.config/proteus/focus-mode`.
pub fn focus_profiles() -> Vec<FocusProfile> {
    let base = proteus_shell_core::facts::config_base();
    let settings = proteus_shell_core::facts::read_settings(&base);
    let mut out = Vec::new();
    if let Some(arr) = settings.get("focusProfiles").and_then(|v| v.as_array()) {
        for p in arr {
            let id = p.get("id").and_then(|x| x.as_str()).unwrap_or("").trim();
            if id.is_empty() {
                continue;
            }
            let name = p
                .get("name")
                .and_then(|x| x.as_str())
                .unwrap_or(id)
                .to_string();
            out.push(FocusProfile {
                id: id.into(),
                name,
            });
        }
    }
    if out.is_empty() {
        out.push(FocusProfile {
            id: "work".into(),
            name: "Work".into(),
        });
        out.push(FocusProfile {
            id: "personal".into(),
            name: "Personal".into(),
        });
    }
    out
}

pub fn focus_active_profile_id() -> String {
    let base = proteus_shell_core::facts::config_base();
    let settings = proteus_shell_core::facts::read_settings(&base);
    settings
        .get("focusActiveProfileId")
        .and_then(|v| v.as_str())
        .unwrap_or("work")
        .trim()
        .to_string()
}

pub fn set_focus_active_profile(id: &str) -> Result<(), String> {
    let base = proteus_shell_core::facts::config_base();
    let patch = serde_json::json!({ "focusActiveProfileId": id });
    proteus_shell_core::facts::write_settings(&base, &patch).map(|_| ())?;
    Ok(())
}

/// `off` | `indefinite` (QML FocusMode.mode thin subset; no schedules).
pub fn focus_mode() -> String {
    let base = proteus_shell_core::facts::config_base();
    let path = base.join("proteus/focus-mode");
    std::fs::read_to_string(path)
        .ok()
        .map(|s| s.trim().to_lowercase())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "off".into())
}

pub fn focus_active() -> bool {
    focus_mode() != "off"
}

pub fn set_focus_mode(mode: &str) -> Result<(), String> {
    let mode = match mode.trim().to_lowercase().as_str() {
        "indefinite" | "on" | "1" | "true" => "indefinite",
        _ => "off",
    };
    let base = proteus_shell_core::facts::config_base();
    let dir = base.join("proteus");
    std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    std::fs::write(dir.join("focus-mode"), format!("{mode}\n")).map_err(|e| e.to_string())?;
    Ok(())
}

pub fn set_notifications_dnd(on: bool) -> Result<(), String> {
    let base = proteus_shell_core::facts::config_base();
    let patch = serde_json::json!({ "notificationsDnd": on });
    proteus_shell_core::facts::write_settings(&base, &patch).map(|_| ())?;
    Ok(())
}

pub fn notifications_dnd_fact() -> bool {
    let base = proteus_shell_core::facts::config_base();
    let settings = proteus_shell_core::facts::read_settings(&base);
    settings
        .get("notificationsDnd")
        .and_then(|v| v.as_bool())
        .unwrap_or(false)
}
