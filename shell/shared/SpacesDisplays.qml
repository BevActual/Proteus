pragma Singleton

import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick

// Multi-head Spaces honesty — DesktopSpacesLeaf + hotplug ensure.
// Fact: bands via proteus-workspace; named Spaces / Super+7–10 Out.
Singleton {
  id: root

  property bool busy: false
  property bool ready: false
  property string error: ""
  property string hint: ""
  property string summary: "—"
  property string mode: "synced"
  property int monitorCount: 0
  property var monitors: []
  property int rev: 0

  property int lastEnsureCount: -1
  property bool ensurePending: false

  readonly property string helper: Config.scriptsDir + "/proteus-workspace"

  readonly property string summaryLabel: {
    if (!root.ready && root.busy)
      return "Reading displays…"
    if (root.summary && root.summary !== "—")
      return root.summary
    if (root.error.length)
      return root.error
    return "—"
  }

  readonly property int liveMonitorCount: {
    try {
      return Hyprland.monitors.values.length
    } catch (e) {
      return 0
    }
  }

  onLiveMonitorCountChanged: {
    if (liveMonitorCount <= 0)
      return
    root.refresh()
    if (root.lastEnsureCount >= 0 && liveMonitorCount !== root.lastEnsureCount)
      root.scheduleEnsure()
    else if (root.lastEnsureCount < 0)
      root.lastEnsureCount = liveMonitorCount
  }

  function refresh() {
    root.busy = true
    root.error = ""
    statusProc.command = ["bash", root.helper, "status"]
    statusProc.running = false
    statusProc.running = true
  }

  function scheduleEnsure() {
    root.ensurePending = true
    ensureDebounce.restart()
  }

  function ensureBands() {
    root.ensurePending = false
    ensureProc.command = ["bash", root.helper, "ensure"]
    ensureProc.running = false
    ensureProc.running = true
  }

  Timer {
    id: ensureDebounce
    interval: 400
    repeat: false
    onTriggered: {
      if (root.ensurePending || root.liveMonitorCount !== root.lastEnsureCount)
        root.ensureBands()
    }
  }

  Process {
    id: statusProc
    command: ["true"]
    stdout: StdioCollector {
      onStreamFinished: {
        root.busy = false
        try {
          const data = JSON.parse(String(text).trim() || "{}")
          if (data.ok === false) {
            root.error = String(data.error || "Could not read Spaces displays")
            root.ready = true
            root.rev++
            return
          }
          root.mode = String(data.mode || Config.workspaceMode || "synced")
          root.monitorCount = Math.max(0, Math.round(Number(data.monitorCount) || 0))
          root.monitors = Array.isArray(data.monitors) ? data.monitors : []
          root.summary = String(data.summary || "—")
          root.hint = String(data.hint || "")
          root.error = ""
          root.ready = true
          root.rev++
        } catch (e) {
          root.error = "Could not parse Spaces status"
          root.ready = true
          root.rev++
        }
      }
    }
  }

  Process {
    id: ensureProc
    command: ["true"]
    onExited: (exitCode) => {
      root.lastEnsureCount = root.liveMonitorCount
      root.refresh()
      if (exitCode !== 0 && !root.error.length)
        root.error = "Could not rebind Spaces bands"
    }
  }

  Component.onCompleted: root.refresh()

  Connections {
    target: Config
    function onWorkspaceModeChanged() {
      root.refresh()
    }
  }
}
