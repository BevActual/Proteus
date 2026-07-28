import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../shared"

// Peripherals → Mouse leaf.
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: Theme.spaceMd

  readonly property string sensitivityLabel: {
    const v = Config.mouseSensitivity
    return (v > 0 ? "+" : "") + v.toFixed(1)
  }

  SettingsGroup {
    title: "Pointer"

    SettingsFormRow {
      label: "Sensitivity"
      hint: root.sensitivityLabel
      showSeparator: true
      Slider {
        Layout.preferredWidth: 150
        from: -1.0
        to: 1.0
        stepSize: 0.1
        value: Config.mouseSensitivity
        onMoved: Config.mouseSensitivity = Math.round(value * 10) / 10
      }
    }

    SettingsFormRow {
      label: "Flat acceleration"
      hint: Config.mouseAccelFlat ? "Constant pointer speed" : "Off — adaptive (default)"
      showSeparator: false
      Switch {
        checked: Config.mouseAccelFlat
        onToggled: Config.mouseAccelFlat = checked
      }
    }
  }

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 480
    text: "Fact: settings.json + hyprctl input:sensitivity / input:accel_profile."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }
}
