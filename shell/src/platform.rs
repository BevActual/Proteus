//! Platform services the Quickshell runtime used to provide implicitly.
//!
//! - notifications: org.freedesktop.Notifications (zbus server, dbus-monitor fallback)
//! - tray: StatusNotifierItem host stub
//! - mpris: player listing via D-Bus
//! - upower / logind: power + session inhibit stubs
//! - brightness: backlight sysfs / brightnessctl
//! - audio: pactl / proteus-audio-mix
//! - session lock: layer-overlay default; `PROTEUS_SESSION_LOCK=protocol` uses
//!   iced_sessionlock helper when wired (see engine::activate_session_lock)

use std::io::{BufRead, BufReader, Write};
use std::process::{Command, Stdio};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

use serde::Serialize;

#[derive(Debug, Clone, Default, Serialize)]
pub struct Notification {
    pub id: u32,
    pub app_name: String,
    pub summary: String,
    pub body: String,
}

#[derive(Debug, Default)]
pub struct NotifBus {
    pub next_id: u32,
    pub items: Vec<Notification>,
    pub dnd: bool,
}

pub type SharedNotifs = Arc<Mutex<NotifBus>>;

impl NotifBus {
    pub fn notify(&mut self, app: &str, summary: &str, body: &str) -> u32 {
        if self.dnd {
            return 0;
        }
        self.next_id = self.next_id.saturating_add(1);
        let id = self.next_id;
        self.items.push(Notification {
            id,
            app_name: app.into(),
            summary: summary.into(),
            body: body.into(),
        });
        if self.items.len() > 50 {
            self.items.remove(0);
        }
        id
    }
}

#[derive(Debug, Clone, Default, Serialize)]
pub struct TrayItem {
    pub id: String,
    pub title: String,
    pub icon: String,
}

#[derive(Debug, Default)]
pub struct TrayHost {
    pub items: Vec<TrayItem>,
}

pub type SharedTray = Arc<Mutex<TrayHost>>;

/// List StatusNotifierItem bus names (list-only; no activate menu).
pub fn tray_poll() -> Vec<TrayItem> {
    let out = Command::new("busctl")
        .args(["--user", "list", "--no-legend", "--no-pager"])
        .output();
    let Ok(out) = out else {
        return Vec::new();
    };
    if !out.status.success() {
        return Vec::new();
    }
    let text = String::from_utf8_lossy(&out.stdout);
    let mut items = Vec::new();
    for line in text.lines() {
        let name = line.split_whitespace().next().unwrap_or("");
        if !name.contains("StatusNotifierItem") && !name.contains("statusnotifieritem") {
            continue;
        }
        let title = tray_prop(name, "Title")
            .or_else(|| tray_prop(name, "Id"))
            .unwrap_or_else(|| name.rsplit('.').next().unwrap_or(name).to_string());
        let icon = tray_prop(name, "IconName").unwrap_or_default();
        items.push(TrayItem {
            id: name.to_string(),
            title,
            icon,
        });
        if items.len() >= 12 {
            break;
        }
    }
    items
}

fn tray_prop(dest: &str, prop: &str) -> Option<String> {
    let out = Command::new("busctl")
        .args([
            "--user",
            "get-property",
            dest,
            "/StatusNotifierItem",
            "org.kde.StatusNotifierItem",
            prop,
        ])
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }
    let s = String::from_utf8_lossy(&out.stdout);
    // Format: s "Title"
    let q = s.find('"')?;
    let rest = &s[q + 1..];
    let end = rest.rfind('"')?;
    Some(rest[..end].to_string())
}

/// Background poller for tray list.
pub fn start_tray_watcher() -> SharedTray {
    let host = Arc::new(Mutex::new(TrayHost::default()));
    let h = Arc::clone(&host);
    thread::spawn(move || loop {
        let items = tray_poll();
        if let Ok(mut t) = h.lock() {
            t.items = items;
        }
        thread::sleep(Duration::from_secs(3));
    });
    host
}

#[derive(Debug, Clone, Default, Serialize)]
pub struct MprisPlayer {
    pub name: String,
    pub title: String,
    pub artist: String,
    pub playing: bool,
}

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

