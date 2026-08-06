// Typed facts — the on-disk truth every renderer needs (OWNED-STACK rung 0,
// slice 2). Ports the read paths of SessionPosture.qml (posture fact +
// normalization), Hardware.qml (hw-probe cache shape), and Config.qml's
// JsonAdapter (settings.json schema: keys, types, defaults). The QML
// singletons stay the runtime consumers for now; parity is gated by
// shell-core-smoke (schema-keys vs Config.qml) and the fixture tests below.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use serde::Serialize;
use serde_json::Value;

/// XDG config base: $XDG_CONFIG_HOME or ~/.config (SessionPosture.factPath).
pub fn config_base() -> PathBuf {
    if let Ok(xdg) = std::env::var("XDG_CONFIG_HOME") {
        if !xdg.trim().is_empty() {
            return PathBuf::from(xdg);
        }
    }
    let home = std::env::var("HOME").unwrap_or_else(|_| "/".into());
    Path::new(&home).join(".config")
}

// ---------------------------------------------------------------- posture --

/// SessionPosture.normalize: couch/media → console; unknown → desktop.
pub fn normalize_posture(raw: &str) -> &'static str {
    match raw.trim().to_lowercase().as_str() {
        "console" | "couch" | "media" => "console",
        "host" => "host",
        _ => "desktop",
    }
}

/// Read + normalize `<config>/proteus/posture`; missing file = desktop.
pub fn read_posture(config_base: &Path) -> &'static str {
    let path = config_base.join("proteus/posture");
    match std::fs::read_to_string(path) {
        Ok(text) => normalize_posture(&text),
        Err(_) => "desktop",
    }
}

// --------------------------------------------------------------- hw probe --

/// Hardware.qml's parsed view of the Wave A probe report
/// (schema proteus.hw.probe/v0 — dev/fixtures/hw-probe.sample.json).
#[derive(Debug, Default, Serialize)]
pub struct HwProbe {
    pub device_class: String,
    pub posture_hint: String,
    pub chassis: String,
    pub capabilities: BTreeMap<String, bool>,
    pub modules: BTreeMap<String, bool>,
    pub probed_at: String,
    /// False when the cache was missing/unparsable — gating must fail open
    /// exactly like EnvGate before Hardware.ready.
    pub ready: bool,
}

impl HwProbe {
    pub fn parse(text: &str) -> Self {
        let Ok(v) = serde_json::from_str::<Value>(text) else {
            return Self::default();
        };
        let map_of_bool = |v: &Value| -> BTreeMap<String, bool> {
            v.as_object()
                .map(|o| {
                    o.iter()
                        .map(|(k, val)| (k.clone(), val.as_bool().unwrap_or(false)))
                        .collect()
                })
                .unwrap_or_default()
        };
        let s = |key: &str| v[key].as_str().unwrap_or("").to_string();
        HwProbe {
            device_class: s("device_class"),
            posture_hint: {
                let h = s("posture_hint");
                if h.is_empty() {
                    "desktop".into()
                } else {
                    h
                }
            },
            chassis: s("chassis"),
            capabilities: map_of_bool(&v["capabilities"]),
            modules: map_of_bool(&v["modules"]),
            probed_at: s("probed_at"),
            ready: v.is_object(),
        }
    }

    pub fn read(config_base: &Path) -> Self {
        let path = config_base.join("proteus/hw-probe.json");
        match std::fs::read_to_string(path) {
            Ok(text) => Self::parse(&text),
            Err(_) => Self::default(),
        }
    }

    /// Hardware.has(cap) — including the soft remote stub
    /// (PROTEUS_REMOTE_PROBE dogfood; caller resolves the env flag).
    pub fn has(&self, cap: &str, remote_stub: bool) -> bool {
        let c = cap.trim().to_lowercase();
        if c.is_empty() {
            return false;
        }
        if self.capabilities.get(&c).copied().unwrap_or(false) {
            return true;
        }
        c == "remote" && remote_stub
    }

    pub fn capability_list(&self) -> Vec<&str> {
        self.capabilities
            .iter()
            .filter(|(_, on)| **on)
            .map(|(k, _)| k.as_str())
            .collect()
    }
}

pub fn remote_stub_from_env() -> bool {
    matches!(
        std::env::var("PROTEUS_REMOTE_PROBE")
            .unwrap_or_default()
            .trim()
            .to_lowercase()
            .as_str(),
        "1" | "true" | "yes" | "on"
    )
}

