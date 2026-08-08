//! DRM / libseat backend — VT/VM prove (`--backend drm`); shipping session
//! default via proteus-session (Hyprland fail-closed).

use std::{
    cell::RefCell,
    collections::{HashMap, HashSet},
    rc::Rc,
    time::Duration,
};

use smithay::{
    backend::{
        allocator::{
            gbm::{GbmAllocator, GbmBufferFlags, GbmDevice},
            Fourcc,
        },
        drm::{DrmDevice, DrmDeviceFd, DrmEvent, DrmNode, GbmBufferedSurface, NodeType},
        egl::{EGLContext, EGLDisplay},
        libinput::{LibinputInputBackend, LibinputSessionInterface},
        renderer::{
            damage::OutputDamageTracker,
            element::memory::MemoryRenderBufferRenderElement,
            gles::{GlesRenderer, GlesTexture},
            Bind, ExportMem, Offscreen,
        },
        session::{
            libseat::{LibSeatSession, LibSeatSessionNotifier},
            Event as SessionEvent, Session,
        },
        udev::{all_gpus, primary_gpu, UdevBackend, UdevEvent},
    },
    desktop::layer_map_for_output,
    output::{Mode as WlMode, Output, PhysicalProperties, Subpixel},
    reexports::{
        calloop::EventLoop,
        drm::control::{connector, crtc, Device as ControlDevice, Mode, ModeTypeFlags},
        input::Libinput,
        rustix::fs::OFlags,
        wayland_server::DisplayHandle,
    },
    utils::{Buffer, DeviceFd, Rectangle, Size, Transform},
};

use crate::dmabuf_init::init_dmabuf_global;
use crate::screencopy::{prepare_screencopy_pixels, CapturedFrame};
use crate::winit::abgr_to_xrgb;
use crate::{CalloopData, CompositorNext};

type RenderSurface = GbmBufferedSurface<GbmAllocator<DrmDeviceFd>, ()>;

struct OutputSurface {
    surface: RenderSurface,
    output: Output,
    damage_tracker: OutputDamageTracker,
    capture_damage: OutputDamageTracker,
    connector: connector::Handle,
}

pub(crate) struct DrmRuntime {
    drm: DrmDevice,
    gbm: GbmDevice<DrmDeviceFd>,
    renderer: GlesRenderer,
    surfaces: HashMap<crtc::Handle, OutputSurface>,
    /// Primary for tiling (first connected / lowest name).
    primary_crtc: Option<crtc::Handle>,
    /// Primary GPU device id (for udev hotplug filter).
    node_dev_id: u64,
    /// Path used to open DRM (for virtio transform heuristic).
    node_path: Option<std::path::PathBuf>,
}

/// Match connector DRM mode to WxH[@Hz]; apply via GbmBufferedSurface::use_mode.
pub(crate) fn apply_output_mode(
    runtime: &Rc<RefCell<DrmRuntime>>,
    state: &mut CompositorNext,
    name: &str,
    width: u32,
    height: u32,
    refresh_hz: Option<f64>,
) -> Result<(), String> {
    let mut rt = runtime.borrow_mut();
    let crtc = rt
        .surfaces
        .iter()
        .find(|(_, s)| s.output.name() == name)
        .map(|(c, _)| *c)
        .ok_or_else(|| format!("unknown output {name}"))?;

    let conn = rt.surfaces[&crtc].connector;
    let info = ControlDevice::get_connector(&rt.drm, conn, false)
        .map_err(|e| format!("connector: {e}"))?;
    let Some(drm_mode) = pick_mode_from_list(info.modes(), width, height, refresh_hz) else {
        return Err(format!(
            "no DRM mode matching {width}x{height}{}",
            refresh_hz
                .map(|h| format!("@{h}"))
                .unwrap_or_default()
        ));
    };

    {
        let surf = rt
            .surfaces
            .get_mut(&crtc)
            .ok_or_else(|| format!("missing surface {name}"))?;
        surf.surface
            .use_mode(drm_mode)
            .map_err(|e| format!("use_mode: {e}"))?;
        let wl_mode = WlMode::from(drm_mode);
        surf.output
            .change_current_state(Some(wl_mode), None, None, None);
        surf.output.set_preferred(wl_mode);
        surf.damage_tracker = OutputDamageTracker::from_output(&surf.output);
        surf.capture_damage = OutputDamageTracker::from_output(&surf.output);
        layer_map_for_output(&surf.output).arrange();
    }
    drop(rt);
    state.relayout_active();
    Ok(())
}