fn sh_ok(cmd: &str, args: &[&str]) -> Result<(), String> {
    let status = Command::new(cmd)
        .args(args)
        .status()
        .map_err(|e| format!("{cmd}: {e}"))?;
    if status.success() {
        Ok(())
    } else {
        Err(format!("{cmd} failed"))
    }
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

fn which_like(name: &str) -> Result<std::path::PathBuf, ()> {
    let out = Command::new("which").arg(name).output().map_err(|_| ())?;
    if !out.status.success() {
        return Err(());
    }
    let p = String::from_utf8_lossy(&out.stdout).trim().to_string();
    if p.is_empty() {
        Err(())
    } else {
        Ok(std::path::PathBuf::from(p))
    }
}


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


#[derive(Debug, Clone, Default, Serialize)]
pub struct FocusProfile {
    pub id: String,
    pub name: String,
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

#[derive(Debug, Clone, Default, Serialize)]
pub struct ConsoleGame {
    pub name: String,
    pub source: String,
    /// steam:<appId> or retro:<path>|<core>
    pub launch_key: String,
}


#[derive(Debug, Clone, Default, Serialize)]
pub struct HostGlance {
    pub cpu: String,
    pub mem: String,
    pub storage: String,
    pub net: String,
    pub drives: String,
    pub health: String,
    pub shares: String,
    pub cards: Vec<(String, String)>,
}

pub fn host_glance() -> HostGlance {
    let Some(bin) = host_metrics_bin() else {
        return HostGlance {
            cpu: "—".into(),
            mem: "—".into(),
            storage: "metrics script missing".into(),
            net: "—".into(),
            drives: "—".into(),
            health: "—".into(),
            shares: "—".into(),
            cards: vec![("Metrics".into(), "proteus-host-metrics.py missing".into())],
        };
    };
    let mut cmd = Command::new("python3");
    cmd.arg(&bin);
    if std::env::var("PROTEUS_HOST_METRICS_FIXTURE").ok().as_deref() == Some("1") {
        cmd.env("PROTEUS_HOST_METRICS_FIXTURE", "1");
    }
    let Ok(out) = cmd.output() else {
        return HostGlance::default();
    };
    if !out.status.success() {
        return HostGlance::default();
    }
    let v: serde_json::Value = serde_json::from_slice(&out.stdout).unwrap_or_default();
    let summary = v
        .get("summary")
        .and_then(|x| x.as_str())
        .unwrap_or("host —")
        .to_string();
    let storage = v
        .pointer("/storage/mounts/0")
        .map(|m| {
            format!(
                "{} {}%",
                m.get("target").and_then(|x| x.as_str()).unwrap_or("/"),
                m.get("usedPct").and_then(|x| x.as_u64()).unwrap_or(0)
            )
        })
        .unwrap_or_else(|| "storage —".into());
    let n_drives = v
        .pointer("/storage/drives")
        .and_then(|x| x.as_array())
        .map(|a| a.len())
        .unwrap_or(0);
    let drives = if n_drives == 0 {
        "no drives".into()
    } else {
        format!("{n_drives} drive{}", if n_drives == 1 { "" } else { "s" })
    };
    let net = v
        .pointer("/network/primary")
        .and_then(|x| x.as_str())
        .map(|p| {
            let up = v
                .pointer("/network/interfaces")
                .and_then(|arr| arr.as_array())
                .and_then(|arr| {
                    arr.iter()
                        .find(|i| i.get("name").and_then(|n| n.as_str()) == Some(p))
                })
                .and_then(|i| i.get("up").and_then(|u| u.as_bool()))
                .unwrap_or(false);
            format!("{p} {}", if up { "up" } else { "down" })
        })
        .unwrap_or_else(|| "net —".into());
    let alert = v
        .pointer("/health/alerts/0/message")
        .and_then(|x| x.as_str())
        .unwrap_or("ok")
        .to_string();
    let n_shares = v
        .pointer("/shares/items")
        .and_then(|x| x.as_array())
        .map(|a| a.len())
        .unwrap_or(0);
    let shares = format!("{n_shares} share{}", if n_shares == 1 { "" } else { "s" });
    let cards = vec![
        ("Summary".into(), summary.clone()),
        ("Storage".into(), storage.clone()),
        ("Drives".into(), drives.clone()),
        ("Network".into(), net.clone()),
        ("Health".into(), alert.clone()),
        ("Shares".into(), shares.clone()),
    ];
    HostGlance {
        cpu: summary,
        mem: alert.clone(),
        storage,
        net,
        drives,
        health: alert,
        shares,
        cards,
    }
}

fn host_metrics_bin() -> Option<std::path::PathBuf> {
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
        let p = root.join("shell/scripts/proteus-host-metrics.py");
        if p.is_file() {
            return Some(p);
        }
    }
    None
}

pub fn console_media_path() -> String {
    let base = proteus_shell_core::facts::config_base();
    let settings = proteus_shell_core::facts::read_settings(&base);
    settings
        .get("consoleLastMediaPath")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .trim()
        .to_string()
}

pub fn open_path(path: &str) -> Result<(), String> {
    let path = path.trim();
    if path.is_empty() {
        return Err("empty path".into());
    }
    if which_like("proteus-open").is_ok() {
        Command::new("proteus-open")
            .arg(path)
            .spawn()
            .map_err(|e| e.to_string())?;
        return Ok(());
    }
    Command::new("xdg-open")
        .arg(path)
        .spawn()
        .map_err(|e| e.to_string())?;
    Ok(())
}

/// Recent / sample desktop apps for console Apps tab (Beacon subset).
pub fn console_apps_thin(limit: usize) -> Vec<(String, String)> {
    crate::beacon::list_desktop_apps()
        .into_iter()
        .take(limit)
        .map(|a| (a.name, a.desktop_id))
        .collect()
}

pub fn console_games_list() -> Vec<ConsoleGame> {
    let Some(bin) = console_games_bin() else {
        return Vec::new();
    };
    let mut cmd = Command::new("python3");
    cmd.arg(&bin);
    if std::env::var("PROTEUS_CONSOLE_GAMES_FIXTURE").ok().as_deref() == Some("1") {
        cmd.env("PROTEUS_CONSOLE_GAMES_FIXTURE", "1");
    }
    let Ok(out) = cmd.output() else {
        return Vec::new();
    };
    if !out.status.success() {
        return Vec::new();
    }
    let v: serde_json::Value = serde_json::from_slice(&out.stdout).unwrap_or_default();
    let mut games = Vec::new();
    if let Some(arr) = v
        .pointer("/steam/titles")
        .and_then(|x| x.as_array())
    {
        for t in arr {
            let id = t.get("appId").and_then(|x| x.as_str()).unwrap_or("");
            let name = t.get("name").and_then(|x| x.as_str()).unwrap_or("Steam");
            if id.is_empty() {
                continue;
            }
            games.push(ConsoleGame {
                name: name.into(),
                source: "Steam".into(),
                launch_key: format!("steam:{id}"),
            });
        }
    }
    if let Some(arr) = v
        .pointer("/retroarch/titles")
        .and_then(|x| x.as_array())
    {
        for t in arr {
            let name = t.get("name").and_then(|x| x.as_str()).unwrap_or("ROM");
            let path = t.get("path").and_then(|x| x.as_str()).unwrap_or("");
            let core = t.get("core").and_then(|x| x.as_str()).unwrap_or("");
            if path.is_empty() {
                continue;
            }
            games.push(ConsoleGame {
                name: name.into(),
                source: "RetroArch".into(),
                launch_key: format!("retro:{path}|{core}"),
            });
        }
    }
    games
}

fn console_games_bin() -> Option<std::path::PathBuf> {
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
        let p = root.join("shell/scripts/proteus-console-games.py");
        if p.is_file() {
            return Some(p);
        }
    }
    which_like("proteus-console-games.py").ok()
}

