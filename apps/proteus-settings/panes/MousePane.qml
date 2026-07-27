import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../shared"

ColumnLayout {
  id: root
  Layout.fillWidth: true
  Layout.maximumWidth: 420
  spacing: 14

  Text {
    Layout.fillWidth: true
    text: "Pointer feel for Hyprland. Writes settings.json + hyprctl."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 12
    wrapMode: Text.WordWrap
  }

  Text {
    text: "Sensitivity"
    color: Theme.textDim
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSizeSm
  }

  RowLayout {
    Layout.fillWidth: true
    Slider {
      Layout.fillWidth: true
      from: -1.0
      to: 1.0
      stepSize: 0.1
      value: Config.mouseSensitivity
      onMoved: Config.mouseSensitivity = Math.round(value * 10) / 10
    }
    Text {
      text: {
        const v = Config.mouseSensitivity
        return (v > 0 ? "+" : "") + v.toFixed(1)
      }
      color: Theme.text
      font.family: Theme.fontFamily
      Layout.preferredWidth: 40
    }
  }

  Rectangle {
    Layout.fillWidth: true
    Layout.preferredHeight: 48
    radius: Theme.radiusMd
    color: Theme.bgPanel
    border.width: 1
    border.color: Theme.border
    RowLayout {
      anchors.fill: parent
      anchors.margins: Theme.spaceMd
      ColumnLayout {
        Layout.fillWidth: true
        spacing: 2
        Text {
          text: "Flat acceleration"
          color: Theme.text
          font.family: Theme.fontFamily
        }
        Text {
          text: "Off = adaptive (default)"
          color: Theme.textMute
          font.family: Theme.fontFamily
          font.pixelSize: 11
        }
      }
      Switch {
        checked: Config.mouseAccelFlat
        onToggled: Config.mouseAccelFlat = checked
      }
    }
  }

  Text {
    Layout.fillWidth: true
    text: "Applied via hyprctl input:sensitivity / input:accel_profile."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }
}
