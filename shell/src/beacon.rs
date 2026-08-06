//! Beacon desktop-entry enumeration + launch helpers.

use std::fs;
use std::path::PathBuf;
use std::process::Command;

#[derive(Debug, Clone)]
pub struct DesktopApp {
    pub id: String,
    pub name: String,
    pub exec: String,
    pub desktop_id: String,
    /// `Icon=` value — theme icon name or absolute path (may be empty).
    pub icon: String,
    /// `StartupWMClass=` for window-class ↔ app matching (may be empty).
    pub wm_class: String,
}

fn xdg_data_dirs() -> Vec<PathBuf> {
    let mut dirs = Vec::new();
    if let Ok(home) = std::env::var("HOME") {
        dirs.push(PathBuf::from(home).join(".local/share"));
    }
    if let Ok(xdg) = std::env::var("XDG_DATA_DIRS") {
        for p in xdg.split(':').filter(|s| !s.is_empty()) {
            dirs.push(PathBuf::from(p));
        }
    } else {
        dirs.push(PathBuf::from("/usr/local/share"));
        dirs.push(PathBuf::from("/usr/share"));
    }
    dirs
}

fn parse_desktop(path: &std::path::Path) -> Option<DesktopApp> {
    let text = fs::read_to_string(path).ok()?;
    let mut in_desktop = false;
    let mut name = String::new();
    let mut exec = String::new();
    let mut icon = String::new();
    let mut wm_class = String::new();
    let mut no_display = false;
    let mut hidden = false;
    let mut typ = String::new();
    for line in text.lines() {
        let line = line.trim();
        if line.starts_with('[') {
            in_desktop = line == "[Desktop Entry]";
            continue;
        }
        if !in_desktop {
            continue;
        }
        if let Some(v) = line.strip_prefix("Name=") {
            if name.is_empty() {
                name = v.to_string();
            }
        } else if let Some(v) = line.strip_prefix("Exec=") {
            if exec.is_empty() {
                exec = v.to_string();
            }
        } else if let Some(v) = line.strip_prefix("Icon=") {
            if icon.is_empty() {
                icon = v.to_string();
            }
        } else if let Some(v) = line.strip_prefix("StartupWMClass=") {
            if wm_class.is_empty() {
                wm_class = v.to_string();
            }
        } else if let Some(v) = line.strip_prefix("Type=") {
            typ = v.to_string();
        } else if let Some(v) = line.strip_prefix("NoDisplay=") {
            no_display = v.eq_ignore_ascii_case("true");
        } else if let Some(v) = line.strip_prefix("Hidden=") {
            hidden = v.eq_ignore_ascii_case("true");
        }
    }
    if name.is_empty() || exec.is_empty() || no_display || hidden {
        return None;
    }
    if !typ.is_empty() && !typ.eq_ignore_ascii_case("Application") {
        return None;
    }
    let desktop_id = path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("app.desktop")
        .to_string();
    let id = desktop_id
        .trim_end_matches(".desktop")
        .to_string();
    Some(DesktopApp {
        id,
        name,
        exec,
        desktop_id,
        icon,
        wm_class,
    })
}

/// Enumerate user + system `.desktop` applications (deduped by desktop id).
pub fn list_desktop_apps() -> Vec<DesktopApp> {
    let mut out = Vec::new();
    let mut seen = std::collections::HashSet::new();
    for data in xdg_data_dirs() {
        let apps = data.join("applications");
        let Ok(rd) = fs::read_dir(&apps) else {
            continue;
        };
        for ent in rd.flatten() {
            let path = ent.path();
            if path.extension().and_then(|e| e.to_str()) != Some("desktop") {
                continue;
            }
            let Some(app) = parse_desktop(&path) else {
                continue;
            };
            if seen.insert(app.desktop_id.clone()) {
                out.push(app);
            }
        }
    }
    out.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()));
    out
}

pub fn filter_desktop_hits(q: &str, limit: usize) -> Vec<String> {
    filter_beacon_hits(q, limit, &[])
}

