use std::time::{Duration, Instant};

use iced::Task;

use proteus_shell::ctl;
use proteus_shell::faces::Face;
use proteus_shell::platform;
use proteus_shell::surfaces::Message as SurfaceMsg;
use proteus_shell::wm_ipc;
use proteus_ui::theme::Theme;

use super::super::*;
use super::handle_surface;

pub(crate) fn handle(app: &mut App, m: SurfaceMsg) -> Task<Message> {
    match m {
        SurfaceMsg::CcRefresh => {
            app.wifi_hits = platform::wifi_list_thin();
            app.bt_hits = platform::bt_list_thin();
            app.wifi_radio_on = platform::wifi_radio_enabled();
            app.bt_radio_on = platform::bt_radio_enabled();
        }
        SurfaceMsg::WifiRadioToggle => {
            match platform::wifi_radio_toggle() {
                Ok(on) => {
                    app.wifi_radio_on = on;
                    app.wifi_err.clear();
                    if on {
                        app.wifi_hits = platform::wifi_list_thin();
                    }
                }
                Err(e) => app.wifi_err = e,
            }
        }
        SurfaceMsg::BtRadioToggle => {
            match platform::bt_radio_toggle() {
                Ok(on) => {
                    app.bt_radio_on = on;
                    app.bt_err.clear();
                    if on {
                        app.bt_hits = platform::bt_list_thin();
                    }
                }
                Err(e) => app.bt_err = e,
            }
        }
        SurfaceMsg::AppearanceMode(i) => {
            let mode = if i == 1 { "light" } else { "dark" };
            if platform::set_chrome_mode(mode).is_ok() {
                let base = proteus_shell_core::facts::config_base();
                app.theme =
                    Theme::from_settings(&proteus_shell_core::facts::read_settings(&base));
            }
        }
        SurfaceMsg::Screenshot(kind) => {
            if let Err(e) = platform::screenshot(&kind) {
                eprintln!("proteus-shell: screenshot: {e}");
            }
        }
        SurfaceMsg::NotifClearAll => {
            if let Ok(mut n) = app.notifs.lock() {
                n.items.clear();
            }
        }
        SurfaceMsg::FaceSelect(i) => {
            let tab = i.min(4);
            let _ = ctl::handle_request(
                &app.chrome,
                &app.chrome_epoch,
                &ctl::Request {
                    target: "chrome".into(),
                    method: "consoleTab".into(),
                    args: vec![tab.to_string()],
                },
            );
            if tab == 3 {
                return handle_surface(app, SurfaceMsg::ToggleLauncher);
            }
            if tab == 4 {
                let _ = std::process::Command::new("proteus-open")
                    .arg("settings")
                    .spawn();
            }
        }
        SurfaceMsg::Refresh => {
            refresh_heavy(app);
            if app.face == Face::Console {
                app.console_games = platform::console_games_list();
                app.console_media_path = platform::console_media_path();
                app.console_apps = platform::console_apps_thin(32);
            }
            if app.face == Face::Host {
                app.host_glance = platform::host_glance();
            }
        }
        SurfaceMsg::BrightnessSet(pct) => {
            // Optimistic UI; pactl/brightnessctl flush off-thread (debounced).
            app.brightness = Some(pct);
            app.pending_brightness = Some(pct);
            app.slider_flush_at = Some(Instant::now() + Duration::from_millis(40));
            let _ = ctl::handle_request(
                &app.chrome,
                &app.chrome_epoch,
                &ctl::Request {
                    target: "hud".into(),
                    method: "brightness".into(),
                    args: vec![pct.to_string()],
                },
            );
        }
        SurfaceMsg::BrightnessStep(delta) => {
            let cur = app.brightness.or_else(platform::brightness_get).unwrap_or(50);
            let next = (cur as i16 + delta as i16).clamp(0, 100) as u8;
            let _ = platform::brightness_set(next);
            app.brightness = Some(next);
            let _ = ctl::handle_request(
                &app.chrome,
                &app.chrome_epoch,
                &ctl::Request {
                    target: "hud".into(),
                    method: "brightness".into(),
                    args: vec![next.to_string()],
                },
            );
        }
        SurfaceMsg::PowerProfile(idx) => {
            let _ = platform::power_set_profile_index(idx);
            app.power = platform::power_status();
        }
        SurfaceMsg::ToggleFloating => {
            let _ = wm_ipc::dispatch("togglefloating");
        }
        SurfaceMsg::VolumeMute => {
            let _ = ctl::handle_request(
                &app.chrome,
                &app.chrome_epoch,
                &ctl::Request {
                    target: "hud".into(),
                    method: "volumeMute".into(),
                    args: vec![],
                },
            );
            app.volume = platform::volume_get().or(app.volume);
        }
        SurfaceMsg::VolumeStep(delta) => {
            if delta != 0 {
                if let Some(v) = platform::volume_step(delta) {
                    app.volume = Some(v);
                    let _ = ctl::handle_request(
                        &app.chrome,
                        &app.chrome_epoch,
                        &ctl::Request {
                            target: "hud".into(),
                            method: "volume".into(),
                            args: vec![v.to_string()],
                        },
                    );
                }
            }
        }
        SurfaceMsg::VolumeSet(pct) => {
            app.volume = Some(pct);
            app.pending_volume = Some(pct);
            app.slider_flush_at = Some(Instant::now() + Duration::from_millis(40));
        }
        SurfaceMsg::MediaPlayPause(bus) => {
            if let Err(e) = platform::mpris_control(&bus, "PlayPause") {
                eprintln!("proteus-shell: {e}");
            }
            app.mpris = platform::mpris_players();
        }
        SurfaceMsg::MediaNext(bus) => {
            if let Err(e) = platform::mpris_control(&bus, "Next") {
                eprintln!("proteus-shell: {e}");
            }
            app.mpris = platform::mpris_players();
        }
        SurfaceMsg::MediaPrev(bus) => {
            if let Err(e) = platform::mpris_control(&bus, "Previous") {
                eprintln!("proteus-shell: {e}");
            }
            app.mpris = platform::mpris_players();
        }
        SurfaceMsg::NotifDismiss(id) => {
            if let Ok(mut n) = app.notifs.lock() {
                n.items.retain(|x| x.id != id);
            }
        }
        SurfaceMsg::LaunchGame(key) => {
            if let Err(e) = platform::console_launch_game(&key) {
                eprintln!("proteus-shell: launch game: {e}");
            }
        }
        SurfaceMsg::HostTab(i) => {
            app.host_tab = i.min(2);
        }
        SurfaceMsg::ToggleDnd => {
            let next = !app.dnd;
            if platform::set_notifications_dnd(next).is_ok() {
                app.dnd = next;
                if let Ok(mut n) = app.notifs.lock() {
                    n.dnd = next;
                }
            }
        }
        SurfaceMsg::WifiConnect(ssid) => {
            match platform::wifi_connect(&ssid) {
                Ok(()) => {
                    app.wifi_err.clear();
                    app.wifi_hits = platform::wifi_list_thin();
                }
                Err(e) => app.wifi_err = e,
            }
        }
        SurfaceMsg::BtConnect(mac) => {
            match platform::bt_connect(&mac) {
                Ok(()) => {
                    app.bt_err.clear();
                    app.bt_hits = platform::bt_list_thin();
                }
                Err(e) => app.bt_err = e,
            }
        }
        SurfaceMsg::OpenMediaPath => {
            let path = app.console_media_path.clone();
            if let Err(e) = platform::open_path(&path) {
                eprintln!("proteus-shell: open media: {e}");
            }
        }
        SurfaceMsg::LaunchConsoleApp(id) => {
            let hit = if id.contains(".desktop") {
                id
            } else {
                format!("{id}.desktop")
            };
            proteus_shell::beacon::launch_hit(&hit);
        }
        SurfaceMsg::ToggleFocus => {
            let next = if app.focus_on { "off" } else { "indefinite" };
            if platform::set_focus_mode(next).is_ok() {
                app.focus_on = platform::focus_active();
            }
        }
        SurfaceMsg::FocusProfile(id) => {
            if platform::set_focus_active_profile(&id).is_ok() {
                app.focus_active_id = id;
                app.focus_profiles = platform::focus_profiles();
            }
        }
        SurfaceMsg::OpenConsoleSettingsPage(page) => {
            let _ = std::process::Command::new("proteus-open")
                .arg("settings")
                .arg(format!("--page={page}"))
                .spawn()
                .or_else(|_| {
                    std::process::Command::new("proteus-open")
                        .arg("settings")
                        .spawn()
                });
        }
        SurfaceMsg::OpenWorkloads => {
            let tab = match app.host_tab {
                1 => "shares",
                2 => "apps",
                _ => "workloads",
            };
            let _ = std::process::Command::new("proteus-workloads")
                .arg(tab)
                .spawn()
                .or_else(|_| {
                    std::process::Command::new("proteus-open")
                        .arg("workloads")
                        .spawn()
                });
        }
        _ => unreachable!(),
    }
    Task::none()
}
