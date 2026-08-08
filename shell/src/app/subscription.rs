//! iced subscriptions (ticks, keyboard).

use std::time::Duration;

use proteus_shell::surfaces::Message as SurfaceMsg;

use super::*;

pub(crate) fn subscription(app: &App) -> iced::Subscription<Message> {
        // Idle desktop: 500ms. Busy chrome: 200ms. Locked auth: 1s (cooldown UI
        // only) — faster ticks redraw every layer and bunch key-repeat.
        let tick_ms = if app.locked && !motion_active(app) {
            1000
        } else if app.dock_hover_pin.is_some()
            || app.dock_preview.is_some()
            || app.dock_edit
            || app.dock_hold_at.is_some()
            || app.cc_open
            || app.launcher_open
            || app.spaces_open
            || app.slider_flush_at.is_some()
            || motion_active(app)
        {
            200
        } else {
            500
        };
        let mut subs = vec![
            iced::window::close_events().map(Message::WindowClosed),
            iced::time::every(Duration::from_millis(tick_ms)).map(|_| Message::Tick),
        ];
        // ~30fps frame ticks only while motion is in flight (magnify / CC /
        // Beacon / shake). Full multi-layer redraw at 60fps was a main lag source.
        if motion_active(app) {
            subs.push(iced::time::every(Duration::from_millis(33)).map(|_| Message::AnimTick));
        }
        // Beacon keyboard nav — ↑↓ move, Esc clears then closes (QML parity).
        // Enter is handled by the input's on_submit.
        if app.launcher_open && !app.locked {
            subs.push(iced::event::listen_with(|event, status, _id| {
                if matches!(status, iced::event::Status::Captured) {
                    return None;
                }
                let iced::Event::Keyboard(iced::keyboard::Event::KeyPressed {
                    key,
                    repeat,
                    ..
                }) = event
                else {
                    return None;
                };
                if repeat {
                    return None;
                }
                match key.as_ref() {
                    iced::keyboard::Key::Named(iced::keyboard::key::Named::ArrowDown) => {
                        Some(Message::Surface(SurfaceMsg::BeaconNav(1)))
                    }
                    iced::keyboard::Key::Named(iced::keyboard::key::Named::ArrowUp) => {
                        Some(Message::Surface(SurfaceMsg::BeaconNav(-1)))
                    }
                    iced::keyboard::Key::Named(iced::keyboard::key::Named::Escape) => {
                        Some(Message::Surface(SurfaceMsg::BeaconEscape))
                    }
                    _ => None,
                }
            }));
        }
        if app.spaces_open && !app.locked {
            subs.push(iced::event::listen_with(|event, _status, _id| {
                if let iced::Event::Keyboard(iced::keyboard::Event::KeyPressed {
                    key, ..
                }) = event
                {
                    match key.as_ref() {
                        iced::keyboard::Key::Named(iced::keyboard::key::Named::Escape) => {
                            Some(Message::Surface(SurfaceMsg::SpacesEscape))
                        }
                        _ => None,
                    }
                } else {
                    None
                }
            }));
        }
        // Lock keyboard wake / PIN digits. Filtering happens in Message::LockKey
        // (listen_with cannot capture reveal/pin_mode). Password text_input uses
        // Captured status so those keys are ignored here — no double-insert.
        // Window id is required: daemon Interaction events are per-surface.
        if app.locked && !app.chrome_snap.protocol_lock {
            subs.push(iced::event::listen_with(|event, status, id| {
                let iced::Event::Keyboard(iced::keyboard::Event::KeyPressed {
                    key,
                    text,
                    repeat,
                    ..
                }) = event
                else {
                    return None;
                };
                Some(Message::LockKey {
                    key,
                    text: text.map(|s| s.to_string()),
                    captured: matches!(status, iced::event::Status::Captured),
                    repeat,
                    window: id,
                })
            }));
        }
        iced::Subscription::batch(subs)
}

