pragma Singleton

import Quickshell
import Quickshell.Hyprland
import QtQuick

Singleton {
  // Fixed chrome pins (not removable)
  readonly property var launcherPin: {
    "id": "launcher",
    "label": "Spotlight",
    "icon": "proteus-launcher",
    "special": "launcher"
  }
  readonly property var settingsPin: {
    "id": "settings",
    "label": "Settings",
    "icon": "proteus-settings",
    "special": "settings",
    // FloatingWindow WM class is "quickshell" (see proteus-settings.desktop).
    "match": "quickshell",
    "desktopId": "proteus-settings",
    "command": ["proteus-settings"]
  }

  // Default middle pins when Config.dockPins is unset
  readonly property var defaultPinIds: [
    "com.mitchellh.ghostty",
    "org.gnome.Nautilus",
    "chromium",
    "org.xfce.mousepad"
  ]

  readonly property string brandMarkUrl: {
    const root = Quickshell.env("PROTEUS_ROOT")
    const base = root && root.length ? root : "/mnt/proteus"
    return "file://" + base + "/brand/proteus-mark.png"
  }

  function brandFileUrl(name) {
    const root = Quickshell.env("PROTEUS_ROOT")
    const base = root && root.length ? root : "/mnt/proteus"
    if (name === "proteus-settings")
      return "file://" + base + "/brand/proteus-settings.svg"
    if (name === "proteus-launcher")
      return "file://" + base + "/brand/proteus-launcher.svg"
    return "file://" + base + "/brand/proteus-mark.png"
  }

  function normalizeDesktopId(id) {
    return String(id || "").trim().replace(/\.desktop$/i, "")
  }

  // Shell chrome / Settings QS — never a transient dock icon.
  function isShellChromeClass(cls) {
    const c = String(cls || "").trim().toLowerCase()
    if (!c.length)
      return false
    if (c === "quickshell" || c === "qs")
      return true
    if (c.indexOf("org.quickshell") === 0)
      return true
    if (c.indexOf("proteus-qs") === 0)
      return true
    return false
  }

  function pinIdList() {
    const raw = String(Config.dockPins || "").trim()
    if (!raw.length)
      return defaultPinIds.slice()
    if (raw === "-")
      return []
    const out = []
    const seen = {}
    const parts = raw.split(",")
    for (let i = 0; i < parts.length; i++) {
      const id = normalizeDesktopId(parts[i])
      if (!id.length || seen[id])
        continue
      // Never persist chrome ids in the middle list
      if (id === "launcher" || id === "settings" || id === "proteus-launcher" || id === "proteus-settings")
        continue
      seen[id] = true
      out.push(id)
    }
    return out
  }

  function setPinIds(ids) {
    const clean = []
    const seen = {}
    for (let i = 0; i < ids.length; i++) {
      const id = normalizeDesktopId(ids[i])
      if (!id.length || seen[id])
        continue
      if (id === "launcher" || id === "settings" || id === "proteus-launcher" || id === "proteus-settings")
        continue
      seen[id] = true
      clean.push(id)
    }
    Config.dockPins = clean.length ? clean.join(",") : "-"
    Config.flushSettings()
  }

  function entryFromDesktopId(desktopId) {
    const id = normalizeDesktopId(desktopId)
    if (!id.length)
      return null
    const desk = DesktopEntries.heuristicLookup(id)
    const short = id.split(".").pop().toLowerCase()
    const label = desk && desk.name ? String(desk.name) : short
    const icon = desk && desk.icon ? String(desk.icon) : short
    const entry = {
      id: id,
      label: label,
      icon: icon,
      desktopId: id,
      match: short
    }
    // Ghostty → proteus-terminal wrapper (VM GL)
    if (id === "com.mitchellh.ghostty" || short === "ghostty") {
      entry.match = "ghostty"
      entry.command = ["proteus-terminal"]
    }
    return entry
  }

  function entryFromDesktopEntry(desk) {
    if (!desk)
      return null
    const id = normalizeDesktopId(desk.id || "")
    if (!id.length)
      return null
    return entryFromDesktopId(id)
  }

  readonly property var pinned: {
    const _pins = Config.dockPins
    const _caps = Hardware.capabilityList
    const out = [launcherPin]
    const ids = pinIdList()
    for (let i = 0; i < ids.length; i++) {
      const e = entryFromDesktopId(ids[i])
      if (e)
        out.push(e)
    }
    out.push(settingsPin)
    return out
  }

  readonly property var visiblePinned: {
    const _caps = Hardware.capabilityList
    const _pins = Config.dockPins
    const list = pinned
    const out = []
    for (let i = 0; i < list.length; i++) {
      if (EnvGate.dockEntryAvailable(list[i]))
        out.push(list[i])
    }
    return out
  }

  // macOS-like: pinned apps + running unpinned (transient) between Spotlight and Settings
  readonly property var dockItems: {
    const _caps = Hardware.capabilityList
    const _pins = Config.dockPins
    const _tops = Hyprland.toplevels.values
    const _ov = Config.iconOverrides

    const out = []
    const seen = {}

    function pushEntry(e) {
      if (!e || !EnvGate.dockEntryAvailable(e))
        return
      const key = normalizeDesktopId(e.desktopId || e.id || e.match || "")
      const sk = key.length ? key : String(e.special || "")
      if (!sk.length || seen[sk])
        return
      seen[sk] = true
      out.push(e)
    }

    pushEntry(launcherPin)

    const ids = pinIdList()
    for (let i = 0; i < ids.length; i++)
      pushEntry(entryFromDesktopId(ids[i]))

    // Running apps not already pinned (after pinned, before Settings)
    const tops = Hyprland.toplevels.values
    for (let i = 0; i < tops.length; i++) {
      const cls = classOf(tops[i])
      if (!cls.length || isShellChromeClass(cls))
        continue
      const e = entryFromWindowClass(cls)
      if (!e)
        continue
      const id = normalizeDesktopId(e.desktopId || e.id)
      if (!id.length || isPinned(id) || seen[id])
        continue
      // Skip Settings chrome if somehow matched
      if (id === "proteus-settings" || id === "settings" || isShellChromeClass(id))
        continue
      e.transient = true
      pushEntry(e)
    }

    pushEntry(settingsPin)
    return out
  }

  function entryFromWindowClass(cls) {
    const c = String(cls || "").trim().toLowerCase()
    if (!c.length)
      return null
    // Settings FloatingWindow + any chrome QS share class "quickshell".
    // Settings is a fixed pin; never invent a "Quickshell" transient.
    if (isShellChromeClass(c) || c.indexOf("proteus-settings") >= 0 || c === "settings")
      return null

    // Known aliases
    if (c.indexOf("ghostty") >= 0)
      return entryFromDesktopId("com.mitchellh.ghostty")

    const apps = DesktopEntries.applications.values
    for (let i = 0; i < apps.length; i++) {
      const a = apps[i]
      if (!a)
        continue
      const id = normalizeDesktopId(a.id || "")
      if (!id.length)
        continue
      const idLower = id.toLowerCase()
      const short = idLower.split(".").pop()
      let wm = ""
      try {
        if (a.startupWmClass)
          wm = String(a.startupWmClass).toLowerCase()
      } catch (err) {
      }
      if (wm === c || idLower === c || short === c || idLower.endsWith("." + c)) {
        // Desktop entry for Settings (StartupWMClass=quickshell) — not transient.
        if (idLower === "proteus-settings" || short === "settings" || isShellChromeClass(wm))
          return null
        const e = entryFromDesktopId(id)
        if (e) {
          e.match = short.length ? short : c
          return e
        }
      }
    }

    // Synthetic transient — still focusable via class match
    const short = c.split(".").pop()
    return {
      id: c,
      label: short.charAt(0).toUpperCase() + short.slice(1),
      icon: short,
      desktopId: c,
      match: short,
      transient: true
    }
  }

  function isPinned(desktopId) {
    const id = normalizeDesktopId(desktopId)
    if (!id.length)
      return false
    if (id === "proteus-settings" || id === "settings")
      return true
    if (id === "proteus-launcher" || id === "launcher")
      return true
    return pinIdList().indexOf(id) >= 0
  }

  function isTransient(entry) {
    return !!(entry && entry.transient)
  }

  function canUnpin(entry) {
    if (!entry)
      return false
    if (entry.special === "launcher" || entry.special === "settings")
      return false
    if (isTransient(entry))
      return false
    return true
  }

  function canKeepInDock(entry) {
    if (!entry || entry.special === "launcher" || entry.special === "settings")
      return false
    const id = normalizeDesktopId(entry.desktopId || entry.id)
    if (!id.length)
      return false
    return !isPinned(id)
  }

  function pinDesktopId(desktopId) {
    const id = normalizeDesktopId(desktopId)
    if (!id.length || isPinned(id))
      return false
    if (!entryFromDesktopId(id))
      return false
    const ids = pinIdList()
    ids.push(id)
    setPinIds(ids)
    return true
  }

  function pinDesktopEntry(desk) {
    if (!desk)
      return false
    return pinDesktopId(desk.id)
  }

  function unpinDesktopId(desktopId) {
    const id = normalizeDesktopId(desktopId)
    if (!id.length)
      return false
    if (id === "proteus-settings" || id === "settings" || id === "proteus-launcher" || id === "launcher")
      return false
    const ids = pinIdList().filter(x => x !== id)
    setPinIds(ids)
    return true
  }

  function unpinEntry(entry) {
    if (!canUnpin(entry))
      return false
    return unpinDesktopId(entry.desktopId || entry.id)
  }

  // Middle pins only (Spotlight + Settings stay fixed). toPinIndex is 0..pins.length.
  function canReorder(entry) {
    if (!entry || entry.special === "launcher" || entry.special === "settings")
      return false
    if (isTransient(entry))
      return false
    const id = normalizeDesktopId(entry.desktopId || entry.id)
    return id.length && pinIdList().indexOf(id) >= 0
  }

  function reorderPinnedDesktopId(desktopId, toPinIndex) {
    const id = normalizeDesktopId(desktopId)
    if (!id.length)
      return false
    const ids = pinIdList()
    const from = ids.indexOf(id)
    if (from < 0)
      return false
    ids.splice(from, 1)
    const to = Math.max(0, Math.min(ids.length, Math.round(Number(toPinIndex))))
    ids.splice(to, 0, id)
    setPinIds(ids)
    return true
  }

  function iconFor(entry) {
    if (!entry)
      return "application-x-executable"
    if (entry.special === "launcher")
      return "proteus-launcher"
    if (entry.special === "settings")
      return "proteus-settings"
    const overrideId = entry.desktopId || entry.id
    if (overrideId) {
      const ov = Config.iconOverrideFor(overrideId)
      if (ov.length)
        return ov
    }
    if (entry.desktopId) {
      const desk = DesktopEntries.heuristicLookup(entry.desktopId)
      if (desk && desk.icon && String(desk.icon).length)
        return String(desk.icon)
    }
    if (entry.icon && String(entry.icon).length)
      return String(entry.icon)
    return "application-x-executable"
  }

  function iconSource(entry) {
    // Track overrides for QML binding invalidation
    const _ov = Config.iconOverrides
    const name = iconFor(entry)
    if (name.indexOf("file:") === 0)
      return name
    if (name.indexOf("/") === 0)
      return "file://" + name
    const path = Quickshell.iconPath(name, true)
    if (path && path.length)
      return path
    if (name === "proteus" || name === "proteus-settings" || name === "proteus-launcher")
      return brandFileUrl(name)
    const fb = Quickshell.iconPath("application-x-executable", true)
    return (fb && fb.length) ? fb : brandMarkUrl
  }

  function terminalCommand(extraArgs) {
    const root = Quickshell.env("PROTEUS_ROOT")
    const base = root && root.length ? root : "/mnt/proteus"
    const wrapper = base + "/shell/scripts/proteus-terminal"
    let suffix = ""
    if (extraArgs && extraArgs.length) {
      for (let i = 0; i < extraArgs.length; i++)
        suffix += " " + shellQuote(extraArgs[i])
    }
    return [
      "bash",
      "-lc",
      "W=$(command -v proteus-terminal 2>/dev/null || true); "
          + "exec \"${W:-" + wrapper + "}\"" + suffix
    ]
  }

  function shellQuote(s) {
    return "'" + String(s).replace(/'/g, "'\\''") + "'"
  }

  function classOf(toplevel) {
    if (!toplevel)
      return ""
    const ipc = toplevel.lastIpcObject
    if (ipc) {
      if (ipc.class)
        return String(ipc.class)
      if (ipc.initialClass)
        return String(ipc.initialClass)
    }
    if (toplevel.wayland && toplevel.wayland.appId)
      return String(toplevel.wayland.appId)
    return ""
  }

  function isRunning(entry) {
    if (!entry || !entry.match)
      return false
    const needle = entry.match.toLowerCase()
    const tops = Hyprland.toplevels.values
    for (let i = 0; i < tops.length; i++) {
      if (classOf(tops[i]).toLowerCase().indexOf(needle) !== -1)
        return true
    }
    return false
  }

  function isActive(entry) {
    if (!entry || !entry.match)
      return false
    const t = Hyprland.activeToplevel
    if (!t)
      return false
    return classOf(t).toLowerCase().indexOf(entry.match.toLowerCase()) !== -1
  }

  function focusOrLaunch(entry) {
    if (!entry)
      return
    if (entry.special === "launcher") {
      ShellState.toggleLauncher()
      return
    }
    if (entry.special === "settings") {
      ShellState.openSettings()
      return
    }

    const needle = (entry.match || "").toLowerCase()
    if (needle.length) {
      const tops = Hyprland.toplevels.values
      for (let i = 0; i < tops.length; i++) {
        const t = tops[i]
        if (classOf(t).toLowerCase().indexOf(needle) !== -1) {
          let addr = t.address || ""
          if (addr.length) {
            if (addr.indexOf("0x") !== 0)
              addr = "0x" + addr
            Hyprland.dispatch("focuswindow address:" + addr)
            return
          }
          if (t.workspace)
            t.workspace.activate()
          return
        }
      }
    }

    const desk = entry.desktopId ? DesktopEntries.heuristicLookup(entry.desktopId) : null
    if (entry.id === "terminal" || entry.match === "ghostty" || entry.desktopId === "com.mitchellh.ghostty") {
      Quickshell.execDetached({
        command: terminalCommand([])
      })
      return
    }
    if (desk) {
      desk.execute()
      return
    }
    if (entry.command && entry.command.length) {
      Quickshell.execDetached({
        command: entry.command
      })
    }
  }

  Connections {
    target: Hyprland

    function onRawEvent(event) {
      switch (event.name) {
      case "openwindow":
      case "closewindow":
      case "movewindow":
      case "activewindow":
      case "activewindowv2":
      case "windowtitle":
      case "windowtitlev2":
      case "fullscreen":
        Hyprland.refreshToplevels()
        break
      }
    }
  }

  Timer {
    interval: 5000
    running: !ShellState.sessionLocked
    repeat: true
    onTriggered: Hyprland.refreshToplevels()
  }
}
