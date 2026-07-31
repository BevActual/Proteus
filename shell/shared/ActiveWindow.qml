pragma Singleton

import Quickshell
import Quickshell.Hyprland
import QtQuick

Singleton {
  // Raw window title (fallback surface)
  readonly property string text: {
    const t = Hyprland.activeToplevel
    if (!t)
      return ""
    if (t.wayland && t.wayland.title)
      return t.wayland.title
    const ipc = t.lastIpcObject
    if (ipc && ipc.title)
      return ipc.title
    if (ipc && ipc.class)
      return ipc.class
    return ""
  }

  // Menu-bar identity — app name (macOS-style), not the noisy document title.
  // Shell chrome windows (Settings FloatingWindow) fall back to their title.
  readonly property string barText: {
    const t = Hyprland.activeToplevel
    if (!t)
      return ""
    const cls = DockApps.classOf(t)
    if (cls.length && !DockApps.isShellChromeClass(cls)) {
      const e = DockApps.entryFromWindowClass(cls)
      if (e && e.label && String(e.label).length)
        return String(e.label)
    }
    return text
  }
}
