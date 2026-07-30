import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../shared"
import "../kit"

// Leaf UI for DesktopPane — Borders & rounding.
ColumnLayout {
  id: root
  width: parent ? parent.width : implicitWidth
  spacing: Theme.spaceMd

  SettingsGroup {
    title: "Borders & rounding"

    Text {
      Layout.fillWidth: true
      Layout.leftMargin: Theme.spaceMd
      Layout.rightMargin: Theme.spaceMd
      Layout.topMargin: Theme.spaceSm
      text: "Border size"
      color: Theme.textDim
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSizeSm
    }
    RowLayout {
      Layout.fillWidth: true
      Layout.leftMargin: Theme.spaceMd
      Layout.rightMargin: Theme.spaceMd
      Layout.bottomMargin: Theme.spaceSm
      Slider {
        Layout.fillWidth: true
        from: 0
        to: 8
        stepSize: 1
        value: Config.borderSize
        onMoved: Config.borderSize = Math.round(value)
      }
      Text {
        text: Config.borderSize
        color: Theme.text
        font.family: Theme.fontFamily
        Layout.preferredWidth: 28
      }
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 1
      color: Theme.separator
      opacity: 0.6
    }

    Text {
      Layout.fillWidth: true
      Layout.leftMargin: Theme.spaceMd
      Layout.rightMargin: Theme.spaceMd
      Layout.topMargin: Theme.spaceSm
      text: "Window rounding"
      color: Theme.textDim
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSizeSm
    }
    RowLayout {
      Layout.fillWidth: true
      Layout.leftMargin: Theme.spaceMd
      Layout.rightMargin: Theme.spaceMd
      Layout.bottomMargin: Theme.spaceMd
      Slider {
        Layout.fillWidth: true
        from: 0
        to: 24
        stepSize: 1
        value: Config.rounding
        onMoved: Config.rounding = Math.round(value)
      }
      Text {
        text: Config.rounding
        color: Theme.text
        font.family: Theme.fontFamily
        Layout.preferredWidth: 28
      }
    }
  }
}