/// Launch a console title via seat helper or direct steam/retroarch.
pub fn console_launch_game(key: &str) -> Result<(), String> {
    let seat = which_like("proteus-console-seat")
        .ok()
        .or_else(|| {
            std::env::var("PROTEUS_ROOT").ok().map(|r| {
                std::path::PathBuf::from(r).join("shell/scripts/proteus-console-seat")
            })
        });
    if let Some(seat) = seat {
        if seat.is_file() || seat.exists() {
            // Prefer direct child argv after -- for seat script
            if let Some(rest) = key.strip_prefix("steam:") {
                let status = Command::new(&seat)
                    .args(["--", "steam", "-applaunch", rest])
                    .status()
                    .map_err(|e| e.to_string())?;
                return if status.success() {
                    Ok(())
                } else {
                    Err("proteus-console-seat steam failed".into())
                };
            }
            if let Some(rest) = key.strip_prefix("retro:") {
                let (path, core) = rest.split_once('|').unwrap_or((rest, ""));
                let mut args: Vec<String> =
                    vec!["--".into(), "retroarch".into()];
                if !core.is_empty() {
                    args.push("-L".into());
                    args.push(core.into());
                }
                args.push(path.into());
                let status = Command::new(&seat)
                    .args(&args)
                    .status()
                    .map_err(|e| e.to_string())?;
                return if status.success() {
                    Ok(())
                } else {
                    Err("proteus-console-seat retroarch failed".into())
                };
            }
        }
    }
    if let Some(rest) = key.strip_prefix("steam:") {
        let _ = Command::new("steam").args(["-applaunch", rest]).spawn();
        return Ok(());
    }
    if let Some(rest) = key.strip_prefix("retro:") {
        let (path, core) = rest.split_once('|').unwrap_or((rest, ""));
        let mut cmd = Command::new("retroarch");
        if !core.is_empty() {
            cmd.args(["-L", core]);
        }
        cmd.arg(path);
        let _ = cmd.spawn();
        return Ok(());
    }
    Err(format!("unknown launch key: {key}"))
}

