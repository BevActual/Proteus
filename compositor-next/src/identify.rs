//! Identify flash — centered connector-name badge on every output.
//!
//! `dispatch identify [secs]` (default 3, clamp 1..=10). Pass-through (no input
//! intercept). Cleared when `Instant::now() >= until`.

use std::collections::HashMap;
use std::time::{Duration, Instant};

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
    utils::{Logical, Physical, Rectangle, Transform},
};

use crate::CompositorNext;

const COLOR_BADGE: [u8; 4] = [31, 33, 41, 230];
const COLOR_TEXT: CosmicColor = CosmicColor::rgb(0xE8, 0xE8, 0xEC);
const FONT_SIZE: f32 = 28.0;
const LINE_HEIGHT: f32 = 36.0;
const PAD_X: i32 = 24;
const PAD_Y: i32 = 16;
const DEFAULT_SECS: u64 = 3;
const MIN_SECS: u64 = 1;
const MAX_SECS: u64 = 10;

/// Parse `identify` or `identify <secs>` → duration.
pub fn parse_identify_secs(rest: &str) -> Result<Duration, String> {
    let rest = rest.trim();
    if rest.is_empty() {
        return Ok(Duration::from_secs(DEFAULT_SECS));
    }
    let n: u64 = rest
        .parse()
        .map_err(|_| format!("identify: bad seconds: {rest}"))?;
    let n = n.clamp(MIN_SECS, MAX_SECS);
    Ok(Duration::from_secs(n))
}

pub struct IdentifyChrome {
    font_system: FontSystem,
    swash_cache: SwashCache,
    buffers: HashMap<String, CachedBadge>,
}

struct CachedBadge {
    key: BadgeKey,
    buffer: MemoryRenderBuffer,
    /// Logical size of the badge (for centering).
    logical_w: i32,
    logical_h: i32,
}

#[derive(Clone, PartialEq, Eq)]
struct BadgeKey {
    name: String,
    scale_milli: u32,
}

