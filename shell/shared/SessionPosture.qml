pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Hard session posture switch — Settings About + proteus-posture.
// Distinct from HyprProfile (soft window-rule pointer) and Hardware.postureHint.
Singleton {
  id: root

  // UI / Fact ids: desktop | console | host
  property string activePosture: "desktop"
  property string pendingPosture: ""
  property bool busy: false
  property string error: ""
  property string statusNote: ""
  property bool helperMissing: false
  property string helperPath: ""

  readonly property string factPath: {
    const xdg = Quickshell.env("XDG_CONFIG_HOME")
    const home = Quickshell.env("HOME")
    const base = (xdg && xdg.length) ? xdg : (home + "/.config")
    return base + "/proteus/posture"
  }

  readonly property var postureCatalog: [
    { id: "desktop", label: "Desktop" },
    { id: "console", label: "Console" },
    { id: "host", label: "Host" }
  ]

  readonly property var postureOptions: {
    const out = []
    for (let i = 0; i < root.postureCatalog.length; i++) {
      const c = root.postureCatalog[i]
      out.push({ id: c.id, label: c.label })
    }
    return out
  }

  readonly property string activePostureLabel: root.postureLabel(root.activePosture)

  readonly property string hardHonesty: "Hard session posture — restarts chrome (proteus-posture). Soft Hyprland profile below does not flip posture."

  readonly property bool confirmOpen: root.pendingPosture.length > 0
      && root.pendingPosture !== root.activePosture

  readonly property string helperHint: {
    if (root.helperPath.length)
      return root.helperPath
    return "Needs proteus-posture (PROTEUS_ROOT or /mnt/proteus)"
  }

  function postureLabel(id) {
    const u = String(id || "")
    for (let i = 0; i < root.postureCatalog.length; i++) {
      if (root.postureCatalog[i].id === u)
        return root.postureCatalog[i].label
    }
    return u.length ? u : "—"
  }

  function normalize(raw) {
    let p = String(raw || "").trim().toLowerCase()
    if (p === "couch" || p === "media")
      p = "console"
    if (p === "desktop" || p === "console" || p === "host")
      return p
    return "desktop"
  }

  function applyFactText(raw) {
    root.activePosture = root.normalize(raw)
    if (!root.busy && root.error.indexOf("posture") >= 0)
      root.error = ""
  }

  function refresh() {
    factFile.reload()
    probeHelperProc.running = false
    probeHelperProc.running = true
  }

  function requestSwitch(uiId) {
    const id = root.normalize(uiId)
    if (!id.length || id === root.activePosture) {
      root.pendingPosture = ""
      return
    }
    let known = false
    for (let i = 0; i < root.postureCatalog.length; i++) {
      if (root.postureCatalog[i].id === id) {
        known = true
        break
      }
    }
    if (!known) {
      root.error = "Unknown posture: " + id
      return
    }
    root.error = ""
    root.pendingPosture = id
  }

  function cancelPending() {
    root.pendingPosture = ""
  }

  function confirmSwitch() {
    if (!root.confirmOpen)
      return
    root.set(root.pendingPosture)
  }

  function set(uiId) {
    const id = root.normalize(uiId)
    if (!id.length)
      return
    let known = false
    for (let i = 0; i < root.postureCatalog.length; i++) {
      if (root.postureCatalog[i].id === id) {
        known = true
        break
      }
    }
    if (!known) {
      root.error = "Unknown posture: " + id
      return
    }
    if (id === root.activePosture && !root.busy) {
      root.pendingPosture = ""
      return
    }
    if (!root.helperPath.length) {
      root.helperMissing = true
      root.error = "proteus-posture not found — install overlay or set PROTEUS_ROOT"
      root.statusNote = ""
      return
    }

    root.busy = true
    root.error = ""
    root.statusNote = "Switching to " + root.postureLabel(id) + "…"
    root.pendingPosture = ""
    setProc.command = ["bash", root.helperPath, id]
    setProc.running = false
    setProc.running = true
  }

  Component.onCompleted: root.refresh()

  FileView {
    id: factFile
    path: root.factPath
    watchChanges: true
    onLoaded: root.applyFactText(factFile.text())
    onLoadFailed: {
      if (!root.busy)
        root.activePosture = "desktop"
    }
  }

  Process {
    id: probeHelperProc
    command: [
      "bash",
      "-c",
      "candidates=()\n"
          + "[[ -n \"${PROTEUS_ROOT:-}\" ]] && candidates+=(\"${PROTEUS_ROOT}/vm/guest/proteus-posture\")\n"
          + "candidates+=(\"/mnt/proteus/vm/guest/proteus-posture\"\n"
          + "  \"${HOME}/Projects/Proteus/vm/guest/proteus-posture\")\n"
          + "command -v proteus-posture >/dev/null 2>&1 && candidates+=(\"$(command -v proteus-posture)\")\n"
          + "for p in \"${candidates[@]}\"; do\n"
          + "  [[ -x \"$p\" || -f \"$p\" ]] && echo \"$p\" && exit 0\n"
          + "done\n"
          + "exit 1\n"
    ]
    stdout: StdioCollector {
      id: probeOut
    }
    onExited: (exitCode) => {
      if (exitCode === 0) {
        const p = probeOut.text.trim().split("\n")[0] || ""
        root.helperPath = p
        root.helperMissing = !p.length
        if (p.length && root.error.indexOf("proteus-posture") >= 0)
          root.error = ""
      } else {
        root.helperPath = ""
        root.helperMissing = true
      }
    }
  }

  Process {
    id: setProc
    command: ["true"]
    stderr: StdioCollector {
      id: setErr
    }
    stdout: StdioCollector {
      id: setOut
    }
    onExited: (exitCode) => {
      root.busy = false
      const out = setOut.text.trim()
      const err = setErr.text.trim()
      if (exitCode === 0) {
        root.error = ""
        root.statusNote = "Hard switch started — chrome restarts for the new posture"
        root.refresh()
        return
      }
      const e = err.split("\n")[0]
          || out.split("\n").filter(l => l.length).slice(-1)[0]
          || ""
      root.statusNote = ""
      root.error = e.length ? e : "Could not hard-switch posture"
      root.refresh()
    }
  }
}
