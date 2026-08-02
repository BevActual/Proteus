pragma Singleton

import Quickshell
import Quickshell.Hyprland
import QtQuick

Singleton {
  // Fixed chrome pins (not removable)
  readonly property var launcherPin: {
    "id": "launcher",
    "label": "Beacon",
    "icon": "proteus-launcher",
    "special": "launcher"
  }
  readonly property var settingsPin: {
    "id": "settings",
    "label": "Settings",
    "icon": "proteus-settings",
    "special": "settings",
    // FloatingWindow class is shared with shell chrome ("quickshell") — match by
    // window title instead so the pin is not always "running".
    "match": "",
    "titleMatch": "Proteus Settings",
    "desktopId": "proteus-settings",
    "command": ["proteus-settings"]
  }

  // Dock-minimize parking workspace (Hyprland has no classic minimize).
  readonly property string minimizeWorkspace: "special:minimized"

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

  // macOS-like: pinned apps + running unpinned (transient) between Beacon and Settings
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

    // Running apps not already pinned (after pinned, before Settings) —
    // divided from the pins by a hairline (macOS: temporary vs kept).
    const pinnedCount = out.length
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
    if (out.length > pinnedCount) {
      out.splice(pinnedCount, 0, {
        id: "separator",
        label: "",
        separator: true
      })
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

  function isSeparator(entry) {
    return !!(entry && entry.separator)
  }

  function canUnpin(entry) {
    if (!entry || entry.separator)
      return false
    if (entry.special === "launcher" || entry.special === "settings")
      return false
    if (isTransient(entry))
      return false
    return true
  }

  function canKeepInDock(entry) {
    if (!entry || entry.separator || entry.special === "launcher" || entry.special === "settings")
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

  // Middle pins only (Beacon + Settings stay fixed). toPinIndex is 0..pins.length.
  function canReorder(entry) {
    if (!entry || entry.separator || entry.special === "launcher" || entry.special === "settings")
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

  function titleOf(toplevel) {
    if (!toplevel)
      return ""
    if (toplevel.wayland && toplevel.wayland.title)
      return String(toplevel.wayland.title)
    const ipc = toplevel.lastIpcObject
    if (ipc && ipc.title)
      return String(ipc.title)
    if (toplevel.title)
      return String(toplevel.title)
    return ""
  }

  function titleMatchOf(entry) {
    if (!entry)
      return ""
    return String(entry.titleMatch || "").trim()
  }

  function workspaceNameOf(toplevel) {
    if (!toplevel)
      return ""
    const ipc = toplevel.lastIpcObject
    if (ipc && ipc.workspace) {
      if (ipc.workspace.name)
        return String(ipc.workspace.name)
    }
    if (toplevel.workspace && toplevel.workspace.name)
      return String(toplevel.workspace.name)
    return ""
  }

  function isRunning(entry) {
    if (!entry)
      return false
    if (titleMatchOf(entry).length || entry.special === "settings")
      return windowsFor(entry).length > 0
    if (!entry.match)
      return false
    const needle = entry.match.toLowerCase()
    const tops = Hyprland.toplevels.values
    for (let i = 0; i < tops.length; i++) {
      if (classOf(tops[i]).toLowerCase().indexOf(needle) !== -1)
        return true
    }
    return false
  }

  // All toplevels of an entry (class match, or titleMatch for Settings).
  function windowsFor(entry) {
    if (!entry)
      return []
    const titleNeedle = titleMatchOf(entry)
        || (entry.special === "settings" ? "Proteus Settings" : "")
    const wins = []
    const tops = Hyprland.toplevels.values
    if (titleNeedle.length) {
      for (let i = 0; i < tops.length; i++) {
        if (titleOf(tops[i]) === titleNeedle)
          wins.push(tops[i])
      }
      return wins
    }
    if (!entry.match)
      return []
    const needle = entry.match.toLowerCase()
    for (let i = 0; i < tops.length; i++) {
      if (classOf(tops[i]).toLowerCase().indexOf(needle) !== -1)
        wins.push(tops[i])
    }
    return wins
  }

  function windowAddress(toplevel) {
    let addr = (toplevel && toplevel.address) ? String(toplevel.address) : ""
    if (addr.length && addr.indexOf("0x") !== 0)
      addr = "0x" + addr
    return addr
  }

  function minimizeToplevel(toplevel) {
    const addr = windowAddress(toplevel)
    if (!addr.length)
      return false
    Hyprland.dispatch("movetoworkspacesilent " + minimizeWorkspace + ",address:" + addr)
    return true
  }

  function isMinimizedToplevel(toplevel) {
    const ws = workspaceNameOf(toplevel)
    return ws === minimizeWorkspace || ws.indexOf("special:minimized") === 0
  }

  function closeToplevel(toplevel) {
    const addr = windowAddress(toplevel)
    if (addr.length)
      Hyprland.dispatch("closewindow address:" + addr)
  }

  // —— Active-window controls (menu bar traffic lights + tiling toggle) ——

  function closeActiveWindow() {
    closeToplevel(Hyprland.activeToplevel)
  }

  function minimizeActiveWindow() {
    minimizeToplevel(Hyprland.activeToplevel)
  }

  // Maximize-with-bar toggle (Hyprland "fullscreen 1" acts on the active window).
  function maximizeActiveWindow() {
    if (Hyprland.activeToplevel)
      Hyprland.dispatch("fullscreen 1")
  }

  readonly property bool activeFloating: {
    const t = Hyprland.activeToplevel
    if (!t)
      return false
    const ipc = t.lastIpcObject
    return !!(ipc && ipc.floating)
  }

  function toggleFloatActiveWindow() {
    const t = Hyprland.activeToplevel
    if (!t)
      return
    const addr = windowAddress(t)
    Hyprland.dispatch(addr.length ? ("togglefloating address:" + addr) : "togglefloating")
    floatRefresh.restart()
  }

  Timer {
    id: floatRefresh
    interval: 140
    onTriggered: Hyprland.refreshToplevels()
  }

  function focusToplevel(toplevel) {
    const addr = windowAddress(toplevel)
    if (addr.length) {
      if (isMinimizedToplevel(toplevel))
        Hyprland.dispatch("movetoworkspace +0,address:" + addr)
      Hyprland.dispatch("focuswindow address:" + addr)
      return true
    }
    if (toplevel && toplevel.workspace) {
      toplevel.workspace.activate()
      return true
    }
    return false
  }

  function focusWindowAddress(addr) {
    let a = String(addr || "").trim()
    if (!a.length)
      return false
    if (a.indexOf("0x") !== 0)
      a = "0x" + a
    // Restore if parked on special:minimized.
    const tops = Hyprland.toplevels.values
    for (let i = 0; i < tops.length; i++) {
      if (windowAddress(tops[i]) === a) {
        return focusToplevel(tops[i])
      }
    }
    Hyprland.dispatch("focuswindow address:" + a)
    return true
  }

  // Beacon / Search — running windows (skips Quickshell chrome).
  function listSearchableWindows() {
    const tops = Hyprland.toplevels.values
    const out = []
    const seen = {}
    for (let i = 0; i < tops.length; i++) {
      const t = tops[i]
      if (!t)
        continue
      const cls = classOf(t)
      const title = titleOf(t)
      const clsL = cls.toLowerCase()
      if (clsL === "quickshell" || clsL.indexOf("quickshell") >= 0)
        continue
      if (!title.length && !cls.length)
        continue
      const addr = windowAddress(t)
      if (!addr.length || seen[addr])
        continue
      seen[addr] = true
      const ws = workspaceNameOf(t)
      const minimized = isMinimizedToplevel(t)
      let subtitle = cls.length ? cls : "Window"
      if (ws.length)
        subtitle += " · " + (minimized ? "Hidden" : ws)
      else if (minimized)
        subtitle += " · Hidden"
      // Best-effort desktop icon via class / title match
      let icon = "preferences-system-windows"
      const entry = entryFromWindowClass(cls)
      if (entry)
        icon = EnvGate.resolveAppIcon(entry)
      out.push({
        address: addr,
        title: title.length ? title : cls,
        className: cls,
        subtitle: subtitle,
        icon: icon,
        minimized: minimized
      })
    }
    return out
  }

  // Quit = close every window of the app (Hyprland closewindow; apps with
  // unsaved state get their own prompt). Not exposed for the Beacon pin.
  function canQuit(entry) {
    if (!entry || entry.separator || entry.special === "launcher")
      return false
    return windowsFor(entry).length > 0
  }

  function quitEntry(entry) {
    const wins = windowsFor(entry)
    for (let i = 0; i < wins.length; i++) {
      const addr = windowAddress(wins[i])
      if (addr.length)
        Hyprland.dispatch("closewindow address:" + addr)
    }
  }

  function isActive(entry) {
    if (!entry)
      return false
    const t = Hyprland.activeToplevel
    if (!t)
      return false
    const titleNeedle = titleMatchOf(entry)
        || (entry.special === "settings" ? "Proteus Settings" : "")
    if (titleNeedle.length)
      return titleOf(t) === titleNeedle
    if (!entry.match)
      return false
    return classOf(t).toLowerCase().indexOf(entry.match.toLowerCase()) !== -1
  }

  function focusOrLaunch(entry) {
    if (!entry || entry.separator)
      return
    if (entry.special === "launcher") {
      ShellState.toggleLauncher()
      return
    }
    if (entry.special === "settings") {
      const settingsWins = windowsFor(entry)
      if (settingsWins.length) {
        // Frontmost → dock-minimize; otherwise restore / raise (never spawn).
        if (isActive(entry)) {
          minimizeToplevel(settingsWins[0])
          return
        }
        if (focusToplevel(settingsWins[0]))
          return
        ShellState.openSettings()
        return
      }
      ShellState.openSettings()
      return
    }

    const wins = windowsFor(entry)
    if (wins.length) {
      // Already frontmost with several windows → cycle to the next (macOS-ish).
      if (wins.length > 1 && isActive(entry)) {
        const activeAddr = windowAddress(Hyprland.activeToplevel)
        let at = -1
        for (let i = 0; i < wins.length; i++) {
          if (windowAddress(wins[i]) === activeAddr) {
            at = i
            break
          }
        }
        if (focusToplevel(wins[(at + 1) % wins.length]))
          return
      }
      // Single focused window → dock-minimize; click again restores (Windows-taskbar
      // semantics; Hyprland minimize = park on special:minimized).
      if (wins.length === 1 && isActive(entry)) {
        minimizeToplevel(wins[0])
        return
      }
      // Prefer a visible window; otherwise restore a parked one.
      let target = wins[0]
      for (let i = 0; i < wins.length; i++) {
        if (!isMinimizedToplevel(wins[i])) {
          target = wins[i]
          break
        }
      }
      if (focusToplevel(target))
        return
    }

    const desk = entry.desktopId ? DesktopEntries.heuristicLookup(entry.desktopId) : null
    if (entry.id === "terminal" || entry.match === "ghostty" || entry.desktopId === "com.mitchellh.ghostty") {
      markLaunching(entry)
      Quickshell.execDetached({
        command: terminalCommand([])
      })
      return
    }
    if (desk) {
      markLaunching(entry)
      desk.execute()
      return
    }
    if (entry.command && entry.command.length) {
      markLaunching(entry)
      Quickshell.execDetached({
        command: entry.command
      })
    }
  }

  // —— Launch feedback (dock bounce) ——
  // Marked on spawn; cleared when a window appears or after a timeout.
  property var launchingMap: ({})
  property int launchingRev: 0

  function isLaunching(entry) {
    const _r = launchingRev
    if (!entry)
      return false
    const id = normalizeDesktopId(entry.desktopId || entry.id)
    return !!(id.length && launchingMap[id])
  }

  function markLaunching(entry) {
    const id = normalizeDesktopId(entry.desktopId || entry.id)
    if (!id.length)
      return
    launchingMap[id] = {
      t: Date.now(),
      match: String(entry.match || "")
    }
    launchingRev++
    launchPoll.restart()
  }

  Timer {
    id: launchPoll
    interval: 350
    repeat: true
    onTriggered: {
      const now = Date.now()
      const ids = Object.keys(launchingMap)
      if (!ids.length) {
        stop()
        return
      }
      let changed = false
      for (let i = 0; i < ids.length; i++) {
        const rec = launchingMap[ids[i]]
        const probe = {
          id: ids[i],
          desktopId: ids[i],
          match: rec.match
        }
        if ((rec.match.length && isRunning(probe)) || now - rec.t > 8000) {
          delete launchingMap[ids[i]]
          changed = true
        }
      }
      if (changed)
        launchingRev++
      if (!Object.keys(launchingMap).length)
        stop()
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
      case "changefloatingmode":
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
