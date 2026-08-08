//! Snapshot sync, settings reload, dock/spaces ticks.

use std::sync::atomic::Ordering;
use std::thread;
use std::time::{Duration, Instant};

use iced::window;
use iced::Task;

use proteus_shell::anim::{self, Easing};
use proteus_shell::ctl::ChromeState;
use proteus_shell::faces::Face;
use proteus_shell::layers;
use proteus_shell::platform::{
    self,
};
use proteus_shell::surfaces::{self};
use proteus_ui::theme::Theme;

use super::*;

pub(crate) fn sync_snapshots(app: &mut App) {
    let was_launcher = app.launcher_open;
    let was_cc = app.cc_open;
    let was_hub = app.hub_open;
    let was_spaces = app.spaces_open;
    let had_hud = !app.hud_kind.is_empty();
    let prev_hud = app.hud_kind.clone();
    let prev_hud_value = app.hud_value;
    let prev_toast_id = app.toast.as_ref().map(|t| t.id);
    if let Ok(c) = app.chrome.lock() {
        app.launcher_open = c.launcher_open;
        app.cc_open = c.control_center_open;
        app.hub_open = c.calendar_open || c.notifications_open || c.weather_open;
        app.spaces_open = c.spaces_open;
        app.locked = c.locked || c.session_start_lock_pending;
        app.hud_kind = c.hud_kind.clone();
        app.hud_value = c.hud_value;
        app.privacy_ask = c.privacy_ask.clone();
        app.privacy_ask_app = c.privacy_ask_app.clone();
        app.beacon_query = c.beacon_query.clone();
        app.widget_kinds = c.widgets.clone();
        // IPC `widgets add` only updates kind list — place any missing.
        for kind in app.widget_kinds.clone() {
            if !app.desktop_widgets.items.iter().any(|w| w.kind == kind) {
                app.desktop_widgets.add(&kind);
            }
        }
        if app.lock_ui.customize != c.lock_customize {
            app.lock_ui.customize = c.lock_customize;
            if c.lock_customize {
                let mpris = app.mpris.clone();
                let power = app.power.clone();
                app.lock_ui.refresh_applets(&mpris, &power);
            }
        }
        app.chrome_snap = ChromeState {
            launcher_open: c.launcher_open,
            control_center_open: c.control_center_open,
            calendar_open: c.calendar_open,
            weather_open: c.weather_open,
            notifications_open: c.notifications_open,
            spaces_open: c.spaces_open,
            locked: c.locked,
            session_start_lock_pending: c.session_start_lock_pending,
            protocol_lock: c.protocol_lock,
            hud_kind: c.hud_kind.clone(),
            hud_value: c.hud_value,
            toast_queue: c.toast_queue.clone(),
            privacy_ask: c.privacy_ask.clone(),
            privacy_ask_app: c.privacy_ask_app.clone(),
            privacy_ask_pending: c.privacy_ask_pending.clone(),
            widgets_customize: c.widgets_customize,
            lock_customize: c.lock_customize,
            widgets: c.widgets.clone(),
            widgets_snap: c.widgets_snap,
            face: c.face.clone(),
            beacon_query: c.beacon_query.clone(),
            console_nav_open: c.console_nav_open,
            console_switcher_open: c.console_switcher_open,
            console_tab: c.console_tab,
        };
    }
    if let Ok(n) = app.notifs.lock() {
        app.toast = n.items.last().cloned();
        app.notif_items = n.items.clone();
    }
    if let Ok(t) = app.tray.lock() {
        app.tray_items = t.items.clone();
    }
    // WM state is pulled via pull_wm() — avoid double-clone here.
    app.last_epoch = app.chrome_epoch.load(Ordering::Relaxed);

    // Motion transitions (QML parity timings).
    if app.launcher_open != was_launcher {
        app.anims.beacon.animate_to(
            if app.launcher_open { 1.0 } else { 0.0 },
            180,
            Easing::OutCubic,
        );
        if app.launcher_open {
            app.beacon_selected = 0;
            app.beacon_focus_pending = true;
        }
    }
    if app.cc_open != was_cc || app.hub_open != was_hub {
        let open = app.cc_open || app.hub_open;
        let was_open = was_cc || was_hub;
        if open != was_open {
            app.anims
                .cc
                .animate_to(if open { 1.0 } else { 0.0 }, 200, Easing::OutCubic);
        }
    }
    if app.spaces_open && !was_spaces {
        app.spaces_need_thumbs = true;
        app.spaces_rename_id = None;
        app.spaces_drag = None;
        app.spaces_drag_output = None;
        app.spaces_drag_target = None;
        app.spaces_drag_target_output = None;
        app.anims.spaces.set(0.0);
        app.anims.spaces.animate_to(1.0, 180, Easing::OutCubic);
    }
    if !app.spaces_open && was_spaces {
        app.spaces_thumbs.clear();
        app.spaces_rename_id = None;
        app.spaces_rename_buf.clear();
        app.spaces_drag = None;
        app.spaces_drag_output = None;
        app.spaces_drag_target = None;
        app.spaces_drag_target_output = None;
        app.spaces_need_thumbs = false;
        app.anims.spaces.set(0.0);
    }
    let has_hud = !app.hud_kind.is_empty();
    if has_hud && (!had_hud || app.hud_kind != prev_hud || app.hud_value != prev_hud_value) {
        if !had_hud {
            app.anims.hud.animate_to(1.0, 160, Easing::OutCubic);
        }
        app.hud_deadline = Some(anim::Deadline::after_ms(1500));
    } else if !has_hud && had_hud {
        app.anims.hud.set(0.0);
        app.hud_deadline = None;
    }
    let toast_id = app.toast.as_ref().map(|t| t.id);
    if toast_id != prev_toast_id {
        match toast_id {
            Some(id) => {
                app.anims.toast.animate_to(1.0, 160, Easing::OutCubic);
                app.toast_deadline = Some((id, anim::Deadline::after_ms(4500)));
            }
            None => {
                app.anims.toast.set(0.0);
                app.toast_deadline = None;
            }
        }
    }
}

