//! Compositor state — smallvil-derived (smithay 0.7) + wlr-layer-shell.

use std::{
    collections::{HashMap, HashSet},
    ffi::OsString,
    path::PathBuf,
    sync::{Arc, Mutex},
};

use smithay::wayland::session_lock::{LockSurface, SessionLocker};

use smithay::{
    desktop::{PopupManager, Space, Window, WindowSurfaceType},
    input::{Seat, SeatState},
    reexports::{
        calloop::{generic::Generic, EventLoop, Interest, LoopSignal, Mode, PostAction},
        wayland_server::{
            backend::{ClientData, ClientId, DisconnectReason},
            protocol::wl_surface::WlSurface,
            Client, Display, DisplayHandle,
        },
    },
    utils::{Logical, Point},
    wayland::{
        compositor::{CompositorClientState, CompositorState},
        dmabuf::{DmabufGlobal, DmabufState},
        fractional_scale::FractionalScaleManagerState,
        output::OutputManagerState,
        selection::data_device::DataDeviceState,
        shell::{
            wlr_layer::WlrLayerShellState,
            xdg::{decoration::XdgDecorationState, XdgShellState},
        },
        session_lock::SessionLockManagerState,
        shm::ShmState,
        socket::ListeningSocketSource,
        viewporter::ViewporterState,
        xwayland_shell::XWaylandShellState,
    },
    xwayland::X11Wm,
};

use crate::ctl::CtlSubscribers;
use crate::screencopy::{CapturedFrame, PendingScreencopy};
use crate::wm::Wm;
use crate::CalloopData;

pub struct CompositorNext {
    pub start_time: std::time::Instant,
    pub socket_name: OsString,
    pub display_handle: DisplayHandle,

    pub space: Space<Window>,
    pub loop_signal: LoopSignal,

    pub compositor_state: CompositorState,
    pub xdg_shell_state: XdgShellState,
    pub xdg_decoration_state: XdgDecorationState,
    pub layer_shell_state: WlrLayerShellState,
    pub viewporter_state: ViewporterState,
    pub fractional_scale_state: FractionalScaleManagerState,
    pub shm_state: ShmState,
    pub dmabuf_state: DmabufState,
    pub dmabuf_global: Option<DmabufGlobal>,
    pub output_manager_state: OutputManagerState,
    pub seat_state: SeatState<CompositorNext>,
    pub data_device_state: DataDeviceState,
    pub popups: PopupManager,

    pub seat: Seat<Self>,

    /// Workspace / toplevel roster (IPC contract).
    pub wm: Wm,
    /// All known xdg/X11 windows (including unmapped / minimized).
    pub windows: HashMap<String, Window>,
    pub ctl_path: Option<PathBuf>,
    pub ctl_subscribers: CtlSubscribers,

    pub xwayland_shell_state: XWaylandShellState,
    pub xwm: Option<X11Wm>,
    pub xwayland_client: Option<Client>,
    /// X11 display number once Xwayland is Ready (`DISPLAY=:{n}`).
    pub x11_display: Option<u32>,

    /// Last rendered output frame for wlr-screencopy / grim.
    pub last_frame: Option<CapturedFrame>,
    pub pending_screencopies: Vec<PendingScreencopy>,
    /// SSD titlebar font + MemoryRenderBuffer cache.
    pub ssd_chrome: crate::decoration::SsdChrome,
    /// Last LMB on SSD titlebar body (double-click maximize).
    pub ssd_last_titlebar_click: Option<crate::decoration::SsdTitlebarClick>,
    /// Pointer over close/max/min cell.
    pub ssd_hover: Option<(String, crate::decoration::SsdChromePart)>,
    /// LMB held on close/max/min cell.
    pub ssd_pressed: Option<(String, crate::decoration::SsdChromePart)>,
    /// Soft pointer cursor (default arrow).
    pub cursor: crate::cursor::CursorState,
    /// Identify flash deadline + badge cache.
    pub identify_until: Option<std::time::Instant>,
    pub identify_chrome: crate::identify::IdentifyChrome,
    /// DRM backend runtime (set by `init_drm`); enables live modeset.
    pub(crate) drm_runtime: Option<std::rc::Rc<std::cell::RefCell<crate::drm::DrmRuntime>>>,
    /// Session keybind table (defaults + keybinds.json).
    pub binds: crate::binds::BindsState,
    /// Pointer / touchpad Facts (`settings.json`); live via `input-reload`.
    pub input_config: crate::input_config::InputConfig,

    /// ext-session-lock-v1 global + locked output list (Smithay).
    pub session_lock_state: SessionLockManagerState,
    /// Lock surfaces per output (shell / proteus-session-lock).
    pub lock_surfaces: Vec<(smithay::output::Output, LockSurface)>,
    /// Session lock confirmed by the client.
    pub session_locked: bool,
    /// Waiting for a blank frame before `SessionLocker::lock()`.
    pub session_lock_pending: bool,
    pub pending_locker: Option<SessionLocker>,
    pub pending_lock_blank_outputs: HashSet<String>,
}

