pragma Singleton

import Quickshell
import Quickshell.Services.Notifications
import QtQuick
import ".."

// Desktop notification host for top-bar Control Center + toasts.
Singleton {
  id: root

  property int unreadCount: 0
  property var toastNotification: null
  property int toastSeq: 0

  readonly property var list: server.trackedNotifications
  readonly property int count: server.trackedNotifications ? server.trackedNotifications.values.length : 0
  readonly property bool dnd: Config.notificationsDnd

  NotificationServer {
    id: server
    keepOnReload: true
    bodySupported: true
    actionsSupported: true
    imageSupported: true
    actionIconsSupported: true

    onNotification: notification => {
      notification.tracked = true
      if (!ShellState.controlCenterOpen)
        root.unreadCount += 1
      if (!Config.notificationsDnd && !ShellState.controlCenterOpen) {
        root.toastNotification = notification
        root.toastSeq += 1
      }
    }
  }

  function setDnd(on) {
    Config.notificationsDnd = !!on
    Config.flushSettings()
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
    if (notification)
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
}