pub fn mpris_players() -> Vec<MprisPlayer> {
    let out = Command::new("busctl").args(["--user", "list"]).output();
    let Ok(out) = out else {
        return Vec::new();
    };
    let text = String::from_utf8_lossy(&out.stdout);
    text.lines()
        .filter(|l| l.contains("org.mpris.MediaPlayer2."))
        .filter_map(|l| {
            let name = l.split_whitespace().next()?.to_string();
            let (title, artist, playing) = mpris_metadata(&name);
            Some(MprisPlayer {
                name,
                title,
                artist,
                playing,
            })
        })
        .collect()
}

/// Transport command (`PlayPause` / `Next` / `Previous`) to an MPRIS player.
pub fn mpris_control(bus: &str, method: &str) -> Result<(), String> {
    let ok = Command::new("busctl")
        .args([
            "--user",
            "call",
            bus,
            "/org/mpris/MediaPlayer2",
            "org.mpris.MediaPlayer2.Player",
            method,
        ])
        .status()
        .map(|s| s.success())
        .unwrap_or(false);
    if ok {
        Ok(())
    } else {
        Err(format!("mpris {method} failed for {bus}"))
    }
}

fn mpris_metadata(bus: &str) -> (String, String, bool) {
    let meta = Command::new("busctl")
        .args([
            "--user",
            "get-property",
            bus,
            "/org/mpris/MediaPlayer2",
            "org.mpris.MediaPlayer2.Player",
            "Metadata",
        ])
        .output()
        .ok();
    let playing = Command::new("busctl")
        .args([
            "--user",
            "get-property",
            bus,
            "/org/mpris/MediaPlayer2",
            "org.mpris.MediaPlayer2.Player",
            "PlaybackStatus",
        ])
        .output()
        .ok()
        .and_then(|o| {
            let t = String::from_utf8_lossy(&o.stdout);
            Some(t.contains("Playing"))
        })
        .unwrap_or(false);
    let text = meta
        .map(|o| String::from_utf8_lossy(&o.stdout).to_string())
        .unwrap_or_default();
    let title = extract_mpris_str(&text, "xesam:title").unwrap_or_default();
    let artist = extract_mpris_str(&text, "xesam:artist").unwrap_or_default();
    (title, artist, playing)
}

fn extract_mpris_str(blob: &str, key: &str) -> Option<String> {
    let idx = blob.find(key)?;
    let rest = &blob[idx..];
    let q1 = rest.find('"')? + 1;
    let q2 = rest[q1..].find('"')? + q1;
    Some(rest[q1..q2].to_string())
}