impl Default for IdentifyChrome {
    fn default() -> Self {
        Self {
            font_system: FontSystem::new(),
            swash_cache: SwashCache::new(),
            buffers: HashMap::new(),
        }
    }
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

fn blend_rgba(
    pixels: &mut [u8],
    stride: i32,
    buf_w: i32,
    buf_h: i32,
    x: i32,
    y: i32,
    c: CosmicColor,
) {
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

fn measure_text(font_system: &mut FontSystem, text: &str) -> (f32, f32) {
    let metrics = Metrics::new(FONT_SIZE, LINE_HEIGHT);
    let attrs = Attrs::new().family(Family::SansSerif);
    let mut buf = Buffer::new(font_system, metrics);
    buf.set_size(font_system, Some(800.0), Some(LINE_HEIGHT));
    buf.set_text(font_system, text, &attrs, Shaping::Advanced, None);
    buf.shape_until_scroll(font_system, false);
    let w = buf
        .layout_runs()
        .map(|run| run.line_w)
        .fold(0.0_f32, f32::max);
    (w, LINE_HEIGHT)
}

fn rasterize_badge(chrome: &mut IdentifyChrome, name: &str, scale: f64) -> (MemoryRenderBuffer, i32, i32) {
    let (text_w, text_h) = measure_text(&mut chrome.font_system, name);
    let logical_w = ((text_w as i32) + 2 * PAD_X).max(80);
    let logical_h = ((text_h as i32) + 2 * PAD_Y).max(48);
    let pw = ((logical_w as f64) * scale).round().max(1.0) as i32;
    let ph = ((logical_h as f64) * scale).round().max(1.0) as i32;
    let stride = pw * 4;
    let mut pixels = vec![0u8; (stride * ph) as usize];
    fill_rgba(
        &mut pixels,
        stride,
        pw,
        ph,
        Rectangle::new((0, 0).into(), (pw, ph).into()),
        COLOR_BADGE,
    );

    let metrics = Metrics::new(FONT_SIZE * scale as f32, LINE_HEIGHT * scale as f32);
    let attrs = Attrs::new().family(Family::SansSerif);
    let mut buf = Buffer::new(&mut chrome.font_system, metrics);
    buf.set_size(
        &mut chrome.font_system,
        Some(pw as f32),
        Some(ph as f32),
    );
    buf.set_text(
        &mut chrome.font_system,
        name,
        &attrs,
        Shaping::Advanced,
        None,
    );
    buf.shape_until_scroll(&mut chrome.font_system, false);

    let run_w = buf
        .layout_runs()
        .map(|run| run.line_w)
        .fold(0.0_f32, f32::max);
    let text_x = ((pw as f32 - run_w) / 2.0).round() as i32;
    let text_y = ((ph as f32 - LINE_HEIGHT * scale as f32) / 2.0).round() as i32;

    for run in buf.layout_runs() {
        for glyph in run.glyphs.iter() {
            let physical = glyph.physical((0.0, 0.0), 1.0);
            chrome.swash_cache.with_pixels(
                &mut chrome.font_system,
                physical.cache_key,
                COLOR_TEXT,
                |x, y, color| {
                    blend_rgba(
                        &mut pixels,
                        stride,
                        pw,
                        ph,
                        text_x + physical.x + x,
                        text_y + physical.y + y,
                        color,
                    );
                },
            );
        }
    }

    let buffer = MemoryRenderBuffer::from_slice(
        &pixels,
        Fourcc::Abgr8888,
        (pw, ph),
        1,
        Transform::Normal,
        None,
    );
    (buffer, logical_w, logical_h)
}

impl CompositorNext {
    pub fn start_identify(&mut self, secs: Duration) {
        self.identify_until = Some(Instant::now() + secs);
        eprintln!(
            "proteus-compositor-next: identify for {}s",
            secs.as_secs().max(1)
        );
    }

    pub fn identify_active(&mut self) -> bool {
        match self.identify_until {
            Some(until) if Instant::now() < until => true,
            Some(_) => {
                self.identify_until = None;
                self.identify_chrome.buffers.clear();
                false
            }
            None => false,
        }
    }

    /// Centered connector-name badges while identify is active.
    pub fn identify_render_elements<R>(
        &mut self,
        renderer: &mut R,
        output: &Output,
    ) -> Vec<MemoryRenderBufferRenderElement<R>>
    where
        R: Renderer + ImportMem,
        R::TextureId: Clone + Send + 'static,
    {
        if !self.identify_active() {
            return Vec::new();
        }
        let Some(output_geo) = self.space.output_geometry(output) else {
            return Vec::new();
        };
        let scale = output.current_scale().fractional_scale();
        let name = output.name();
        let scale_milli = (scale * 1000.0).round() as u32;
        let key = BadgeKey {
            name: name.clone(),
            scale_milli,
        };

        let need_new = match self.identify_chrome.buffers.get(&name) {
            Some(c) if c.key == key => false,
            _ => true,
        };
        if need_new {
            let (buffer, logical_w, logical_h) =
                rasterize_badge(&mut self.identify_chrome, &name, scale);
            self.identify_chrome.buffers.insert(
                name.clone(),
                CachedBadge {
                    key,
                    buffer,
                    logical_w,
                    logical_h,
                },
            );
        }

        let Some(cached) = self.identify_chrome.buffers.get(&name) else {
            return Vec::new();
        };
        let lx = output_geo.loc.x + (output_geo.size.w - cached.logical_w) / 2;
        let ly = output_geo.loc.y + (output_geo.size.h - cached.logical_h) / 2;
        let local = Rectangle::new(
            (lx - output_geo.loc.x, ly - output_geo.loc.y).into(),
            (cached.logical_w, cached.logical_h).into(),
        );
        let phys: Rectangle<i32, Physical> = local.to_physical_precise_round(scale);
        let loc = (phys.loc.x as f64, phys.loc.y as f64);
        match MemoryRenderBufferRenderElement::from_buffer(
            renderer,
            loc,
            &cached.buffer,
            None,
            None,
            None,
            Kind::Unspecified,
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
    fn parse_identify_default_and_clamp() {
        assert_eq!(parse_identify_secs("").unwrap(), Duration::from_secs(3));
        assert_eq!(parse_identify_secs("5").unwrap(), Duration::from_secs(5));
        assert_eq!(parse_identify_secs("0").unwrap(), Duration::from_secs(1));
        assert_eq!(parse_identify_secs("99").unwrap(), Duration::from_secs(10));
        assert!(parse_identify_secs("nope").is_err());
    }
}