/// Cheap WM pull from the socket listener — never blocks on compositor ctl.
/// Returns true when the UI snapshot actually changed (`gen` advanced).
pub(crate) fn pull_wm(app: &mut App) -> bool {
    let Ok(h) = app.wm_shared.try_lock() else {
        return false;
    };
    if h.gen == app.wm_gen {
        return false;
    }
    app.wm_gen = h.gen;
    app.wm = h.state.clone();
    true
}

/// Coalesce dock scrub samples — sub-pixel spam rebuilt the whole shelf.

/// Flush debounced CC volume / brightness to helpers off the UI thread.
pub(crate) fn flush_pending_sliders(app: &mut App) {
    let Some(at) = app.slider_flush_at else {
        return;
    };
    if Instant::now() < at {
        return;
    }
    app.slider_flush_at = None;
    if let Some(v) = app.pending_volume.take() {
        thread::spawn(move || {
            let _ = platform::volume_set(v);
        });
    }
    if let Some(b) = app.pending_brightness.take() {
        thread::spawn(move || {
            let _ = platform::brightness_set(b);
        });
    }
}

pub(crate) fn refresh_heavy(app: &mut App) {
    let _ = pull_wm(app);
    // Copy the worker-gathered snapshot. Never block: skip if the worker
    // holds the lock right now — next tick picks it up.
    app.heavy.cc_open.store(app.cc_open || app.hub_open, Ordering::Relaxed);
    if let Ok(s) = app.heavy.snap.try_lock() {
        app.power = s.power.clone();
        app.privacy_dots = s.privacy.clone();
        // Thin capture enforce while indicators are lit (Deny/Ask + no session grant).
        let dots = app.privacy_dots.mic || app.privacy_dots.camera || app.privacy_dots.screen;
        if dots {
            let due = app
                .privacy_enforce_at
                .map(|t| t.elapsed() >= Duration::from_secs(12))
                .unwrap_or(true);
            if due {
                app.privacy_enforce_at = Some(Instant::now());
                thread::spawn(|| {
                    let _ = std::process::Command::new("proteus-permissions.py")
                        .arg("enforce-capture")
                        .output();
                });
            }
        }
        app.dnd = s.dnd;
        app.volume = s.volume;
        app.brightness = s.brightness;
        app.mpris = s.mpris.clone();
        if app.cc_open {
            app.wifi_hits = s.wifi.clone();
            app.bt_hits = s.bt.clone();
            app.focus_on = s.focus_on;
            app.focus_profiles = s.focus_profiles.clone();
            app.focus_active_id = s.focus_active_id.clone();
        }
        if app.face == Face::Console {
            app.console_games = s.console_games.clone();
            app.console_media_path = s.console_media_path.clone();
            app.console_apps = s.console_apps.clone();
        }
        if app.face == Face::Host {
            app.host_glance = s.host_glance.clone();
        }
    }
    apply_settings_if_changed(app);
    // Focus schedule auto-apply (edge-triggered; schedule.enabled on active profile).
    app.focus_schedule_last = platform::apply_focus_schedule(app.focus_schedule_last);
    if app.focus_schedule_last.is_some() {
        app.focus_on = platform::focus_active();
    }
    if app.locked {
        // Values only — widgets list is cached (reload on Customize / settings).
        app.lock_ui.refresh_applets(&app.mpris, &app.power);
    }
}

