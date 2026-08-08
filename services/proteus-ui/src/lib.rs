//! Shared iced UI kit for the owned Proteus shell and sibling apps.

pub mod theme;
pub mod widgets;

pub use theme::{contrasting_text, darken, fade, lighten, ChromeMode, Theme};
pub use widgets::{
    circle_button, chrome_tile, dock_plate, elevated_chip, form_row, glass_plate, hub_row,
    large_title, menu_bar_plate, segmented_control, settings_group, settings_row, sidebar_item,
    squircle_plate, tab_bar, text_input_style, theme_slider, theme_switch, toggle_button,
    CircleStyle, SQUIRCLE_RATIO,
};
