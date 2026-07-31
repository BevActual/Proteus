pragma Singleton

import Quickshell
import QtQuick

Singleton {
  property bool launcherOpen: false
  // Cold boot / session start: locked until password (see DesktopShell + Config.lockOnSessionStart)
  property bool sessionLocked: false
  property bool sessionStartLockPending: true
  // Unlocked desktop widget Customize session
  property bool desktopCustomizeMode: false
  // Top-bar Control Center (notifications + quick settings)
  property bool controlCenterOpen: false

  // Hardware probe mirrors (session start — see Hardware.qml)
  readonly property bool hwReady: Hardware.ready
  readonly property bool hwProbing: Hardware.probing
  readonly property string deviceClass: Hardware.deviceClass
  readonly property string postureHint: Hardware.postureHint
  readonly property var capabilities: Hardware.capabilityList
  readonly property string hwError: Hardware.error

  function hasCapability(cap) {
    return Hardware.has(cap)
  }

  function refreshHardware() {
    Hardware.refresh()
  }

  function closeOverlays() {
    launcherOpen = false
    desktopCustomizeMode = false
    controlCenterOpen = false
  }

  function toggleLauncher() {
    if (sessionLocked || desktopCustomizeMode)
      return
    controlCenterOpen = false
    launcherOpen = !launcherOpen
  }

  function openLauncher() {
    if (sessionLocked || desktopCustomizeMode)
      return
    controlCenterOpen = false
    launcherOpen = true
  }

  function closeLauncher() {
    launcherOpen = false
  }

  function toggleControlCenter() {
    if (sessionLocked || desktopCustomizeMode)
      return
    launcherOpen = false
    controlCenterOpen = !controlCenterOpen
  }

  function openControlCenter() {
    if (sessionLocked || desktopCustomizeMode)
      return
    launcherOpen = false
    controlCenterOpen = true
  }

  function closeControlCenter() {
    controlCenterOpen = false
  }

  function enterDesktopCustomize() {
    if (sessionLocked)
      return
    launcherOpen = false
    controlCenterOpen = false
    if (!desktopCustomizeMode)
      Config.beginLiveConfigEdits()
    desktopCustomizeMode = true
  }

  function exitDesktopCustomize() {
    if (!desktopCustomizeMode)
      return
    desktopCustomizeMode = false
    Config.endLiveConfigEdits()
  }

  function lockSession() {
    closeOverlays()
    sessionLocked = true
  }

  function unlockSession() {
    sessionLocked = false
  }

  function openSettings(pageId, query) {
    if (sessionLocked)
      return
    launcherOpen = false
    controlCenterOpen = false
    const page = String(pageId || "").trim()
    const q = String(query || "").trim()
    let envPrefix = ""
    if (page.length)
      envPrefix += "PROTEUS_SETTINGS_PAGE=" + shellQuote(page) + " "
    if (q.length)
      envPrefix += "PROTEUS_SETTINGS_QUERY=" + shellQuote(q) + " "
    Quickshell.execDetached({
      command: [
        "bash",
        "-lc",
        envPrefix
          + "command -v proteus-settings >/dev/null && exec proteus-settings"
          + " || exec /mnt/proteus/apps/proteus-settings/proteus-settings"
      ]
    })
  }

  function shellQuote(s) {
    return "'" + String(s).replace(/'/g, "'\\''") + "'"
  }
}
