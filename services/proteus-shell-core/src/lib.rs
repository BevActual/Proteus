// proteus-shell-core — the owned shell spine (OWNED-STACK.md rung 0).
//
// Typed facts, chrome-token generation, and gating logic extracted from the
// QML singletons (Theme/Config/EnvGate/SessionPosture/Hardware) so every
// renderer — Quickshell today, iced chrome and XR faces later — shares one
// tested core. Truth stays on disk (ARCHITECTURE HARD RULES): this crate
// reads/writes the same fact files and catalogs; it owns no runtime state.

pub mod facts;
pub mod gate;
pub mod open;
pub mod permissions;
pub mod subscribe;
pub mod tokens;
