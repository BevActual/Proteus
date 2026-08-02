//! Privileged greetd config helper for Proteus Settings → Users.
//! `show` is unprivileged; `set-autologin` / `clear-autologin` require root (pkexec).
//! Docs: docs/proteus/STACK.md · SETTINGS-IA Users depth

use serde_json::{json, Value};
use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode};

const CONF_PATH: &str = "/etc/greetd/config.toml";
const DEFAULT_CMD: &str = "/usr/local/bin/proteus-session";

fn usage() -> ! {
    eprintln!(
        "Usage: proteus-greetd <show|set-autologin|clear-autologin|smoke> [args…]\n\
         show                         — JSON status (no root)\n\
         set-autologin <user> [cmd]   — write [initial_session] (root / pkexec)\n\
         clear-autologin              — remove [initial_session] (root / pkexec)\n\
         smoke                        — static self-check JSON"
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
    if euid() == Some(0) {
        return;
    }
    // Host smoke: allow non-root writes only when conf is overridden under /tmp.
    let test_ok = env::var("PROTEUS_GREETD_TEST_WRITE")
        .map(|v| v == "1" || v.eq_ignore_ascii_case("true"))
        .unwrap_or(false);
    let conf = conf_path();
    if test_ok && conf.starts_with("/tmp") {
        return;
    }
    eprintln!("proteus-greetd: must run as root (use pkexec)");
    std::process::exit(1);
}

fn print_json(v: &Value) {
    println!(
        "{}",
        serde_json::to_string_pretty(v).unwrap_or_else(|_| "{}".into())
    );
}

fn valid_username(user: &str) -> bool {
    if user.is_empty() || user.len() > 32 {
        return false;
    }
    let mut chars = user.chars();
    let Some(first) = chars.next() else {
        return false;
    };
    if !(first.is_ascii_lowercase() || first == '_') {
        return false;
    }
    for c in chars {
        if !(c.is_ascii_lowercase() || c.is_ascii_digit() || c == '_' || c == '-' || c == '$') {
            return false;
        }
    }
    true
}

fn user_exists(user: &str) -> bool {
    Command::new("getent")
        .args(["passwd", user])
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false)
}

fn valid_command(cmd: &str) -> bool {
    if cmd.is_empty() || cmd.contains('\n') || cmd.contains('\0') {
        return false;
    }
    Path::new(cmd).is_absolute()
}

fn systemctl_state(unit: &str, mode: &str) -> String {
    Command::new("systemctl")
        .args([mode, unit])
        .output()
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .unwrap_or_default()
}

fn parse_initial_session(text: &str) -> (String, String) {
    let mut in_block = false;
    let mut user = String::new();
    let mut command = String::new();
    for line in text.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with('[') {
            in_block = trimmed == "[initial_session]";
            continue;
        }
        if !in_block || trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }
        if let Some(rest) = trimmed.strip_prefix("user") {
            let rest = rest.trim_start();
            if let Some(rest) = rest.strip_prefix('=') {
                let v = rest.trim().trim_matches('"').to_string();
                if !v.is_empty() {
                    user = v;
                }
            }
        } else if let Some(rest) = trimmed.strip_prefix("command") {
            let rest = rest.trim_start();
            if let Some(rest) = rest.strip_prefix('=') {
                let v = rest.trim().trim_matches('"').to_string();
                if !v.is_empty() {
                    command = v;
                }
            }
        }
    }
    (user, command)
}

fn remove_initial_session(text: &str) -> String {
    let mut out = String::new();
    let mut skipping = false;
    for line in text.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with('[') {
            skipping = trimmed == "[initial_session]";
            if skipping {
                continue;
            }
        }
        if skipping {
            continue;
        }
        out.push_str(line);
        out.push('\n');
    }
    // Collapse excessive trailing blanks
    while out.ends_with("\n\n\n") {
        out.pop();
    }
    if !out.ends_with('\n') {
        out.push('\n');
    }
    out
}

