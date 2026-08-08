use iced::Task;

use proteus_shell::ctl;
use proteus_shell::platform;
use proteus_shell::surfaces::Message as SurfaceMsg;

use super::super::*;
use super::handle_surface;

pub(crate) fn handle(app: &mut App, m: SurfaceMsg) -> Task<Message> {
    match m {
        SurfaceMsg::Lock => {
            let _ = ctl::handle_request(
                &app.chrome,
                &app.chrome_epoch,
                &ctl::Request {
                    target: "lock".into(),
                    method: "lock".into(),
                    args: vec![],
                },
            );
        }
        SurfaceMsg::Unlock => {
            app.lock_ui.clear_expired_cooldown();
            if app.lock_ui.cooldown_secs() > 0 {
                let left = app.lock_ui.cooldown_secs().max(1);
                app.lock_ui.status = format!("Cooldown · {left}s");
                return Task::none();
            }
            match platform::try_unlock(&app.lock_ui.pin) {
                Ok(()) => {
                    let _ = ctl::handle_request(
                        &app.chrome,
                        &app.chrome_epoch,
                        &ctl::Request {
                            target: "lock".into(),
                            method: "unlock".into(),
                            args: vec![],
                        },
                    );
                    if let Ok(mut s) = app.chrome.lock() {
                        s.session_start_lock_pending = false;
                    }
                    app.lock_ui.on_success();
                }
                Err(e) => {
                    eprintln!("proteus-shell: unlock failed: {e}");
                    app.lock_ui.on_fail();
                }
            }
        }
        SurfaceMsg::PinEntry(p) => {
            if !app.lock_ui.reveal {
                app.lock_ui.reveal = true;
            }
            app.lock_ui.pin = p;
        }
        SurfaceMsg::LockReveal => {
            app.lock_ui.reveal = true;
            if !lock_pin_mode(app) {
                app.lock_password_focus_pending = true;
            }
        }
        SurfaceMsg::LockWakeChar(ch) => {
            // Idle lock: keep the wake keystroke (password seed or PIN digit).
            app.lock_ui.reveal = true;
            if lock_pin_mode(app) {
                if app.lock_ui.push_digit(ch) {
                    return handle_surface(app, SurfaceMsg::Unlock);
                }
            } else if !ch.is_control() {
                app.lock_ui.pin.push(ch);
                app.lock_password_focus_pending = true;
            } else {
                app.lock_password_focus_pending = true;
            }
        }
        SurfaceMsg::LockPinDigit(ch) => {
            if app.lock_ui.push_digit(ch) {
                return handle_surface(app, SurfaceMsg::Unlock);
            }
        }
        SurfaceMsg::LockPinBackspace => {
            app.lock_ui.pin.pop();
        }
        SurfaceMsg::LockPinClear => {
            app.lock_ui.pin.clear();
        }
        SurfaceMsg::LockUsePassword => {
            app.lock_ui.use_password = true;
            app.lock_ui.pin.clear();
            app.lock_ui.reveal = true;
            app.lock_password_focus_pending = true;
        }
        SurfaceMsg::LockUsePin => {
            app.lock_ui.use_password = false;
            app.lock_ui.pin.clear();
            app.lock_ui.reveal = true;
        }
        SurfaceMsg::LockCustomizeAdd(kind) => {
            app.lock_ui.customize_add(&kind);
        }
        SurfaceMsg::LockCustomizeRemove(id) => {
            app.lock_ui.customize_remove(&id);
        }
        SurfaceMsg::LockCustomizeMove(id, delta) => {
            app.lock_ui.customize_move(&id, delta);
        }
        SurfaceMsg::LockCustomizeDone => {
            let _ = ctl::handle_request(
                &app.chrome,
                &app.chrome_epoch,
                &ctl::Request {
                    target: "lock".into(),
                    method: "customize".into(),
                    args: vec![],
                },
            );
            app.lock_ui.reload_widgets();
        }
        _ => unreachable!(),
    }
    Task::none()
}
