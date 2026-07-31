import Quickshell
import QtQuick
import QtQuick.Layouts
import "../shared"
import "../kit"

// Leaf UI for NetworkPane — Wi‑Fi (password prompt for secured SSIDs).
ColumnLayout {
  id: root
  property Item host
  width: parent ? parent.width : implicitWidth
  spacing: Theme.spaceMd

  function wifiHint(net) {
    if (!net)
      return ""
    const bits = []
    if (net.active)
      bits.push("Connected")
    if (net.signal)
      bits.push(net.signal + "%")
    if (net.security && String(net.security).length)
      bits.push(net.security)
    else if (!net.active)
      bits.push("Open / unknown")
    return bits.join(" · ")
  }

  SettingsGroup {
    title: "Wi‑Fi"

    SettingsFormRow {
      visible: host && !host.wifiNetworks.length && !(host && host.wifiError.length)
      label: "Networks"
      hint: host && host.wifiBusy
          ? "Scanning…"
          : (host && host.wifiStatus.length ? host.wifiStatus : "No networks — try Rescan")
      showSeparator: true
    }

    SettingsFormRow {
      visible: host && host.wifiError.length > 0
      label: "Status"
      hint: host ? host.wifiError : ""
      showSeparator: true
      labelColor: Theme.danger
    }

    SettingsFormRow {
      visible: host && host.wifiPasswordSsid.length > 0
      label: "Password"
      hint: host ? ("For " + host.wifiPasswordSsid) : ""
      showSeparator: true
    }

    Item {
      visible: host && host.wifiPasswordSsid.length > 0
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
        border.color: wifiPass.activeFocus ? Theme.accent : Theme.border

        TextInput {
          id: wifiPass
          anchors.fill: parent
          anchors.leftMargin: 10
          anchors.rightMargin: 10
          color: Theme.text
          font.family: Theme.fontFamily
          font.pixelSize: 13
          echoMode: TextInput.Password
          verticalAlignment: TextInput.AlignVCenter
          clip: true
          text: host ? host.wifiPasswordDraft : ""
          onTextChanged: {
            if (host)
              host.wifiPasswordDraft = text
          }
          Keys.onReturnPressed: {
            if (host)
              host.submitWifiPassword()
          }
          Keys.onEscapePressed: {
            if (host)
              host.cancelWifiPassword()
          }
        }
      }
    }

    SettingsFormRow {
      visible: host && host.wifiPasswordSsid.length > 0
      label: "Connect with password"
      hint: "Blank tries a saved NM profile · never stored in settings.json"
      showSeparator: true
      interactive: host && !host.wifiBusy
      onActivated: {
        if (host)
          host.submitWifiPassword()
      }
      Text {
        text: host && host.wifiBusy ? "…" : "Connect"
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: 12
      }
    }

    SettingsFormRow {
      visible: host && host.wifiPasswordSsid.length > 0
      label: "Cancel"
      hint: host ? host.wifiPasswordSsid : ""
      showSeparator: true
      interactive: host && !host.wifiBusy
      onActivated: {
        if (host)
          host.cancelWifiPassword()
      }
      Text {
        text: "Cancel"
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: 12
      }
    }

    Repeater {
      model: host ? host.wifiNetworks : []

      SettingsFormRow {
        required property var modelData
        required property int index
        label: modelData.ssid || "(hidden)"
        hint: root.wifiHint(modelData)
        showSeparator: true
        interactive: host && !host.wifiBusy && modelData.ssid && modelData.ssid.length > 0
        onActivated: {
          if (!host)
            return
          if (modelData.active)
            host.disconnectWifi()
          else
            host.beginWifiConnect(modelData.ssid, modelData.security)
        }
        Text {
          text: {
            if (host && host.wifiBusy)
              return "…"
            if (host && host.wifiPasswordSsid === modelData.ssid)
              return "…"
            return modelData.active ? "Disconnect" : "Connect"
          }
          color: {
            if (host && host.wifiBusy)
              return Theme.textMute
            return modelData.active ? Theme.danger : Theme.accent
          }
          font.family: Theme.fontFamily
          font.pixelSize: 12
        }
      }
    }

    SettingsFormRow {
      label: "Rescan"
      hint: {
        if (!host)
          return ""
        if (host.wifiBusy)
          return "Working…"
        if (host.wifiDevice.length)
          return "Interface " + host.wifiDevice + " · nmcli device wifi"
        return "Needs a Wi‑Fi device"
      }
      showSeparator: false
      interactive: host && !host.wifiBusy && host.wifiDevice.length > 0
      onActivated: {
        if (host)
          host.rescanWifi()
      }
      Text {
        text: host && host.wifiBusy ? "…" : "↻"
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }
    }
  }

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 480
    text: "Fact: nmcli device wifi connect · secured SSIDs prompt in-pane (password never in settings.json)."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }
}