// ------------------------------------------------------------ permissions --

/// Raw permissions store (`<config>/proteus/permissions.json`) — shape owned
/// by proteus-permissions.py; exposed untyped until gating needs more.
pub fn read_permissions(config_base: &Path) -> Value {
    let path = config_base.join("proteus/permissions.json");
    std::fs::read_to_string(path)
        .ok()
        .and_then(|t| serde_json::from_str(&t).ok())
        .unwrap_or(Value::Null)
}

// ---------------------------------------------------------------- settings --

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    Int,
    Real,
    Bool,
    Str,
    List,
    Map,
}

/// settings.json schema — one row per Config.qml JsonAdapter property, same
/// order, with the QML default rendered as JSON text. shell-core-smoke pins
/// the key set to Config.qml; the fixture tests pin types against
/// dev/fixtures/settings.minimal.json.
pub const SETTINGS_SCHEMA: &[(&str, Kind, &str)] = &[
    ("gapsIn", Kind::Int, "8"),
    ("gapsOut", Kind::Int, "14"),
    ("borderSize", Kind::Int, "2"),
    ("rounding", Kind::Int, "10"),
    ("animationsEnabled", Kind::Bool, "true"),
    ("dockEnabled", Kind::Bool, "true"),
    ("dockIconSize", Kind::Int, "48"),
    ("dockAutoHide", Kind::Bool, "false"),
    ("dockMonitor", Kind::Str, "\"all\""),
    ("barHeight", Kind::Int, "34"),
    ("barAutoHide", Kind::Bool, "false"),
    ("barMonitor", Kind::Str, "\"all\""),
    ("workspaceMode", Kind::Str, "\"synced\""),
    ("workspaceNames", Kind::List, "[]"),
    ("workspaceOrder", Kind::List, "[]"),
    ("specialWorkspaces", Kind::List, "[]"),
    ("specialWorkspaceChords", Kind::Map, "{}"),
    ("specialWorkspaceMoveChords", Kind::Map, "{}"),
    ("mouseSensitivity", Kind::Real, "0"),
    ("mouseAccelFlat", Kind::Bool, "false"),
    ("inputDeviceOverrides", Kind::List, "[]"),
    ("touchpadNaturalScroll", Kind::Bool, "false"),
    ("touchpadTapToClick", Kind::Bool, "true"),
    ("touchpadDisableWhileTyping", Kind::Bool, "true"),
    ("touchpadClickfinger", Kind::Bool, "false"),
    ("touchpadScrollFactor", Kind::Real, "1.0"),
    ("tabletRelativeInput", Kind::Bool, "false"),
    ("tabletLeftHanded", Kind::Bool, "false"),
    ("tabletOutput", Kind::Str, "\"\""),
    ("tabletTransform", Kind::Int, "0"),
    ("tabletActiveAreaPosX", Kind::Real, "0"),
    ("tabletActiveAreaPosY", Kind::Real, "0"),
    ("tabletActiveAreaSizeX", Kind::Real, "0"),
    ("tabletActiveAreaSizeY", Kind::Real, "0"),
    ("tabletPressureMin", Kind::Real, "-1"),
    ("tabletPressureMax", Kind::Real, "-1"),
    ("tabletEraserButtonMode", Kind::Int, "0"),
    ("tabletEraserButtonOverride", Kind::Int, "0"),
    ("tabletRegionPosX", Kind::Real, "0"),
    ("tabletRegionPosY", Kind::Real, "0"),
    ("tabletRegionSizeX", Kind::Real, "0"),
    ("tabletRegionSizeY", Kind::Real, "0"),
    ("tabletRegionAbsolute", Kind::Bool, "false"),
    ("gamepadsGuideSingle", Kind::Str, "\"nav\""),
    ("gamepadsGuideDouble", Kind::Str, "\"cc\""),
    ("consoleRecents", Kind::List, "[]"),
    ("consoleLastMediaPath", Kind::Str, "\"\""),
    ("audioLatency", Kind::Str, "\"high\""),
    ("locationName", Kind::Str, "\"\""),
    ("locationLatitude", Kind::Real, "0"),
    ("locationLongitude", Kind::Real, "0"),
    ("locationTimezone", Kind::Str, "\"\""),
    ("weatherUnits", Kind::Str, "\"metric\""),
    ("weatherEnabled", Kind::Bool, "true"),
    ("tailscaleLoginServer", Kind::Str, "\"\""),
    ("headscaleAdminUrl", Kind::Str, "\"\""),
    ("accentId", Kind::Str, "\"blue\""),
    ("accentCustom", Kind::Str, "\"#3d8bfd\""),
    ("chromeMode", Kind::Str, "\"dark\""),
    ("chromeOpacity", Kind::Real, "0.28"),
    ("chromeBlur", Kind::Bool, "true"),
    ("lockOnSessionStart", Kind::Bool, "true"),
    ("notificationsDnd", Kind::Bool, "false"),
    ("focusAllowedApps", Kind::List, "[]"),
    ("focusBreakCritical", Kind::Bool, "true"),
    ("focusProfiles", Kind::List, "[]"),
    ("focusActiveProfileId", Kind::Str, "\"work\""),
    ("controlCenterLayout", Kind::Map, "{}"),
    ("lockBackgroundMode", Kind::Str, "\"match\""),
    ("lockWallpaperId", Kind::Str, "\"default\""),
    ("lockWallpaperCustomPath", Kind::Str, "\"\""),
    ("lockWallpaperColor", Kind::Str, "\"#0f1419\""),
    ("lockDailySourceId", Kind::Str, "\"\""),
    ("lockDailyPath", Kind::Str, "\"\""),
    ("lockShowClock", Kind::Bool, "true"),
    ("lockDim", Kind::Real, "0.35"),
    ("lockWallpaperVideoPath", Kind::Str, "\"\""),
    ("lockWallpaperReactiveId", Kind::Str, "\"drift\""),
    ("lockWallpaperMode", Kind::Str, "\"fill\""),
    ("lockWallpaperAlbumId", Kind::Str, "\"\""),
    ("lockWallpaperSlideshow", Kind::Bool, "false"),
    ("lockWallpaperSlideshowSecs", Kind::Int, "60"),
    ("lockWallpaperShuffle", Kind::Bool, "false"),
    ("lockWidgets", Kind::List, "[]"),
    ("desktopWidgets", Kind::List, "[]"),
    ("desktopWidgetsSnapToGrid", Kind::Bool, "false"),
    ("wallpaperKind", Kind::Str, "\"image\""),
    ("wallpaperColor", Kind::Str, "\"#0f1419\""),
    ("wallpaperId", Kind::Str, "\"default\""),
    ("wallpaperCustomPath", Kind::Str, "\"\""),
    ("wallpaperMode", Kind::Str, "\"fill\""),
    ("wallpaperFolder", Kind::Str, "\"\""),
    ("wallpaperAlbumId", Kind::Str, "\"\""),
    ("wallpaperAlbums", Kind::List, "[]"),
    ("wallpaperVideoPath", Kind::Str, "\"\""),
    ("wallpaperReactiveId", Kind::Str, "\"drift\""),
    ("wallpaperSlideshow", Kind::Bool, "false"),
    ("wallpaperSlideshowSecs", Kind::Int, "60"),
    ("wallpaperShuffle", Kind::Bool, "false"),
    ("wallpaperDailyProvider", Kind::Str, "\"bing\""),
    ("wallpaperDailyUrl", Kind::Str, "\"\""),
    ("wallpaperDailyApiKey", Kind::Str, "\"\""),
    ("wallpaperDailyAuth", Kind::Str, "\"none\""),
    ("wallpaperDailyMarket", Kind::Str, "\"en-US\""),
    ("wallpaperDailyRefreshHours", Kind::Int, "6"),
    ("wallpaperDailyPath", Kind::Str, "\"\""),
    ("wallpaperDailyTitle", Kind::Str, "\"\""),
    ("wallpaperDailyCopyright", Kind::Str, "\"\""),
    ("wallpaperDailyFetchedAt", Kind::Str, "\"\""),
    ("wallpaperDailySources", Kind::List, "[]"),
    ("wallpaperDailySourceId", Kind::Str, "\"\""),
    ("fontFamily", Kind::Str, "\"Sans\""),
    ("fontSize", Kind::Int, "13"),
    ("fontSizeSm", Kind::Int, "12"),
    ("userFonts", Kind::Str, "\"\""),
    ("launcherRecents", Kind::Str, "\"\""),
    ("launcherFileRecents", Kind::Str, "\"\""),
    ("launcherTagCatalog", Kind::Str, "\"\""),
    ("launcherAppTags", Kind::Str, "\"\""),
    ("dockPins", Kind::Str, "\"\""),
    ("iconPlateMode", Kind::Str, "\"default\""),
    ("iconPlateCustom", Kind::Str, "\"#5c5c5e\""),
    ("iconOverrides", Kind::Str, "\"\""),
];

