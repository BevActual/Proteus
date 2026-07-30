import Quickshell
import QtQuick
import QtQuick.Layouts
import "../shared"
import "../kit"

// Leaf UI for NetworkPane — Bluetooth.
ColumnLayout {
  id: root
  property Item host
  width: parent ? parent.width : implicitWidth
  spacing: Theme.spaceMd

  SettingsGroup {
    title: "Bluetooth"

    SettingsFormRow {
      label: host && host.btAdapter.length ? host.btAdapter : "Adapter"
      hint: host ? host.btHint : ""
      showSeparator: true
      Text {
        visible: host && host.btAvailable
        text: host && host.btPowered ? "On" : "Off"
        color: host && host.btPowered ? Theme.accent : Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: 12
      }
    }

    SettingsFormRow {
      label: "Open Bluetooth settings"
      hint: host && host.btAvailable
          ? "blueman-manager, or bluetoothctl in a terminal"
          : "Install BlueZ / blueman when this machine has Bluetooth"
      showSeparator: false
      interactive: host && host.btAvailable
      onActivated: Config.openBluetoothEditor()
      Text {
        text: host && host.btAvailable ? "›" : ""
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }
    }
  }
}
