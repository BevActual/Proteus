import Quickshell
import QtQuick
import QtQuick.Layouts
import "../shared"
import "../kit"
import ".." // root module — SettingsNav singleton

// Leaf UI for NetworkPane — Bluetooth power / scan / pair / connect.
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

  function deviceHint(dev) {
    if (!dev)
      return ""
    const bits = [dev.mac]
    if (dev.connected)
      bits.push("Connected")
    else if (dev.paired)
      bits.push("Paired")
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
      visible: host && host.btError.length > 0
      label: "Status"
      hint: host ? host.btError : ""
      labelColor: Theme.danger
      showSeparator: true
    }

    SettingsFormRow {
      visible: host && host.btAvailable
      label: "Power"
      hint: host && host.btPowered ? "Turn adapter off" : "Turn adapter on"
      showSeparator: true
      SettingsSegmented {
        Layout.preferredWidth: 140
        enabled: host && host.btAvailable && !host.btBusy
        options: [
          {
            id: "off",
            label: "Off"
          },
          {
            id: "on",
            label: "On"
          }
        ]
        selected: host && host.btPowered ? "on" : "off"
        onActivated: id => {
          if (host)
            host.setBluetoothPower(id === "on")
        }
      }
    }

    SettingsFormRow {
      visible: host && host.btAvailable && host.btPowered
      label: "Scan"
      hint: host && host.btScanning ? "Scanning ~8s…" : "Discover nearby devices"
      showSeparator: true
      interactive: host && !host.btBusy && !host.btScanning
      onActivated: {
        if (host)
          host.scanBluetooth()
      }
      Text {
        text: host && (host.btBusy || host.btScanning) ? "…" : "Scan"
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: 12
      }
    }

    SettingsFormRow {
      visible: host && host.btAvailable && host.btPowered
          && (!host.btDevices || host.btDevices.length === 0)
      label: "Devices"
      hint: "None yet — Scan for nearby"
      showSeparator: true
    }

    Repeater {
      model: (host && host.btAvailable && host.btPowered) ? host.btDevices : []

      SettingsFormRow {
        required property var modelData
        required property int index
        label: modelData.name || modelData.mac
        hint: root.deviceHint(modelData)
        showSeparator: true
        interactive: host && !host.btBusy
        onActivated: {
          if (!host)
            return
          if (modelData.connected)
            host.disconnectBluetooth(modelData.mac)
          else
            host.pairBluetooth(modelData.mac)
        }
        Text {
          text: {
            if (host && host.btBusy)
              return "…"
            return modelData.connected ? "Disconnect" : (modelData.paired ? "Connect" : "Pair")
          }
          color: modelData.connected ? Theme.danger : Theme.accent
          font.family: Theme.fontFamily
          font.pixelSize: 12
        }
      }
    }

    Repeater {
      model: (host && host.btAvailable && host.btPowered) ? host.btDevices : []

      SettingsFormRow {
        required property var modelData
        required property int index
        visible: modelData.paired
        label: "Forget " + (modelData.name || modelData.mac)
        hint: modelData.mac
        showSeparator: true
        interactive: host && !host.btBusy
        onActivated: {
          if (host)
            host.removeBluetooth(modelData.mac)
        }
        Text {
          text: "Remove"
          color: Theme.danger
          font.family: Theme.fontFamily
          font.pixelSize: 12
        }
      }
    }

    SettingsFormRow {
      label: host && host.btAvailable ? "Open Bluetooth settings" : "Install Bluetooth tools…"
      hint: host && host.btAvailable
          ? "blueman-manager · advanced pairing"
          : "Software → Repos · blueman"
      showSeparator: false
      interactive: true
      onActivated: {
        if (host && host.btAvailable)
          Config.openBluetoothEditor()
        else
          SettingsNav.goInstallSearch("blueman")
      }
      Text {
        text: host && host.btAvailable ? "›" : "Install…"
        color: host && host.btAvailable ? Theme.textMute : Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }
    }
  }

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 480
    text: "Fact: bluetoothctl power · scan · pair/trust/connect · remove."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }
}
