//! Privileged logind policy writer for Proteus Settings.
//! Invoked via `pkexec proteus-logind <set|clear|show> …`.
//! Docs: docs/proteus/STACK.md (privileged mutators → Rust)

use std::env;
use std::fs;
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode};

const DROP_IN_DIR: &str = "/etc/systemd/logind.conf.d";
const DROP_IN_PATH: &str = "/etc/systemd/logind.conf.d/99-proteus.conf";
const MAIN_CONF: &str = "/etc/systemd/logind.conf";

const KEYS: &[&str] = &[
    "IdleAction",
    "IdleActionSec",
    "HandleLidSwitch",
    "HandleLidSwitchExternalPower",
];

const ACTION_VALUES: &[&str] = &[
    "ignore",
    "lock",
    "suspend",
    "hibernate",
    "hybrid-sleep",
    "suspend-then-hibernate",
    "poweroff",
];

fn usage() -> ! {
    eprintln!(
        "Usage: proteus-logind <set|unset|clear|show> [args…]\n\
         set   Key=value…  — write /etc/systemd/logind.conf.d/99-proteus.conf + reload logind\n\
         unset Key…        — remove key(s) from the Proteus drop-in (+ reload)\n\
         clear             — remove Proteus drop-in + reload logind\n\
         show              — print effective keys as JSON (main + drop-ins)"
    );
    std::process::exit(2);
}

fn euid() -> Option<u32> {
    let status = fs::read_to_string("/proc/self/status").ok()?;
    for line in status.lines() {
        if let Some(rest) = line.strip_prefix("Uid:") {
            return rest.split_whitespace().nth(1)?.parse().ok();
        }
    }
    None
}

fn require_root() {
    if euid() != Some(0) {
        eprintln!("proteus-logind: must run as root (use pkexec)");
        std::process::exit(1);
    }
}

fn valid_action(value: &str) -> bool {
    ACTION_VALUES.iter().any(|v| *v == value)
}

/// systemd time span: optional number + unit (us|ms|s|min|h|d|w) or bare seconds.
fn valid_timespan(value: &str) -> bool {
    if value.is_empty() {
        return false;
    }
    let bytes = value.as_bytes();
    let mut i = 0;
    while i < bytes.len() && bytes[i].is_ascii_digit() {
        i += 1;
    }
    if i == 0 {
        return false;
    }
    if i == bytes.len() {
        return true; // bare seconds
    }
    matches!(
        &value[i..],
        "us" | "ms" | "s" | "sec" | "min" | "h" | "hr" | "d" | "w"
    )
}

fn parse_assignment(raw: &str) -> Result<(String, String), String> {
    let (k, v) = raw
        .split_once('=')
        .ok_or_else(|| format!("expected Key=value, got {raw:?}"))?;
    let key = k.trim();
    let value = v.trim();
    if !KEYS.iter().any(|k| *k == key) {
        return Err(format!("unsupported key {key:?}"));
    }
    if key == "IdleActionSec" {
        if !valid_timespan(value) {
            return Err(format!("invalid IdleActionSec {value:?}"));
        }
    } else if !valid_action(value) {
        return Err(format!("invalid {key} value {value:?}"));
    }
    Ok((key.to_string(), value.to_string()))
}

fn collect_assignments(args: impl Iterator<Item = String>) -> Result<Vec<(String, String)>, String> {
    let mut out = Vec::new();
    for raw in args {
        out.push(parse_assignment(&raw)?);
    }
    if out.is_empty() {
        return Err("set requires at least one Key=value".into());
    }
    // Last wins per key
    let mut map: Vec<(String, String)> = Vec::new();
    for (k, v) in out {
        if let Some(slot) = map.iter_mut().find(|(ek, _)| *ek == k) {
            slot.1 = v;
        } else {
            map.push((k, v));
        }
    }
    // Stable key order for readable drop-ins
    map.sort_by(|a, b| {
        let ia = KEYS.iter().position(|k| *k == a.0).unwrap_or(99);
        let ib = KEYS.iter().position(|k| *k == b.0).unwrap_or(99);
        ia.cmp(&ib)
    });
    Ok(map)
}

