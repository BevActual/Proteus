pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Host VM/container probe + graceful mutate for thin Workloads app.
// Create/destroy + start/stop/kill In; one-click app deploys (curated catalog)
// + Samba usershare CRUD In; Settings Virtualization hub · host-chrome headless.
Singleton {
  id: root

  property int watchers: 0
  readonly property bool polling: watchers > 0

  property bool busy: false
  property bool ready: false
  property bool mutating: false
  property string error: ""
  property string mutateError: ""
  property string hint: ""
  property string summary: "—"
  property var domains: []
  property var containers: []
  property string containerEngine: ""
  property bool libvirtAvailable: false
  property bool containersAvailable: false
  property int rev: 0

  // One-click apps (env/apps/host-apps.json catalog + deploy status)
  property var hostApps: []
  property bool hostAppsReady: false
  property bool hostAppsAvailable: false
  property string hostAppsEngine: ""

  // Samba usershares
  property var sharesItems: []
  property bool sharesReady: false
  property bool sharesAvailable: false
  property bool smbActive: false
  property string sharesHint: ""

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
    fetchProc.command = ["python3", root.script, "list"]
    fetchProc.running = false
    fetchProc.running = true
  }

  function refreshApps() {
    appsProc.command = ["python3", root.script, "apps"]
    appsProc.running = false
    appsProc.running = true
  }

  function refreshShares() {
    sharesProc.command = ["python3", root.script, "shares"]
    sharesProc.running = false
    sharesProc.running = true
  }

  function start(kind, name) {
    return root._mutate("start", kind, name, "", "")
  }

  function stop(kind, name) {
    return root._mutate("stop", kind, name, "", "")
  }

  function kill(kind, name) {
    return root._mutate("kill", kind, name, "", "")
  }

  function create(kind, name, diskOrImage) {
    const k = String(kind || "").trim()
    const n = String(name || "").trim()
    const extra = String(diskOrImage || "").trim()
    if (k === "vm")
      return root._mutate("create", k, n, extra, "")
    return root._mutate("create", k, n, "", extra)
  }

  function destroy(kind, name) {
    return root._mutate("destroy", kind, name, "", "")
  }

  function deployApp(appId) {
    const id = String(appId || "").trim()
    if (!id.length || root.mutating)
      return false
    root.mutating = true
    root.mutateError = ""
    mutateProc.command = ["python3", root.script, "deploy", "--app", id]
    mutateProc.running = false
    mutateProc.running = true
    return true
  }

  function shareAdd(name, path) {
    const n = String(name || "").trim()
    const p = String(path || "").trim()
    if (!n.length || !p.length || root.mutating)
      return false
    root.mutating = true
    root.mutateError = ""
    mutateProc.command = ["python3", root.script, "share-add", "--name", n, "--path", p]
    mutateProc.running = false
    mutateProc.running = true
    return true
  }

  function shareRemove(name) {
    const n = String(name || "").trim()
    if (!n.length || root.mutating)
      return false
    root.mutating = true
    root.mutateError = ""
    mutateProc.command = ["python3", root.script, "share-remove", "--name", n]
    mutateProc.running = false
    mutateProc.running = true
    return true
  }

  function _mutate(action, kind, name, disk, image) {
    const k = String(kind || "").trim()
    const n = String(name || "").trim()
    if (!k.length || !n.length || root.mutating)
      return false
    root.mutating = true
    root.mutateError = ""
    const cmd = [
      "python3", root.script, action,
      "--kind", k,
      "--name", n
    ]
    const d = String(disk || "").trim()
    const img = String(image || "").trim()
    if (d.length) {
      cmd.push("--disk")
      cmd.push(d)
    }
    if (img.length) {
      cmd.push("--image")
      cmd.push(img)
    }
    mutateProc.command = cmd
    mutateProc.running = false
    mutateProc.running = true
    return true
  }

  function isVmRunning(domain) {
    if (!domain)
      return false
    return String(domain.state || "").toLowerCase().indexOf("run") >= 0
  }

  function isContainerRunning(item) {
    if (!item)
      return false
    const s = String(item.status || "").toLowerCase()
    return s.indexOf("up") === 0 || s.indexOf("running") >= 0
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
    onTriggered: {
      if (!root.mutating)
        root.refresh()
    }
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

  Process {
    id: mutateProc
    command: ["true"]
    stdout: StdioCollector {
      onStreamFinished: {
        root.mutating = false
        try {
          const data = JSON.parse(String(text).trim() || "{}")
          if (data.ok === false) {
            root.mutateError = String(data.error || "Action failed")
            root.rev++
            return
          }
          root.mutateError = ""
          root.refresh()
          root.refreshApps()
          root.refreshShares()
        } catch (e) {
          root.mutateError = "Could not parse action result"
          root.rev++
        }
      }
    }
    onExited: (code) => {
      if (root.mutating && code !== 0) {
        root.mutating = false
        if (!root.mutateError.length)
          root.mutateError = "Action failed"
        root.rev++
      }
    }
  }

  Process {
    id: appsProc
    command: ["true"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const data = JSON.parse(String(text).trim() || "{}")
          if (data.ok === false) {
            root.hostAppsReady = true
            root.rev++
            return
          }
          root.hostApps = Array.isArray(data.apps) ? data.apps : []
          root.hostAppsAvailable = !!data.available
          root.hostAppsEngine = String(data.engine || "")
          root.hostAppsReady = true
          root.rev++
        } catch (e) {
          root.hostAppsReady = true
          root.rev++
        }
      }
    }
  }

  Process {
    id: sharesProc
    command: ["true"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const data = JSON.parse(String(text).trim() || "{}")
          if (data.ok === false) {
            root.sharesReady = true
            root.rev++
            return
          }
          root.sharesItems = Array.isArray(data.items) ? data.items : []
          root.sharesAvailable = !!data.available
          root.smbActive = !!data.smbActive
          root.sharesHint = String(data.hint || "")
          root.sharesReady = true
          root.rev++
        } catch (e) {
          root.sharesReady = true
          root.rev++
        }
      }
    }
  }
}