pub fn schema_keys() -> Vec<&'static str> {
    let mut keys: Vec<&str> = SETTINGS_SCHEMA.iter().map(|(k, _, _)| *k).collect();
    keys.sort_unstable();
    keys
}

fn kind_ok(kind: Kind, v: &Value) -> bool {
    match kind {
        Kind::Int => v.is_i64() || v.is_u64(),
        Kind::Real => v.is_number(),
        Kind::Bool => v.is_boolean(),
        Kind::Str => v.is_string(),
        Kind::List => v.is_array(),
        Kind::Map => v.is_object(),
    }
}

/// Validate a settings.json object against the schema. Returns problems
/// ("unknown key: x", "type: y expected Int"); empty = valid. Missing keys
/// are fine — QML JsonAdapter fills defaults the same way.
pub fn validate_settings(v: &Value) -> Vec<String> {
    let mut problems = Vec::new();
    let Some(obj) = v.as_object() else {
        return vec!["settings.json must be a JSON object".into()];
    };
    for key in obj.keys() {
        if !SETTINGS_SCHEMA.iter().any(|(k, _, _)| k == key) {
            problems.push(format!("unknown key: {key}"));
        }
    }
    for (key, kind, _) in SETTINGS_SCHEMA {
        if let Some(val) = obj.get(*key) {
            if !kind_ok(*kind, val) {
                problems.push(format!("type: {key} expected {kind:?}"));
            }
        }
    }
    problems
}