fn upsert_initial_session(text: &str, user: &str, command: &str) -> String {
    let base = remove_initial_session(text);
    let block = format!(
        "\n# Cold boot → Proteus session (written by proteus-greetd)\n\
         [initial_session]\n\
         command = \"{command}\"\n\
         user = \"{user}\"\n"
    );
    // Prefer insert before [default_session] when present.
    if let Some(idx) = base.find("[default_session]") {
        let mut out = String::new();
        out.push_str(&base[..idx]);
        if !out.ends_with('\n') {
            out.push('\n');
        }
        out.push_str(block.trim_start());
        if !out.ends_with('\n') {
            out.push('\n');
        }
        out.push_str(&base[idx..]);
        if !out.ends_with('\n') {
            out.push('\n');
        }
        out
    } else {
        let mut out = base;
        if !out.ends_with('\n') {
            out.push('\n');
        }
        out.push_str(block.trim_start());
        out
    }
}

fn default_conf() -> String {
    format!(
        "[terminal]\n\
         vt = 1\n\
         \n\
         [default_session]\n\
         command = \"tuigreet --time --remember --remember-user-session --asterisks --greeting 'Proteus' --sessions /usr/share/wayland-sessions --cmd {DEFAULT_CMD}\"\n\
         user = \"greeter\"\n"
    )
}

fn conf_path() -> PathBuf {
    env::var_os("PROTEUS_GREETD_CONF")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(CONF_PATH))
}

fn write_conf(path: &Path, text: &str) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    let tmp = path.with_extension("toml.proteus-tmp");
    fs::write(&tmp, text).map_err(|e| e.to_string())?;
    fs::rename(&tmp, path).map_err(|e| e.to_string())
}

fn show_json() -> Value {
    let path = conf_path();
    let has_systemctl = Command::new("systemctl")
        .arg("--version")
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false);
    let active = if has_systemctl {
        systemctl_state("greetd", "is-active") == "active"
    } else {
        false
    };
    let enabled_raw = if has_systemctl {
        systemctl_state("greetd", "is-enabled")
    } else {
        String::new()
    };
    let enabled = matches!(
        enabled_raw.as_str(),
        "enabled" | "enabled-runtime" | "static"
    );

    let mut user = String::new();
    let mut command = String::new();
    let hint;
    if path.is_file() {
        let text = fs::read_to_string(&path).unwrap_or_default();
        let (u, c) = parse_initial_session(&text);
        user = u;
        command = c;
        let autologin = !user.is_empty() && !command.is_empty();
        let mut bits = Vec::new();
        if active {
            bits.push("active".into());
        } else if enabled {
            bits.push("enabled".into());
        } else if has_systemctl {
            bits.push("inactive".into());
        }
        if autologin {
            bits.push(format!("autologin {user}"));
        } else {
            bits.push("no initial_session".into());
        }
        hint = bits.join(" · ");
    } else if has_systemctl {
        hint = format!(
            "greetd unit {} · no config.toml",
            if active {
                "active"
            } else if enabled {
                "enabled"
            } else {
                "inactive"
            }
        );
    } else {
        hint = "greetd not installed".into();
    }

    let autologin = !user.is_empty() && !command.is_empty();
    json!({
        "ok": true,
        "active": active,
        "enabled": enabled,
        "autologin": autologin,
        "user": user,
        "command": command,
        "conf": path.display().to_string(),
        "hint": hint,
        "defaultCommand": DEFAULT_CMD,
    })
}

