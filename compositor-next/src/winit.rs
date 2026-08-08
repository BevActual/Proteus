//! Winit backend — nested window hosting the spike output.
//! `space::render_output` renders layer-shell surfaces + space windows.

use std::time::Duration;

use smithay::{
    backend::{
        allocator::Fourcc,
        egl::EGLDevice,
        renderer::{
                    damage::OutputDamageTracker, element::memory::MemoryRenderBufferRenderElement,
            gles::{GlesRenderer, GlesTexture},
            Bind, ExportMem, ImportDma, Offscreen,
        },
        winit::{self, WinitEvent},
    },
    desktop::layer_map_for_output,
    output::{Mode, Output, PhysicalProperties, Subpixel},
    reexports::calloop::EventLoop,
    utils::{Buffer, Rectangle, Size, Transform},
    wayland::dmabuf::DmabufFeedbackBuilder,
};

use crate::screencopy::{prepare_screencopy_pixels, CapturedFrame};
use crate::{CalloopData, CompositorNext};

pub fn init_winit(
    event_loop: &mut EventLoop<'static, CalloopData>,
    data: &mut CalloopData,
) -> Result<(), Box<dyn std::error::Error>> {
    let display_handle = data.display_handle.clone();
    let state = &mut data.state;

    let (mut backend, winit) = winit::init()?;

    // Advertise wp_linux_dmabuf so screencopy clients can allocate dmabuf targets.
    init_dmabuf_global(state, &display_handle, backend.renderer())?;

    let mode = Mode {
        size: backend.window_size(),
        refresh: 60_000,
    };

    let output = Output::new(
        "winit".to_string(),
        PhysicalProperties {
            size: (0, 0).into(),
            subpixel: Subpixel::Unknown,
            make: "Proteus".into(),
            model: "compositor-next".into(),
        },
    );
    let _global = output.create_global::<CompositorNext>(&display_handle);
    output.change_current_state(Some(mode), Some(Transform::Flipped180), None, Some((0, 0).into()));
    output.set_preferred(mode);

    state.space.map_output(&output, (0, 0));

    // Apply Displays Fact (scale/pos; mode soft-SKIP on winit).
    state.apply_displays_fact();

    let mut damage_tracker = OutputDamageTracker::from_output(&output);
    // Separate tracker so offscreen screencopy render does not skew window damage.
    let mut capture_damage = OutputDamageTracker::from_output(&output);

    // Children (e.g. `-c proteus-shell`) inherit the spike display + portal desktop id.
    std::env::set_var("WAYLAND_DISPLAY", &state.socket_name);
    std::env::set_var("XDG_CURRENT_DESKTOP", "wlroots");

    event_loop.handle().insert_source(winit, move |event, _, data| {
        let display = &mut data.display_handle;
        let state = &mut data.state;

        match event {
            WinitEvent::Resized { size, .. } => {
                output.change_current_state(
                    Some(Mode {
                        size,
                        refresh: 60_000,
                    }),
                    None,
                    None,
                    None,
                );
                layer_map_for_output(&output).arrange();
            }
            WinitEvent::Input(event) => state.process_input_event(event),
            WinitEvent::Redraw => {
                let size = backend.window_size();
                let damage = Rectangle::from_size(size);

                {
                    let (renderer, mut framebuffer) = backend.bind().unwrap();
                    let mut custom = state.ssd_render_elements(renderer, &output);
                    custom.extend(state.focus_ring_render_elements(renderer, &output));
                    custom.extend(state.identify_render_elements(renderer, &output));
                    custom.extend(state.cursor_render_elements(renderer, &output));
                    let _ = smithay::desktop::space::render_output::<
                        _,
                        MemoryRenderBufferRenderElement<_>,
                        _,
                        _,
                    >(
                        &output,
                        renderer,
                        &mut framebuffer,
                        1.0,
                        0,
                        [&state.space],
                        &custom,
                        &mut damage_tracker,
                        [0.06, 0.07, 0.09, 1.0],
                    );
                }
                if let Err(e) = backend.submit(Some(&[damage])) {
                    eprintln!("proteus-compositor-next: submit: {e:?}");
                }

                // Offscreen readback for zwlr_screencopy — avoids poking the
                // window EGL surface (ReadPixels there poisoned submit).
                {
                    let renderer = backend.renderer();
                    let buf_size = Size::<i32, Buffer>::from((size.w, size.h));
                    if let Ok(mut tex) = Offscreen::<GlesTexture>::create_buffer(
                        renderer,
                        Fourcc::Abgr8888,
                        buf_size,
                    ) {
                        if let Ok(mut fb) = renderer.bind(&mut tex) {
                            let mut custom = state.ssd_render_elements(renderer, &output);
                            custom.extend(state.focus_ring_render_elements(renderer, &output));
                            custom.extend(state.identify_render_elements(renderer, &output));
                            custom.extend(state.cursor_render_elements(renderer, &output));
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
                                [&state.space],
                                &custom,
                                &mut capture_damage,
                                [0.06, 0.07, 0.09, 1.0],
                            );
                            let rect = Rectangle::from_size(buf_size);
                            if let Ok(mapping) =
                                renderer.copy_framebuffer(&fb, rect, Fourcc::Abgr8888)
                            {
                                if let Ok(pixels) = renderer.map_texture(&mapping) {
                                    let prepared = prepare_screencopy_pixels(pixels, size.w, size.h);
                                    state.last_frame = Some(CapturedFrame {
                                        width: size.w,
                                        height: size.h,
                                        data: abgr_to_xrgb(&prepared),
                                    });
                                }
                            }
                        }
                    }
                }

                state.drain_pending_screencopies(backend.renderer());

                // Frame callbacks: space windows + layer surfaces.
                state.space.elements().for_each(|window| {
                    window.send_frame(
                        &output,
                        state.start_time.elapsed(),
                        Some(Duration::ZERO),
                        |_, _| Some(output.clone()),
                    )
                });
                let map = layer_map_for_output(&output);
                for layer in map.layers() {
                    layer.send_frame(
                        &output,
                        state.start_time.elapsed(),
                        Some(Duration::ZERO),
                        |_, _| Some(output.clone()),
                    );
                }
                drop(map);

                state.space.refresh();
                state.popups.cleanup();
                let _ = display.flush_clients();

                backend.window().request_redraw();
            }
            WinitEvent::CloseRequested => {
                state.loop_signal.stop();
            }
            _ => (),
        };
    })?;

    Ok(())
}

