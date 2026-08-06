//! Interactive move / resize pointer grabs (smallvil-derived, floating only).

use smithay::{
    desktop::Window,
    input::{
        pointer::{
            AxisFrame, ButtonEvent, GestureHoldBeginEvent, GestureHoldEndEvent,
            GesturePinchBeginEvent, GesturePinchEndEvent, GesturePinchUpdateEvent,
            GestureSwipeBeginEvent, GestureSwipeEndEvent, GestureSwipeUpdateEvent, GrabStartData,
            MotionEvent, PointerGrab, PointerInnerHandle, RelativeMotionEvent,
        },
    },
    reexports::{
        wayland_protocols::xdg::shell::server::xdg_toplevel,
        wayland_server::protocol::wl_surface::WlSurface,
    },
    utils::{Logical, Point, Rectangle},
};

use crate::CompositorNext;

/// Pure resize geometry — unit-tested without a seat.
pub fn resize_edges_geometry(
    edges: xdg_toplevel::ResizeEdge,
    initial: Rectangle<i32, Logical>,
    delta: Point<f64, Logical>,
) -> Rectangle<i32, Logical> {
    let mut loc = initial.loc;
    let mut size = initial.size;

    let dx = delta.x.round() as i32;
    let dy = delta.y.round() as i32;

    if edges == xdg_toplevel::ResizeEdge::Top
        || edges == xdg_toplevel::ResizeEdge::TopLeft
        || edges == xdg_toplevel::ResizeEdge::TopRight
    {
        loc.y += dy;
        size.h = (size.h - dy).max(1);
    }
    if edges == xdg_toplevel::ResizeEdge::Bottom
        || edges == xdg_toplevel::ResizeEdge::BottomLeft
        || edges == xdg_toplevel::ResizeEdge::BottomRight
    {
        size.h = (size.h + dy).max(1);
    }
    if edges == xdg_toplevel::ResizeEdge::Left
        || edges == xdg_toplevel::ResizeEdge::TopLeft
        || edges == xdg_toplevel::ResizeEdge::BottomLeft
    {
        loc.x += dx;
        size.w = (size.w - dx).max(1);
    }
    if edges == xdg_toplevel::ResizeEdge::Right
        || edges == xdg_toplevel::ResizeEdge::TopRight
        || edges == xdg_toplevel::ResizeEdge::BottomRight
    {
        size.w = (size.w + dx).max(1);
    }

    Rectangle::new(loc, size)
}

pub struct MoveSurfaceGrab {
    pub start_data: GrabStartData<CompositorNext>,
    pub window: Window,
    pub initial_window_location: Point<i32, Logical>,
    pub address: Option<String>,
}

impl PointerGrab<CompositorNext> for MoveSurfaceGrab {
    fn motion(
        &mut self,
        data: &mut CompositorNext,
        handle: &mut PointerInnerHandle<'_, CompositorNext>,
        _focus: Option<(WlSurface, Point<f64, Logical>)>,
        event: &MotionEvent,
    ) {
        handle.motion(data, None, event);

        let delta = event.location - self.start_data.location;
        let new_loc = (
            self.initial_window_location.x + delta.x.round() as i32,
            self.initial_window_location.y + delta.y.round() as i32,
        );
        data.space.map_element(self.window.clone(), new_loc, true);
        if let Some(addr) = &self.address {
            data.wm.set_floating(addr, true);
            if let Some(t) = data.wm.find_mut(addr) {
                t.loc_x = new_loc.0;
                t.loc_y = new_loc.1;
            }
        }
    }

    fn relative_motion(
        &mut self,
        data: &mut CompositorNext,
        handle: &mut PointerInnerHandle<'_, CompositorNext>,
        focus: Option<(WlSurface, Point<f64, Logical>)>,
        event: &RelativeMotionEvent,
    ) {
        handle.relative_motion(data, focus, event);
    }

    fn button(
        &mut self,
        data: &mut CompositorNext,
        handle: &mut PointerInnerHandle<'_, CompositorNext>,
        event: &ButtonEvent,
    ) {
        handle.button(data, event);
        if handle.current_pressed().is_empty() {
            handle.unset_grab(self, data, event.serial, event.time, true);
        }
    }

    fn axis(
        &mut self,
        data: &mut CompositorNext,
        handle: &mut PointerInnerHandle<'_, CompositorNext>,
        details: AxisFrame,
    ) {
        handle.axis(data, details);
    }

    fn frame(
        &mut self,
        data: &mut CompositorNext,
        handle: &mut PointerInnerHandle<'_, CompositorNext>,
    ) {
        handle.frame(data);
    }

