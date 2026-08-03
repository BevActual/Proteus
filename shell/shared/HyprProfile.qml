pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Soft Hyprland posture profile select — Settings About + set-hypr-profile.sh.
// Soft reload only; hard posture switch is proteus-posture (POSTURES.md).
Singleton {
  id: root

  // UI ids: desktop | console | host | home
  property string activeProfile: ""
  property bool busy: false
  property string error: ""
  property string statusNote: ""
  property bool helperMissing: false
  property string helperPath: ""
  property bool lastReloadOk: false

  readonly property string pointerPath: Quickshell.env("HOME") + "/.config/hypr/proteus-profile.conf"
  readonly property string profilesDir: Quickshell.env("HOME") + "/.config/hypr/profiles"

  readonly property var profileCatalog: [
    { id: "desktop", label: "Desktop", file: "desktop" },
    { id: "console", label: "Console", file: "console" },
    { id: "host", label: "Host", file: "host" },
    { id: "home", label: "Home (parked)", file: "home" }
  ]

  readonly property var profileOptions: {
    const out = []
    for (let i = 0; i < root.profileCatalog.length; i++) {
      const c = root.profileCatalog[i]
      out.push({ id: c.id, label: c.label })
    }
    return out
  }

  readonly property string activeProfileLabel: root.profileLabel(root.activeProfile)

  readonly property string softHonesty: "Soft window rules only — does not switch Desktop · Console · Host. Use Session posture above."

  readonly property string activeDetail: {
    if (!root.activeProfile.length)
      return ""
    if (root.activeProfile === "console")
      return "Console profile: fullscreen apps. Hard flip: proteus-posture console."
    if (root.activeProfile === "host")
      return "Host profile: lean ops rules. Hard flip: proteus-posture host."
    if (root.activeProfile === "home")
      return "Home is parked — stub profile only."
    return ""
  }

  readonly property string helperHint: {
    if (root.helperPath.length)
      return root.helperPath
    return "Needs set-hypr-profile.sh (PROTEUS_ROOT or /mnt/proteus)"
  }

  function profileLabel(uiId) {
    const u = String(uiId || "")
    for (let i = 0; i < root.profileCatalog.length; i++) {
      if (root.profileCatalog[i].id === u)
        return root.profileCatalog[i].label
    }
    return u.length ? u : "—"
  }

  function uiIdFromFile(fileStem) {
    const f = String(fileStem || "")
    // Legacy media.conf → console
    if (f === "media")
      return "console"
    for (let i = 0; i < root.profileCatalog.length; i++) {
      if (root.profileCatalog[i].file === f)
        return root.profileCatalog[i].id
    }
    return f
  }

  function fileFromUiId(uiId) {
    const u = String(uiId || "")
    for (let i = 0; i < root.profileCatalog.length; i++) {
      if (root.profileCatalog[i].id === u)
        return root.profileCatalog[i].file
    }
    if (u === "console")
      return "console"
    return u
  }

  function scriptArgFromUiId(uiId) {
    // set-hypr-profile.sh accepts console|media|desktop|host|home
    const u = String(uiId || "")
    if (u === "console")
      return "console"
    return root.fileFromUiId(u)
  }

  function parsePointerText(raw) {
    const text = String(raw || "")
    const re = /profiles\/([A-Za-z0-9_-]+)\.conf/
    const m = text.match(re)
    if (!m)
      return ""
    return root.uiIdFromFile(m[1])
  }

  function applyPointerText(raw) {
    const id = root.parsePointerText(raw)
    root.activeProfile = id
    if (id.length && !root.busy) {
      if (root.statusNote.indexOf("pointer") >= 0)
        root.statusNote = ""
      if (root.error.indexOf("pointer") >= 0)
        root.error = ""
    }
  }

  function refresh() {
    pointerFile.reload()
    probeHelperProc.running = false
    probeHelperProc.running = true
  }

  function openInstallHelper() {
    Quickshell.execDetached({
      command: [
        "bash",
        "-lc",
        "exec proteus-terminal -e bash -lc "
            + JSON.stringify(
              "sudo bash /mnt/proteus/install/machine/install-desktop-conf.sh"
                  + "; echo; read -r -p \"Press Enter to close…\" _")
      ]
    })
  }

  function set(uiId) {
    const id = String(uiId || "")
    if (!id.length)
      return
    let known = false
    for (let i = 0; i < root.profileCatalog.length; i++) {
      if (root.profileCatalog[i].id === id) {
        known = true
        break
      }
    }
    if (!known) {
      root.error = "Unknown profile: " + id
      return
    }
    if (id === root.activeProfile && !root.busy)
      return
    if (!root.helperPath.length) {
      root.helperMissing = true
      root.error = "set-hypr-profile.sh not found — install desktop conf or set PROTEUS_ROOT"
      root.statusNote = ""
      return
    }

    root.busy = true
    root.error = ""
    root.statusNote = ""
    root.lastReloadOk = false
    const arg = root.scriptArgFromUiId(id)
    setProc.command = ["bash", root.helperPath, arg]
    setProc.running = false
    setProc.running = true
  }

  Component.onCompleted: root.refresh()

  FileView {
    id: pointerFile
    path: root.pointerPath
    watchChanges: true
    onLoaded: root.applyPointerText(pointerFile.text())
    onLoadFailed: {
      if (!root.busy) {
        root.activeProfile = ""
        root.statusNote = "No active profile pointer yet — pick a profile to create one"
        if (root.error.indexOf("pointer") >= 0)
          root.error = ""
      }
    }
  }

  Process {
    id: probeHelperProc
    command: [
      "bash",
      "-c",
      "candidates=()\n"
          + "[[ -n \"${PROTEUS_ROOT:-}\" ]] && candidates+=(\"${PROTEUS_ROOT}/shell/scripts/set-hypr-profile.sh\")\n"
          + "candidates+=(\"/mnt/proteus/shell/scripts/set-hypr-profile.sh\"\n"
          + "  \"${HOME}/Projects/Proteus/shell/scripts/set-hypr-profile.sh\")\n"
          + "for p in \"${candidates[@]}\"; do\n"
          + "  [[ -f \"$p\" ]] && echo \"$p\" && exit 0\n"
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
        if (p.length && root.error.indexOf("set-hypr-profile") >= 0)
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
        root.lastReloadOk = out.indexOf("hyprctl reload OK") >= 0
        if (root.lastReloadOk)
          root.statusNote = "Pointer updated · hyprctl reload OK (soft)"
        else if (out.indexOf("pointer updated") >= 0 || out.indexOf("Active profile") >= 0)
          root.statusNote = "Pointer updated on disk — reload when Hyprland is running"
        else
          root.statusNote = "Profile applied (soft)"
        root.refresh()
        return
      }
      const e = err.split("\n")[0]
          || out.split("\n").filter(l => l.length).slice(-1)[0]
          || ""
      root.statusNote = ""
      root.lastReloadOk = false
      root.error = e.length ? e : "Could not change Hyprland posture profile"
      root.refresh()
    }
  }
}