fn init_dmabuf_global(
    state: &mut CompositorNext,
    display_handle: &smithay::reexports::wayland_server::DisplayHandle,
    renderer: &GlesRenderer,
) -> Result<(), Box<dyn std::error::Error>> {
    if state.dmabuf_global.is_some() {
        return Ok(());
    }
    let formats: Vec<_> = renderer.dmabuf_formats().iter().copied().collect();
    if formats.is_empty() {
        eprintln!("proteus-compositor-next: dmabuf formats empty — SHM screencopy only");
        return Ok(());
    }

    let global = match EGLDevice::device_for_display(renderer.egl_context().display())
        .ok()
        .and_then(|d| d.try_get_render_node().ok().flatten())
    {
        Some(node) => {
            let feedback = DmabufFeedbackBuilder::new(node.dev_id(), formats).build()?;
            state
                .dmabuf_state
                .create_global_with_default_feedback::<CompositorNext>(display_handle, &feedback)
        }
        None => {
            eprintln!(
                "proteus-compositor-next: no EGL render node — dmabuf global v3 without feedback"
            );
            state
                .dmabuf_state
                .create_global::<CompositorNext>(display_handle, formats)
        }
    };
    state.dmabuf_global = Some(global);
    Ok(())
}

pub fn abgr_to_xrgb(src: &[u8]) -> Vec<u8> {
    let mut out = vec![0u8; src.len()];
    for (s, d) in src.chunks_exact(4).zip(out.chunks_exact_mut(4)) {
        // Memory: R,G,B,A (Abgr8888 LE) → B,G,R,X (Xrgb8888 LE)
        d[0] = s[2];
        d[1] = s[1];
        d[2] = s[0];
        d[3] = 255;
    }
    out
}
