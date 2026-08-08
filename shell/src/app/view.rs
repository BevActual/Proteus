//! Layer view dispatch + iced theme/style.

use iced::widget::{column, container, Space};
use iced::window;
use iced::{Alignment, Color, Element, Length};

use proteus_shell::faces::{self, Face};
use proteus_shell::layers;
use proteus_shell::surfaces::{self, Message as SurfaceMsg};
use proteus_ui::theme::ChromeMode;

use super::*;

pub(crate) fn launch_open(id: &str) {
    proteus_shell::beacon::launch_hit(id);
}

pub(crate) fn view_real(app: &App, id: window::Id) -> Element<'_, Message> {
    let ns = namespace_for(app, id);
    let suppressed = session_chrome_suppressed(app);
    let body = match ns {
        n if n == layers::LOCK => {
            if app.locked && !app.chrome_snap.protocol_lock {
                surfaces::lock_view(
                    &app.theme,
                    &app.lock_ui,
                    &app.wallpaper,
                    app.wallpaper_handle.as_ref().map(|(_, h)| h),
                )
            } else {
                surfaces::empty_layer(&app.theme)
            }
        }
        n if n == layers::BAR => {
            if suppressed {
                surfaces::empty_layer(&app.theme)
            } else {
                let bar = surfaces::bar_view(
                    &app.theme,
                    &app.chrome_snap,
                    &app.wm,
                    &app.power,
                    &app.tray_items,
                    &app.privacy_dots,
                    app.dnd,
                    &app.clock,
                    &app.weather,
                    app.notif_items.len(),
                    app.bar_rounding,
                );
                let slide = app.anims.bar_slide.value();
                let hide = (1.0 - slide) * app.bar_height as f32;
                iced::widget::mouse_area(
                    container(column![
                        Space::new().height(Length::Fixed(hide)),
                        bar,
                    ])
                    .width(Length::Fill)
                    .height(Length::Fill)
                    .align_y(Alignment::Start),
                )
                .on_enter(SurfaceMsg::BarEdgeEnter)
                .on_exit(SurfaceMsg::BarLeave)
                .into()
            }
        }
        n if n == layers::DOCK => {
            if suppressed || !app.dock_enabled {
                surfaces::empty_layer(&app.theme)
            } else {
                let slide = if app.dock_autohide {
                    let v = app.anims.dock_slide.value();
                    if !app.dock_edge_armed && v < 0.05 {
                        // Hot-edge peek while fully stowed.
                        surfaces::DOCK_PEEK_SLIDE
                    } else {
                        v
                    }
                } else {
                    1.0
                };
                surfaces::dock_view(
                    &app.theme,
                    &app.pins,
                    &app.wm,
                    app.dock_preview.as_ref(),
                    &app.icon_cache,
                    app.dock_hover_pin.as_deref(),
                    app.anims.dock_hover.value(),
                    slide,
                    app.dock_icon_size,
                    app.dock_layout,
                    app.dock_rounding,
                    &app.dock_bounce_strengths,
                    app.launcher_open,
                    app.dock_edit,
                    app.dock_drag.as_deref(),
                    app.dock_drag_target,
                    if app.dock_edit {
                        (app.tick_n as f32 * 0.22).sin()
                    } else {
                        0.0
                    },
                )
            }
        }
        n if n == layers::SPACES => {
            if suppressed || !app.spaces_open {
                surfaces::empty_layer(&app.theme)
            } else {
                proteus_shell::spaces::overview_view(
                    &app.theme,
                    &app.wm,
                    &app.workspace_names,
                    app.spaces_floor,
                    &app.spaces_thumbs,
                    app.spaces_rename_id,
                    &app.spaces_rename_buf,
                    app.spaces_drag.as_deref(),
                    app.spaces_drag_target,
                    app.spaces_drag_target_output.as_deref(),
                    app.anims.spaces.value(),
                )
            }
        }
        n if n == layers::LAUNCHER => {
            if suppressed || !app.launcher_open {
                surfaces::empty_layer(&app.theme)
            } else {
                surfaces::beacon_view(
                    &app.theme,
                    &app.chrome_snap,
                    &app.beacon_hits,
                    app.beacon_selected,
                    &app.icon_cache,
                    app.anims.beacon.value(),
                )
            }
        }
        n if n == layers::CONTROL_CENTER => {
            if suppressed {
                surfaces::empty_layer(&app.theme)
            } else if app.cc_open {
                surfaces::control_center_view(
                    &app.theme,
                    &app.chrome_snap,
                    &app.power,
                    app.brightness,
                    app.volume,
                    &app.mpris,
                    app.dnd,
                    &app.wifi_hits,
                    &app.bt_hits,
                    app.wifi_radio_on,
                    app.bt_radio_on,
                    &app.wifi_err,
                    &app.bt_err,
                    app.focus_on,
                    &app.focus_profiles,
                    &app.focus_active_id,
                    app.anims.cc.value(),
                )
            } else if app.chrome_snap.calendar_open || app.chrome_snap.notifications_open {
                surfaces::center_hub_view(
                    &app.theme,
                    &app.chrome_snap,
                    &app.notif_items,
                    app.anims.cc.value(),
                )
            } else if app.chrome_snap.weather_open {
                surfaces::weather_glance_view(
                    &app.theme,
                    &app.weather,
                    app.anims.cc.value(),
                )
            } else {
                surfaces::empty_layer(&app.theme)
            }
        }
        n if n == layers::HUD => {
            if suppressed || app.hud_kind.is_empty() || app.cc_open {
                surfaces::empty_layer(&app.theme)
            } else {
                surfaces::hud_view(&app.theme, &app.chrome_snap, app.anims.hud.value())
            }
        }
        n if n == layers::BG => surfaces::wallpaper_view(
            &app.theme,
            &app.wallpaper,
            app.wallpaper_handle.as_ref().map(|(_, h)| h),
        ),
        n if n == layers::DESKTOP_WIDGETS => {
            if suppressed {
                surfaces::empty_layer(&app.theme)
            } else if app.chrome_snap.widgets_customize
                || !app.desktop_widgets.items.is_empty()
            {
                surfaces::desktop_widgets_view(
                    &app.theme,
                    &app.desktop_widgets,
                    &app.widget_gallery,
                    app.chrome_snap.widgets_customize,
                    app.chrome_snap.widgets_snap,
                    &app.clock,
                    &app.weather,
                    &app.power,
                )
            } else {
                surfaces::empty_layer(&app.theme)
            }
        }
        n if n == layers::TOAST => {
            if suppressed || app.cc_open {
                surfaces::empty_layer(&app.theme)
            } else {
                match &app.toast {
                    Some(t) => {
                        let fade = app.anims.toast.value();
                        let hidden =
                            app.toast_hidden_id == Some(t.id) && fade <= 0.01;
                        if hidden {
                            surfaces::empty_layer(&app.theme)
                        } else {
                            surfaces::toast_view(&app.theme, t, fade)
                        }
                    }
                    None => surfaces::empty_layer(&app.theme),
                }
            }
        }
        n if n == layers::PRIVACY_ASK => match &app.privacy_ask {
            Some(cat) if !suppressed => surfaces::privacy_ask_view(&app.theme, cat),
            _ => surfaces::empty_layer(&app.theme),
        },
        _ if app.face == Face::Console && !suppressed => {
            faces::console_face_view(
                &app.theme,
                &app.chrome_snap,
                &app.console_games,
                &app.console_media_path,
                &app.console_apps,
            )
        }
        _ if app.face == Face::Host && !suppressed => {
            faces::host_face_view(&app.theme, app.host_tab, &app.host_glance)
        }
        _ => surfaces::empty_layer(&app.theme),
    };
    container(body.map(Message::Surface))
        .width(Length::Fill)
        .height(Length::Fill)
        .into()
}

pub(crate) fn style(_app: &App, theme: &iced::Theme) -> iced::theme::Style {
    iced::theme::Style {
        background_color: Color::TRANSPARENT,
        text_color: theme.palette().text,
    }
}

pub(crate) fn iced_theme(app: &App, _id: window::Id) -> iced::Theme {
    match app.theme.mode {
        ChromeMode::Light => iced::Theme::Light,
        ChromeMode::Dark => iced::Theme::Dark,
    }
}
