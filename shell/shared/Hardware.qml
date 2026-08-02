pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Wave A hardware probe → capabilities for shell / Settings.
// Spec: docs/proteus/HARDWARE.md · services/proteus-hw-probe/
// Cache is written by the probe (--cache), not by hex-encoding from QML.
Singleton {
  id: root

  property bool ready: false
  property bool probing: false
  property string error: ""
  property string deviceClass: ""
  property string postureHint: "desktop"
  property string chassis: ""
  property var capabilities: ({})
  property var modules: ({})
  property var capabilityList: []
  property var moduleList: []
  property string probedAt: ""
  property string probePath: ""

  readonly property string cachePath: Quickshell.env("HOME") + "/.config/proteus/hw-probe.json"

  readonly property string repoProbe: {
    const shell = Quickshell.shellRoot
    if (shell && shell.length)
      return shell + "/../services/proteus-hw-probe/proteus-hw-probe"
    return "/mnt/proteus/services/proteus-hw-probe/proteus-hw-probe"
  }

  // Thin Wave B: probe may set capabilities.remote / modules input.remote
  // (CEC/IR/lirc or Bluetooth HID remote-like Name=). Soft stub:
  // PROTEUS_REMOTE_PROBE=1 when no hardware (dogfood adapts.input).
  readonly property bool remoteProbeStub: {
    const v = String(Quickshell.env("PROTEUS_REMOTE_PROBE") || "").trim().toLowerCase()
    return v === "1" || v === "true" || v === "yes" || v === "on"
  }

  readonly property bool remoteFromProbe: {
    if (capabilities && capabilities.remote)
      return true
    return !!(modules && modules["input.remote"])
  }

  function has(cap) {
    const c = String(cap || "").trim().toLowerCase()
    if (!c.length)
      return false
    if (capabilities && capabilities[c])
      return true
    // Stub only for remote when probe did not find CEC/IR/BT HID.
    if (c === "remote" && root.remoteProbeStub)
      return true
    return false
  }

  function hasModule(mod) {
    return !!(modules && modules[mod])
  }

  function shellQuote(s) {
    return "'" + String(s).replace(/'/g, "'\\''") + "'"
  }

  function refresh() {
    if (probing)
      return
    error = ""
    probing = true
    probePath = ""
    const q = shellQuote(repoProbe)
    resolveProc.command = [
      "bash",
      "-c",
      "if command -v proteus-hw-probe >/dev/null 2>&1; then command -v proteus-hw-probe; "
          + "elif [ -x " + q + " ] || [ -f " + q + " ]; then echo " + q + "; "
          + "else echo ''; fi"
    ]
    resolveProc.running = false
    resolveProc.running = true
  }

  function applyReport(obj, fromLiveProbe) {
    if (!obj || typeof obj !== "object") {
      error = "Invalid probe JSON"
      ready = false
      if (fromLiveProbe)
        probing = false
      return
    }
    deviceClass = obj.device_class || ""
    postureHint = obj.posture_hint || "desktop"
    chassis = obj.chassis || ""
    capabilities = obj.capabilities || ({})
    modules = obj.modules || ({})
    capabilityList = Object.keys(capabilities).filter(k => capabilities[k]).sort()
    moduleList = Object.keys(modules).filter(k => modules[k]).sort()
    probedAt = obj.probed_at || new Date().toISOString()
    ready = true
    // Cache priming must not clear an in-flight live probe.
    if (fromLiveProbe)
      probing = false
  }

  function loadCacheFallback() {
    // Prefer FileView over bash -lc (login shell adds ~80ms for a tiny JSON read).
    cacheFile.reload()
  }

  // Settings is a separate qs process — don't pay ~3s probe on every open.
  // Shell: cache first for instant chrome, then refresh in the background.
  readonly property bool isSettingsApp: {
    const d = String(Quickshell.shellDir || Quickshell.shellRoot || "")
    return d.indexOf("proteus-settings") >= 0
  }

  Process {
    id: resolveProc
    command: ["true"]
    stdout: StdioCollector {
      onStreamFinished: {
        const p = text.trim().split("\n")[0]
        if (!p || !p.length) {
          root.error = "proteus-hw-probe not found"
          root.probing = false
          root.loadCacheFallback()
          return
        }
        root.probePath = p
        // --cache writes ~/.config/proteus/hw-probe.json from the probe itself
        if (p.endsWith(".py"))
          probeProc.command = ["python3", p, "--compact", "--cache"]
        else
          probeProc.command = [p, "--compact", "--cache"]
        probeProc.running = false
        probeProc.running = true
      }
    }
  }

  Process {
    id: probeProc
    command: ["true"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          root.error = ""
          root.applyReport(JSON.parse(text.trim()), true)
        } catch (e) {
          root.error = "Probe parse failed"
          root.probing = false
          root.loadCacheFallback()
        }
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        if (text && text.trim().length)
          root.error = text.trim().split("\n")[0]
      }
    }
  }

  FileView {
    id: cacheFile
    path: root.cachePath
    watchChanges: false
    onLoaded: {
      const t = String(cacheFile.text()).trim()
      if (!t.length) {
        if (!root.probing && !root.ready)
          root.refresh()
        return
      }
      try {
        if (!root.ready)
          root.applyReport(JSON.parse(t), false)
        if (root.ready && !root.probing)
          root.error = "Using cached probe"
      } catch (e) {
        if (!root.probing && !root.ready)
          root.refresh()
      }
    }
    onLoadFailed: {
      if (!root.probing && !root.ready)
        root.refresh()
    }
  }

  Timer {
    id: deferredRefresh
    interval: 1
    repeat: false
    onTriggered: root.refresh()
  }

  Component.onCompleted: {
    loadCacheFallback()
    if (!isSettingsApp)
      deferredRefresh.start()
  }
}
