//! Nested Xwayland — spawn Xwayland + X11Wm; map X11 windows into Space/wm.
//! Fail soft if the `Xwayland` binary is missing.

use std::os::unix::io::OwnedFd;
use std::process::Stdio;

use smithay::{
    desktop::Window,
    input::pointer::{Focus, GrabStartData},
    reexports::{
        calloop::EventLoop,
        wayland_server::protocol::wl_surface::WlSurface,
    },
    utils::{Logical, Rectangle, SERIAL_COUNTER},
    wayland::{
        selection::SelectionTarget,
        xwayland_shell::{XWaylandShellHandler, XWaylandShellState},
    },
    xwayland::{
        xwm::{Reorder, ResizeEdge as X11ResizeEdge, WmWindowProperty, X11Window, XwmId},
        X11Surface, X11Wm, XWayland, XWaylandEvent, XwmHandler,
    },
};

use crate::grabs::{resize_edges_geometry, MoveSurfaceGrab, ResizeSurfaceGrab};
use crate::{CalloopData, CompositorNext};

use smithay::reexports::wayland_protocols::xdg::shell::server::xdg_toplevel;

/// Start Xwayland (soft-fail) and insert into the event loop.
pub fn init_xwayland(
    event_loop: &mut EventLoop<'static, CalloopData>,
    data: &mut CalloopData,
) {
    let dh = data.display_handle.clone();
    let (xwayland, client) = match XWayland::spawn(
        &dh,
        None,
        std::iter::empty::<(String, String)>(),
        true,
        Stdio::null(),
        Stdio::null(),
        |_| (),
    ) {
        Ok(pair) => pair,
        Err(e) => {
            eprintln!(
                "proteus-compositor-next: Xwayland unavailable ({e}) — Wayland-only mode"
            );
            return;
        }
    };

    data.state.xwayland_client = Some(client.clone());
    let handle = event_loop.handle();
    let handle_for_wm = handle.clone();
    if let Err(e) = handle.insert_source(xwayland, move |event, _, data| match event {
        XWaylandEvent::Ready {
            x11_socket,
            display_number,
        } => {
            data.state.x11_display = Some(display_number);
            let display = format!(":{display_number}");
            std::env::set_var("DISPLAY", &display);
            eprintln!("proteus-compositor-next: Xwayland ready DISPLAY={display}");

            match X11Wm::start_wm(handle_for_wm.clone(), x11_socket, client.clone()) {
                Ok(wm) => {
                    data.state.xwm = Some(wm);
                    eprintln!("proteus-compositor-next: X11Wm attached");
                }
                Err(e) => {
                    eprintln!("proteus-compositor-next: X11Wm failed: {e}");
                }
            }
        }
        XWaylandEvent::Error => {
            eprintln!("proteus-compositor-next: Xwayland failed to start");
        }
    }) {
        eprintln!("proteus-compositor-next: insert Xwayland source: {e}");
    }
}

fn map_x11_edge(edge: X11ResizeEdge) -> xdg_toplevel::ResizeEdge {
    match edge {
        X11ResizeEdge::Top => xdg_toplevel::ResizeEdge::Top,
        X11ResizeEdge::Bottom => xdg_toplevel::ResizeEdge::Bottom,
        X11ResizeEdge::Left => xdg_toplevel::ResizeEdge::Left,
        X11ResizeEdge::Right => xdg_toplevel::ResizeEdge::Right,
        X11ResizeEdge::TopLeft => xdg_toplevel::ResizeEdge::TopLeft,
        X11ResizeEdge::TopRight => xdg_toplevel::ResizeEdge::TopRight,
        X11ResizeEdge::BottomLeft => xdg_toplevel::ResizeEdge::BottomLeft,
        X11ResizeEdge::BottomRight => xdg_toplevel::ResizeEdge::BottomRight,
    }
}

impl CompositorNext {
    fn address_for_x11(&self, surface: &X11Surface) -> Option<String> {
        self.windows.iter().find_map(|(addr, w)| {
            w.x11_surface()
                .filter(|x| *x == surface)
                .map(|_| addr.clone())
        })
    }

