//! Beacon desktop-entry enumeration + launch helpers.

use std::fs;
use std::path::{Path, PathBuf};
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
    filter_beacon_hits(q, limit, &[], BeaconMode::Apps)
}

/// Beacon mode strip (Ctrl+1–4) — filters hit categories.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum BeaconMode {
    #[default]
    Apps = 0,
    Settings = 1,
    Windows = 2,
    Files = 3,
}

impl BeaconMode {
    pub const LABELS: [&'static str; 4] = ["Apps", "Settings", "Windows", "Files"];

    pub fn from_index(i: usize) -> Self {
        match i {
            1 => Self::Settings,
            2 => Self::Windows,
            3 => Self::Files,
            _ => Self::Apps,
        }
    }

    pub fn index(self) -> usize {
        self as usize
    }
}

/// Beacon hits filtered by mode: calc/clipboard/apps · Settings · Windows · files.
pub fn filter_beacon_hits(
    q: &str,
    limit: usize,
    windows: &[crate::wm_ipc::Toplevel],
    mode: BeaconMode,
) -> Vec<String> {
    let raw_q = q.trim();
    let q = raw_q.to_lowercase();
    let mut hits: Vec<String> = Vec::new();
    let want_apps = matches!(mode, BeaconMode::Apps);
    let want_settings = matches!(mode, BeaconMode::Settings);
    let want_windows = matches!(mode, BeaconMode::Windows);
    let want_files = matches!(mode, BeaconMode::Files);

    if want_apps {
        if let Some(label) = calc_hit(raw_q) {
            hits.push(label);
        }
        for label in clipboard_hits(&q, 8) {
            if hits.len() >= limit {
                break;
            }
            if !hits.iter().any(|h| h == &label) {
                hits.push(label);
            }
        }
        for builtin in ["Workloads", "Lock screen"] {
            if hits.len() >= limit {
                break;
            }
            if q.is_empty() || builtin.to_lowercase().contains(&q) {
                hits.push(builtin.into());
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
    }
    if want_settings {
        for builtin in [
            "Settings",
            "Settings · Style",
            "Settings · Sound",
            "Settings · Packages",
        ] {
            if hits.len() >= limit {
                break;
            }
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
    }
    if want_windows {
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
    }
    if want_files {
        for label in file_hits(&q, 8) {
            if hits.len() >= limit {
                break;
            }
            if !hits.iter().any(|h| h == &label) {
                hits.push(label);
            }
        }
    }
    hits.truncate(limit);
    hits
}

/// `cliphist list` → `Clipboard · <list-line>` (Enter: decode | wl-copy).
fn clipboard_hits(q: &str, limit: usize) -> Vec<String> {
    if !command_exists("cliphist") {
        return Vec::new();
    }
    let out = Command::new("cliphist").arg("list").output();
    let Ok(out) = out else {
        return Vec::new();
    };
    if !out.status.success() {
        return Vec::new();
    }
    let text = String::from_utf8_lossy(&out.stdout);
    let mut hits = Vec::new();
    for line in text.lines() {
        if hits.len() >= limit {
            break;
        }
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        // Prefer text-ish rows; skip obvious binary previews when filtering.
        let preview = line.split('\t').nth(1).unwrap_or(line);
        if !q.is_empty()
            && !preview.to_lowercase().contains(q)
            && !line.to_lowercase().contains(q)
            && q != "clip"
            && q != "clipboard"
            && !q.starts_with("clip ")
        {
            continue;
        }
        if q.is_empty()
            || q == "clip"
            || q == "clipboard"
            || q.starts_with("clip ")
            || preview.to_lowercase().contains(q)
            || line.to_lowercase().contains(q)
        {
            let label = format!("Clipboard · {line}");
            if !hits.iter().any(|h| h == &label) {
                hits.push(label);
            }
        }
    }
    hits
}

fn command_exists(name: &str) -> bool {
    Command::new("which")
        .arg(name)
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false)
}

/// Safe arithmetic expression → `Calc · expr = result` (Enter copies result).
fn calc_hit(raw: &str) -> Option<String> {
    let expr = raw.trim();
    if expr.is_empty() || !looks_like_calc(expr) {
        return None;
    }
    let value = eval_calc(expr)?;
    let shown = format_calc_result(value);
    Some(format!("Calc · {expr} = {shown}"))
}

fn looks_like_calc(expr: &str) -> bool {
    let mut has_digit = false;
    let mut has_op = false;
    for c in expr.chars() {
        match c {
            '0'..='9' | '.' => has_digit = true,
            '+' | '-' | '*' | '/' | '%' | '^' | '(' | ')' => has_op = true,
            ' ' | '\t' => {}
            _ => return false,
        }
    }
    has_digit && (has_op || expr.contains('.'))
}

fn format_calc_result(v: f64) -> String {
    if !v.is_finite() {
        return v.to_string();
    }
    if (v - v.round()).abs() < 1e-9 && v.abs() < 1e15 {
        format!("{}", v.round() as i64)
    } else {
        let s = format!("{v:.10}");
        s.trim_end_matches('0').trim_end_matches('.').to_string()
    }
}

/// Tiny recursive-descent calculator: + - * / % ^ and parentheses.
fn eval_calc(expr: &str) -> Option<f64> {
    let chars: Vec<char> = expr.chars().filter(|c| !c.is_whitespace()).collect();
    if chars.is_empty() || chars.len() > 64 {
        return None;
    }
    let mut i = 0usize;
    let v = parse_expr(&chars, &mut i)?;
    if i != chars.len() {
        return None;
    }
    Some(v)
}

fn parse_expr(chars: &[char], i: &mut usize) -> Option<f64> {
    let mut v = parse_term(chars, i)?;
    while *i < chars.len() {
        match chars[*i] {
            '+' => {
                *i += 1;
                v += parse_term(chars, i)?;
            }
            '-' => {
                *i += 1;
                v -= parse_term(chars, i)?;
            }
            _ => break,
        }
    }
    Some(v)
}

fn parse_term(chars: &[char], i: &mut usize) -> Option<f64> {
    let mut v = parse_power(chars, i)?;
    while *i < chars.len() {
        match chars[*i] {
            '*' => {
                *i += 1;
                v *= parse_power(chars, i)?;
            }
            '/' => {
                *i += 1;
                let r = parse_power(chars, i)?;
                if r == 0.0 {
                    return None;
                }
                v /= r;
            }
            '%' => {
                *i += 1;
                let r = parse_power(chars, i)?;
                if r == 0.0 {
                    return None;
                }
                v %= r;
            }
            _ => break,
        }
    }
    Some(v)
}

fn parse_power(chars: &[char], i: &mut usize) -> Option<f64> {
    let base = parse_unary(chars, i)?;
    if *i < chars.len() && chars[*i] == '^' {
        *i += 1;
        let exp = parse_unary(chars, i)?;
        Some(base.powf(exp))
    } else {
        Some(base)
    }
}

fn parse_unary(chars: &[char], i: &mut usize) -> Option<f64> {
    if *i < chars.len() && chars[*i] == '+' {
        *i += 1;
        return parse_unary(chars, i);
    }
    if *i < chars.len() && chars[*i] == '-' {
        *i += 1;
        return Some(-parse_unary(chars, i)?);
    }
    parse_primary(chars, i)
}

fn parse_primary(chars: &[char], i: &mut usize) -> Option<f64> {
    if *i < chars.len() && chars[*i] == '(' {
        *i += 1;
        let v = parse_expr(chars, i)?;
        if *i >= chars.len() || chars[*i] != ')' {
            return None;
        }
        *i += 1;
        return Some(v);
    }
    parse_number(chars, i)
}

fn parse_number(chars: &[char], i: &mut usize) -> Option<f64> {
    let start = *i;
    while *i < chars.len() && (chars[*i].is_ascii_digit() || chars[*i] == '.') {
        *i += 1;
    }
    if start == *i {
        return None;
    }
    let s: String = chars[start..*i].iter().collect();
    s.parse().ok()
}

fn clipboard_list_line(hit: &str) -> Option<&str> {
    hit.strip_prefix("Clipboard · ")
        .or_else(|| {
            let lower = hit.to_lowercase();
            if lower.starts_with("clipboard · ") {
                Some(hit["clipboard · ".len()..].trim())
            } else {
                None
            }
        })
}

fn calc_result_from_hit(hit: &str) -> Option<String> {
    let rest = hit.strip_prefix("Calc · ")?;
    let (_, result) = rest.rsplit_once(" = ")?;
    Some(result.trim().to_string())
}

fn wl_copy_text(text: &str) -> bool {
    let mut child = match Command::new("wl-copy").stdin(std::process::Stdio::piped()).spawn() {
        Ok(c) => c,
        Err(_) => return false,
    };
    if let Some(mut stdin) = child.stdin.take() {
        use std::io::Write;
        let _ = stdin.write_all(text.as_bytes());
    }
    child.wait().map(|s| s.success()).unwrap_or(false)
}

fn paste_clipboard_via_wtype() {
    if !command_exists("wtype") {
        return;
    }
    // Best-effort inject after Beacon closes; ignore failures.
    let _ = Command::new("wtype")
        .args(["-M", "ctrl", "-P", "v", "-m", "ctrl"])
        .spawn();
}

fn file_hits(q: &str, limit: usize) -> Vec<String> {
    if q.is_empty() {
        return file_empty_hits(limit);
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
                        .map(|s| format!("File · {s}"))
                })
                .take(limit)
                .collect()
        })
        .unwrap_or_default()
}

