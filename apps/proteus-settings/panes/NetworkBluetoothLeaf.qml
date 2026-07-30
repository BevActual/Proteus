import Quickshell
import QtQuick
import QtQuick.Layouts
import "../shared"
import "../kit"

// Leaf UI for NetworkPane — Bluetooth (status + escape hatch honesty).
ColumnLayout {
  id: root
  property Item host
  width: parent ? parent.width : implicitWidth
  spacing: Theme.spaceMd

  readonly property string adapterHint: {
    if (!host)
      return ""
    if (!host.btAvailable)
      return host.btHint.length ? host.btHint : "No adapter"
    const bits = []
    if (host.btAdapter.length)
      bits.push(host.btAdapter)
    bits.push(host.btPowered ? "Powered" : "Off")
    if (host.btHint.length && host.btHint !== "Powered" && host.btHint !== "Off")
      bits.push(host.btHint)
    return bits.join(" · ")
  }

  SettingsGroup {
    title: "Bluetooth"

    SettingsFormRow {
      label: "Adapter"
      hint: root.adapterHint
      showSeparator: true
      Text {
        text: {
          if (!host || !host.btAvailable)
            return ""
          return host.btPowered ? "On" : "Off"
        }
        color: host && host.btAvailable && host.btPowered ? Theme.accent : Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: 12
      }
    }

    SettingsFormRow {
      label: host && host.btAvailable ? "Open Bluetooth settings" : "Bluetooth unavailable"
      hint: host && host.btAvailable
          ? "blueman-manager · pairing stays in system tools"
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

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 480
    text: "Fact: bluetoothctl show · pairing / device list → blueman or bluetoothctl."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }
}
