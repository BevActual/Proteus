//! Top-level iced update loop.

use std::sync::atomic::Ordering;
use std::time::{Duration, Instant};

use iced::Task;

use proteus_shell::ctl::{self};
use proteus_shell::layers;
use proteus_shell::platform::{
    self,
};
use proteus_shell::surfaces::{self, Message as SurfaceMsg};

use super::*;

pub(crate) fn update(app: &mut App, message: Message) -> Task<Message> {
    if std::env::var_os("PROTEUS_SHELL_TRACE").is_some() {
        match &message {
            Message::Tick => eprintln!("[trace] tick"),
            Message::AnimTick => {}
            m => eprintln!("[trace] msg {:?}", std::mem::discriminant(m)),
        }
    }
    match message {
        Message::Tick => {
            app.tick_n = app.tick_n.wrapping_add(1);
            app.lock_ui.clear_expired_cooldown();
            // Lock auth path: keep the UI thread light so password keystrokes
            // aren't delayed into key-repeat bunches (desktop peek + lag).
            if app.locked {
                let epoch = app.chrome_epoch.load(Ordering::Relaxed);
                let epoch_dirty = epoch != app.last_epoch;
                if epoch_dirty {
                    sync_snapshots(app);
                }
                // Settings mtime only — no WM/sensor/applet spam while typing.
                if app.tick_n % 10 == 0 {
                    apply_settings_if_changed(app);
                }
                expire_overlays(app);
                let input_task = if epoch_dirty || app.tick_n < 12 {
                    reconcile_layer_input(app)
                } else {
                    Task::none()
                };
                return Task::batch([input_task, take_lock_password_focus(app)]);
            }
            flush_pending_sliders(app);
            // WM from socket listener — clone only when gen advances.
            let wm_dirty = pull_wm(app);
            // In-process clock ~every 3s (was a `date` subprocess).
            if app.tick_n % 15 == 1 {
                app.clock = surfaces::bar_clock_now();
            }
            // Weather glance ~every 60s (curl Open-Meteo off UI when due).
            if app.tick_n % 120 == 2 {
                app.weather = platform::weather_glance();
            }
            // Hold empty wallpaper → Customize (~450ms).
            if let Some(start) = app.desktop_hold_at {
                if start.elapsed()
                    >= Duration::from_millis(proteus_shell::desktop_widgets::HOLD_MS)
                {
                    app.desktop_hold_at = None;
                    if !app.chrome_snap.widgets_customize {
                        let _ = ctl::handle_request(
                            &app.chrome,
                            &app.chrome_epoch,
                            &ctl::Request {
                                target: "chrome".into(),
                                method: "customizeDesktop".into(),
                                args: vec![],
                            },
                        );
                    }
                }
            }
            // Long-press dock pin → edit mode (~450ms).
            if let Some((_pin, start)) = &app.dock_hold_at {
                if start.elapsed()
                    >= Duration::from_millis(proteus_shell::desktop_widgets::HOLD_MS)
                {
                    enter_dock_edit(app);
                }
            }
            let epoch = app.chrome_epoch.load(Ordering::Relaxed);
            let epoch_dirty = epoch != app.last_epoch;
            // Chrome/notifs/tray: on epoch change, else ~every 4s.
            if epoch_dirty || app.tick_n % 20 == 0 {
                sync_snapshots(app);
            }
            // Sensors / settings: ~every 2s.
            if app.tick_n % 10 == 0 {
                refresh_heavy(app);
            }
            // Dock hover dwell → capture preview thumbnails (desktop only).
            let mut preview_task = Task::none();
            dock_leave_tick(app);
            let dock_busy = app.dock_hover_pin.is_some()
                || app.dock_leave_at.is_some()
                || app.dock_dwell.is_some()
                || app.dock_preview.is_some()
                || app.dock_edit
                || app.dock_hold_at.is_some()
                || app.dock_drag.is_some();
            if let Some((pin, start)) = app.dock_dwell.clone() {
                if start.elapsed() >= Duration::from_millis(surfaces::DOCK_PREVIEW_DWELL_MS)
                {
                    app.dock_dwell = None;
                    if app.dock_hover_pin.as_deref() == Some(pin.as_str())
                        && app.dock_leave_at.is_none()
                    {
                        preview_task = capture_dock_preview(app, &pin);
                    }
                }
            }
            expire_overlays(app);
            let spaces_task = take_spaces_thumbs_task(app);
            // Skip input reconcile when idle + stable — applied map already matches.
            // Do not force reconcile every tick while locked (handled above).
            let need_input = dock_busy
                || wm_dirty
                || epoch_dirty
                || app.launcher_open
                || app.cc_open
                || app.hub_open
                || app.spaces_open
                || app.chrome_snap.widgets_customize
                || !app.hud_kind.is_empty()
                || app.toast.is_some()
                || app.tick_n < 12
                || app.tick_n % 25 == 0;
            let input_task = if need_input {
                reconcile_layer_input(app)
            } else {
                Task::none()
            };
            let focus_task = Task::batch([
                take_beacon_focus(app),
                take_spaces_rename_focus(app),
                take_lock_password_focus(app),
            ]);
            Task::batch([preview_task, spaces_task, input_task, focus_task])
        }
        Message::AnimTick => {
            // Frame ticks arrive via a timer subscription while motion runs;
            // the message itself is enough to trigger a redraw.
            flush_pending_sliders(app);
            if !app.locked {
                dock_bounce_tick(app);
                dock_leave_tick(app);
            }
            if !motion_active(app) && app.lock_ui.shake.as_ref().is_some_and(|k| k.done()) {
                app.lock_ui.shake = None;
            }
            Task::none()
        }
        Message::LockKey {
            key,
            text,
            captured,
            repeat,
            window,
        } => {
            if !app.locked || app.chrome_snap.protocol_lock || captured || repeat {
                return Task::none();
            }
            // iced daemon: only the lock layer may consume wake/PIN keys.
            if namespace_for(app, window) != layers::LOCK {
                return Task::none();
            }
            let revealed = app.lock_ui.reveal;
            let pin_mode = lock_pin_mode(app);
            // Password field owns keys once revealed — never double-append.
            if revealed && !pin_mode {
                return Task::none();
            }
            let fingerprint = format!("{key:?}|{text:?}");
            if let Some((prev, at)) = &app.lock_key_debounce {
                if prev == &fingerprint && at.elapsed() < Duration::from_millis(40) {
                    return Task::none();
                }
            }
            app.lock_key_debounce = Some((fingerprint, Instant::now()));
            let task = if matches!(
                key.as_ref(),
                iced::keyboard::Key::Named(iced::keyboard::key::Named::Enter)
            ) {
                if revealed {
                    Task::none()
                } else {
                    handle_surface(app, SurfaceMsg::LockReveal)
                }
            } else if matches!(
                key.as_ref(),
                iced::keyboard::Key::Named(iced::keyboard::key::Named::Backspace)
            ) {
                if pin_mode {
                    handle_surface(app, SurfaceMsg::LockPinBackspace)
                } else {
                    Task::none()
                }
            } else {
                let Some(ch) = text
                    .as_ref()
                    .and_then(|t| t.chars().next())
                    .or_else(|| match key.as_ref() {
                        iced::keyboard::Key::Character(c) => c.chars().next(),
                        _ => None,
                    })
                else {
                    return Task::none();
                };
                if !revealed {
                    handle_surface(app, SurfaceMsg::LockWakeChar(ch))
                } else if pin_mode && ch.is_ascii_digit() {
                    handle_surface(app, SurfaceMsg::LockPinDigit(ch))
                } else {
                    Task::none()
                }
            };
            Task::batch([task, take_lock_password_focus(app)])
        }
        Message::DockPreviewReady { pin, rows } => {
            if app.dock_hover_pin.as_deref() != Some(pin.as_str()) || app.locked {
                return Task::none();
            }
            let wins: Vec<surfaces::DockPreviewWin> = rows
                .into_iter()
                .map(|(address, title, hidden, bytes)| {
                    let handle = if bytes.is_empty() {
                        iced::widget::image::Handle::from_rgba(1, 1, vec![0, 0, 0, 0])
                    } else {
                        iced::widget::image::Handle::from_bytes(bytes)
                    };
                    surfaces::DockPreviewWin {
                        address,
                        title,
                        hidden,
                        handle,
                    }
                })
                .collect();
            app.dock_preview = if wins.is_empty() {
                None
            } else {
                Some((pin, wins))
            };
            reconcile_layer_input(app)
        }
        Message::SpacesThumbsReady(rows) => {
            if !app.spaces_open || app.locked {
                return Task::none();
            }
            app.spaces_thumbs.clear();
            for (address, title, workspace, bytes) in rows {
                let handle = if bytes.is_empty() {
                    iced::widget::image::Handle::from_rgba(1, 1, vec![0, 0, 0, 0])
                } else {
                    iced::widget::image::Handle::from_bytes(bytes)
                };
                app.spaces_thumbs.insert(
                    address.clone(),
                    proteus_shell::spaces::SpaceWinThumb {
                        address,
                        title,
                        workspace,
                        handle,
                    },
                );
            }
            Task::none()
        }
        Message::WindowClosed(id) => {
            app.windows.remove(&id);
            app.layer_input_applied.remove(&id);
            Task::none()
        }
        Message::Surface(m) => {
            // Hover / PIN / nav spam must not re-clone chrome+wm+tray every event.
            // Unlock / LockCustomizeDone still sync (or epoch bump from auto-unlock).
            let skip_sync = matches!(
                m,
                SurfaceMsg::DockHover(_)
                    | SurfaceMsg::DockPress(_)
                    | SurfaceMsg::DockRelease(_)
                    | SurfaceMsg::DockDragHover(_)
                    | SurfaceMsg::DockEdgeEnter
                    | SurfaceMsg::BarEdgeEnter
                    | SurfaceMsg::BarLeave
                    | SurfaceMsg::DockLeave
                    | SurfaceMsg::DockPreviewEnter
                    | SurfaceMsg::DockPreviewFocus(_)
                    | SurfaceMsg::DockPreviewClose(_)
                    | SurfaceMsg::SpacesCycle(_)
                    | SurfaceMsg::SpacesRenameInput(_)
                    | SurfaceMsg::SpacesDragStart(_)
                    | SurfaceMsg::SpacesDragHover(_, _)
                    | SurfaceMsg::BeaconNav(_)
                    | SurfaceMsg::PinEntry(_)
                    | SurfaceMsg::LockReveal
                    | SurfaceMsg::LockWakeChar(_)
                    | SurfaceMsg::LockPinDigit(_)
                    | SurfaceMsg::LockPinBackspace
                    | SurfaceMsg::LockPinClear
                    | SurfaceMsg::LockUsePassword
                    | SurfaceMsg::LockUsePin
                    | SurfaceMsg::LockCustomizeAdd(_)
                    | SurfaceMsg::LockCustomizeRemove(_)
                    | SurfaceMsg::LockCustomizeMove(_, _)
                    | SurfaceMsg::VolumeSet(_)
                    | SurfaceMsg::BrightnessSet(_)
            );
            // Pointer scrub / cell hover never changes input regions — Tick
            // expands DockPreview after dwell. Skip reconcile on the hot path.
            let skip_reconcile = matches!(
                m,
                SurfaceMsg::DockEdgeEnter
                    | SurfaceMsg::BarEdgeEnter
                    | SurfaceMsg::BarLeave
                    |                 SurfaceMsg::DockHover(_)
                    | SurfaceMsg::DockPress(_)
                    | SurfaceMsg::DockRelease(_)
                    | SurfaceMsg::DockDragHover(_)
                    | SurfaceMsg::DockLeave
                    | SurfaceMsg::DockPreviewEnter
                    | SurfaceMsg::BeaconNav(_)
                    | SurfaceMsg::VolumeSet(_)
                    | SurfaceMsg::BrightnessSet(_)
                    | SurfaceMsg::SpacesRenameInput(_)
                    | SurfaceMsg::SpacesDragHover(_, _)
                    | SurfaceMsg::PinEntry(_)
                    | SurfaceMsg::LockWakeChar(_)
                    | SurfaceMsg::LockPinDigit(_)
                    | SurfaceMsg::LockPinBackspace
                    | SurfaceMsg::LockPinClear
                    | SurfaceMsg::LockReveal
                    | SurfaceMsg::LockUsePassword
                    | SurfaceMsg::LockUsePin
            );
            let epoch_before = app.chrome_epoch.load(Ordering::Relaxed);
            let task = handle_surface(app, m);
            let epoch_after = app.chrome_epoch.load(Ordering::Relaxed);
            if !skip_sync || epoch_after != epoch_before {
                sync_snapshots(app);
            }
            let spaces_task = take_spaces_thumbs_task(app);
            let input_task = if skip_reconcile {
                Task::none()
            } else {
                reconcile_layer_input(app)
            };
            let focus_task = Task::batch([
                take_beacon_focus(app),
                take_spaces_rename_focus(app),
                take_lock_password_focus(app),
            ]);
            Task::batch([task, spaces_task, input_task, focus_task])
        }
        Message::AnchorChange { .. }
        | Message::SetInputRegion { .. }
        | Message::AnchorSizeChange { .. }
        | Message::LayerChange { .. }
        | Message::MarginChange { .. }
        | Message::SizeChange { .. }
        | Message::ExclusiveZoneChange { .. }
        | Message::KeyboardInteractivityChange { .. }
        | Message::VirtualKeyboardPressed { .. }
        | Message::NewLayerShell { .. }
        | Message::NewBaseWindow { .. }
        | Message::NewPopUp { .. }
        | Message::NewMenu { .. }
        | Message::NewInputPanel { .. }
        | Message::RemoveWindow(_)
        | Message::ForgetLastOutput => Task::none(),
    }
}
