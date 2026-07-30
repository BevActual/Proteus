import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../shared"
import "../kit"

// Leaf UI for DesktopPane — Borders & rounding (SettingsFormRow honesty).
ColumnLayout {
  id: root
  width: parent ? parent.width : implicitWidth
  spacing: Theme.spaceMd

  SettingsGroup {
    title: "Borders & rounding"

    SettingsFormRow {
      label: "Border size"
      hint: Config.borderSize + " px"
      showSeparator: true
      Slider {
        Layout.preferredWidth: 160
        from: 0
        to: 8
        stepSize: 1
        value: Config.borderSize
        onMoved: Config.borderSize = Math.round(value)
      }
    }

    SettingsFormRow {
      label: "Window rounding"
      hint: Config.rounding + " px"
      showSeparator: false
      Slider {
        Layout.preferredWidth: 160
        from: 0
        to: 24
        stepSize: 1
        value: Config.rounding
        onMoved: Config.rounding = Math.round(value)
      }
    }
  }
}
