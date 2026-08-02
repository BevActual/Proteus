pragma Singleton

import Quickshell
import QtQuick

// Privacy Ask prompt — launch-time (Dock/Beacon) + mid-session capture
// (mic/camera/screen). Actions: Allow once (session) · Always Allow (store) · Deny.
// Fact: Permissions store + session file for capture enforce; fail-closed until ready.
Singleton {
  id: root

  property bool open: false
  // launch | capture
  property string mode: "launch"
  property var pendingEntry: null
  property string pendingCategory: ""
  property string appLabel: ""
  property string appId: ""
  property var pendingLaunch: null

  readonly property string categoryLabel: Permissions.categoryLabel(pendingCategory)
  readonly property bool visible: open && pendingCategory.length > 0
  readonly property bool isCapture: mode === "capture"

  readonly property string honesty: isCapture
      ? "Mid-session Ask — mic/camera/screen. Session Allow once. Deny/Ask kills screencast streams (best-effort). Not an OS sandbox."
      : "Ask once — not an OS sandbox. Portal may still prompt Flatpak apps."

  function promptLaunch(entry, category, launchFn) {
    if (!entry || !category)
      return false
    const id = Permissions.normalizeAppId(entry.id || entry.desktopId || "")
    if (!id.length)
      return false
    if (!Permissions.isAsk(id, category))
      return false
    root.mode = "launch"
    root.pendingEntry = entry
    root.pendingCategory = String(category)
    root.appId = id
    root.appLabel = String(entry.name || entry.label || id)
    root.pendingLaunch = typeof launchFn === "function" ? launchFn : null
    root.open = true
    ShellState.closeLauncher()
    ShellState.closeControlCenter()
    return true
  }

  // Mid-session: activity probe saw mic/camera/screen for an Ask-grant app.
  function promptCapture(appId, category, label) {
    if (!Permissions.ready)
      return false
    const id = Permissions.normalizeAppId(appId)
    const cat = String(category || "")
    if (!id.length || (cat !== "microphone" && cat !== "camera" && cat !== "screen"))
      return false
    if (!Permissions.isAsk(id, cat))
      return false
    // Don't stomp an open launch prompt.
    if (root.visible && root.mode === "launch")
      return false
    // Same capture already prompting.
    if (root.visible && root.mode === "capture"
        && root.appId === id && root.pendingCategory === cat)
      return true
    root.mode = "capture"
    root.pendingEntry = null
    root.pendingCategory = cat
    root.appId = id
    root.appLabel = String(label || id)
    root.pendingLaunch = null
    root.open = true
    ShellState.closeLauncher()
    ShellState.closeControlCenter()
    return true
  }

  function cancel() {
    root.open = false
    root.mode = "launch"
    root.pendingEntry = null
    root.pendingCategory = ""
    root.appLabel = ""
    root.appId = ""
    root.pendingLaunch = null
  }

  function _finishLaunch() {
    const fn = root.pendingLaunch
    const entry = root.pendingEntry
    root.cancel()
    if (typeof fn === "function")
      fn(entry)
  }

  function allowOnce() {
    if (!root.visible)
      return
    Permissions.grantSession(root.appId, root.pendingCategory)
    if (root.isCapture)
      root.cancel()
    else
      root._finishLaunch()
  }

  function allowAlways() {
    if (!root.visible)
      return
    const aid = root.appId
    const cat = root.pendingCategory
    Permissions.grantSession(aid, cat)
    Permissions.setAppGrant(aid, cat, "allow")
    if (root.isCapture)
      root.cancel()
    else
      root._finishLaunch()
  }

  function denyAlways() {
    if (!root.visible)
      return
    const aid = root.appId
    const cat = root.pendingCategory
    Permissions.clearSessionGrant(aid, cat)
    Permissions.setAppGrant(aid, cat, "deny")
    root.cancel()
  }
}
