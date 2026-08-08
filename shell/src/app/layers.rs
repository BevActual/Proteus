//! Layer-shell geometry, input reconcile, boot helpers.

use iced::window;
use iced::Task;
use iced_layershell::actions::ActionCallback;
use iced_layershell::reexport::{
    Anchor, KeyboardInteractivity, Layer, NewLayerShellSettings, OutputOption,
};
use iced_layershell::settings::{LayerShellSettings, StartMode};

use proteus_shell::layers;
use proteus_shell::surfaces::{self};

use super::*;

pub(crate) fn load_dock_pins() -> Vec<String> {
    let base = proteus_shell_core::facts::config_base();
    surfaces::dock_pins_from_settings(&proteus_shell_core::facts::read_settings(&base))
}

pub(crate) fn default_beacon_hits() -> Vec<String> {
    proteus_shell::beacon::filter_beacon_hits("", 24, &[])
}

pub(crate) fn dock_layer_geom(layout: surfaces::DockLayout) -> (Anchor, (u32, u32)) {
    match layout {
        surfaces::DockLayout::Left => (
            Anchor::Left | Anchor::Top | Anchor::Bottom,
            (surfaces::DOCK_LAYER_H, 0),
        ),
        surfaces::DockLayout::Right => (
            Anchor::Right | Anchor::Top | Anchor::Bottom,
            (surfaces::DOCK_LAYER_H, 0),
        ),
        _ => (
            Anchor::Bottom | Anchor::Left | Anchor::Right,
            (0, surfaces::DOCK_LAYER_H),
        ),
    }
}

pub(crate) fn layer_settings(namespace: &str) -> LayerShellSettings {
    // Layer-shell protocol: width 0 requires Left+Right anchor, height 0 requires
    // Top+Bottom. Violations are a compositor protocol error that kills the client
    // at boot (khronos-egl panic) — guarded by layer_geometry_tests below.
    let full = Anchor::Top | Anchor::Bottom | Anchor::Left | Anchor::Right;
    let (anchor, size) = match namespace {
        n if n == layers::BAR => (
            Anchor::Top | Anchor::Left | Anchor::Right,
            Some((0, surfaces::BAR_EXCLUSIVE)),
        ),
        // Dock surface hosts shelf + preview band; layout Fact re-anchors later.
        n if n == layers::DOCK => {
            let (a, s) = dock_layer_geom(surfaces::DockLayout::Center);
            (a, Some(s))
        }
        // HUD / toast are top-right chips (CHROME.md), not full-screen overlays.
        n if n == layers::HUD => (Anchor::Top | Anchor::Right, Some((320, 56))),
        n if n == layers::TOAST => (Anchor::Top | Anchor::Right, Some((360, 132))),
        _ => (full, None),
    };
    let layer = match namespace {
        n if n == layers::BG => Layer::Background,
        n if n == layers::DESKTOP_WIDGETS => Layer::Bottom,
        // Dock stays Top (above wallpaper) with a shelf exclusive_zone so
        // windows lay out above it — Bottom put it under widgets / invisible.
        n if n == layers::BAR || n == layers::DOCK => Layer::Top,
        _ => Layer::Overlay,
    };
    let margin = match namespace {
        n if n == layers::HUD => (8, 12, 0, 12),
        // Clear the taller menu bar (BAR_EXCLUSIVE + small gap).
        n if n == layers::TOAST => (surfaces::BAR_EXCLUSIVE as i32 + 14, 12, 0, 12),
        _ => (0, 0, 0, 0),
    };
    LayerShellSettings {
        anchor,
        layer,
        // Bar/dock exclusive zones reserve window work-area. Full-bleed
        // surfaces (wallpaper + lock) must be DontCare (-1) so smithay sizes
        // them to the full output — Neutral (0) after exclusives gets a
        // clipped rect (black under dock / desktop wallpaper bleeding under lock).
        exclusive_zone: match namespace {
            n if n == layers::BAR => surfaces::BAR_EXCLUSIVE as i32,
            // Boot default = rest 48; settings reload pushes ExclusiveZoneChange.
            n if n == layers::DOCK => {
                surfaces::dock_strip_h(surfaces::DOCK_ICON_REST) as i32
            }
            n if n == layers::BG || n == layers::LOCK => -1,
            _ => 0,
        },
        size,
        margin,
        // Only the lock starts with a keyboard grab (session-start lock pending).
        // Launcher/CC get Exclusive dynamically when opened (reconcile_layer_input);
        // a permanently-Exclusive overlay would starve app windows of keyboard.
        keyboard_interactivity: if namespace == layers::LOCK {
            KeyboardInteractivity::Exclusive
        } else {
            KeyboardInteractivity::None
        },
        start_mode: StartMode::Active,
        ..Default::default()
    }
}