fn pick_mode_from_list(
    modes: &[Mode],
    width: u32,
    height: u32,
    refresh_hz: Option<f64>,
) -> Option<Mode> {
    let candidates: Vec<Mode> = modes
        .iter()
        .copied()
        .filter(|m| {
            let (w, h) = m.size();
            w == width as u16 && h == height as u16
        })
        .collect();
    if candidates.is_empty() {
        return None;
    }
    let Some(want_hz) = refresh_hz else {
        return candidates.into_iter().next();
    };
    candidates.into_iter().min_by(|a, b| {
        let ah = a.vrefresh() as f64;
        let bh = b.vrefresh() as f64;
        (ah - want_hz)
            .abs()
            .partial_cmp(&(bh - want_hz).abs())
            .unwrap_or(std::cmp::Ordering::Equal)
    })
}

/// Open libseat before constructing compositor state (seat name).
pub fn open_session() -> Result<(LibSeatSession, LibSeatSessionNotifier), Box<dyn std::error::Error>>
{
    LibSeatSession::new().map_err(|e| format!("libseat session: {e}").into())
}

pub fn init_drm(
    event_loop: &mut EventLoop<'static, CalloopData>,
    data: &mut CalloopData,
    mut session: LibSeatSession,
    notifier: LibSeatSessionNotifier,
) -> Result<(), Box<dyn std::error::Error>> {
    let seat_name = session.seat();
    let display_handle = data.display_handle.clone();

    let primary = resolve_primary_gpu(&session)?;
    // Enumerate all GPUs for dogfood / multi-GPU readiness (still single-device open).
    {
        let seat = session.seat();
        match all_gpus(&seat) {
            Ok(gpus) => {
                let list: Vec<String> = gpus
                    .iter()
                    .map(|p| p.display().to_string())
                    .collect();
                eprintln!(
                    "proteus-compositor: drm enumerate gpus ({}): {}",
                    list.len(),
                    if list.is_empty() {
                        "(none)".into()
                    } else {
                        list.join(", ")
                    }
                );
            }
            Err(e) => eprintln!("proteus-compositor: drm enumerate gpus failed: {e}"),
        }
    }
    eprintln!(
        "proteus-compositor: drm primary gpu {}",
        primary
            .dev_path()
            .map(|p| p.display().to_string())
            .unwrap_or_else(|| primary.to_string())
    );

    let path = primary
        .dev_path()
        .ok_or("drm node has no device path")?;
    let fd = session.open(
        &path,
        OFlags::RDWR | OFlags::CLOEXEC | OFlags::NOCTTY | OFlags::NONBLOCK,
    )?;
    let device_fd = DrmDeviceFd::new(DeviceFd::from(fd));
    let (drm, drm_notifier) = DrmDevice::new(device_fd.clone(), true)?;
    let gbm = GbmDevice::new(device_fd)?;

    let egl = unsafe { EGLDisplay::new(gbm.clone())? };
    let context = EGLContext::new(&egl)?;
    let renderer = unsafe { GlesRenderer::new(context)? };

    init_dmabuf_global(&mut data.state, &display_handle, &renderer)?;

    let node_dev_id = primary.dev_id() as u64;
    let node_path = primary.dev_path();
    let runtime = Rc::new(RefCell::new(DrmRuntime {
        drm,
        gbm,
        renderer,
        surfaces: HashMap::new(),
        primary_crtc: None,
        node_dev_id,
        node_path,
    }));

    {
        let mut rt = runtime.borrow_mut();
        sync_connectors(&mut rt, &display_handle, &mut data.state)?;
        if rt.surfaces.is_empty() {
            return Err("no connected DRM connector with free CRTC".into());
        }
    }

    data.state.drm_runtime = Some(runtime.clone());
    // Scale / remaining Fact fields after connectors exist (positions applied in rearrange).
    data.state.apply_displays_fact();

    std::env::set_var("WAYLAND_DISPLAY", &data.state.socket_name);
    std::env::set_var("XDG_CURRENT_DESKTOP", "wlroots");

    let mut libinput_context =
        Libinput::new_with_udev::<LibinputSessionInterface<LibSeatSession>>(session.clone().into());
    libinput_context
        .udev_assign_seat(&seat_name)
        .map_err(|()| "libinput udev_assign_seat failed")?;
    let libinput_backend = LibinputInputBackend::new(libinput_context.clone());

    event_loop
        .handle()
        .insert_source(libinput_backend, move |event, _, data| {
            data.state.process_input_event(event);
        })?;

    let runtime_vblank = runtime.clone();
    event_loop.handle().insert_source(drm_notifier, move |event, _, data| {
        match event {
            DrmEvent::VBlank(event_crtc) => {
                if let Some(surf) = runtime_vblank.borrow_mut().surfaces.get_mut(&event_crtc) {
                    let _ = surf.surface.frame_submitted();
                }
                if let Err(e) = render_drm_crtc(&runtime_vblank, data, event_crtc) {
                    eprintln!("proteus-compositor: drm render: {e}");
                }
            }
            DrmEvent::Error(err) => {
                eprintln!("proteus-compositor: drm error: {err:?}");
            }
        }
    })?;

    let runtime_session = runtime.clone();
    event_loop
        .handle()
        .insert_source(notifier, move |event, _, _data| match event {
            SessionEvent::PauseSession => {
                eprintln!("proteus-compositor: drm session pause");
                libinput_context.suspend();
                runtime_session.borrow_mut().drm.pause();
            }
            SessionEvent::ActivateSession => {
                eprintln!("proteus-compositor: drm session activate");
                if let Err(e) = libinput_context.resume() {
                    eprintln!("proteus-compositor: libinput resume: {e:?}");
                }
                if let Err(e) = runtime_session.borrow_mut().drm.activate(false) {
                    eprintln!("proteus-compositor: drm activate: {e:?}");
                }
            }
        })?;

    // Udev hotplug — rescan connectors on primary GPU changes.
    let udev = UdevBackend::new(&seat_name).map_err(|e| format!("udev backend: {e}"))?;
    let runtime_udev = runtime.clone();
    let dh_udev = display_handle.clone();
    event_loop
        .handle()
        .insert_source(udev, move |event, _, data| {
            let ours = runtime_udev.borrow().node_dev_id;
            let relevant = match &event {
                UdevEvent::Added { device_id, .. }
                | UdevEvent::Changed { device_id }
                | UdevEvent::Removed { device_id } => *device_id as u64 == ours,
            };
            if !relevant {
                return;
            }
            eprintln!("proteus-compositor: drm udev hotplug {event:?}");
            let mut rt = runtime_udev.borrow_mut();
            if let Err(e) = sync_connectors(&mut rt, &dh_udev, &mut data.state) {
                eprintln!("proteus-compositor: connector sync: {e}");
            }
            data.state.relayout_active();
        })?;

    // First frames for all outputs.
    let crtcs: Vec<_> = runtime.borrow().surfaces.keys().copied().collect();
    for crtc in crtcs {
        if let Err(e) = render_drm_crtc(&runtime, data, crtc) {
            eprintln!("proteus-compositor: drm initial render: {e}");
        }
    }

    Ok(())
}