/// Warm the home file index cache (non-blocking — call from a background thread).
pub fn warm_file_index() {
    let Some(bin) = beacon_file_index_bin() else {
        return;
    };
    let _ = Command::new("python3")
        .args([bin.to_string_lossy().as_ref(), "search", "."])
        .output();
}

fn file_empty_hits(limit: usize) -> Vec<String> {
    let mut out = Vec::new();
    if let Some(home) = std::env::var("HOME").ok().map(PathBuf::from) {
        for path in [
            home.clone(),
            home.join("Documents"),
            home.join("Downloads"),
            home.join("Desktop"),
        ] {
            if out.len() >= limit {
                break;
            }
            if path.is_dir() {
                let label = format!("Place · {}", path.display());
                if !out.iter().any(|h| h == &label) {
                    out.push(label);
                }
            }
        }
    }
    for path in file_recents_from_settings().into_iter().take(8) {
        if out.len() >= limit {
            break;
        }
        if Path::new(&path).exists() {
            let label = format!("Recent · {path}");
            if !out.iter().any(|h| h == &label) {
                out.push(label);
            }
        }
    }
    out
}

fn file_recents_from_settings() -> Vec<String> {
    let base = proteus_shell_core::facts::config_base();
    let settings = proteus_shell_core::facts::read_settings(&base);
    let raw = settings
        .get("launcherFileRecents")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    parse_path_list(raw)
}

