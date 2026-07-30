import Quickshell
import QtQuick
import QtQuick.Layouts
import "../shared"
import "../kit"

// Leaf UI for NetworkPane — Devices.
ColumnLayout {
  id: root
  property Item host
  width: parent ? parent.width : implicitWidth
  spacing: Theme.spaceMd

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 480
    visible: host && !host.devices.length
    text: host ? host.status : ""
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 12
    wrapMode: Text.WordWrap
  }

  SettingsGroup {
    visible: host && host.devices.length > 0
    title: "Devices"

    Repeater {
      model: host ? host.devices : []

      SettingsFormRow {
        required property var modelData
        required property int index
        label: modelData.device
        hint: host ? host.stateHint(modelData) : ""
        showSeparator: host && index < host.devices.length - 1
        Text {
          text: host && host.isUp(modelData) ? "Connected" : ""
          color: Theme.accent
          font.family: Theme.fontFamily
          font.pixelSize: 12
        }
      }
    }
  }
}
