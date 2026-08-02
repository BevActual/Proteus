import Quickshell
import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import "../shared"
import "../kit"

// Leaf UI for NetworkPane — VPN up/down + WireGuard / OpenVPN import.
ColumnLayout {
  id: root
  property Item host
  width: parent ? parent.width : implicitWidth
  spacing: Theme.spaceMd

  // Ephemeral OpenVPN auth drafts — never written to settings.json
  property string ovpnUserDraft: ""
  property string ovpnPassDraft: ""

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

  function localPathFromUrl(url) {
    let s = String(url)
    if (s.startsWith("file://"))
      s = s.slice(7)
    try {
      return decodeURIComponent(s)
    } catch (e) {
      return s
    }
  }

  FileDialog {
    id: wgDialog
    title: "Import WireGuard config"
    nameFilters: ["WireGuard (*.conf)", "All files (*)"]
    onAccepted: {
      if (!host)
        return
      host.importWireGuard(root.localPathFromUrl(selectedFile))
    }
  }

  FileDialog {
    id: ovpnDialog
    title: "Import OpenVPN config"
    nameFilters: ["OpenVPN (*.ovpn *.conf)", "All files (*)"]
    onAccepted: {
      if (!host)
        return
      host.importOpenVpn(
            root.localPathFromUrl(selectedFile),
            root.ovpnUserDraft,
            root.ovpnPassDraft)
    }
  }

  SettingsGroup {
    title: "VPN"

    SettingsFormRow {
      visible: host && host.vpnError.length > 0
      label: "Status"
      hint: host ? host.vpnError : ""
      labelColor: Theme.danger
      showSeparator: true
    }

    SettingsFormRow {
      visible: host && host.vpnImportHint.length > 0
      label: "Import"
      hint: host ? host.vpnImportHint : ""
      showSeparator: true
    }

    SettingsFormRow {
      visible: host && !host.vpnConnections.length
      label: "Profiles"
      hint: host && host.vpnStatus.length
          ? host.vpnStatus
          : "No VPN profiles yet — import WireGuard / OpenVPN or use NetworkManager"
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
        interactive: host && !host.vpnBusy
        onActivated: {
          if (host)
            host.vpnToggle(modelData.name, !!modelData.active)
        }
        Text {
          text: {
            if (host && host.vpnBusy)
              return "…"
            return modelData.active ? "Disconnect" : "Connect"
          }
          color: modelData.active ? Theme.danger : Theme.accent
          font.family: Theme.fontFamily
          font.pixelSize: 12
        }
      }
    }

    SettingsFormRow {
      label: "Import WireGuard…"
      hint: "nmcli connection import type wireguard"
      showSeparator: true
      interactive: host && !host.vpnBusy
      onActivated: wgDialog.open()
      Text {
        text: host && host.vpnBusy ? "…" : "Choose…"
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: 12
      }
    }

    SettingsFormRow {
      label: "OpenVPN username"
      hint: root.ovpnUserDraft.length
          ? root.ovpnUserDraft
          : "Optional — applied after .ovpn import (never in settings.json)"
      showSeparator: true
    }

    Item {
      Layout.fillWidth: true
      Layout.preferredHeight: 44
      Rectangle {
        anchors.fill: parent
        anchors.leftMargin: Theme.spaceMd
        anchors.rightMargin: Theme.spaceMd
        anchors.topMargin: Theme.spaceXs
        anchors.bottomMargin: Theme.spaceSm
        radius: Theme.radiusMd
        color: Theme.bgHover
        border.width: 1
        border.color: ovpnUser.activeFocus ? Theme.accent : Theme.border
        TextInput {
          id: ovpnUser
          anchors.fill: parent
          anchors.leftMargin: 10
          anchors.rightMargin: 10
          color: Theme.text
          font.family: Theme.fontFamily
          font.pixelSize: 13
          text: root.ovpnUserDraft
          onTextChanged: root.ovpnUserDraft = text
        }
      }
    }

    SettingsFormRow {
      label: "OpenVPN password"
      hint: "Optional — session only"
      showSeparator: true
    }

    Item {
      Layout.fillWidth: true
      Layout.preferredHeight: 44
      Rectangle {
        anchors.fill: parent
        anchors.leftMargin: Theme.spaceMd
        anchors.rightMargin: Theme.spaceMd
        anchors.topMargin: Theme.spaceXs
        anchors.bottomMargin: Theme.spaceSm
        radius: Theme.radiusMd
        color: Theme.bgHover
        border.width: 1
        border.color: ovpnPass.activeFocus ? Theme.accent : Theme.border
        TextInput {
          id: ovpnPass
          anchors.fill: parent
          anchors.leftMargin: 10
          anchors.rightMargin: 10
          color: Theme.text
          font.family: Theme.fontFamily
          font.pixelSize: 13
          echoMode: TextInput.Password
          text: root.ovpnPassDraft
          onTextChanged: root.ovpnPassDraft = text
        }
      }
    }

    SettingsFormRow {
      label: "Import OpenVPN…"
      hint: "nmcli connection import type openvpn · needs networkmanager-openvpn"
      showSeparator: true
      interactive: host && !host.vpnBusy
      onActivated: ovpnDialog.open()
      Text {
        text: host && host.vpnBusy ? "…" : "Choose…"
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: 12
      }
    }

    SettingsFormRow {
      label: "Open NetworkManager"
      hint: "Certs · advanced edit · PKCS#11"
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
    text: "Fact: nmcli connection up/down · WireGuard + OpenVPN import (.ovpn). Optional OpenVPN user/pass are session-only. Cert wizard Out · Headscale admin → Network → Headscale."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }
}
