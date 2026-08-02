import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."
import "../shared"
import "../kit"

// Top-level Notifications — prefs only; live list lives in Control Center.
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: Theme.spaceMd

  property bool active: false

  SettingsGroup {
    title: "Notifications"

    Text {
      Layout.fillWidth: true
      Layout.leftMargin: Theme.spaceMd
      Layout.rightMargin: Theme.spaceMd
      Layout.topMargin: Theme.spaceSm
      Layout.bottomMargin: Theme.spaceSm
      text: "Notification history and quick actions live in Control Center. Use Focus for filtered quiet while keeping selected toasts."
      color: Theme.textMute
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSizeSm
      wrapMode: Text.WordWrap
    }

    SettingsFormRow {
      label: "Do Not Disturb"
      hint: Notifications.dnd
          ? "All toasts suppressed"
          : "Toasts allowed (Focus may still filter)"
      showSeparator: true
      ThemeSwitch {
        checked: Config.notificationsDnd
        onToggled: Notifications.setDnd(checked)
      }
    }

    SettingsFormRow {
      label: "Focus"
      hint: "Profiles, allowlist, schedule"
      interactive: true
      showSeparator: false
      onActivated: SettingsNav.go("desktop-focus")
      Text {
        text: "›"
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: 16
      }
    }
  }
}