fn resolve_primary_gpu(session: &LibSeatSession) -> Result<DrmNode, Box<dyn std::error::Error>> {
    // Hard override: PROTEUS_DRM_DEVICE=/dev/dri/cardN (or render node path).
    if let Ok(path) = std::env::var("PROTEUS_DRM_DEVICE") {
        let path = path.trim();
        if path.is_empty() {
            return Err("PROTEUS_DRM_DEVICE is set but empty".into());
        }
        eprintln!("proteus-compositor: drm using PROTEUS_DRM_DEVICE={path}");
        return DrmNode::from_path(path).map_err(|e| {
            format!("PROTEUS_DRM_DEVICE={path} open failed: {e}").into()
        });
    }
    let seat = session.seat();
    if let Some(path) = primary_gpu(&seat)? {
        if let Ok(node) = DrmNode::from_path(&path) {
            // Prefer Primary (card) for GBM scanout. Render nodes (renderD*)
            // fail open/modeset under virtio-gpu/VirGL in the QEMU guest.
            if let Some(Ok(primary)) = node.node_with_type(NodeType::Primary) {
                return Ok(primary);
            }
            return Ok(node);
        }
    }
    for path in all_gpus(&seat)? {
        if let Ok(node) = DrmNode::from_path(&path) {
            if let Some(Ok(primary)) = node.node_with_type(NodeType::Primary) {
                return Ok(primary);
            }
            return Ok(node);
        }
    }
    Err("no DRM GPU found for seat".into())
}