/// Reload theme / dock pins / wallpaper only when settings.json mtime changes.
pub(crate) fn apply_settings_if_changed(app: &mut App) {
    let base = proteus_shell_core::facts::config_base();
    let path = base.join("proteus/settings.json");
    let mtime = std::fs::metadata(&path).and_then(|m| m.modified()).ok();
    if mtime.is_some() && mtime == app.settings_mtime {
        return;
    }
    app.settings_mtime = mtime;
    let settings = proteus_shell_core::facts::read_settings(&base);
    app.theme = Theme::from_settings(&settings);
    let next_icon = settings
        .get("dockIconSize")
        .and_then(|v| v.as_i64())
        .unwrap_or(48)
        .clamp(32, 72) as f32;
    let next_layout = surfaces::DockLayout::parse(
        settings
            .get("dockLayout")
            .and_then(|v| v.as_str())
            .unwrap_or("center"),
    );
    let next_rounding = settings
        .get("dockRounding")
        .and_then(|v| v.as_i64())
        .unwrap_or(16)
        .clamp(0, 28) as f32;
    let next_enabled = settings
        .get("dockEnabled")
        .and_then(|v| v.as_bool())
        .unwrap_or(true);
    let next_autohide = settings
        .get("dockAutoHide")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    let next_bar_h = surfaces::bar_exclusive(
        settings
            .get("barHeight")
            .and_then(|v| v.as_i64())
            .unwrap_or(38)
            .clamp(28, 48) as u32,
    );
    let next_bar_r = settings
        .get("barRounding")
        .and_then(|v| v.as_i64())
        .unwrap_or(0)
        .clamp(0, 24) as f32;
    let next_bar_ah = settings
        .get("barAutoHide")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    let geom_dirty = (next_icon - app.dock_icon_size).abs() > f32::EPSILON
        || next_layout != app.dock_layout
        || next_enabled != app.dock_enabled
        || next_bar_h != app.bar_height;
    app.dock_icon_size = next_icon;
    if next_layout != app.dock_layout {
        app.dock_geom_dirty = true;
    }
    app.dock_layout = next_layout;
    app.dock_rounding = next_rounding;
    app.dock_enabled = next_enabled;
    app.dock_autohide = next_autohide;
    app.bar_height = next_bar_h;
    app.bar_rounding = next_bar_r;
    app.bar_autohide = next_bar_ah;
    if !next_autohide {
        app.anims.dock_slide.set(1.0);
        app.dock_edge_armed = true;
    }
    if !next_bar_ah {
        app.anims.bar_slide.set(1.0);
        app.bar_edge_armed = true;
    }
    if geom_dirty {
        app.layer_input_applied.retain(|id, _| {
            app.windows
                .get(id)
                .map(|ns| ns.as_str() != layers::DOCK && ns.as_str() != layers::BAR)
                .unwrap_or(true)
        });
        app.dock_exclusive_zone = None;
        app.bar_exclusive_zone = None;
    }
    app.workspace_names = proteus_shell::spaces::parse_workspace_names(&settings);
    app.workspace_mode = settings
        .get("workspaceMode")
        .and_then(|v| v.as_str())
        .unwrap_or("synced")
        .to_string();
    let pins = surfaces::dock_pins_from_settings(&settings);
    // Don't clobber in-memory reorder/unpin while Edit Dock is open.
    if !app.dock_edit && pins != app.pins {
        app.pins = pins;
        warm_icons(app);
    }
    refresh_wallpaper_from(app, &settings);
    // Lock strip layout may have changed with settings.
    if app.locked || app.lock_ui.customize {
        app.lock_ui.reload_widgets();
    }
}

/// Re-resolve wallpaper; reload the image handle only when the path changes
/// so the texture uploads once (not per view).
pub(crate) fn refresh_wallpaper_from(app: &mut App, settings: &serde_json::Value) {
    let wp = platform::wallpaper_from_settings(settings);
    if wp == app.wallpaper && app.wallpaper_handle.is_some() == wp.path.is_some() {
        return;
    }
    app.wallpaper_handle = match &wp.path {
        Some(p) => {
            let keep = app
                .wallpaper_handle
                .take()
                .filter(|(cached, _)| cached == p);
            keep.or_else(|| {
                Some((
                    p.clone(),
                    iced::widget::image::Handle::from_path(p),
                ))
            })
        }
        None => None,
    };
    app.wallpaper = wp;
}