pub fn audio_mix_available() -> bool {
    Command::new("sh")
        .args(["-c", "command -v proteus-audio-mix"])
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}


/// Resolved wallpaper for the owned BG layer (QS BgConfig parity, thin).
/// Video / reactive kinds fall back to the image path (honest thin).
#[derive(Debug, Clone, Default, Serialize, PartialEq)]
pub struct WallpaperState {
    /// "image" | "solid" | "daily" (others fall back to image)
    pub kind: String,
    /// Resolved image path when kind wants an image; None → solid fallback.
    pub path: Option<String>,
    /// Solid color `#rrggbb` (also the fallback when image missing).
    pub color: String,
    /// "fill" | "fit" | "stretch" | "center"
    pub mode: String,
}

fn wallpaper_assets_dir() -> std::path::PathBuf {
    let root = std::env::var("PROTEUS_ROOT").unwrap_or_else(|_| "/mnt/proteus".into());
    std::path::Path::new(&root).join("shell/assets")
}

/// Read wallpaper settings from settings.json (same keys as QS `BgConfig.qml`).
pub fn wallpaper_state() -> WallpaperState {
    let base = proteus_shell_core::facts::config_base();
    let s = proteus_shell_core::facts::read_settings(&base);
    let get = |k: &str| s.get(k).and_then(|v| v.as_str()).unwrap_or("").to_string();

    let kind = {
        let k = get("wallpaperKind");
        if k.is_empty() { "image".into() } else { k }
    };
    let color = {
        let c = get("wallpaperColor");
        if c.is_empty() { "#0f1419".into() } else { c }
    };
    let mode = {
        let m = get("wallpaperMode");
        if m.is_empty() { "fill".into() } else { m }
    };
    let id = get("wallpaperId");
    let custom = get("wallpaperCustomPath");
    let daily = get("wallpaperDailyPath");

    if kind == "solid" {
        return WallpaperState { kind, path: None, color, mode };
    }

    let path = if (kind == "daily" || id == "daily") && !daily.is_empty() {
        Some(daily)
    } else if id == "custom" && !custom.is_empty() {
        Some(custom)
    } else {
        let assets = wallpaper_assets_dir();
        let file = match id.as_str() {
            "" | "default" => "wallpaper.jpg".to_string(),
            other => format!("wallpaper-{other}.jpg"),
        };
        let p = assets.join(&file);
        if p.is_file() {
            Some(p.to_string_lossy().into_owned())
        } else {
            let fallback = assets.join("wallpaper.jpg");
            fallback
                .is_file()
                .then(|| fallback.to_string_lossy().into_owned())
        }
    };
    // Missing file → solid fallback rather than a broken image.
    let path = path.filter(|p| std::path::Path::new(p).is_file());
    WallpaperState { kind, path, color, mode }
}

/// Capture a window thumbnail for dock hover previews (ScreencopyView-class,
/// thin). Region capture via grim + hyprctl geometry; PNGs cached under
/// $XDG_RUNTIME_DIR/proteus/previews with a short refresh window.
/// Upgrade path: hyprland-toplevel-export-v1 client later (occlusion-proof).
pub fn dock_preview_capture(address: &str) -> Option<Vec<u8>> {
    let rt = std::env::var("XDG_RUNTIME_DIR").ok()?;
    let dir = std::path::Path::new(&rt).join("proteus/previews");
    std::fs::create_dir_all(&dir).ok()?;
    let file = dir.join(format!("{}.png", address.trim_start_matches("0x")));

    let fresh = file
        .metadata()
        .ok()
        .and_then(|m| m.modified().ok())
        .and_then(|m| m.elapsed().ok())
        .map(|e| e.as_secs() < 3)
        .unwrap_or(false);
    if !fresh {
        let v = crate::wm_ipc::hyprctl_json(&["clients"]).ok()?;
        let c = v
            .as_array()?
            .iter()
            .find(|c| c.get("address").and_then(|a| a.as_str()) == Some(address))?;
        let at = c.get("at")?.as_array()?;
        let size = c.get("size")?.as_array()?;
        let (x, y) = (at.first()?.as_i64()?, at.get(1)?.as_i64()?);
        let (w, h) = (size.first()?.as_i64()?, size.get(1)?.as_i64()?);
        if w <= 0 || h <= 0 {
            return None;
        }
        let geo = format!("{x},{y} {w}x{h}");
        let ok = Command::new("grim")
            .args(["-g", &geo, "-t", "png", "-s", "0.25"])
            .arg(&file)
            .status()
            .ok()?
            .success();
        if !ok {
            return None;
        }
    }
    std::fs::read(&file).ok()
}

