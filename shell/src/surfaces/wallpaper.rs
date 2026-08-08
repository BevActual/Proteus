//! Desktop wallpaper / hold-to-Customize surface.


#![allow(unused_imports)]

use iced::widget::{button, column, container, mouse_area, row, scrollable, text, text_input, Space};
use iced::{Alignment, Background, Border, Color, Element, Length, Padding};

use proteus_ui::theme::Theme;
use proteus_ui::widgets::{
    chrome_tile, dock_plate, elevated_chip, glass_plate, menu_bar_plate, segmented_control,
};

use crate::ctl::ChromeState;
use crate::platform::{
    MprisPlayer, Notification, PowerStatus, PrivacyDots, WallpaperState, WeatherGlance,
};
use crate::wm_ipc::WmState;

use super::{
    bar_clock_now, is_beacon_pin, light_font, pin_label, pin_matches, semibold, BarClock,
    DockPreview, DockPreviewWin, Message,
};

pub(crate) fn parse_wallpaper_color(hex: &str, fallback: Color) -> Color {
    let s = hex.trim().trim_start_matches('#');
    if s.len() != 6 {
        return fallback;
    }
    let Ok(v) = u32::from_str_radix(s, 16) else {
        return fallback;
    };
    Color::from_rgb8(
        ((v >> 16) & 0xff) as u8,
        ((v >> 8) & 0xff) as u8,
        (v & 0xff) as u8,
    )
}

/// Owned wallpaper — image from settings.json (QS BgConfig parity) with
/// solid-color fallback. Hold empty wallpaper → Customize (via press/release).
pub fn wallpaper_view<'a>(
    theme: &'a Theme,
    wp: &'a crate::platform::WallpaperState,
    handle: Option<&'a iced::widget::image::Handle>,
) -> Element<'a, Message> {
    let under = if let Some(h) = handle {
        let fit = match wp.mode.as_str() {
            "fit" => iced::ContentFit::Contain,
            "stretch" => iced::ContentFit::Fill,
            "center" => iced::ContentFit::None,
            _ => iced::ContentFit::Cover,
        };
        let img = iced::widget::image(h.clone())
            .width(Length::Fill)
            .height(Length::Fill)
            .content_fit(fit);
        let color = parse_wallpaper_color(&wp.color, theme.bg);
        container(img)
            .width(Length::Fill)
            .height(Length::Fill)
            .clip(true)
            .style(move |_t| container::Style {
                background: Some(Background::Color(color)),
                ..Default::default()
            })
    } else {
        let bg = parse_wallpaper_color(&wp.color, theme.bg);
        container(Space::new().width(Length::Fill).height(Length::Fill))
            .width(Length::Fill)
            .height(Length::Fill)
            .style(move |_t| container::Style {
                background: Some(Background::Color(bg)),
                ..Default::default()
            })
    };
    iced::widget::mouse_area(under)
        .on_press(Message::DesktopPress)
        .on_release(Message::DesktopRelease)
        .into()
}