fn parse_path_list(raw: &str) -> Vec<String> {
    raw.split([',', ';'])
        .map(|s| s.trim())
        .filter(|s| !s.is_empty())
        .map(|s| s.to_string())
        .collect()
}

/// Append a launched file path to `launcherFileRecents` (dedupe, cap 12).
pub fn record_file_recent(path: &str) {
    let path = path.trim();
    if path.is_empty() {
        return;
    }
    let base = proteus_shell_core::facts::config_base();
    let settings = proteus_shell_core::facts::read_settings(&base);
    let raw = settings
        .get("launcherFileRecents")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    let mut paths = parse_path_list(raw);
    paths.retain(|p| p != path);
    paths.insert(0, path.to_string());
    paths.truncate(12);
    let joined = paths.join(",");
    let patch = serde_json::json!({ "launcherFileRecents": joined });
    let _ = proteus_shell_core::facts::write_settings(&base, &patch);
}

fn file_hit_path(hit: &str) -> Option<&str> {
    for prefix in ["File · ", "Place · ", "Recent · "] {
        if let Some(rest) = hit.strip_prefix(prefix) {
            return Some(rest.trim());
        }
    }
    let lower = hit.to_lowercase();
    for prefix in ["file · ", "place · ", "recent · "] {
        if lower.starts_with(prefix) {
            return Some(hit[prefix.len()..].trim());
        }
    }
    None
}

fn beacon_file_index_bin() -> Option<PathBuf> {
    if let Ok(out) = Command::new("which").arg("beacon-file-index.py").output() {
        if out.status.success() {
            let path = String::from_utf8_lossy(&out.stdout).trim().to_string();
            if !path.is_empty() {
                let p = PathBuf::from(&path);
                if p.is_file() {
                    return Some(p);
                }
            }
        }
    }
    if let Ok(path_env) = std::env::var("PATH") {
        for dir in path_env.split(':').filter(|s| !s.is_empty()) {
            let p = PathBuf::from(dir).join("beacon-file-index.py");
            if p.is_file() {
                return Some(p);
            }
        }
    }
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
    if let Some(line) = clipboard_list_line(hit) {
        if command_exists("cliphist") && command_exists("wl-copy") {
            let decode = Command::new("cliphist")
                .arg("decode")
                .stdin(std::process::Stdio::piped())
                .stdout(std::process::Stdio::piped())
                .spawn();
            if let Ok(mut child) = decode {
                if let Some(mut stdin) = child.stdin.take() {
                    use std::io::Write;
                    let _ = writeln!(stdin, "{line}");
                }
                if let Ok(out) = child.wait_with_output() {
                    if out.status.success() {
                        let mut copy = Command::new("wl-copy")
                            .stdin(std::process::Stdio::piped())
                            .spawn();
                        if let Ok(ref mut c) = copy {
                            if let Some(mut stdin) = c.stdin.take() {
                                use std::io::Write;
                                let _ = stdin.write_all(&out.stdout);
                            }
                            let _ = c.wait();
                        }
                        paste_clipboard_via_wtype();
                    }
                }
            }
        }
        return;
    }
    if let Some(result) = calc_result_from_hit(hit) {
        let _ = wl_copy_text(&result);
        return;
    }
    if lower.starts_with("window ·") {
        if let Some(addr) = hit.rsplit(" · ").next() {
            let _ = crate::wm_ipc::focus_window_address(addr.trim());
        }
        return;
    }
    if let Some(path) = file_hit_path(hit) {
        if Command::new("xdg-open").arg(path).spawn().is_ok() {
            record_file_recent(path);
        }
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
        // Single raise via proteus-open (deep link + single-instance).
        let mut cmd = Command::new("proteus-open");
        cmd.arg("settings");
        if let Some(p) = page {
            cmd.arg("--page").arg(p);
        }
        let _ = cmd.spawn();
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
    // Ghostty needs proteus-terminal on VirGL VMs (OpenGL 4.3 path).
    if is_ghostty_desktop_id(id) {
        let _ = Command::new("proteus-terminal").spawn();
        return;
    }
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
        if is_ghostty_desktop_id(&app.id) || app.exec.contains("ghostty") {
            let _ = Command::new("proteus-terminal").spawn();
            return;
        }
        let exec = strip_exec_field_codes(&app.exec);
        let _ = Command::new("bash").args(["-lc", &exec]).spawn();
    }
}

