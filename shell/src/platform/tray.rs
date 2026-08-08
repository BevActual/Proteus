use std::process::Command;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

use serde::Serialize;

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
