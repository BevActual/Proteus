//! Thin server-side decoration chrome (OWNED-STACK compositor spike).
//! Solid titlebar + maximize/close hits + cosmic-text title (MemoryRenderBuffer).

use std::collections::HashMap;

use cosmic_text::{
    Attrs, Buffer, Color as CosmicColor, Family, FontSystem, Metrics, Shaping, SwashCache,
};
use smithay::{
    backend::allocator::Fourcc,
    backend::renderer::{
        element::{
            memory::{MemoryRenderBuffer, MemoryRenderBufferRenderElement},
            Kind,
        },
        ImportMem, Renderer,
    },
    output::Output,
    utils::{Logical, Physical, Point, Rectangle, Size, Transform},
};

use crate::CompositorNext;

/// Fixed SSD titlebar height (logical px).
pub const TITLEBAR_H: i32 = 28;

const COLOR_BAR: [u8; 4] = [31, 33, 41, 255]; // ~0.12,0.13,0.16
const COLOR_BAR_FOCUSED: [u8; 4] = [46, 51, 61, 255]; // ~0.18,0.20,0.24
const COLOR_CLOSE: [u8; 4] = [191, 71, 71, 255]; // ~0.75,0.28,0.28
const COLOR_MAXIMIZE: [u8; 4] = [90, 120, 160, 255]; // soft blue square
const COLOR_TITLE: CosmicColor = CosmicColor::rgb(0xE8, 0xE8, 0xEC);
const TITLE_PAD_X: i32 = 8;
const FONT_SIZE: f32 = 13.0;
const LINE_HEIGHT: f32 = 18.0;

/// Font + titlebar pixel cache for SSD chrome.
pub struct SsdChrome {
    font_system: FontSystem,
    swash_cache: SwashCache,
    /// address → cached titlebar buffer
    buffers: HashMap<String, CachedTitlebar>,
}

struct CachedTitlebar {
    key: TitleCacheKey,
    buffer: MemoryRenderBuffer,
}

#[derive(Clone, PartialEq, Eq)]
struct TitleCacheKey {
    title: String,
    w: i32,
    h: i32,
    focused: bool,
    show_maximize: bool,
}

impl Default for SsdChrome {
    fn default() -> Self {
        Self {
            font_system: FontSystem::new(),
            swash_cache: SwashCache::new(),
            buffers: HashMap::new(),
        }
    }
}

/// Split an outer tile into content origin + size when SSD is active.
pub fn outer_to_content_geo(
    outer: Rectangle<i32, Logical>,
    ssd: bool,
) -> (Point<i32, Logical>, Size<i32, Logical>) {
    if !ssd || outer.size.h <= TITLEBAR_H {
        return (outer.loc, outer.size);
    }
    let content_h = (outer.size.h - TITLEBAR_H).max(1);
    (
        (outer.loc.x, outer.loc.y + TITLEBAR_H).into(),
        (outer.size.w.max(1), content_h).into(),
    )
}

/// Titlebar rect in global logical space from content origin + width.
pub fn titlebar_rect_from_content(
    content_loc: Point<i32, Logical>,
    content_w: i32,
    ssd: bool,
) -> Option<Rectangle<i32, Logical>> {
    if !ssd || content_w <= 0 {
        return None;
    }
    Some(Rectangle::new(
        (content_loc.x, content_loc.y - TITLEBAR_H).into(),
        (content_w.max(1), TITLEBAR_H).into(),
    ))
}

/// Close button hit rect (right edge of titlebar).
pub fn close_hit_rect(titlebar: Rectangle<i32, Logical>) -> Rectangle<i32, Logical> {
    let side = TITLEBAR_H.min(titlebar.size.w).max(1);
    Rectangle::new(
        (titlebar.loc.x + titlebar.size.w - side, titlebar.loc.y).into(),
        (side, TITLEBAR_H).into(),
    )
}

