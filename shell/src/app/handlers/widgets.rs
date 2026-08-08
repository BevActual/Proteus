use std::sync::atomic::Ordering;

use iced::Task;

use proteus_shell::ctl;
use proteus_shell::surfaces::Message as SurfaceMsg;

use super::super::*;
use super::handle_surface;

pub(crate) fn handle(app: &mut App, m: SurfaceMsg) -> Task<Message> {
    match m {
        SurfaceMsg::WidgetAdd(kind) => {
            app.desktop_widgets.add(&kind);
            app.widget_kinds = app.desktop_widgets.kinds();
            if let Ok(mut s) = app.chrome.lock() {
                s.widgets = app.widget_kinds.clone();
                if !s.widgets_customize {
                    s.widgets_customize = true;
                }
            }
            app.chrome_epoch.fetch_add(1, Ordering::Relaxed);
            let _ = app.desktop_widgets.persist();
        }
        SurfaceMsg::WidgetRemove(id) => {
            app.desktop_widgets.remove(&id);
            app.widget_kinds = app.desktop_widgets.kinds();
            if let Ok(mut s) = app.chrome.lock() {
                s.widgets = app.widget_kinds.clone();
            }
            app.chrome_epoch.fetch_add(1, Ordering::Relaxed);
            let _ = app.desktop_widgets.persist();
        }
        SurfaceMsg::WidgetSelect(id) => {
            app.desktop_widgets.select(&id);
        }
        SurfaceMsg::WidgetDragStart(id) => {
            app.desktop_widgets.start_drag(&id);
        }
        SurfaceMsg::WidgetDrag(x, y) => {
            let snap = app.chrome_snap.widgets_snap;
            app.desktop_widgets.drag_to(x, y, snap, (1920.0, 1080.0));
        }
        SurfaceMsg::WidgetDragEnd => {
            app.desktop_widgets.end_drag();
            let _ = app.desktop_widgets.persist();
        }
        SurfaceMsg::WidgetNudge(dx, dy) => {
            let snap = app.chrome_snap.widgets_snap;
            app.desktop_widgets.nudge(dx, dy, snap);
            let _ = app.desktop_widgets.persist();
        }
        SurfaceMsg::WidgetSnapToggle => {
            let _ = ctl::handle_request(
                &app.chrome,
                &app.chrome_epoch,
                &ctl::Request {
                    target: "widgets".into(),
                    method: "setSnap".into(),
                    args: vec![],
                },
            );
        }
        SurfaceMsg::WidgetCustomizeDone => {
            let _ = app.desktop_widgets.persist();
            if let Ok(mut s) = app.chrome.lock() {
                s.widgets_customize = false;
            }
            app.chrome_epoch.fetch_add(1, Ordering::Relaxed);
        }
        SurfaceMsg::WidgetActivate(kind) => match kind.as_str() {
            "Clock" | "Calendar" | "WorldClock" => {
                return handle_surface(app, SurfaceMsg::ToggleCalendar);
            }
            "Weather" => {
                return handle_surface(app, SurfaceMsg::ToggleWeather);
            }
            "Battery" => {
                return handle_surface(app, SurfaceMsg::OpenSettingsPage("power".into()));
            }
            "System" => {
                return handle_surface(app, SurfaceMsg::ToggleSpaces);
            }
            _ => {}
        },
        _ => unreachable!(),
    }
    Task::none()
}
