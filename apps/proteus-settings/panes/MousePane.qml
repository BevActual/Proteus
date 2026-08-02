import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../shared"
import "../kit"

// Peripherals → Mouse leaf (+ thin per-device hypr device {} overrides).
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: Theme.spaceMd

  property string newDeviceName: ""
  property real newDeviceSens: 0
  property bool newDeviceAccelFlat: false
  property string confirmDeleteDevice: ""

  readonly property string sensitivityLabel: {
    const v = Config.mouseSensitivity
    return (v > 0 ? "+" : "") + v.toFixed(1)
  }

  readonly property var deviceOverrides: {
    const _ = Config.inputDeviceOverrides
    return Config.inputDeviceOverridesList()
  }

  SettingsGroup {
    title: "Pointer"

    SettingsFormRow {
      label: "Sensitivity"
      hint: root.sensitivityLabel
      showSeparator: true
      ThemeSlider {
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
      ThemeSwitch {
        checked: Config.mouseAccelFlat
        onToggled: Config.mouseAccelFlat = checked
      }
    }
  }

  SettingsGroup {
    title: "Per-device"

    SettingsFormRow {
      label: "Overrides"
      hint: root.deviceOverrides.length
          ? (root.deviceOverrides.length + " · names from hyprctl devices")
          : "Optional hypr device {} · empty = global Pointer only"
      showSeparator: true
      Text {
        text: String(root.deviceOverrides.length)
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSm
      }
    }

    Repeater {
      model: root.deviceOverrides

      ColumnLayout {
        required property var modelData
        required property int index
        Layout.fillWidth: true
        spacing: 0

        SettingsFormRow {
          label: modelData.name
          hint: {
            const s = Number(modelData.sensitivity) || 0
            const label = (s > 0 ? "+" : "") + s.toFixed(1)
            return "Sensitivity " + label + (modelData.accelFlat ? " · flat" : " · adaptive")
          }
          showSeparator: true
          ThemeSlider {
            Layout.preferredWidth: 140
            from: -1.0
            to: 1.0
            stepSize: 0.1
            value: Number(modelData.sensitivity) || 0
            onMoved: Config.upsertInputDeviceOverride(
                       modelData.name, Math.round(value * 10) / 10, modelData.accelFlat)
          }
        }

        SettingsFormRow {
          label: "Flat accel"
          hint: root.confirmDeleteDevice === modelData.name
              ? ("Confirm remove override for " + modelData.name)
              : (modelData.accelFlat ? "Flat on this device" : "Adaptive on this device")
          showSeparator: true
          ThemeSwitch {
            checked: !!modelData.accelFlat
            onToggled: Config.upsertInputDeviceOverride(
                         modelData.name, modelData.sensitivity, checked)
          }
          Text {
            visible: root.confirmDeleteDevice !== modelData.name
            text: "Remove"
            color: Theme.danger
            font.family: Theme.fontFamily
            font.pixelSize: 13
            MouseArea {
              anchors.fill: parent
              anchors.margins: -8
              cursorShape: Qt.PointingHandCursor
              onClicked: root.confirmDeleteDevice = modelData.name
            }
          }
          RowLayout {
            visible: root.confirmDeleteDevice === modelData.name
            spacing: Theme.spaceMd
            Text {
              text: "Cancel"
              color: Theme.textMute
              font.family: Theme.fontFamily
              font.pixelSize: 13
              MouseArea {
                anchors.fill: parent
                anchors.margins: -8
                cursorShape: Qt.PointingHandCursor
                onClicked: root.confirmDeleteDevice = ""
              }
            }
            Text {
              text: "Remove"
              color: Theme.danger
              font.family: Theme.fontFamily
              font.pixelSize: 13
              MouseArea {
                anchors.fill: parent
                anchors.margins: -8
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  Config.removeInputDeviceOverride(modelData.name)
                  root.confirmDeleteDevice = ""
                }
              }
            }
          }
        }
      }
    }

    SettingsFormRow {
      label: "Device name"
      hint: root.deviceOverrides.length >= 16
          ? "Limit 16 overrides"
          : "Paste name from hyprctl devices (mice / touchpads)"
      showSeparator: true
      TextField {
        Layout.preferredWidth: 180
        placeholderText: "epic-mouse-v1"
        text: root.newDeviceName
        color: Theme.text
        placeholderTextColor: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        background: Item {}
        enabled: root.deviceOverrides.length < 16
        onTextChanged: root.newDeviceName = text
      }
    }

    SettingsFormRow {
      label: "Add override"
      hint: "Writes device { name · sensitivity · accel_profile } to proteus-general.conf"
      showSeparator: false
      ThemeSlider {
        Layout.preferredWidth: 120
        from: -1.0
        to: 1.0
        stepSize: 0.1
        value: root.newDeviceSens
        onMoved: root.newDeviceSens = Math.round(value * 10) / 10
      }
      ThemeSwitch {
        checked: root.newDeviceAccelFlat
        onToggled: root.newDeviceAccelFlat = checked
      }
      Text {
        text: "Add"
        color: root.deviceOverrides.length < 16 ? Theme.accent : Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: 13
        MouseArea {
          anchors.fill: parent
          anchors.margins: -8
          enabled: root.deviceOverrides.length < 16
          cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: {
            if (Config.upsertInputDeviceOverride(
                  root.newDeviceName, root.newDeviceSens, root.newDeviceAccelFlat))
              root.newDeviceName = ""
          }
        }
      }
    }
  }

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 480
    text: "Fact: global Pointer → input:sensitivity / accel_profile · per-device → hypr device {} (sensitivity + accel only; pressure · active-area · gesture maps Out)."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }
}
