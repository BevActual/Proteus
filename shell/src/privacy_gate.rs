//! Thin Privacy Ask producer for Beacon/Dock launches.
//!
//! When mic/camera/screen grant is `ask` for the app (and no session Allow-once),
//! open the Ask layer and defer launch until Allow / Deny.

use proteus_shell_core::permissions::PermissionsStore;

/// Capture categories gated at launch (not location/notifications).
pub const LAUNCH_ASK_CATS: &[&str] = &["microphone", "camera", "screen"];

/// Desktop id for a Beacon hit or dock pin, if launchable as an app.
pub fn desktop_id_for_launch(target: &str) -> Option<String> {
    let lower = target.trim().to_lowercase();
    if lower.is_empty()
        || lower.starts_with("clipboard ·")
        || lower.starts_with("calc ·")
        || lower.starts_with("window ·")
        || lower.starts_with("file ·")
        || lower.starts_with("place ·")
        || lower.starts_with("recent ·")
        || lower.starts_with("settings")
        || lower.contains("workload")
        || lower.contains("lock screen")
        || crate::surfaces::is_beacon_pin(target)
    {
        return None;
    }
    let id = target
        .rsplit(" · ")
        .next()
        .unwrap_or(target)
        .trim()
        .trim_end_matches(".desktop");
    if id.is_empty() {
        return None;
    }
    Some(id.to_string())
}

/// First mic/camera/screen Ask category for `app_id`, or None.
pub fn first_launch_ask_category(app_id: &str) -> Option<String> {
    let base = proteus_shell_core::facts::config_base();
    let store = PermissionsStore::read(&base);
    if !store.ready {
        return None;
    }
    for cat in LAUNCH_ASK_CATS {
        if store.is_ask(app_id, cat) {
            return Some((*cat).to_string());
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn desktop_id_from_beacon_and_skips() {
        assert_eq!(
            desktop_id_for_launch("Cheese · org.gnome.Cheese.desktop"),
            Some("org.gnome.Cheese".into())
        );
        assert_eq!(desktop_id_for_launch("org.gnome.Cheese"), Some("org.gnome.Cheese".into()));
        assert!(desktop_id_for_launch("Calc · 2+2 = 4").is_none());
        assert!(desktop_id_for_launch("Settings · Sound · --page=sound").is_none());
        assert!(desktop_id_for_launch("File · /tmp/x").is_none());
        assert!(desktop_id_for_launch("proteus-launcher").is_none());
    }
}