/// Beacon hits: builtins · Settings · Windows · files · desktop apps.
pub fn filter_beacon_hits(q: &str, limit: usize, windows: &[crate::wm_ipc::Toplevel]) -> Vec<String> {
    let q = q.trim().to_lowercase();
    let mut hits: Vec<String> = Vec::new();
    for builtin in [
        "Settings",
        "Workloads",
        "Settings · Style",
        "Settings · Sound",
        "Settings · Packages",
        "Lock screen",
    ] {
        if q.is_empty() || builtin.to_lowercase().contains(&q) {
            hits.push(builtin.into());
        }
    }
    for leaf in settings_catalog_hits(&q) {
        if hits.len() >= limit {
            break;
        }
        if !hits.iter().any(|h| h == &leaf) {
            hits.push(leaf);
        }
    }
    for w in windows {
        if hits.len() >= limit {
            break;
        }
        let title = if w.title.is_empty() {
            w.class.clone()
        } else {
            w.title.clone()
        };
        if title.is_empty() {
            continue;
        }
        if q.is_empty()
            || title.to_lowercase().contains(&q)
            || w.class.to_lowercase().contains(&q)
        {
            let label = format!("Window · {title} · {}", w.address);
            if !hits.iter().any(|h| h == &label) {
                hits.push(label);
            }
        }
    }
    for path in file_hits(&q, 8) {
        if hits.len() >= limit {
            break;
        }
        let label = format!("File · {path}");
        if !hits.iter().any(|h| h == &label) {
            hits.push(label);
        }
    }
    for app in list_desktop_apps() {
        if hits.len() >= limit {
            break;
        }
        if q.is_empty()
            || app.name.to_lowercase().contains(&q)
            || app.id.to_lowercase().contains(&q)
        {
            let label = format!("{} · {}", app.name, app.desktop_id);
            if !hits.iter().any(|h| h == &label) {
                hits.push(label);
            }
        }
    }
    hits.truncate(limit);
    hits
}

fn file_hits(q: &str, limit: usize) -> Vec<String> {
    if q.is_empty() {
        return Vec::new();
    }
    let Some(bin) = beacon_file_index_bin() else {
        return Vec::new();
    };
    let out = Command::new("python3")
        .args([bin.to_string_lossy().as_ref(), "search", q])
        .output();
    let Ok(out) = out else {
        return Vec::new();
    };
    if !out.status.success() {
        return Vec::new();
    }
    let v: serde_json::Value = serde_json::from_slice(&out.stdout).unwrap_or_default();
    v.get("hits")
        .and_then(|h| h.as_array())
        .map(|arr| {
            arr.iter()
                .filter_map(|h| {
                    h.get("path")
                        .and_then(|p| p.as_str())
                        .or_else(|| h.as_str())
                        .map(|s| s.to_string())
                })
                .take(limit)
                .collect()
        })
        .unwrap_or_default()
}

fn beacon_file_index_bin() -> Option<PathBuf> {
    for root in [
        std::env::var("PROTEUS_ROOT").ok().map(PathBuf::from),
        Some(PathBuf::from("/mnt/proteus")),
        std::env::var("HOME")
            .ok()
            .map(|h| PathBuf::from(h).join("Projects/Proteus")),
    ]
    .into_iter()
    .flatten()
    {
        let p = root.join("shell/scripts/beacon-file-index.py");
        if p.is_file() {
            return Some(p);
        }
    }
    None
}

