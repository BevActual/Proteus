//! Library-first facts subscribe API (OWNED-STACK rung 0 serve growth).
//!
//! The CLI `serve` subcommand is a thin NDJSON adapter over
//! [`FactsWatch`]. The iced shell (and any in-process consumer) uses the
//! library directly — no always-on daemon.

use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime};

use serde_json::Value;

use crate::facts::{self, HwProbe};

const WATCHED: &[&str] = &[
    "proteus/posture",
    "proteus/hw-probe.json",
    "proteus/settings.json",
    "proteus/permissions.json",
];

/// Normalized facts snapshot — same schema as the CLI `facts` / `serve` line.
pub fn facts_snapshot(config_base: &Path) -> Value {
    let posture = facts::read_posture(config_base);
    let probe = HwProbe::read(config_base);
    let remote_stub = facts::remote_stub_from_env();
    let settings_raw = std::fs::read_to_string(config_base.join("proteus/settings.json"))
        .ok()
        .and_then(|t| serde_json::from_str::<Value>(&t).ok());
    let (settings_present, settings_problems) = match &settings_raw {
        Some(v) => (true, facts::validate_settings(v)),
        None => (false, Vec::new()),
    };
    let caps: Vec<&str> = probe.capability_list();
    let perms = facts::read_permissions(config_base);
    serde_json::json!({
        "schema": "proteus.shell.facts/v0",
        "posture": posture,
        "deviceClass": probe.device_class,
        "postureHint": probe.posture_hint,
        "probeReady": probe.ready,
        "remoteStub": remote_stub,
        "capabilities": caps,
        "settingsPresent": settings_present,
        "settingsProblems": settings_problems,
        "permissionsPresent": !perms.is_null(),
    })
}

fn mtimes(base: &Path) -> Vec<Option<SystemTime>> {
    WATCHED
        .iter()
        .map(|rel| base.join(rel).metadata().and_then(|m| m.modified()).ok())
        .collect()
}

/// Polling watcher — emits a snapshot on start, then whenever watched fact
/// files change. Call [`FactsWatch::poll`] from a timer / async loop.
pub struct FactsWatch {
    base: PathBuf,
    last: Vec<Option<SystemTime>>,
    started: bool,
}

impl FactsWatch {
    pub fn new(config_base: impl Into<PathBuf>) -> Self {
        let base = config_base.into();
        let last = mtimes(&base);
        Self {
            base,
            last,
            started: false,
        }
    }

    pub fn config_base(&self) -> &Path {
        &self.base
    }

    /// Returns `Some(snapshot)` on first call and whenever facts change.
    pub fn poll(&mut self) -> Option<Value> {
        if !self.started {
            self.started = true;
            self.last = mtimes(&self.base);
            return Some(facts_snapshot(&self.base));
        }
        let now = mtimes(&self.base);
        if now != self.last {
            self.last = now;
            Some(facts_snapshot(&self.base))
        } else {
            None
        }
    }

    /// Blocking NDJSON loop — CLI `serve` adapter. Returns when `emit` returns
    /// false (pipe closed).
    pub fn run_ndjson<F>(&mut self, mut emit: F, interval: Duration)
    where
        F: FnMut(&Value) -> bool,
    {
        loop {
            if let Some(snap) = self.poll() {
                if !emit(&snap) {
                    return;
                }
            }
            std::thread::sleep(interval);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    #[test]
    fn snapshot_schema() {
        let dir = std::env::temp_dir().join(format!(
            "proteus-facts-snap-{}",
            std::process::id()
        ));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(dir.join("proteus")).unwrap();
        fs::write(dir.join("proteus/posture"), "desktop\n").unwrap();
        let v = facts_snapshot(&dir);
        assert_eq!(v["schema"], "proteus.shell.facts/v0");
        assert_eq!(v["posture"], "desktop");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn watch_emits_on_change() {
        let dir = std::env::temp_dir().join(format!(
            "proteus-facts-watch-{}",
            std::process::id()
        ));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(dir.join("proteus")).unwrap();
        fs::write(dir.join("proteus/posture"), "desktop\n").unwrap();
        let mut w = FactsWatch::new(&dir);
        assert!(w.poll().is_some());
        assert!(w.poll().is_none());
        // Ensure mtime advances on coarse filesystems.
        std::thread::sleep(Duration::from_millis(20));
        fs::write(dir.join("proteus/posture"), "host\n").unwrap();
        let snap = w.poll().expect("change");
        assert_eq!(snap["posture"], "host");
        let _ = fs::remove_dir_all(&dir);
    }
}
