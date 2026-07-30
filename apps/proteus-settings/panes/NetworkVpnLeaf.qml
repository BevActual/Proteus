import Quickshell
import QtQuick
import QtQuick.Layouts
import "../shared"
import "../kit"

// Leaf UI for NetworkPane — VPN + NetworkManager escape (denser honesty).
ColumnLayout {
  id: root
  property Item host
  width: parent ? parent.width : implicitWidth
  spacing: Theme.spaceMd

  function vpnHint(conn) {
    if (!conn)
      return ""
    const bits = []
    if (conn.type)
      bits.push(conn.type)
    if (conn.active)
      bits.push("Connected")
    else
      bits.push("Idle")
    return bits.join(" · ")
  }

  SettingsGroup {
    title: "VPN"

    SettingsFormRow {
      visible: host && !host.vpnConnections.length
      label: "Profiles"
      hint: host && host.vpnStatus.length
          ? host.vpnStatus
          : "No VPN profiles yet — add one in NetworkManager"
      showSeparator: true
    }

    Repeater {
      model: host ? host.vpnConnections : []

      SettingsFormRow {
        required property var modelData
        required property int index
        label: modelData.name
        hint: root.vpnHint(modelData)
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
      label: "Open NetworkManager"
      hint: "Add or edit VPN · password Wi‑Fi · nmtui in a terminal"
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
    text: "Fact: nmcli connection show · WireGuard / OpenVPN wizards stay in system tools."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }
}
