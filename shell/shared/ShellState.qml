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
  // Monitor name that should host CC (multi-monitor); empty = focused monitor.
  property string controlCenterMonitor: ""
  // Menu-bar center cluster → calendar / today popover
  property bool calendarOpen: false
  // Menu-bar weather glance → WeatherPanel (hands off to Weather app)
  property bool weatherOpen: false
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
  // Host posture — lean ops chrome (HostShell)
  property bool hostSurfaceActive: false

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
    weatherOpen = false
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
    if (sessionLocked || sessionStartLockPending || desktopCustomizeMode)
      return
    controlCenterOpen = false
    calendarOpen = false
    weatherOpen = false
    launcherOpen = !launcherOpen
  }

  function openLauncher() {
    if (sessionLocked || sessionStartLockPending || desktopCustomizeMode)
      return
    controlCenterOpen = false
    calendarOpen = false
    weatherOpen = false
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
    if (sessionLocked || sessionStartLockPending || desktopCustomizeMode)
      return
    controlCenterOpen = false
    launcherOpen = true
    beaconQuerySeeded(String(q || ""))
  }

  function toggleControlCenter(monitorName) {
    if (sessionLocked || sessionStartLockPending || desktopCustomizeMode)
      return
    launcherOpen = false
    calendarOpen = false
    weatherOpen = false
    if (controlCenterOpen) {
      controlCenterOpen = false
      controlCenterMonitor = ""
      return
    }
    controlCenterMonitor = String(monitorName || "")
    controlCenterOpen = true
  }

  function openControlCenter(monitorName) {
    if (sessionLocked || sessionStartLockPending || desktopCustomizeMode)
      return
    launcherOpen = false
    calendarOpen = false
    weatherOpen = false
    controlCenterMonitor = String(monitorName || "")
    controlCenterOpen = true
  }

  function closeControlCenter() {
    controlCenterOpen = false
    controlCenterMonitor = ""
  }

  function toggleCalendar() {
    if (sessionLocked || sessionStartLockPending || desktopCustomizeMode)
      return
    launcherOpen = false
    controlCenterOpen = false
    weatherOpen = false
    calendarOpen = !calendarOpen
  }

  function closeCalendar() {
    calendarOpen = false
  }

  function toggleWeather() {
    if (sessionLocked || sessionStartLockPending || desktopCustomizeMode)
      return
    // No location yet — send the user to set one instead of an empty glance.
    if (!Weather.hasLocation) {
      openDateTimeSettings()
      return
    }
    launcherOpen = false
    controlCenterOpen = false
    calendarOpen = false
    weatherOpen = !weatherOpen
  }

  function closeWeather() {
    weatherOpen = false
  }

  function enterDesktopCustomize() {
    if (sessionLocked)
      return
    launcherOpen = false
    controlCenterOpen = false
    calendarOpen = false
    weatherOpen = false
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
    weatherOpen = false
    const page = String(pageId || "").trim()
    const q = String(query || "").trim()
    const environment = ({})
    if (page.length)
      environment.PROTEUS_SETTINGS_PAGE = page
    if (q.length)
      environment.PROTEUS_SETTINGS_QUERY = q
    // Inject resolved adapts (same keys DockApps.launchEntry uses).
    try {
      const adapt = EnvGate.appAdaptLaunchEnv({
        id: "proteus-settings",
        desktopId: "proteus-settings"
      }) || ({})
      const keys = Object.keys(adapt)
      for (let i = 0; i < keys.length; i++)
        environment[keys[i]] = adapt[keys[i]]
    } catch (e) {
    }
    // Prefer the live tree launcher (single-instance via nav IPC) when the
    // repo is mounted — PATH may still point at a stale /usr/local copy.
    const root = String(Quickshell.env("PROTEUS_ROOT") || "").trim()
    const live = (root.length ? root : "/mnt/proteus") + "/apps/proteus-settings/proteus-settings"
    Quickshell.execDetached({
      command: [
        "bash",
        "-lc",
        "if [[ -x " + shellQuote(live) + " ]]; then exec " + shellQuote(live) + "; fi; "
          + "command -v proteus-settings >/dev/null && exec proteus-settings; "
          + "exec " + shellQuote(live)
      ],
      environment: environment
    })
  }

  // Thin Host workloads app (read-only inventory) — not Settings.
  function openWorkloadsApp() {
    if (sessionLocked || sessionStartLockPending)
      return false
    closeOverlays()
    const root = String(Quickshell.env("PROTEUS_ROOT") || "").trim()
    const live = (root.length ? root : "/mnt/proteus") + "/apps/proteus-workloads/proteus-workloads"
    Quickshell.execDetached({
      command: [
        "bash",
        "-lc",
        "if [[ -x " + shellQuote(live) + " ]]; then exec " + shellQuote(live) + "; fi; "
            + "command -v proteus-workloads >/dev/null && exec proteus-workloads; "
            + "exec " + shellQuote(live)
      ]
    })
    return true
  }

  // Preferred calendar desktop ids (GNOME Calendar first — desktop kit).
  readonly property var calendarDesktopIds: [
    "org.gnome.Calendar",
    "gnome-calendar",
    "org.kde.merkuro.calendar",
    "org.kde.kalendar",
    "org.gnome.Evolution",
    "evolution"
  ]

  function findCalendarDesktop() {
    for (let i = 0; i < calendarDesktopIds.length; i++) {
      const id = calendarDesktopIds[i]
      const desk = DesktopEntries.heuristicLookup(id)
      if (desk)
        return desk
    }
    // Fallback: any desktop entry whose id/name looks like a calendar app.
    const apps = DesktopEntries.applications.values
    for (let i = 0; i < apps.length; i++) {
      const a = apps[i]
      const id = String(a.id || "").toLowerCase()
      const name = String(a.name || "").toLowerCase()
      if (id.indexOf("calendar") >= 0 || name === "calendar" || name.indexOf("calendar") === 0)
        return a
    }
    return null
  }

  // Re-evaluate when the desktop-entry catalog changes.
  readonly property bool calendarAppAvailable: {
    const _n = DesktopEntries.applications.values.length
    return !!findCalendarDesktop()
  }

  // Open the system Calendar app; if none, fall through to Date, time & weather.
  function openCalendarApp() {
    if (sessionLocked || sessionStartLockPending)
      return false
    const desk = findCalendarDesktop()
    closeOverlays()
    if (desk) {
      desk.execute()
      return true
    }
    openSettings("datetime")
    return false
  }

  function openDateTimeSettings() {
    openSettings("datetime")
  }

  // Preferred mail desktop ids (Geary first — desktop kit).
  readonly property var mailDesktopIds: [
    "org.gnome.Geary",
    "geary",
    "org.mozilla.Thunderbird",
    "thunderbird",
    "org.gnome.Evolution",
    "evolution"
  ]

  function findMailDesktop() {
    for (let i = 0; i < mailDesktopIds.length; i++) {
      const id = mailDesktopIds[i]
      const desk = DesktopEntries.heuristicLookup(id)
      if (desk)
        return desk
    }
    const apps = DesktopEntries.applications.values
    for (let i = 0; i < apps.length; i++) {
      const a = apps[i]
      const id = String(a.id || "").toLowerCase()
      const name = String(a.name || "").toLowerCase()
      if (id.indexOf("mail") >= 0 || id.indexOf("thunderbird") >= 0
          || name === "mail" || name.indexOf("mail") === 0)
        return a
    }
    return null
  }

  readonly property bool mailAppAvailable: {
    const _n = DesktopEntries.applications.values.length
    return !!findMailDesktop()
  }

  function openMailApp() {
    if (sessionLocked || sessionStartLockPending)
      return false
    const desk = findMailDesktop()
    closeOverlays()
    if (desk) {
      desk.execute()
      return true
    }
    openSettings("accounts")
    return false
  }

  // Preferred weather desktop ids (GNOME Weather first — desktop kit).
  readonly property var weatherDesktopIds: [
    "org.gnome.Weather",
    "gnome-weather",
    "org.kde.kweather",
    "kweather"
  ]

  function findWeatherDesktop() {
    for (let i = 0; i < weatherDesktopIds.length; i++) {
      const id = weatherDesktopIds[i]
      const desk = DesktopEntries.heuristicLookup(id)
      if (desk)
        return desk
    }
    const apps = DesktopEntries.applications.values
    for (let i = 0; i < apps.length; i++) {
      const a = apps[i]
      const id = String(a.id || "").toLowerCase()
      const name = String(a.name || "").toLowerCase()
      if (id.indexOf("weather") >= 0 || name === "weather" || name.indexOf("weather") === 0)
        return a
    }
    return null
  }

  readonly property bool weatherAppAvailable: {
    const _n = DesktopEntries.applications.values.length
    return !!findWeatherDesktop()
  }

  // Full Weather app; if none, Date, time & weather settings.
  function openWeatherApp() {
    if (sessionLocked || sessionStartLockPending)
      return false
    const desk = findWeatherDesktop()
    closeOverlays()
    if (desk) {
      desk.execute()
      return true
    }
    openSettings("datetime")
    return false
  }

  function shellQuote(s) {
    return "'" + String(s).replace(/'/g, "'\\''") + "'"
  }
}
