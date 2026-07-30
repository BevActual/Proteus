import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../shared"
import "../kit"

// Leaf UI for NetworkPane — This machine (SettingsFormRow honesty).
ColumnLayout {
  id: root
  property Item host
  width: parent ? parent.width : implicitWidth
  spacing: Theme.spaceMd

  readonly property string hostnameHint: {
    if (!host)
      return ""
    if (host.hostnameError.length)
      return host.hostnameError
    if (host.hostnameBusy)
      return "Applying…"
    if (host.hostnameDirty)
      return (host.hostname.length ? host.hostname : "…") + " · pending Apply"
    if (host.hostname.length)
      return host.hostname + " · hostnamectl"
    return "Reading hostname…"
  }

  SettingsGroup {
    title: "This machine"

    SettingsFormRow {
      label: "Hostname"
      hint: root.hostnameHint
      showSeparator: true
      labelColor: host && host.hostnameError.length ? Theme.danger : Theme.text

      RowLayout {
        spacing: Theme.spaceSm
        TextInput {
          Layout.preferredWidth: 160
          text: host ? host.hostnameDraft : ""
          color: Theme.text
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSize
          verticalAlignment: TextInput.AlignVCenter
          selectByMouse: true
          enabled: host && !host.hostnameBusy
          onTextChanged: {
            if (host)
              host.hostnameDraft = text
          }
          Keys.onReturnPressed: {
            if (host)
              host.applyHostname()
          }
        }
        Text {
          visible: host && (host.hostnameDirty || host.hostnameBusy)
          text: host && host.hostnameBusy ? "…" : "Apply"
          color: host && host.hostnameBusy ? Theme.textMute : Theme.accent
          font.family: Theme.fontFamily
          font.pixelSize: 12
          MouseArea {
            anchors.fill: parent
            enabled: host && host.hostnameDirty && !host.hostnameBusy
            cursorShape: Qt.PointingHandCursor
            onClicked: host.applyHostname()
          }
        }
      }
    }

    SettingsFormRow {
      label: "Refresh all"
      hint: "Reload devices, Wi‑Fi, Bluetooth, Tailscale, and VPN"
      showSeparator: false
      interactive: true
      onActivated: {
        if (host)
          host.refresh()
      }
      Text {
        text: "↻"
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }
    }
  }

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 480
    text: "Fact: hostnamectl set-hostname (polkit-gated)."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }
}
