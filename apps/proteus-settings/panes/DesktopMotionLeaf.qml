import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../shared"
import "../kit"

// Leaf UI for DesktopPane — Motion.
ColumnLayout {
  id: root
  width: parent ? parent.width : implicitWidth
  spacing: Theme.spaceMd

  SettingsGroup {
    title: "Motion"

    SettingsFormRow {
      label: "Window animations"
      hint: Config.animationsEnabled ? "On — Hypr window animations" : "Off — instant moves"
      showSeparator: false
      ThemeSwitch {
        checked: Config.animationsEnabled
        onToggled: Config.animationsEnabled = checked
      }
    }
  }
}
