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
      id: "foot",
      label: "Terminal",
      icon: "utilities-terminal",
      desktopId: "foot",
      match: "foot",
      command: ["foot"]
    },
    {
      id: "files",
      label: "Files",
      icon: "system-file-manager",
      desktopId: "thunar",
      match: "thunar",
      command: ["thunar"],
      requires: ["display"]
    },
    {
      id: "browser",
      label: "Browser",
      icon: "firefox",
      desktopId: "firefox",
      match: "firefox",
      command: ["firefox"],
      requires: ["display"]
    },
    {
      id: "editor",
      label: "Editor",
      icon: "accessories-text-editor",
      desktopId: "org.kde.kate",
      match: "kate",
      command: ["kate"],
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

  Timer {
    interval: 1500
    running: true
    repeat: true
    onTriggered: Hyprland.refreshToplevels()
  }
}
