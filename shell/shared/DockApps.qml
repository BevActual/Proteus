pragma Singleton

import Quickshell
import Quickshell.Hyprland
import QtQuick

Singleton {
  readonly property var pinned: [
    {
      id: "launcher",
      label: "Proteus",
      icon: "application-menu",
      special: "launcher"
    },
    {
      id: "terminal",
      label: "Terminal",
      icon: "utilities-terminal",
      desktopId: "com.mitchellh.ghostty",
      match: "ghostty",
      command: ["ghostty"]
    },
    {
      id: "files",
      label: "Files",
      icon: "system-file-manager",
      desktopId: "org.gnome.Nautilus",
      match: "nautilus",
      command: ["nautilus"],
      requires: ["display"]
    },
    {
      id: "browser",
      label: "Browser",
      icon: "chromium",
      desktopId: "chromium",
      match: "chromium",
      command: ["chromium"],
      requires: ["display"]
    },
    {
      id: "editor",
      label: "Editor",
      icon: "accessories-text-editor",
      desktopId: "mousepad",
      match: "mousepad",
      command: ["mousepad"],
      requires: ["display"]
    },
    {
      id: "settings",
      label: "Settings",
      icon: "preferences-system",
      special: "settings",
      match: "proteus-settings",
      desktopId: "proteus-settings",
      command: ["proteus-settings"]
    }
  ]

  readonly property var visiblePinned: {
    const _caps = Hardware.capabilityList
    const out = []
    for (let i = 0; i < pinned.length; i++) {
      if (EnvGate.dockEntryAvailable(pinned[i]))
        out.push(pinned[i])
    }
    return out
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

  // Toplevel state drives dock running-dots and the top-bar title
  // (ActiveWindow). Hyprland already pushes window lifecycle over its event
  // socket, so resync on those instead of polling in the steady state. The
  // timer is only a safety net for a missed event, and stops while locked —
  // nothing renders toplevel data behind the lock surface.
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