/// Materialize a full settings object: schema defaults overlaid with the
/// (valid-typed) keys present in `v` — the Rust twin of JsonAdapter hydration.
pub fn settings_with_defaults(v: &Value) -> Value {
    let mut out = serde_json::Map::new();
    let obj = v.as_object();
    for (key, kind, default) in SETTINGS_SCHEMA {
        let val = obj
            .and_then(|o| o.get(*key))
            .filter(|val| kind_ok(*kind, val))
            .cloned()
            .unwrap_or_else(|| serde_json::from_str(default).expect("schema default parses"));
        out.insert((*key).to_string(), val);
    }
    Value::Object(out)
}

/// Read settings.json (raw object) or empty object if missing.
pub fn read_settings(config_base: &Path) -> Value {
    let path = config_base.join("proteus/settings.json");
    std::fs::read_to_string(path)
        .ok()
        .and_then(|t| serde_json::from_str(&t).ok())
        .unwrap_or_else(|| Value::Object(serde_json::Map::new()))
}

/// Patch + write settings.json. Merges `patch` into the existing file (or
/// defaults), validates types, writes atomically via `.tmp` + rename.
/// Returns the full hydrated object written, or an error string.
///
/// QML Config.qml remains the shipping writer until the owned shell swap;
/// this path is for iced consumers and the CLI `settings-write` probe.
pub fn write_settings(config_base: &Path, patch: &Value) -> Result<Value, String> {
    let Some(patch_obj) = patch.as_object() else {
        return Err("patch must be a JSON object".into());
    };
    let mut current = read_settings(config_base);
    let cur = current
        .as_object_mut()
        .ok_or_else(|| "existing settings.json is not an object".to_string())?;
    for (k, v) in patch_obj {
        cur.insert(k.clone(), v.clone());
    }
    let problems = validate_settings(&current);
    if !problems.is_empty() {
        return Err(format!("validation failed: {}", problems.join("; ")));
    }
    let full = settings_with_defaults(&current);
    let dir = config_base.join("proteus");
    std::fs::create_dir_all(&dir).map_err(|e| format!("mkdir {}: {e}", dir.display()))?;
    let path = dir.join("settings.json");
    let tmp = dir.join("settings.json.tmp");
    let body = serde_json::to_string_pretty(&full).map_err(|e| e.to_string())?;
    std::fs::write(&tmp, format!("{body}\n")).map_err(|e| format!("write temp: {e}"))?;
    std::fs::rename(&tmp, &path).map_err(|e| format!("rename: {e}"))?;
    Ok(full)
}

