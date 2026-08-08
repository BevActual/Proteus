//! Surface message handlers (bar/dock/CC/lock/…).

mod dock;
mod lock;
mod overlays;
mod spaces;
mod system;
mod widgets;

use iced::Task;
use proteus_shell::surfaces::Message as SurfaceMsg;

use super::*;

pub(crate) use dock::enter_dock_edit;
pub(crate) fn handle_surface(app: &mut App, m: SurfaceMsg) -> Task<Message> {
    match m {
        m @ (
            SurfaceMsg::ToggleLauncher
            | SurfaceMsg::ToggleControlCenter
            | SurfaceMsg::ToggleCalendar
            | SurfaceMsg::ToggleWeather
            | SurfaceMsg::ToggleNotifications
            | SurfaceMsg::CenterTab(_)
            | SurfaceMsg::CloseCenterHub
            | SurfaceMsg::DesktopPress
            | SurfaceMsg::DesktopRelease
            | SurfaceMsg::CustomizeDesktop
            | SurfaceMsg::BeaconInput(_)
            | SurfaceMsg::BeaconLaunch(_)
            | SurfaceMsg::BeaconNav(_)
            | SurfaceMsg::BeaconSubmit
            | SurfaceMsg::BeaconEscape
            | SurfaceMsg::HudDismiss
            | SurfaceMsg::ToastDismiss(_)
            | SurfaceMsg::PrivacyAllow
            | SurfaceMsg::PrivacyDeny
            | SurfaceMsg::OpenPrivacy
            | SurfaceMsg::OpenSettingsPage(_)
            | SurfaceMsg::OpenSettings
        ) => overlays::handle(app, m),

        m @ (
            SurfaceMsg::ToggleSpaces
            | SurfaceMsg::SpacesEscape
            | SurfaceMsg::SpacesCycle(_)
            | SurfaceMsg::ScratchToggle
            | SurfaceMsg::SpacesSelect(_, _)
            | SurfaceMsg::SpacesAdd
            | SurfaceMsg::SpacesRenameStart(_)
            | SurfaceMsg::SpacesRenameInput(_)
            | SurfaceMsg::SpacesRenameCommit
            | SurfaceMsg::SpacesDragStart(_)
            | SurfaceMsg::SpacesDragHover(_, _)
            | SurfaceMsg::SpacesDrop(_, _)
            | SurfaceMsg::SpacesThumbRelease(_)
        ) => spaces::handle(app, m),

        m @ (
            SurfaceMsg::Workspace(_)
            | SurfaceMsg::DockLaunch(_)
            | SurfaceMsg::DockPress(_)
            | SurfaceMsg::DockRelease(_)
            | SurfaceMsg::DockEditDone
            | SurfaceMsg::DockUnpin(_)
            | SurfaceMsg::DockDragHover(_)
            | SurfaceMsg::DockDragOffHover(_)
            | SurfaceMsg::DockDragOffDrop
            | SurfaceMsg::DockHover(_)
            | SurfaceMsg::DockEdgeEnter
            | SurfaceMsg::BarEdgeEnter
            | SurfaceMsg::BarLeave
            | SurfaceMsg::DockLeave
            | SurfaceMsg::DockPreviewEnter
            | SurfaceMsg::DockPreviewFocus(_)
            | SurfaceMsg::DockPreviewClose(_)
        ) => dock::handle(app, m),

        m @ (
            SurfaceMsg::Lock
            | SurfaceMsg::Unlock
            | SurfaceMsg::PinEntry(_)
            | SurfaceMsg::LockReveal
            | SurfaceMsg::LockWakeChar(_)
            | SurfaceMsg::LockPinDigit(_)
            | SurfaceMsg::LockPinBackspace
            | SurfaceMsg::LockPinClear
            | SurfaceMsg::LockUsePassword
            | SurfaceMsg::LockUsePin
            | SurfaceMsg::LockCustomizeAdd(_)
            | SurfaceMsg::LockCustomizeRemove(_)
            | SurfaceMsg::LockCustomizeMove(_, _)
            | SurfaceMsg::LockCustomizeDone
        ) => lock::handle(app, m),

        m @ (
            SurfaceMsg::WidgetAdd(_)
            | SurfaceMsg::WidgetRemove(_)
            | SurfaceMsg::WidgetSelect(_)
            | SurfaceMsg::WidgetDragStart(_)
            | SurfaceMsg::WidgetDrag(_, _)
            | SurfaceMsg::WidgetDragEnd
            | SurfaceMsg::WidgetNudge(_, _)
            | SurfaceMsg::WidgetSnapToggle
            | SurfaceMsg::WidgetCustomizeDone
            | SurfaceMsg::WidgetActivate(_)
        ) => widgets::handle(app, m),

        m @ (
            SurfaceMsg::CcRefresh
            | SurfaceMsg::WifiRadioToggle
            | SurfaceMsg::BtRadioToggle
            | SurfaceMsg::AppearanceMode(_)
            | SurfaceMsg::Screenshot(_)
            | SurfaceMsg::FaceSelect(_)
            | SurfaceMsg::Refresh
            | SurfaceMsg::BrightnessSet(_)
            | SurfaceMsg::BrightnessStep(_)
            | SurfaceMsg::PowerProfile(_)
            | SurfaceMsg::ToggleFloating
            | SurfaceMsg::VolumeMute
            | SurfaceMsg::VolumeStep(_)
            | SurfaceMsg::VolumeSet(_)
            | SurfaceMsg::MediaPlayPause(_)
            | SurfaceMsg::MediaNext(_)
            | SurfaceMsg::MediaPrev(_)
            | SurfaceMsg::NotifClearAll
            | SurfaceMsg::NotifDismiss(_)
            | SurfaceMsg::LaunchGame(_)
            | SurfaceMsg::HostTab(_)
            | SurfaceMsg::ToggleDnd
            | SurfaceMsg::WifiConnect(_)
            | SurfaceMsg::BtConnect(_)
            | SurfaceMsg::OpenMediaPath
            | SurfaceMsg::LaunchConsoleApp(_)
            | SurfaceMsg::ToggleFocus
            | SurfaceMsg::FocusProfile(_)
            | SurfaceMsg::OpenConsoleSettingsPage(_)
            | SurfaceMsg::OpenWorkloads
        ) => system::handle(app, m),
    }
}
