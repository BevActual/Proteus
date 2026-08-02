pragma Singleton

import Quickshell
import Quickshell.Services.Notifications
import QtQuick

// Desktop notification host for top-bar Control Center + toasts.
Singleton {
  id: root

  property int unreadCount: 0
  property var toastNotification: null
  property int toastSeq: 0

  readonly property var list: server.trackedNotifications
  readonly property int count: server.trackedNotifications ? server.trackedNotifications.values.length : 0
  readonly property bool dnd: Config.notificationsDnd

  // Single SoT for toast suppress (hard DND · Control Center open · Focus filters).
  readonly property bool toastsSuppressed: dnd || ShellState.controlCenterOpen
  readonly property bool showToast: !!toastNotification && !toastsSuppressed

  // Receipt clock (ms epoch by notification id) — the freedesktop payload has
  // no timestamp, so the Control Center's "2m ago" labels come from here.
  property var receivedTimes: ({})

  function receivedAt(notification) {
    if (!notification)
      return 0
    const t = receivedTimes[notification.id]
    return t ? t : 0
  }

  function shouldToast(n) {
    if (ShellState.controlCenterOpen)
      return false
    if (Config.notificationsDnd)
      return false
    if (FocusMode.active)
      return FocusMode.allows(n)
    return true
  }

  // Grouped view for CC (Phase 2d) — [{ appName, items: [...] }, ...]
  function groupedList() {
    const vals = server.trackedNotifications ? server.trackedNotifications.values : []
    const order = []
    const map = {}
    for (let i = 0; i < vals.length; i++) {
      const n = vals[i]
      if (!n)
        continue
      const name = String(n.appName || "App")
      if (!map[name]) {
        map[name] = []
        order.push(name)
      }
      map[name].push(n)
    }
    const out = []
    for (let i = 0; i < order.length; i++) {
      out.push({
        appName: order[i],
        items: map[order[i]]
      })
    }
    return out
  }

  NotificationServer {
    id: server
    keepOnReload: true
    bodySupported: true
    actionsSupported: true
    imageSupported: true
    actionIconsSupported: true

    onNotification: notification => {
      notification.tracked = true
      root.receivedTimes[notification.id] = Date.now()
      try {
        FocusMode.rememberRecent(notification)
      } catch (e) {
      }
      // Unread badge only when CC is closed (open clears / stays at 0).
      if (!ShellState.controlCenterOpen)
        root.unreadCount += 1
      if (root.shouldToast(notification)) {
        root.toastNotification = notification
        root.toastSeq += 1
      }
    }
  }

  function setDnd(on) {
    const next = !!on
    Config.notificationsDnd = next
    Config.flushSettings()
    if (next) {
      root.clearToast()
      // Hard quiet ends Focus so filters aren't confusingly "on" under DND.
      if (FocusMode.active)
        FocusMode.stop()
    }
  }

  function toggleDnd() {
    setDnd(!Config.notificationsDnd)
  }

  function markAllRead() {
    root.unreadCount = 0
  }

  function clearToast() {
    root.toastNotification = null
  }

  function dismiss(notification) {
    if (!notification)
      return
    if (root.toastNotification === notification)
      root.clearToast()
    delete root.receivedTimes[notification.id]
    notification.dismiss()
  }

  function clearAll() {
    const vals = server.trackedNotifications.values
    const copy = []
    for (let i = 0; i < vals.length; i++)
      copy.push(vals[i])
    for (let i = 0; i < copy.length; i++) {
      if (copy[i])
        copy[i].dismiss()
    }
    root.receivedTimes = {}
    root.unreadCount = 0
    root.clearToast()
  }

  Connections {
    target: ShellState
    function onControlCenterOpenChanged() {
      if (ShellState.controlCenterOpen) {
        root.markAllRead()
        root.clearToast()
      }
    }
  }

  Connections {
    target: Config
    function onNotificationsDndChanged() {
      if (Config.notificationsDnd)
        root.clearToast()
    }
  }
}
