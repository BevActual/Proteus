use std::sync::atomic::Ordering;
use std::time::Instant;

use iced::Task;

use proteus_shell::ctl;
use proteus_shell::platform;
use proteus_shell::privacy_gate;
use proteus_shell::surfaces::Message as SurfaceMsg;

use super::super::*;
use super::handle_surface;

/// Returns true when launch was deferred behind Privacy Ask.
pub(crate) fn gate_launch_for_privacy(app: &mut App, target: &str) -> bool {
    let Some(aid) = privacy_gate::desktop_id_for_launch(target) else {
        return false;
    };
    let Some(cat) = privacy_gate::first_launch_ask_category(&aid) else {
        return false;
    };
    if let Ok(mut s) = app.chrome.lock() {
        s.privacy_ask = Some(cat.clone());
        s.privacy_ask_app = Some(aid.clone());
        s.privacy_ask_pending = Some(target.to_string());
        s.launcher_open = false;
    }
    app.privacy_ask = Some(cat);
    app.privacy_ask_app = Some(aid);
    app.chrome_epoch.fetch_add(1, Ordering::Relaxed);
    true
}

/// Returns true when Focus blocked the launch (allowedApps / keywords).
pub(crate) fn gate_launch_for_focus(_app: &mut App, target: &str) -> bool {
    let Some(aid) = privacy_gate::desktop_id_for_launch(target) else {
        return false;
    };
    !platform::focus_launch_allowed(&aid)
}

