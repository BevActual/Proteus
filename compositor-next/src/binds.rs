//! Session keybind table — defaults + optional `keybinds.json` Fact overrides.
//!
//! Matching is compositor-owned (global Super chords). Actions:
//! - `Shell` → `proteus-shellctl <target> <method>`
//! - `Dispatch` → wm dispatch verb (in-process)
//! - `Exec` → spawn argv (PATH / best-effort)

use std::path::PathBuf;
use std::process::Command;

use serde_json::Value;
use smithay::input::keyboard::{keysyms, Keysym, ModifiersState};

/// Stable override id (Fact `overrides[].id`).
pub type BindId = String;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BindMods {
    pub logo: bool,
    pub shift: bool,
    pub ctrl: bool,
    pub alt: bool,
}

impl BindMods {
    pub const fn logo_only() -> Self {
        Self {
            logo: true,
            shift: false,
            ctrl: false,
            alt: false,
        }
    }

    pub const fn logo_shift() -> Self {
        Self {
            logo: true,
            shift: true,
            ctrl: false,
            alt: false,
        }
    }

    pub fn matches(&self, m: &ModifiersState) -> bool {
        m.logo == self.logo
            && m.shift == self.shift
            && m.ctrl == self.ctrl
            && m.alt == self.alt
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BindAction {
    Shell { target: String, method: String },
    Dispatch(String),
    Exec(Vec<String>),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BindEntry {
    pub id: BindId,
    pub mods: BindMods,
    pub key: String,
    pub action: BindAction,
}

/// Loaded bind table (defaults merged with Fact overrides).
#[derive(Debug, Clone, Default)]
pub struct BindsState {
    pub entries: Vec<BindEntry>,
}

impl BindsState {
    pub fn load() -> Self {
        let mut entries = default_binds();
        merge_fact_overrides(&mut entries);
        Self { entries }
    }

    pub fn reload(&mut self) {
        *self = Self::load();
        eprintln!(
            "proteus-compositor-next: reloaded keybinds ({} entries)",
            self.entries.len()
        );
    }

    /// Find action for pressed chord (key name lowercase).
    pub fn lookup(&self, mods: &ModifiersState, key: &str) -> Option<&BindAction> {
        let key = normalize_key_name(key);
        self.entries
            .iter()
            .find(|e| e.mods.matches(mods) && normalize_key_name(&e.key) == key)
            .map(|e| &e.action)
    }
}

pub fn keybinds_fact_path() -> PathBuf {
    if let Ok(xdg) = std::env::var("XDG_CONFIG_HOME") {
        if !xdg.is_empty() {
            return PathBuf::from(xdg).join("proteus/keybinds.json");
        }
    }
    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".into());
    PathBuf::from(home).join(".config/proteus/keybinds.json")
}

/// Map xkb Keysym → catalog key name (lowercase).
pub fn keysym_to_name(sym: Keysym) -> Option<&'static str> {
    let ks = |u: u32| -> Keysym { Keysym::from(u) };

    // Digits (raw / shifted layout may still report KEY_1..).
    if sym == ks(keysyms::KEY_0) || sym == ks(keysyms::KEY_KP_0) {
        return Some("0");
    }
    if sym == ks(keysyms::KEY_1) || sym == ks(keysyms::KEY_KP_1) {
        return Some("1");
    }
    if sym == ks(keysyms::KEY_2) || sym == ks(keysyms::KEY_KP_2) {
        return Some("2");
    }
    if sym == ks(keysyms::KEY_3) || sym == ks(keysyms::KEY_KP_3) {
        return Some("3");
    }
    if sym == ks(keysyms::KEY_4) || sym == ks(keysyms::KEY_KP_4) {
        return Some("4");
    }
    if sym == ks(keysyms::KEY_5) || sym == ks(keysyms::KEY_KP_5) {
        return Some("5");
    }
    if sym == ks(keysyms::KEY_6) || sym == ks(keysyms::KEY_KP_6) {
        return Some("6");
    }
    if sym == ks(keysyms::KEY_7) || sym == ks(keysyms::KEY_KP_7) {
        return Some("7");
    }
    if sym == ks(keysyms::KEY_8) || sym == ks(keysyms::KEY_KP_8) {
        return Some("8");
    }
    if sym == ks(keysyms::KEY_9) || sym == ks(keysyms::KEY_KP_9) {
        return Some("9");
    }

    if sym == ks(keysyms::KEY_space) {
        return Some("space");
    }
    if sym == ks(keysyms::KEY_Return) || sym == ks(keysyms::KEY_KP_Enter) {
        return Some("return");
    }
    if sym == ks(keysyms::KEY_comma) {
        return Some("comma");
    }
    if sym == ks(keysyms::KEY_d) || sym == ks(keysyms::KEY_D) {
        return Some("d");
    }
    if sym == ks(keysyms::KEY_l) || sym == ks(keysyms::KEY_L) {
        return Some("l");
    }
    if sym == ks(keysyms::KEY_w) || sym == ks(keysyms::KEY_W) {
        return Some("w");
    }
    if sym == ks(keysyms::KEY_s) || sym == ks(keysyms::KEY_S) {
        return Some("s");
    }
    None
}

pub fn normalize_key_name(k: &str) -> String {
    let k = k.trim().to_ascii_lowercase();
    match k.as_str() {
        "enter" => "return".into(),
        "," => "comma".into(),
        " " => "space".into(),
        other => other.into(),
    }
}

/// Super+N workspace target (0 → 10).
pub fn workspace_for_digit(key: &str) -> Option<i64> {
    match normalize_key_name(key).as_str() {
        "1" => Some(1),
        "2" => Some(2),
        "3" => Some(3),
        "4" => Some(4),
        "5" => Some(5),
        "6" => Some(6),
        "7" => Some(7),
        "8" => Some(8),
        "9" => Some(9),
        "0" => Some(10),
        _ => None,
    }
}

pub fn default_binds() -> Vec<BindEntry> {
    let mut v = vec![
        BindEntry {
            id: "beacon".into(),
            mods: BindMods::logo_only(),
            key: "space".into(),
            action: BindAction::Shell {
                target: "chrome".into(),
                method: "beacon".into(),
            },
        },
        BindEntry {
            id: "beacon_d".into(),
            mods: BindMods::logo_only(),
            key: "d".into(),
            action: BindAction::Shell {
                target: "chrome".into(),
                method: "beacon".into(),
            },
        },
        BindEntry {
            id: "settings".into(),
            mods: BindMods::logo_only(),
            key: "comma".into(),
            action: BindAction::Exec(vec!["proteus-open".into(), "settings".into()]),
        },
        BindEntry {
            id: "lock".into(),
            mods: BindMods::logo_only(),
            key: "l".into(),
            action: BindAction::Shell {
                target: "lock".into(),
                method: "lock".into(),
            },
        },
        BindEntry {
            id: "terminal".into(),
            mods: BindMods::logo_only(),
            key: "return".into(),
            action: BindAction::Exec(vec!["proteus-terminal".into()]),
        },
        BindEntry {
            id: "customize_desktop".into(),
            mods: BindMods::logo_shift(),
            key: "w".into(),
            action: BindAction::Shell {
                target: "chrome".into(),
                method: "customizeDesktop".into(),
            },
        },
        BindEntry {
            id: "screenshot".into(),
            mods: BindMods::logo_shift(),
            key: "s".into(),
            action: BindAction::Exec(vec!["proteus-screenshot".into()]),
        },
    ];
    for d in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"] {
        let n = workspace_for_digit(d).unwrap();
        v.push(BindEntry {
            id: format!("workspace_{n}"),
            mods: BindMods::logo_only(),
            key: d.into(),
            action: BindAction::Dispatch(format!("workspace {n}")),
        });
    }
    v
}

fn merge_fact_overrides(entries: &mut Vec<BindEntry>) {
    let path = keybinds_fact_path();
    let Ok(raw) = std::fs::read_to_string(&path) else {
        return;
    };
    let Ok(v) = serde_json::from_str::<Value>(&raw) else {
        eprintln!(
            "proteus-compositor-next: keybinds.json invalid JSON ({})",
            path.display()
        );
        return;
    };
    let Some(arr) = v.get("overrides").and_then(|x| x.as_array()) else {
        return;
    };
    for item in arr {
        let Some(id) = item.get("id").and_then(|x| x.as_str()) else {
            continue;
        };
        let Some(key) = item.get("key").and_then(|x| x.as_str()) else {
            continue;
        };
        let mods = parse_mods(item.get("mods"));
        let Some(action) = parse_action(item.get("action")) else {
            eprintln!("proteus-compositor-next: keybinds override {id}: bad action");
            continue;
        };
        let entry = BindEntry {
            id: id.to_string(),
            mods,
            key: normalize_key_name(key),
            action,
        };
        if let Some(slot) = entries.iter_mut().find(|e| e.id == id) {
            *slot = entry;
        } else {
            // Unknown id: append (allows extra binds via Fact).
            entries.push(entry);
        }
    }
}

fn parse_mods(v: Option<&Value>) -> BindMods {
    let mut m = BindMods {
        logo: false,
        shift: false,
        ctrl: false,
        alt: false,
    };
    let Some(arr) = v.and_then(|x| x.as_array()) else {
        return BindMods::logo_only();
    };
    for item in arr {
        let Some(s) = item.as_str() else {
            continue;
        };
        match s.to_ascii_lowercase().as_str() {
            "super" | "logo" | "mod" | "meta" => m.logo = true,
            "shift" => m.shift = true,
            "ctrl" | "control" => m.ctrl = true,
            "alt" => m.alt = true,
            _ => {}
        }
    }
    m
}

fn parse_action(v: Option<&Value>) -> Option<BindAction> {
    let v = v?;
    if let Some(arr) = v.get("shell").and_then(|x| x.as_array()) {
        let target = arr.first()?.as_str()?.to_string();
        let method = arr.get(1)?.as_str()?.to_string();
        return Some(BindAction::Shell { target, method });
    }
    if let Some(s) = v.get("dispatch").and_then(|x| x.as_str()) {
        return Some(BindAction::Dispatch(s.to_string()));
    }
    if let Some(arr) = v.get("exec").and_then(|x| x.as_array()) {
        let args: Vec<String> = arr
            .iter()
            .filter_map(|x| x.as_str().map(str::to_string))
            .collect();
        if args.is_empty() {
            return None;
        }
        return Some(BindAction::Exec(args));
    }
    None
}

/// Resolve a helper on PATH or common install / build locations.
fn resolve_bin(name: &str) -> Option<String> {
    if let Ok(p) = which_bin(name) {
        return Some(p);
    }
    let home = std::env::var("HOME").unwrap_or_default();
    let candidates = [
        format!("/usr/local/bin/{name}"),
        format!("{home}/.local/bin/{name}"),
        format!("/mnt/proteus/target/debug/{name}"),
        format!("/mnt/proteus/target/release/{name}"),
        format!("/mnt/proteus/shell/scripts/{name}"),
    ];
    for c in candidates {
        if std::path::Path::new(&c).is_file() {
            return Some(c);
        }
    }
    // Repo-relative from PROTEUS_ROOT
    if let Ok(root) = std::env::var("PROTEUS_ROOT") {
        for sub in ["target/debug", "target/release", "shell/scripts"] {
            let p = format!("{root}/{sub}/{name}");
            if std::path::Path::new(&p).is_file() {
                return Some(p);
            }
        }
    }
    None
}

fn which_bin(name: &str) -> Result<String, ()> {
    let out = Command::new("sh")
        .arg("-c")
        .arg(format!("command -v {name}"))
        .output()
        .map_err(|_| ())?;
    if !out.status.success() {
        return Err(());
    }
    let s = String::from_utf8_lossy(&out.stdout).trim().to_string();
    if s.is_empty() {
        Err(())
    } else {
        Ok(s)
    }
}

/// Spawn shellctl / exec actions (detached). Dispatch handled by caller in-process.
pub fn spawn_action(action: &BindAction) {
    match action {
        BindAction::Dispatch(_) => {}
        BindAction::Shell { target, method } => {
            let bin = resolve_bin("proteus-shellctl").unwrap_or_else(|| "proteus-shellctl".into());
            let _ = Command::new(&bin).arg(target).arg(method).spawn();
        }
        BindAction::Exec(args) => {
            if args.is_empty() {
                return;
            }
            let bin_name = &args[0];
            let bin = resolve_bin(bin_name).unwrap_or_else(|| bin_name.clone());
            let mut cmd = Command::new(&bin);
            if args.len() > 1 {
                cmd.args(&args[1..]);
            }
            if let Err(e) = cmd.spawn() {
                eprintln!("proteus-compositor-next: exec {bin}: {e}");
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn workspace_digit_map() {
        assert_eq!(workspace_for_digit("1"), Some(1));
        assert_eq!(workspace_for_digit("0"), Some(10));
        assert_eq!(workspace_for_digit("x"), None);
    }

    #[test]
    fn normalize_keys() {
        assert_eq!(normalize_key_name("Enter"), "return");
        assert_eq!(normalize_key_name("SPACE"), "space");
        assert_eq!(normalize_key_name(","), "comma");
    }

    #[test]
    fn defaults_include_beacon_lock_workspace() {
        let d = default_binds();
        assert!(d.iter().any(|e| e.id == "beacon"));
        assert!(d.iter().any(|e| e.id == "lock"));
        assert!(d.iter().any(|e| e.id == "workspace_1"));
        assert!(d.iter().any(|e| e.id == "workspace_10"));
    }

    #[test]
    fn parse_mods_super_shift() {
        let v = serde_json::json!(["super", "shift"]);
        let m = parse_mods(Some(&v));
        assert!(m.logo && m.shift && !m.ctrl);
    }

    #[test]
    fn parse_action_variants() {
        let shell = serde_json::json!({"shell": ["chrome", "beacon"]});
        assert_eq!(
            parse_action(Some(&shell)),
            Some(BindAction::Shell {
                target: "chrome".into(),
                method: "beacon".into(),
            })
        );
        let disp = serde_json::json!({"dispatch": "workspace 2"});
        assert_eq!(
            parse_action(Some(&disp)),
            Some(BindAction::Dispatch("workspace 2".into()))
        );
        let exec = serde_json::json!({"exec": ["proteus-terminal"]});
        assert_eq!(
            parse_action(Some(&exec)),
            Some(BindAction::Exec(vec!["proteus-terminal".into()]))
        );
    }

    #[test]
    fn lookup_logo_space() {
        let state = BindsState {
            entries: default_binds(),
        };
        let mods = ModifiersState {
            logo: true,
            ..Default::default()
        };
        let a = state.lookup(&mods, "space").unwrap();
        assert!(matches!(a, BindAction::Shell { method, .. } if method == "beacon"));
    }
}
