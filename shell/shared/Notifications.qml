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

  // Single SoT for toast suppress (DND · Control Center open).
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
      // Unread badge only when CC is closed (open clears / stays at 0).
      if (!ShellState.controlCenterOpen)
        root.unreadCount += 1
      // Toasts suppressed while DND or CC open — alerts still queue in the list.
      if (!root.toastsSuppressed) {
        root.toastNotification = notification
        root.toastSeq += 1
      }
    }
  }

  function setDnd(on) {
    const next = !!on
    Config.notificationsDnd = next
    Config.flushSettings()
    if (next)
      root.clearToast()
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
    // Copy ids first — mutating while iterating is unsafe
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
