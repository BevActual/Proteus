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
  // Menu-bar center cluster → calendar / today popover
  property bool calendarOpen: false
  // A desktop Note widget is being edited in place (widget layer raised +
  // keyboard grab — see DesktopShell deskWidgetsWin)
  property bool desktopNoteEditing: false

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
    calendarOpen = false
    desktopNoteEditing = false
  }

  function toggleLauncher() {
    if (sessionLocked || desktopCustomizeMode)
      return
    controlCenterOpen = false
    calendarOpen = false
    launcherOpen = !launcherOpen
  }

  function openLauncher() {
    if (sessionLocked || desktopCustomizeMode)
      return
    controlCenterOpen = false
    calendarOpen = false
    launcherOpen = true
  }

  function closeLauncher() {
    launcherOpen = false
  }

  // Beacon dogfood probe — open with a seeded query (chrome IPC / smokes).
  // Beacon mirrors a result summary into beaconProbe for assertions.
  signal beaconQuerySeeded(string query)
  property string beaconProbe: "{}"

  function seedBeaconQuery(q) {
    if (sessionLocked || desktopCustomizeMode)
      return
    controlCenterOpen = false
    launcherOpen = true
    beaconQuerySeeded(String(q || ""))
  }

  function toggleControlCenter() {
    if (sessionLocked || desktopCustomizeMode)
      return
    launcherOpen = false
    calendarOpen = false
    controlCenterOpen = !controlCenterOpen
  }

  function openControlCenter() {
    if (sessionLocked || desktopCustomizeMode)
      return
    launcherOpen = false
    calendarOpen = false
    controlCenterOpen = true
  }

  function closeControlCenter() {
    controlCenterOpen = false
  }

  function toggleCalendar() {
    if (sessionLocked || desktopCustomizeMode)
      return
    launcherOpen = false
    controlCenterOpen = false
    calendarOpen = !calendarOpen
  }

  function closeCalendar() {
    calendarOpen = false
  }

  function enterDesktopCustomize() {
    if (sessionLocked)
      return
    launcherOpen = false
    controlCenterOpen = false
    desktopNoteEditing = false
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
    calendarOpen = false
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
