pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Online accounts seats — Settings Accounts pane.
// CLI SoT: proteus-accounts (catalog · status · connect · disconnect).
// Tokens never live in settings.json.
Singleton {
  id: root

  property bool ready: false
  property bool busy: false
  property string error: ""
  property bool googleClientConfigured: false
  property var connectors: []
  property var seats: []

  function _binCandidates() {
    return [
      Quickshell.shellDir + "/../services/proteus-accounts/bin/proteus-accounts",
      Quickshell.shellDir + "/../services/proteus-accounts/target/release/proteus-accounts",
      Quickshell.env("HOME") + "/.local/libexec/proteus-accounts",
      Quickshell.env("HOME") + "/.local/bin/proteus-accounts",
      "/usr/local/libexec/proteus-accounts",
      "/usr/local/bin/proteus-accounts"
    ]
  }

  function _runCmd(args) {
    // bash picks first executable candidate, then runs remaining args.
    const picks = root._binCandidates().map(p => "'" + String(p).replace(/'/g, "'\\''") + "'").join(" ")
    const rest = (args || []).map(a => "'" + String(a).replace(/'/g, "'\\''") + "'").join(" ")
    return ["bash", "-lc",
      "for c in " + picks + "; do "
      + "if [[ -x \"$c\" ]]; then exec \"$c\" " + rest + "; fi; "
      + "done; echo '{\"ok\":false,\"error\":\"proteus-accounts not installed\"}'; exit 127"
    ]
  }

  function refresh() {
    root.busy = true
    root.error = ""
    statusProc.command = root._runCmd(["status"])
    statusProc.running = false
    statusProc.running = true
  }

  function connectGoogle() {
    root.busy = true
    root.error = ""
    connectProc.command = root._runCmd(["connect", "google"])
    connectProc.running = false
    connectProc.running = true
  }

  function disconnectSeat(seatId) {
    if (!seatId || !String(seatId).length)
      return
    root.busy = true
    root.error = ""
    disconnectProc.command = root._runCmd(["disconnect", String(seatId)])
    disconnectProc.running = false
    disconnectProc.running = true
  }

  function _parse(text) {
    try {
      return JSON.parse(String(text || "").trim() || "{}")
    } catch (e) {
      return { ok: false, error: "bad JSON from proteus-accounts" }
    }
  }

  function _applyStatus(obj) {
    if (!obj || obj.ok === false) {
      root.error = (obj && obj.error) ? String(obj.error) : "status failed"
      root.connectors = root.connectors.length ? root.connectors : []
      root.ready = true
      root.busy = false
      return
    }
    root.googleClientConfigured = !!obj.googleClientConfigured
    root.connectors = obj.connectors || []
    root.seats = obj.seats || []
    root.error = ""
    root.ready = true
    root.busy = false
  }

  Process {
    id: statusProc
    command: ["true"]
    stdout: StdioCollector {
      onStreamFinished: root._applyStatus(root._parse(text))
    }
    stderr: StdioCollector {}
    onExited: code => {
      if (code !== 0 && !root.ready)
        root._applyStatus({ ok: false, error: "proteus-accounts status exit " + code })
      else if (code !== 0)
        root.busy = false
    }
  }

  Process {
    id: connectProc
    command: ["true"]
    stdout: StdioCollector {
      onStreamFinished: {
        const obj = root._parse(text)
        if (obj && obj.ok === false)
          root.error = String(obj.error || "connect failed")
      }
    }
    stderr: StdioCollector {}
    onExited: () => {
      root.busy = false
      root.refresh()
    }
  }

  Process {
    id: disconnectProc
    command: ["true"]
    stdout: StdioCollector {}
    stderr: StdioCollector {}
    onExited: () => {
      root.busy = false
      root.refresh()
    }
  }

  Component.onCompleted: root.refresh()
}
