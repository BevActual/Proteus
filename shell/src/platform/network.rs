use std::process::Command;

use serde::Serialize;

use super::util::sh_ok;

#[derive(Debug, Clone, Default, Serialize)]
pub struct WifiHit {
    pub ssid: String,
    pub signal: u8,
    pub active: bool,
}

#[derive(Debug, Clone, Default, Serialize)]
pub struct BtHit {
    pub mac: String,
    pub name: String,
    pub connected: bool,
}

pub fn wifi_list_thin() -> Vec<WifiHit> {
    let out = Command::new("nmcli")
        .args(["-t", "-f", "SSID,SIGNAL,ACTIVE", "dev", "wifi"])
        .output();
    let Ok(out) = out else {
        return Vec::new();
    };
    let mut hits = Vec::new();
    for line in String::from_utf8_lossy(&out.stdout).lines() {
        let parts: Vec<_> = line.split(':').collect();
        if parts.len() < 3 {
            continue;
        }
        let ssid = parts[0].trim();
        if ssid.is_empty() {
            continue;
        }
        let signal = parts[1].trim().parse().unwrap_or(0);
        let active = parts[2].trim().eq_ignore_ascii_case("yes");
        hits.push(WifiHit {
            ssid: ssid.into(),
            signal,
            active,
        });
    }
    hits.truncate(12);
    hits
}

pub fn wifi_connect(ssid: &str) -> Result<(), String> {
    sh_ok("nmcli", &["dev", "wifi", "connect", ssid])
}

pub fn bt_list_thin() -> Vec<BtHit> {
    let out = Command::new("bluetoothctl").args(["devices"]).output();
    let Ok(out) = out else {
        return Vec::new();
    };
    let connected: std::collections::HashSet<String> = Command::new("bluetoothctl")
        .args(["devices", "Connected"])
        .output()
        .ok()
        .map(|o| {
            String::from_utf8_lossy(&o.stdout)
                .lines()
                .filter_map(|l| l.split_whitespace().nth(1).map(|s| s.to_string()))
                .collect()
        })
        .unwrap_or_default();
    let mut hits = Vec::new();
    for line in String::from_utf8_lossy(&out.stdout).lines() {
        let mut parts = line.split_whitespace();
        if parts.next() != Some("Device") {
            continue;
        }
        let Some(mac) = parts.next() else { continue };
        let name = parts.collect::<Vec<_>>().join(" ");
        hits.push(BtHit {
            mac: mac.into(),
            name: if name.is_empty() { mac.into() } else { name },
            connected: connected.contains(mac),
        });
    }
    hits.truncate(12);
    hits
}

pub fn bt_connect(mac: &str) -> Result<(), String> {
    let _ = Command::new("bluetoothctl").args(["connect", mac]).status();
    Ok(())
}

/// Wi‑Fi radio on/off via NetworkManager.
pub fn wifi_radio_enabled() -> bool {
    Command::new("nmcli")
        .args(["-t", "-f", "WIFI", "radio"])
        .output()
        .ok()
        .map(|o| {
            String::from_utf8_lossy(&o.stdout)
                .trim()
                .eq_ignore_ascii_case("enabled")
        })
        .unwrap_or(true)
}

pub fn wifi_radio_set(on: bool) -> Result<(), String> {
    sh_ok("nmcli", &["radio", "wifi", if on { "on" } else { "off" }])
}

pub fn wifi_radio_toggle() -> Result<bool, String> {
    let next = !wifi_radio_enabled();
    wifi_radio_set(next)?;
    Ok(next)
}

/// Bluetooth powered state (bluez).
pub fn bt_radio_enabled() -> bool {
    Command::new("bluetoothctl")
        .args(["show"])
        .output()
        .ok()
        .map(|o| {
            String::from_utf8_lossy(&o.stdout)
                .lines()
                .any(|l| l.contains("Powered: yes"))
        })
        .unwrap_or(false)
}

pub fn bt_radio_set(on: bool) -> Result<(), String> {
    sh_ok("bluetoothctl", &["power", if on { "on" } else { "off" }])
}

pub fn bt_radio_toggle() -> Result<bool, String> {
    let next = !bt_radio_enabled();
    bt_radio_set(next)?;
    Ok(next)
}
