use std::process::Command;

use serde::Serialize;

use super::util::{sh_ok, which_like};

#[derive(Debug, Clone, Default, Serialize)]
pub struct PowerStatus {
    pub on_battery: bool,
    pub percent: u8,
    pub profile: String,
}

#[derive(Debug, Clone, Default, Serialize)]
pub struct PrivacyDots {
    pub mic: bool,
    pub camera: bool,
    pub screen: bool,
}

/// Brightness 0–100 via brightnessctl when present.
pub fn brightness_get() -> Option<u8> {
    let out = Command::new("brightnessctl").args(["-m"]).output().ok()?;
    if !out.status.success() {
        return None;
    }
    let line = String::from_utf8_lossy(&out.stdout);
    let pct = line.split(',').nth(3)?;
    pct.trim().trim_end_matches('%').parse().ok()
}

pub fn brightness_set(pct: u8) -> Result<(), String> {
    let status = Command::new("brightnessctl")
        .args(["set", &format!("{pct}%")])
        .status()
        .map_err(|e| e.to_string())?;
    if status.success() {
        Ok(())
    } else {
        Err("brightnessctl failed".into())
    }
}

pub fn brightness_step(delta: i8) -> Option<u8> {
    let cur = brightness_get().unwrap_or(50);
    let next = (cur as i16 + delta as i16).clamp(0, 100) as u8;
    let _ = brightness_set(next);
    Some(next)
}

/// Default sink volume 0–100 via pactl.
pub fn volume_get() -> Option<u8> {
    let out = Command::new("pactl")
        .args(["get-sink-volume", "@DEFAULT_SINK@"])
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }
    let text = String::from_utf8_lossy(&out.stdout);
    for tok in text.split_whitespace() {
        if let Some(p) = tok.strip_suffix('%') {
            if let Ok(v) = p.parse::<u8>() {
                return Some(v.min(150));
            }
        }
    }
    None
}

pub fn volume_set(pct: u8) -> Result<(), String> {
    let pct = pct.min(150);
    sh_ok(
        "pactl",
        &["set-sink-volume", "@DEFAULT_SINK@", &format!("{pct}%")],
    )
}

pub fn volume_step(delta: i8) -> Option<u8> {
    let cur = volume_get().unwrap_or(50);
    let next = (cur as i16 + delta as i16).clamp(0, 150) as u8;
    let _ = volume_set(next);
    Some(next)
}

pub fn volume_mute_toggle() -> Result<bool, String> {
    sh_ok("pactl", &["set-sink-mute", "@DEFAULT_SINK@", "toggle"])?;
    let out = Command::new("pactl")
        .args(["get-sink-mute", "@DEFAULT_SINK@"])
        .output()
        .map_err(|e| e.to_string())?;
    let text = String::from_utf8_lossy(&out.stdout);
    Ok(text.to_lowercase().contains("yes"))
}

pub fn power_status() -> PowerStatus {
    let mut s = PowerStatus {
        profile: "balanced".into(),
        ..Default::default()
    };
    if let Ok(out) = Command::new("powerprofilesctl").arg("get").output() {
        if out.status.success() {
            s.profile = String::from_utf8_lossy(&out.stdout).trim().into();
        }
    }
    if let Ok(out) = Command::new("upower")
        .args(["-i", "/org/freedesktop/UPower/devices/DisplayDevice"])
        .output()
    {
        let text = String::from_utf8_lossy(&out.stdout);
        for line in text.lines() {
            if let Some(rest) = line.trim().strip_prefix("percentage:") {
                if let Ok(p) = rest.trim().trim_end_matches('%').trim().parse::<f32>() {
                    s.percent = p as u8;
                }
            }
            if let Some(rest) = line.trim().strip_prefix("state:") {
                s.on_battery = rest.trim() == "discharging";
            }
        }
    }
    s
}

/// Map CC segmented index → powerprofilesctl name.
pub fn power_set_profile_index(idx: usize) -> Result<(), String> {
    let name = match idx {
        0 => "performance",
        2 => "power-saver",
        _ => "balanced",
    };
    sh_ok("powerprofilesctl", &["set", name])
}

pub fn power_profile_index(profile: &str) -> usize {
    match profile.trim().to_lowercase().as_str() {
        "performance" => 0,
        "power-saver" | "powersaver" | "power_saver" => 2,
        _ => 1,
    }
}

/// Mic / camera / screen activity via privacy-indicators.py.
pub fn privacy_dots() -> PrivacyDots {
    let script = privacy_indicators_bin();
    let Some(bin) = script else {
        return PrivacyDots::default();
    };
    let out = Command::new(&bin).output().ok();
    let Some(out) = out else {
        return PrivacyDots::default();
    };
    if !out.status.success() {
        return PrivacyDots::default();
    }
    let v: serde_json::Value = serde_json::from_slice(&out.stdout).unwrap_or_default();
    PrivacyDots {
        mic: v.get("mic").and_then(|x| x.as_bool()).unwrap_or(false),
        camera: v.get("camera").and_then(|x| x.as_bool()).unwrap_or(false),
        screen: v.get("screen").and_then(|x| x.as_bool()).unwrap_or(false),
    }
}

fn privacy_indicators_bin() -> Option<std::path::PathBuf> {
    if let Ok(p) = which_like("privacy-indicators.py") {
        return Some(p);
    }
    for root in [
        std::env::var("PROTEUS_ROOT").ok().map(std::path::PathBuf::from),
        Some(std::path::PathBuf::from("/mnt/proteus")),
        std::env::var("HOME")
            .ok()
            .map(|h| std::path::PathBuf::from(h).join("Projects/Proteus")),
    ]
    .into_iter()
    .flatten()
    {
        let p = root.join("shell/scripts/privacy-indicators.py");
        if p.is_file() {
            return Some(p);
        }
    }
    None
}