fn set_autologin(user: &str, command: Option<&str>) -> Result<Value, String> {
    require_root();
    if !valid_username(user) {
        return Err(format!("invalid username: {user}"));
    }
    let skip_getent = env::var("PROTEUS_GREETD_TEST_WRITE")
        .map(|v| v == "1" || v.eq_ignore_ascii_case("true"))
        .unwrap_or(false)
        && conf_path().starts_with("/tmp");
    if !skip_getent && !user_exists(user) {
        return Err(format!("user not found: {user}"));
    }
    let cmd = command.unwrap_or(DEFAULT_CMD);
    if !valid_command(cmd) {
        return Err(format!(
            "command must be an absolute path without newlines: {cmd}"
        ));
    }
    let path = conf_path();
    let text = if path.is_file() {
        fs::read_to_string(&path).map_err(|e| e.to_string())?
    } else {
        default_conf()
    };
    let next = upsert_initial_session(&text, user, cmd);
    write_conf(&path, &next)?;
    Ok(json!({
        "ok": true,
        "autologin": true,
        "user": user,
        "command": cmd,
        "conf": path.display().to_string(),
        "hint": "Wrote [initial_session] — applies on next boot / greeter cycle (greetd not restarted)",
    }))
}

fn clear_autologin() -> Result<Value, String> {
    require_root();
    let path = conf_path();
    if !path.is_file() {
        return Err(format!("missing {}", path.display()));
    }
    let text = fs::read_to_string(&path).map_err(|e| e.to_string())?;
    let next = remove_initial_session(&text);
    write_conf(&path, &next)?;
    Ok(json!({
        "ok": true,
        "autologin": false,
        "conf": path.display().to_string(),
        "hint": "Removed [initial_session] — applies on next boot / greeter cycle",
    }))
}

fn smoke_json() -> Value {
    json!({
        "ok": true,
        "confPath": conf_path().display().to_string(),
        "defaultCommand": DEFAULT_CMD,
        "writesInitialSessionOnly": true,
        "restartsGreetd": false,
    })
}

fn main() -> ExitCode {
    let mut args = env::args().skip(1);
    let cmd = match args.next() {
        Some(c) => c,
        None => usage(),
    };

    let result = match cmd.as_str() {
        "show" => Ok(show_json()),
        "smoke" => Ok(smoke_json()),
        "set-autologin" => {
            let user = args.next().unwrap_or_default();
            if user.is_empty() {
                Err("set-autologin requires <user>".into())
            } else {
                let command = args.next();
                set_autologin(&user, command.as_deref())
            }
        }
        "clear-autologin" => clear_autologin(),
        "-h" | "--help" | "help" => usage(),
        other => Err(format!("unknown command: {other}")),
    };

    match result {
        Ok(v) => {
            print_json(&v);
            ExitCode::SUCCESS
        }
        Err(e) => {
            print_json(&json!({ "ok": false, "error": e }));
            ExitCode::from(1)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_and_upsert_roundtrip() {
        let sample = r#"[terminal]
vt = 1

[default_session]
command = "tuigreet"
user = "greeter"
"#;
        let with = upsert_initial_session(sample, "andrew", DEFAULT_CMD);
        assert!(with.contains("[initial_session]"));
        assert!(with.contains("user = \"andrew\""));
        let (u, c) = parse_initial_session(&with);
        assert_eq!(u, "andrew");
        assert_eq!(c, DEFAULT_CMD);
        // default_session preserved after insert
        assert!(with.find("[initial_session]").unwrap() < with.find("[default_session]").unwrap());
        let cleared = remove_initial_session(&with);
        assert!(!cleared.contains("[initial_session]"));
        assert!(cleared.contains("[default_session]"));
    }

    #[test]
    fn username_rules() {
        assert!(valid_username("andrew"));
        assert!(valid_username("_svc"));
        assert!(!valid_username(""));
        assert!(!valid_username("Bad User"));
        assert!(!valid_username("root/../x"));
    }

    #[test]
    fn command_must_be_absolute() {
        assert!(valid_command("/usr/local/bin/proteus-session"));
        assert!(!valid_command("proteus-session"));
        assert!(!valid_command("/bin/sh\nrm -rf /"));
    }
}