/// Parse `PROTEUS_DRM_TRANSFORM` (default Normal).
/// Virtio-gpu/VirGL orientation varies by host GL; override when the panel
/// looks flipped: `180`, `flipped`, `flipped180`, etc.
fn resolve_drm_output_transform(node_path: Option<&std::path::Path>) -> Transform {
    let raw = std::env::var("PROTEUS_DRM_TRANSFORM").unwrap_or_default();
    let raw = raw.trim();
    if raw.is_empty() {
        if node_path.is_some_and(is_virtio_gpu_node) {
            eprintln!(
                "proteus-compositor: virtio-gpu — transform=Normal (set PROTEUS_DRM_TRANSFORM=180|flipped if upside-down)"
            );
        }
        return Transform::Normal;
    }
    let t = match raw.to_ascii_lowercase().as_str() {
        "normal" | "0" => Transform::Normal,
        "90" => Transform::_90,
        "180" => Transform::_180,
        "270" => Transform::_270,
        "flipped" | "flip" => Transform::Flipped,
        "flipped180" | "flip180" => Transform::Flipped180,
        "flipped90" => Transform::Flipped90,
        "flipped270" => Transform::Flipped270,
        other => {
            eprintln!(
                "proteus-compositor: unknown PROTEUS_DRM_TRANSFORM={other} — Normal"
            );
            Transform::Normal
        }
    };
    eprintln!("proteus-compositor: drm output transform={t:?} (env)");
    t
}

fn is_virtio_gpu_node(path: &std::path::Path) -> bool {
    let Some(name) = path.file_name().and_then(|s| s.to_str()) else {
        return false;
    };
    // /dev/dri/card1 → /sys/class/drm/card1/device/driver
    let driver = std::path::PathBuf::from(format!("/sys/class/drm/{name}/device/driver"));
    if let Ok(link) = std::fs::read_link(&driver) {
        let s = link.to_string_lossy();
        if s.contains("virtio") {
            return true;
        }
    }
    // Fallback: modalias / uevent
    if let Ok(uevent) = std::fs::read_to_string(format!("/sys/class/drm/{name}/device/uevent")) {
        if uevent.to_ascii_lowercase().contains("virtio") {
            return true;
        }
    }
    false
}

fn is_non_desktop(drm: &DrmDevice, conn: connector::Handle) -> bool {
    let Ok(props) = ControlDevice::get_properties(drm, conn) else {
        return false;
    };
    for (handle, value) in props {
        let Ok(info) = ControlDevice::get_property(drm, handle) else {
            continue;
        };
        if info.name().to_str() == Ok("non-desktop") {
            return info
                .value_type()
                .convert_value(value)
                .as_boolean()
                .unwrap_or(false);
        }
    }
    false
}

fn pick_crtc_for_connector(
    drm: &DrmDevice,
    info: &connector::Info,
    claimed: &HashSet<crtc::Handle>,
) -> Option<crtc::Handle> {
    let resources = ControlDevice::resource_handles(drm).ok()?;
    let mut crtc_candidate = None;
    if let Some(enc_handle) = info.current_encoder() {
        if let Ok(enc) = ControlDevice::get_encoder(drm, enc_handle) {
            if let Some(c) = enc.crtc() {
                if !claimed.contains(&c) {
                    crtc_candidate = Some(c);
                }
            }
            if crtc_candidate.is_none() {
                crtc_candidate = resources
                    .filter_crtcs(enc.possible_crtcs())
                    .into_iter()
                    .find(|c| !claimed.contains(c));
            }
        }
    }
    if crtc_candidate.is_none() {
        for &enc_handle in info.encoders() {
            let Ok(enc) = ControlDevice::get_encoder(drm, enc_handle) else {
                continue;
            };
            if let Some(c) = resources
                .filter_crtcs(enc.possible_crtcs())
                .into_iter()
                .find(|c| !claimed.contains(c))
            {
                crtc_candidate = Some(c);
                break;
            }
        }
    }
    crtc_candidate
}

