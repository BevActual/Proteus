//! Input routing — smallvil-derived; layer surfaces get focus via
//! `CompositorNext::surface_under` (overlay/top layers above windows).
//! Session Super chords intercepted via [`crate::binds`].

use smithay::{
    backend::input::{
        AbsolutePositionEvent, Axis, AxisSource, ButtonState, Device, DeviceCapability, Event,
        InputBackend, InputEvent, KeyState, KeyboardKeyEvent, PointerAxisEvent,
        PointerButtonEvent, PointerMotionEvent, ProximityState, TabletToolButtonEvent,
        TabletToolEvent, TabletToolProximityEvent, TabletToolTipEvent, TabletToolTipState,
        TabletToolType,
    },
    input::{
        keyboard::FilterResult,
        pointer::{
            AxisFrame, ButtonEvent, Focus, GrabStartData, MotionEvent, RelativeMotionEvent,
        },
    },
    reexports::wayland_server::protocol::wl_surface::WlSurface,
    utils::SERIAL_COUNTER,
    wayland::tablet_manager::{TabletDescriptor, TabletSeatTrait},
};

use smithay::reexports::wayland_protocols::xdg::shell::server::xdg_toplevel;
use smithay::utils::{Logical, Point, Rectangle};

use crate::binds::{self, BindAction, BindmAction};
use crate::decoration::{
    is_ssd_titlebar_double_click, ssd_chrome_part_from_hit, SsdHit, SsdTitlebarClick,
};
use crate::grabs::{MoveSurfaceGrab, ResizeSurfaceGrab};
use crate::state::CompositorNext;

