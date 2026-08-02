pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Host VM/container glance — HostHome via proteus-workloads.py.
// Not the full Host workloads app (create/destroy stays Out).
Singleton {
  id: root

  property int watchers: 0
  readonly property bool polling: watchers > 0

  property bool busy: false
  property bool ready: false
  property string error: ""
  property string hint: ""
  property string summary: "—"
  property var domains: []
  property var containers: []
  property string containerEngine: ""
  property bool libvirtAvailable: false
  property bool containersAvailable: false
  property int rev: 0

  readonly property string script: Config.scriptsDir + "/proteus-workloads.py"

  readonly property string summaryLabel: {
    if (!root.ready && root.busy)
      return "Reading workloads…"
    if (root.summary && root.summary !== "—")
      return root.summary
    if (root.error.length)
      return root.error
    return "—"
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
            root.error = String(data.error || "Could not load workloads")
            root.ready = true
            root.rev++
            return
          }
          const lv = data.libvirt || {}
          const ct = data.containers || {}
          root.libvirtAvailable = !!lv.available
          root.containersAvailable = !!ct.available
          root.domains = Array.isArray(lv.domains) ? lv.domains : []
          root.containers = Array.isArray(ct.items) ? ct.items : []
          root.containerEngine = String(ct.engine || "")
          root.summary = String(data.summary || "—")
          root.hint = String(data.hint || "")
          const errs = data.errors || []
          root.error = (errs.length && !root.domains.length && !root.containers.length)
              ? String(errs[0])
              : ""
          root.ready = true
          root.rev++
        } catch (e) {
          root.error = "Could not parse workloads"
          root.ready = true
          root.rev++
        }
      }
    }
  }
}
