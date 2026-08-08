//! Custom `render_output` elements — Memory chrome + game-present Rescale blit.

use smithay::{
    backend::renderer::{
        element::{
            memory::MemoryRenderBufferRenderElement,
            render_elements,
            surface::{render_elements_from_surface_tree, WaylandSurfaceRenderElement},
            utils::{Relocate, RelocateRenderElement, RescaleRenderElement},
            Kind,
        },
        ImportAll, ImportMem, Renderer, TextureFilter,
    },
    output::Output,
    utils::{Physical, Point, Scale},
};

use crate::game_present::{present_dst_rect, present_scale_factors, PresentFilter};
use crate::CompositorNext;

render_elements! {
    /// SSD / focus / identify / cursor (Memory) + game-present surface Rescale.
    pub CustomRenderElement<R> where R: ImportAll + ImportMem;
    Memory=MemoryRenderBufferRenderElement<R>,
    Present=RelocateRenderElement<RescaleRenderElement<WaylandSurfaceRenderElement<R>>>,
}

impl CompositorNext {
    /// Texture filter for game-present blit (Fact `filter`). No-op when inactive.
    pub fn apply_game_present_texture_filter<R: Renderer>(&self, renderer: &mut R) {
        if self.wm.game_present_address.is_none() || self.session_lock_active() {
            return;
        }
        let filter = match self.wm.game_present.filter {
            PresentFilter::Nearest => TextureFilter::Nearest,
            PresentFilter::Linear => TextureFilter::Linear,
        };
        let _ = renderer.upscale_filter(filter);
        let _ = renderer.downscale_filter(filter);
    }

    /// Restore default bilinear filters after a present frame.
    pub fn clear_game_present_texture_filter<R: Renderer>(renderer: &mut R) {
        let _ = renderer.upscale_filter(TextureFilter::Linear);
        let _ = renderer.downscale_filter(TextureFilter::Linear);
    }

    /// Custom elements for one output: chrome Memory + optional game-present Rescale.
    pub fn output_custom_render_elements<R>(
        &mut self,
        renderer: &mut R,
        output: &Output,
    ) -> Vec<CustomRenderElement<R>>
    where
        R: Renderer + ImportAll + ImportMem,
        R::TextureId: Clone + Send + 'static,
    {
        let mut custom: Vec<CustomRenderElement<R>> = if self.session_lock_active() {
            Vec::new()
        } else {
            self.ssd_render_elements(renderer, output)
                .into_iter()
                .map(Into::into)
                .collect()
        };
        if !self.session_lock_active() {
            custom.extend(
                self.focus_ring_render_elements(renderer, output)
                    .into_iter()
                    .map(Into::into),
            );
            custom.extend(
                self.identify_render_elements(renderer, output)
                    .into_iter()
                    .map(Into::into),
            );
            custom.extend(self.game_present_render_elements(renderer, output));
        }
        custom.extend(
            self.cursor_render_elements(renderer, output)
                .into_iter()
                .map(Into::into),
        );
        custom
    }

    /// Rescale/Relocate surface tree for the active game-present window on `output`.
    ///
    /// Window stays at native (`restore_*`) size and is unmapped from Space so
    /// `render_output` does not double-draw it at 1:1.
    pub fn game_present_render_elements<R>(
        &self,
        renderer: &mut R,
        output: &Output,
    ) -> Vec<CustomRenderElement<R>>
    where
        R: Renderer + ImportAll,
        R::TextureId: Clone + 'static,
    {
        if self.session_lock_active() {
            return Vec::new();
        }
        let Some(addr) = self.wm.game_present_address.as_deref() else {
            return Vec::new();
        };
        let Some(window) = self.windows.get(addr) else {
            return Vec::new();
        };
        let primary = self.primary_output_name();
        let out_name = self
            .wm
            .find(addr)
            .map(|t| {
                if t.output.is_empty() {
                    primary.clone()
                } else {
                    t.output.clone()
                }
            })
            .unwrap_or(primary);
        if output.name() != out_name {
            return Vec::new();
        }
        let Some(output_geo) = self.space.output_geometry(output) else {
            return Vec::new();
        };

        let (src_w, src_h) = self
            .wm
            .find(addr)
            .map(|t| {
                let w = if t.restore_w > 0 {
                    t.restore_w
                } else if t.size_w > 0 {
                    t.size_w
                } else {
                    window.geometry().size.w
                };
                let h = if t.restore_h > 0 {
                    t.restore_h
                } else if t.size_h > 0 {
                    t.size_h
                } else {
                    window.geometry().size.h
                };
                (w.max(1), h.max(1))
            })
            .unwrap_or((320, 200));

        let mode = self.wm.game_present.scale_mode;
        let dst = present_dst_rect(
            src_w,
            src_h,
            output_geo.size.w,
            output_geo.size.h,
            mode,
        );
        let (sx, sy) = present_scale_factors(src_w, src_h, dst);

        let Some(wl_surface) = window
            .toplevel()
            .map(|t| t.wl_surface().clone())
            .or_else(|| window.x11_surface().and_then(|x| x.wl_surface().clone()))
        else {
            return Vec::new();
        };

        let scale = Scale::from(output.current_scale().fractional_scale());
        let letterbox_logical = Point::from((output_geo.loc.x + dst.x, output_geo.loc.y + dst.y));
        let letterbox_phys = letterbox_logical
            .to_f64()
            .to_physical(scale)
            .to_i32_round();

        // Surface tree at origin → Rescale → Relocate Relative into letterbox.
        // Relative (not Absolute) preserves subsurface offsets within the tree.
        let origin = Point::<i32, Physical>::from((0, 0));
        let present_scale = Scale { x: sx, y: sy };
        render_elements_from_surface_tree(
            renderer,
            &wl_surface,
            origin,
            scale,
            1.0,
            Kind::Unspecified,
        )
        .into_iter()
        .map(|elem| {
            let scaled = RescaleRenderElement::from_element(elem, origin, present_scale);
            let relocated =
                RelocateRenderElement::from_element(scaled, letterbox_phys, Relocate::Relative);
            CustomRenderElement::Present(relocated)
        })
        .collect()
    }

    /// Send frame callbacks to the game-present window even when Space-unmapped.
    pub fn send_game_present_frames(&self, output: &Output, time: std::time::Duration) {
        let Some(addr) = self.wm.game_present_address.as_deref() else {
            return;
        };
        let Some(window) = self.windows.get(addr) else {
            return;
        };
        if self.space.elements().any(|w| w == window) {
            return;
        }
        window.send_frame(output, time, Some(std::time::Duration::ZERO), |_, _| {
            Some(output.clone())
        });
    }
}