/// libinput / smithay BTN_LEFT.
const BTN_LEFT: u32 = 0x110;

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
                        if state.session_lock_active() {
                            return FilterResult::Forward;
                        }
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
                    if self.session_lock_active() {
                        return;
                    }
                    match &action {
                        BindAction::Dispatch(verb) => {
                            match self.wm.dispatch(verb) {
                                Ok(ops) => self.apply_wm_ops(ops),
                                Err(e) => {
                                    eprintln!("proteus-compositor: bind dispatch: {e}")
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
                self.update_ssd_pointer_chrome(pos);
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
                self.update_ssd_pointer_chrome(pos);
            }
            InputEvent::PointerButton { event, .. } => {
                let pointer = self.seat.get_pointer().unwrap();
                let keyboard = self.seat.get_keyboard().unwrap();
                let serial = SERIAL_COUNTER.next_serial();
                let button = event.button_code();
                let button_state = event.state();
                let location = pointer.current_location();
                let time_msec = event.time_msec();

                if button == BTN_LEFT && button_state == ButtonState::Released {
                    self.ssd_pressed = None;
                }

                if ButtonState::Pressed == button_state && !pointer.is_grabbed() {
                    if self.session_lock_active() {
                        if let Some((surface, _)) = self.surface_under(location) {
                            keyboard.set_focus(self, Some(surface), serial);
                        } else {
                            keyboard.set_focus(self, Option::<WlSurface>::None, serial);
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

                    // SSD chrome takes precedence over client surfaces under the bar.
                    if let Some(hit) = self.ssd_hit_at(location) {
                        if button == BTN_LEFT {
                            if let Some(part) = ssd_chrome_part_from_hit(&hit) {
                                self.ssd_pressed = Some(part);
                            }
                        }
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
                                self.focus_address(&address);
                                if button == BTN_LEFT
                                    && is_ssd_titlebar_double_click(
                                        self.ssd_last_titlebar_click.as_ref(),
                                        &address,
                                        time_msec,
                                        location.x,
                                        location.y,
                                    )
                                {
                                    self.ssd_last_titlebar_click = None;
                                    self.toggle_maximized(&address);
                                } else {
                                    if button == BTN_LEFT {
                                        self.ssd_last_titlebar_click = Some(SsdTitlebarClick {
                                            address: address.clone(),
                                            time_msec,
                                            x: location.x,
                                            y: location.y,
                                        });
                                    }
                                    self.start_ssd_move(&address, button, location, serial);
                                }
                            }
                        }
                        pointer.button(
                            self,
                            &ButtonEvent {
                                button,
                                state: button_state,
                                serial,
                                time: time_msec,
                            },
                        );
                        pointer.frame(self);
                        return;
                    }

                    // Super+LMB/RMB bindm (move/resize) before normal click focus.
                    let mods = keyboard.modifier_state();
                    if let Some(action) = self.binds.lookup_bindm(&mods, button) {
                        if self.try_start_bindm(action, button, location, serial) {
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
            InputEvent::DeviceAdded { device } => {
                if device.has_capability(DeviceCapability::TabletTool) {
                    let tablet_seat = self.seat.tablet_seat();
                    tablet_seat.add_tablet::<Self>(
                        &self.display_handle,
                        &TabletDescriptor::from(&device),
                    );
                }
            }
            InputEvent::DeviceRemoved { device } => {
                if device.has_capability(DeviceCapability::TabletTool) {
                    let tablet_seat = self.seat.tablet_seat();
                    tablet_seat.remove_tablet(&TabletDescriptor::from(&device));
                    if tablet_seat.count_tablets() == 0 {
                        tablet_seat.clear_tools();
                    }
                }
            }
            InputEvent::TabletToolAxis { event } => {
                self.on_tablet_tool_axis::<I>(&event);
            }
            InputEvent::TabletToolProximity { event } => {
                self.on_tablet_tool_proximity::<I>(&event);
            }
            InputEvent::TabletToolTip { event } => {
                self.on_tablet_tool_tip::<I>(&event);
            }
            InputEvent::TabletToolButton { event } => {
                let tablet_seat = self.seat.tablet_seat();
                if let Some(tool) = tablet_seat.get_tool(&event.tool()) {
                    tool.button(
                        event.button(),
                        event.button_state(),
                        SERIAL_COUNTER.next_serial(),
                        event.time_msec(),
                    );
                }
            }
            _ => {}
        }
    }

    fn tablet_position<I: InputBackend>(
        &self,
        event: &impl AbsolutePositionEvent<I>,
    ) -> Option<Point<f64, Logical>> {
        let output = self.space.outputs().next()?;
        let output_geo = self.space.output_geometry(output)?;
        Some(event.position_transformed(output_geo.size) + output_geo.loc.to_f64())
    }

    fn on_tablet_tool_proximity<I: InputBackend>(
        &mut self,
        event: &I::TabletToolProximityEvent,
    ) {
        let Some(pos) = self.tablet_position(event) else {
            return;
        };
        let under = self.surface_under(pos);
        let tablet_seat = self.seat.tablet_seat();
        let display_handle = self.display_handle.clone();
        let tool = tablet_seat.add_tool::<Self>(self, &display_handle, &event.tool());
        let Some(tablet) = tablet_seat.get_tablet(&TabletDescriptor::from(&event.device())) else {
            return;
        };
        match event.state() {
            ProximityState::In => {
                if let Some(under) = under {
                    tool.proximity_in(
                        pos,
                        under,
                        &tablet,
                        SERIAL_COUNTER.next_serial(),
                        event.time_msec(),
                    );
                }
            }
            ProximityState::Out => {
                tool.proximity_out(event.time_msec());
            }
        }
    }

    fn on_tablet_tool_tip<I: InputBackend>(&mut self, event: &I::TabletToolTipEvent) {
        let Some(tool) = self.seat.tablet_seat().get_tool(&event.tool()) else {
            return;
        };
        match event.tip_state() {
            TabletToolTipState::Down => {
                tool.tip_down(SERIAL_COUNTER.next_serial(), event.time_msec());
            }
            TabletToolTipState::Up => {
                tool.tip_up(event.time_msec());
            }
        }
    }

    fn on_tablet_tool_axis<I: InputBackend>(&mut self, event: &I::TabletToolAxisEvent) {
        let Some(pos) = self.tablet_position(event) else {
            return;
        };
        let under = self.surface_under(pos);
        let tablet_seat = self.seat.tablet_seat();
        let tablet = tablet_seat.get_tablet(&TabletDescriptor::from(&event.device()));
        let tool = tablet_seat.get_tool(&event.tool());
        let Some((tablet, tool)) = tablet.zip(tool) else {
            return;
        };
        if event.pressure_has_changed() {
            let eraser = matches!(event.tool().tool_type, TabletToolType::Eraser);
            let pressure = self.input_config.remap_tablet_pressure(event.pressure(), eraser);
            tool.pressure(pressure);
        }
        if event.distance_has_changed() {
            tool.distance(event.distance());
        }
        if event.tilt_has_changed() {
            tool.tilt(event.tilt());
        }
        if event.slider_has_changed() {
            tool.slider_position(event.slider_position());
        }
        if event.rotation_has_changed() {
            tool.rotation(event.rotation());
        }
        if event.wheel_has_changed() {
            tool.wheel(event.wheel_delta(), event.wheel_delta_discrete());
        }
        tool.motion(
            pos,
            under,
            &tablet,
            SERIAL_COUNTER.next_serial(),
            event.time_msec(),
        );
    }

    fn update_ssd_pointer_chrome(&mut self, pos: Point<f64, Logical>) {
        let hover = self
            .ssd_hit_at(pos)
            .and_then(|h| ssd_chrome_part_from_hit(&h));
        if hover != self.ssd_hover {
            self.ssd_hover = hover;
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

    /// Super+mouse bindm — returns true if a grab started.
    fn try_start_bindm(
        &mut self,
        action: BindmAction,
        button: u32,
        location: Point<f64, Logical>,
        serial: smithay::utils::Serial,
    ) -> bool {
        let Some((window, _)) = self
            .space
            .element_under(location)
            .map(|(w, l)| (w.clone(), l))
        else {
            return false;
        };
        let Some(initial_window_location) = self.space.element_location(&window) else {
            return false;
        };
        let address = self.windows.iter().find_map(|(a, w)| {
            (w == &window).then(|| a.clone())
        });
        if let Some(addr) = &address {
            self.focus_address(addr);
            self.wm.set_floating(addr, true);
        }
        let Some(pointer) = self.seat.get_pointer() else {
            return false;
        };
        let start_data = GrabStartData {
            focus: None,
            button,
            location,
        };
        match action {
            BindmAction::Move => {
                pointer.set_grab(
                    self,
                    MoveSurfaceGrab {
                        start_data,
                        window,
                        initial_window_location,
                        address,
                    },
                    serial,
                    Focus::Clear,
                );
                true
            }
            BindmAction::Resize => {
                let geometry = window.geometry();
                let initial_rect = Rectangle::new(initial_window_location, geometry.size);
                if let Some(t) = window.toplevel() {
                    t.with_pending_state(|state| {
                        state.states.set(xdg_toplevel::State::Resizing);
                    });
                    t.send_pending_configure();
                }
                pointer.set_grab(
                    self,
                    ResizeSurfaceGrab {
                        start_data,
                        window,
                        edges: xdg_toplevel::ResizeEdge::BottomRight,
                        initial_rect,
                        address,
                    },
                    serial,
                    Focus::Clear,
                );
                true
            }
        }
    }
}
