use std::time::{Duration, Instant};

use iced::Task;

use proteus_shell::anim::Easing;
use proteus_shell::surfaces::{self, Message as SurfaceMsg};
use proteus_shell::wm_ipc;

use super::super::*;
use super::handle_surface;
use super::overlays::gate_launch_for_privacy;

pub(crate) fn enter_dock_edit(app: &mut App) {
    app.dock_edit = true;
    app.dock_hold_at = None;
    app.dock_drag = None;
    app.dock_drag_target = None;
    app.dock_preview = None;
    app.dock_dwell = None;
    cancel_dock_leave(app);
    app.dock_hover_pin = None;
    app.anims.dock_hover.animate_to(0.0, 70, Easing::OutCubic);
}

pub(crate) fn handle(app: &mut App, m: SurfaceMsg) -> Task<Message> {
    match m {
        SurfaceMsg::Workspace(id) => {
            let _ = wm_ipc::dispatch(&format!("workspace {id}"));
        }
        SurfaceMsg::DockLaunch(id) => {
            if app.dock_edit {
                return Task::none();
            }
            if surfaces::is_beacon_pin(&id) {
                return handle_surface(app, SurfaceMsg::ToggleLauncher);
            }
            match wm_ipc::dock_activate(&id, &app.wm) {
                wm_ipc::DockAction::Launch => {
                    if gate_launch_for_privacy(app, &id) {
                        return Task::none();
                    }
                    app.dock_bounce.insert(id.clone(), Instant::now());
                    launch_open(&id);
                }
                _ => {}
            }
        }
        SurfaceMsg::DockPress(pin) => {
            if app.dock_edit {
                if surfaces::is_beacon_pin(&pin) {
                    return Task::none();
                }
                app.dock_drag = Some(pin.clone());
                app.dock_drag_target = app.pins.iter().position(|p| p == &pin);
                return Task::none();
            }
            app.dock_hold_at = Some((pin, Instant::now()));
        }
        SurfaceMsg::DockRelease(pin) => {
            if app.dock_edit {
                if let Some(drag) = app.dock_drag.take() {
                    if drag == pin {
                        if let Some(from) = app.pins.iter().position(|p| p == &pin) {
                            if let Some(to) = app.dock_drag_target {
                                surfaces::reorder_dock_pins(&mut app.pins, from, to);
                            }
                        }
                    }
                }
                app.dock_drag_target = None;
                return Task::none();
            }
            let short_tap = app
                .dock_hold_at
                .as_ref()
                .is_some_and(|(p, start)| p == &pin && start.elapsed() < Duration::from_millis(proteus_shell::desktop_widgets::HOLD_MS));
            app.dock_hold_at = None;
            if short_tap {
                return handle_surface(app, SurfaceMsg::DockLaunch(pin));
            }
        }
        SurfaceMsg::DockEditDone => {
            let _ = surfaces::persist_dock_pins(&app.pins);
            app.dock_edit = false;
            app.dock_drag = None;
            app.dock_drag_target = None;
            app.settings_mtime = None;
            warm_icons(app);
        }
        SurfaceMsg::DockUnpin(id) => {
            if !app.dock_edit {
                return Task::none();
            }
            if surfaces::remove_dock_pin(&mut app.pins, &id) {
                if app.dock_drag.as_deref() == Some(id.as_str()) {
                    app.dock_drag = None;
                    app.dock_drag_target = None;
                }
                warm_icons(app);
            }
        }
        SurfaceMsg::DockDragHover(idx) => {
            if app.dock_edit && app.dock_drag.is_some() && idx > 0 {
                app.dock_drag_target = Some(idx);
            }
        }
        SurfaceMsg::DockHover(pin) => {
            if app.dock_edit {
                return Task::none();
            }
            cancel_dock_leave(app);
            app.dock_edge_armed = true;
            app.anims
                .dock_slide
                .animate_to(1.0, 180, Easing::OutCubic);
            let same = app.dock_hover_pin.as_deref() == Some(pin.as_str());
            app.dock_hover_pin = Some(pin.clone());
            app.anims.dock_hover.animate_to(1.0, 70, Easing::OutCubic);
            // Dwell before grim capture (immediate tip only until then).
            // Beacon pin has no windows — tip only. Skip reset when re-entering
            // the same pin (bridge cancel / cell jitter).
            if !same {
                app.dock_preview = None;
                if surfaces::is_beacon_pin(&pin) {
                    app.dock_dwell = None;
                } else {
                    app.dock_dwell = Some((pin, Instant::now()));
                }
            } else if surfaces::is_beacon_pin(&pin) {
                app.dock_dwell = None;
            } else if app.dock_dwell.is_none() && app.dock_preview.is_none() {
                app.dock_dwell = Some((pin, Instant::now()));
            }
        }
        SurfaceMsg::DockEdgeEnter => {
            cancel_dock_leave(app);
            app.dock_edge_armed = true;
            app.anims
                .dock_slide
                .animate_to(1.0, 180, Easing::OutCubic);
        }
        SurfaceMsg::BarEdgeEnter => {
            app.bar_edge_armed = true;
            app.anims.bar_slide.animate_to(1.0, 180, Easing::OutCubic);
        }
        SurfaceMsg::BarLeave => {
            if app.bar_autohide {
                app.bar_edge_armed = false;
                app.anims.bar_slide.animate_to(0.0, 180, Easing::OutCubic);
            }
        }
        SurfaceMsg::DockLeave => {
            if app.dock_edit {
                return Task::none();
            }
            // Bridge: allow the pointer to reach the preview card / next cell.
            app.dock_leave_at = Some(
                Instant::now() + Duration::from_millis(surfaces::DOCK_LEAVE_DELAY_MS),
            );
        }
        SurfaceMsg::DockPreviewEnter => {
            cancel_dock_leave(app);
        }
        SurfaceMsg::DockPreviewFocus(addr) => {
            let _ = wm_ipc::dock_focus_or_restore(&addr, &app.wm);
            app.dock_preview = None;
            app.dock_dwell = None;
            app.dock_leave_at = None;
            app.anims.dock_hover.animate_to(0.0, 70, Easing::OutCubic);
        }
        SurfaceMsg::DockPreviewClose(addr) => {
            cancel_dock_leave(app);
            let _ = wm_ipc::window_close_address(&addr);
            if let Some((pin, mut wins)) = app.dock_preview.take() {
                wins.retain(|w| w.address != addr);
                if wins.is_empty() {
                    app.dock_preview = None;
                } else {
                    app.dock_preview = Some((pin, wins));
                }
            }
        }
        _ => unreachable!(),
    }
    Task::none()
}