fn write_drop_in(pairs: &[(String, String)]) -> Result<(), String> {
    fs::create_dir_all(DROP_IN_DIR).map_err(|e| format!("mkdir {DROP_IN_DIR}: {e}"))?;
    let mut body = String::from("# Managed by proteus-logind (Proteus Settings → Power)\n[Login]\n");
    for (k, v) in pairs {
        body.push_str(k);
        body.push('=');
        body.push_str(v);
        body.push('\n');
    }
    let path = Path::new(DROP_IN_PATH);
    let tmp = PathBuf::from(format!("{DROP_IN_PATH}.new"));
    fs::write(&tmp, body.as_bytes()).map_err(|e| format!("write {}: {e}", tmp.display()))?;
    fs::rename(&tmp, path).map_err(|e| format!("rename {}: {e}", path.display()))?;
    Ok(())
}

fn clear_drop_in() -> Result<bool, String> {
    let path = Path::new(DROP_IN_PATH);
    if !path.exists() {
        return Ok(false);
    }
    fs::remove_file(path).map_err(|e| format!("remove {}: {e}", path.display()))?;
    Ok(true)
}

/// Apply drop-in changes without tearing down seats / DRM.
/// `systemctl restart systemd-logind` drops the active Wayland seat (black
/// screen / Permission denied DRM). SIGHUP via reload keeps the same PID and
/// updates IdleAction* / HandleLid* immediately (verified on guest).
fn reload_logind() -> Result<(), String> {
    let status = Command::new("systemctl")
        .args(["reload", "systemd-logind.service"])
        .status()
        .map_err(|e| format!("failed to exec systemctl: {e}"))?;
    if status.success() {
        Ok(())
    } else {
        Err(format!(
            "systemctl reload systemd-logind failed (exit {})",
            status.code().unwrap_or(1)
        ))
    }
}

/// Parse Key=value lines from one conf file; commented lines are defaults.
fn parse_conf_file(path: &Path, out: &mut [(String, String, bool)]) {
    let Ok(text) = fs::read_to_string(path) else {
        return;
    };
    for line in text.lines() {
        let s = line.trim();
        if s.is_empty() || !s.contains('=') {
            continue;
        }
        let commented = s.starts_with('#');
        let body = s.trim_start_matches('#').trim();
        let Some((k, v)) = body.split_once('=') else {
            continue;
        };
        let key = k.trim();
        let value = v.trim();
        if let Some(slot) = out.iter_mut().find(|(ek, _, _)| ek == key) {
            // Uncommented always wins over prior; commented only if unset.
            if commented {
                if slot.1.is_empty() {
                    slot.1 = value.to_string();
                    slot.2 = true;
                }
            } else {
                slot.1 = value.to_string();
                slot.2 = false;
            }
        }
    }
}

fn list_drop_ins() -> Vec<PathBuf> {
    let dir = Path::new(DROP_IN_DIR);
    let mut files = Vec::new();
    let Ok(entries) = fs::read_dir(dir) else {
        return files;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.extension().and_then(|e| e.to_str()) == Some("conf") {
            files.push(path);
        }
    }
    files.sort();
    files
}

fn show_effective() -> ExitCode {
    let mut slots: Vec<(String, String, bool)> = KEYS
        .iter()
        .map(|k| ((*k).to_string(), String::new(), true))
        .collect();

    parse_conf_file(Path::new(MAIN_CONF), &mut slots);
    for drop in list_drop_ins() {
        parse_conf_file(&drop, &mut slots);
    }

    // JSON without serde
    print!("{{");
    for (i, (k, v, defaulted)) in slots.iter().enumerate() {
        if i > 0 {
            print!(",");
        }
        let esc_v = v.replace('\\', "\\\\").replace('"', "\\\"");
        print!(
            "\"{k}\":{{\"value\":\"{esc_v}\",\"default\":{}}}",
            if *defaulted { "true" } else { "false" }
        );
    }
    println!("}}");
    let _ = io::stdout().flush();
    ExitCode::SUCCESS
}