/// Pointer input shape for a layer surface.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum InputShape {
    /// Click-through everywhere.
    Empty,
    /// Whole surface interactive.
    Full,
    /// Only the bottom dock strip is interactive (preview area click-through).
    DockStrip,
    /// Dock strip + preview band interactive (dwell card open).
    DockPreview,
}

/// Desired pointer/keyboard interactivity per layer given current chrome state.
/// Idle full-screen overlays must be click-through or they swallow app input.
pub(crate) fn overlay_desired(app: &App, ns: &str) -> (InputShape, KeyboardInteractivity) {
    use KeyboardInteractivity as Ki;
    match ns {
        n if n == layers::LAUNCHER => {
            if app.launcher_open {
                (InputShape::Full, Ki::Exclusive)
            } else {
                (InputShape::Empty, Ki::None)
            }
        }
        n if n == layers::CONTROL_CENTER => {
            if app.cc_open || app.hub_open {
                (InputShape::Full, Ki::Exclusive)
            } else {
                (InputShape::Empty, Ki::None)
            }
        }
        n if n == layers::SPACES => {
            if app.spaces_open {
                (InputShape::Full, Ki::Exclusive)
            } else {
                (InputShape::Empty, Ki::None)
            }
        }
        n if n == layers::LOCK => {
            let active = app.locked && !app.chrome_snap.protocol_lock;
            if active {
                (InputShape::Full, Ki::Exclusive)
            } else {
                (InputShape::Empty, Ki::None)
            }
        }
        n if n == layers::PRIVACY_ASK => (
            if app.privacy_ask.is_some() {
                InputShape::Full
            } else {
                InputShape::Empty
            },
            Ki::None,
        ),
        n if n == layers::DESKTOP_WIDGETS => (
            if app.chrome_snap.widgets_customize || !app.desktop_widgets.items.is_empty() {
                InputShape::Full
            } else {
                InputShape::Empty
            },
            if app.chrome_snap.widgets_customize {
                Ki::OnDemand
            } else {
                Ki::None
            },
        ),
        n if n == layers::TOAST => (
            // Auto-hidden toasts are click-through (still in the CC list).
            match &app.toast {
                Some(t) if app.toast_hidden_id != Some(t.id) => InputShape::Full,
                _ => InputShape::Empty,
            },
            Ki::None,
        ),
        n if n == layers::HUD => (
            if app.hud_kind.is_empty() {
                InputShape::Empty
            } else {
                InputShape::Full
            },
            Ki::None,
        ),
        n if n == layers::DOCK => {
            if !app.dock_enabled {
                (InputShape::Empty, Ki::None)
            } else if app.dock_edit {
                (InputShape::Full, Ki::None)
            } else if app.dock_preview.is_some() && app.anims.dock_hover.value() > 0.05 {
                (InputShape::DockPreview, Ki::None)
            } else {
                (InputShape::DockStrip, Ki::None)
            }
        }
        // Bar / wallpaper stay pointer-interactive, no keyboard grab.
        _ => (InputShape::Full, Ki::None),
    }
}

pub(crate) fn shape_code(shape: InputShape) -> u8 {
    match shape {
        InputShape::Empty => 0,
        InputShape::Full => 1,
        InputShape::DockStrip => 2,
        InputShape::DockPreview => 3,
    }
}

pub(crate) fn ki_code(ki: KeyboardInteractivity) -> u8 {
    match ki {
        KeyboardInteractivity::None => 0,
        KeyboardInteractivity::OnDemand => 1,
        KeyboardInteractivity::Exclusive => 2,
        _ => 3,
    }
}

