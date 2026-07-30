import Quickshell
import QtQuick
import QtQuick.Layouts
import "../shared"
import "../kit"

// Leaf UI for NetworkPane — Tailscale (status/actions denser).
ColumnLayout {
  id: root
  property Item host
  width: parent ? parent.width : implicitWidth
  spacing: Theme.spaceMd

  readonly property string statusTrailing: {
    if (!host || !host.tsAvailable)
      return ""
    if (host.tsBusy)
      return "…"
    if (host.tsRunning)
      return "Connected"
    if (host.tsNeedsLogin)
      return "Login"
    if (host.tsState === "Stopped")
      return "Stopped"
    if (host.tsState === "Error")
      return "Error"
    return host.tsState || ""
  }

  readonly property string actionHint: {
    if (!host)
      return ""
    if (host.tsBusy)
      return "Working…"
    if (host.tsNeedsLogin)
      return "Opens Tailscale login (browser or CLI)"
    if (host.tsRunning)
      return "tailscale down"
    return "tailscale up"
  }

  SettingsGroup {
    title: "Tailscale"

    SettingsFormRow {
      label: "Status"
      hint: {
        if (!host)
          return ""
        if (!host.tsAvailable)
          return host.tsHint.length ? host.tsHint : "Not installed"
        return host.tsHint.length ? host.tsHint : (host.tsState || "Unknown")
      }
      showSeparator: true
      Text {
        text: root.statusTrailing
        color: {
          if (!host || !host.tsAvailable)
            return Theme.textMute
          if (host.tsBusy)
            return Theme.textMute
          if (host.tsRunning)
            return Theme.accent
          if (host.tsState === "Error")
            return Theme.danger
          return Theme.textMute
        }
        font.family: Theme.fontFamily
        font.pixelSize: 12
      }
    }

    SettingsFormRow {
      visible: host && host.tsAvailable && host.tsIp.length > 0
      label: "Tailscale IP"
      hint: host ? host.tsIp : ""
      showSeparator: true
      interactive: host && host.tsAvailable && host.tsIp.length > 0 && !host.tsBusy
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
      hint: root.actionHint
      showSeparator: true
      interactive: host && host.tsAvailable && !host.tsBusy && host.tsActionLabel.length > 0
          && host.tsActionLabel !== "Working…"
      onActivated: {
        if (host)
          host.runTailscaleAction()
      }
      Text {
        text: host && host.tsBusy ? "…" : "›"
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }
    }

    SettingsFormRow {
      label: host && host.tsAvailable ? "Open Tailscale status" : "Tailscale not installed"
      hint: host && host.tsAvailable
          ? "tailscale status · Headscale = login-server via CLI"
          : "Install tailscale · Headscale stays CLI"
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

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 480
    text: "Fact: tailscale status --json · wl-copy for IP · Headscale admin stays Out."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }
}
