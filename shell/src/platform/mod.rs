//! Platform services the Quickshell runtime used to provide implicitly.
//!
//! - notifications: org.freedesktop.Notifications (zbus server, dbus-monitor fallback)
//! - tray: StatusNotifierItem host stub
//! - mpris: player listing via D-Bus
//! - upower / logind: power + session inhibit stubs
//! - brightness: backlight sysfs / brightnessctl
//! - audio: pactl / proteus-audio-mix
//! - session lock: layer-overlay default; `PROTEUS_SESSION_LOCK=protocol` uses
//!   iced_sessionlock helper when wired (see engine::activate_session_lock)

mod console_host;
mod focus;
mod lock_auth;
mod media;
mod network;
mod notifs;
mod power;
mod tray;
mod util;
mod wallpaper;
mod weather;

pub use console_host::*;
pub use focus::*;
pub use lock_auth::*;
pub use media::*;
pub use network::*;
pub use notifs::*;
pub use power::*;
pub use tray::*;
pub use wallpaper::*;
pub use weather::*;
