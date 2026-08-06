//! Icon resolution — freedesktop theme lookup, brand assets, embedded chrome
//! glyphs (QML `DockApps.iconSource` / `SquircleIcon` parity for the owned shell).

use std::collections::HashMap;
use std::path::{Path, PathBuf};

use iced::widget::{image, svg};
use iced::{Color, Element, Length};

/// Resolved icon ready for the renderer.
#[derive(Debug, Clone)]
pub enum IconHandle {
    Svg(svg::Handle),
    Raster(image::Handle),
}

impl IconHandle {
    /// Render at a fixed square size, preserving original colors.
    pub fn view<'a, Message: 'a>(&self, size: f32) -> Element<'a, Message> {
        match self {
            IconHandle::Svg(h) => svg::Svg::new(h.clone())
                .width(Length::Fixed(size))
                .height(Length::Fixed(size))
                .into(),
            IconHandle::Raster(h) => iced::widget::image(h.clone())
                .width(Length::Fixed(size))
                .height(Length::Fixed(size))
                .into(),
        }
    }
}

/// App-icon cache — resolve once per key (pin id, desktop id, window class).
#[derive(Debug, Default)]
pub struct IconCache {
    map: HashMap<String, Option<IconHandle>>,
}

impl IconCache {
    /// Resolve (and memoize) the icon for an app key.
    pub fn ensure(&mut self, key: &str) {
        if !self.map.contains_key(key) {
            let handle = resolve_app_icon(key).and_then(|p| load_handle(&p));
            self.map.insert(key.to_string(), handle);
        }
    }

    /// Cached handle for a key (call [`ensure`] from `update` first).
    pub fn get(&self, key: &str) -> Option<&IconHandle> {
        self.map.get(key).and_then(|o| o.as_ref())
    }
}

fn load_handle(path: &Path) -> Option<IconHandle> {
    match path.extension().and_then(|e| e.to_str()) {
        Some("svg") => Some(IconHandle::Svg(svg::Handle::from_path(path))),
        Some("png") | Some("jpg") | Some("jpeg") | Some("webp") => {
            Some(IconHandle::Raster(image::Handle::from_path(path)))
        }
        _ => None,
    }
}

/// Resolve an app key (pin id, desktop id, or window class) to an icon file.
///
/// Order mirrors the QML chrome: brand assets for first-party ids, then the
/// matching `.desktop` `Icon=`, then the key itself as a theme icon name,
/// then `application-x-executable`.
pub fn resolve_app_icon(key: &str) -> Option<PathBuf> {
    let key_lc = key.trim().trim_end_matches(".desktop").to_lowercase();
    if key_lc.is_empty() {
        return None;
    }

    if let Some(brand) = brand_icon(&key_lc) {
        return Some(brand);
    }

    // Matching .desktop entry → its Icon= (name or absolute path).
    if let Some(icon) = desktop_icon_for(&key_lc) {
        if icon.starts_with('/') {
            let p = PathBuf::from(&icon);
            if p.exists() {
                return Some(p);
            }
        } else if let Some(p) = lookup_theme_icon(&icon) {
            return Some(p);
        }
    }

    // The key itself (and its last dot-segment) as a theme icon name.
    for candidate in [key_lc.as_str(), key_lc.rsplit('.').next().unwrap_or("")] {
        if candidate.is_empty() {
            continue;
        }
        if let Some(p) = lookup_theme_icon(candidate) {
            return Some(p);
        }
    }

    lookup_theme_icon("application-x-executable")
}

/// First-party brand icons under `$PROTEUS_ROOT/brand/`.
fn brand_icon(key_lc: &str) -> Option<PathBuf> {
    let root = std::env::var("PROTEUS_ROOT").unwrap_or_else(|_| "/mnt/proteus".into());
    let brand = PathBuf::from(root).join("brand");
    let file = if key_lc.contains("proteus-settings") || key_lc == "settings" {
        "proteus-settings.svg"
    } else if key_lc.contains("launcher") || key_lc.contains("beacon") {
        "proteus-launcher.svg"
    } else if key_lc.contains("proteus") || key_lc.contains("workloads") {
        "proteus-mark.svg"
    } else {
        return None;
    };
    let p = brand.join(file);
    p.exists().then_some(p)
}

