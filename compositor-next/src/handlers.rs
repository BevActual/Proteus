//! Protocol handlers — compositor/shm/seat/output/xdg-shell + wlr-layer-shell.

use smithay::{
    backend::renderer::utils::on_commit_buffer_handler,
    delegate_compositor, delegate_data_device, delegate_dmabuf, delegate_layer_shell, delegate_output,
    delegate_seat, delegate_shm, delegate_xdg_decoration, delegate_xdg_shell,
    desktop::{
        find_popup_root_surface, get_popup_toplevel_coords, layer_map_for_output, LayerSurface,
        PopupKeyboardGrab, PopupKind, PopupManager, PopupPointerGrab, Space, Window,
        WindowSurfaceType,
    },
    input::{
        pointer::{Focus, GrabStartData as PointerGrabStartData},
        Seat, SeatHandler, SeatState,
    },
    output::Output,
    reexports::wayland_server::{
        protocol::{wl_buffer, wl_output::WlOutput, wl_seat, wl_surface::WlSurface},
        Client, Resource,
    },
    utils::{Rectangle, Serial},
    wayland::{
        buffer::BufferHandler,
        compositor::{
            get_parent, is_sync_subsurface, with_states, CompositorClientState, CompositorHandler,
            CompositorState,
        },
        dmabuf::{DmabufHandler, DmabufState, ImportNotifier},
        output::OutputHandler,
        selection::{
            data_device::{
                set_data_device_focus, ClientDndGrabHandler, DataDeviceHandler, DataDeviceState,
                ServerDndGrabHandler,
            },
            SelectionHandler,
        },
        shell::{
            wlr_layer::{
                Layer, LayerSurface as WlrLayerSurface, LayerSurfaceData, WlrLayerShellHandler,
                WlrLayerShellState,
            },
            xdg::{
                decoration::XdgDecorationHandler,
                PopupSurface, PositionerState, ToplevelSurface, XdgShellHandler, XdgShellState,
                XdgToplevelSurfaceData,
            },
        },
        shm::{ShmHandler, ShmState},
    },
};
use smithay::reexports::wayland_protocols::xdg::decoration::zv1::server::zxdg_toplevel_decoration_v1::Mode;

use crate::grabs::{MoveSurfaceGrab, ResizeSurfaceGrab};
use crate::state::ClientState;
use crate::CompositorNext;

// -------------------------------------------------------------- compositor --

impl CompositorHandler for CompositorNext {
    fn compositor_state(&mut self) -> &mut CompositorState {
        &mut self.compositor_state
    }

    fn client_compositor_state<'a>(&self, client: &'a Client) -> &'a CompositorClientState {
        if let Some(state) = client.get_data::<ClientState>() {
            return &state.compositor_state;
        }
        if let Some(state) = client.get_data::<smithay::xwayland::XWaylandClientData>() {
            return &state.compositor_state;
        }
        panic!("Unknown client data type for compositor state");
    }

    fn commit(&mut self, surface: &WlSurface) {
        on_commit_buffer_handler::<Self>(surface);
        if !is_sync_subsurface(surface) {
            let mut root = surface.clone();
            while let Some(parent) = get_parent(&root) {
                root = parent;
            }
            if let Some(window) = self
                .space
                .elements()
                .find(|w| w.toplevel().is_some_and(|t| t.wl_surface() == &root))
            {
                window.on_commit();
            }
        };

        handle_xdg_commit(&mut self.popups, &self.space, surface);
        self.handle_layer_commit(surface);
    }
}

impl BufferHandler for CompositorNext {
    fn buffer_destroyed(&mut self, _buffer: &wl_buffer::WlBuffer) {}
}

impl DmabufHandler for CompositorNext {
    fn dmabuf_state(&mut self) -> &mut DmabufState {
        &mut self.dmabuf_state
    }

