//! ext-session-lock-v1 — blank client windows while locked; draw LockSurfaces.

use smithay::{
    backend::renderer::{
        element::{
            surface::{render_elements_from_surface_tree, WaylandSurfaceRenderElement},
            Kind,
        },
        utils::draw_render_elements,
        ImportAll, Renderer, Frame,
    },
    delegate_session_lock,
    desktop::{Space, Window},
    output::Output,
    reexports::wayland_server::protocol::wl_output::WlOutput,
    utils::{Logical, Point, Rectangle, Scale, Size, Transform},
    wayland::session_lock::{
        LockSurface, SessionLockHandler, SessionLockManagerState, SessionLocker,
    },
};

use crate::CompositorNext;

impl SessionLockHandler for CompositorNext {
    fn lock_state(&mut self) -> &mut SessionLockManagerState {
        &mut self.session_lock_state
    }

    fn lock(&mut self, confirmation: SessionLocker) {
        eprintln!("proteus-compositor: ext-session-lock requested");
        self.session_lock_pending = true;
        self.pending_locker = Some(confirmation);
        self.pending_lock_blank_outputs = self
            .space
            .outputs()
            .map(|o| o.name())
            .collect();
        if self.pending_lock_blank_outputs.is_empty() {
            self.pending_lock_blank_outputs.insert("winit".into());
        }
    }

    fn unlock(&mut self) {
        eprintln!("proteus-compositor: ext-session-lock released");
        self.session_locked = false;
        self.session_lock_pending = false;
        self.pending_locker = None;
        self.lock_surfaces.retain(|(_, s)| s.alive());
        self.lock_surfaces.clear();
        self.pending_lock_blank_outputs.clear();
    }

    fn new_surface(&mut self, surface: LockSurface, wl_output: WlOutput) {
        let Some(output) = Output::from_resource(&wl_output) else {
            eprintln!("proteus-compositor: session-lock surface for unknown output");
            return;
        };
        let size = output
            .current_mode()
            .map(|m| m.size)
            .unwrap_or_else(|| (0, 0).into());
        surface.with_pending_state(|state| {
            state.size = Some((size.w.max(0) as u32, size.h.max(0) as u32).into());
        });
        self.lock_surfaces.push((output, surface));
    }
}

delegate_session_lock!(CompositorNext);

enum Either<L, R> {
    Left(L),
    Right(R),
}

impl<L, R, T> Iterator for Either<L, R>
where
    L: Iterator<Item = T>,
    R: Iterator<Item = T>,
{
    type Item = T;

    fn next(&mut self) -> Option<Self::Item> {
        match self {
            Either::Left(l) => l.next(),
            Either::Right(r) => r.next(),
        }
    }
}

impl CompositorNext {
    /// Lock pending or confirmed — normal clients should not receive input.
    pub fn session_lock_active(&self) -> bool {
        self.session_lock_pending || self.session_locked
    }

    /// Iterator for `render_output` — empty while session lock blanks client windows.
    pub fn render_space_iter(&self) -> impl IntoIterator<Item = &Space<Window>> {
        if self.session_lock_active() {
            Either::Left(std::iter::empty())
        } else {
            Either::Right(std::iter::once(&self.space))
        }
    }

    /// Clear color for the output background while locking.
    pub fn render_clear_color(&self) -> [f32; 4] {
        if self.session_lock_active() {
            [0.0, 0.0, 0.0, 1.0]
        } else {
            [0.06, 0.07, 0.09, 1.0]
        }
    }

    /// Draw lock surfaces on top of an already-cleared output framebuffer.
    pub fn draw_session_lock_surfaces<R>(
        &self,
        renderer: &mut R,
        framebuffer: &mut R::Framebuffer<'_>,
        output: &Output,
    ) -> Result<(), R::Error>
    where
        R: Renderer + ImportAll,
        R::TextureId: Clone + 'static,
    {
        if !self.session_lock_active() {
            return Ok(());
        }
        let scale = output.current_scale().fractional_scale();
        let elements = self.session_lock_render_elements(renderer, output, scale);
        if elements.is_empty() {
            return Ok(());
        }
        let Some(output_geo) = self.space.output_geometry(output) else {
            return Ok(());
        };
        let buf_size = Size::<i32, smithay::utils::Physical>::from((
            output_geo.size.w.max(0),
            output_geo.size.h.max(0),
        ));
        let damage = [Rectangle::from_size(buf_size)];
        let refs: Vec<_> = elements.iter().collect();
        let mut frame = renderer.render(framebuffer, buf_size, Transform::Normal)?;
        draw_render_elements(&mut frame, scale, &refs, &damage)?;
        let _ = frame.finish()?;
        Ok(())
    }

    /// Draw ext-session-lock surfaces covering their outputs.
    pub fn session_lock_render_elements<R>(
        &self,
        renderer: &mut R,
        output: &Output,
        scale: f64,
    ) -> Vec<WaylandSurfaceRenderElement<R>>
    where
        R: Renderer + ImportAll,
        R::TextureId: Clone + 'static,
    {
        if !self.session_lock_active() {
            return Vec::new();
        }
        let Some(output_geo) = self.space.output_geometry(output) else {
            return Vec::new();
        };
        let scale = Scale::from(scale);
        let loc = output_geo.loc.to_f64().to_physical(scale).to_i32_round();
        self.lock_surfaces
            .iter()
            .filter(|(o, ls)| o == output && ls.alive())
            .flat_map(|(_, ls)| {
                render_elements_from_surface_tree(
                    renderer,
                    ls.wl_surface(),
                    loc,
                    scale,
                    1.0,
                    Kind::Unspecified,
                )
            })
            .collect()
    }

    /// After a blank frame is presented on `output`, confirm lock when all outputs are blank.
    pub fn session_lock_after_output_render(&mut self, output: &Output) {
        if !self.session_lock_pending {
            return;
        }
        self.pending_lock_blank_outputs.remove(&output.name());
        if !self.pending_lock_blank_outputs.is_empty() {
            return;
        }
        if let Some(locker) = self.pending_locker.take() {
            locker.lock();
            self.session_locked = true;
            self.session_lock_pending = false;
            eprintln!("proteus-compositor: ext-session-lock confirmed");
        }
    }

    /// Send frame callbacks for lock surfaces on this output.
    pub fn send_lock_surface_frames(&self, output: &Output, time: u32) {
        use smithay::wayland::compositor::{with_states, SurfaceAttributes};

        for (o, ls) in &self.lock_surfaces {
            if o != output || !ls.alive() {
                continue;
            }
            with_states(ls.wl_surface(), |states| {
                for callback in states
                    .cached_state
                    .get::<SurfaceAttributes>()
                    .current()
                    .frame_callbacks
                    .drain(..)
                {
                    callback.done(time);
                }
            });
        }
    }

    /// Input target while locked — lock surface on the output under `pos`.
    pub fn lock_surface_under(&self, pos: Point<f64, Logical>) -> Option<(smithay::reexports::wayland_server::protocol::wl_surface::WlSurface, Point<f64, Logical>)> {
        if !self.session_lock_active() {
            return None;
        }
        for (output, lock_surface) in &self.lock_surfaces {
            if !lock_surface.alive() {
                continue;
            }
            let Some(geo) = self.space.output_geometry(output) else {
                continue;
            };
            let p = pos.to_i32_round();
            if geo.loc.x <= p.x
                && geo.loc.y <= p.y
                && p.x < geo.loc.x + geo.size.w
                && p.y < geo.loc.y + geo.size.h
            {
                return Some((lock_surface.wl_surface().clone(), pos));
            }
        }
        None
    }
}