    fn map_x11_window(&mut self, window: X11Surface, override_redirect: bool) {
        let geo = window.geometry();
        let loc = if override_redirect {
            (geo.loc.x, geo.loc.y)
        } else {
            self.wm.next_cascade_loc()
        };
        if !override_redirect {
            let _ = window.configure(Some(Rectangle::new(loc.into(), geo.size)));
            let _ = window.set_mapped(true);
        }

        let address = self.wm.alloc_address();
        let class = window.class();
        let title = window.title();
        self.wm
            .add_toplevel_ssd(
                address.clone(),
                class,
                title,
                loc,
                self.primary_output_name(),
                false,
            );

        let win = Window::new_x11_window(window);
        self.windows.insert(address.clone(), win.clone());
        self.space.map_element(win, loc, false);
        if !override_redirect {
            self.relayout_active();
            self.focus_address(&address);
        }
        self.broadcast_event(&format!("openwindow>>{address}"));
        eprintln!(
            "proteus-compositor-next: x11 toplevel mapped: {address}{}",
            if override_redirect {
                " (override-redirect)"
            } else {
                ""
            }
        );
    }

    fn unmap_x11_window(&mut self, surface: &X11Surface) {
        let Some(addr) = self.address_for_x11(surface) else {
            return;
        };
        if let Some(window) = self.windows.remove(&addr) {
            self.space.unmap_elem(&window);
        }
        self.wm.remove_toplevel(&addr);
        self.relayout_active();
        self.broadcast_event(&format!("closewindow>>{addr}"));
        if let Some(focus) = self.wm.focused.clone() {
            self.focus_address(&focus);
        }
    }

    fn output_geo(&self) -> Option<Rectangle<i32, Logical>> {
        let output = self.space.outputs().next()?.clone();
        self.space.output_geometry(&output)
    }
}

impl XwmHandler for CompositorNext {
    fn xwm_state(&mut self, _xwm: XwmId) -> &mut X11Wm {
        self.xwm
            .as_mut()
            .expect("X11Wm callback without attached wm")
    }

    fn new_window(&mut self, _xwm: XwmId, _window: X11Surface) {}
    fn new_override_redirect_window(&mut self, _xwm: XwmId, _window: X11Surface) {}

    fn map_window_request(&mut self, _xwm: XwmId, window: X11Surface) {
        self.map_x11_window(window, false);
    }

    fn mapped_override_redirect_window(&mut self, _xwm: XwmId, window: X11Surface) {
        self.map_x11_window(window, true);
    }

    fn unmapped_window(&mut self, _xwm: XwmId, window: X11Surface) {
        self.unmap_x11_window(&window);
        let _ = window.set_mapped(false);
    }

    fn destroyed_window(&mut self, _xwm: XwmId, window: X11Surface) {
        self.unmap_x11_window(&window);
    }

    fn configure_request(
        &mut self,
        _xwm: XwmId,
        window: X11Surface,
        x: Option<i32>,
        y: Option<i32>,
        w: Option<u32>,
        h: Option<u32>,
        _reorder: Option<Reorder>,
    ) {
        let mut geo = window.geometry();
        if let Some(x) = x {
            geo.loc.x = x;
        }
        if let Some(y) = y {
            geo.loc.y = y;
        }
        if let Some(w) = w {
            geo.size.w = w as i32;
        }
        if let Some(h) = h {
            geo.size.h = h as i32;
        }
        let _ = window.configure(Some(geo));
        if let Some(addr) = self.address_for_x11(&window) {
            if let Some(win) = self.windows.get(&addr).cloned() {
                self.space.map_element(win, geo.loc, false);
            }
            if let Some(t) = self.wm.find_mut(&addr) {
                t.loc_x = geo.loc.x;
                t.loc_y = geo.loc.y;
                t.size_w = geo.size.w;
                t.size_h = geo.size.h;
            }
        }
    }

    fn configure_notify(
        &mut self,
        _xwm: XwmId,
        window: X11Surface,
        geometry: Rectangle<i32, Logical>,
        _above: Option<X11Window>,
    ) {
        if let Some(addr) = self.address_for_x11(&window) {
            if let Some(win) = self.windows.get(&addr).cloned() {
                self.space.map_element(win, geometry.loc, false);
            }
            if let Some(t) = self.wm.find_mut(&addr) {
                t.loc_x = geometry.loc.x;
                t.loc_y = geometry.loc.y;
                t.size_w = geometry.size.w;
                t.size_h = geometry.size.h;
            }
        }
    }

    fn property_notify(&mut self, _xwm: XwmId, window: X11Surface, property: WmWindowProperty) {
        let Some(addr) = self.address_for_x11(&window) else {
            return;
        };
        match property {
            WmWindowProperty::Title => {
                self.wm.set_title(&addr, window.title());
                self.broadcast_event("activewindow>>");
            }
            WmWindowProperty::Class => {
                self.wm.set_class(&addr, window.class());
            }
            _ => {}
        }
    }