    fn dmabuf_imported(
        &mut self,
        _global: &smithay::wayland::dmabuf::DmabufGlobal,
        _dmabuf: smithay::backend::allocator::dmabuf::Dmabuf,
        notifier: ImportNotifier,
    ) {
        // Thin: accept client dmabufs so screencopy targets can be created.
        // Surface compositing of client dmabufs is not a goal this slice.
        let _ = notifier.successful::<CompositorNext>();
    }
}

impl ShmHandler for CompositorNext {
    fn shm_state(&self) -> &ShmState {
        &self.shm_state
    }
}

delegate_compositor!(CompositorNext);
delegate_shm!(CompositorNext);
delegate_dmabuf!(CompositorNext);

// --------------------------------------------------------------------- seat --

impl SeatHandler for CompositorNext {
    type KeyboardFocus = WlSurface;
    type PointerFocus = WlSurface;
    type TouchFocus = WlSurface;

    fn seat_state(&mut self) -> &mut SeatState<CompositorNext> {
        &mut self.seat_state
    }

    fn cursor_image(
        &mut self,
        _seat: &Seat<Self>,
        image: smithay::input::pointer::CursorImageStatus,
    ) {
        self.set_cursor_status(image);
    }

    fn focus_changed(&mut self, seat: &Seat<Self>, focused: Option<&WlSurface>) {
        let dh = &self.display_handle;
        let client = focused.and_then(|s| dh.get_client(s.id()).ok());
        set_data_device_focus(dh, seat, client);
    }
}

delegate_seat!(CompositorNext);

impl SelectionHandler for CompositorNext {
    type SelectionUserData = ();
}

impl DataDeviceHandler for CompositorNext {
    fn data_device_state(&self) -> &DataDeviceState {
        &self.data_device_state
    }
}

impl ClientDndGrabHandler for CompositorNext {}
impl ServerDndGrabHandler for CompositorNext {}

delegate_data_device!(CompositorNext);

impl OutputHandler for CompositorNext {}
delegate_output!(CompositorNext);

impl smithay::wayland::fractional_scale::FractionalScaleHandler for CompositorNext {}
smithay::delegate_viewporter!(CompositorNext);
smithay::delegate_fractional_scale!(CompositorNext);

// ---------------------------------------------------------------- xdg-shell --

impl XdgShellHandler for CompositorNext {
    fn xdg_shell_state(&mut self) -> &mut XdgShellState {
        &mut self.xdg_shell_state
    }

    fn new_toplevel(&mut self, surface: ToplevelSurface) {
        let window = Window::new_wayland_window(surface.clone());
        let address = self.wm.alloc_address();
        let loc = self.wm.next_cascade_loc();
        let (class, title) = with_states(surface.wl_surface(), |states| {
            let data = states
                .data_map
                .get::<XdgToplevelSurfaceData>()
                .and_then(|d| d.lock().ok());
            let class = data
                .as_ref()
                .and_then(|d| d.app_id.clone())
                .unwrap_or_default();
            let title = data
                .as_ref()
                .and_then(|d| d.title.clone())
                .unwrap_or_default();
            (class, title)
        });
        self.wm
            .add_toplevel_on(address.clone(), class, title, loc, self.primary_output_name());
        self.windows.insert(address.clone(), window.clone());
        self.space.map_element(window.clone(), loc, false);
        self.relayout_active();
        self.focus_address(&address);
        self.broadcast_event(&format!("openwindow>>{address}"));
        eprintln!("proteus-compositor-next: toplevel mapped: {address}");
    }

    fn new_popup(&mut self, surface: PopupSurface, _positioner: PositionerState) {
        self.unconstrain_popup(&surface);
        let _ = self.popups.track_popup(PopupKind::Xdg(surface));
    }