/// Dock / Beacon / gtk-launch ids that should use `proteus-terminal`.
pub fn is_ghostty_desktop_id(id: &str) -> bool {
    let id = id
        .trim()
        .trim_end_matches(".desktop")
        .to_ascii_lowercase();
    id == "com.mitchellh.ghostty" || id == "ghostty" || id.ends_with(".ghostty")
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

    #[test]
    fn ghostty_ids() {
        assert!(is_ghostty_desktop_id("com.mitchellh.ghostty"));
        assert!(is_ghostty_desktop_id("com.mitchellh.ghostty.desktop"));
        assert!(is_ghostty_desktop_id("ghostty"));
        assert!(!is_ghostty_desktop_id("org.gnome.Nautilus"));
    }

    #[test]
    fn parse_path_list_splits_comma_semicolon() {
        assert_eq!(
            parse_path_list("/a,/b;/c , /d"),
            vec!["/a", "/b", "/c", "/d"]
        );
        assert!(parse_path_list("  , ; ").is_empty());
    }

    #[test]
    fn file_hit_path_prefixes() {
        assert_eq!(
            file_hit_path("File · /tmp/x"),
            Some("/tmp/x")
        );
        assert_eq!(
            file_hit_path("Place · /home/u"),
            Some("/home/u")
        );
        assert_eq!(
            file_hit_path("Recent · /home/u/Downloads/a.pdf"),
            Some("/home/u/Downloads/a.pdf")
        );
        assert_eq!(file_hit_path("Settings · Sound"), None);
    }

    #[test]
    fn calc_eval_basic() {
        assert_eq!(eval_calc("2+2"), Some(4.0));
        assert_eq!(eval_calc("10/4"), Some(2.5));
        assert_eq!(eval_calc("(1+2)*3"), Some(9.0));
        assert_eq!(eval_calc("2^3"), Some(8.0));
        assert_eq!(eval_calc("10%3"), Some(1.0));
        assert!(eval_calc("2+").is_none());
        assert!(eval_calc("os.system").is_none());
        assert!(calc_hit("2+2").unwrap().contains("= 4"));
        assert!(calc_hit("hello").is_none());
    }

    #[test]
    fn clipboard_and_calc_hit_parse() {
        assert_eq!(
            clipboard_list_line("Clipboard · 12\thello"),
            Some("12\thello")
        );
        assert_eq!(calc_result_from_hit("Calc · 2+2 = 4"), Some("4".into()));
    }

    #[test]
    fn mode_filters_categories() {
        let settings = filter_beacon_hits("sound", 24, &[], BeaconMode::Settings);
        assert!(
            settings.iter().any(|h| h.contains("Settings")),
            "{settings:?}"
        );
        assert!(
            !settings.iter().any(|h| h.ends_with(".desktop")),
            "apps leaked into Settings: {settings:?}"
        );
        let apps = filter_beacon_hits("2+2", 8, &[], BeaconMode::Apps);
        assert!(
            apps.iter().any(|h| h.starts_with("Calc ·")),
            "{apps:?}"
        );
        let files = filter_beacon_hits("", 8, &[], BeaconMode::Files);
        assert!(
            files
                .iter()
                .all(|h| h.starts_with("File · ")
                    || h.starts_with("Place · ")
                    || h.starts_with("Recent · ")),
            "{files:?}"
        );
        assert_eq!(BeaconMode::from_index(2), BeaconMode::Windows);
        assert_eq!(BeaconMode::Settings.index(), 1);
    }
}
