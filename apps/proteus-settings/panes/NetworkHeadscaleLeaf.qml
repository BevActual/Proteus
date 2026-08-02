import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../shared"
import "../kit"

// Leaf UI for NetworkPane — remote Headscale admin (not local server).
// Fact: proteus-headscale.py · vault API key · settings.json URL only.
ColumnLayout {
  id: root
  property Item host
  width: parent ? parent.width : implicitWidth
  spacing: Theme.spaceMd

  property string urlDraft: ""
  property string keyDraft: ""
  property bool busy: false
  property string error: ""
  property string hint: ""
  property string version: ""
  property bool hasKey: false
  property bool reachable: false
  property int nodeCount: 0
  property var nodes: []
  property string confirmExpireId: ""
  property int rev: 0

  readonly property string script: Config.scriptsDir + "/proteus-headscale.py"

  readonly property bool urlDirty: {
    const a = String(Config.headscaleAdminUrl || "").trim().replace(/\/+$/, "")
    const b = String(urlDraft || "").trim().replace(/\/+$/, "")
    return a !== b
  }

  function shellQuote(s) {
    return "'" + String(s).replace(/'/g, "'\\''") + "'"
  }

  function adminUrlEnv() {
    const u = String(Config.headscaleAdminUrl || urlDraft || "").trim().replace(/\/+$/, "")
    return "PROTEUS_HEADSCALE_ADMIN_URL=" + root.shellQuote(u)
  }

  function refresh() {
    root.busy = true
    root.error = ""
    statusProc.command = [
      "bash", "-lc",
      root.adminUrlEnv() + " python3 " + root.shellQuote(root.script) + " status"
    ]
    nodesProc.command = [
      "bash", "-lc",
      root.adminUrlEnv() + " python3 " + root.shellQuote(root.script) + " nodes"
    ]
    kick(statusProc)
    kick(nodesProc)
  }

  function kick(proc) {
    proc.running = false
    proc.running = true
  }

  function applyUrl() {
    const u = String(urlDraft || "").trim().replace(/\/+$/, "")
    Config.headscaleAdminUrl = u
    root.busy = true
    root.error = ""
    setUrlProc.command = ["python3", root.script, "set-url", u]
    kick(setUrlProc)
  }

  function saveKey() {
    const k = String(keyDraft || "").trim()
    if (!k.length)
      return
    root.busy = true
    root.error = ""
    setKeyProc.command = [
      "bash", "-lc",
      "printf '%s\\n' " + root.shellQuote(k) + " | python3 " + root.shellQuote(root.script) + " set-key"
    ]
    kick(setKeyProc)
  }

  function clearKey() {
    root.busy = true
    root.error = ""
    clearKeyProc.command = ["python3", root.script, "clear-key"]
    kick(clearKeyProc)
  }

  function expireNode(id) {
    const nid = String(id || "").trim()
    if (!nid.length)
      return
    root.busy = true
    root.error = ""
    root.confirmExpireId = ""
    mutateProc.command = [
      "bash", "-lc",
      root.adminUrlEnv() + " python3 " + root.shellQuote(root.script)
          + " expire " + root.shellQuote(nid)
    ]
    kick(mutateProc)
  }

  function enableNode(id) {
    const nid = String(id || "").trim()
    if (!nid.length)
      return
    root.busy = true
    root.error = ""
    mutateProc.command = [
      "bash", "-lc",
      root.adminUrlEnv() + " python3 " + root.shellQuote(root.script)
          + " enable " + root.shellQuote(nid)
    ]
    kick(mutateProc)
  }

  function openAdmin() {
    const u = String(Config.headscaleAdminUrl || urlDraft || "").trim()
    if (!u.length)
      return
    Config.openHeadscaleAdmin(u)
  }

  Component.onCompleted: {
    urlDraft = Config.headscaleAdminUrl
    refresh()
  }

  SettingsGroup {
    title: "Headscale admin"

    SettingsFormRow {
      label: "Status"
      hint: {
        const _r = root.rev
        if (root.busy)
          return "Working…"
        if (root.error.length)
          return root.error
        if (root.hint.length)
          return root.hint
        if (!String(Config.headscaleAdminUrl || "").trim().length)
          return "Set admin URL · API key stays in vault"
        return (root.reachable ? "Reachable" : "Not verified")
            + (root.version.length ? (" · " + root.version) : "")
            + (root.hasKey ? (" · " + root.nodeCount + " nodes") : " · no API key")
      }
      showSeparator: true
      Text {
        text: {
          const _r = root.rev
          if (!String(Config.headscaleAdminUrl || "").trim().length)
            return "Unset"
          if (root.reachable)
            return "OK"
          return "…"
        }
        color: root.reachable ? Theme.accent : Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: 12
      }
    }

    SettingsFormRow {
      label: "Admin URL"
      hint: "https://headscale.example.com · not the Tailscale client login field"
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
        border.color: urlInput.activeFocus ? Theme.accent : Theme.border

        TextInput {
          id: urlInput
          anchors.fill: parent
          anchors.leftMargin: 10
          anchors.rightMargin: 10
          color: Theme.text
          font.family: Theme.fontFamily
          font.pixelSize: 13
          verticalAlignment: TextInput.AlignVCenter
          clip: true
          text: root.urlDraft
          onTextChanged: root.urlDraft = text
        }
      }
    }

    SettingsFormRow {
      label: "Apply admin URL"
      hint: root.urlDirty ? "Saves to settings.json + vault side file" : "Saved"
      showSeparator: true
      interactive: root.urlDirty && !root.busy
      onActivated: root.applyUrl()
      Text {
        text: root.busy ? "…" : "Apply"
        color: root.urlDirty ? Theme.accent : Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: 12
      }
    }

    SettingsFormRow {
      label: "API key"
      hint: "headscale apikeys create · vault ~/.local/share/proteus/headscale/ · never settings.json"
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
        border.color: keyInput.activeFocus ? Theme.accent : Theme.border

        TextInput {
          id: keyInput
          anchors.fill: parent
          anchors.leftMargin: 10
          anchors.rightMargin: 10
          color: Theme.text
          font.family: Theme.fontFamily
          font.pixelSize: 13
          verticalAlignment: TextInput.AlignVCenter
          clip: true
          echoMode: TextInput.Password
          text: root.keyDraft
          onTextChanged: root.keyDraft = text
        }
      }
    }

    SettingsFormRow {
      label: "Save API key"
      hint: root.hasKey ? "Key on disk · paste replaces" : "Paste key above then Save"
      showSeparator: true
      interactive: root.keyDraft.trim().length > 0 && !root.busy
      onActivated: root.saveKey()
      Text {
        text: "Save"
        color: root.keyDraft.trim().length ? Theme.accent : Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: 12
      }
    }

    SettingsFormRow {
      label: "Clear API key"
      hint: "Removes vault file"
      showSeparator: true
      interactive: root.hasKey && !root.busy
      onActivated: root.clearKey()
      Text {
        text: "Clear"
        color: root.hasKey ? Theme.danger : Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: 12
      }
    }

    SettingsFormRow {
      label: "Open admin UI"
      hint: "Browser · /api/v1/docs when available"
      showSeparator: true
      interactive: String(Config.headscaleAdminUrl || urlDraft || "").trim().length > 0
      onActivated: root.openAdmin()
      Text {
        text: "›"
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }
    }

    SettingsFormRow {
      label: "Refresh"
      hint: "Re-probe /version + list nodes"
      showSeparator: false
      interactive: !root.busy
      onActivated: root.refresh()
      Text {
        text: "↻"
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: 12
      }
    }
  }

  SettingsGroup {
    visible: root.nodes && root.nodes.length > 0
    title: "Nodes"

    Repeater {
      model: root.nodes

      SettingsFormRow {
        required property var modelData
        required property int index
        label: modelData.name || ("node " + modelData.id)
        hint: {
          const bits = []
          if (modelData.user)
            bits.push(modelData.user)
          if (modelData.ips && modelData.ips.length)
            bits.push(modelData.ips[0])
          bits.push(modelData.online ? "Online" : "Offline")
          if (modelData.expiry)
            bits.push("expiry set")
          return bits.join(" · ")
        }
        showSeparator: index < root.nodes.length - 1
        interactive: false

        Row {
          spacing: 10

          Text {
            visible: root.confirmExpireId !== String(modelData.id)
            text: "Expire"
            color: Theme.danger
            font.family: Theme.fontFamily
            font.pixelSize: 12
            MouseArea {
              anchors.fill: parent
              anchors.margins: -4
              cursorShape: Qt.PointingHandCursor
              onClicked: root.confirmExpireId = String(modelData.id)
            }
          }

          Text {
            visible: root.confirmExpireId === String(modelData.id)
            text: "Confirm"
            color: Theme.danger
            font.family: Theme.fontFamily
            font.pixelSize: 12
            font.weight: Font.DemiBold
            MouseArea {
              anchors.fill: parent
              anchors.margins: -4
              cursorShape: Qt.PointingHandCursor
              onClicked: root.expireNode(modelData.id)
            }
          }

          Text {
            visible: root.confirmExpireId === String(modelData.id)
            text: "Cancel"
            color: Theme.textMute
            font.family: Theme.fontFamily
            font.pixelSize: 12
            MouseArea {
              anchors.fill: parent
              anchors.margins: -4
              cursorShape: Qt.PointingHandCursor
              onClicked: root.confirmExpireId = ""
            }
          }

          Text {
            text: "Enable"
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: 12
            MouseArea {
              anchors.fill: parent
              anchors.margins: -4
              cursorShape: Qt.PointingHandCursor
              onClicked: root.enableNode(modelData.id)
            }
          }
        }
      }
    }
  }

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 480
    text: "Fact: proteus-headscale.py · GET /api/v1/node · expire/enable · vault API key. ACL/policy · users · preauth · DNS · server install Out."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }

  Process {
    id: statusProc
    command: ["true"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const data = JSON.parse(String(text).trim() || "{}")
          root.hasKey = !!data.hasKey
          root.reachable = !!data.reachable
          root.version = String(data.version || "")
          root.nodeCount = Math.max(0, Math.round(Number(data.nodeCount) || 0))
          root.hint = String(data.hint || "")
          if (data.ok === false)
            root.error = String(data.error || "status failed")
          root.rev++
        } catch (e) {
          root.error = "Could not parse status"
          root.rev++
        }
      }
    }
  }

  Process {
    id: nodesProc
    command: ["true"]
    stdout: StdioCollector {
      onStreamFinished: {
        root.busy = false
        try {
          const data = JSON.parse(String(text).trim() || "{}")
          if (data.ok === false) {
            root.nodes = []
            if (!root.error.length)
              root.error = String(data.error || "")
            root.rev++
            return
          }
          root.nodes = Array.isArray(data.nodes) ? data.nodes : []
          root.nodeCount = root.nodes.length
          root.rev++
        } catch (e) {
          root.nodes = []
          root.error = "Could not parse nodes"
          root.rev++
        }
      }
    }
  }

  Process {
    id: setUrlProc
    command: ["true"]
    stdout: StdioCollector {
      onStreamFinished: {
        root.refresh()
      }
    }
  }

  Process {
    id: setKeyProc
    command: ["true"]
    stdout: StdioCollector {
      onStreamFinished: {
        root.keyDraft = ""
        root.refresh()
      }
    }
  }

  Process {
    id: clearKeyProc
    command: ["true"]
    stdout: StdioCollector {
      onStreamFinished: root.refresh()
    }
  }

  Process {
    id: mutateProc
    command: ["true"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const data = JSON.parse(String(text).trim() || "{}")
          if (data.ok === false)
            root.error = String(data.error || "mutate failed")
        } catch (e) {
          root.error = "Could not parse mutate"
        }
        root.refresh()
      }
    }
  }
}