/// Maximize button hit rect (immediately left of close).
pub fn maximize_hit_rect(titlebar: Rectangle<i32, Logical>) -> Rectangle<i32, Logical> {
    let side = TITLEBAR_H.min(titlebar.size.w).max(1);
    let close = close_hit_rect(titlebar);
    let x = (close.loc.x - side).max(titlebar.loc.x);
    Rectangle::new((x, titlebar.loc.y).into(), (side, TITLEBAR_H).into())
}

/// Max logical width available for title text (titlebar minus chrome + pads).
/// `show_maximize`: reserve maximize square left of close when true.
pub fn title_text_max_width(titlebar_w: i32) -> i32 {
    title_text_max_width_ex(titlebar_w, true)
}

pub fn title_text_max_width_ex(titlebar_w: i32, show_maximize: bool) -> i32 {
    let btn = TITLEBAR_H.min(titlebar_w).max(1);
    let chrome = if show_maximize { btn * 2 } else { btn };
    (titlebar_w - chrome - 2 * TITLE_PAD_X).max(0)
}

/// Which SSD chrome region contains `pos`, if any.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SsdHit {
    Close { address: String },
    Maximize { address: String },
    Titlebar { address: String },
}

fn fill_rgba(
    pixels: &mut [u8],
    stride: i32,
    buf_w: i32,
    buf_h: i32,
    rect: Rectangle<i32, Logical>,
    rgba: [u8; 4],
) {
    let x0 = rect.loc.x.max(0);
    let y0 = rect.loc.y.max(0);
    let x1 = (rect.loc.x + rect.size.w).min(buf_w);
    let y1 = (rect.loc.y + rect.size.h).min(buf_h);
    for y in y0..y1 {
        for x in x0..x1 {
            let i = ((y * stride) + x * 4) as usize;
            if i + 3 < pixels.len() {
                pixels[i] = rgba[0];
                pixels[i + 1] = rgba[1];
                pixels[i + 2] = rgba[2];
                pixels[i + 3] = rgba[3];
            }
        }
    }
}

fn blend_rgba(pixels: &mut [u8], stride: i32, buf_w: i32, buf_h: i32, x: i32, y: i32, c: CosmicColor) {
    if x < 0 || y < 0 || x >= buf_w || y >= buf_h {
        return;
    }
    let i = ((y * stride) + x * 4) as usize;
    if i + 3 >= pixels.len() {
        return;
    }
    let (sr, sg, sb, sa) = c.as_rgba_tuple();
    if sa == 0 {
        return;
    }
    if sa == 255 {
        pixels[i] = sr;
        pixels[i + 1] = sg;
        pixels[i + 2] = sb;
        pixels[i + 3] = 255;
        return;
    }
    let a = sa as u32;
    let inv = 255 - a;
    pixels[i] = ((sr as u32 * a + pixels[i] as u32 * inv) / 255) as u8;
    pixels[i + 1] = ((sg as u32 * a + pixels[i + 1] as u32 * inv) / 255) as u8;
    pixels[i + 2] = ((sb as u32 * a + pixels[i + 2] as u32 * inv) / 255) as u8;
    pixels[i + 3] = 255;
}

/// Truncate `title` so shaped width fits `max_w` (adds ellipsis when shortened).
pub fn truncate_title_to_width(
    font_system: &mut FontSystem,
    title: &str,
    max_w: f32,
) -> String {
    if title.is_empty() || max_w <= 1.0 {
        return String::new();
    }
    let metrics = Metrics::new(FONT_SIZE, LINE_HEIGHT);
    let attrs = Attrs::new().family(Family::SansSerif);
    let mut buf = Buffer::new(font_system, metrics);
    buf.set_size(font_system, Some(max_w * 4.0), Some(LINE_HEIGHT));

    let measure = |font_system: &mut FontSystem, buf: &mut Buffer, s: &str| -> f32 {
        buf.set_text(font_system, s, &attrs, Shaping::Advanced, None);
        buf.shape_until_scroll(font_system, false);
        buf.layout_runs()
            .map(|run| run.line_w)
            .fold(0.0_f32, f32::max)
    };

    if measure(font_system, &mut buf, title) <= max_w {
        return title.to_string();
    }

    let chars: Vec<char> = title.chars().collect();
    if chars.is_empty() {
        return String::new();
    }
    let mut lo = 0usize;
    let mut hi = chars.len();
    let mut best = String::new();
    while lo < hi {
        let mid = (lo + hi + 1) / 2;
        let candidate: String = chars[..mid].iter().collect::<String>() + "…";
        if measure(font_system, &mut buf, &candidate) <= max_w {
            best = candidate;
            lo = mid;
        } else {
            hi = mid - 1;
        }
    }
    best
}