/// Push input-region + keyboard-interactivity changes for layers whose desired
/// state drifted (open/close, lock, toast). Early ticks force a re-apply since
/// surfaces map asynchronously after NewLayerShell.
pub(crate) fn reconcile_layer_input(app: &mut App) -> Task<Message> {
    if app.tick_n == 10 {
        app.layer_input_applied.clear();
    }
    let mut tasks = Vec::new();
    let entries: Vec<(window::Id, String)> = app
        .windows
        .iter()
        .map(|(id, ns)| (*id, ns.clone()))
        .collect();
    let dock_shown = app.dock_enabled
        && (!app.dock_autohide || app.anims.dock_slide.value() > 0.05 || app.dock_edge_armed);
    let want_zone = if !app.dock_enabled {
        0
    } else if app.dock_autohide && !dock_shown {
        1 // hot-edge peek reservation
    } else {
        surfaces::dock_strip_h(app.dock_icon_size) as i32
    };
    let want_bar_zone = if app.bar_autohide && app.anims.bar_slide.value() < 0.05 {
        1
    } else {
        app.bar_height as i32
    };
    if app.dock_geom_dirty {
        for (id, ns) in &entries {
            if ns.as_str() == layers::DOCK {
                let (anchor, size) = dock_layer_geom(app.dock_layout);
                tasks.push(Task::done(Message::AnchorSizeChange {
                    id: *id,
                    anchor,
                    size,
                }));
            }
        }
        app.dock_geom_dirty = false;
        app.layer_input_applied.retain(|id, _| {
            app.windows
                .get(id)
                .map(|ns| ns.as_str() != layers::DOCK)
                .unwrap_or(true)
        });
    }
    if app.dock_exclusive_zone != Some(want_zone) {
        for (id, ns) in &entries {
            if ns.as_str() == layers::DOCK {
                tasks.push(Task::done(Message::ExclusiveZoneChange {
                    id: *id,
                    zone_size: want_zone,
                }));
            }
        }
        app.dock_exclusive_zone = Some(want_zone);
    }
    if app.bar_exclusive_zone != Some(want_bar_zone) {
        for (id, ns) in &entries {
            if ns.as_str() == layers::BAR {
                tasks.push(Task::done(Message::ExclusiveZoneChange {
                    id: *id,
                    zone_size: want_bar_zone,
                }));
                tasks.push(Task::done(Message::SizeChange {
                    id: *id,
                    size: (0, app.bar_height),
                }));
            }
        }
        app.bar_exclusive_zone = Some(want_bar_zone);
    }
    for (id, ns) in entries {
        let (shape, ki) = overlay_desired(app, &ns);
        let want = (shape_code(shape), ki_code(ki));
        if app.layer_input_applied.get(&id) == Some(&want) {
            continue;
        }
        app.layer_input_applied.insert(id, want);
        let strip_h = surfaces::dock_strip_h(app.dock_icon_size);
        let vertical = app.dock_layout.vertical();
        let callback = ActionCallback::new(move |region| match shape {
            InputShape::Empty => {}
            InputShape::Full => region.add(0, 0, i32::MAX, i32::MAX),
            InputShape::DockStrip if vertical => {
                region.add(0, 0, strip_h as i32, i32::MAX);
            }
            InputShape::DockStrip => region.add(
                0,
                (surfaces::DOCK_LAYER_H - strip_h) as i32,
                i32::MAX,
                strip_h as i32,
            ),
            InputShape::DockPreview => region.add(0, 0, i32::MAX, i32::MAX),
        });
        tasks.push(Task::done(Message::SetInputRegion { id, callback }));
        tasks.push(Task::done(Message::KeyboardInteractivityChange {
            id,
            keyboard_interactivity: ki,
        }));
    }
    if tasks.is_empty() {
        Task::none()
    } else {
        Task::batch(tasks)
    }
}

pub(crate) fn new_layer_settings(namespace: &str) -> NewLayerShellSettings {
    let ls = layer_settings(namespace);
    NewLayerShellSettings {
        size: ls.size,
        layer: ls.layer,
        anchor: ls.anchor,
        exclusive_zone: Some(ls.exclusive_zone),
        margin: Some(ls.margin),
        keyboard_interactivity: ls.keyboard_interactivity,
        output_option: OutputOption::Active,
        events_transparent: false,
        namespace: Some(namespace.to_string()),
    }
}