    fn maximize_request(&mut self, _xwm: XwmId, window: X11Surface) {
        let _ = window.set_maximized(true);
        if let Some(geo) = self.output_geo() {
            let _ = window.configure(Some(geo));
            if let Some(addr) = self.address_for_x11(&window) {
                if let Some(win) = self.windows.get(&addr).cloned() {
                    self.space.map_element(win, geo.loc, true);
                }
            }
        }
    }

    fn unmaximize_request(&mut self, _xwm: XwmId, window: X11Surface) {
        let _ = window.set_maximized(false);
    }

    fn fullscreen_request(&mut self, _xwm: XwmId, window: X11Surface) {
        let _ = window.set_fullscreen(true);
        if let Some(geo) = self.output_geo() {
            let _ = window.configure(Some(geo));
            if let Some(addr) = self.address_for_x11(&window) {
                if let Some(t) = self.wm.find_mut(&addr) {
                    t.fullscreen = true;
                }
                if let Some(win) = self.windows.get(&addr).cloned() {
                    self.space.map_element(win, geo.loc, true);
                }
            }
        }
    }

    fn unfullscreen_request(&mut self, _xwm: XwmId, window: X11Surface) {
        let _ = window.set_fullscreen(false);
        if let Some(addr) = self.address_for_x11(&window) {
            if let Some(t) = self.wm.find_mut(&addr) {
                t.fullscreen = false;
            }
        }
    }

    fn minimize_request(&mut self, _xwm: XwmId, window: X11Surface) {
        if let Some(addr) = self.address_for_x11(&window) {
            self.wm.focused = Some(addr);
            if let Ok(ops) = self.wm.dispatch("movetoworkspacesilent special:minimized") {
                self.apply_wm_ops(ops);
            }
        }
    }

    fn move_request(&mut self, _xwm: XwmId, window: X11Surface, button: u32) {
        let Some(addr) = self.address_for_x11(&window) else {
            return;
        };
        let Some(win) = self.windows.get(&addr).cloned() else {
            return;
        };
        let Some(initial) = self.space.element_location(&win) else {
            return;
        };
        let seat = self.seat.clone();
        let Some(pointer) = seat.get_pointer() else {
            return;
        };
        let serial = SERIAL_COUNTER.next_serial();
        let start_data = GrabStartData {
            focus: None,
            button,
            location: pointer.current_location(),
        };
        pointer.set_grab(
            self,
            MoveSurfaceGrab {
                start_data,
                window: win,
                initial_window_location: initial,
                address: Some(addr),
            },
            serial,
            Focus::Clear,
        );
    }

    fn resize_request(
        &mut self,
        _xwm: XwmId,
        window: X11Surface,
        button: u32,
        resize_edge: X11ResizeEdge,
    ) {
        let Some(addr) = self.address_for_x11(&window) else {
            return;
        };
        let Some(win) = self.windows.get(&addr).cloned() else {
            return;
        };
        let Some(loc) = self.space.element_location(&win) else {
            return;
        };
        let initial_rect = Rectangle::new(loc, win.geometry().size);
        let seat = self.seat.clone();
        let Some(pointer) = seat.get_pointer() else {
            return;
        };
        let serial = SERIAL_COUNTER.next_serial();
        let start_data = GrabStartData {
            focus: None,
            button,
            location: pointer.current_location(),
        };
        let edges = map_x11_edge(resize_edge);
        let _ = resize_edges_geometry(edges, initial_rect, (0.0, 0.0).into());
        pointer.set_grab(
            self,
            ResizeSurfaceGrab {
                start_data,
                window: win,
                edges,
                initial_rect,
                address: Some(addr),
            },
            serial,
            Focus::Clear,
        );
    }

    fn allow_selection_access(&mut self, _xwm: XwmId, _selection: SelectionTarget) -> bool {
        false
    }

    fn send_selection(
        &mut self,
        _xwm: XwmId,
        _selection: SelectionTarget,
        _mime_type: String,
        _fd: OwnedFd,
    ) {
    }
}