fn sync_connectors(
    rt: &mut DrmRuntime,
    display_handle: &DisplayHandle,
    state: &mut CompositorNext,
) -> Result<(), Box<dyn std::error::Error>> {
    let resources = ControlDevice::resource_handles(&rt.drm)?;
    let mut wanted: HashMap<connector::Handle, (connector::Info, Mode, crtc::Handle)> =
        HashMap::new();
    let mut claimed: HashSet<crtc::Handle> = HashSet::new();

    // Prefer keeping existing crtc assignments.
    for (crtc, surf) in &rt.surfaces {
        claimed.insert(*crtc);
        let Ok(info) = ControlDevice::get_connector(&rt.drm, surf.connector, true) else {
            continue;
        };
        if info.state() == connector::State::Connected && !info.modes().is_empty() {
            let out_name = format!("{}-{}", info.interface().as_str(), info.interface_id());
            let mode = mode_for_connector(info.modes(), &out_name)
                .unwrap_or_else(|| {
                    info.modes()
                        .iter()
                        .find(|m| m.mode_type().contains(ModeTypeFlags::PREFERRED))
                        .copied()
                        .unwrap_or(info.modes()[0])
                });
            wanted.insert(surf.connector, (info, mode, *crtc));
        }
    }

    for &conn_handle in resources.connectors() {
        if wanted.contains_key(&conn_handle) {
            continue;
        }
        let info = ControlDevice::get_connector(&rt.drm, conn_handle, true)?;
        if info.state() != connector::State::Connected || info.modes().is_empty() {
            continue;
        }
        if is_non_desktop(&rt.drm, conn_handle) {
            continue;
        }
        let out_name = format!("{}-{}", info.interface().as_str(), info.interface_id());
        let mode = mode_for_connector(info.modes(), &out_name).unwrap_or_else(|| {
            info.modes()
                .iter()
                .find(|m| m.mode_type().contains(ModeTypeFlags::PREFERRED))
                .copied()
                .unwrap_or(info.modes()[0])
        });
        let Some(crtc) = pick_crtc_for_connector(&rt.drm, &info, &claimed) else {
            continue;
        };
        claimed.insert(crtc);
        wanted.insert(conn_handle, (info, mode, crtc));
    }

    // Remove disconnected.
    let existing_conns: Vec<_> = rt
        .surfaces
        .iter()
        .map(|(c, s)| (*c, s.connector, s.output.clone()))
        .collect();
    for (crtc, conn, output) in existing_conns {
        if !wanted.contains_key(&conn) {
            eprintln!(
                "proteus-compositor: drm disconnect {}",
                output.name()
            );
            state.space.unmap_output(&output);
            // Destroy output global by dropping Output after unmap.
            rt.surfaces.remove(&crtc);
            if rt.primary_crtc == Some(crtc) {
                rt.primary_crtc = None;
            }
        }
    }

    // Add new.
    for (conn, (info, mode, crtc)) in &wanted {
        if rt.surfaces.contains_key(crtc) {
            continue;
        }
        match create_output_surface(rt, display_handle, info, *mode, *crtc, *conn) {
            Ok(surf) => {
                eprintln!(
                    "proteus-compositor: drm connect {}",
                    surf.output.name()
                );
                rt.surfaces.insert(*crtc, surf);
            }
            Err(e) => eprintln!("proteus-compositor: map connector failed: {e}"),
        }
    }

    rearrange_outputs(rt, state);
    Ok(())
}

