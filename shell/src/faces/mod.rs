//! Session faces — composition boundary for **desktop · console · host**.
//!
//! Shared chrome kit (bar, dock, CC, Spaces, lock, …) stays in
//! [`crate::surfaces`] (`surfaces/{bar,dock,beacon,…}.rs`).
//! Faces own:
//! - which layers boot for the posture
//! - exclusive UI (console list IA, host Glance cards)
//! - future composition helpers as postures deepen
//!
//! Do **not** fork bar/dock/tokens per face — [CHROME.md](../../../docs/proteus/CHROME.md).

pub mod console;
pub mod desktop;
pub mod host;

pub use console::console_face_view;
pub use desktop::desktop_face_note;
pub use host::host_face_view;

use crate::layers;

/// Shared lean layer set (console + host): no dock / desktop-widgets.
pub const BOOT_LAYERS_LEAN: &[&str] = &[
    layers::LAUNCHER,
    layers::CONTROL_CENTER,
    layers::SPACES,
    layers::HUD,
    layers::BG,
    layers::TOAST,
    layers::PRIVACY_ASK,
    layers::LOCK,
];

/// Session face (posture chrome composition).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Face {
    #[default]
    Desktop,
    Console,
    Host,
}

impl Face {
    pub fn parse(raw: &str) -> Self {
        match raw.trim().to_ascii_lowercase().as_str() {
            "console" => Self::Console,
            "host" => Self::Host,
            "desktop" | "couch" | "" => Self::Desktop,
            other => {
                eprintln!("proteus-shell: unknown face {other:?} — using desktop");
                Self::Desktop
            }
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Self::Desktop => "desktop",
            Self::Console => "console",
            Self::Host => "host",
        }
    }

    /// Extra layer namespaces after the primary (bar) daemon window.
    pub fn boot_layers(self) -> &'static [&'static str] {
        match self {
            Self::Desktop => desktop::BOOT_LAYERS,
            Self::Console | Self::Host => BOOT_LAYERS_LEAN,
        }
    }

    /// Lean faces: no dock / desktop-widgets shelf.
    pub fn is_lean(self) -> bool {
        matches!(self, Self::Console | Self::Host)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn face_parse_and_layers() {
        assert_eq!(Face::parse("desktop"), Face::Desktop);
        assert_eq!(Face::parse("console"), Face::Console);
        assert_eq!(Face::parse("host"), Face::Host);
        assert!(Face::Desktop.boot_layers().contains(&crate::layers::DOCK));
        assert!(!Face::Console.boot_layers().contains(&crate::layers::DOCK));
        assert!(Face::Host.is_lean());
        assert_eq!(Face::Console.boot_layers(), BOOT_LAYERS_LEAN);
    }
}
