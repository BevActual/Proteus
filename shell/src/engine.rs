//! Session lock + compositor facts. Chrome is owned iced only (Quickshell retired).

use std::env;
use std::path::PathBuf;

/// Chrome engine — owned iced is the only shipping path.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ShellEngine {
    Owned,
}

impl ShellEngine {
    pub fn as_str(self) -> &'static str {
        "owned"
    }

    pub fn parse(_raw: &str) -> Self {
        Self::Owned
    }
}

/// Always Owned — fact/env kept for honesty with existing installs that still
/// write `shell-engine=owned`.
pub fn resolve_engine() -> ShellEngine {
    ShellEngine::Owned
}

pub fn write_engine_fact(engine: ShellEngine) -> Result<(), String> {
    let base = proteus_shell_core::facts::config_base();
    let dir = base.join("proteus");
    std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    std::fs::write(dir.join("shell-engine"), format!("{}\n", engine.as_str()))
        .map_err(|e| e.to_string())
}

/// Resolve compositor engine fact. Hyprland ships; the Smithay rung-2 spike
/// (`compositor-next`, nested winit only) is accepted from an explicit fact/env
/// opt-in — rung 1 gates closed 2026-08-05 per OWNED-STACK.md.
pub fn resolve_compositor_engine() -> &'static str {
    let raw = env::var("PROTEUS_COMPOSITOR_ENGINE").unwrap_or_default();
    let from_env = raw.trim().to_lowercase();
    let from_fact = {
        let base = proteus_shell_core::facts::config_base();
        std::fs::read_to_string(base.join("proteus/compositor-engine"))
            .ok()
            .map(|s| s.trim().to_lowercase())
            .unwrap_or_default()
    };
    let requested = if !from_env.is_empty() {
        from_env
    } else {
        from_fact
    };
    match requested.as_str() {
        "" | "hyprland" | "hypr" => "hyprland",
        "smithay" | "compositor-next" => "smithay",
        other => {
            eprintln!(
                "proteus-shell: compositor-engine={other:?} unknown — using hyprland"
            );
            "hyprland"
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SessionLockMode {
    /// Layer-shell lock surface (shipping default).
    Overlay,
    /// ext-session-lock via iced_sessionlock — spike; falls back if unwired.
    Protocol,
}

impl SessionLockMode {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Overlay => "overlay",
            Self::Protocol => "protocol",
        }
    }

    pub fn parse(raw: &str) -> Self {
        match raw.trim().to_lowercase().as_str() {
            "protocol" | "sessionlock" | "ext-session-lock" | "iced_sessionlock" => Self::Protocol,
            _ => Self::Overlay,
        }
    }
}

/// Resolve lock mode: env `PROTEUS_SESSION_LOCK`, else `~/.config/proteus/session-lock`,
/// else Overlay.
pub fn resolve_session_lock() -> SessionLockMode {
    if let Ok(v) = env::var("PROTEUS_SESSION_LOCK") {
        if !v.trim().is_empty() {
            return SessionLockMode::parse(&v);
        }
    }
    let base = proteus_shell_core::facts::config_base();
    if let Ok(text) = std::fs::read_to_string(base.join("proteus/session-lock")) {
        return SessionLockMode::parse(&text);
    }
    SessionLockMode::Overlay
}

fn session_lock_helper_path() -> Option<PathBuf> {
    for cand in [
        "/usr/local/libexec/proteus/proteus-session-lock",
        "/usr/local/bin/proteus-session-lock",
    ] {
        let p = PathBuf::from(cand);
        if p.is_file() {
            return Some(p);
        }
    }
    if let Ok(root) = env::var("PROTEUS_ROOT") {
        for rel in [
            "target/release/proteus-session-lock",
            "target/debug/proteus-session-lock",
            "shell/target/release/proteus-session-lock",
        ] {
            let p = PathBuf::from(&root).join(rel);
            if p.is_file() {
                return Some(p);
            }
        }
    }
    // Next to this binary / PATH.
    if let Ok(exe) = env::current_exe() {
        if let Some(dir) = exe.parent() {
            let p = dir.join("proteus-session-lock");
            if p.is_file() {
                return Some(p);
            }
        }
    }
    env::var_os("PATH").and_then(|paths| {
        env::split_paths(&paths).find_map(|dir| {
            let p = dir.join("proteus-session-lock");
            p.is_file().then_some(p)
        })
    })
}

/// True when `proteus-session-lock` (iced_sessionlock) is on PATH or next to this binary.
pub fn session_lock_helper_available() -> bool {
    session_lock_helper_path().is_some()
}

/// Alias used by smokes / ctl — same as [`session_lock_helper_path`].
pub fn session_lock_helper() -> Option<PathBuf> {
    session_lock_helper_path()
}

/// Attempt protocol lock; returns the mode actually used + reason if fallback.
pub fn activate_session_lock(requested: SessionLockMode) -> (SessionLockMode, Option<&'static str>) {
    match requested {
        SessionLockMode::Overlay => (SessionLockMode::Overlay, None),
        SessionLockMode::Protocol => {
            if session_lock_helper_available() {
                (SessionLockMode::Protocol, None)
            } else {
                (
                    SessionLockMode::Overlay,
                    Some("proteus-session-lock binary missing"),
                )
            }
        }
    }
}

/// Spawn ext-session-lock helper. Ok(true) if spawned; Ok(false) if unavailable.
pub fn spawn_protocol_lock() -> Result<bool, String> {
    let Some(bin) = session_lock_helper_path() else {
        return Ok(false);
    };
    std::process::Command::new(bin)
        .spawn()
        .map(|_| true)
        .map_err(|e| e.to_string())
}

/// Control socket path — `$XDG_RUNTIME_DIR/proteus/shell.sock`.
pub fn control_socket_path() -> PathBuf {
    let rt = env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| {
        let home = env::var("HOME").unwrap_or_else(|_| "/tmp".into());
        format!("{home}/.local/state")
    });
    PathBuf::from(rt).join("proteus/shell.sock")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn engine_always_owned() {
        assert_eq!(ShellEngine::parse("quickshell"), ShellEngine::Owned);
        assert_eq!(ShellEngine::parse("owned"), ShellEngine::Owned);
        assert_eq!(resolve_engine(), ShellEngine::Owned);
    }

    #[test]
    fn session_lock_parse() {
        assert_eq!(SessionLockMode::parse("overlay"), SessionLockMode::Overlay);
        assert_eq!(
            SessionLockMode::parse("protocol"),
            SessionLockMode::Protocol
        );
    }

    #[test]
    fn control_socket_under_runtime() {
        let p = control_socket_path();
        assert!(p.ends_with("proteus/shell.sock"));
    }
}