pub(crate) fn namespace_for(app: &App, id: window::Id) -> &str {
    app.windows
        .get(&id)
        .map(|s| s.as_str())
        .unwrap_or(app.primary_namespace.as_str())
}

pub(crate) fn boot_extra_layers(app: &mut App) -> Task<Message> {
    if app.single_surface {
        return Task::none();
    }
    let mut tasks = Vec::new();
    for ns in app.face.boot_layers() {
        let id = window::Id::unique();
        app.windows.insert(id, (*ns).to_string());
        let settings = new_layer_settings(ns);
        tasks.push(Task::done(Message::NewLayerShell { settings, id }));
    }
    Task::batch(tasks)
}

/// When locked, chrome overlays empty out (QS sessionStartLockPending / sessionLocked).
pub(crate) fn session_chrome_suppressed(app: &App) -> bool {
    app.locked
}

/// Focus the Beacon search input right after the launcher opens.
pub(crate) fn take_beacon_focus(app: &mut App) -> Task<Message> {
    if app.beacon_focus_pending {
        app.beacon_focus_pending = false;
        iced::widget::operation::focus("beacon-input")
    } else {
        Task::none()
    }
}

pub(crate) fn take_spaces_rename_focus(app: &mut App) -> Task<Message> {
    if app.spaces_rename_focus_pending {
        app.spaces_rename_focus_pending = false;
        iced::widget::operation::focus("spaces-rename-input")
    } else {
        Task::none()
    }
}

pub(crate) fn take_lock_password_focus(app: &mut App) -> Task<Message> {
    if app.lock_password_focus_pending {
        app.lock_password_focus_pending = false;
        iced::widget::operation::focus("lock-password-input")
    } else {
        Task::none()
    }
}

pub(crate) fn lock_pin_mode(app: &App) -> bool {
    app.lock_ui.pin_configured && !app.lock_ui.use_password
}

/// Kick grim thumbnails for every visible overview window (off UI thread).
pub(crate) fn capture_spaces_thumbs(app: &mut App) -> Task<Message> {
    if !app.spaces_open || app.locked {
        return Task::none();
    }
    let mut jobs = Vec::new();
    if app.wm.monitors.len() > 1 {
        for mon in &app.wm.monitors {
            let occupied =
                proteus_shell::spaces::occupied_space_ids_for_output(&app.wm, &mon.name);
            let visible = proteus_shell::spaces::visible_space_ids(
                mon.active_workspace,
                &occupied,
                app.spaces_floor,
            );
            for t in &app.wm.toplevels {
                if !visible.contains(&t.workspace) {
                    continue;
                }
                if !t.output.is_empty() && t.output != mon.name {
                    continue;
                }
                jobs.push((t.address.clone(), t.title.clone(), t.workspace));
                if jobs.len() >= 24 {
                    break;
                }
            }
            if jobs.len() >= 24 {
                break;
            }
        }
    } else {
        let occupied = proteus_shell::spaces::occupied_space_ids(&app.wm);
        let visible = proteus_shell::spaces::visible_space_ids(
            app.wm.active_workspace,
            &occupied,
            app.spaces_floor,
        );
        for t in &app.wm.toplevels {
            if !visible.contains(&t.workspace) {
                continue;
            }
            jobs.push((t.address.clone(), t.title.clone(), t.workspace));
            if jobs.len() >= 24 {
                break;
            }
        }
    }
    // Scratchpad card thumbs (`special:scratch` · -98) — global park, not in 1..=10.
    if jobs.len() < 24 {
        for t in &app.wm.toplevels {
            if t.workspace != proteus_shell::wm_ipc::SCRATCH_WORKSPACE {
                continue;
            }
            if jobs.iter().any(|(a, _, _)| a == &t.address) {
                continue;
            }
            jobs.push((t.address.clone(), t.title.clone(), t.workspace));
            if jobs.len() >= 24 {
                break;
            }
        }
    }
    if jobs.is_empty() {
        app.spaces_thumbs.clear();
        return Task::none();
    }
    Task::perform(
        async move {
            tokio::task::spawn_blocking(move || {
                let mut rows = Vec::new();
                for (address, title, workspace) in jobs {
                    let bytes = platform::dock_preview_capture(&address).unwrap_or_default();
                    rows.push((address, title, workspace, bytes));
                }
                rows
            })
            .await
            .unwrap_or_default()
        },
        Message::SpacesThumbsReady,
    )
}

pub(crate) fn take_spaces_thumbs_task(app: &mut App) -> Task<Message> {
    if app.spaces_need_thumbs {
        app.spaces_need_thumbs = false;
        capture_spaces_thumbs(app)
    } else {
        Task::none()
    }
}

