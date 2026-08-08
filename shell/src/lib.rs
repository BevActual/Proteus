//! Owned Proteus shell — iced_layershell session over proteus-shell-core.
//!
//! Ships as `proteus-shell`. Sole chrome tree (Quickshell retired).

pub mod anim;
pub mod beacon;
pub mod ctl;
pub mod desktop_widgets;
pub mod engine;
pub mod faces;
pub mod wm_ipc;
pub mod icons;
pub mod lock_ui;
pub mod platform;
pub mod spaces;
pub mod surfaces;

/// Layer namespaces — Hyprland rules / layerrules target these ids.
pub mod layers {
    pub const BAR: &str = "proteus-bar";
    pub const DOCK: &str = "proteus-dock";
    pub const LAUNCHER: &str = "proteus-launcher";
    pub const CONTROL_CENTER: &str = "proteus-control-center";
    pub const SPACES: &str = "proteus-spaces";
    pub const HUD: &str = "proteus-hud";
    pub const BG: &str = "proteus-bg";
    pub const DESKTOP_WIDGETS: &str = "proteus-desktop-widgets";
    pub const TOAST: &str = "proteus-toast";
    pub const PRIVACY_ASK: &str = "proteus-privacy-ask";
    pub const LOCK: &str = "proteus-lock";

    pub fn all() -> &'static [&'static str] {
        &[
            BAR,
            DOCK,
            LAUNCHER,
            CONTROL_CENTER,
            SPACES,
            HUD,
            BG,
            DESKTOP_WIDGETS,
            TOAST,
            PRIVACY_ASK,
            LOCK,
        ]
    }
}

/// IPC targets for `proteus-shellctl`.
pub mod ipc_targets {
    pub const LOCK: &str = "lock";
    pub const CHROME: &str = "chrome";
    pub const WIDGETS: &str = "widgets";
    pub const HUD: &str = "hud";

    pub fn all() -> &'static [&'static str] {
        &[LOCK, CHROME, WIDGETS, HUD]
    }
}
