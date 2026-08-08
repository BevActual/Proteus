//! Soft cursor from a real XCursor theme (Adwaita / `XCURSOR_THEME`).
//!
//! No hand-drawn glyphs — load `left_ptr` via the `xcursor` crate.

use std::env;
use std::fs;

use smithay::{
    backend::allocator::Fourcc,
    backend::renderer::{
        element::{
            memory::{MemoryRenderBuffer, MemoryRenderBufferRenderElement},
            Kind,
        },
        ImportMem, Renderer,
    },
    input::pointer::CursorImageStatus,
    output::Output,
    utils::{Logical, Physical, Point, Size, Transform},
};
use xcursor::{parser::parse_xcursor, CursorTheme};

use crate::CompositorNext;

/// Preferred nominal size (px) when picking among theme sizes.
const WANT_SIZE: u32 = 24;

pub struct CursorState {
    status: CursorImageStatus,
    buffer: MemoryRenderBuffer,
    /// Hotspot in buffer pixels (theme xhot/yhot).
    hotspot: (f64, f64),
    /// Logical width/height of the loaded image.
    logical_size: Size<i32, Logical>,
}

impl Default for CursorState {
    fn default() -> Self {
        match load_theme_left_ptr() {
            Some((buffer, hotspot, logical_size)) => Self {
                status: CursorImageStatus::default_named(),
                buffer,
                hotspot,
                logical_size,
            },
            None => {
                eprintln!(
                    "proteus-compositor: no XCursor left_ptr found — pointer will be blank"
                );
                // 1×1 transparent placeholder so render path stays valid.
                let pixels = [0u8, 0, 0, 0];
                let buffer = MemoryRenderBuffer::from_slice(
                    &pixels,
                    Fourcc::Abgr8888,
                    (1, 1),
                    1,
                    Transform::Normal,
                    None,
                );
                Self {
                    status: CursorImageStatus::Hidden,
                    buffer,
                    hotspot: (0.0, 0.0),
                    logical_size: (1, 1).into(),
                }
            }
        }
    }
}

impl CursorState {
    pub fn set_status(&mut self, status: CursorImageStatus) {
        // Theme named cursors all use our loaded left_ptr for now (thin).
        self.status = match status {
            CursorImageStatus::Hidden => CursorImageStatus::Hidden,
            other => other,
        };
    }

    pub fn hidden(&self) -> bool {
        matches!(self.status, CursorImageStatus::Hidden)
    }
}

fn theme_names() -> Vec<String> {
    let mut names = Vec::new();
    if let Ok(t) = env::var("XCURSOR_THEME") {
        let t = t.trim();
        if !t.is_empty() {
            names.push(t.to_string());
        }
    }
    for fallback in ["Adwaita", "default", "breeze_cursors", "Bibata-Modern-Classic"] {
        if !names.iter().any(|n| n.eq_ignore_ascii_case(fallback)) {
            names.push(fallback.to_string());
        }
    }
    names
}

fn load_theme_left_ptr() -> Option<(MemoryRenderBuffer, (f64, f64), Size<i32, Logical>)> {
    for name in theme_names() {
        let theme = CursorTheme::load(&name);
        let Some(path) = theme.load_icon("left_ptr").or_else(|| theme.load_icon("default")) else {
            continue;
        };
        let Ok(bytes) = fs::read(&path) else {
            continue;
        };
        let Some(images) = parse_xcursor(&bytes) else {
            continue;
        };
        if images.is_empty() {
            continue;
        }
        // Prefer size nearest WANT_SIZE; first frame only (static cursor).
        let img = images
            .iter()
            .min_by_key(|i| (i.size as i32 - WANT_SIZE as i32).unsigned_abs())
            .unwrap();
        let w = img.width as i32;
        let h = img.height as i32;
        if w <= 0 || h <= 0 || img.pixels_rgba.len() < (w * h * 4) as usize {
            continue;
        }
        // XCursor RGBA as stored; Abgr8888 path here is R,G,B,A bytes.
        let buffer = MemoryRenderBuffer::from_slice(
            &img.pixels_rgba,
            Fourcc::Abgr8888,
            (w, h),
            1,
            Transform::Normal,
            None,
        );
        eprintln!(
            "proteus-compositor: cursor theme={name} file={} {}x{} hot=({},{})",
            path.display(),
            w,
            h,
            img.xhot,
            img.yhot
        );
        return Some((
            buffer,
            (img.xhot as f64, img.yhot as f64),
            (w, h).into(),
        ));
    }
    None
}

impl CompositorNext {
    pub fn set_cursor_status(&mut self, status: CursorImageStatus) {
        self.cursor.set_status(status);
    }

    /// Soft cursor element at the seat pointer (output-local physical).
    pub fn cursor_render_elements<R>(
        &mut self,
        renderer: &mut R,
        output: &Output,
    ) -> Vec<MemoryRenderBufferRenderElement<R>>
    where
        R: Renderer + ImportMem,
        R::TextureId: Clone + Send + 'static,
    {
        if self.cursor.hidden() {
            return Vec::new();
        }
        let Some(pointer) = self.seat.get_pointer() else {
            return Vec::new();
        };
        let Some(output_geo) = self.space.output_geometry(output) else {
            return Vec::new();
        };
        let scale = output.current_scale().fractional_scale();
        let global: Point<f64, Logical> = pointer.current_location();
        let local_x = global.x - output_geo.loc.x as f64;
        let local_y = global.y - output_geo.loc.y as f64;
        let margin = self.cursor.logical_size.w.max(self.cursor.logical_size.h) as f64 + 16.0;
        if local_x < -margin
            || local_y < -margin
            || local_x > (output_geo.size.w as f64) + margin
            || local_y > (output_geo.size.h as f64) + margin
        {
            return Vec::new();
        }
        let phys: Point<f64, Physical> = Point::from((local_x * scale, local_y * scale));
        let loc = (
            phys.x - self.cursor.hotspot.0 * scale,
            phys.y - self.cursor.hotspot.1 * scale,
        );
        let size = self.cursor.logical_size;
        match MemoryRenderBufferRenderElement::from_buffer(
            renderer,
            loc,
            &self.cursor.buffer,
            None,
            None,
            Some(size),
            Kind::Cursor,
        ) {
            Ok(elem) => vec![elem],
            Err(_) => Vec::new(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn theme_left_ptr_loads_or_hides() {
        let c = CursorState::default();
        // On CI without icons this may be Hidden; with Adwaita it must be visible.
        if std::path::Path::new("/usr/share/icons/Adwaita/cursors/left_ptr").exists()
            || std::path::Path::new("/usr/share/icons/Adwaita/cursors/default").exists()
        {
            assert!(!c.hidden(), "Adwaita present but cursor hidden");
            assert!(c.logical_size.w >= 16);
        }
    }
}