fn main() -> ExitCode {
    let mut args = env::args().skip(1);
    let Some(action) = args.next() else {
        usage();
    };

    match action.as_str() {
        "-h" | "--help" | "help" => usage(),
        "show" => {
            // show is read-only — allow non-root for smoke
            return show_effective();
        }
        "set" | "unset" | "clear" => {}
        other => {
            eprintln!("proteus-logind: unknown action {other:?}");
            usage();
        }
    }

    // Validate args before require_root so bad Key=value fails without pkexec.
    let rest: Vec<String> = args.collect();
    let set_pairs = if action == "set" {
        match collect_assignments(rest.clone().into_iter()) {
            Ok(pairs) => Some(pairs),
            Err(e) => {
                eprintln!("proteus-logind: set {e}");
                return ExitCode::from(2);
            }
        }
    } else {
        None
    };
    if action == "unset" {
        if rest.is_empty() {
            eprintln!("proteus-logind: unset requires at least one Key");
            return ExitCode::from(2);
        }
        for key in &rest {
            if !KEYS.iter().any(|k| *k == key.as_str()) {
                eprintln!("proteus-logind: unsupported key {key:?}");
                return ExitCode::from(2);
            }
        }
    }

    require_root();

    match action.as_str() {
        "unset" => {
            let keys = rest;
            if !Path::new(DROP_IN_PATH).exists() {
                println!("proteus-logind: no drop-in to unset");
                let _ = io::stdout().flush();
                return ExitCode::SUCCESS;
            }
            let mut existing: Vec<(String, String, bool)> = KEYS
                .iter()
                .map(|k| ((*k).to_string(), String::new(), true))
                .collect();
            parse_conf_file(Path::new(DROP_IN_PATH), &mut existing);
            let mut kept: Vec<(String, String)> = Vec::new();
            for (k, v, defaulted) in existing {
                if defaulted || v.is_empty() {
                    continue;
                }
                if keys.iter().any(|uk| *uk == k) {
                    continue;
                }
                kept.push((k, v));
            }
            if kept.is_empty() {
                match clear_drop_in() {
                    Ok(_) => {
                        println!("proteus-logind: removed {DROP_IN_PATH}");
                        let _ = io::stdout().flush();
                    }
                    Err(e) => {
                        eprintln!("proteus-logind: {e}");
                        return ExitCode::from(1);
                    }
                }
            } else if let Err(e) = write_drop_in(&kept) {
                eprintln!("proteus-logind: {e}");
                return ExitCode::from(1);
            } else {
                println!("proteus-logind: wrote {DROP_IN_PATH}");
                let _ = io::stdout().flush();
            }
            if let Err(e) = reload_logind() {
                eprintln!("proteus-logind: {e}");
                return ExitCode::from(1);
            }
            println!("proteus-logind: ok");
            let _ = io::stdout().flush();
            ExitCode::SUCCESS
        }
        "set" => {
            let pairs = set_pairs.expect("set_pairs validated");
            // Merge with existing Proteus drop-in so partial sets keep other keys.
            let mut merged = pairs;
            if Path::new(DROP_IN_PATH).exists() {
                let mut existing: Vec<(String, String, bool)> = KEYS
                    .iter()
                    .map(|k| ((*k).to_string(), String::new(), true))
                    .collect();
                parse_conf_file(Path::new(DROP_IN_PATH), &mut existing);
                for (k, v, defaulted) in existing {
                    if defaulted || v.is_empty() {
                        continue;
                    }
                    if !merged.iter().any(|(mk, _)| *mk == k) {
                        merged.push((k, v));
                    }
                }
                merged.sort_by(|a, b| {
                    let ia = KEYS.iter().position(|k| *k == a.0).unwrap_or(99);
                    let ib = KEYS.iter().position(|k| *k == b.0).unwrap_or(99);
                    ia.cmp(&ib)
                });
            }
            if let Err(e) = write_drop_in(&merged) {
                eprintln!("proteus-logind: {e}");
                return ExitCode::from(1);
            }
            println!("proteus-logind: wrote {DROP_IN_PATH}");
            let _ = io::stdout().flush();
            if let Err(e) = reload_logind() {
                eprintln!("proteus-logind: {e}");
                return ExitCode::from(1);
            }
            println!("proteus-logind: ok");
            let _ = io::stdout().flush();
            ExitCode::SUCCESS
        }
        "clear" => match clear_drop_in() {
            Ok(false) => {
                println!("proteus-logind: no drop-in to clear");
                let _ = io::stdout().flush();
                ExitCode::SUCCESS
            }
            Ok(true) => {
                println!("proteus-logind: removed {DROP_IN_PATH}");
                let _ = io::stdout().flush();
                if let Err(e) = reload_logind() {
                    eprintln!("proteus-logind: {e}");
                    return ExitCode::from(1);
                }
                println!("proteus-logind: ok");
                let _ = io::stdout().flush();
                ExitCode::SUCCESS
            }
            Err(e) => {
                eprintln!("proteus-logind: {e}");
                ExitCode::from(1)
            }
        },
        _ => unreachable!(),
    }
}