    fn toplevel_destroyed(&mut self, surface: ToplevelSurface) {
        let Some(addr) = self.address_for_surface(surface.wl_surface()) else {
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

    fn app_id_changed(&mut self, surface: ToplevelSurface) {
        let Some(addr) = self.address_for_surface(surface.wl_surface()) else {
            return;
        };
        let class = with_states(surface.wl_surface(), |states| {
            states
                .data_map
                .get::<XdgToplevelSurfaceData>()
                .and_then(|d| d.lock().ok())
                .and_then(|d| d.app_id.clone())
                .unwrap_or_default()
        });
        self.wm.set_class(&addr, class);
    }

    fn title_changed(&mut self, surface: ToplevelSurface) {
        let Some(addr) = self.address_for_surface(surface.wl_surface()) else {
            return;
        };
        let title = with_states(surface.wl_surface(), |states| {
            states
                .data_map
                .get::<XdgToplevelSurfaceData>()
                .and_then(|d| d.lock().ok())
                .and_then(|d| d.title.clone())
                .unwrap_or_default()
        });
        self.wm.set_title(&addr, title);
        self.broadcast_event("activewindow>>");
    }

    fn reposition_request(
        &mut self,
        surface: PopupSurface,
        positioner: PositionerState,
        token: u32,
    ) {
        surface.with_pending_state(|state| {
            let geometry = positioner.get_geometry();
            state.geometry = geometry;
            state.positioner = positioner;
        });
        self.unconstrain_popup(&surface);
        surface.send_repositioned(token);
    }

    fn move_request(&mut self, surface: ToplevelSurface, seat: wl_seat::WlSeat, serial: Serial) {
        let Some(seat) = Seat::from_resource(&seat) else {
            return;
        };
        let Some(pointer) = seat.get_pointer() else {
            return;
        };
        if !pointer.has_grab(serial) {
            return;
        }
        let Some(start_data) = pointer.grab_start_data() else {
            return;
        };
        if !focus_on_toplevel(&start_data, &surface) {
            return;
        }

        let wl = surface.wl_surface();
        let Some(window) = self
            .space
            .elements()
            .find(|w| w.toplevel().is_some_and(|t| t.wl_surface() == wl))
            .cloned()
        else {
            return;
        };
        let Some(initial_window_location) = self.space.element_location(&window) else {
            return;
        };
        let address = self.address_for_surface(wl);
        pointer.set_grab(
            self,
            MoveSurfaceGrab {
                start_data,
                window,
                initial_window_location,
                address,
            },
            serial,
            Focus::Clear,
        );
    }

    fn resize_request(
        &mut self,
        surface: ToplevelSurface,
        seat: wl_seat::WlSeat,
        serial: Serial,
        edges: smithay::reexports::wayland_protocols::xdg::shell::server::xdg_toplevel::ResizeEdge,
    ) {
        let Some(seat) = Seat::from_resource(&seat) else {
            return;
        };
        let Some(pointer) = seat.get_pointer() else {
            return;
        };
        if !pointer.has_grab(serial) {
            return;
        }
        let Some(start_data) = pointer.grab_start_data() else {
            return;
        };
        if !focus_on_toplevel(&start_data, &surface) {
            return;
        }

        let wl = surface.wl_surface();
        let Some(window) = self
            .space
            .elements()
            .find(|w| w.toplevel().is_some_and(|t| t.wl_surface() == wl))
            .cloned()
        else {
            return;
        };
        let Some(initial_window_location) = self.space.element_location(&window) else {
            return;
        };
        let geometry = window.geometry();
        let initial_rect = Rectangle::new(initial_window_location, geometry.size);
        let address = self.address_for_surface(wl);

        surface.with_pending_state(|state| {
            state.states.set(
                smithay::reexports::wayland_protocols::xdg::shell::server::xdg_toplevel::State::Resizing,
            );
        });
        surface.send_pending_configure();

        pointer.set_grab(
            self,
            ResizeSurfaceGrab {
                start_data,
                window,
                edges,
                initial_rect,
                address,
            },
            serial,
            Focus::Clear,
        );
    }

    fn grab(&mut self, surface: PopupSurface, seat: wl_seat::WlSeat, serial: Serial) {
        let Some(seat) = Seat::from_resource(&seat) else {
            return;
        };
        let kind = PopupKind::Xdg(surface);
        let Ok(root) = find_popup_root_surface(&kind) else {
            return;
        };
        match self.popups.grab_popup(root.clone(), kind, &seat, serial) {
            Ok(grab) => {
                if let Some(keyboard) = seat.get_keyboard() {
                    if keyboard.has_grab(serial) {
                        keyboard.set_focus(self, grab.current_grab(), serial);
                        keyboard.set_grab(self, PopupKeyboardGrab::new(&grab), serial);
                    }
                }
                if let Some(pointer) = seat.get_pointer() {
                    if pointer.has_grab(serial) {
                        let ret = pointer.grab_start_data();
                        pointer.motion(
                            self,
                            ret.as_ref().and_then(|s| s.focus.clone()),
                            &smithay::input::pointer::MotionEvent {
                                location: pointer.current_location(),
                                serial,
                                time: 0,
                            },
                        );
                        pointer.set_grab(self, PopupPointerGrab::new(&grab), serial, Focus::Keep);
                    }
                }
            }
            Err(err) => {
                eprintln!("proteus-compositor-next: popup grab denied: {err:?}");
            }
        }
    }
}

fn focus_on_toplevel(
    start_data: &PointerGrabStartData<CompositorNext>,
    surface: &ToplevelSurface,
) -> bool {
    let Some((focus, _)) = start_data.focus.as_ref() else {
        return false;
    };
    let mut surf = focus.clone();
    loop {
        if &surf == surface.wl_surface() {
            return true;
        }
        match get_parent(&surf) {
            Some(parent) => surf = parent,
            None => return false,
        }
    }
}

delegate_xdg_shell!(CompositorNext);

// ----------------------------------------------------------- xdg-decoration --

impl XdgDecorationHandler for CompositorNext {
    fn new_decoration(&mut self, toplevel: ToplevelSurface) {
        // Always CSD — GTK often *requests* ServerSide even when it draws its
        // own header; honoring that reserved a 28px SSD gap and let windows
        // feel like they sit under the dock/menu chrome.
        toplevel.with_pending_state(|state| {
            state.decoration_mode = Some(Mode::ClientSide);
        });
        toplevel.send_configure();
        self.sync_ssd_for_toplevel(&toplevel, false);
    }

    fn request_mode(&mut self, toplevel: ToplevelSurface, _mode: Mode) {
        // Ignore ServerSide asks — app chrome only (see new_decoration).
        toplevel.with_pending_state(|state| {
            state.decoration_mode = Some(Mode::ClientSide);
        });
        toplevel.send_configure();
        self.sync_ssd_for_toplevel(&toplevel, false);
    }

    fn unset_mode(&mut self, toplevel: ToplevelSurface) {
        toplevel.with_pending_state(|state| {
            state.decoration_mode = Some(Mode::ClientSide);
        });
        toplevel.send_configure();
        self.sync_ssd_for_toplevel(&toplevel, false);
    }
}

impl CompositorNext {
    fn sync_ssd_for_toplevel(&mut self, toplevel: &ToplevelSurface, ssd: bool) {
        let Some(addr) = self.address_for_surface(toplevel.wl_surface()) else {
            return;
        };
        let prev = self.wm.find(&addr).map(|t| t.ssd);
        self.wm.set_ssd(&addr, ssd);
        if prev != Some(ssd) {
            self.relayout_active();
        }
    }
}

delegate_xdg_decoration!(CompositorNext);

fn handle_xdg_commit(popups: &mut PopupManager, space: &Space<Window>, surface: &WlSurface) {
    if let Some(window) = space
        .elements()
        .find(|w| w.toplevel().is_some_and(|t| t.wl_surface() == surface))
        .cloned()
    {
        let initial_configure_sent = with_states(surface, |states| {
            states
                .data_map
                .get::<XdgToplevelSurfaceData>()
                .unwrap()
                .lock()
                .unwrap()
                .initial_configure_sent
        });
        if !initial_configure_sent {
            if let Some(toplevel) = window.toplevel() {
                toplevel.send_configure();
            }
        }
    }

    popups.commit(surface);
    if let Some(popup) = popups.find_popup(surface) {
        if let PopupKind::Xdg(ref xdg) = popup {
            if !xdg.is_initial_configure_sent() {
                xdg.send_configure().expect("initial configure failed");
            }
        }
    }
}

impl CompositorNext {
    fn unconstrain_popup(&self, popup: &PopupSurface) {
        let Ok(root) = find_popup_root_surface(&PopupKind::Xdg(popup.clone())) else {
            return;
        };
        let Some(window) = self
            .space
            .elements()
            .find(|w| w.toplevel().is_some_and(|t| t.wl_surface() == &root))
        else {
            return;
        };
        let Some(output) = self.space.outputs().next() else {
            return;
        };
        let Some(output_geo) = self.space.output_geometry(output) else {
            return;
        };
        let Some(window_geo) = self.space.element_geometry(window) else {
            return;
        };

        let mut target = output_geo;
        target.loc -= get_popup_toplevel_coords(&PopupKind::Xdg(popup.clone()));
        target.loc -= window_geo.loc;

        popup.with_pending_state(|state| {
            state.geometry = state.positioner.get_unconstrained_geometry(target);
        });
    }

    /// Send the initial layer-shell configure once the surface committed
    /// (wlr-layer-shell requires configure after the first commit).
    fn handle_layer_commit(&mut self, surface: &WlSurface) {
        let outputs: Vec<Output> = self.space.outputs().cloned().collect();
        let mut need_relayout = false;
        for output in outputs {
            let initial = {
                let mut map = layer_map_for_output(&output);
                let Some(layer) = map
                    .layer_for_surface(surface, WindowSurfaceType::ALL)
                    .cloned()
                else {
                    continue;
                };
                map.arrange();
                need_relayout = true;
                let initial_configure_sent = with_states(surface, |states| {
                    states
                        .data_map
                        .get::<LayerSurfaceData>()
                        .map(|d| d.lock().unwrap().initial_configure_sent)
                        .unwrap_or(true)
                });
                if !initial_configure_sent {
                    Some(layer)
                } else {
                    None
                }
            };
            if let Some(layer) = initial {
                layer.layer_surface().send_configure();
            }
            break;
        }
        if need_relayout {
            self.relayout_active();
        }
    }
}

// ------------------------------------------------------------- layer-shell --

impl WlrLayerShellHandler for CompositorNext {
    fn shell_state(&mut self) -> &mut WlrLayerShellState {
        &mut self.layer_shell_state
    }

    fn new_layer_surface(
        &mut self,
        surface: WlrLayerSurface,
        wl_output: Option<WlOutput>,
        _layer: Layer,
        namespace: String,
    ) {
        let output = wl_output
            .as_ref()
            .and_then(Output::from_resource)
            .or_else(|| self.space.outputs().next().cloned());
        let Some(output) = output else {
            surface.send_close();
            return;
        };
        let mut map = layer_map_for_output(&output);
        let layer_surface = LayerSurface::new(surface, namespace.clone());
        match map.map_layer(&layer_surface) {
            // Prove marker for the nested spike gate ("bar+dock map").
            Ok(()) => eprintln!("proteus-compositor-next: layer mapped: {namespace}"),
            Err(e) => eprintln!("proteus-compositor-next: map_layer failed ({namespace}): {e}"),
        }
        drop(map);
        self.relayout_active();
    }

    fn layer_destroyed(&mut self, surface: WlrLayerSurface) {
        let outputs: Vec<Output> = self.space.outputs().cloned().collect();
        for output in outputs {
            let mut map = layer_map_for_output(&output);
            let layer = map
                .layers()
                .find(|l| l.layer_surface() == &surface)
                .cloned();
            if let Some(layer) = layer {
                map.unmap_layer(&layer);
            }
        }
        self.relayout_active();
    }
}

delegate_layer_shell!(CompositorNext);

// wlr-screencopy Dispatch/GlobalDispatch live on CompositorNext in screencopy.rs.
