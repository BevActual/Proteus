import Quickshell
import QtQuick
import QtQuick.Layouts
import "../shared"
import "../kit"

// Leaf UI for NetworkPane — Tailscale.
ColumnLayout {
  id: root
  property Item host
  width: parent ? parent.width : implicitWidth
  spacing: Theme.spaceMd

  SettingsGroup {
    title: "Tailscale"

    SettingsFormRow {
      label: "Status"
      hint: host ? host.tsHint : ""
      showSeparator: true
      Text {
        visible: host && host.tsAvailable && host.tsRunning
        text: "Connected"
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: 12
      }
    }

    SettingsFormRow {
      visible: host && host.tsAvailable && host.tsIp.length > 0
      label: "Tailscale IP"
      hint: host ? host.tsIp : ""
      showSeparator: true
      interactive: true
      onActivated: {
        if (host)
          host.copyTailscaleIp()
      }
      Text {
        text: host && host.tsCopied.length ? host.tsCopied : "Copy"
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: 12
      }
    }

    SettingsFormRow {
      visible: host && host.tsAvailable && host.tsPeers > 0
      label: "Peers"
      hint: host ? (host.tsPeers + (host.tsPeers === 1 ? " device online" : " devices online")) : ""
      showSeparator: true
    }

    SettingsFormRow {
      visible: host && host.tsAvailable
      label: host ? host.tsActionLabel : ""
      hint: host && host.tsNeedsLogin
          ? "Opens Tailscale login (browser or CLI)"
          : (host && host.tsRunning ? "tailscale down" : "tailscale up")
      showSeparator: true
      interactive: host && host.tsAvailable && !host.tsBusy && host.tsActionLabel.length > 0
      onActivated: {
        if (host)
          host.runTailscaleAction()
      }
      Text {
        text: "›"
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }
    }

    SettingsFormRow {
      label: host && host.tsAvailable ? "Open Tailscale status" : "Tailscale not installed"
      hint: host && host.tsAvailable
          ? "tailscale status in a terminal"
          : "Install tailscale · Headscale = set login-server via CLI"
      showSeparator: false
      interactive: host && host.tsAvailable
      onActivated: Config.openTailscaleStatus()
      Text {
        text: host && host.tsAvailable ? "›" : ""
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }
    }
  }
}