fn rasterize_titlebar(
    chrome: &mut SsdChrome,
    title: &str,
    w: i32,
    h: i32,
    focused: bool,
    show_maximize: bool,
) -> MemoryRenderBuffer {
    let w = w.max(1);
    let h = h.max(1);
    let stride = w * 4;
    let mut pixels = vec![0u8; (stride * h) as usize];
    let bg = if focused {
        COLOR_BAR_FOCUSED
    } else {
        COLOR_BAR
    };
    fill_rgba(
        &mut pixels,
        stride,
        w,
        h,
        Rectangle::new((0, 0).into(), (w, h).into()),
        bg,
    );

    let close_side = TITLEBAR_H.min(w).max(1);
    // Scale button boxes roughly with buffer height.
    let btn_w = ((close_side as f32) * (h as f32) / (TITLEBAR_H as f32)).round() as i32;
    let btn_w = btn_w.clamp(1, w);
    let inset = (2.0 * (h as f32) / (TITLEBAR_H as f32)).round() as i32;
    let inner_w = (btn_w - 2 * inset).max(1);
    let inner_h = (h - 2 * inset).max(1);
    fill_rgba(
        &mut pixels,
        stride,
        w,
        h,
        Rectangle::new((w - btn_w + inset, inset).into(), (inner_w, inner_h).into()),
        COLOR_CLOSE,
    );
    if show_maximize && w >= btn_w * 2 {
        fill_rgba(
            &mut pixels,
            stride,
            w,
            h,
            Rectangle::new(
                (w - 2 * btn_w + inset, inset).into(),
                (inner_w, inner_h).into(),
            ),
            COLOR_MAXIMIZE,
        );
    }

    let text_max = title_text_max_width_ex(w, show_maximize);
    if text_max > 0 && !title.is_empty() {
        let fitted = truncate_title_to_width(&mut chrome.font_system, title, text_max as f32);
        if !fitted.is_empty() {
            let metrics = Metrics::new(FONT_SIZE, LINE_HEIGHT);
            let attrs = Attrs::new().family(Family::SansSerif);
            let mut text_buf = Buffer::new(&mut chrome.font_system, metrics);
            text_buf.set_size(
                &mut chrome.font_system,
                Some(text_max as f32),
                Some(h as f32),
            );
            text_buf.set_text(
                &mut chrome.font_system,
                &fitted,
                &attrs,
                Shaping::Advanced,
                None,
            );
            text_buf.shape_until_scroll(&mut chrome.font_system, false);
            let y_off = ((h as f32 - LINE_HEIGHT) / 2.0).round() as i32;
            text_buf.draw(
                &mut chrome.font_system,
                &mut chrome.swash_cache,
                COLOR_TITLE,
                |x, y, _w, _h, color| {
                    blend_rgba(
                        &mut pixels,
                        stride,
                        w,
                        h,
                        x + TITLE_PAD_X,
                        y + y_off,
                        color,
                    );
                },
            );
        }
    }

    MemoryRenderBuffer::from_slice(
        &pixels,
        Fourcc::Abgr8888,
        (w, h),
        1,
        Transform::Normal,
        None,
    )
}

impl CompositorNext {
    pub fn ssd_titlebar_height(&self, addr: &str) -> i32 {
        match self.wm.find(addr) {
            Some(t) if t.ssd => TITLEBAR_H,
            _ => 0,
        }
    }

