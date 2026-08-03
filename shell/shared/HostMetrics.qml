pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Host dashboard metrics glance (HexOS-style cards): storage drives/mounts/
// pools · network rates · health alerts via proteus-host-metrics.py.
// Read-only — mutations stay in the Workloads app.
Singleton {
  id: root

  property int watchers: 0
  readonly property bool polling: watchers > 0

  property bool busy: false
  property bool ready: false
  property string error: ""
  property string hint: ""
  property string summary: "—"

  property var drives: []
  property var mounts: []
  property var pools: []
  property bool smartAvailable: false
  property string netPrimary: ""
  property var netInterfaces: []
  property bool sharesAvailable: false
  property bool smbActive: false
  property var shares: []
  property var alerts: []
  property int failedUnits: 0
  property int rev: 0

  readonly property string script: Config.scriptsDir + "/proteus-host-metrics.py"

  readonly property string summaryLabel: {
    if (!root.ready && root.busy)
      return "Reading host metrics…"
    if (root.summary && root.summary !== "—")
      return root.summary
    if (root.error.length)
      return root.error
    return "—"
  }

  readonly property var primaryInterface: {
    const list = root.netInterfaces || []
    for (let i = 0; i < list.length; i++) {
      if (list[i] && list[i].name === root.netPrimary)
        return list[i]
    }
    return list.length ? list[0] : null
  }

  readonly property int alertCount: (root.alerts || []).length

  function rateLabel(bps) {
    const n = Number(bps) || 0
    if (n >= 1024 * 1024)
      return (n / (1024 * 1024)).toFixed(1) + " MB/s"
    if (n >= 1024)
      return (n / 1024).toFixed(0) + " KB/s"
    return n.toFixed(0) + " B/s"
  }

  function retain() {
    watchers++
  }

  function release() {
    watchers = Math.max(0, watchers - 1)
  }

  function refresh() {
    root.busy = true
    root.error = ""
    fetchProc.command = ["python3", root.script]
    fetchProc.running = false
    fetchProc.running = true
  }

  onPollingChanged: {
    if (polling) {
      root.refresh()
      poll.restart()
    } else {
      poll.stop()
    }
  }

  Timer {
    id: poll
    interval: 12000
    repeat: true
    running: false
    onTriggered: root.refresh()
  }

  Process {
    id: fetchProc
    command: ["true"]
    stdout: StdioCollector {
      onStreamFinished: {
        root.busy = false
        try {
          const data = JSON.parse(String(text).trim() || "{}")
          if (data.ok === false) {
            root.error = String(data.error || "Could not load host metrics")
            root.ready = true
            root.rev++
            return
          }
          const st = data.storage || {}
          const net = data.network || {}
          const sh = data.shares || {}
          const health = data.health || {}
          root.drives = Array.isArray(st.drives) ? st.drives : []
          root.mounts = Array.isArray(st.mounts) ? st.mounts : []
          root.pools = Array.isArray(st.pools) ? st.pools : []
          root.smartAvailable = !!st.smartAvailable
          root.netPrimary = String(net.primary || "")
          root.netInterfaces = Array.isArray(net.interfaces) ? net.interfaces : []
          root.sharesAvailable = !!sh.available
          root.smbActive = !!sh.smbActive
          root.shares = Array.isArray(sh.items) ? sh.items : []
          root.alerts = Array.isArray(health.alerts) ? health.alerts : []
          root.failedUnits = Number(health.failedUnits) || 0
          root.summary = String(data.summary || "—")
          root.hint = String(data.hint || "")
          const errs = data.errors || []
          root.error = (errs.length && !root.drives.length && !root.mounts.length)
              ? String(errs[0])
              : ""
          root.ready = true
          root.rev++
        } catch (e) {
          root.error = "Could not parse host metrics"
          root.ready = true
          root.rev++
        }
      }
    }
  }
}
