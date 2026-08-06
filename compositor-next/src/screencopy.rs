//! Minimal `zwlr_screencopy_manager_v1` for nested grim + screencast clients.
//!
//! Serves SHM and linux-dmabuf copies from the last rendered output frame.
//! `Copy` may use the current frame; `CopyWithDamage` always waits for the next
//! redraw and emits a full-buffer `damage` event.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use smithay::{
    backend::{
        allocator::Fourcc,
        renderer::{
            element::{memory::MemoryRenderBufferRenderElement, Kind},
            gles::GlesRenderer,
            utils::draw_render_elements,
            Bind, Color32F, Frame, Renderer,
        },
    },
    output::Output,
    reexports::{
        wayland_protocols_wlr::screencopy::v1::server::{
            zwlr_screencopy_frame_v1::{self, Flags, ZwlrScreencopyFrameV1},
            zwlr_screencopy_manager_v1::{self, ZwlrScreencopyManagerV1},
        },
        wayland_server::{
            protocol::{wl_buffer::WlBuffer, wl_shm::Format},
            Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource,
        },
    },
    utils::{Logical, Point, Rectangle, Size, Transform},
    wayland::{
        dmabuf::get_dmabuf,
        shm,
    },
};

use crate::state::CompositorNext;

const VERSION: u32 = 3;

/// Last composited output pixels (top-left origin, little-endian XRGB8888).
#[derive(Clone)]
pub struct CapturedFrame {
    pub width: i32,
    pub height: i32,
    pub data: Vec<u8>,
}

impl CapturedFrame {
    pub fn crop(&self, rect: Rectangle<i32, Logical>) -> Option<Vec<u8>> {
        if rect.size.w <= 0 || rect.size.h <= 0 {
            return None;
        }
        let x0 = rect.loc.x.max(0);
        let y0 = rect.loc.y.max(0);
        let x1 = (rect.loc.x + rect.size.w).min(self.width);
        let y1 = (rect.loc.y + rect.size.h).min(self.height);
        let w = x1 - x0;
        let h = y1 - y0;
        if w <= 0 || h <= 0 {
            return None;
        }
        let mut out = vec![0u8; (w * h * 4) as usize];
        for row in 0..h {
            let src_y = y0 + row;
            let src_off = ((src_y * self.width + x0) * 4) as usize;
            let dst_off = (row * w * 4) as usize;
            let len = (w * 4) as usize;
            out[dst_off..dst_off + len].copy_from_slice(&self.data[src_off..src_off + len]);
        }
        Some(out)
    }
}

/// Flip GL ReadPixels (bottom-up) to top-left XRGB rows.
pub fn flip_y_xrgb(src: &[u8], width: i32, height: i32) -> Vec<u8> {
    let stride = (width * 4) as usize;
    let mut out = vec![0u8; src.len()];
    for y in 0..height as usize {
        let src_row = (height as usize - 1 - y) * stride;
        let dst_row = y * stride;
        out[dst_row..dst_row + stride].copy_from_slice(&src[src_row..src_row + stride]);
    }
    out
}

pub struct ScreencopyManagerGlobalData;

pub enum ScreencopyFrameState {
    Failed,
    Pending {
        info: ScreencopyFrameInfo,
        copied: Arc<AtomicBool>,
    },
}

#[derive(Clone)]
pub struct ScreencopyFrameInfo {
    pub output: Output,
    pub buffer_size: Size<i32, Logical>,
    pub region: Rectangle<i32, Logical>,
}

/// In-flight copy waiting for a rendered frame (or fulfilled immediately).
pub struct PendingScreencopy {
    pub frame: ZwlrScreencopyFrameV1,
    pub buffer: WlBuffer,
    pub info: ScreencopyFrameInfo,
    /// When true, send a full-buffer `damage` event before ready (copy_with_damage).
    pub with_damage: bool,
}

impl CompositorNext {
    pub fn init_screencopy_global(&self) {
        self.display_handle
            .create_global::<Self, ZwlrScreencopyManagerV1, _>(VERSION, ScreencopyManagerGlobalData);
    }

    /// Copy `last_frame` region into the client SHM or dmabuf buffer and send ready/failed.
    pub fn fulfill_screencopy(
        &self,
        renderer: &mut GlesRenderer,
        frame: &ZwlrScreencopyFrameV1,
        buffer: &WlBuffer,
        info: &ScreencopyFrameInfo,
        with_damage: bool,
    ) {
        let Some(captured) = self.last_frame.as_ref() else {
            frame.failed();
            return;
        };

        let expected_w = info.buffer_size.w;
        let expected_h = info.buffer_size.h;
        let pixels = match size_pixels(captured, info, expected_w, expected_h) {
            Some(p) => p,
            None => {
                frame.failed();
                return;
            }
        };

        let wrote = if get_dmabuf(buffer).is_ok() {
            write_dmabuf_xrgb(renderer, buffer, expected_w, expected_h, &pixels)
        } else {
            write_shm_xrgb(buffer, expected_w, expected_h, &pixels)
        };

        if wrote.is_err() {
            frame.failed();
            return;
        }

        if with_damage {
            frame.damage(0, 0, expected_w as u32, expected_h as u32);
        }
        frame.flags(Flags::empty());
        let ts = self.start_time.elapsed();
        let secs = ts.as_secs();
        frame.ready(
            (secs >> 32) as u32,
            (secs & 0xffff_ffff) as u32,
            ts.subsec_nanos(),
        );
    }

