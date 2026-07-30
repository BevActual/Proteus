import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../shared"
import "../kit"

// Leaf UI for DesktopPane — Gaps (SettingsFormRow honesty).
ColumnLayout {
  id: root
  width: parent ? parent.width : implicitWidth
  spacing: Theme.spaceMd

  SettingsGroup {
    title: "Gaps"

    SettingsFormRow {
      label: "Window gaps (inside)"
      hint: Config.gapsIn + " px · between tiled windows"
      showSeparator: true
      Slider {
        Layout.preferredWidth: 160
        from: 0
        to: 32
        stepSize: 1
        value: Config.gapsIn
        onMoved: Config.gapsIn = Math.round(value)
      }
    }

    SettingsFormRow {
      label: "Outer gaps"
      hint: Config.gapsOut + " px · to screen edges"
      showSeparator: false
      Slider {
        Layout.preferredWidth: 160
        from: 0
        to: 48
        stepSize: 1
        value: Config.gapsOut
        onMoved: Config.gapsOut = Math.round(value)
      }
    }
  }
}
