use std::process::Command;

use chrono::{Datelike, Local, Timelike};
use serde::Serialize;
use serde_json::Value;

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

/// Active profile's schedule window — `None` if schedule disabled / missing.
pub fn focus_schedule_should_be_on() -> Option<bool> {
    let base = proteus_shell_core::facts::config_base();
    let settings = proteus_shell_core::facts::read_settings(&base);
    let active = focus_active_profile_id();
    let profile = settings
        .get("focusProfiles")
        .and_then(|v| v.as_array())
        .and_then(|arr| {
            arr.iter().find(|p| {
                p.get("id").and_then(|x| x.as_str()).unwrap_or("") == active.as_str()
            })
        });
    let Some(profile) = profile else {
        return None;
    };
    schedule_window_active(profile.get("schedule"))
}

/// Evaluate `{ enabled, days[1–7], start, end }` against local now.
pub fn schedule_window_active(schedule: Option<&Value>) -> Option<bool> {
    let schedule = schedule?;
    let enabled = schedule.get("enabled").and_then(|v| v.as_bool())?;
    if !enabled {
        return None;
    }
    let days: Vec<u32> = schedule
        .get("days")
        .and_then(|v| v.as_array())
        .map(|a| {
            a.iter()
                .filter_map(|d| d.as_u64().or_else(|| d.as_i64().map(|i| i as u64)))
                .filter(|d| (1..=7).contains(d))
                .map(|d| d as u32)
                .collect()
        })
        .unwrap_or_default();
    if days.is_empty() {
        return None;
    }
    let start = parse_hhmm(schedule.get("start").and_then(|v| v.as_str())?)?;
    let end = parse_hhmm(schedule.get("end").and_then(|v| v.as_str())?)?;
    let now = Local::now();
    // chrono: Mon=1 … Sun=7 (matches Settings Focus days).
    let dow = now.weekday().number_from_monday();
    if !days.contains(&dow) {
        return Some(false);
    }
    let mins = now.hour() * 60 + now.minute();
    let in_window = if end < start {
        // Overnight window (e.g. 22:00–06:00).
        mins >= start || mins < end
    } else {
        mins >= start && mins < end
    };
    Some(in_window)
}

fn parse_hhmm(s: &str) -> Option<u32> {
    let (h, m) = s.trim().split_once(':')?;
    let h: u32 = h.parse().ok()?;
    let m: u32 = m.parse().ok()?;
    if h > 23 || m > 59 {
        return None;
    }
    Some(h * 60 + m)
}

/// Apply schedule edge: turn Focus on/off when window membership changes.
/// Returns new `last` state to store on the app (`None` = schedule inactive).
pub fn apply_focus_schedule(last: Option<bool>) -> Option<bool> {
    let want = focus_schedule_should_be_on();
    let Some(want) = want else {
        return None;
    };
    if last == Some(want) {
        return Some(want);
    }
    let mode = if want { "indefinite" } else { "off" };
    let _ = set_focus_mode(mode);
    Some(want)
}

/// `off` | `indefinite` (QML FocusMode.mode thin subset; schedules apply via `apply_focus_schedule`).
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

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn schedule_window_days_and_overnight() {
        let sched = json!({
            "enabled": true,
            "days": [1, 2, 3, 4, 5, 6, 7],
            "start": "00:00",
            "end": "23:59"
        });
        assert_eq!(schedule_window_active(Some(&sched)), Some(true));
        let off = json!({
            "enabled": false,
            "days": [1],
            "start": "09:00",
            "end": "17:00"
        });
        assert_eq!(schedule_window_active(Some(&off)), None);
        let empty_days = json!({
            "enabled": true,
            "days": [],
            "start": "09:00",
            "end": "17:00"
        });
        assert_eq!(schedule_window_active(Some(&empty_days)), None);
    }

    #[test]
    fn parse_hhmm_ok() {
        assert_eq!(parse_hhmm("09:30"), Some(9 * 60 + 30));
        assert!(parse_hhmm("25:00").is_none());
    }
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
