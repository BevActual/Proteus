//! Permissions store reader — twin of `Permissions.qml` for gating.
//!
//! Fact: `~/.config/proteus/permissions.json` (written by
//! `proteus-permissions.py`). Session Allow-once lives under
//! `$XDG_RUNTIME_DIR/proteus/permissions-session.json`. Fail-closed until
//! the store parses.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use serde_json::Value;

pub const CATEGORY_IDS: &[&str] = &[
    "microphone",
    "camera",
    "location",
    "notifications",
    "screen",
    "diagnostics",
];

pub fn category_label(cat: &str) -> &'static str {
    match cat {
        "microphone" => "Microphone",
        "camera" => "Camera",
        "location" => "Location",
        "notifications" => "Notifications",
        "screen" => "Screen recording",
        "diagnostics" => "Diagnostics",
        _ => "Permission",
    }
}

pub fn privacy_pane_for(cat: &str) -> String {
    if CATEGORY_IDS.contains(&cat) {
        format!("privacy-{cat}")
    } else {
        "privacy".into()
    }
}

#[derive(Debug, Clone, Default)]
pub struct PermissionsStore {
    pub ready: bool,
    pub categories: BTreeMap<String, String>,
    pub apps: BTreeMap<String, BTreeMap<String, String>>,
    pub session_allow: BTreeMap<String, bool>,
}

impl PermissionsStore {
    pub fn empty_ready() -> Self {
        let mut categories = BTreeMap::new();
        for id in CATEGORY_IDS {
            categories.insert((*id).to_string(), "allow".into());
        }
        Self {
            ready: true,
            categories,
            apps: BTreeMap::new(),
            session_allow: BTreeMap::new(),
        }
    }

    pub fn parse(text: &str) -> Self {
        let Ok(v) = serde_json::from_str::<Value>(text) else {
            return Self::default();
        };
        let mut categories = BTreeMap::new();
        if let Some(obj) = v.get("categories").and_then(|c| c.as_object()) {
            for (k, val) in obj {
                if let Some(s) = val.as_str() {
                    categories.insert(k.clone(), s.to_string());
                }
            }
        }
        for id in CATEGORY_IDS {
            categories
                .entry((*id).to_string())
                .or_insert_with(|| "allow".into());
        }
        let mut apps = BTreeMap::new();
        if let Some(obj) = v.get("apps").and_then(|a| a.as_object()) {
            for (aid, row) in obj {
                let mut grants = BTreeMap::new();
                if let Some(r) = row.as_object() {
                    for (cat, val) in r {
                        if let Some(s) = val.as_str() {
                            grants.insert(cat.clone(), s.to_string());
                        }
                    }
                }
                apps.insert(normalize_app_id(aid), grants);
            }
        }
        Self {
            ready: true,
            categories,
            apps,
            session_allow: BTreeMap::new(),
        }
    }

    pub fn read(config_base: &Path) -> Self {
        let path = config_base.join("proteus/permissions.json");
        match std::fs::read_to_string(path) {
            Ok(text) => {
                let mut store = Self::parse(&text);
                store.load_session();
                store
            }
            Err(_) => Self::default(),
        }
    }

    fn load_session(&mut self) {
        let path = session_path();
        let Ok(text) = std::fs::read_to_string(path) else {
            return;
        };
        let Ok(v) = serde_json::from_str::<Value>(&text) else {
            return;
        };
        if let Some(obj) = v.as_object() {
            // Dual shape: grants[] + flat "app\tcat": true map.
            if let Some(arr) = obj.get("grants").and_then(|g| g.as_array()) {
                for item in arr {
                    if let Some(k) = item.as_str() {
                        if k.contains('\t') {
                            self.session_allow.insert(k.to_string(), true);
                        }
                    }
                }
            }
            for (k, val) in obj {
                if k == "grants" || !k.contains('\t') {
                    continue;
                }
                if val.as_bool().unwrap_or(false) || val.as_str() == Some("allow") {
                    self.session_allow.insert(k.clone(), true);
                }
            }
        }
    }

    pub fn category_state(&self, cat: &str) -> &str {
        self.categories
            .get(cat)
            .map(String::as_str)
            .filter(|s| *s == "deny" || *s == "ask" || *s == "allow")
            .map(|s| if s == "deny" { "deny" } else if s == "ask" { "ask" } else { "allow" })
            .unwrap_or("allow")
    }

