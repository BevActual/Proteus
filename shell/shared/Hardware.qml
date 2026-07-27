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

  function has(cap) {
    return !!(capabilities && capabilities[cap])
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

  function applyReport(obj) {
    if (!obj || typeof obj !== "object") {
      error = "Invalid probe JSON"
      ready = false
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
    probing = false
  }

  function loadCacheFallback() {
    cacheRead.running = false
    cacheRead.running = true
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
          root.applyReport(JSON.parse(text.trim()))
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

  Process {
    id: cacheRead
    command: [
      "bash",
      "-lc",
      "test -f \"$HOME/.config/proteus/hw-probe.json\" && cat \"$HOME/.config/proteus/hw-probe.json\" || true"
    ]
    stdout: StdioCollector {
      onStreamFinished: {
        const t = text.trim()
        if (!t.length || root.ready)
          return
        try {
          root.applyReport(JSON.parse(t))
          if (root.ready)
            root.error = "Using cached probe"
        } catch (e) {}
      }
    }
  }

  Component.onCompleted: refresh()
}
