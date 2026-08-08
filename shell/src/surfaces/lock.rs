//! Lock overlay surface (maps lock_ui into shell messages).


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
use super::wallpaper::parse_wallpaper_color;

/// Opaque lock floor — wallpaper (or solid) painted *into* the Overlay surface
/// so windows under the lock cannot peek through a translucent scrim.
fn lock_backdrop<'a>(
    theme: &'a Theme,
    wp: &'a crate::platform::WallpaperState,
    handle: Option<&'a iced::widget::image::Handle>,
) -> Element<'a, Message> {
    let color = parse_wallpaper_color(&wp.color, theme.bg);
    // Force opaque — layer clear color is transparent; floor must seal the desktop.
    let floor = Color {
        r: color.r,
        g: color.g,
        b: color.b,
        a: 1.0,
    };
    if let Some(h) = handle {
        let fit = match wp.mode.as_str() {
            "fit" => iced::ContentFit::Contain,
            "stretch" => iced::ContentFit::Fill,
            "center" => iced::ContentFit::None,
            _ => iced::ContentFit::Cover,
        };
        container(
            iced::widget::image(h.clone())
                .width(Length::Fill)
                .height(Length::Fill)
                .content_fit(fit),
        )
        .width(Length::Fill)
        .height(Length::Fill)
        .clip(true)
        .style(move |_t| container::Style {
            background: Some(Background::Color(floor)),
            ..Default::default()
        })
        .into()
    } else {
        container(Space::new().width(Length::Fill).height(Length::Fill))
            .width(Length::Fill)
            .height(Length::Fill)
            .style(move |_t| container::Style {
                background: Some(Background::Color(floor)),
                ..Default::default()
            })
            .into()
    }
}

/// Full-bleed lock overlay — opaque wallpaper floor + shared lock UI.
/// Maps [`crate::lock_ui`] into shell messages.
pub fn lock_view<'a>(
    theme: &'a Theme,
    st: &'a crate::lock_ui::LockUiState,
    wp: &'a crate::platform::WallpaperState,
    handle: Option<&'a iced::widget::image::Handle>,
) -> Element<'a, Message> {
    use crate::lock_ui::LockMsg;
    let ui = crate::lock_ui::lock_screen_view(theme, st).map(|m| match m {
        LockMsg::Reveal => Message::LockReveal,
        LockMsg::PinDigit(c) => Message::LockPinDigit(c),
        LockMsg::PinBackspace => Message::LockPinBackspace,
        LockMsg::PinClear => Message::LockPinClear,
        LockMsg::UsePassword => Message::LockUsePassword,
        LockMsg::UsePin => Message::LockUsePin,
        LockMsg::PinEntry(s) => Message::PinEntry(s),
        LockMsg::Unlock => Message::Unlock,
        LockMsg::CustomizeAdd(k) => Message::LockCustomizeAdd(k),
        LockMsg::CustomizeRemove(id) => Message::LockCustomizeRemove(id),
        LockMsg::CustomizeMove(id, d) => Message::LockCustomizeMove(id, d),
        LockMsg::CustomizeDone => Message::LockCustomizeDone,
    });
    iced::widget::stack![lock_backdrop(theme, wp, handle), ui]
        .width(Length::Fill)
        .height(Length::Fill)
        .into()
}
