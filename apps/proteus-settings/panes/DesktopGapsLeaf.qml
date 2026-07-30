import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../shared"
import "../kit"

// Leaf UI for DesktopPane — Gaps.
ColumnLayout {
  id: root
  width: parent ? parent.width : implicitWidth
  spacing: Theme.spaceMd

  SettingsGroup {
    title: "Gaps"

    Text {
      Layout.fillWidth: true
      Layout.leftMargin: Theme.spaceMd
      Layout.rightMargin: Theme.spaceMd
      Layout.topMargin: Theme.spaceSm
      text: "Window gaps (inside)"
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
        to: 32
        stepSize: 1
        value: Config.gapsIn
        onMoved: Config.gapsIn = Math.round(value)
      }
      Text {
        text: Config.gapsIn
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
      text: "Outer gaps"
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
        to: 48
        stepSize: 1
        value: Config.gapsOut
        onMoved: Config.gapsOut = Math.round(value)
      }
      Text {
        text: Config.gapsOut
        color: Theme.text
        font.family: Theme.fontFamily
        Layout.preferredWidth: 28
      }
    }
  }
}
