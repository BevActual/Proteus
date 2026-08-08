//! Session application — state, update, view, layers (binary-private).
//!
//! `main.rs` stays the boot entry (ctl socket, daemon, CLI). Shared chrome
//! views live in [`proteus_shell::surfaces`]; faces in [`proteus_shell::faces`].

mod handlers;
mod layers;
mod runtime;
mod state;
mod subscription;
mod update;
mod view;

pub(crate) use handlers::*;
pub(crate) use layers::*;
pub(crate) use runtime::*;
pub(crate) use state::*;
pub(crate) use subscription::subscription;
pub(crate) use update::*;
pub(crate) use view::*;
