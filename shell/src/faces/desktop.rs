//! Desktop face — default session chrome (bar, dock, Beacon, CC, lock, …).
//!
//! Layer views live in [`crate::surfaces`]; this module marks the face boundary
//! so console/host rebuilds do not churn the desktop tree again.

/// Short ledger note for docs/smokes — desktop is the shipping default face.
pub fn desktop_face_note() -> &'static str {
    "desktop — full chrome via surfaces (bar/dock/Beacon/CC/HUD/toast/lock/widgets)"
}
