//! Desktop face — default session chrome composition.
//!
//! Layer *views* live in [`crate::surfaces`] (shared kit). This module owns the
//! desktop layer set and is the home for desktop-only composition as it grows
//! (e.g. wiring helpers) — not a second copy of bar/dock.

use crate::layers;

/// Extra layers after the primary bar window (full desktop chrome).
pub const BOOT_LAYERS: &[&str] = &[
    layers::DOCK,
    layers::LAUNCHER,
    layers::CONTROL_CENTER,
    layers::SPACES,
    layers::HUD,
    layers::BG,
    layers::DESKTOP_WIDGETS,
    layers::TOAST,
    layers::PRIVACY_ASK,
    layers::LOCK,
];

/// Short ledger note for docs/smokes — desktop is the shipping default face.
pub fn desktop_face_note() -> &'static str {
    "desktop — full chrome via surfaces (bar/dock/Beacon/CC/HUD/toast/lock/widgets)"
}
