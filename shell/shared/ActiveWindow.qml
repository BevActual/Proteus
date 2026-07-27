pragma Singleton

import Quickshell
import Quickshell.Hyprland
import QtQuick

Singleton {
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
}