#[derive(Debug, Clone, Default, Serialize)]
pub struct PinStatus {
    pub configured: bool,
    pub length: usize,
}

pub fn pin_status() -> PinStatus {
    let Some(script) = find_script("proteus-pin.py") else {
        return PinStatus::default();
    };
    let Ok(out) = Command::new("python3").arg(&script).arg("status").output() else {
        return PinStatus::default();
    };
    if !out.status.success() {
        return PinStatus::default();
    }
    let v: serde_json::Value = serde_json::from_slice(&out.stdout).unwrap_or_default();
    PinStatus {
        configured: v.get("configured").and_then(|x| x.as_bool()).unwrap_or(false),
        length: v.get("length").and_then(|x| x.as_u64()).unwrap_or(0) as usize,
    }
}

/// Progressive cooldown after free attempts (QML LockSurface parity).
pub fn lock_cooldown_secs(fail_count: u32) -> u64 {
    const FREE: u32 = 3;
    if fail_count <= FREE {
        return 0;
    }
    let over = fail_count - FREE;
    match over {
        1 => 5,
        2 => 10,
        3 => 30,
        _ => 60,
    }
}

/// Unlock via check-unlock.py (PAM / PIN). Returns Ok(()) on success.
pub fn try_unlock(secret: &str) -> Result<(), String> {
    let user = std::env::var("USER").unwrap_or_default();
    if user.is_empty() {
        return Err("USER unset".into());
    }
    let script = find_script("check-unlock.py").ok_or("check-unlock.py not found")?;
    let mode = if secret.chars().all(|c| c.is_ascii_digit()) && secret.len() >= 4 && secret.len() <= 8
    {
        "pin"
    } else {
        "password"
    };
    let mut child = Command::new("python3")
        .arg(&script)
        .arg(&user)
        .arg(mode)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| e.to_string())?;
    if let Some(mut stdin) = child.stdin.take() {
        let _ = writeln!(stdin, "{secret}");
    }
    let out = child.wait_with_output().map_err(|e| e.to_string())?;
    if out.status.success() {
        Ok(())
    } else {
        Err("authentication failed".into())
    }
}

fn find_script(name: &str) -> Option<std::path::PathBuf> {
    let mut roots = Vec::new();
    if let Ok(r) = std::env::var("PROTEUS_ROOT") {
        roots.push(std::path::PathBuf::from(r));
    }
    roots.push(std::path::PathBuf::from("/mnt/proteus"));
    if let Ok(h) = std::env::var("HOME") {
        roots.push(std::path::PathBuf::from(h).join("Projects/Proteus"));
    }
    for root in roots {
        let p = root.join("shell/scripts").join(name);
        if p.is_file() {
            return Some(p);
        }
    }
    None
}

/// In-process notification bus + real `org.freedesktop.Notifications` zbus server.
/// Falls back to dbus-monitor feeder if the bus name is already taken.
pub fn start_local_notifd() -> SharedNotifs {
    let bus = Arc::new(Mutex::new(NotifBus::default()));
    {
        let base = proteus_shell_core::facts::config_base();
        let settings = proteus_shell_core::facts::read_settings(&base);
        if let Ok(mut b) = bus.lock() {
            b.dnd = settings
                .get("notificationsDnd")
                .and_then(|v| v.as_bool())
                .unwrap_or(false);
        }
    }

    let bus_srv = Arc::clone(&bus);
    thread::spawn(move || {
        if let Err(e) = run_notifications_server(bus_srv.clone()) {
            eprintln!("proteus-shell: Notifications zbus server: {e} — falling back to dbus-monitor");
            spawn_dbus_monitor_feeder(bus_srv);
        }
    });

    let bus_dnd = Arc::clone(&bus);
    thread::spawn(move || loop {
        thread::sleep(Duration::from_secs(2));
        let base = proteus_shell_core::facts::config_base();
        let settings = proteus_shell_core::facts::read_settings(&base);
        if let Ok(mut b) = bus_dnd.lock() {
            b.dnd = settings
                .get("notificationsDnd")
                .and_then(|v| v.as_bool())
                .unwrap_or(false);
        }
    });
    bus
}