/// Write posture fact (`desktop` | `console` | `host` after normalize).
pub fn write_posture(config_base: &Path, raw: &str) -> Result<&'static str, String> {
    let posture = normalize_posture(raw);
    let dir = config_base.join("proteus");
    std::fs::create_dir_all(&dir).map_err(|e| format!("mkdir: {e}"))?;
    let path = dir.join("posture");
    std::fs::write(&path, format!("{posture}\n")).map_err(|e| format!("write: {e}"))?;
    Ok(posture)
}

#[cfg(test)]
mod tests {
    use super::*;

    const HW_FIXTURE: &str = include_str!("../../../dev/fixtures/hw-probe.sample.json");
    const SETTINGS_FIXTURE: &str = include_str!("../../../dev/fixtures/settings.minimal.json");

    #[test]
    fn posture_normalization_matches_sessionposture() {
        assert_eq!(normalize_posture("desktop"), "desktop");
        assert_eq!(normalize_posture(" Console\n"), "console");
        assert_eq!(normalize_posture("couch"), "console");
        assert_eq!(normalize_posture("media"), "console");
        assert_eq!(normalize_posture("HOST"), "host");
        assert_eq!(normalize_posture("wearable"), "desktop");
        assert_eq!(normalize_posture(""), "desktop");
    }

    #[test]
    fn hw_probe_fixture_parses() {
        let p = HwProbe::parse(HW_FIXTURE);
        assert!(p.ready);
        assert_eq!(p.device_class, "desktop");
        assert_eq!(p.posture_hint, "desktop");
        assert!(p.has("display", false));
        assert!(p.has("qs_pipewire", false));
        assert!(!p.has("remote", false));
        assert!(p.has("remote", true), "remote stub honored");
        assert!(p.capability_list().contains(&"tiling"));
    }

    #[test]
    fn hw_probe_garbage_fails_open() {
        let p = HwProbe::parse("not json");
        assert!(!p.ready);
        assert!(!p.has("display", false));
    }

    #[test]
    fn settings_fixture_is_schema_valid() {
        let v: Value = serde_json::from_str(SETTINGS_FIXTURE).unwrap();
        let problems = validate_settings(&v);
        assert!(problems.is_empty(), "fixture problems: {problems:?}");
    }

    #[test]
    fn schema_has_all_config_keys_count() {
        assert_eq!(SETTINGS_SCHEMA.len(), 123, "Config.qml JsonAdapter key count");
        // No duplicates.
        let keys = schema_keys();
        let mut dedup = keys.clone();
        dedup.dedup();
        assert_eq!(keys, dedup);
    }

    #[test]
    fn defaults_materialize_every_key() {
        let full = settings_with_defaults(&Value::Null);
        assert_eq!(full.as_object().unwrap().len(), SETTINGS_SCHEMA.len());
        assert_eq!(full["accentId"], "blue");
        assert_eq!(full["chromeOpacity"], 0.28);
        assert_eq!(full["tabletPressureMin"], -1);
        // Overlay wins when typed correctly, ignored when mistyped.
        let v: Value = serde_json::from_str(r#"{"gapsIn": 3, "chromeMode": 7}"#).unwrap();
        let merged = settings_with_defaults(&v);
        assert_eq!(merged["gapsIn"], 3);
        assert_eq!(merged["chromeMode"], "dark");
    }

    #[test]
    fn validate_flags_unknown_and_mistyped() {
        let v: Value = serde_json::from_str(r#"{"nope": 1, "gapsIn": "big"}"#).unwrap();
        let problems = validate_settings(&v);
        assert!(problems.iter().any(|p| p.contains("unknown key: nope")));
        assert!(problems.iter().any(|p| p.contains("gapsIn")));
    }

    #[test]
    fn write_settings_roundtrip() {
        let dir = std::env::temp_dir().join(format!(
            "proteus-settings-write-{}",
            std::process::id()
        ));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(dir.join("proteus")).unwrap();
        let patch = serde_json::json!({"chromeMode": "light"});
        let full = write_settings(&dir, &patch).expect("write");
        assert_eq!(full["chromeMode"], "light");
        let raw = std::fs::read_to_string(dir.join("proteus/settings.json")).unwrap();
        assert!(raw.contains("light"));
        assert_eq!(write_posture(&dir, "couch").unwrap(), "console");
        assert_eq!(read_posture(&dir), "console");
        let _ = std::fs::remove_dir_all(&dir);
    }
}
