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

/// Evaluate `{ enabled, days[1–7], start, end, rrule? }` against local now.
/// When `rrule` is a valid thin WEEKLY (BYDAY ± UNTIL), BYDAY overrides `days`.
pub fn schedule_window_active(schedule: Option<&Value>) -> Option<bool> {
    let schedule = schedule?;
    let enabled = schedule.get("enabled").and_then(|v| v.as_bool())?;
    if !enabled {
        return None;
    }
    let mut days: Vec<u32> = schedule
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
    let now = Local::now();
    if let Some(rrule) = schedule.get("rrule").and_then(|v| v.as_str()) {
        let rrule = rrule.trim();
        if !rrule.is_empty() {
            if let Some((byday, until)) = parse_weekly_rrule(rrule) {
                if let Some(until) = until {
                    if now.date_naive() > until {
                        // Recurrence ended — schedule inactive (no edge apply).
                        return None;
                    }
                }
                if !byday.is_empty() {
                    days = byday;
                }
            }
        }
    }
    if days.is_empty() {
        return None;
    }
    let start = parse_hhmm(schedule.get("start").and_then(|v| v.as_str())?)?;
    let end = parse_hhmm(schedule.get("end").and_then(|v| v.as_str())?)?;
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

/// Thin RRULE: `FREQ=WEEKLY` + `BYDAY=MO,TU,…` (+ optional `UNTIL=YYYYMMDD`).
/// `INTERVAL` must be absent or `1`. Returns `(days 1–7, until date)`.
pub fn parse_weekly_rrule(rrule: &str) -> Option<(Vec<u32>, Option<chrono::NaiveDate>)> {
    let mut freq_weekly = false;
    let mut byday: Vec<u32> = Vec::new();
    let mut until: Option<chrono::NaiveDate> = None;
    for part in rrule.split(';') {
        let part = part.trim();
        if part.is_empty() {
            continue;
        }
        let (key, val) = match part.split_once('=') {
            Some((k, v)) => (k.trim(), v.trim()),
            None => continue,
        };
        match key.to_ascii_uppercase().as_str() {
            "FREQ" => {
                if !val.eq_ignore_ascii_case("WEEKLY") {
                    return None;
                }
                freq_weekly = true;
            }
            "INTERVAL" => {
                if val != "1" {
                    return None;
                }
            }
            "BYDAY" => {
                for tok in val.split(',') {
                    let d = match tok.trim().to_ascii_uppercase().as_str() {
                        "MO" => 1,
                        "TU" => 2,
                        "WE" => 3,
                        "TH" => 4,
                        "FR" => 5,
                        "SA" => 6,
                        "SU" => 7,
                        _ => continue,
                    };
                    if !byday.contains(&d) {
                        byday.push(d);
                    }
                }
            }
            "UNTIL" => {
                // YYYYMMDD or YYYYMMDDTHHMMSSZ — date prefix only.
                let digits: String = val.chars().take(8).filter(|c| c.is_ascii_digit()).collect();
                if digits.len() == 8 {
                    until = chrono::NaiveDate::parse_from_str(&digits, "%Y%m%d").ok();
                }
            }
            "COUNT" => {
                // Thin: ignore COUNT (day/time window still applies).
            }
            _ => {}
        }
    }
    if !freq_weekly || byday.is_empty() {
        return None;
    }
    byday.sort_unstable();
    Some((byday, until))
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

fn string_list(v: Option<&Value>) -> Vec<String> {
    v.and_then(|x| x.as_array())
        .map(|a| {
            a.iter()
                .filter_map(|e| e.as_str())
                .map(|s| s.trim().to_lowercase())
                .filter(|s| !s.is_empty())
                .collect()
        })
        .unwrap_or_default()
}

fn active_focus_profile(settings: &Value) -> Option<&Value> {
    let active = settings
        .get("focusActiveProfileId")
        .and_then(|v| v.as_str())
        .unwrap_or("work")
        .trim();
    settings
        .get("focusProfiles")
        .and_then(|v| v.as_array())
        .and_then(|arr| {
            arr.iter().find(|p| {
                p.get("id").and_then(|x| x.as_str()).unwrap_or("") == active
            })
        })
}

/// Settings / escape apps — allowed when profile `breakCritical` is true (default).
fn is_critical_escape(desktop_id: &str) -> bool {
    desktop_id.contains("proteus-settings")
        || desktop_id == "org.proteus.settings"
        || desktop_id.contains("proteussettings")
}

fn profile_break_critical(profile: &Value) -> bool {
    profile
        .get("breakCritical")
        .and_then(|v| v.as_bool())
        .unwrap_or(true)
}

/// Whether a Beacon/Dock launch target is permitted under the active Focus profile.
///
/// When Focus is off → always allow. When on:
/// - `breakCritical` (default true) always allows Settings escape apps
/// - `keywordDeny` substrings block the desktop id
/// - non-empty `allowedApps` is a whitelist (desktop id / basename match)
/// - else non-empty `keywordAllow` requires a substring match
/// - empty lists → allow (no enforce)
pub fn focus_launch_allowed(desktop_id: &str) -> bool {
    if !focus_active() {
        return true;
    }
    let id = desktop_id
        .trim()
        .trim_end_matches(".desktop")
        .to_lowercase();
    if id.is_empty() {
        return true;
    }
    let base = proteus_shell_core::facts::config_base();
    let settings = proteus_shell_core::facts::read_settings(&base);
    let Some(profile) = active_focus_profile(&settings) else {
        return true;
    };
    if profile_break_critical(profile) && is_critical_escape(&id) {
        return true;
    }
    let deny = string_list(profile.get("keywordDeny"));
    if deny.iter().any(|k| id.contains(k.as_str())) {
        return false;
    }
    let allowed = string_list(profile.get("allowedApps"));
    if !allowed.is_empty() {
        return allowed.iter().any(|a| {
            let a = a.trim_end_matches(".desktop");
            id == a || id.ends_with(&format!(".{a}")) || a.ends_with(&format!(".{id}")) || id.contains(a)
        });
    }
    let allow_kw = string_list(profile.get("keywordAllow"));
    if !allow_kw.is_empty() {
        return allow_kw.iter().any(|k| id.contains(k.as_str()));
    }
    true
}

/// Pure helper for tests — same rules without reading Focus mode / Facts.
pub fn focus_launch_allowed_for_profile(desktop_id: &str, profile: &Value, focus_on: bool) -> bool {
    if !focus_on {
        return true;
    }
    let id = desktop_id
        .trim()
        .trim_end_matches(".desktop")
        .to_lowercase();
    if id.is_empty() {
        return true;
    }
    if profile_break_critical(profile) && is_critical_escape(&id) {
        return true;
    }
    let deny = string_list(profile.get("keywordDeny"));
    if deny.iter().any(|k| id.contains(k.as_str())) {
        return false;
    }
    let allowed = string_list(profile.get("allowedApps"));
    if !allowed.is_empty() {
        return allowed.iter().any(|a| {
            let a = a.trim_end_matches(".desktop");
            id == a || id.contains(a)
        });
    }
    let allow_kw = string_list(profile.get("keywordAllow"));
    if !allow_kw.is_empty() {
        return allow_kw.iter().any(|k| id.contains(k.as_str()));
    }
    true
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

    #[test]
    fn parse_weekly_rrule_byday_and_until() {
        let (days, until) =
            parse_weekly_rrule("FREQ=WEEKLY;BYDAY=MO,WE,FR;UNTIL=20261231").unwrap();
        assert_eq!(days, vec![1, 3, 5]);
        assert_eq!(
            until,
            Some(chrono::NaiveDate::from_ymd_opt(2026, 12, 31).unwrap())
        );
        assert!(parse_weekly_rrule("FREQ=DAILY;BYDAY=MO").is_none());
        assert!(parse_weekly_rrule("FREQ=WEEKLY;INTERVAL=2;BYDAY=MO").is_none());
        assert!(parse_weekly_rrule("FREQ=WEEKLY").is_none());
    }

    #[test]
    fn schedule_rrule_overrides_days_all_week() {
        let sched = json!({
            "enabled": true,
            "days": [1],
            "start": "00:00",
            "end": "23:59",
            "rrule": "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR,SA,SU"
        });
        assert_eq!(schedule_window_active(Some(&sched)), Some(true));
        let expired = json!({
            "enabled": true,
            "days": [1, 2, 3, 4, 5, 6, 7],
            "start": "00:00",
            "end": "23:59",
            "rrule": "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR,SA,SU;UNTIL=20200101"
        });
        assert_eq!(schedule_window_active(Some(&expired)), None);
    }

    #[test]
    fn launch_allowed_apps_and_keywords() {
        let p = json!({
            "allowedApps": ["org.gnome.Calculator", "ghostty"],
            "keywordAllow": [],
            "keywordDeny": ["steam"]
        });
        assert!(focus_launch_allowed_for_profile("org.gnome.Calculator", &p, true));
        assert!(focus_launch_allowed_for_profile("ghostty.desktop", &p, true));
        assert!(!focus_launch_allowed_for_profile("firefox", &p, true));
        assert!(!focus_launch_allowed_for_profile("steam", &p, true));
        assert!(focus_launch_allowed_for_profile("firefox", &p, false));

        let kw = json!({
            "allowedApps": [],
            "keywordAllow": ["term", "code"],
            "keywordDeny": ["game"]
        });
        assert!(focus_launch_allowed_for_profile("proteus-terminal", &kw, true));
        assert!(!focus_launch_allowed_for_profile("game-store", &kw, true));
        assert!(!focus_launch_allowed_for_profile("firefox", &kw, true));

        let locked = json!({
            "breakCritical": true,
            "allowedApps": ["ghostty"],
            "keywordAllow": [],
            "keywordDeny": []
        });
        assert!(focus_launch_allowed_for_profile("proteus-settings", &locked, true));
        assert!(!focus_launch_allowed_for_profile("firefox", &locked, true));
        let no_escape = json!({
            "breakCritical": false,
            "allowedApps": ["ghostty"],
            "keywordAllow": [],
            "keywordDeny": []
        });
        assert!(!focus_launch_allowed_for_profile("proteus-settings", &no_escape, true));
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
