import Quickshell
import QtQuick
import QtQuick.Layouts
import "../shared"
import "../kit"

// Leaf UI for NetworkPane — VPN + NetworkManager escape.
ColumnLayout {
  id: root
  property Item host
  width: parent ? parent.width : implicitWidth
  spacing: Theme.spaceMd

  SettingsGroup {
    title: "VPN"

    SettingsFormRow {
      visible: host && !host.vpnConnections.length
      label: "No profiles"
      hint: host ? host.vpnStatus : ""
      showSeparator: true
    }

    Repeater {
      model: host ? host.vpnConnections : []

      SettingsFormRow {
        required property var modelData
        required property int index
        label: modelData.name
        hint: modelData.type || "vpn"
        showSeparator: true
        Text {
          text: modelData.active ? "Connected" : ""
          color: Theme.accent
          font.family: Theme.fontFamily
          font.pixelSize: 12
        }
      }
    }

    SettingsFormRow {
      label: "Open VPN / NetworkManager"
      hint: "Add or edit VPN profiles · password Wi‑Fi also lives here"
      showSeparator: false
      interactive: true
      onActivated: Config.openNetworkEditor()
      Text {
        text: "›"
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }
    }
  }

  SettingsGroup {
    SettingsFormRow {
      label: "Open network settings"
      hint: "NetworkManager editor, or nmtui in a terminal"
      showSeparator: false
      interactive: true
      onActivated: Config.openNetworkEditor()
      Text {
        text: "›"
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }
    }
  }

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 480
    text: "Fact: hostnamectl · nmcli wifi · bluetoothctl · tailscale · wl-copy. Password Wi‑Fi / pairing / Headscale admin → system tools."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }
}