/// `Icon=` from the `.desktop` entry matching the key (id, name, or wm class).
fn desktop_icon_for(key_lc: &str) -> Option<String> {
    for app in crate::beacon::list_desktop_apps() {
        let id_lc = app.id.to_lowercase();
        if id_lc == key_lc
            || app.name.to_lowercase() == key_lc
            || app.wm_class.to_lowercase() == key_lc
            || id_lc.rsplit('.').next() == Some(key_lc)
        {
            if !app.icon.is_empty() {
                return Some(app.icon);
            }
        }
    }
    None
}

/// Freedesktop icon lookup — hicolor + installed themes + pixmaps.
pub fn lookup_theme_icon(name: &str) -> Option<PathBuf> {
    if name.is_empty() {
        return None;
    }
    let mut roots: Vec<PathBuf> = Vec::new();
    if let Ok(home) = std::env::var("HOME") {
        roots.push(PathBuf::from(&home).join(".icons"));
        roots.push(PathBuf::from(&home).join(".local/share/icons"));
    }
    if let Ok(dirs) = std::env::var("XDG_DATA_DIRS") {
        for d in dirs.split(':').filter(|s| !s.is_empty()) {
            roots.push(PathBuf::from(d).join("icons"));
        }
    } else {
        roots.push(PathBuf::from("/usr/local/share/icons"));
        roots.push(PathBuf::from("/usr/share/icons"));
    }

    // hicolor first (spec fallback), then whatever themes are installed.
    for root in &roots {
        if let Some(p) = search_theme_dir(&root.join("hicolor"), name) {
            return Some(p);
        }
    }
    for root in &roots {
        let Ok(rd) = std::fs::read_dir(root) else {
            continue;
        };
        for ent in rd.flatten() {
            let theme = ent.path();
            if !theme.is_dir() || theme.file_name().and_then(|n| n.to_str()) == Some("hicolor") {
                continue;
            }
            if let Some(p) = search_theme_dir(&theme, name) {
                return Some(p);
            }
        }
    }

    // Legacy pixmaps.
    for dir in ["/usr/share/pixmaps", "/usr/local/share/pixmaps"] {
        for ext in ["svg", "png"] {
            let p = PathBuf::from(dir).join(format!("{name}.{ext}"));
            if p.exists() {
                return Some(p);
            }
        }
    }
    None
}

/// Search one theme directory for an icon, preferring scalable then large sizes.
fn search_theme_dir(theme: &Path, name: &str) -> Option<PathBuf> {
    if !theme.is_dir() {
        return None;
    }
    let sized = [
        "scalable/apps",
        "512x512/apps",
        "256x256/apps",
        "128x128/apps",
        "96x96/apps",
        "64x64/apps",
        "48x48/apps",
        // Adwaita-style inverted layout.
        "apps/scalable",
        "apps/512",
        "apps/256",
        "apps/128",
        "apps/64",
        "apps/48",
        "symbolic/apps",
    ];
    for sub in sized {
        for ext in ["svg", "png"] {
            let p = theme.join(sub).join(format!("{name}.{ext}"));
            if p.exists() {
                return Some(p);
            }
        }
    }
    None
}

// ---------------------------------------------------------------- glyphs --

/// Embedded monochrome chrome glyph (24×24 viewBox, white fill — recolor via
/// `svg::Style { color }`). Replaces emoji/ASCII status icons in the chrome.
pub fn chrome_glyph(name: &str) -> svg::Handle {
    let bytes: &'static [u8] = match name {
        "wifi" => GLYPH_WIFI,
        "bluetooth" => GLYPH_BLUETOOTH,
        "volume" => GLYPH_VOLUME,
        "battery" => GLYPH_BATTERY,
        "mic" => GLYPH_MIC,
        "camera" => GLYPH_CAMERA,
        "screen" => GLYPH_SCREEN,
        "cc" => GLYPH_CC,
        "search" => GLYPH_SEARCH,
        "sun" => GLYPH_SUN,
        "moon" => GLYPH_MOON,
        "bell" => GLYPH_BELL,
        "note" => GLYPH_NOTE,
        "play" => GLYPH_PLAY,
        "pause" => GLYPH_PAUSE,
        "prev" => GLYPH_PREV,
        "next" => GLYPH_NEXT,
        "close" => GLYPH_CLOSE,
        "power" => GLYPH_POWER,
        "focus" => GLYPH_FOCUS,
        "calendar" => GLYPH_CALENDAR,
        "backspace" => GLYPH_BACKSPACE,
        _ => GLYPH_DOT,
    };
    svg::Handle::from_memory(bytes)
}