    fn gesture_swipe_begin(
        &mut self,
        data: &mut CompositorNext,
        handle: &mut PointerInnerHandle<'_, CompositorNext>,
        event: &GestureSwipeBeginEvent,
    ) {
        handle.gesture_swipe_begin(data, event);
    }
    fn gesture_swipe_update(
        &mut self,
        data: &mut CompositorNext,
        handle: &mut PointerInnerHandle<'_, CompositorNext>,
        event: &GestureSwipeUpdateEvent,
    ) {
        handle.gesture_swipe_update(data, event);
    }
    fn gesture_swipe_end(
        &mut self,
        data: &mut CompositorNext,
        handle: &mut PointerInnerHandle<'_, CompositorNext>,
        event: &GestureSwipeEndEvent,
    ) {
        handle.gesture_swipe_end(data, event);
    }
    fn gesture_pinch_begin(
        &mut self,
        data: &mut CompositorNext,
        handle: &mut PointerInnerHandle<'_, CompositorNext>,
        event: &GesturePinchBeginEvent,
    ) {
        handle.gesture_pinch_begin(data, event);
    }
    fn gesture_pinch_update(
        &mut self,
        data: &mut CompositorNext,
        handle: &mut PointerInnerHandle<'_, CompositorNext>,
        event: &GesturePinchUpdateEvent,
    ) {
        handle.gesture_pinch_update(data, event);
    }
    fn gesture_pinch_end(
        &mut self,
        data: &mut CompositorNext,
        handle: &mut PointerInnerHandle<'_, CompositorNext>,
        event: &GesturePinchEndEvent,
    ) {
        handle.gesture_pinch_end(data, event);
    }
    fn gesture_hold_begin(
        &mut self,
        data: &mut CompositorNext,
        handle: &mut PointerInnerHandle<'_, CompositorNext>,
        event: &GestureHoldBeginEvent,
    ) {
        handle.gesture_hold_begin(data, event);
    }
    fn gesture_hold_end(
        &mut self,
        data: &mut CompositorNext,
        handle: &mut PointerInnerHandle<'_, CompositorNext>,
        event: &GestureHoldEndEvent,
    ) {
        handle.gesture_hold_end(data, event);
    }

    fn start_data(&self) -> &GrabStartData<CompositorNext> {
        &self.start_data
    }

    fn unset(&mut self, data: &mut CompositorNext) {
        if let Some(loc) = data.space.element_location(&self.window) {
            if let Some(addr) = &self.address {
                if let Some(t) = data.wm.find_mut(addr) {
                    t.loc_x = loc.x;
                    t.loc_y = loc.y;
                }
            }
        }
    }
}

pub struct ResizeSurfaceGrab {
    pub start_data: GrabStartData<CompositorNext>,
    pub window: Window,
    pub edges: xdg_toplevel::ResizeEdge,
    pub initial_rect: Rectangle<i32, Logical>,
    pub address: Option<String>,
}

impl PointerGrab<CompositorNext> for ResizeSurfaceGrab {
    fn motion(
        &mut self,
        data: &mut CompositorNext,
        handle: &mut PointerInnerHandle<'_, CompositorNext>,
        _focus: Option<(WlSurface, Point<f64, Logical>)>,
        event: &MotionEvent,
    ) {
        handle.motion(data, None, event);

        let delta = event.location - self.start_data.location;
        let new_geo = resize_edges_geometry(self.edges, self.initial_rect, delta);

        data.space
            .map_element(self.window.clone(), new_geo.loc, true);
        if let Some(addr) = &self.address {
            data.wm.set_floating(addr, true);
            data.wm.set_geometry(
                addr,
                (new_geo.loc.x, new_geo.loc.y),
                (new_geo.size.w, new_geo.size.h),
            );
        }

        let Some(toplevel) = self.window.toplevel() else {
            return;
        };
        toplevel.with_pending_state(|state| {
            state.states.set(xdg_toplevel::State::Resizing);
            state.size = Some(new_geo.size);
        });
        toplevel.send_pending_configure();
    }

    fn relative_motion(
        &mut self,
        data: &mut CompositorNext,
        handle: &mut PointerInnerHandle<'_, CompositorNext>,
        focus: Option<(WlSurface, Point<f64, Logical>)>,
        event: &RelativeMotionEvent,
    ) {
        handle.relative_motion(data, focus, event);
    }

