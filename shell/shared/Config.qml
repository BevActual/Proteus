pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick

Singleton {
  id: root

  ConfigHypr { id: hypr; host: root }


  property alias gapsIn: adapter.gapsIn
  property alias gapsOut: adapter.gapsOut
  property alias borderSize: adapter.borderSize
  property alias rounding: adapter.rounding
  property alias animationsEnabled: adapter.animationsEnabled
  property alias dockEnabled: adapter.dockEnabled
  property alias dockIconSize: adapter.dockIconSize
  property alias dockAutoHide: adapter.dockAutoHide
  property alias dockMonitor: adapter.dockMonitor
  property alias barHeight: adapter.barHeight
  property alias barAutoHide: adapter.barAutoHide
  property alias barMonitor: adapter.barMonitor
  property alias mouseSensitivity: adapter.mouseSensitivity
  property alias mouseAccelFlat: adapter.mouseAccelFlat
  property alias audioLatency: adapter.audioLatency
  property alias locationName: adapter.locationName
  property alias locationLatitude: adapter.locationLatitude
  property alias locationLongitude: adapter.locationLongitude
  property alias locationTimezone: adapter.locationTimezone
  property alias weatherUnits: adapter.weatherUnits
  property alias accentId: adapter.accentId
  property alias accentCustom: adapter.accentCustom
  property alias chromeMode: adapter.chromeMode
  property alias chromeOpacity: adapter.chromeOpacity
  property alias chromeBlur: adapter.chromeBlur
  property alias lockOnSessionStart: adapter.lockOnSessionStart
  property alias notificationsDnd: adapter.notificationsDnd
  property alias lockBackgroundMode: adapter.lockBackgroundMode
  property alias lockWallpaperId: adapter.lockWallpaperId
  property alias lockWallpaperCustomPath: adapter.lockWallpaperCustomPath
  property alias lockWallpaperColor: adapter.lockWallpaperColor
  property alias lockDailySourceId: adapter.lockDailySourceId
  property alias lockDailyPath: adapter.lockDailyPath
  // Migrated into clock applet; kept for hydrate/compat writes
  property alias lockShowClock: adapter.lockShowClock
  property alias lockDim: adapter.lockDim
  property alias lockWallpaperVideoPath: adapter.lockWallpaperVideoPath
  property alias lockWallpaperReactiveId: adapter.lockWallpaperReactiveId
  property alias lockWallpaperMode: adapter.lockWallpaperMode
  property alias lockWallpaperAlbumId: adapter.lockWallpaperAlbumId
  property alias lockWallpaperSlideshow: adapter.lockWallpaperSlideshow
  property alias lockWallpaperSlideshowSecs: adapter.lockWallpaperSlideshowSecs
  property alias lockWallpaperShuffle: adapter.lockWallpaperShuffle
  // [{ id, type, enabled, x, y, size, showControls, showWhenIdle }, ...]
  property alias lockWidgets: adapter.lockWidgets
  // Desktop free-place applets: [{ id, type, enabled, x, y, size, ... }, ...]
  property alias desktopWidgets: adapter.desktopWidgets
  property alias wallpaperKind: adapter.wallpaperKind
  property alias wallpaperColor: adapter.wallpaperColor
  property alias wallpaperId: adapter.wallpaperId
  property alias wallpaperCustomPath: adapter.wallpaperCustomPath
  property alias wallpaperMode: adapter.wallpaperMode
  property alias wallpaperFolder: adapter.wallpaperFolder
  property alias wallpaperAlbumId: adapter.wallpaperAlbumId
  property alias wallpaperAlbums: adapter.wallpaperAlbums
  property alias wallpaperVideoPath: adapter.wallpaperVideoPath
  property alias wallpaperReactiveId: adapter.wallpaperReactiveId
  property alias wallpaperSlideshow: adapter.wallpaperSlideshow
  property alias wallpaperSlideshowSecs: adapter.wallpaperSlideshowSecs
  property alias wallpaperShuffle: adapter.wallpaperShuffle
  property alias wallpaperDailyProvider: adapter.wallpaperDailyProvider
  property alias wallpaperDailyUrl: adapter.wallpaperDailyUrl
  property alias wallpaperDailyApiKey: adapter.wallpaperDailyApiKey
  property alias wallpaperDailyAuth: adapter.wallpaperDailyAuth
  property alias wallpaperDailyMarket: adapter.wallpaperDailyMarket
  property alias wallpaperDailyRefreshHours: adapter.wallpaperDailyRefreshHours
  property alias wallpaperDailyPath: adapter.wallpaperDailyPath
  property alias wallpaperDailyTitle: adapter.wallpaperDailyTitle
  property alias wallpaperDailyCopyright: adapter.wallpaperDailyCopyright
  property alias wallpaperDailyFetchedAt: adapter.wallpaperDailyFetchedAt
  property alias wallpaperDailySources: adapter.wallpaperDailySources
  property alias wallpaperDailySourceId: adapter.wallpaperDailySourceId
  property alias fontFamily: adapter.fontFamily
  property alias fontSize: adapter.fontSize
  property alias fontSizeSm: adapter.fontSizeSm

  property bool settingsReady: false

  // System fonts discovered via fc-list (falls back to built-in list)
  property var discoveredFonts: []
  property bool fontsScanning: false

  readonly property var fallbackFonts: [
    {
      id: "Sans",
      label: "Sans"
    },
    {
      id: "Noto Sans",
      label: "Noto Sans"
    },
    {
      id: "DejaVu Sans",
      label: "DejaVu"
    },
    {
      id: "Cantarell",
      label: "Cantarell"
    },
    {
      id: "JetBrains Mono",
      label: "JetBrains Mono"
    },
    {
      id: "monospace",
      label: "Monospace"
    }
  ]

  readonly property var fonts: discoveredFonts.length ? discoveredFonts : fallbackFonts

  readonly property string scriptsDir: {
    const root = Quickshell.shellRoot
    if (root && root.length) {
      const marker = "/apps/proteus-settings"
      const idx = root.indexOf(marker)
      if (idx >= 0)
        return root.slice(0, idx) + "/shell/scripts"
      if (root.indexOf("/shell") >= 0)
        return root.replace(/\/shell.*/, "/shell/scripts")
      return root + "/../scripts"
    }
    return "/mnt/proteus/shell/scripts"
  }

  function shellQuote(s) {
    return "'" + String(s).replace(/'/g, "'\\''") + "'"
  }

  readonly property string generalConfPath: Quickshell.env("HOME") + "/.config/hypr/proteus-general.conf"
  readonly property string settingsJsonPath: Quickshell.env("HOME") + "/.config/proteus/settings.json"


  readonly property var accents: [
    {
      id: "blue",
      label: "Electric",
      color: "#3d8bfd"
    },
    {
      id: "teal",
      label: "Teal",
      color: "#2dd4bf"
    },
    {
      id: "violet",
      label: "Violet",
      color: "#a78bfa"
    },
    {
      id: "amber",
      label: "Amber",
      color: "#fbbf24"
    },
    {
      id: "rose",
      label: "Rose",
      color: "#fb7185"
    },
    {
      id: "custom",
      label: "Custom",
      color: ""
    }
  ]

  function normalizeAccentHex(hex) {
    let s = String(hex || "").trim()
    if (s.startsWith("#"))
      s = s.slice(1)
    if (/^[0-9a-fA-F]{3}$/.test(s))
      s = s[0] + s[0] + s[1] + s[1] + s[2] + s[2]
    if (!/^[0-9a-fA-F]{6}$/.test(s))
      return ""
    return "#" + s.toLowerCase()
  }

  readonly property color accentColor: {
    if (accentId === "custom") {
      const h = normalizeAccentHex(accentCustom)
      if (h.length)
        return h
      return accents[0].color
    }
    for (let i = 0; i < accents.length; i++) {
      if (accents[i].id === accentId && accents[i].id !== "custom")
        return accents[i].color
    }
    return accents[0].color
  }


  function setWallpaperSlideshow(on) { Background.setWallpaperSlideshow(on) }
  function setWallpaperSlideshowSecs(secs) { Background.setWallpaperSlideshowSecs(secs) }
  function setWallpaperShuffle(on) { Background.setWallpaperShuffle(on) }

  function scanSystemFonts() {
    if (fontScanProc.running)
      return
    fontsScanning = true
    fontScanProc.running = false
    fontScanProc.running = true
  }

  function session(action) {
    switch (action) {
    case "logout":
      Hyprland.dispatch("exit")
      break
    case "reboot":
      Quickshell.execDetached({
        command: ["systemctl", "reboot"]
      })
      break
    case "shutdown":
      Quickshell.execDetached({
        command: ["systemctl", "poweroff"]
      })
      break
    case "lock":
      Quickshell.execDetached({
        command: [
          "bash",
          "-lc",
          "quickshell -p /mnt/proteus/shell ipc call lock lock 2>/dev/null"
            + " || quickshell ipc call lock lock 2>/dev/null"
            + " || loginctl lock-session"
        ]
      })
      break
    }
  }

  function openNetworkEditor() {
    const nmtui = DesktopEntries.heuristicLookup("nm-connection-editor")
    if (nmtui) {
      nmtui.execute()
      return
    }
    Quickshell.execDetached({
      command: ["foot", "-e", "nmtui"]
    })
  }

  function setAccentCustom(hex) {
    const n = normalizeAccentHex(hex)
    if (!n.length)
      return false
    accentCustom = n
    accentId = "custom"
    applyHyprland()
    return true
  }

  function setLockOnSessionStart(on) {
    lockOnSessionStart = !!on
    flushSettings()
  }

  function setLockShowClock(on) {
    ensureLockClockWidget()
    const list = lockWidgetsList
    for (let i = 0; i < list.length; i++) {
      if (list[i].type === "clock") {
        setLockWidgetEnabled(list[i].id, !!on)
        lockShowClock = !!on
        return
      }
    }
    lockShowClock = !!on
    flushSettings()
  }

  function setLockDim(v) { return Background.setLockDim(v) }
  function setLockBackgroundMode(mode) { return Background.setLockBackgroundMode(mode) }
  function setLockWallpaperMode(mode) { return Background.setLockWallpaperMode(mode) }
  function setLockWallpaperAlbum(id) { return Background.setLockWallpaperAlbum(id) }
  function setLockWallpaperSlideshow(on) { return Background.setLockWallpaperSlideshow(on) }
  function setLockWallpaperSlideshowSecs(secs) { return Background.setLockWallpaperSlideshowSecs(secs) }
  function setLockWallpaperShuffle(on) { return Background.setLockWallpaperShuffle(on) }
  function setLockWallpaperVideo(path) { return Background.setLockWallpaperVideo(path) }
  function setLockWallpaperReactive(id) { return Background.setLockWallpaperReactive(id) }
  function advanceLockSlideshow() { return Background.advanceLockSlideshow() }
  function setLockWallpaper(id) { return Background.setLockWallpaper(id) }
  function setLockCustomWallpaper(path) { return Background.setLockCustomWallpaper(path) }
  function setLockWallpaperColor(hex) { return Background.setLockWallpaperColor(hex) }
  function setLockDailySource(id) { return Background.setLockDailySource(id) }
  function dailyFetchPlan(src, cacheDir) { return Background.dailyFetchPlan(src, cacheDir) }
  function parseDailyResult(raw, label) { return Background.parseDailyResult(raw, label) }
  function refreshLockDailyWallpaper() { return Background.refreshLockDailyWallpaper() }
  function setWallpaperKind(kind) { return Background.setWallpaperKind(kind) }
  function setWallpaperColor(hex) { return Background.setWallpaperColor(hex) }
  function setWallpaper(id) { return Background.setWallpaper(id) }
  function setWallpaperDailyProvider(id) { return Background.setWallpaperDailyProvider(id) }
  function setWallpaperDailyUrl(url) { return Background.setWallpaperDailyUrl(url) }
  function setWallpaperDailyApiKey(key) { return Background.setWallpaperDailyApiKey(key) }
  function setWallpaperDailyAuth(mode) { return Background.setWallpaperDailyAuth(mode) }
  function setWallpaperDailyMarket(mkt) { return Background.setWallpaperDailyMarket(mkt) }
  function setWallpaperDailyRefreshHours(hours) { return Background.setWallpaperDailyRefreshHours(hours) }
  function dailySourceIdNew() { return Background.dailySourceIdNew() }
  function defaultDailySource(provider) { return Background.defaultDailySource(provider) }
  function normalizeDailySource(s) { return Background.normalizeDailySource(s) }
  function hydrateDailySourcesFromFile() { return Background.hydrateDailySourcesFromFile() }
  function resolveActiveDailySource() { return Background.resolveActiveDailySource() }
  function ensureDailySources() { return Background.ensureDailySources() }
  function syncDailyLegacyFromActive() { return Background.syncDailyLegacyFromActive() }
  function patchActiveDailySource(patch) { return Background.patchActiveDailySource(patch) }
  function addDailySource(provider) { return Background.addDailySource(provider) }
  function setDailySource(id, fetchIfActive) { return Background.setDailySource(id, fetchIfActive) }
  function removeDailySource(id) { return Background.removeDailySource(id) }
  function renameDailySource(id, label) { return Background.renameDailySource(id, label) }
  function setWallpaperDaily() { return Background.setWallpaperDaily() }
  function refreshDailyWallpaper(applyAfter) { return Background.refreshDailyWallpaper(applyAfter) }
  function setCustomWallpaper(path) { return Background.setCustomWallpaper(path) }
  function clearCustomWallpaper() { return Background.clearCustomWallpaper() }
  function setWallpaperMode(mode) { return Background.setWallpaperMode(mode) }
  function setWallpaperFolder(path) { return Background.setWallpaperFolder(path) }
  function albumIdFromPath(path) { return Background.albumIdFromPath(path) }
  function albumLabelFromPath(path) { return Background.albumLabelFromPath(path) }
  function ensureWallpaperAlbums() { return Background.ensureWallpaperAlbums() }
  function addWallpaperAlbum(path) { return Background.addWallpaperAlbum(path) }
  function setWallpaperAlbum(id) { return Background.setWallpaperAlbum(id) }
  function removeWallpaperAlbum(id) { return Background.removeWallpaperAlbum(id) }
  function renameWallpaperAlbum(id, label) { return Background.renameWallpaperAlbum(id, label) }
  function setWallpaperVideo(path) { return Background.setWallpaperVideo(path) }
  function clearWallpaperVideo() { return Background.clearWallpaperVideo() }
  function setWallpaperReactive(id) { return Background.setWallpaperReactive(id) }
  function pickWallpaperFile() { return Background.pickWallpaperFile() }
  function pickWallpaperFolder() { return Background.pickWallpaperFolder() }
  function pickWallpaperVideo() { return Background.pickWallpaperVideo() }
  function scanWallpaperFolder(dirOverride) { return Background.scanWallpaperFolder(dirOverride) }
  function stopBackgroundBackends() { return Background.stopBackgroundBackends() }
  function applyBackground() { return Background.applyBackground() }
  function applyWallpaper() { return Background.applyWallpaper() }

  function flushSettings() {
    if (!settingsReady)
      return
    try {
      configFile.writeAdapter()
    } catch (e) {
    }
  }


  Process {
    id: fontScanProc
    command: [
      "bash",
      "-lc",
      "fc-list : family 2>/dev/null | sed 's/,.*//' | sort -u | head -n 80 | python3 -c "
          + "'import sys,json; fams=[l.strip() for l in sys.stdin if l.strip()]; "
          + "print(json.dumps([{\"id\":f,\"label\":f} for f in fams]))'"
    ]
    stdout: StdioCollector {
      onStreamFinished: {
        root.fontsScanning = false
        try {
          const list = JSON.parse(text.trim() || "[]")
          root.discoveredFonts = Array.isArray(list) && list.length ? list : []
        } catch (e) {
          root.discoveredFonts = []
        }
      }
    }
  }

  // Forwarders — ConfigHypr
  function utf8Hex(str) { return hypr.utf8Hex(str) }
  function generalConfText() { return hypr.generalConfText() }
  function applyHyprlandLive() { return hypr.applyHyprlandLive() }
  function persistGeneralConf() { return hypr.persistGeneralConf() }
  function persistGeneralConfNow() { return hypr.persistGeneralConfNow() }
  function applyHyprland() { return hypr.applyHyprland() }
  function openGeneralConfInEditor() { return hypr.openGeneralConfInEditor() }
  function openSettingsJsonInEditor() { return hypr.openSettingsJsonInEditor() }
  function setChromeMode(mode) { return hypr.setChromeMode(mode) }
  function setChromeOpacity(v) { return hypr.setChromeOpacity(v) }
  function setChromeBlur(on) { return hypr.setChromeBlur(on) }
  function chromeOnScreen(screen, selector) { return hypr.chromeOnScreen(screen, selector) }
  function chromeScreenOptions() { return hypr.chromeScreenOptions() }
  function applyChromeEffects() { return hypr.applyChromeEffects() }

  FileView {
    id: configFile
    path: Quickshell.env("HOME") + "/.config/proteus/settings.json"
    watchChanges: true
    onFileChanged: reload()
    onAdapterUpdated: {
      // Block writes until disk hydrate finishes — otherwise defaults clobber Daily sources.
      if (root.settingsReady)
        writeAdapter()
    }
    onLoaded: {
      // JsonAdapter often drops nested object arrays; re-parse from file text.
      Background.hydrateDailyFromRaw(configFile.text())
      Widgets.hydrateLockFromRaw(configFile.text())
      Widgets.hydrateDesktopFromRaw(configFile.text())
      root.settingsReady = true
    }
    onLoadFailed: error => {
      writeAdapter()
      root.settingsReady = true
      Background.ensureDailySources()
      Widgets.hydrateLockFromRaw(configFile.text())
      Widgets.hydrateDesktopFromRaw(configFile.text())
    }

    JsonAdapter {
      id: adapter
      property int gapsIn: 8
      property int gapsOut: 14
      property int borderSize: 2
      property int rounding: 10
      property bool animationsEnabled: true
      property bool dockEnabled: true
      // Resting dock icon size (px); magnification peaks ~1.45×
      property int dockIconSize: 48
      property bool dockAutoHide: false
      // "all" or a Quickshell/Hyprland output name (e.g. DP-1, Virtual-1)
      property string dockMonitor: "all"
      // Menu bar / top chrome height (px)
      property int barHeight: 34
      property bool barAutoHide: false
      property string barMonitor: "all"
      property real mouseSensitivity: 0
      property bool mouseAccelFlat: false
      // low | balanced | high → PipeWire clock.force-quantum 256 / 512 / 1024
      property string audioLatency: "high"
      // One system location, set once and shared by every surface that needs
      // "where am I" — weather today, sunrise/sunset later. Stored as precise
      // coordinates from an explicit place search, never inferred from IP.
      property string locationName: ""
      property real locationLatitude: 0
      property real locationLongitude: 0
      property string locationTimezone: ""
      // metric | imperial
      property string weatherUnits: "metric"
      property string accentId: "blue"
      property string accentCustom: "#3d8bfd"
      property string chromeMode: "dark"
      property real chromeOpacity: 1
      property bool chromeBlur: false
      property bool lockOnSessionStart: true
      property bool notificationsDnd: false
      // match | color | image | daily | video | reactive
      property string lockBackgroundMode: "match"
      property string lockWallpaperId: "default"
      property string lockWallpaperCustomPath: ""
      property string lockWallpaperColor: "#0f1419"
      property string lockDailySourceId: ""
      property string lockDailyPath: ""
      property bool lockShowClock: true
      // 0..0.75 overlay strength on lock backdrop
      property real lockDim: 0.35
      property string lockWallpaperVideoPath: ""
      property string lockWallpaperReactiveId: "drift"
      property string lockWallpaperMode: "fill"
      property string lockWallpaperAlbumId: ""
      property bool lockWallpaperSlideshow: false
      property int lockWallpaperSlideshowSecs: 60
      property bool lockWallpaperShuffle: false
      // Lock applets: [{ id, type, enabled, x, y, size, showControls, showWhenIdle }, ...]
      property var lockWidgets: []
      // Desktop free-place: [{ id, type, enabled, x, y, size, ... }, ...]
      property var desktopWidgets: []
      property string wallpaperKind: "image"
      property string wallpaperColor: "#0f1419"
      property string wallpaperId: "default"
      property string wallpaperCustomPath: ""
      property string wallpaperMode: "fill"
      property string wallpaperFolder: ""
      property string wallpaperAlbumId: ""
      // [{ id, label, path }, ...] — image slideshow albums
      property var wallpaperAlbums: []
      property string wallpaperVideoPath: ""
      property string wallpaperReactiveId: "drift"
      property bool wallpaperSlideshow: false
      property int wallpaperSlideshowSecs: 60
      property bool wallpaperShuffle: false
      property string wallpaperDailyProvider: "bing"
      property string wallpaperDailyUrl: ""
      property string wallpaperDailyApiKey: ""
      // none | bearer | client-id | query — used for custom (and Unsplash defaults to client-id)
      property string wallpaperDailyAuth: "none"
      property string wallpaperDailyMarket: "en-US"
      property int wallpaperDailyRefreshHours: 6
      property string wallpaperDailyPath: ""
      property string wallpaperDailyTitle: ""
      property string wallpaperDailyCopyright: ""
      property string wallpaperDailyFetchedAt: ""
      // [{ id, label, provider, url, apiKey, auth, market }, ...]
      property var wallpaperDailySources: []
      property string wallpaperDailySourceId: ""
      property string fontFamily: "Sans"
      property int fontSize: 13
      property int fontSizeSm: 12

      onGapsInChanged: root.applyHyprland()
      onGapsOutChanged: root.applyHyprland()
      onBorderSizeChanged: root.applyHyprland()
      onRoundingChanged: root.applyHyprland()
      onAnimationsEnabledChanged: root.applyHyprland()
      onMouseSensitivityChanged: root.applyHyprland()
      onMouseAccelFlatChanged: root.applyHyprland()
      onAccentIdChanged: root.applyHyprland()
      onAudioLatencyChanged: Audio.applyAudioLatency()
    }
  }


  Component.onCompleted: {
    applyHyprland()
    Audio.applyAudioLatency()
    Hardware.refresh()
  }
}