    pub fn drain_pending_screencopies(&mut self, renderer: &mut GlesRenderer) {
        if self.last_frame.is_none() {
            return;
        }
        let pending = std::mem::take(&mut self.pending_screencopies);
        for p in pending {
            self.fulfill_screencopy(renderer, &p.frame, &p.buffer, &p.info, p.with_damage);
        }
    }

    /// Fulfill only pending copies for `output` (multi-output DRM: capture then drain per crtc).
    pub fn drain_pending_screencopies_for(
        &mut self,
        renderer: &mut GlesRenderer,
        output: &Output,
    ) {
        if self.last_frame.is_none() {
            return;
        }
        let pending = std::mem::take(&mut self.pending_screencopies);
        let mut rest = Vec::new();
        for p in pending {
            if &p.info.output == output {
                self.fulfill_screencopy(renderer, &p.frame, &p.buffer, &p.info, p.with_damage);
            } else {
                rest.push(p);
            }
        }
        self.pending_screencopies = rest;
    }
}

fn size_pixels(
    captured: &CapturedFrame,
    info: &ScreencopyFrameInfo,
    expected_w: i32,
    expected_h: i32,
) -> Option<Vec<u8>> {
    let Some(pixels) = captured.crop(info.region) else {
        return None;
    };
    if pixels.len() == (expected_w * expected_h * 4) as usize {
        return Some(pixels);
    }
    let mut sized = vec![0u8; (expected_w * expected_h * 4) as usize];
    let copy_w = expected_w.min(info.region.size.w).max(0);
    let copy_h = expected_h.min(info.region.size.h).max(0);
    if let Some(exact) = captured.crop(Rectangle::new(
        info.region.loc,
        Size::from((copy_w, copy_h)),
    )) {
        let row_bytes = (copy_w * 4) as usize;
        for row in 0..copy_h as usize {
            let src = row * row_bytes;
            let dst = row * (expected_w as usize) * 4;
            sized[dst..dst + row_bytes].copy_from_slice(&exact[src..src + row_bytes]);
        }
    }
    Some(sized)
}

fn write_shm_xrgb(buffer: &WlBuffer, width: i32, height: i32, pixels: &[u8]) -> Result<(), ()> {
    shm::with_buffer_contents_mut(buffer, |ptr, len, data| {
        if data.format != Format::Xrgb8888
            && data.format != Format::Argb8888
            && data.format != Format::Xbgr8888
            && data.format != Format::Abgr8888
        {
            return Err(());
        }
        if data.width != width || data.height != height {
            return Err(());
        }
        let stride = data.stride as usize;
        let row_bytes = (width * 4) as usize;
        if len < stride * height as usize || pixels.len() < row_bytes * height as usize {
            return Err(());
        }
        unsafe {
            let dst = std::slice::from_raw_parts_mut(ptr, len);
            for y in 0..height as usize {
                let src_off = y * row_bytes;
                let dst_off = y * stride;
                dst[dst_off..dst_off + row_bytes]
                    .copy_from_slice(&pixels[src_off..src_off + row_bytes]);
            }
        }
        Ok(())
    })
    .map_err(|_| ())?
}

fn write_dmabuf_xrgb(
    renderer: &mut GlesRenderer,
    buffer: &WlBuffer,
    width: i32,
    height: i32,
    pixels: &[u8],
) -> Result<(), ()> {
    let Ok(dmabuf_ref) = get_dmabuf(buffer) else {
        return Err(());
    };
    let mut dmabuf = dmabuf_ref.clone();
    let mem = smithay::backend::renderer::element::memory::MemoryRenderBuffer::from_slice(
        pixels,
        Fourcc::Xrgb8888,
        (width, height),
        1,
        Transform::Normal,
        None,
    );
    let elem = MemoryRenderBufferRenderElement::from_buffer(
        renderer,
        (0.0, 0.0),
        &mem,
        None,
        None,
        None,
        Kind::Unspecified,
    )
    .map_err(|_| ())?;

    let size = Size::from((width, height));
    let damage = [Rectangle::from_size(size)];
    {
        let mut fb = renderer.bind(&mut dmabuf).map_err(|_| ())?;
        let mut frame = renderer
            .render(&mut fb, size, Transform::Normal)
            .map_err(|_| ())?;
        frame
            .clear(Color32F::TRANSPARENT, &damage)
            .map_err(|_| ())?;
        draw_render_elements(&mut frame, 1.0, &[&elem], &damage).map_err(|_| ())?;
        let _ = frame.finish().map_err(|_| ())?;
    }
    Ok(())
}