    fn button(
        &mut self,
        data: &mut CompositorNext,
        handle: &mut PointerInnerHandle<'_, CompositorNext>,
        event: &ButtonEvent,
    ) {
        handle.button(data, event);
        if handle.current_pressed().is_empty() {
            handle.unset_grab(self, data, event.serial, event.time, true);
        }
    }

    fn axis(
        &mut self,
        data: &mut CompositorNext,
        handle: &mut PointerInnerHandle<'_, CompositorNext>,
        details: AxisFrame,
    ) {
        handle.axis(data, details);
    }

    fn frame(
        &mut self,
        data: &mut CompositorNext,
        handle: &mut PointerInnerHandle<'_, CompositorNext>,
    ) {
        handle.frame(data);
    }

    fn gesture_swipe_begin(
        &mut self,
        data: &mut CompositorNext,
        handle: &mut PointerInnerHandle<'_, CompositorNext>,
        event: &GestureSwipeBeginEvent,
    ) {
        handle.gesture_swipe_begin(data, event);
    }
    fn gesture_swipe_update(
        &mut self,
        data: &mut CompositorNext,
        handle: &mut PointerInnerHandle<'_, CompositorNext>,
        event: &GestureSwipeUpdateEvent,
    ) {
        handle.gesture_swipe_update(data, event);
    }
    fn gesture_swipe_end(
        &mut self,
        data: &mut CompositorNext,
        handle: &mut PointerInnerHandle<'_, CompositorNext>,
        event: &GestureSwipeEndEvent,
    ) {
        handle.gesture_swipe_end(data, event);
    }
    fn gesture_pinch_begin(
        &mut self,
        data: &mut CompositorNext,
        handle: &mut PointerInnerHandle<'_, CompositorNext>,
        event: &GesturePinchBeginEvent,
    ) {
        handle.gesture_pinch_begin(data, event);
    }
    fn gesture_pinch_update(
        &mut self,
        data: &mut CompositorNext,
        handle: &mut PointerInnerHandle<'_, CompositorNext>,
        event: &GesturePinchUpdateEvent,
    ) {
        handle.gesture_pinch_update(data, event);
    }
    fn gesture_pinch_end(
        &mut self,
        data: &mut CompositorNext,
        handle: &mut PointerInnerHandle<'_, CompositorNext>,
        event: &GesturePinchEndEvent,
    ) {
        handle.gesture_pinch_end(data, event);
    }
    fn gesture_hold_begin(
        &mut self,
        data: &mut CompositorNext,
        handle: &mut PointerInnerHandle<'_, CompositorNext>,
        event: &GestureHoldBeginEvent,
    ) {
        handle.gesture_hold_begin(data, event);
    }
    fn gesture_hold_end(
        &mut self,
        data: &mut CompositorNext,
        handle: &mut PointerInnerHandle<'_, CompositorNext>,
        event: &GestureHoldEndEvent,
    ) {
        handle.gesture_hold_end(data, event);
    }

    fn start_data(&self) -> &GrabStartData<CompositorNext> {
        &self.start_data
    }

    fn unset(&mut self, data: &mut CompositorNext) {
        if let Some(toplevel) = self.window.toplevel() {
            toplevel.with_pending_state(|state| {
                state.states.unset(xdg_toplevel::State::Resizing);
            });
            toplevel.send_configure();
        }
        if let Some(loc) = data.space.element_location(&self.window) {
            if let Some(addr) = &self.address {
                if let Some(t) = data.wm.find_mut(addr) {
                    t.loc_x = loc.x;
                    t.loc_y = loc.y;
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn resize_right_bottom_grows() {
        let initial = Rectangle::new((10, 20).into(), (100, 80).into());
        let geo = resize_edges_geometry(
            xdg_toplevel::ResizeEdge::BottomRight,
            initial,
            (15.0, 10.0).into(),
        );
        assert_eq!(geo.loc, (10, 20).into());
        assert_eq!(geo.size, (115, 90).into());
    }

    #[test]
    fn resize_top_left_moves_origin() {
        let initial = Rectangle::new((50, 50).into(), (100, 100).into());
        let geo = resize_edges_geometry(
            xdg_toplevel::ResizeEdge::TopLeft,
            initial,
            (10.0, 20.0).into(),
        );
        assert_eq!(geo.loc, (60, 70).into());
        assert_eq!(geo.size, (90, 80).into());
    }

    #[test]
    fn resize_clamps_min_one() {
        let initial = Rectangle::new((0, 0).into(), (10, 10).into());
        let geo =
            resize_edges_geometry(xdg_toplevel::ResizeEdge::Right, initial, (-100.0, 0.0).into());
        assert_eq!(geo.size.w, 1);
    }
}
