import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../shared"
import "../kit"

// Leaf UI for NetworkPane — This machine (hostname).
ColumnLayout {
  id: root
  property Item host
  width: parent ? parent.width : implicitWidth
  spacing: Theme.spaceMd

  SettingsGroup {
    title: "This machine"

    SettingsFormRow {
      label: "Hostname"
      hint: host && host.hostnameError.length ? host.hostnameError
          : (host && host.hostname.length ? host.hostname : "…")
      showSeparator: true
      labelColor: host && host.hostnameError.length ? Theme.danger : Theme.text

      RowLayout {
        spacing: Theme.spaceSm
        TextInput {
          Layout.preferredWidth: 140
          text: host ? host.hostnameDraft : ""
          color: Theme.text
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSize
          verticalAlignment: TextInput.AlignVCenter
          selectByMouse: true
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
          visible: host && host.hostnameDirty
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
      label: "Refresh"
      hint: "Reload devices, Wi‑Fi, Bluetooth, Tailscale, VPN"
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
}
