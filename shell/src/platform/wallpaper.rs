use std::process::Command;

use serde::Serialize;

/// Resolved wallpaper for the owned BG layer (QS BgConfig parity, thin).
/// Video / reactive kinds fall back to the image path (honest thin).
#[derive(Debug, Clone, Default, Serialize, PartialEq)]
pub struct WallpaperState {
    /// "image" | "solid" | "daily" (others fall back to image)
    pub kind: String,
    /// Resolved image path when kind wants an image; None → solid fallback.
    pub path: Option<String>,
    /// Solid color `#rrggbb` (also the fallback when image missing).
    pub color: String,
    /// "fill" | "fit" | "stretch" | "center"
    pub mode: String,
}

fn wallpaper_assets_dir() -> std::path::PathBuf {
    let root = std::env::var("PROTEUS_ROOT").unwrap_or_else(|_| "/mnt/proteus".into());
    std::path::Path::new(&root).join("shell/assets")
}

/// Read wallpaper settings from settings.json (same keys as QS `BgConfig.qml`).
pub fn wallpaper_state() -> WallpaperState {
    let base = proteus_shell_core::facts::config_base();
    wallpaper_from_settings(&proteus_shell_core::facts::read_settings(&base))
}

/// Wallpaper from an already-loaded settings object (avoids a second disk read).
pub fn wallpaper_from_settings(s: &serde_json::Value) -> WallpaperState {
    let get = |k: &str| s.get(k).and_then(|v| v.as_str()).unwrap_or("").to_string();

    let kind = {
        let k = get("wallpaperKind");
        if k.is_empty() {
            "image".into()
        } else {
            k
        }
    };
    let color = {
        let c = get("wallpaperColor");
        if c.is_empty() {
            "#0f1419".into()
        } else {
            c
        }
    };
    let mode = {
        let m = get("wallpaperMode");
        if m.is_empty() {
            "fill".into()
        } else {
            m
        }
    };
    let id = get("wallpaperId");
    let custom = get("wallpaperCustomPath");
    let daily = get("wallpaperDailyPath");

    if kind == "solid" {
        return WallpaperState {
            kind,
            path: None,
            color,
            mode,
        };
    }

    let path = if (kind == "daily" || id == "daily") && !daily.is_empty() {
        Some(daily)
    } else if id == "custom" && !custom.is_empty() {
        Some(custom)
    } else {
        let assets = wallpaper_assets_dir();
        let file = match id.as_str() {
            "" | "default" => "wallpaper.jpg".to_string(),
            other => format!("wallpaper-{other}.jpg"),
        };
        let p = assets.join(&file);
        if p.is_file() {
            Some(p.to_string_lossy().into_owned())
        } else {
            let fallback = assets.join("wallpaper.jpg");
            fallback
                .is_file()
                .then(|| fallback.to_string_lossy().into_owned())
        }
    };
    // Missing file → solid fallback rather than a broken image.
    let path = path.filter(|p| std::path::Path::new(p).is_file());
    WallpaperState {
        kind,
        path,
        color,
        mode,
    }
}

/// Capture a window thumbnail for dock hover previews (ScreencopyView-class,
/// thin). Region capture via grim + compositorctl client geometry; PNGs cached
/// under $XDG_RUNTIME_DIR/proteus/previews with a short refresh window.
/// Upgrade path: compositor toplevel-export client later (occlusion-proof).
pub fn dock_preview_capture(address: &str) -> Option<Vec<u8>> {
    let rt = std::env::var("XDG_RUNTIME_DIR").ok()?;
    let dir = std::path::Path::new(&rt).join("proteus/previews");
    std::fs::create_dir_all(&dir).ok()?;
    let file = dir.join(format!("{}.png", address.trim_start_matches("0x")));

    let fresh = file
        .metadata()
        .ok()
        .and_then(|m| m.modified().ok())
        .and_then(|m| m.elapsed().ok())
        .map(|e| e.as_secs() < 3)
        .unwrap_or(false);
    if !fresh {
        let v = crate::wm_ipc::compositorctl_json(&["clients"]).ok()?;
        let c = v
            .as_array()?
            .iter()
            .find(|c| c.get("address").and_then(|a| a.as_str()) == Some(address))?;
        let at = c.get("at")?.as_array()?;
        let size = c.get("size")?.as_array()?;
        let (x, y) = (at.first()?.as_i64()?, at.get(1)?.as_i64()?);
        let (w, h) = (size.first()?.as_i64()?, size.get(1)?.as_i64()?);
        if w <= 0 || h <= 0 {
            return None;
        }
        let geo = format!("{x},{y} {w}x{h}");
        let ok = Command::new("grim")
            .args(["-g", &geo, "-t", "png", "-s", "0.25"])
            .arg(&file)
            .status()
            .ok()?
            .success();
        if !ok {
            return None;
        }
    }
    std::fs::read(&file).ok()
}
