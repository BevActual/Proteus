pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Named Spaces — labels for logical slots 1–10 (settings.json source of truth).
// Hyprland renameworkspace is a derived apply via proteus-workspace apply-names.
// Logical slots 1–10 SoT. Strip visual order: Config.workspaceOrder.
// Custom specials: SpacesSpecials + specialWorkspaces. Disconnect: migrate-disconnect.
Singleton {
  id: root

  readonly property int maxLogical: 10
  readonly property int maxLabelLen: 24
  property int rev: 0

  readonly property string helper: Config.scriptsDir + "/proteus-workspace"

  function normalizeList(raw) {
    const out = []
    const src = Array.isArray(raw) ? raw : []
    for (let i = 0; i < root.maxLogical; i++) {
      let s = ""
      if (i < src.length && src[i] != null)
        s = String(src[i]).trim()
      if (s.length > root.maxLabelLen)
        s = s.slice(0, root.maxLabelLen)
      out.push(s)
    }
    return out
  }

  function names() {
    return root.normalizeList(Config.workspaceNames)
  }

  function labelForLogical(n) {
    const i = Math.round(Number(n) || 0) - 1
    if (i < 0 || i >= root.maxLogical)
      return ""
    return root.names()[i] || ""
  }

  // Short form for menu-bar pills (fallback to number).
  function displayForLogical(n) {
    const logical = Math.max(1, Math.min(root.maxLogical, Math.round(Number(n) || 1)))
    const label = root.labelForLogical(logical)
    if (!label.length)
      return String(logical)
    if (label.length <= 3)
      return label
    return label.slice(0, 2)
  }

  function setName(n, name) {
    const i = Math.round(Number(n) || 0) - 1
    if (i < 0 || i >= root.maxLogical)
      return false
    const list = root.names()
    let s = String(name || "").trim()
    if (s.length > root.maxLabelLen)
      s = s.slice(0, root.maxLabelLen)
    list[i] = s
    Config.workspaceNames = list
    root.rev++
    root.applyToHypr()
    return true
  }

  function applyToHypr() {
    applyProc.command = ["bash", root.helper, "apply-names"]
    applyProc.running = false
    applyProc.running = true
  }

  Connections {
    target: Config
    function onWorkspaceNamesChanged() {
      root.rev++
    }
  }

  Process {
    id: applyProc
    command: ["true"]
  }
}