    /// Hit-test SSD chrome in global logical coordinates.
    pub fn ssd_hit_at(&self, pos: Point<f64, Logical>) -> Option<SsdHit> {
        let px = pos.x.round() as i32;
        let py = pos.y.round() as i32;
        let active = self.wm.active_workspace;
        for t in self.wm.toplevels.iter().rev() {
            if !t.ssd || t.workspace != active || t.workspace <= 0 {
                continue;
            }
            let Some(window) = self.windows.get(&t.address) else {
                continue;
            };
            let Some(loc) = self.space.element_location(window) else {
                continue;
            };
            let geo = window.geometry();
            let w = geo.size.w.max(t.size_w).max(1);
            let Some(bar) = titlebar_rect_from_content(loc, w, true) else {
                continue;
            };
            if !bar.contains((px, py)) {
                continue;
            }
            let close = close_hit_rect(bar);
            if close.contains((px, py)) {
                return Some(SsdHit::Close {
                    address: t.address.clone(),
                });
            }
            // Hide maximize chrome while already fullscreen.
            if !t.fullscreen {
                let max = maximize_hit_rect(bar);
                if max.contains((px, py)) {
                    return Some(SsdHit::Maximize {
                        address: t.address.clone(),
                    });
                }
            }
            return Some(SsdHit::Titlebar {
                address: t.address.clone(),
            });
        }
        None
    }