pub(crate) fn handle(app: &mut App, m: SurfaceMsg) -> Task<Message> {
    match m {
        SurfaceMsg::ToggleLauncher => {
            let _ = ctl::handle_request(
                &app.chrome,
                &app.chrome_epoch,
                &ctl::Request {
                    target: "chrome".into(),
                    method: "launcher".into(),
                    args: vec![],
                },
            );
        }
        SurfaceMsg::ToggleControlCenter => {
            let _ = ctl::handle_request(
                &app.chrome,
                &app.chrome_epoch,
                &ctl::Request {
                    target: "chrome".into(),
                    method: "controlCenter".into(),
                    args: vec![],
                },
            );
        }
        SurfaceMsg::ToggleCalendar => {
            let _ = ctl::handle_request(
                &app.chrome,
                &app.chrome_epoch,
                &ctl::Request {
                    target: "chrome".into(),
                    method: "calendar".into(),
                    args: vec![],
                },
            );
        }
        SurfaceMsg::ToggleWeather => {
            let _ = ctl::handle_request(
                &app.chrome,
                &app.chrome_epoch,
                &ctl::Request {
                    target: "chrome".into(),
                    method: "weather".into(),
                    args: vec![],
                },
            );
            app.weather = platform::weather_glance();
        }
        SurfaceMsg::ToggleNotifications => {
            let _ = ctl::handle_request(
                &app.chrome,
                &app.chrome_epoch,
                &ctl::Request {
                    target: "chrome".into(),
                    method: "notifications".into(),
                    args: vec![],
                },
            );
        }
        SurfaceMsg::CenterTab(i) => {
            if let Ok(mut s) = app.chrome.lock() {
                if i == 0 {
                    s.calendar_open = true;
                    s.notifications_open = false;
                } else {
                    s.notifications_open = true;
                    s.calendar_open = false;
                }
                s.weather_open = false;
                s.control_center_open = false;
                s.launcher_open = false;
            }
            app.chrome_epoch.fetch_add(1, Ordering::Relaxed);
        }
        SurfaceMsg::CloseCenterHub => {
            if let Ok(mut s) = app.chrome.lock() {
                s.calendar_open = false;
                s.notifications_open = false;
                s.weather_open = false;
            }
            app.chrome_epoch.fetch_add(1, Ordering::Relaxed);
        }
        SurfaceMsg::DesktopPress => {
            if !app.chrome_snap.widgets_customize {
                app.desktop_hold_at = Some(Instant::now());
            }
        }
        SurfaceMsg::DesktopRelease => {
            app.desktop_hold_at = None;
        }
        SurfaceMsg::CustomizeDesktop => {
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
        SurfaceMsg::BeaconInput(q) => {
            if let Ok(mut s) = app.chrome.lock() {
                s.beacon_query = q.clone();
            }
            app.chrome_epoch.fetch_add(1, Ordering::Relaxed);
            app.beacon_hits = proteus_shell::beacon::filter_beacon_hits(
                &q,
                24,
                &app.wm.toplevels,
                app.beacon_mode,
            );
            app.beacon_selected = 0;
            warm_icons(app);
        }
        SurfaceMsg::BeaconSetMode(i) => {
            app.beacon_mode = proteus_shell::beacon::BeaconMode::from_index(i);
            let q = app
                .chrome
                .lock()
                .ok()
                .map(|s| s.beacon_query.clone())
                .unwrap_or_else(|| app.beacon_query.clone());
            app.beacon_hits = proteus_shell::beacon::filter_beacon_hits(
                &q,
                24,
                &app.wm.toplevels,
                app.beacon_mode,
            );
            app.beacon_selected = 0;
            warm_icons(app);
        }
        SurfaceMsg::BeaconLaunch(id) => {
            if gate_launch_for_focus(app, &id) {
                return Task::none();
            }
            if gate_launch_for_privacy(app, &id) {
                return Task::none();
            }
            proteus_shell::beacon::launch_hit(&id);
            if let Ok(mut s) = app.chrome.lock() {
                s.launcher_open = false;
            }
            app.chrome_epoch.fetch_add(1, Ordering::Relaxed);
        }
        SurfaceMsg::BeaconNav(delta) => {
            let count = app.beacon_hits.len().min(12);
            if count > 0 {
                let cur = app.beacon_selected as i32;
                app.beacon_selected = (cur + delta).rem_euclid(count as i32) as usize;
            }
        }
        SurfaceMsg::BeaconSubmit => {
            if let Some(hit) = app.beacon_hits.get(app.beacon_selected).cloned() {
                return handle_surface(app, SurfaceMsg::BeaconLaunch(hit));
            }
        }
        SurfaceMsg::BeaconEscape => {
            let clear_query = !app.beacon_query.is_empty();
            if let Ok(mut s) = app.chrome.lock() {
                if clear_query {
                    s.beacon_query.clear();
                } else {
                    s.launcher_open = false;
                }
            }
            app.chrome_epoch.fetch_add(1, Ordering::Relaxed);
            if clear_query {
                app.beacon_hits = proteus_shell::beacon::filter_beacon_hits(
                    "",
                    24,
                    &app.wm.toplevels,
                    app.beacon_mode,
                );
                app.beacon_selected = 0;
            }
        }
        SurfaceMsg::HudDismiss => {
            let _ = ctl::handle_request(
                &app.chrome,
                &app.chrome_epoch,
                &ctl::Request {
                    target: "hud".into(),
                    method: "hide".into(),
                    args: vec![],
                },
            );
        }
        SurfaceMsg::ToastDismiss(id) => {
            if let Ok(mut n) = app.notifs.lock() {
                n.items.retain(|x| x.id != id);
            }
        }
        SurfaceMsg::PrivacyAllow => {
            let (cat, app_id, pending) = {
                let s = app.chrome.lock().ok();
                s.map(|g| {
                    (
                        g.privacy_ask.clone(),
                        g.privacy_ask_app.clone(),
                        g.privacy_ask_pending.clone(),
                    )
                })
                .unwrap_or((None, None, None))
            };
            if let (Some(cat), Some(aid)) = (cat.as_deref(), app_id.as_deref()) {
                // Wait for session file so resume launch sees Allow-once.
                let _ = std::process::Command::new("proteus-permissions.py")
                    .args(["session-allow", aid, cat])
                    .output();
            }
            clear_privacy_ask(app);
            if let Some(pending) = pending {
                proteus_shell::beacon::launch_hit(&pending);
            }
        }
        SurfaceMsg::PrivacyDeny => {
            let (cat, app_id) = {
                let s = app.chrome.lock().ok();
                s.map(|g| (g.privacy_ask.clone(), g.privacy_ask_app.clone()))
                    .unwrap_or((None, None))
            };
            if let (Some(cat), Some(aid)) = (cat.as_deref(), app_id.as_deref()) {
                let _ = std::process::Command::new("proteus-permissions.py")
                    .args(["store-set-app", aid, cat, "deny"])
                    .spawn();
            } else {
                let _ = std::process::Command::new("proteus-permissions.py")
                    .arg("enforce-capture")
                    .spawn();
            }
            clear_privacy_ask(app);
        }
        SurfaceMsg::OpenSettingsPage(page) => {
            let _ = std::process::Command::new("proteus-open")
                .args(["settings", &format!("--page={page}")])
                .spawn();
        }
        SurfaceMsg::OpenSettings => {
            let _ = std::process::Command::new("proteus-open")
                .arg("settings")
                .spawn();
        }
        SurfaceMsg::OpenPrivacy => {
            let _ = std::process::Command::new("proteus-open")
                .args(["settings", "--page=privacy-activity"])
                .spawn();
        }
        _ => unreachable!(),
    }
    Task::none()
}

fn clear_privacy_ask(app: &mut App) {
    if let Ok(mut s) = app.chrome.lock() {
        s.privacy_ask = None;
        s.privacy_ask_app = None;
        s.privacy_ask_pending = None;
    }
    app.privacy_ask = None;
    app.privacy_ask_app = None;
    app.chrome_epoch.fetch_add(1, Ordering::Relaxed);
}
