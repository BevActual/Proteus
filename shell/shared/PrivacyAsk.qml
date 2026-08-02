pragma Singleton

import Quickshell
import QtQuick

// Launch-time Ask prompt for manifest-gated Privacy grants.
// Actions: Allow once (session) · Always Allow (store) · Deny (store).
// Fact: Permissions store; fail-open until Permissions.ready.
Singleton {
  id: root

  property bool open: false
  property var pendingEntry: null
  property string pendingCategory: ""
  property string appLabel: ""
  property string appId: ""
  property var pendingLaunch: null

  readonly property string categoryLabel: Permissions.categoryLabel(pendingCategory)
  readonly property bool visible: open && pendingCategory.length > 0

  readonly property string honesty: "Ask once — not an OS sandbox. Portal may still prompt Flatpak apps."

  function promptLaunch(entry, category, launchFn) {
    if (!entry || !category)
      return false
    const id = Permissions.normalizeAppId(entry.id || entry.desktopId || "")
    if (!id.length)
      return false
    if (!Permissions.isAsk(id, category))
      return false
    root.pendingEntry = entry
    root.pendingCategory = String(category)
    root.appId = id
    root.appLabel = String(entry.name || id)
    root.pendingLaunch = typeof launchFn === "function" ? launchFn : null
    root.open = true
    ShellState.closeLauncher()
    ShellState.closeControlCenter()
    return true
  }

  function cancel() {
    root.open = false
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
    root._finishLaunch()
  }

  function allowAlways() {
    if (!root.visible)
      return
    const aid = root.appId
    const cat = root.pendingCategory
    Permissions.grantSession(aid, cat)
    Permissions.setAppGrant(aid, cat, "allow")
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
