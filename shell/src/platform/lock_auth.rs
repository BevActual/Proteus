use std::io::Write;
use std::process::{Command, Stdio};

use serde::Serialize;

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
