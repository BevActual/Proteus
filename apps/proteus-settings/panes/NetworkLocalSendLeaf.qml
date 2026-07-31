import Quickshell
import QtQuick
import QtQuick.Layouts
import "../shared"
import "../kit"
import ".." // root module — SettingsNav singleton

// Leaf UI for NetworkPane — LocalSend (LAN AirDrop-style share).
ColumnLayout {
  id: root
  property Item host
  width: parent ? parent.width : implicitWidth
  spacing: Theme.spaceMd

  Component.onCompleted: LocalSend.refresh()

  SettingsGroup {
    title: "LocalSend"

    SettingsFormRow {
      label: "Status"
      hint: LocalSend.available
          ? LocalSend.hint
          : "Native package localsend-bin (AUR)"
      showSeparator: true
      Text {
        text: LocalSend.statusLabel
        color: {
          if (!LocalSend.available)
            return Theme.textMute
          if (LocalSend.running)
            return Theme.accent
          return Theme.textDim
        }
        font.family: Theme.fontFamily
        font.pixelSize: 12
      }
    }

    SettingsFormRow {
      visible: LocalSend.available
      label: LocalSend.running ? "Stop receiving" : "Start LocalSend"
      hint: LocalSend.running
          ? "Quits LocalSend (port 53317)"
          : "Opens LocalSend so nearby devices can send files"
      showSeparator: true
      interactive: LocalSend.available
      onActivated: {
        if (LocalSend.running)
          LocalSend.stop()
        else
          LocalSend.start()
      }
      Text {
        text: LocalSend.running ? "Stop" : "Start"
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: 12
      }
    }

    SettingsFormRow {
      label: LocalSend.available ? "Open LocalSend" : "Install LocalSend…"
      hint: LocalSend.available
          ? "Send or receive files on the local network"
          : "Software → AUR · localsend-bin"
      showSeparator: true
      interactive: true
      onActivated: {
        if (LocalSend.available)
          LocalSend.open()
        else
          SettingsNav.goInstallSearch("localsend-bin", "packages-aur")
      }
      Text {
        text: LocalSend.available ? "›" : "Install…"
        color: LocalSend.available ? Theme.textMute : Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }
    }

    SettingsFormRow {
      visible: LocalSend.receiveEndpoint.length > 0
      label: "Receive address"
      hint: LocalSend.receiveEndpoint + " · same LAN / Tailscale"
      showSeparator: true
      interactive: true
      onActivated: Config.copyToClipboard(LocalSend.receiveEndpoint)
      Text {
        text: "Copy"
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: 12
      }
    }

    SettingsFormRow {
      label: "Refresh"
      hint: "Re-check install + listening port"
      showSeparator: false
      interactive: true
      onActivated: LocalSend.refresh()
      Text {
        text: "↻"
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: 12
      }
    }
  }

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 480
    text: "Fact: localsend · default port 53317 · nearby devices on the same LAN / Tailscale."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }
}