fn begin_capture(
    data_init: &mut DataInit<'_, CompositorNext>,
    frame: New<ZwlrScreencopyFrameV1>,
    output_res: &smithay::reexports::wayland_server::protocol::wl_output::WlOutput,
    region: Option<Rectangle<i32, Logical>>,
) {
    let Some(output) = Output::from_resource(output_res) else {
        let frame = data_init.init(frame, ScreencopyFrameState::Failed);
        frame.failed();
        return;
    };

    let Some(mode) = output.current_mode() else {
        let frame = data_init.init(frame, ScreencopyFrameState::Failed);
        frame.failed();
        return;
    };

    let output_size: Size<i32, Logical> = mode.size.to_logical(1);
    let region = match region {
        None => Rectangle::from_size(output_size),
        Some(r) => {
            if r.size.w <= 0 || r.size.h <= 0 {
                let frame = data_init.init(frame, ScreencopyFrameState::Failed);
                frame.failed();
                return;
            }
            let output_rect = Rectangle::from_size(output_size);
            let Some(clamped) = r.intersection(output_rect) else {
                let frame = data_init.init(frame, ScreencopyFrameState::Failed);
                frame.failed();
                return;
            };
            clamped
        }
    };

    let buf_w = region.size.w as u32;
    let buf_h = region.size.h as u32;
    let info = ScreencopyFrameInfo {
        output,
        buffer_size: region.size,
        region,
    };
    let frame = data_init.init(
        frame,
        ScreencopyFrameState::Pending {
            info,
            copied: Arc::new(AtomicBool::new(false)),
        },
    );

    frame.buffer(Format::Xrgb8888, buf_w, buf_h, buf_w * 4);
    if frame.version() >= 3 {
        frame.linux_dmabuf(Fourcc::Xrgb8888 as u32, buf_w, buf_h);
        frame.buffer_done();
    }
}

impl GlobalDispatch<ZwlrScreencopyManagerV1, ScreencopyManagerGlobalData> for CompositorNext {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<ZwlrScreencopyManagerV1>,
        _global_data: &ScreencopyManagerGlobalData,
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<ZwlrScreencopyManagerV1, ()> for CompositorNext {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &ZwlrScreencopyManagerV1,
        request: zwlr_screencopy_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zwlr_screencopy_manager_v1::Request::CaptureOutput {
                frame,
                overlay_cursor: _,
                output,
            } => begin_capture(data_init, frame, &output, None),
            zwlr_screencopy_manager_v1::Request::CaptureOutputRegion {
                frame,
                overlay_cursor: _,
                output,
                x,
                y,
                width,
                height,
            } => begin_capture(
                data_init,
                frame,
                &output,
                Some(Rectangle::new(
                    Point::from((x, y)),
                    Size::from((width, height)),
                )),
            ),
            zwlr_screencopy_manager_v1::Request::Destroy => {}
            _ => unreachable!(),
        }
    }
}

impl Dispatch<ZwlrScreencopyFrameV1, ScreencopyFrameState> for CompositorNext {
    fn request(
        state: &mut Self,
        _client: &Client,
        resource: &ZwlrScreencopyFrameV1,
        request: zwlr_screencopy_frame_v1::Request,
        data: &ScreencopyFrameState,
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zwlr_screencopy_frame_v1::Request::Destroy => {}
            zwlr_screencopy_frame_v1::Request::Copy { buffer } => {
                let ScreencopyFrameState::Pending { info, copied } = data else {
                    return;
                };
                if copied.swap(true, Ordering::SeqCst) {
                    resource.post_error(
                        zwlr_screencopy_frame_v1::Error::AlreadyUsed,
                        "frame already copied",
                    );
                    return;
                }

                // Immediate fulfill needs a renderer — queue until next redraw.
                state.pending_screencopies.push(PendingScreencopy {
                    frame: resource.clone(),
                    buffer,
                    info: info.clone(),
                    with_damage: false,
                });
            }
            zwlr_screencopy_frame_v1::Request::CopyWithDamage { buffer } => {
                let ScreencopyFrameState::Pending { info, copied } = data else {
                    return;
                };
                if copied.swap(true, Ordering::SeqCst) {
                    resource.post_error(
                        zwlr_screencopy_frame_v1::Error::AlreadyUsed,
                        "frame already copied",
                    );
                    return;
                }
                // Always wait for the next redraw so screencast clients see fresh damage.
                state.pending_screencopies.push(PendingScreencopy {
                    frame: resource.clone(),
                    buffer,
                    info: info.clone(),
                    with_damage: true,
                });
            }
            _ => unreachable!(),
        }
    }
}