/// Kick grim thumbnail capture off the UI thread (dwell preview).
pub(crate) fn capture_dock_preview(app: &mut App, pin: &str) -> Task<Message> {
    if app.locked {
        app.dock_preview = None;
        return Task::none();
    }
    let mut jobs = Vec::new();
    for t in &app.wm.toplevels {
        if !surfaces::pin_matches(pin, &t.class, &t.title) {
            continue;
        }
        jobs.push((
            t.address.clone(),
            t.title.clone(),
            t.workspace < 0,
        ));
        if jobs.len() >= 4 {
            break;
        }
    }
    if jobs.is_empty() {
        app.dock_preview = None;
        return Task::none();
    }
    let pin = pin.to_string();
    Task::perform(
        async move {
            tokio::task::spawn_blocking(move || {
                let mut rows = Vec::new();
                for (address, title, hidden) in jobs {
                    let bytes = platform::dock_preview_capture(&address).unwrap_or_default();
                    rows.push((address, title, hidden, bytes));
                }
                (pin, rows)
            })
            .await
            .unwrap_or_else(|_| (String::new(), Vec::new()))
        },
        |(pin, rows)| Message::DockPreviewReady { pin, rows },
    )
}

/// Drop finished launch bounces and refresh view strengths (~30fps via AnimTick).
pub(crate) fn dock_bounce_tick(app: &mut App) {
    if app.dock_bounce.is_empty() {
        if !app.dock_bounce_strengths.is_empty() {
            app.dock_bounce_strengths.clear();
        }
        return;
    }
    let timeout = Duration::from_millis(surfaces::DOCK_BOUNCE_TIMEOUT_MS);
    app.dock_bounce.retain(|pin, start| {
        if start.elapsed() >= timeout {
            return false;
        }
        let appeared = app
            .wm
            .toplevels
            .iter()
            .any(|t| surfaces::pin_matches(pin, &t.class, &t.title));
        !appeared
    });
    app.dock_bounce_strengths = app
        .dock_bounce
        .iter()
        .map(|(pin, start)| {
            let t = start.elapsed().as_secs_f32();
            // Scale + lift share this envelope (view applies Y pad from strength).
            // Stronger Windows-style launch pulse (was ×14 / 2.5s).
            let strength = (t * 16.0).sin().abs();
            (pin.clone(), strength)
        })
        .collect();
}

/// Apply delayed dock leave once the bridge window expires.
pub(crate) fn dock_leave_tick(app: &mut App) {
    let Some(at) = app.dock_leave_at else {
        return;
    };
    if Instant::now() < at {
        return;
    }
    app.dock_leave_at = None;
    app.dock_preview = None;
    app.dock_dwell = None;
    app.dock_edge_armed = false;
    app.anims.dock_hover.animate_to(0.0, 70, Easing::OutCubic);
    app.dock_hover_pin = None;
    if app.dock_autohide {
        app.anims
            .dock_slide
            .animate_to(0.0, 180, Easing::OutCubic);
    }
}

pub(crate) fn cancel_dock_leave(app: &mut App) {
    app.dock_leave_at = None;
}

/// Resolve app icons for dock pins + current Beacon hits (memoized).
pub(crate) fn warm_icons(app: &mut App) {
    let keys: Vec<String> = app
        .pins
        .iter()
        .cloned()
        .chain(
            surfaces::dock_transients(&app.pins, &app.wm)
                .into_iter(),
        )
        .chain(app.beacon_hits.iter().filter_map(|h| {
            h.rsplit(" · ")
                .next()
                .filter(|tail| tail.ends_with(".desktop"))
                .map(|s| s.to_string())
        }))
        .collect();
    for key in keys {
        app.icon_cache.ensure(&key);
    }
}

/// Auto-hide deadlines — HUD 1500ms, toast 4500ms (QML StatusHud / toast).
pub(crate) fn expire_overlays(app: &mut App) {
    if let Some(d) = app.hud_deadline {
        if d.expired() && !app.hud_kind.is_empty() {
            if let Ok(mut s) = app.chrome.lock() {
                s.hud_kind.clear();
            }
            app.chrome_epoch.fetch_add(1, Ordering::Relaxed);
            app.hud_deadline = None;
            app.hud_kind.clear();
            app.anims.hud.animate_to(0.0, 160, Easing::OutCubic);
        }
    }
    if let Some((id, d)) = app.toast_deadline {
        if d.expired() {
            app.toast_hidden_id = Some(id);
            app.toast_deadline = None;
            app.anims.toast.animate_to(0.0, 140, Easing::InCubic);
        }
    }
}
