//! proteus-compositor-next — Smithay rung-2 spike (OWNED-STACK).
//!
//! Minimal nested compositor: winit backend, xdg-shell toplevels and
//! wlr-layer-shell so `proteus-shell` chrome layers can map inside it.
//! Explicit opt-in via `PROTEUS_COMPOSITOR_ENGINE=smithay`; no session
//! takeover, no DRM backend — Hyprland stays the shipping compositor.
//! Honest status: docs/proteus/COMPOSITOR-SPIKE.md.

mod handlers;
mod input;
mod state;
mod winit;

use smithay::reexports::{
    calloop::EventLoop,
    wayland_server::{Display, DisplayHandle},
};
pub use state::CompositorNext;

pub struct CalloopData {
    state: CompositorNext,
    display_handle: DisplayHandle,
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut event_loop: EventLoop<CalloopData> = EventLoop::try_new()?;

    let display: Display<CompositorNext> = Display::new()?;
    let display_handle = display.handle();
    let state = CompositorNext::new(&mut event_loop, display);

    let socket = state.socket_name.clone();
    let mut data = CalloopData {
        state,
        display_handle,
    };

    crate::winit::init_winit(&mut event_loop, &mut data)?;

    eprintln!(
        "proteus-compositor-next: nested spike on WAYLAND_DISPLAY={}",
        socket.to_string_lossy()
    );

    // Optional client to spawn inside the spike (e.g. proteus-shell).
    let mut args = std::env::args().skip(1);
    if let (Some(flag), Some(command)) = (args.next(), args.next()) {
        if flag == "-c" || flag == "--command" {
            let extra: Vec<String> = args.collect();
            std::process::Command::new(command).args(extra).spawn().ok();
        }
    }

    event_loop.run(None, &mut data, move |_| {})?;

    Ok(())
}