impl CompositorNext {
    pub fn new(
        event_loop: &mut EventLoop<'static, CalloopData>,
        display: Display<Self>,
        seat_name: &str,
    ) -> Self {
        let start_time = std::time::Instant::now();
        let dh = display.handle();

        let compositor_state = CompositorState::new::<Self>(&dh);
        let xdg_shell_state = XdgShellState::new::<Self>(&dh);
        let xdg_decoration_state = XdgDecorationState::new::<Self>(&dh);
        let layer_shell_state = WlrLayerShellState::new::<Self>(&dh);
        // iced_layershell clients hard-require wp_viewporter (hidpi path).
        let viewporter_state = ViewporterState::new::<Self>(&dh);
        let fractional_scale_state = FractionalScaleManagerState::new::<Self>(&dh);
        let shm_state = ShmState::new::<Self>(&dh, vec![]);
        let dmabuf_state = DmabufState::new();
        let output_manager_state = OutputManagerState::new_with_xdg_output::<Self>(&dh);
        let mut seat_state = SeatState::new();
        let data_device_state = DataDeviceState::new::<Self>(&dh);
        let popups = PopupManager::default();
        let xwayland_shell_state = XWaylandShellState::new::<Self>(&dh);
        let session_lock_state = SessionLockManagerState::new::<Self, _>(&dh, |_| true);

        let mut seat: Seat<Self> = seat_state.new_wl_seat(&dh, seat_name);
        // Repeat delay/rate — slightly conservative so iced text fields and
        // lock wake don't feel hair-trigger under nested/VM input.
        seat.add_keyboard(Default::default(), 400, 25).unwrap();
        seat.add_pointer();

        let space = Space::default();
        let socket_name = Self::init_wayland_listener(display, event_loop);
        let loop_signal = event_loop.get_signal();

        Self {
            start_time,
            display_handle: dh,
            space,
            loop_signal,
            socket_name,
            compositor_state,
            xdg_shell_state,
            xdg_decoration_state,
            layer_shell_state,
            viewporter_state,
            fractional_scale_state,
            shm_state,
            dmabuf_state,
            dmabuf_global: None,
            output_manager_state,
            seat_state,
            data_device_state,
            popups,
            seat,
            wm: {
                let mut wm = Wm::new();
                let path = crate::input_config::InputConfig::settings_fact_path();
                if let Ok(raw) = std::fs::read_to_string(&path) {
                    wm.load_workspace_names_from_settings(&raw);
                }
                wm
            },
            windows: HashMap::new(),
            ctl_path: None,
            ctl_subscribers: Arc::new(Mutex::new(Vec::new())),
            xwayland_shell_state,
            xwm: None,
            xwayland_client: None,
            x11_display: None,
            last_frame: None,
            pending_screencopies: Vec::new(),
            ssd_chrome: crate::decoration::SsdChrome::default(),
            ssd_last_titlebar_click: None,
            ssd_hover: None,
            ssd_pressed: None,
            cursor: crate::cursor::CursorState::default(),
            identify_until: None,
            identify_chrome: crate::identify::IdentifyChrome::default(),
            drm_runtime: None,
            binds: crate::binds::BindsState::load(),
            input_config: crate::input_config::InputConfig::load(),
            session_lock_state,
            lock_surfaces: Vec::new(),
            session_locked: false,
            session_lock_pending: false,
            pending_locker: None,
            pending_lock_blank_outputs: HashSet::new(),
        }
    }

    fn init_wayland_listener(
        display: Display<CompositorNext>,
        event_loop: &mut EventLoop<'static, CalloopData>,
    ) -> OsString {
        let listening_socket = ListeningSocketSource::new_auto().unwrap();
        let socket_name = listening_socket.socket_name().to_os_string();
        let loop_handle = event_loop.handle();

        loop_handle
            .insert_source(listening_socket, move |client_stream, _, state| {
                state
                    .display_handle
                    .insert_client(client_stream, Arc::new(ClientState::default()))
                    .unwrap();
            })
            .expect("Failed to init the wayland event source.");

        loop_handle
            .insert_source(
                Generic::new(display, Interest::READ, Mode::Level),
                |_, display, state| {
                    // Safety: we don't drop the display
                    unsafe {
                        display.get_mut().dispatch_clients(&mut state.state).unwrap();
                    }
                    Ok(PostAction::Continue)
                },
            )
            .unwrap();

        socket_name
    }

    /// Input target under the pointer — layer surfaces (top/overlay have
    /// priority over windows), then space windows.
    pub fn surface_under(
        &self,
        pos: Point<f64, Logical>,
    ) -> Option<(WlSurface, Point<f64, Logical>)> {
        if let Some(hit) = self.lock_surface_under(pos) {
            return Some(hit);
        }
        if self.session_lock_active() {
            return None;
        }

        use smithay::desktop::layer_map_for_output;
        use smithay::wayland::shell::wlr_layer::Layer;

        let output = self.space.outputs().next()?;
        let output_geo = self.space.output_geometry(output)?;
        let map = layer_map_for_output(output);
        for layer_kind in [Layer::Overlay, Layer::Top] {
            if let Some(layer) = map
                .layer_under(layer_kind, pos - output_geo.loc.to_f64())
                .cloned()
            {
                let layer_loc = map.layer_geometry(&layer)?.loc;
                let inner = pos - output_geo.loc.to_f64() - layer_loc.to_f64();
                if let Some((s, p)) = layer.surface_under(inner, WindowSurfaceType::ALL) {
                    return Some((
                        s,
                        (p + layer_loc + output_geo.loc).to_f64(),
                    ));
                }
            }
        }
        drop(map);

        self.space.element_under(pos).and_then(|(window, location)| {
            window
                .surface_under(pos - location.to_f64(), WindowSurfaceType::ALL)
                .map(|(s, p)| (s, (p + location).to_f64()))
        })
    }
}

#[derive(Default)]
pub struct ClientState {
    pub compositor_state: CompositorClientState,
}

impl ClientData for ClientState {
    fn initialized(&self, _client_id: ClientId) {}
    fn disconnected(&self, _client_id: ClientId, _reason: DisconnectReason) {}
}
