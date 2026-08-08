//! proteus-compositor — owned Smithay session compositor (OWNED-STACK).
//!
//! Nested winit by default; `--backend drm` for libseat/TTY sessions via
//! `proteus-session`. Hyprland purged. Depth checklist:
//! docs/proteus/COMPOSITOR-SPIKE.md.

mod binds;
mod ctl;
mod cursor;
mod decoration;
mod displays;
mod dmabuf_init;
mod drm;
mod grabs;
mod handlers;
mod identify;
mod input;
mod input_config;
mod layout;
mod screencopy;
mod session_lock;
mod state;
mod wm;
mod winit;
mod xwayland;

use smithay::backend::session::Session;
use smithay::reexports::{
    calloop::EventLoop,
    wayland_server::{Display, DisplayHandle},
};
pub use state::CompositorNext;

pub struct CalloopData {
    pub state: CompositorNext,
    pub display_handle: DisplayHandle,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum BackendKind {
    Winit,
    Drm,
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Match xdg-desktop-portal-wlr UseIn=wlroots (Screenshot over zwlr_screencopy).
    // Applies to this compositor process and its -c children.
    std::env::set_var("XDG_CURRENT_DESKTOP", "wlroots");

    let (backend_kind, command) = parse_cli()?;

    let mut event_loop: EventLoop<'static, CalloopData> = EventLoop::try_new()?;
    let display: Display<CompositorNext> = Display::new()?;
    let display_handle = display.handle();

    let (seat_name, session_pair) = match backend_kind {
        BackendKind::Winit => ("winit".to_string(), None),
        BackendKind::Drm => {
            let (session, notifier) = crate::drm::open_session()?;
            (session.seat(), Some((session, notifier)))
        }
    };

    let state = CompositorNext::new(&mut event_loop, display, &seat_name);
    state.init_screencopy_global();
    eprintln!(
        "proteus-compositor: screencopy flip_y={} (PROTEUS_SCREENCOPY_FLIP_Y / virtio auto)",
        crate::screencopy::screencopy_should_flip_y()
    );

    let socket = state.socket_name.clone();
    let mut data = CalloopData {
        state,
        display_handle,
    };

    match backend_kind {
        BackendKind::Winit => {
            crate::winit::init_winit(&mut event_loop, &mut data)?;
            eprintln!(
                "proteus-compositor: nested on WAYLAND_DISPLAY={}",
                socket.to_string_lossy()
            );
        }
        BackendKind::Drm => {
            let (session, notifier) = session_pair.expect("drm session");
            crate::drm::init_drm(&mut event_loop, &mut data, session, notifier)?;
            eprintln!(
                "proteus-compositor: drm spike on WAYLAND_DISPLAY={}",
                socket.to_string_lossy()
            );
        }
    }

    crate::ctl::init_ctl(&mut event_loop, &mut data.state)?;
    crate::xwayland::init_xwayland(&mut event_loop, &mut data);

    if let Some((command, extra)) = command {
        let mut cmd = std::process::Command::new(&command);
        cmd.args(&extra);
        cmd.env("WAYLAND_DISPLAY", &socket);
        cmd.env("XDG_CURRENT_DESKTOP", "wlroots");
        if let Some(ref sock) = data.state.ctl_path {
            cmd.env("PROTEUS_COMPOSITOR_SOCK", sock);
        }
        cmd.env("PROTEUS_COMPOSITOR_ENGINE", "smithay");
        if let Some(n) = data.state.x11_display {
            cmd.env("DISPLAY", format!(":{n}"));
        }
        match cmd.spawn() {
            Ok(_) => {}
            Err(e) => eprintln!("proteus-compositor: spawn {command}: {e}"),
        }
    }

    event_loop.run(None, &mut data, move |_| {})?;

    Ok(())
}

fn parse_cli() -> Result<(BackendKind, Option<(String, Vec<String>)>), Box<dyn std::error::Error>>
{
    let mut args: Vec<String> = std::env::args().skip(1).collect();

    let mut backend = match std::env::var("PROTEUS_COMPOSITOR_BACKEND")
        .unwrap_or_default()
        .to_ascii_lowercase()
        .as_str()
    {
        "drm" => BackendKind::Drm,
        _ => BackendKind::Winit,
    };

    let mut i = 0;
    while i < args.len() {
        if args[i] == "--backend" {
            let value = args
                .get(i + 1)
                .ok_or("--backend requires winit|drm")?
                .to_ascii_lowercase();
            backend = match value.as_str() {
                "winit" => BackendKind::Winit,
                "drm" => BackendKind::Drm,
                other => {
                    return Err(format!("unknown --backend {other} (expected winit|drm)").into())
                }
            };
            args.drain(i..=i + 1);
            continue;
        }
        i += 1;
    }

    let command = if args.first().map(|s| s.as_str()) == Some("-c")
        || args.first().map(|s| s.as_str()) == Some("--command")
    {
        if args.len() < 2 {
            return Err("-c / --command requires a program".into());
        }
        let cmd = args[1].clone();
        let extra = args[2..].to_vec();
        Some((cmd, extra))
    } else if !args.is_empty() {
        return Err(format!("unexpected args: {}", args.join(" ")).into());
    } else {
        None
    };

    Ok((backend, command))
}
