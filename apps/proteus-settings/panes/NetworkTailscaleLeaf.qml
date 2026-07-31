import Quickshell
import QtQuick
import QtQuick.Layouts
import "../shared"
import "../kit"
import ".." // root module — SettingsNav singleton

// Leaf UI for NetworkPane — Tailscale peers · exit-node · login-server.
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

  readonly property var exitOptions: {
    const opts = [
      {
        id: "",
        label: "None"
      }
    ]
    if (!host || !host.tsPeerList)
      return opts
    for (let i = 0; i < host.tsPeerList.length; i++) {
      const p = host.tsPeerList[i]
      if (!p || !p.exitOption)
        continue
      const id = String(p.ip || p.id || "")
      if (!id.length)
        continue
      opts.push({
        id: id,
        label: p.label || id
      })
    }
    return opts
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
      visible: host && host.tsError.length > 0
      label: "Error"
      hint: host ? host.tsError : ""
      labelColor: Theme.danger
      showSeparator: true
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
      visible: host && host.tsAvailable && host.tsRunning
      label: "Exit node"
      hint: host && host.tsExitNodeLabel.length
          ? ("Using " + host.tsExitNodeLabel)
          : "None — traffic leaves this machine"
      showSeparator: true
    }

    SettingsFormRow {
      visible: host && host.tsAvailable && host.tsRunning && root.exitOptions.length > 1
      label: "Set exit node"
      hint: "tailscale set --exit-node"
      showSeparator: true
      SettingsCombo {
        preferredWidth: 180
        enabled: host && !host.tsBusy
        model: root.exitOptions
        currentValue: host ? host.tsExitNode : ""
        onActivated: v => {
          if (!host)
            return
          const next = String(v || "")
          if (next === String(host.tsExitNode || ""))
            return
          host.setExitNode(next)
        }
      }
    }

    SettingsFormRow {
      visible: host && host.tsAvailable
      label: "Login server"
      hint: "Headscale URL · empty = Tailscale corp"
      showSeparator: true
    }

    Item {
      visible: host && host.tsAvailable
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
        border.color: loginInput.activeFocus ? Theme.accent : Theme.border

        TextInput {
          id: loginInput
          anchors.fill: parent
          anchors.leftMargin: 10
          anchors.rightMargin: 10
          color: Theme.text
          font.family: Theme.fontFamily
          font.pixelSize: 13
          verticalAlignment: TextInput.AlignVCenter
          clip: true
          text: host ? host.tsLoginDraft : ""
          onTextChanged: {
            if (host)
              host.tsLoginDraft = text
          }
        }
      }
    }

    SettingsFormRow {
      visible: host && host.tsAvailable
      label: "Apply login server"
      hint: host && host.tsLoginDirty
          ? "Saves + tailscale up"
          : "Saved"
      showSeparator: true
      interactive: host && host.tsAvailable && !host.tsBusy && host.tsLoginDirty
      onActivated: {
        if (host)
          host.applyLoginServer()
      }
      Text {
        text: host && host.tsBusy ? "…" : "Apply"
        color: host && host.tsLoginDirty ? Theme.accent : Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: 12
      }
    }

    SettingsFormRow {
      label: host && host.tsAvailable ? "Open Tailscale status" : "Install Tailscale…"
      hint: host && host.tsAvailable
          ? "tailscale status · Headscale admin stays Out"
          : "Software → Repos · tailscale"
      showSeparator: false
      interactive: true
      onActivated: {
        if (host && host.tsAvailable)
          Config.openTailscaleStatus()
        else
          SettingsNav.goInstallSearch("tailscale")
      }
      Text {
        text: host && host.tsAvailable ? "›" : "Install…"
        color: host && host.tsAvailable ? Theme.textMute : Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }
    }
  }

  SettingsGroup {
    visible: host && host.tsAvailable && host.tsPeerList && host.tsPeerList.length > 0
    title: "Peers"

    Repeater {
      model: host ? host.tsPeerList : []

      SettingsFormRow {
        required property var modelData
        required property int index
        label: modelData.label || modelData.ip || "peer"
        hint: {
          const bits = []
          if (modelData.ip)
            bits.push(modelData.ip)
          bits.push(modelData.online ? "Online" : "Offline")
          if (modelData.exitNode)
            bits.push("Exit")
          else if (modelData.exitOption)
            bits.push("Can exit")
          return bits.join(" · ")
        }
        showSeparator: index < host.tsPeerList.length - 1
        interactive: host && modelData.ip && String(modelData.ip).length > 0
        onActivated: {
          if (host)
            host.copyPeerIp(modelData.ip)
        }
        Text {
          text: modelData.ip ? (host && host.tsCopied.length ? "Copied" : "Copy") : ""
          color: Theme.accent
          font.family: Theme.fontFamily
          font.pixelSize: 12
        }
      }
    }
  }

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 480
    text: "Fact: tailscale status --json · set --exit-node · up --login-server. Headscale admin Out."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }
}
