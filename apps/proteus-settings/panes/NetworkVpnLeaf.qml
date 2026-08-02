import Quickshell
import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import "../shared"
import "../kit"

// Leaf UI for NetworkPane — VPN up/down + WireGuard / OpenVPN import.
// Optional OpenVPN user/pass + CA/cert/key(+tls-auth) path attach (session-only).
ColumnLayout {
  id: root
  property Item host
  width: parent ? parent.width : implicitWidth
  spacing: Theme.spaceMd

  // Ephemeral OpenVPN drafts — never written to settings.json
  property string ovpnUserDraft: ""
  property string ovpnPassDraft: ""
  property string ovpnCaDraft: ""
  property string ovpnCertDraft: ""
  property string ovpnKeyDraft: ""
  property string ovpnTlsAuthDraft: ""

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

  function pathHint(p) {
    const s = String(p || "")
    if (!s.length)
      return ""
    const parts = s.split("/")
    return parts.length > 2 ? ("…/" + parts.slice(-2).join("/")) : s
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
            root.ovpnPassDraft,
            root.ovpnCaDraft,
            root.ovpnCertDraft,
            root.ovpnKeyDraft,
            root.ovpnTlsAuthDraft)
    }
  }

  FileDialog {
    id: ovpnCaDialog
    title: "OpenVPN CA certificate"
    nameFilters: ["Certificates (*.crt *.pem *.cer)", "All files (*)"]
    onAccepted: root.ovpnCaDraft = root.localPathFromUrl(selectedFile)
  }

  FileDialog {
    id: ovpnCertDialog
    title: "OpenVPN client certificate"
    nameFilters: ["Certificates (*.crt *.pem *.cer)", "All files (*)"]
    onAccepted: root.ovpnCertDraft = root.localPathFromUrl(selectedFile)
  }

  FileDialog {
    id: ovpnKeyDialog
    title: "OpenVPN private key"
    nameFilters: ["Keys (*.key *.pem)", "All files (*)"]
    onAccepted: root.ovpnKeyDraft = root.localPathFromUrl(selectedFile)
  }

  FileDialog {
    id: ovpnTlsAuthDialog
    title: "OpenVPN tls-auth key"
    nameFilters: ["Keys (*.key *.pem)", "All files (*)"]
    onAccepted: root.ovpnTlsAuthDraft = root.localPathFromUrl(selectedFile)
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
      label: "CA certificate…"
      hint: root.ovpnCaDraft.length
          ? root.pathHint(root.ovpnCaDraft)
          : "Optional — absolute path via +vpn.data ca= (session draft)"
      showSeparator: true
      interactive: true
      onActivated: ovpnCaDialog.open()
      Text {
        text: root.ovpnCaDraft.length ? "Change…" : "Choose…"
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: 12
      }
    }

    SettingsFormRow {
      label: "Client certificate…"
      hint: root.ovpnCertDraft.length
          ? root.pathHint(root.ovpnCertDraft)
          : "Optional — +vpn.data cert="
      showSeparator: true
      interactive: true
      onActivated: ovpnCertDialog.open()
      Text {
        text: root.ovpnCertDraft.length ? "Change…" : "Choose…"
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: 12
      }
    }

    SettingsFormRow {
      label: "Private key…"
      hint: root.ovpnKeyDraft.length
          ? root.pathHint(root.ovpnKeyDraft)
          : "Optional — +vpn.data key= (path only; never settings.json)"
      showSeparator: true
      interactive: true
      onActivated: ovpnKeyDialog.open()
      Text {
        text: root.ovpnKeyDraft.length ? "Change…" : "Choose…"
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: 12
      }
    }

    SettingsFormRow {
      label: "tls-auth key…"
      hint: root.ovpnTlsAuthDraft.length
          ? root.pathHint(root.ovpnTlsAuthDraft)
          : "Optional — +vpn.data tls-auth="
      showSeparator: true
      interactive: true
      onActivated: ovpnTlsAuthDialog.open()
      Text {
        text: root.ovpnTlsAuthDraft.length ? "Change…" : "Choose…"
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: 12
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
      visible: {
        const n = host && host.vpnOvpnPendingName
        return !!(host && String(n || "").length
                  && (root.ovpnCaDraft.length || root.ovpnCertDraft.length
                      || root.ovpnKeyDraft.length || root.ovpnTlsAuthDraft.length))
      }
      label: "Attach certs to last import…"
      hint: host ? ("nmcli +vpn.data → " + String(host.vpnOvpnPendingName || "")) : ""
      showSeparator: true
      interactive: host && !host.vpnBusy
      onActivated: {
        if (!host)
          return
        host.applyOpenVpnCerts(
              host.vpnOvpnPendingName,
              root.ovpnCaDraft,
              root.ovpnCertDraft,
              root.ovpnKeyDraft,
              root.ovpnTlsAuthDraft)
      }
      Text {
        text: host && host.vpnBusy ? "…" : "Apply"
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: 12
      }
    }

    SettingsFormRow {
      label: "Open NetworkManager"
      hint: "PKCS#11 · advanced edit · encrypted key passphrase"
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
    text: "Fact: nmcli connection up/down · WireGuard + OpenVPN import (.ovpn). Optional user/pass + CA/cert/key path attach are session-only. Cert path attach thin In · PKI/PKCS#11 Out · Headscale admin → Network → Headscale."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }
}
