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

  // Console posture — nav layer + app switcher (ConsoleShell)
  property bool consoleSurfaceActive: false
  property bool consoleNavVisible: true
  property bool consoleSwitcherOpen: false
  // Guide long-press → return to desktop confirm (ConsoleHome)
  property bool consoleExitConfirmOpen: false
  // True while a console seat launch is in flight — suppress auto-show nav
  // so Exclusive grab does not beat the new client to focus.
  property bool consoleLaunchPending: false

  // Pad grammar — surfaces connect to padAction / implement handlers
  signal padAction(string button)
  readonly property bool padWanted: sessionLocked
      || controlCenterOpen
      || launcherOpen
      || consoleSwitcherOpen
      || consoleExitConfirmOpen
      || (consoleSurfaceActive && consoleNavVisible && !sessionLocked)

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
    consoleSwitcherOpen = false
    consoleExitConfirmOpen = false
  }

  // Shared pad router — lock → exit confirm → switcher → CC → Beacon → console nav
  function handlePad(button) {
    const b = String(button || "").toLowerCase()
    if (!b.length)
      return
    padAction(b)
  }

  function showConsoleNav() {
    consoleNavVisible = true
    consoleSwitcherOpen = false
  }

  function hideConsoleNav() {
    consoleNavVisible = false
    consoleSwitcherOpen = false
    controlCenterOpen = false
  }

  function toggleConsoleNav() {
    if (consoleNavVisible && !consoleSwitcherOpen) {
      hideConsoleNav()
      return
    }
    consoleNavVisible = true
    consoleSwitcherOpen = false
  }

  function openConsoleSwitcher() {
    consoleNavVisible = true
    controlCenterOpen = false
    consoleSwitcherOpen = true
  }

  function closeConsoleSwitcher() {
    consoleSwitcherOpen = false
  }

  function toggleConsoleSwitcher() {
    if (consoleSwitcherOpen) {
      consoleSwitcherOpen = false
      return
    }
    openConsoleSwitcher()
  }

  // Guide single-press target: show nav; if already on home with apps running,
  // open the switcher.
  function consoleGuidePrimary() {
    if (!consoleNavVisible) {
      consoleNavVisible = true
      consoleSwitcherOpen = false
      controlCenterOpen = false
      return
    }
    if (controlCenterOpen) {
      controlCenterOpen = false
      return
    }
    toggleConsoleSwitcher()
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
    consoleNavVisible = false
    sessionLocked = true
  }

  function unlockSession() {
    sessionLocked = false
    // First unlock of the session — allow chrome/widgets to map (they are
    // held back during the cold-boot lock so the desktop never flashes).
    sessionStartLockPending = false
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
    // Prefer the live tree launcher (single-instance via nav IPC) when the
    // repo is mounted — PATH may still point at a stale /usr/local copy.
    const root = String(Quickshell.env("PROTEUS_ROOT") || "").trim()
    const live = (root.length ? root : "/mnt/proteus") + "/apps/proteus-settings/proteus-settings"
    Quickshell.execDetached({
      command: [
        "bash",
        "-lc",
        envPrefix
          + "if [[ -x " + shellQuote(live) + " ]]; then exec " + shellQuote(live) + "; fi; "
          + "command -v proteus-settings >/dev/null && exec proteus-settings; "
          + "exec " + shellQuote(live)
      ]
    })
  }

  function shellQuote(s) {
    return "'" + String(s).replace(/'/g, "'\\''") + "'"
  }
}