fn create_output_surface(
    rt: &mut DrmRuntime,
    display_handle: &DisplayHandle,
    info: &connector::Info,
    drm_mode: Mode,
    crtc: crtc::Handle,
    conn: connector::Handle,
) -> Result<OutputSurface, Box<dyn std::error::Error>> {
    let surface = rt.drm.create_surface(crtc, drm_mode, &[conn])?;
    let allocator =
        GbmAllocator::new(rt.gbm.clone(), GbmBufferFlags::RENDERING | GbmBufferFlags::SCANOUT);
    let render_formats = rt.renderer.egl_context().dmabuf_render_formats().clone();
    let gbm_surface = GbmBufferedSurface::new(
        surface,
        allocator,
        &[Fourcc::Argb8888, Fourcc::Xrgb8888],
        render_formats.iter().copied(),
    )?;

    let wl_mode = WlMode::from(drm_mode);
    let (phys_w, phys_h) = info.size().unwrap_or((0, 0));
    let output_name = format!("{}-{}", info.interface().as_str(), info.interface_id());
    let output = Output::new(
        output_name,
        PhysicalProperties {
            size: (phys_w as i32, phys_h as i32).into(),
            subpixel: Subpixel::Unknown,
            make: "Proteus".into(),
            model: "compositor-drm".into(),
        },
    );
    let _global = output.create_global::<CompositorNext>(display_handle);
    let transform = resolve_drm_output_transform(rt.node_path.as_deref());
    output.change_current_state(Some(wl_mode), Some(transform), None, Some((0, 0).into()));
    output.set_preferred(wl_mode);

    let damage_tracker = OutputDamageTracker::from_output(&output);
    let capture_damage = OutputDamageTracker::from_output(&output);

    Ok(OutputSurface {
        surface: gbm_surface,
        output,
        damage_tracker,
        capture_damage,
        connector: conn,
    })
}

fn mode_for_connector(modes: &[Mode], output_name: &str) -> Option<Mode> {
    let facts = crate::displays::load_displays_fact();
    let fact = facts.iter().find(|f| f.name == output_name)?;
    if fact.width == 0 || fact.height == 0 {
        return None;
    }
    pick_mode_from_list(modes, fact.width, fact.height, Some(fact.refresh_rate))
}

fn rearrange_outputs(rt: &mut DrmRuntime, state: &mut CompositorNext) {
    let mut entries: Vec<(crtc::Handle, String, Size<i32, smithay::utils::Physical>)> = rt
        .surfaces
        .iter()
        .map(|(crtc, s)| {
            let size = s
                .output
                .current_mode()
                .map(|m| m.size)
                .unwrap_or_else(|| (0, 0).into());
            (*crtc, s.output.name(), size)
        })
        .collect();
    entries.sort_by(|a, b| a.1.cmp(&b.1));

    rt.primary_crtc = entries.first().map(|(c, _, _)| *c);

    let names: Vec<String> = entries.iter().map(|(_, n, _)| n.clone()).collect();
    let facts = crate::displays::load_displays_fact();
    let use_fact_pos = crate::displays::facts_cover_all_outputs(&facts, &names);

    if use_fact_pos {
        for (crtc, name, _) in &entries {
            if let Some(surf) = rt.surfaces.get(crtc) {
                let (x, y) = facts
                    .iter()
                    .find(|f| f.name == *name)
                    .map(|f| (f.x, f.y))
                    .unwrap_or((0, 0));
                state.space.map_output(&surf.output, (x, y));
                state.wm.ensure_output(&surf.output.name());
                layer_map_for_output(&surf.output).arrange();
            }
        }
        return;
    }

    let mut x = 0i32;
    for (crtc, _, size) in &entries {
        if let Some(surf) = rt.surfaces.get(crtc) {
            state.space.map_output(&surf.output, (x, 0));
            state.wm.ensure_output(&surf.output.name());
            layer_map_for_output(&surf.output).arrange();
        }
        x += size.w;
    }
}

