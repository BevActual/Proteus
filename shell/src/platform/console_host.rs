use std::process::Command;

use serde::Serialize;

use super::util::which_like;

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
