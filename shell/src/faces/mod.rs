//! Session faces — desktop (default chrome), console, and host.
//!
//! Console and host UIs are thin stubs today; rebuild in-tree later.
//! No Quickshell console-home / gamescope swap in this pass.

pub mod console;
pub mod desktop;
pub mod host;

pub use console::console_face_view;
pub use desktop::desktop_face_note;
pub use host::host_face_view;
