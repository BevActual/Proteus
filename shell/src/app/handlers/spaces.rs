use std::sync::atomic::Ordering;

use iced::Task;

use proteus_shell::ctl;
use proteus_shell::surfaces::Message as SurfaceMsg;
use proteus_shell::wm_ipc::{self, focused_monitor};

use super::super::*;

fn workspace_dispatch(app: &App, id: i64, output: Option<&str>) -> String {
    if app.wm.monitors.len() > 1
        && app.workspace_mode == "perDisplay"
        && output.is_some_and(|o| !o.is_empty())
    {
        format!("workspace {id},output:{}", output.unwrap())
    } else {
        format!("workspace {id}")
    }
}

fn drag_same_column(app: &App, hover_output: Option<&str>) -> bool {
    if app.wm.monitors.len() <= 1 {
        return true;
    }
    match (app.spaces_drag_output.as_deref(), hover_output) {
        (Some(src), Some(dst)) => src == dst,
        _ => false,
    }
}

pub(crate) fn handle(app: &mut App, m: SurfaceMsg) -> Task<Message> {
    match m {
        SurfaceMsg::ToggleSpaces => {
            let _ = ctl::handle_request(
                &app.chrome,
                &app.chrome_epoch,
                &ctl::Request {
                    target: "chrome".into(),
                    method: "spaces".into(),
                    args: vec![],
                },
            );
        }
        SurfaceMsg::SpacesEscape => {
            if let Ok(mut c) = app.chrome.lock() {
                if c.spaces_open {
                    c.spaces_open = false;
                    app.chrome_epoch.fetch_add(1, Ordering::Relaxed);
                }
            }
        }
        SurfaceMsg::ScratchToggle => {
            let _ = wm_ipc::scratch_toggle(&app.wm);
        }
        SurfaceMsg::SpacesCycle(dir) => {
            if dir == 0 {
                return Task::none();
            }
            let (active, occupied) = if app.wm.monitors.len() > 1 {
                if let Some(mon) = focused_monitor(&app.wm) {
                    (
                        mon.active_workspace,
                        proteus_shell::spaces::occupied_space_ids_for_output(
                            &app.wm,
                            &mon.name,
                        ),
                    )
                } else {
                    (
                        app.wm.active_workspace,
                        proteus_shell::spaces::occupied_space_ids(&app.wm),
                    )
                }
            } else {
                (
                    app.wm.active_workspace,
                    proteus_shell::spaces::occupied_space_ids(&app.wm),
                )
            };
            let visible = proteus_shell::spaces::visible_space_ids(
                active,
                &occupied,
                app.spaces_floor,
            );
            if let Some(next) = proteus_shell::spaces::cycle_visible(&visible, active, dir) {
                let _ = wm_ipc::dispatch(&format!("workspace {next}"));
            }
        }
        SurfaceMsg::SpacesSelect(id, output) => {
            if app.spaces_drag.is_some() {
                return Task::none();
            }
            if id == wm_ipc::SCRATCH_WORKSPACE {
                let _ = wm_ipc::scratch_toggle(&app.wm);
                return Task::none();
            }
            let cmd = workspace_dispatch(app, id, output.as_deref());
            let _ = wm_ipc::dispatch(&cmd);
            if let Ok(mut c) = app.chrome.lock() {
                c.spaces_open = false;
            }
            app.chrome_epoch.fetch_add(1, Ordering::Relaxed);
        }
        SurfaceMsg::SpacesAdd => {
            let active = if app.wm.monitors.len() > 1 {
                focused_monitor(&app.wm)
                    .map(|m| m.active_workspace)
                    .unwrap_or(app.wm.active_workspace)
            } else {
                app.wm.active_workspace
            };
            let occupied = if app.wm.monitors.len() > 1 {
                focused_monitor(&app.wm)
                    .map(|m| {
                        proteus_shell::spaces::occupied_space_ids_for_output(
                            &app.wm,
                            &m.name,
                        )
                    })
                    .unwrap_or_else(|| proteus_shell::spaces::occupied_space_ids(&app.wm))
            } else {
                proteus_shell::spaces::occupied_space_ids(&app.wm)
            };
            let visible = proteus_shell::spaces::visible_space_ids(
                active,
                &occupied,
                app.spaces_floor,
            );
            let end = visible.last().copied().unwrap_or(1);
            if end < proteus_shell::spaces::SPACE_MAX {
                app.spaces_floor = (end + 1).max(app.spaces_floor);
            }
        }
        SurfaceMsg::SpacesRenameStart(id) => {
            app.spaces_rename_id = Some(id);
            app.spaces_rename_buf = proteus_shell::spaces::space_name(&app.workspace_names, id);
            if app.spaces_rename_buf.starts_with("Space ") {
                app.spaces_rename_buf.clear();
            }
            app.spaces_rename_focus_pending = true;
        }
        SurfaceMsg::SpacesRenameInput(s) => {
            app.spaces_rename_buf = s;
        }
        SurfaceMsg::SpacesRenameCommit => {
            if let Some(id) = app.spaces_rename_id.take() {
                let names = proteus_shell::spaces::names_with_rename(
                    &app.workspace_names,
                    id,
                    &app.spaces_rename_buf,
                );
                let base = proteus_shell_core::facts::config_base();
                let patch = serde_json::json!({ "workspaceNames": names });
                if proteus_shell_core::facts::write_settings(&base, &patch).is_ok() {
                    app.workspace_names = names;
                    app.settings_mtime = None; // force reload next heavy tick
                }
            }
            app.spaces_rename_buf.clear();
        }
        SurfaceMsg::SpacesDragStart(addr) => {
            app.spaces_drag_output = app
                .wm
                .toplevels
                .iter()
                .find(|t| t.address == addr)
                .map(|t| t.output.clone())
                .filter(|o| !o.is_empty());
            app.spaces_drag = Some(addr);
            app.spaces_drag_target = None;
            app.spaces_drag_target_output = None;
        }
        SurfaceMsg::SpacesDragHover(id, output) => {
            let allow = app.spaces_drag.is_some()
                && (id == wm_ipc::SCRATCH_WORKSPACE
                    || drag_same_column(app, output.as_deref()));
            if allow {
                app.spaces_drag_target = Some(id);
                app.spaces_drag_target_output = if id == wm_ipc::SCRATCH_WORKSPACE {
                    None
                } else {
                    output
                };
            }
        }
        SurfaceMsg::SpacesDrop(id, output) => {
            let allow = id == wm_ipc::SCRATCH_WORKSPACE
                || drag_same_column(app, output.as_deref());
            if !allow {
                app.spaces_drag = None;
                app.spaces_drag_output = None;
                app.spaces_drag_target = None;
                app.spaces_drag_target_output = None;
                return Task::none();
            }
            if let Some(addr) = app.spaces_drag.take() {
                let src = app
                    .wm
                    .toplevels
                    .iter()
                    .find(|t| t.address == addr)
                    .map(|t| t.workspace);
                if src != Some(id) {
                    let _ = wm_ipc::move_window_to_workspace(&addr, id);
                    app.spaces_need_thumbs = true;
                }
            }
            app.spaces_drag_output = None;
            app.spaces_drag_target = None;
            app.spaces_drag_target_output = None;
        }
        SurfaceMsg::SpacesThumbRelease(addr) => {
            let drag = app.spaces_drag.clone();
            if drag.as_deref() != Some(addr.as_str()) {
                return Task::none();
            }
            let target = app.spaces_drag_target;
            let src = app
                .wm
                .toplevels
                .iter()
                .find(|t| t.address == addr)
                .map(|t| t.workspace);
            app.spaces_drag = None;
            app.spaces_drag_output = None;
            app.spaces_drag_target = None;
            app.spaces_drag_target_output = None;
            if let Some(dest) = target.filter(|d| Some(*d) != src) {
                let _ = wm_ipc::move_window_to_workspace(&addr, dest);
                app.spaces_need_thumbs = true;
                return Task::none();
            }
            // Focus window and leave overview.
            let _ = wm_ipc::dock_focus_or_restore(&addr, &app.wm);
            if let Ok(mut c) = app.chrome.lock() {
                c.spaces_open = false;
            }
            app.chrome_epoch.fetch_add(1, Ordering::Relaxed);
        }
        _ => unreachable!(),
    }
    Task::none()
}