/// Recolorable glyph element at a fixed square size.
pub fn glyph_view<'a, Message: 'a>(name: &str, size: f32, color: Color) -> Element<'a, Message> {
    svg::Svg::new(chrome_glyph(name))
        .width(Length::Fixed(size))
        .height(Length::Fixed(size))
        .style(move |_t, _s| svg::Style { color: Some(color) })
        .into()
}

const GLYPH_WIFI: &[u8] = br##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="#fff" d="M12 20.5a1.7 1.7 0 1 0 0-3.4 1.7 1.7 0 0 0 0 3.4z"/><path fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" d="M8.5 15.2a5.4 5.4 0 0 1 7 0M5.6 12a9.6 9.6 0 0 1 12.8 0M2.8 8.8a13.8 13.8 0 0 1 18.4 0"/></svg>"##;
const GLYPH_BLUETOOTH: &[u8] = br##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" d="M6.5 7.5 17 16.5l-5 4.5V3l5 4.5L6.5 16.5"/></svg>"##;
const GLYPH_VOLUME: &[u8] = br##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="#fff" d="M4 9v6h4l5 4V5L8 9H4z"/><path fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" d="M16 9a4.2 4.2 0 0 1 0 6M18.5 6.5a8 8 0 0 1 0 11"/></svg>"##;
const GLYPH_BATTERY: &[u8] = br##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><rect x="2" y="7" width="17" height="10" rx="2.5" fill="none" stroke="#fff" stroke-width="2"/><rect x="20.5" y="10" width="2" height="4" rx="1" fill="#fff"/><rect x="4.5" y="9.5" width="8" height="5" rx="1" fill="#fff"/></svg>"##;
const GLYPH_MIC: &[u8] = br##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><rect x="9" y="3" width="6" height="11" rx="3" fill="#fff"/><path fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" d="M5.5 11.5a6.5 6.5 0 0 0 13 0M12 18v3"/></svg>"##;
const GLYPH_CAMERA: &[u8] = br##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><rect x="2" y="6" width="14" height="12" rx="2.5" fill="#fff"/><path fill="#fff" d="m17 10 5-3v10l-5-3v-4z"/></svg>"##;
const GLYPH_SCREEN: &[u8] = br##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><rect x="2.5" y="4" width="19" height="13" rx="2" fill="none" stroke="#fff" stroke-width="2"/><path fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" d="M9 20.5h6"/></svg>"##;
const GLYPH_CC: &[u8] = br##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" d="M3 8h18M3 16h18"/><circle cx="9" cy="8" r="3" fill="#fff"/><circle cx="15" cy="16" r="3" fill="#fff"/></svg>"##;
const GLYPH_SEARCH: &[u8] = br##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><circle cx="10.5" cy="10.5" r="6" fill="none" stroke="#fff" stroke-width="2"/><path fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" d="m15.5 15.5 5 5"/></svg>"##;
const GLYPH_SUN: &[u8] = br##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><circle cx="12" cy="12" r="4.5" fill="#fff"/><path fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" d="M12 2.5v2.4M12 19.1v2.4M2.5 12h2.4M19.1 12h2.4M5 5l1.7 1.7M17.3 17.3 19 19M19 5l-1.7 1.7M6.7 17.3 5 19"/></svg>"##;
const GLYPH_MOON: &[u8] = br##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="#fff" d="M20 14.5A8.5 8.5 0 0 1 9.5 4a8.5 8.5 0 1 0 10.5 10.5z"/></svg>"##;
const GLYPH_BELL: &[u8] = br##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="#fff" d="M12 3a6 6 0 0 0-6 6v4l-1.8 3.2a.8.8 0 0 0 .7 1.3h14.2a.8.8 0 0 0 .7-1.3L18 13V9a6 6 0 0 0-6-6z"/><path fill="#fff" d="M9.8 19.5a2.3 2.3 0 0 0 4.4 0z"/></svg>"##;
const GLYPH_NOTE: &[u8] = br##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="#fff" d="M9 3v11.3a3.3 3.3 0 1 0 2 3V7h8V3H9z"/></svg>"##;
const GLYPH_PLAY: &[u8] = br##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="#fff" d="M7 4.5v15l12-7.5-12-7.5z"/></svg>"##;
const GLYPH_PAUSE: &[u8] = br##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><rect x="6" y="4.5" width="4" height="15" rx="1" fill="#fff"/><rect x="14" y="4.5" width="4" height="15" rx="1" fill="#fff"/></svg>"##;
const GLYPH_PREV: &[u8] = br##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="#fff" d="M18 4.5v15l-9-7.5 9-7.5z"/><rect x="5" y="4.5" width="2.5" height="15" rx="1" fill="#fff"/></svg>"##;
const GLYPH_NEXT: &[u8] = br##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="#fff" d="M6 4.5v15l9-7.5-9-7.5z"/><rect x="16.5" y="4.5" width="2.5" height="15" rx="1" fill="#fff"/></svg>"##;
const GLYPH_CLOSE: &[u8] = br##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="none" stroke="#fff" stroke-width="2.4" stroke-linecap="round" d="M6 6l12 12M18 6 6 18"/></svg>"##;
const GLYPH_POWER: &[u8] = br##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" d="M12 3v8M6.2 6.5a8 8 0 1 0 11.6 0"/></svg>"##;
const GLYPH_FOCUS: &[u8] = br##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><circle cx="12" cy="12" r="8.5" fill="none" stroke="#fff" stroke-width="2"/><circle cx="12" cy="12" r="3.5" fill="#fff"/></svg>"##;
const GLYPH_CALENDAR: &[u8] = br##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><rect x="3" y="5" width="18" height="16" rx="2.5" fill="none" stroke="#fff" stroke-width="2"/><path fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" d="M3 9.5h18M8 2.8v4M16 2.8v4"/></svg>"##;
const GLYPH_BACKSPACE: &[u8] = br##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="none" stroke="#fff" stroke-width="2" stroke-linejoin="round" d="M8.5 5h11A1.5 1.5 0 0 1 21 6.5v11a1.5 1.5 0 0 1-1.5 1.5h-11L3 12l5.5-7z"/><path fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" d="m11 9.5 5 5M16 9.5l-5 5"/></svg>"##;
const GLYPH_DOT: &[u8] = br##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><circle cx="12" cy="12" r="4" fill="#fff"/></svg>"##;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn glyphs_parse_as_svg_bytes() {
        for name in [
            "wifi",
            "bluetooth",
            "volume",
            "battery",
            "mic",
            "camera",
            "screen",
            "cc",
            "search",
            "sun",
            "moon",
            "bell",
            "note",
            "play",
            "pause",
            "prev",
            "next",
            "close",
            "power",
            "focus",
            "calendar",
            "backspace",
            "unknown-falls-back",
        ] {
            let _ = chrome_glyph(name);
        }
        assert!(std::str::from_utf8(GLYPH_WIFI).unwrap().starts_with("<svg"));
    }

    #[test]
    fn icon_cache_memoizes_misses() {
        let mut cache = IconCache::default();
        cache.ensure("definitely-not-a-real-app-xyz");
        // Second ensure hits the memo (no re-resolution, entry persists).
        cache.ensure("definitely-not-a-real-app-xyz");
        assert!(cache.map.contains_key("definitely-not-a-real-app-xyz"));
    }

    #[test]
    fn brand_icon_matches_first_party_keys() {
        // Path existence depends on PROTEUS_ROOT; only exercise the matcher.
        let _ = brand_icon("proteus-settings");
        let _ = brand_icon("org.mozilla.firefox");
    }
}