/// X11Wm runs on the calloop data type — forward to compositor state.
impl XwmHandler for CalloopData {
    fn xwm_state(&mut self, xwm: XwmId) -> &mut X11Wm {
        XwmHandler::xwm_state(&mut self.state, xwm)
    }
    fn new_window(&mut self, xwm: XwmId, window: X11Surface) {
        XwmHandler::new_window(&mut self.state, xwm, window)
    }
    fn new_override_redirect_window(&mut self, xwm: XwmId, window: X11Surface) {
        XwmHandler::new_override_redirect_window(&mut self.state, xwm, window)
    }
    fn map_window_request(&mut self, xwm: XwmId, window: X11Surface) {
        XwmHandler::map_window_request(&mut self.state, xwm, window)
    }
    fn mapped_override_redirect_window(&mut self, xwm: XwmId, window: X11Surface) {
        XwmHandler::mapped_override_redirect_window(&mut self.state, xwm, window)
    }
    fn unmapped_window(&mut self, xwm: XwmId, window: X11Surface) {
        XwmHandler::unmapped_window(&mut self.state, xwm, window)
    }
    fn destroyed_window(&mut self, xwm: XwmId, window: X11Surface) {
        XwmHandler::destroyed_window(&mut self.state, xwm, window)
    }
    fn configure_request(
        &mut self,
        xwm: XwmId,
        window: X11Surface,
        x: Option<i32>,
        y: Option<i32>,
        w: Option<u32>,
        h: Option<u32>,
        reorder: Option<Reorder>,
    ) {
        XwmHandler::configure_request(&mut self.state, xwm, window, x, y, w, h, reorder)
    }
    fn configure_notify(
        &mut self,
        xwm: XwmId,
        window: X11Surface,
        geometry: Rectangle<i32, Logical>,
        above: Option<X11Window>,
    ) {
        XwmHandler::configure_notify(&mut self.state, xwm, window, geometry, above)
    }
    fn property_notify(&mut self, xwm: XwmId, window: X11Surface, property: WmWindowProperty) {
        XwmHandler::property_notify(&mut self.state, xwm, window, property)
    }
    fn maximize_request(&mut self, xwm: XwmId, window: X11Surface) {
        XwmHandler::maximize_request(&mut self.state, xwm, window)
    }
    fn unmaximize_request(&mut self, xwm: XwmId, window: X11Surface) {
        XwmHandler::unmaximize_request(&mut self.state, xwm, window)
    }
    fn fullscreen_request(&mut self, xwm: XwmId, window: X11Surface) {
        XwmHandler::fullscreen_request(&mut self.state, xwm, window)
    }
    fn unfullscreen_request(&mut self, xwm: XwmId, window: X11Surface) {
        XwmHandler::unfullscreen_request(&mut self.state, xwm, window)
    }
    fn minimize_request(&mut self, xwm: XwmId, window: X11Surface) {
        XwmHandler::minimize_request(&mut self.state, xwm, window)
    }
    fn move_request(&mut self, xwm: XwmId, window: X11Surface, button: u32) {
        XwmHandler::move_request(&mut self.state, xwm, window, button)
    }
    fn resize_request(
        &mut self,
        xwm: XwmId,
        window: X11Surface,
        button: u32,
        resize_edge: X11ResizeEdge,
    ) {
        XwmHandler::resize_request(&mut self.state, xwm, window, button, resize_edge)
    }
    fn allow_selection_access(&mut self, xwm: XwmId, selection: SelectionTarget) -> bool {
        XwmHandler::allow_selection_access(&mut self.state, xwm, selection)
    }
    fn send_selection(
        &mut self,
        xwm: XwmId,
        selection: SelectionTarget,
        mime_type: String,
        fd: OwnedFd,
    ) {
        XwmHandler::send_selection(&mut self.state, xwm, selection, mime_type, fd)
    }
}

impl XWaylandShellHandler for CalloopData {
    fn xwayland_shell_state(&mut self) -> &mut XWaylandShellState {
        &mut self.state.xwayland_shell_state
    }

    fn surface_associated(&mut self, xwm: XwmId, surface: WlSurface, window: X11Surface) {
        XWaylandShellHandler::surface_associated(&mut self.state, xwm, surface, window)
    }
}

impl XWaylandShellHandler for CompositorNext {
    fn xwayland_shell_state(&mut self) -> &mut XWaylandShellState {
        &mut self.xwayland_shell_state
    }

    fn surface_associated(&mut self, _xwm: XwmId, _surface: WlSurface, window: X11Surface) {
        if let Some(addr) = self.address_for_x11(&window) {
            if let Some(win) = self.windows.get(&addr).cloned() {
                self.space.raise_element(&win, true);
            }
        }
    }
}

smithay::delegate_xwayland_shell!(CompositorNext);