fn settings_catalog_hits(q: &str) -> Vec<String> {
    let mut roots = Vec::new();
    if let Ok(r) = std::env::var("PROTEUS_ROOT") {
        roots.push(PathBuf::from(r));
    }
    roots.push(PathBuf::from("/mnt/proteus"));
    if let Ok(h) = std::env::var("HOME") {
        roots.push(PathBuf::from(h).join("Projects/Proteus"));
    }
    let mut out = Vec::new();
    for root in roots {
        let path = root.join("env/settings/catalog.json");
        let Ok(text) = fs::read_to_string(&path) else {
            continue;
        };
        let Ok(v) = serde_json::from_str::<serde_json::Value>(&text) else {
            continue;
        };
        // hubs[].leaves or panes — catalog shape varies; collect id+label pairs
        if let Some(hubs) = v.get("hubs").and_then(|h| h.as_array()) {
            for hub in hubs {
                let hub_label = hub
                    .get("label")
                    .and_then(|x| x.as_str())
                    .unwrap_or("Settings");
                let hub_id = hub.get("id").and_then(|x| x.as_str()).unwrap_or("");
                if q.is_empty()
                    || hub_label.to_lowercase().contains(q)
                    || hub_id.to_lowercase().contains(q)
                {
                    out.push(format!("Settings · {hub_label} · --page={hub_id}"));
                }
                if let Some(leaves) = hub.get("leaves").and_then(|l| l.as_array()) {
                    for leaf in leaves {
                        let id = leaf.get("id").and_then(|x| x.as_str()).unwrap_or("");
                        let label = leaf
                            .get("label")
                            .and_then(|x| x.as_str())
                            .unwrap_or(id);
                        if id.is_empty() {
                            continue;
                        }
                        if q.is_empty()
                            || label.to_lowercase().contains(q)
                            || id.to_lowercase().contains(q)
                        {
                            out.push(format!("Settings · {label} · --page={id}"));
                        }
                    }
                }
            }
        }
        break;
    }
    out.truncate(16);
    out
}

/// Launch a Beacon hit: proteus-open for Settings/Workloads, gtk-launch / desktop Exec otherwise.
pub fn launch_hit(hit: &str) {
    let lower = hit.to_lowercase();
    if lower.starts_with("window ·") || lower.starts_with("window ·") {
        if let Some(addr) = hit.rsplit(" · ").next() {
            let _ = crate::wm_ipc::focus_window_address(addr.trim());
        }
        return;
    }
    if lower.starts_with("file ·") {
        let path = hit
            .strip_prefix("File · ")
            .or_else(|| hit.strip_prefix("file · "))
            .unwrap_or(hit)
            .trim();
        let _ = Command::new("xdg-open").arg(path).spawn();
        return;
    }
    if lower == "lock screen" || lower.contains("lock screen") {
        let _ = Command::new("proteus-shellctl")
            .args(["lock", "lock"])
            .spawn();
        return;
    }
    if lower.starts_with("settings") || lower.contains("settings ·") {
        // Catalog hits: "Settings · Label · --page=id"
        let page = hit
            .split(" · ")
            .find(|p| p.starts_with("--page="))
            .map(|p| p.trim_start_matches("--page=").to_string())
            .or_else(|| {
                if lower.contains("style") {
                    Some("style-accent".into())
                } else if lower.contains("sound") {
                    Some("sound-output".into())
                } else if lower.contains("package") {
                    Some("packages-updates".into())
                } else {
                    None
                }
            });
        if let Some(p) = page {
            let _ = Command::new("proteus-settings")
                .arg(format!("--page={p}"))
                .spawn();
        }
        let _ = Command::new("proteus-open").arg("settings").spawn();
        return;
    }
    if lower.contains("workload") {
        let _ = Command::new("proteus-open").arg("workloads").spawn();
        return;
    }
    // "Name · id.desktop" or bare desktop id
    let desktop_id = hit
        .rsplit(" · ")
        .next()
        .unwrap_or(hit)
        .trim()
        .to_string();
    let id = desktop_id.trim_end_matches(".desktop");
    if Command::new("gtk-launch").arg(id).spawn().is_ok() {
        return;
    }
    if Command::new("proteus-open").arg(id).spawn().is_ok() {
        return;
    }
    // Last resort: look up Exec from cache
    if let Some(app) = list_desktop_apps()
        .into_iter()
        .find(|a| a.desktop_id == desktop_id || a.id == id)
    {
        let exec = strip_exec_field_codes(&app.exec);
        let _ = Command::new("bash").args(["-lc", &exec]).spawn();
    }
}

fn strip_exec_field_codes(exec: &str) -> String {
    // Remove desktop Exec field codes (%f %u …) for bare launch.
    exec.split_whitespace()
        .filter(|t| !t.starts_with('%'))
        .collect::<Vec<_>>()
        .join(" ")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn strip_codes() {
        assert_eq!(strip_exec_field_codes("foo %u --bar"), "foo --bar");
    }
}