fn render_drm_crtc(
    runtime: &Rc<RefCell<DrmRuntime>>,
    data: &mut CalloopData,
    crtc: crtc::Handle,
) -> Result<(), String> {
    let mut rt = runtime.borrow_mut();
    if !rt.drm.is_active() {
        return Ok(());
    }
    if !rt.surfaces.contains_key(&crtc) {
        return Ok(());
    }

    let (mut dmabuf, age) = {
        let surf = rt.surfaces.get_mut(&crtc).unwrap();
        surf.surface
            .next_buffer()
            .map_err(|e| format!("next_buffer: {e:?}"))?
    };

    let output = rt.surfaces.get(&crtc).unwrap().output.clone();
    let clear = data.state.render_clear_color();
    {
        let DrmRuntime {
            renderer,
            surfaces,
            ..
        } = &mut *rt;
        let ssd = if data.state.session_lock_active() {
            Vec::new()
        } else {
            data.state.ssd_render_elements(renderer, &output)
        };
        let focus = if data.state.session_lock_active() {
            Vec::new()
        } else {
            data.state.focus_ring_render_elements(renderer, &output)
        };
        let identify = if data.state.session_lock_active() {
            Vec::new()
        } else {
            data.state.identify_render_elements(renderer, &output)
        };
        let cursor = data.state.cursor_render_elements(renderer, &output);
        let mut custom = ssd;
        custom.extend(focus);
        custom.extend(identify);
        custom.extend(cursor);
        let surf = surfaces.get_mut(&crtc).unwrap();
        let mut fb = renderer
            .bind(&mut dmabuf)
            .map_err(|e| format!("bind: {e:?}"))?;
        let _ = smithay::desktop::space::render_output::<
            _,
            MemoryRenderBufferRenderElement<_>,
            _,
            _,
        >(
            &output,
            renderer,
            &mut fb,
            1.0,
            age as usize,
            data.state.render_space_iter(),
            &custom,
            &mut surf.damage_tracker,
            clear,
        );
        let _ = data
            .state
            .draw_session_lock_surfaces(renderer, &mut fb, &output);
    }

    let mode_size: Size<i32, smithay::utils::Physical> = output
        .current_mode()
        .map(|m| m.size)
        .unwrap_or_else(|| (0, 0).into());
    let damage = vec![Rectangle::from_size(mode_size)];

    rt.surfaces
        .get_mut(&crtc)
        .unwrap()
        .surface
        .queue_buffer(None, Some(damage), ())
        .map_err(|e| format!("queue_buffer: {e:?}"))?;

    data.state.session_lock_after_output_render(&output);

    // Offscreen readback for screencopy (same pattern as winit).
    let size = mode_size;
    {
        let DrmRuntime {
            renderer,
            surfaces,
            ..
        } = &mut *rt;
        let surf = surfaces.get_mut(&crtc).unwrap();
        let buf_size = Size::<i32, Buffer>::from((size.w, size.h));
        if let Ok(mut tex) =
            Offscreen::<GlesTexture>::create_buffer(renderer, Fourcc::Abgr8888, buf_size)
        {
            if let Ok(mut fb) = renderer.bind(&mut tex) {
                let mut custom = if data.state.session_lock_active() {
                    Vec::new()
                } else {
                    data.state.ssd_render_elements(renderer, &output)
                };
                if !data.state.session_lock_active() {
                    custom.extend(data.state.focus_ring_render_elements(renderer, &output));
                    custom.extend(data.state.identify_render_elements(renderer, &output));
                }
                custom.extend(data.state.cursor_render_elements(renderer, &output));
                let _ = smithay::desktop::space::render_output::<
                    _,
                    MemoryRenderBufferRenderElement<_>,
                    _,
                    _,
                >(
                    &output,
                    renderer,
                    &mut fb,
                    1.0,
                    0,
                    data.state.render_space_iter(),
                    &custom,
                    &mut surf.capture_damage,
                    clear,
                );
                let _ = data
                    .state
                    .draw_session_lock_surfaces(renderer, &mut fb, &output);
                let rect = Rectangle::from_size(buf_size);
                if let Ok(mapping) = renderer.copy_framebuffer(&fb, rect, Fourcc::Abgr8888) {
                    if let Ok(pixels) = renderer.map_texture(&mapping) {
                        let prepared = prepare_screencopy_pixels(pixels, size.w, size.h);
                        data.state.last_frame = Some(CapturedFrame {
                            width: size.w,
                            height: size.h,
                            data: abgr_to_xrgb(&prepared),
                        });
                    }
                }
            }
        }
        data.state
            .drain_pending_screencopies_for(renderer, &output);
    }

    drop(rt);

    let frame_time = data.state.start_time.elapsed().as_millis() as u32;
    data.state.send_lock_surface_frames(&output, frame_time);

    if !data.state.session_lock_active() {
        data.state.space.elements().for_each(|window| {
            window.send_frame(
                &output,
                data.state.start_time.elapsed(),
                Some(Duration::ZERO),
                |_, _| Some(output.clone()),
            );
        });
        let map = layer_map_for_output(&output);
        for layer in map.layers() {
            layer.send_frame(
                &output,
                data.state.start_time.elapsed(),
                Some(Duration::ZERO),
                |_, _| Some(output.clone()),
            );
        }
        drop(map);
    }

    data.state.space.refresh();
    data.state.popups.cleanup();
    let _ = data.display_handle.flush_clients();

    Ok(())
}