    /// Titlebar MemoryRenderBuffers (bar + title + close) for `output`.
    pub fn ssd_render_elements<R>(
        &mut self,
        renderer: &mut R,
        output: &Output,
    ) -> Vec<MemoryRenderBufferRenderElement<R>>
    where
        R: Renderer + ImportMem,
        R::TextureId: Clone + Send + 'static,
    {
        let Some(output_geo) = self.space.output_geometry(output) else {
            return Vec::new();
        };
        let scale = output.current_scale().fractional_scale();
        let focused = self.wm.focused.clone();
        let active = self.wm.active_workspace;
        let mut out = Vec::new();
        let mut keep: Vec<String> = Vec::new();

        // Collect draw list first (avoids borrow fights with chrome cache).
        let mut jobs: Vec<(String, String, Rectangle<i32, Logical>, bool, bool)> = Vec::new();
        for t in &self.wm.toplevels {
            if !t.ssd || t.workspace != active || t.workspace <= 0 {
                continue;
            }
            let Some(window) = self.windows.get(&t.address) else {
                continue;
            };
            let Some(loc) = self.space.element_location(window) else {
                continue;
            };
            let geo = window.geometry();
            let w = geo.size.w.max(t.size_w).max(1);
            let Some(bar) = titlebar_rect_from_content(loc, w, true) else {
                continue;
            };
            if !bar.overlaps(output_geo) {
                continue;
            }
            let focused_here = focused.as_deref() == Some(t.address.as_str());
            let show_maximize = !t.fullscreen;
            jobs.push((
                t.address.clone(),
                t.title.clone(),
                bar,
                focused_here,
                show_maximize,
            ));
        }

        for (address, title, bar, focused_here, show_maximize) in jobs {
            let bar_local = Rectangle::new(
                (bar.loc.x - output_geo.loc.x, bar.loc.y - output_geo.loc.y).into(),
                bar.size,
            );
            let bar_phys: Rectangle<i32, Physical> =
                bar_local.to_physical_precise_round(scale);
            let pw = bar_phys.size.w.max(1);
            let ph = bar_phys.size.h.max(1);
            let key = TitleCacheKey {
                title: title.clone(),
                w: pw,
                h: ph,
                focused: focused_here,
                show_maximize,
            };

            let need_new = match self.ssd_chrome.buffers.get(&address) {
                Some(c) if c.key == key => false,
                _ => true,
            };
            if need_new {
                let buffer = rasterize_titlebar(
                    &mut self.ssd_chrome,
                    &title,
                    pw,
                    ph,
                    focused_here,
                    show_maximize,
                );
                self.ssd_chrome.buffers.insert(
                    address.clone(),
                    CachedTitlebar { key, buffer },
                );
            }
            keep.push(address.clone());

            let Some(cached) = self.ssd_chrome.buffers.get(&address) else {
                continue;
            };
            let loc = (
                bar_phys.loc.x as f64,
                bar_phys.loc.y as f64,
            );
            if let Ok(elem) = MemoryRenderBufferRenderElement::from_buffer(
                renderer,
                loc,
                &cached.buffer,
                None,
                None,
                None,
                Kind::Unspecified,
            ) {
                out.push(elem);
            }
        }

        self.ssd_chrome
            .buffers
            .retain(|addr, _| keep.iter().any(|k| k == addr));
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn area(x: i32, y: i32, w: i32, h: i32) -> Rectangle<i32, Logical> {
        Rectangle::new((x, y).into(), (w, h).into())
    }

    #[test]
    fn outer_to_content_reserves_titlebar() {
        let (loc, size) = outer_to_content_geo(area(10, 20, 200, 100), true);
        assert_eq!(loc, (10, 20 + TITLEBAR_H).into());
        assert_eq!(size, (200, 100 - TITLEBAR_H).into());
        let (loc2, size2) = outer_to_content_geo(area(10, 20, 200, 100), false);
        assert_eq!(loc2, (10, 20).into());
        assert_eq!(size2, (200, 100).into());
    }

    #[test]
    fn titlebar_and_close_geometry() {
        let bar = titlebar_rect_from_content((40, 80).into(), 120, true).unwrap();
        assert_eq!(bar, area(40, 80 - TITLEBAR_H, 120, TITLEBAR_H));
        let close = close_hit_rect(bar);
        assert_eq!(close.size.w, TITLEBAR_H);
        assert_eq!(close.loc.x + close.size.w, bar.loc.x + bar.size.w);
        assert!(titlebar_rect_from_content((0, 0).into(), 10, false).is_none());
    }

    #[test]
    fn maximize_hit_left_of_close() {
        let bar = titlebar_rect_from_content((0, 40).into(), 200, true).unwrap();
        let close = close_hit_rect(bar);
        let max = maximize_hit_rect(bar);
        assert_eq!(max.size.w, TITLEBAR_H);
        assert_eq!(max.loc.x + max.size.w, close.loc.x);
        assert_eq!(max.loc.y, close.loc.y);
    }

    #[test]
    fn title_text_max_width_leaves_close_and_pads() {
        let max = title_text_max_width(200);
        assert_eq!(max, 200 - 2 * TITLEBAR_H - 2 * TITLE_PAD_X);
        assert_eq!(title_text_max_width_ex(200, false), 200 - TITLEBAR_H - 2 * TITLE_PAD_X);
        assert_eq!(title_text_max_width(TITLEBAR_H), 0);
    }

    #[test]
    fn empty_title_truncates_clean() {
        let mut fs = FontSystem::new();
        assert_eq!(truncate_title_to_width(&mut fs, "", 100.0), "");
    }

    #[test]
    fn long_title_fits_max_width() {
        let mut fs = FontSystem::new();
        let long = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 ".repeat(4);
        let fitted = truncate_title_to_width(&mut fs, &long, 80.0);
        assert!(!fitted.is_empty());
        assert!(fitted.chars().count() < long.chars().count());
        assert!(fitted.contains('…') || fitted.len() < long.len());

        let metrics = Metrics::new(FONT_SIZE, LINE_HEIGHT);
        let attrs = Attrs::new().family(Family::SansSerif);
        let mut buf = Buffer::new(&mut fs, metrics);
        buf.set_size(&mut fs, Some(320.0), Some(LINE_HEIGHT));
        buf.set_text(&mut fs, &fitted, &attrs, Shaping::Advanced, None);
        buf.shape_until_scroll(&mut fs, false);
        let w = buf
            .layout_runs()
            .map(|run| run.line_w)
            .fold(0.0_f32, f32::max);
        assert!(w <= 80.0 + 1.0, "fitted width {w} exceeds 80");
    }
}