    pub fn app_grant(&self, app_id: &str, cat: &str) -> String {
        let aid = normalize_app_id(app_id);
        if let Some(row) = self.apps.get(&aid) {
            if let Some(g) = row.get(cat) {
                return g.clone();
            }
        }
        self.category_state(cat).to_string()
    }

    pub fn is_ask(&self, app_id: &str, cat: &str) -> bool {
        if !self.ready {
            return false;
        }
        if self.session_allow.contains_key(&session_key(app_id, cat)) {
            return false;
        }
        self.app_grant(app_id, cat) == "ask"
    }

    pub fn granted(&self, app_id: &str, cat: &str) -> bool {
        if !self.ready {
            return false;
        }
        if self.session_allow.contains_key(&session_key(app_id, cat)) {
            return true;
        }
        self.app_grant(app_id, cat) == "allow"
    }

    /// EnvGate.permissionDeniedReason — empty = allowed.
    pub fn denied_reason(&self, app_id: &str, perms: &[String]) -> String {
        if perms.is_empty() {
            return String::new();
        }
        if !self.ready {
            return "Privacy · Permissions loading…".into();
        }
        for cat in perms {
            if cat.is_empty() {
                continue;
            }
            if self.is_ask(app_id, cat) {
                return format!("Privacy · Ask · {}", category_label(cat));
            }
            if !self.granted(app_id, cat) {
                return format!("Blocked by Privacy · {}", category_label(cat));
            }
        }
        String::new()
    }

    /// First Ask category, or "".
    pub fn ask_category(&self, app_id: &str, perms: &[String]) -> String {
        if !self.ready || perms.is_empty() {
            return String::new();
        }
        for cat in perms {
            if !cat.is_empty() && self.is_ask(app_id, cat) {
                return cat.clone();
            }
        }
        String::new()
    }

    /// Pane id for hard Deny (skip Ask), or "" if allowed / only Ask.
    pub fn block_pane(&self, app_id: &str, perms: &[String]) -> String {
        if perms.is_empty() {
            return String::new();
        }
        if !self.ready {
            return "privacy".into();
        }
        for cat in perms {
            if cat.is_empty() {
                continue;
            }
            if self.is_ask(app_id, cat) {
                continue;
            }
            if !self.granted(app_id, cat) {
                return privacy_pane_for(cat);
            }
        }
        String::new()
    }
}

pub fn normalize_app_id(id: &str) -> String {
    let s = id.trim();
    if let Some(stripped) = s.strip_suffix(".desktop") {
        stripped.to_string()
    } else {
        s.to_string()
    }
}

fn session_key(app_id: &str, cat: &str) -> String {
    format!("{}\t{cat}", normalize_app_id(app_id))
}

fn session_path() -> PathBuf {
    if let Ok(rt) = std::env::var("XDG_RUNTIME_DIR") {
        if !rt.trim().is_empty() {
            return PathBuf::from(rt).join("proteus/permissions-session.json");
        }
    }
    let home = std::env::var("HOME").unwrap_or_else(|_| "/".into());
    Path::new(&home).join(".local/state/proteus/permissions-session.json")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fail_closed_until_ready() {
        let store = PermissionsStore::default();
        assert!(!store.ready);
        assert!(!store.granted("cam", "camera"));
        assert_eq!(
            store.denied_reason("cam", &["camera".into()]),
            "Privacy · Permissions loading…"
        );
    }

    #[test]
    fn deny_and_ask() {
        let mut store = PermissionsStore::empty_ready();
        store
            .categories
            .insert("camera".into(), "deny".into());
        assert!(!store.granted("foo", "camera"));
        assert!(store
            .denied_reason("foo", &["camera".into()])
            .contains("Camera"));

        store
            .apps
            .entry("bar".into())
            .or_default()
            .insert("microphone".into(), "ask".into());
        assert!(store.is_ask("bar", "microphone"));
        assert_eq!(store.ask_category("bar", &["microphone".into()]), "microphone");
        assert_eq!(store.block_pane("bar", &["microphone".into()]), "");
    }

    #[test]
    fn parse_store_shape() {
        let store = PermissionsStore::parse(
            r#"{"categories":{"camera":"deny"},"apps":{"cheese":{"camera":"allow"}}}"#,
        );
        assert!(store.ready);
        assert!(store.granted("cheese", "camera"));
        assert!(!store.granted("other", "camera"));
    }
}
