//! Input routing — smallvil-derived; layer surfaces get focus via
//! `CompositorNext::surface_under` (overlay/top layers above windows).
//! Session Super chords intercepted via [`crate::binds`].

use smithay::{
    backend::input::{
        AbsolutePositionEvent, Axis, AxisSource, ButtonState, Event, InputBackend, InputEvent,
        KeyState, KeyboardKeyEvent, PointerAxisEvent, PointerButtonEvent, PointerMotionEvent,
    },
    input::{
        keyboard::FilterResult,
        pointer::{
            AxisFrame, ButtonEvent, Focus, GrabStartData, MotionEvent, RelativeMotionEvent,
        },
    },
    reexports::wayland_server::protocol::wl_surface::WlSurface,
    utils::SERIAL_COUNTER,
};

use crate::binds::{self, BindAction};
use crate::decoration::SsdHit;
use crate::grabs::MoveSurfaceGrab;
use crate::state::CompositorNext;

impl CompositorNext {
    pub fn process_input_event<I: InputBackend>(&mut self, event: InputEvent<I>) {
        match event {
            InputEvent::Keyboard { event, .. } => {
                let serial = SERIAL_COUNTER.next_serial();
                let time = Event::time_msec(&event);
                let pressed = event.state() == KeyState::Pressed;
                let action = self.seat.get_keyboard().unwrap().input::<Option<BindAction>, _>(
                    self,
                    event.key_code(),
                    event.state(),
                    serial,
                    time,
                    |state, modifiers, handle| {
                        if !pressed {
                            return FilterResult::Forward;
                        }
                        let sym = handle
                            .raw_latin_sym_or_raw_current_sym()
                            .unwrap_or_else(|| handle.modified_sym());
                        let Some(name) = binds::keysym_to_name(sym) else {
                            return FilterResult::Forward;
                        };
                        match state.binds.lookup(modifiers, name) {
                            Some(action) => FilterResult::Intercept(Some(action.clone())),
                            None => FilterResult::Forward,
                        }
                    },
                );
                if let Some(Some(action)) = action {
                    match &action {
                        BindAction::Dispatch(verb) => {
                            match self.wm.dispatch(verb) {
                                Ok(ops) => self.apply_wm_ops(ops),
                                Err(e) => {
                                    eprintln!("proteus-compositor-next: bind dispatch: {e}")
                                }
                            }
                        }
                        other => binds::spawn_action(other),
                    }
                }
            }
            InputEvent::PointerMotion { event, .. } => {
                let Some(output) = self.space.outputs().next() else {
                    return;
                };
                let Some(output_geo) = self.space.output_geometry(output) else {
                    return;
                };
                let scale = self.input_config.sensitivity_scale();
                let raw = event.delta();
                let delta = smithay::utils::Point::from((raw.x * scale, raw.y * scale));
                let raw_unaccel = event.delta_unaccel();
                let delta_unaccel = smithay::utils::Point::from((
                    raw_unaccel.x * scale,
                    raw_unaccel.y * scale,
                ));
                let pointer = self.seat.get_pointer().unwrap();
                let mut pos = pointer.current_location() + delta;
                pos.x = pos.x.clamp(
                    output_geo.loc.x as f64,
                    (output_geo.loc.x + output_geo.size.w) as f64,
                );
                pos.y = pos.y.clamp(
                    output_geo.loc.y as f64,
                    (output_geo.loc.y + output_geo.size.h) as f64,
                );
                let serial = SERIAL_COUNTER.next_serial();
                let under = self.surface_under(pos);
                pointer.motion(
                    self,
                    under.clone(),
                    &MotionEvent {
                        location: pos,
                        serial,
                        time: event.time_msec(),
                    },
                );
                pointer.relative_motion(
                    self,
                    under,
                    &RelativeMotionEvent {
                        delta,
                        delta_unaccel,
                        utime: event.time(),
                    },
                );
                pointer.frame(self);
            }
            InputEvent::PointerMotionAbsolute { event, .. } => {
                let Some(output) = self.space.outputs().next() else {
                    return;
                };
                let output_geo = self.space.output_geometry(output).unwrap();
                let pos = event.position_transformed(output_geo.size) + output_geo.loc.to_f64();
                let serial = SERIAL_COUNTER.next_serial();
                let pointer = self.seat.get_pointer().unwrap();
                let under = self.surface_under(pos);
                pointer.motion(
                    self,
                    under,
                    &MotionEvent {
                        location: pos,
                        serial,
                        time: event.time_msec(),
                    },
                );
                pointer.frame(self);
            }
            InputEvent::PointerButton { event, .. } => {
                let pointer = self.seat.get_pointer().unwrap();
                let keyboard = self.seat.get_keyboard().unwrap();
                let serial = SERIAL_COUNTER.next_serial();
                let button = event.button_code();
                let button_state = event.state();
                let location = pointer.current_location();

                if ButtonState::Pressed == button_state && !pointer.is_grabbed() {
                    // SSD chrome takes precedence over client surfaces under the bar.
                    if let Some(hit) = self.ssd_hit_at(location) {
                        match hit {
                            SsdHit::Close { address } => {
                                self.focus_address(&address);
                                self.close_address(&address);
                            }
                            SsdHit::Maximize { address } => {
                                self.focus_address(&address);
                                self.toggle_maximized(&address);
                            }
                            SsdHit::Minimize { address } => {
                                self.focus_address(&address);
                                self.minimize_address(&address);
                            }
                            SsdHit::Titlebar { address } => {
                                self.start_ssd_move(&address, button, location, serial);
                            }
                        }
                        pointer.button(
                            self,
                            &ButtonEvent {
                                button,
                                state: button_state,
                                serial,
                                time: event.time_msec(),
                            },
                        );
                        pointer.frame(self);
                        return;
                    }

                    // Focus the surface under the pointer (layer or window).
                    if let Some((surface, _)) = self.surface_under(location) {
                        if let Some((window, _)) = self
                            .space
                            .element_under(location)
                            .map(|(w, l)| (w.clone(), l))
                        {
                            self.space.raise_element(&window, true);
                            if let Some(addr) = self.windows.iter().find_map(|(a, w)| {
                                (w == &window).then(|| a.clone())
                            }) {
                                self.wm.focused = Some(addr);
                                self.broadcast_event("activewindow>>");
                            }
                        }
                        keyboard.set_focus(self, Some(surface), serial);
                        self.space.elements().for_each(|window| {
                            if let Some(t) = window.toplevel() {
                                t.send_pending_configure();
                            }
                        });
                    } else {
                        self.space.elements().for_each(|window| {
                            window.set_activated(false);
                            if let Some(t) = window.toplevel() {
                                t.send_pending_configure();
                            }
                        });
                        keyboard.set_focus(self, Option::<WlSurface>::None, serial);
                        self.wm.focused = None;
                        self.broadcast_event("activewindow>>");
                    }
                };

                pointer.button(
                    self,
                    &ButtonEvent {
                        button,
                        state: button_state,
                        serial,
                        time: event.time_msec(),
                    },
                );
                pointer.frame(self);
            }
            InputEvent::PointerAxis { event, .. } => {
                let source = event.source();
                let scroll = self.input_config.scroll_scale();
                let natural = self.input_config.natural_scroll;
                let horizontal_amount = event.amount(Axis::Horizontal).unwrap_or_else(|| {
                    event.amount_v120(Axis::Horizontal).unwrap_or(0.0) * 15.0 / 120.
                }) * scroll;
                let mut vertical_amount = event.amount(Axis::Vertical).unwrap_or_else(|| {
                    event.amount_v120(Axis::Vertical).unwrap_or(0.0) * 15.0 / 120.
                }) * scroll;
                let horizontal_amount_discrete =
                    event.amount_v120(Axis::Horizontal).map(|v| v * scroll);
                let mut vertical_amount_discrete =
                    event.amount_v120(Axis::Vertical).map(|v| v * scroll);
                if natural {
                    // Invert vertical for natural scroll (touchpad / wheel).
                    vertical_amount = -vertical_amount;
                    if let Some(d) = vertical_amount_discrete.as_mut() {
                        *d = -*d;
                    }
                }

                let mut frame = AxisFrame::new(event.time_msec()).source(source);
                if horizontal_amount != 0.0 {
                    frame = frame.value(Axis::Horizontal, horizontal_amount);
                    if let Some(discrete) = horizontal_amount_discrete {
                        frame = frame.v120(Axis::Horizontal, discrete as i32);
                    }
                }
                if vertical_amount != 0.0 {
                    frame = frame.value(Axis::Vertical, vertical_amount);
                    if let Some(discrete) = vertical_amount_discrete {
                        frame = frame.v120(Axis::Vertical, discrete as i32);
                    }
                }
                if source == AxisSource::Finger {
                    if event.amount(Axis::Horizontal) == Some(0.0) {
                        frame = frame.stop(Axis::Horizontal);
                    }
                    if event.amount(Axis::Vertical) == Some(0.0) {
                        frame = frame.stop(Axis::Vertical);
                    }
                }

                let pointer = self.seat.get_pointer().unwrap();
                pointer.axis(self, frame);
                pointer.frame(self);
            }
            _ => {}
        }
    }

    fn start_ssd_move(
        &mut self,
        address: &str,
        button: u32,
        location: smithay::utils::Point<f64, smithay::utils::Logical>,
        serial: smithay::utils::Serial,
    ) {
        let Some(window) = self.windows.get(address).cloned() else {
            return;
        };
        let Some(initial_window_location) = self.space.element_location(&window) else {
            return;
        };
        self.focus_address(address);
        let Some(pointer) = self.seat.get_pointer() else {
            return;
        };
        let start_data = GrabStartData {
            focus: None,
            button,
            location,
        };
        pointer.set_grab(
            self,
            MoveSurfaceGrab {
                start_data,
                window,
                initial_window_location,
                address: Some(address.to_string()),
            },
            serial,
            Focus::Clear,
        );
    }
}