struct NotificationsIface {
    bus: SharedNotifs,
}

#[zbus::interface(name = "org.freedesktop.Notifications")]
impl NotificationsIface {
    fn notify(
        &mut self,
        app_name: &str,
        replaces_id: u32,
        _app_icon: &str,
        summary: &str,
        body: &str,
        _actions: Vec<String>,
        _hints: std::collections::HashMap<String, zvariant::Value<'_>>,
        _expire_timeout: i32,
    ) -> u32 {
        let Ok(mut b) = self.bus.lock() else {
            return 0;
        };
        if b.dnd {
            return 0;
        }
        if replaces_id != 0 {
            if let Some(existing) = b.items.iter_mut().find(|n| n.id == replaces_id) {
                existing.app_name = app_name.into();
                existing.summary = summary.into();
                existing.body = body.into();
                return replaces_id;
            }
        }
        b.notify(app_name, summary, body)
    }

    fn close_notification(&mut self, id: u32) {
        if let Ok(mut b) = self.bus.lock() {
            b.items.retain(|n| n.id != id);
        }
    }

    fn get_capabilities(&self) -> Vec<String> {
        vec![
            "body".into(),
            "body-markup".into(),
            "actions".into(),
            "persistence".into(),
        ]
    }

    fn get_server_information(&self) -> (String, String, String, String) {
        (
            "proteus-shell".into(),
            "Proteus".into(),
            "0.1".into(),
            "1.2".into(),
        )
    }
}

fn run_notifications_server(bus: SharedNotifs) -> Result<(), String> {
    let conn = zbus::blocking::Connection::session().map_err(|e| e.to_string())?;
    conn.object_server()
        .at("/org/freedesktop/Notifications", NotificationsIface { bus })
        .map_err(|e| e.to_string())?;
    conn.request_name("org.freedesktop.Notifications")
        .map_err(|e| e.to_string())?;
    // Keep the connection (and object server) alive.
    loop {
        thread::sleep(Duration::from_secs(3600));
    }
}

fn spawn_dbus_monitor_feeder(bus_mon: SharedNotifs) {
    thread::spawn(move || {
        let child = Command::new("dbus-monitor")
            .args([
                "--session",
                "interface='org.freedesktop.Notifications',member='Notify'",
            ])
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn();
        let Ok(mut child) = child else {
            return;
        };
        let Some(stdout) = child.stdout.take() else {
            return;
        };
        let reader = BufReader::new(stdout);
        let mut app = String::new();
        let mut summary = String::new();
        let mut body = String::new();
        let mut str_idx = 0u8;
        for line in reader.lines().flatten() {
            let t = line.trim();
            if t.starts_with("method call") && t.contains("Notify") {
                app.clear();
                summary.clear();
                body.clear();
                str_idx = 0;
            } else if let Some(rest) = t.strip_prefix("string \"") {
                let s = rest.trim_end_matches('"').to_string();
                match str_idx {
                    0 => app = s,
                    1 => {}
                    2 => summary = s,
                    3 => {
                        body = s;
                        if let Ok(mut b) = bus_mon.lock() {
                            let _ = b.notify(&app, &summary, &body);
                        }
                    }
                    _ => {}
                }
                str_idx = str_idx.saturating_add(1);
            }
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn notif_ids_increment() {
        let mut bus = NotifBus::default();
        let a = bus.notify("test", "hi", "");
        let b = bus.notify("test", "hi2", "");
        assert_eq!(a + 1, b);
    }

    #[test]
    fn dnd_suppresses() {
        let mut bus = NotifBus {
            dnd: true,
            ..Default::default()
        };
        assert_eq!(bus.notify("a", "b", "c"), 0);
    }
}
