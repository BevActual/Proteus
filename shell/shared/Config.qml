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
  // Customize: free place by default; optional iOS-like cell snap
  property alias desktopWidgetsSnapToGrid: adapter.desktopWidgetsSnapToGrid
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
  // User-added fonts: "Family Name=/abs/path.ttf;…"
  property alias userFonts: adapter.userFonts
  // Comma-separated .desktop ids, most recent first (Spotlight / launcher)
  property alias launcherRecents: adapter.launcherRecents
  // User-defined tag names, comma-separated (normalized slugs)
  property alias launcherTagCatalog: adapter.launcherTagCatalog
  // Per-app tags: "desktopId=tag1+tag2;otherId=tag3"
  property alias launcherAppTags: adapter.launcherAppTags
  // Dock middle pins: comma-separated desktop ids; "" = defaults; "-" = none
  property alias dockPins: adapter.dockPins
  // Icon plate: default | dark | clear | tinted (macOS Tahoe–style)
  property alias iconPlateMode: adapter.iconPlateMode
  property alias iconPlateCustom: adapter.iconPlateCustom
  // Per-app icon overrides: "desktopId=/path/or/theme-name;…"
  property alias iconOverrides: adapter.iconOverrides

  // Normalized mode (maps legacy auto/accent/custom)
  readonly property string iconPlateStyle: {
    const m = String(iconPlateMode || "").trim().toLowerCase()
    if (m === "auto")
      return "default"
    if (m === "accent" || m === "custom")
      return "tinted"
    if (m === "default" || m === "dark" || m === "clear" || m === "tinted")
      return m
    return "default"
  }

  property bool settingsReady: false
  // Background/Widgets raw JSON hydrate (expensive). Shell always does it on
  // load; Settings defers until Appearance → Background/Lock (or first write).
  property bool domainHydrated: false
  // Prevent onAdapterUpdated → ensureDomainHydrated re-entry while hydrate
  // writes Config.lockWidgets / desktopWidgets (stack overflow in Settings).
  property bool domainHydrating: false
  readonly property bool isSettingsApp: {
    const d = String(Quickshell.shellDir || Quickshell.shellRoot || "")
    return d.indexOf("proteus-settings") >= 0
  }

  // System fonts discovered via fc-list (falls back to built-in list)
  property var discoveredFonts: []
  property bool fontsScanning: false
  property bool userFontBusy: false
  property string userFontError: ""

  readonly property string userFontsDir: Quickshell.env("HOME") + "/.local/share/fonts/proteus"

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

  readonly property var userFontsList: {
    const raw = String(userFonts || "")
    const out = []
    if (!raw.length)
      return out
    const entries = raw.split(";")
    for (let i = 0; i < entries.length; i++) {
      const part = entries[i].trim()
      if (!part.length)
        continue
      const eq = part.indexOf("=")
      if (eq <= 0)
        continue
      const id = part.slice(0, eq).trim()
      const path = part.slice(eq + 1).trim()
      if (!id.length || !path.length)
        continue
      out.push({
        id: id,
        label: id,
        path: path,
        user: true
      })
    }
    return out
  }

  readonly property var fonts: {
    const user = userFontsList
    const sys = discoveredFonts.length ? discoveredFonts : fallbackFonts
    const seen = {}
    const out = []
    for (let i = 0; i < user.length; i++) {
      const id = String(user[i].id)
      if (seen[id])
        continue
      seen[id] = true
      out.push(user[i])
    }
    for (let i = 0; i < sys.length; i++) {
      const id = String(sys[i].id)
      if (seen[id])
        continue
      seen[id] = true
      out.push(sys[i])
    }
    return out
  }

  function isUserFont(family) {
    const id = String(family || "")
    const list = userFontsList
    for (let i = 0; i < list.length; i++) {
      if (String(list[i].id) === id)
        return true
    }
    return false
  }

  function serializeUserFonts(list) {
    const parts = []
    for (let i = 0; i < list.length; i++) {
      const id = String(list[i].id || "").trim()
      const path = String(list[i].path || "").trim()
      if (!id.length || !path.length)
        continue
      parts.push(id + "=" + path)
    }
    return parts.join(";")
  }

  function removeUserFont(family) {
    const id = String(family || "").trim()
    if (!id.length)
      return false
    const next = userFontsList.filter(f => String(f.id) !== id)
    userFonts = serializeUserFonts(next)
    if (fontFamily === id)
      fontFamily = next.length ? next[0].id : (discoveredFonts.length ? discoveredFonts[0].id : "Sans")
    flushSettings()
    return true
  }

  function addUserFontFromPath(srcPath) {
    const src = String(srcPath || "").trim()
    if (!src.length || userFontBusy)
      return false
    userFontBusy = true
    userFontError = ""
    fontAddProc.srcPath = src
    fontAddProc.running = false
    fontAddProc.running = true
    return true
  }

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
      command: ["proteus-terminal", "-e", "nmtui"]
    })
  }

  function openBluetoothEditor() {
    const ids = ["blueman-manager", "blueberry", "gnome-bluetooth-panel"]
    for (let i = 0; i < ids.length; i++) {
      const e = DesktopEntries.heuristicLookup(ids[i])
      if (e) {
        e.execute()
        return
      }
    }
    Quickshell.execDetached({
      command: ["proteus-terminal", "-e", "bluetoothctl"]
    })
  }

  function tailscaleUp() {
    Quickshell.execDetached({
      command: ["tailscale", "up"]
    })
  }

  function tailscaleDown() {
    Quickshell.execDetached({
      command: ["tailscale", "down"]
    })
  }

  function openTailscaleStatus() {
    Quickshell.execDetached({
      command: ["proteus-terminal", "-e", "bash", "-lc", "tailscale status; echo; read -n1 -s -r -p 'Press any key…'"]
    })
  }

  function copyToClipboard(text) {
    const t = String(text || "")
    if (!t.length)
      return
    Quickshell.execDetached({
      command: ["bash", "-lc", "printf %s " + shellQuote(t) + " | wl-copy 2>/dev/null || printf %s " + shellQuote(t) + " | xclip -selection clipboard"]
    })
  }

  function wifiConnect(ssid) {
    const name = String(ssid || "").trim()
    if (!name.length)
      return
    Quickshell.execDetached({
      command: ["nmcli", "device", "wifi", "connect", name]
    })
  }

  function wifiDisconnect(device) {
    const dev = String(device || "").trim()
    if (!dev.length)
      return
    Quickshell.execDetached({
      command: ["nmcli", "device", "disconnect", dev]
    })
  }

  function setHostname(name) {
    const n = String(name || "").trim()
    if (!n.length)
      return
    Quickshell.execDetached({
      command: ["hostnamectl", "set-hostname", n]
    })
  }

  function setAccentCustom(hex) {
    const n = normalizeAccentHex(hex)
    if (!n.length)
      return false
    if (accentCustom === n && accentId === "custom")
      return true
    accentCustom = n
    accentId = "custom"
    applyHyprland()
    return true
  }

  function setIconPlateMode(mode) {
    let m = String(mode || "").trim().toLowerCase()
    // Legacy aliases from earlier dogfood
    if (m === "auto")
      m = "default"
    if (m === "accent" || m === "custom")
      m = "tinted"
    if (m !== "default" && m !== "dark" && m !== "clear" && m !== "tinted")
      return false
    iconPlateMode = m
    flushSettings()
    return true
  }

  function setIconPlateCustom(hex) {
    const n = normalizeAccentHex(hex)
    if (!n.length)
      return false
    if (iconPlateCustom === n && iconPlateMode === "tinted")
      return true
    iconPlateCustom = n
    iconPlateMode = "tinted"
    // Persist via debounced onAdapterUpdated (live Theme update is enough mid-drag).
    return true
  }

  function parseIconOverrides() {
    const raw = String(iconOverrides || "")
    const map = {}
    if (!raw.length)
      return map
    const entries = raw.split(";")
    for (let i = 0; i < entries.length; i++) {
      const part = entries[i].trim()
      if (!part.length)
        continue
      const eq = part.indexOf("=")
      if (eq <= 0)
        continue
      const id = part.slice(0, eq).trim().replace(/\.desktop$/i, "")
      let val = part.slice(eq + 1).trim()
      if (!id.length || !val.length)
        continue
      map[id] = val
    }
    return map
  }

  function serializeIconOverrides(map) {
    const ids = Object.keys(map || {}).sort()
    const parts = []
    for (let i = 0; i < ids.length; i++) {
      const id = ids[i]
      const val = String(map[id] || "").trim()
      if (!id.length || !val.length)
        continue
      parts.push(id + "=" + val)
    }
    return parts.join(";")
  }

  function iconOverrideFor(desktopId) {
    const id = String(desktopId || "").trim().replace(/\.desktop$/i, "")
    if (!id.length)
      return ""
    const map = parseIconOverrides()
    return map[id] ? String(map[id]) : ""
  }

  function setIconOverride(desktopId, value) {
    const id = String(desktopId || "").trim().replace(/\.desktop$/i, "")
    let val = String(value || "").trim()
    if (!id.length)
      return false
    if (val.indexOf("file://") === 0)
      val = val.slice(7)
    const map = parseIconOverrides()
    if (!val.length) {
      delete map[id]
    } else {
      map[id] = val
    }
    iconOverrides = serializeIconOverrides(map)
    flushSettings()
    return true
  }

  function clearIconOverride(desktopId) {
    return setIconOverride(desktopId, "")
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
    // Cancel pending debounce so intentional flushes land immediately.
    settingsWriteTimer.stop()
    try {
      configFile.writeAdapter()
    } catch (e) {
    }
  }

  // Customize / drag: keep JsonAdapter in memory; skip disk round-trip that
  // reloads FileView and fights live applet positions.
  property bool suppressSettingsReload: false
  property bool deferSettingsWrites: false

  function beginLiveConfigEdits() {
    suppressSettingsReload = true
    deferSettingsWrites = true
    settingsWriteTimer.stop()
  }

  function endLiveConfigEdits() {
    deferSettingsWrites = false
    flushSettings()
    suppressSettingsReload = false
  }

  // Coalesce JsonAdapter churn from color graphs / sliders (was writing every tick).
  Timer {
    id: settingsWriteTimer
    interval: 100
    repeat: false
    onTriggered: {
      if (!root.settingsReady || root.domainHydrating)
        return
      try {
        configFile.writeAdapter()
      } catch (e) {
      }
    }
  }

  function launcherRecentList() {
    const raw = String(launcherRecents || "")
    if (!raw.length)
      return []
    return raw.split(",").map(s => s.trim()).filter(s => s.length)
  }

  function clearLauncherRecents() {
    if (!String(launcherRecents || "").length)
      return
    launcherRecents = ""
    flushSettings()
  }

  function recordLauncherRecent(desktopId) {
    const id = String(desktopId || "").trim()
    if (!id.length)
      return
    const next = [id]
    const prev = launcherRecentList()
    for (let i = 0; i < prev.length; i++) {
      if (prev[i] !== id)
        next.push(prev[i])
      if (next.length >= 16)
        break
    }
    launcherRecents = next.join(",")
    flushSettings()
  }

  function normalizeLauncherTag(name) {
    let s = String(name || "").toLowerCase().trim()
    s = s.replace(/[\s_]+/g, "-").replace(/[^a-z0-9\-]/g, "")
    s = s.replace(/-+/g, "-").replace(/^-|-$/g, "")
    return s.slice(0, 32)
  }

  function launcherTagCatalogList() {
    const raw = String(launcherTagCatalog || "")
    if (!raw.length)
      return []
    const out = []
    const seen = {}
    const parts = raw.split(",")
    for (let i = 0; i < parts.length; i++) {
      const t = normalizeLauncherTag(parts[i])
      if (!t.length || seen[t])
        continue
      seen[t] = true
      out.push(t)
    }
    return out
  }

  function ensureLauncherTag(name, doFlush) {
    const t = normalizeLauncherTag(name)
    if (!t.length)
      return ""
    const list = launcherTagCatalogList()
    if (list.indexOf(t) < 0) {
      list.push(t)
      list.sort()
      launcherTagCatalog = list.join(",")
      if (doFlush !== false)
        flushSettings()
    }
    return t
  }

  function removeLauncherTag(name) {
    const t = normalizeLauncherTag(name)
    if (!t.length)
      return
    launcherTagCatalog = launcherTagCatalogList().filter(x => x !== t).join(",")
    const map = parseLauncherAppTagMap()
    const ids = Object.keys(map)
    for (let i = 0; i < ids.length; i++) {
      const id = ids[i]
      map[id] = map[id].filter(x => x !== t)
      if (!map[id].length)
        delete map[id]
    }
    launcherAppTags = serializeLauncherAppTagMap(map)
    flushSettings()
  }

  function parseLauncherAppTagMap() {
    const raw = String(launcherAppTags || "")
    const map = {}
    if (!raw.length)
      return map
    const entries = raw.split(";")
    for (let i = 0; i < entries.length; i++) {
      const part = entries[i].trim()
      if (!part.length)
        continue
      const eq = part.indexOf("=")
      if (eq <= 0)
        continue
      const id = part.slice(0, eq).trim()
      if (!id.length)
        continue
      const tags = part.slice(eq + 1).split("+").map(s => normalizeLauncherTag(s)).filter(s => s.length)
      const uniq = []
      const seen = {}
      for (let j = 0; j < tags.length; j++) {
        if (seen[tags[j]])
          continue
        seen[tags[j]] = true
        uniq.push(tags[j])
      }
      if (uniq.length)
        map[id] = uniq
    }
    return map
  }

  function serializeLauncherAppTagMap(map) {
    const ids = Object.keys(map || {}).sort()
    const parts = []
    for (let i = 0; i < ids.length; i++) {
      const id = ids[i]
      const tags = (map[id] || []).map(t => normalizeLauncherTag(t)).filter(t => t.length)
      if (!tags.length)
        continue
      parts.push(id + "=" + tags.join("+"))
    }
    return parts.join(";")
  }

  function tagsForApp(desktopId) {
    const id = String(desktopId || "").trim()
    if (!id.length)
      return []
    const map = parseLauncherAppTagMap()
    return map[id] || []
  }

  function setAppTags(desktopId, tags) {
    const id = String(desktopId || "").trim()
    if (!id.length)
      return
    const map = parseLauncherAppTagMap()
    const next = []
    const seen = {}
    const list = tags || []
    for (let i = 0; i < list.length; i++) {
      const t = ensureLauncherTag(list[i], false)
      if (!t.length || seen[t])
        continue
      seen[t] = true
      next.push(t)
    }
    if (next.length)
      map[id] = next
    else
      delete map[id]
    launcherAppTags = serializeLauncherAppTagMap(map)
    flushSettings()
  }

  function toggleAppTag(desktopId, tagName) {
    const t = ensureLauncherTag(tagName, false)
    if (!t.length)
      return false
    const cur = tagsForApp(desktopId).slice()
    const i = cur.indexOf(t)
    if (i >= 0)
      cur.splice(i, 1)
    else
      cur.push(t)
    setAppTags(desktopId, cur)
    return i < 0
  }

  function appHasTag(desktopId, tagName) {
    const t = normalizeLauncherTag(tagName)
    if (!t.length)
      return false
    return tagsForApp(desktopId).indexOf(t) >= 0
  }


  Process {
    id: fontScanProc
    command: [
      "bash",
      "-lc",
      "fc-list : family 2>/dev/null | sed 's/,.*//' | sort -u | head -n 240 | python3 -c "
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

  // Copy font into ~/.local/share/fonts/proteus, query family, refresh cache.
  Process {
    id: fontAddProc
    property string srcPath: ""
    command: {
      const src = shellQuote(srcPath)
      const dir = shellQuote(root.userFontsDir)
      return [
        "bash",
        "-lc",
        "set -euo pipefail; "
          + "mkdir -p " + dir + "; "
          + "base=$(basename " + src + "); "
          + "dest=" + dir + "/$base; "
          + "cp -f " + src + " \"$dest\"; "
          + "fam=$(fc-query -f '%{family[0]}\\n' \"$dest\" 2>/dev/null | head -n1 | tr -d '\\r'); "
          + "if [ -z \"$fam\" ]; then fam=$(basename \"$dest\" | sed 's/\\.[^.]*$//'); fi; "
          + "fc-cache -f " + dir + " >/dev/null 2>&1 || true; "
          + "python3 -c 'import json,sys; print(json.dumps({\"id\":sys.argv[1],\"path\":sys.argv[2]}))' \"$fam\" \"$dest\""
      ]
    }
    stdout: StdioCollector {
      onStreamFinished: {
        root.userFontBusy = false
        try {
          const obj = JSON.parse(text.trim() || "{}")
          const id = String(obj.id || "").trim()
          const path = String(obj.path || "").trim()
          if (!id.length || !path.length) {
            root.userFontError = "Could not read font family"
            return
          }
          const next = root.userFontsList.slice()
          let replaced = false
          for (let i = 0; i < next.length; i++) {
            if (String(next[i].id) === id) {
              next[i] = {
                id: id,
                label: id,
                path: path,
                user: true
              }
              replaced = true
              break
            }
          }
          if (!replaced)
            next.push({
              id: id,
              label: id,
              path: path,
              user: true
            })
          root.userFonts = root.serializeUserFonts(next)
          root.fontFamily = id
          root.flushSettings()
          root.scanSystemFonts()
          root.userFontError = ""
        } catch (e) {
          root.userFontError = "Failed to add font"
        }
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        if (root.userFontBusy && text && String(text).trim().length)
          root.userFontError = String(text).trim().split("\n")[0]
      }
    }
    onExited: code => {
      if (code !== 0) {
        root.userFontBusy = false
        if (!root.userFontError.length)
          root.userFontError = "Add font failed (exit " + code + ")"
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

  function ensureDomainHydrated() {
    if (domainHydrated || domainHydrating)
      return
    domainHydrating = true
    const raw = configFile.text()
    Background.hydrateDailyFromRaw(raw)
    Widgets.hydrateLockFromRaw(raw)
    Widgets.hydrateDesktopFromRaw(raw)
    domainHydrated = true
    domainHydrating = false
  }

  FileView {
    id: configFile
    path: Quickshell.env("HOME") + "/.config/proteus/settings.json"
    watchChanges: true
    onFileChanged: {
      if (root.suppressSettingsReload)
        return
      reload()
    }
    onAdapterUpdated: {
      // Block writes until disk hydrate finishes — otherwise defaults clobber Daily sources.
      if (!root.settingsReady || root.domainHydrating)
        return
      if (root.deferSettingsWrites)
        return
      // Settings defers Background/Widgets hydrate; pull them in before any write.
      if (!root.domainHydrated)
        root.ensureDomainHydrated()
      settingsWriteTimer.restart()
    }
    onLoaded: {
      if (root.isSettingsApp) {
        // Appearance hub does not need Daily/Widgets — hydrate on first use.
        root.settingsReady = true
        return
      }
      // JsonAdapter often drops nested object arrays; re-parse from file text.
      Background.hydrateDailyFromRaw(configFile.text())
      Widgets.hydrateLockFromRaw(configFile.text())
      Widgets.hydrateDesktopFromRaw(configFile.text())
      root.domainHydrated = true
      root.settingsReady = true
    }
    onLoadFailed: error => {
      writeAdapter()
      root.settingsReady = true
      if (root.isSettingsApp)
        return
      Background.ensureDailySources()
      Widgets.hydrateLockFromRaw(configFile.text())
      Widgets.hydrateDesktopFromRaw(configFile.text())
      root.domainHydrated = true
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
      property real chromeOpacity: 0.28
      property bool chromeBlur: true
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
      property bool desktopWidgetsSnapToGrid: false
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
      // User-added fonts: "Family Name=/abs/path.ttf;…"
      property string userFonts: ""
      // Comma-separated desktop-entry ids (most recent first)
      property string launcherRecents: ""
      property string launcherTagCatalog: ""
      property string launcherAppTags: ""
      // Dock pins between Spotlight and Settings ("" = built-in defaults)
      property string dockPins: ""
      // default | dark | clear | tinted — squircle plate (macOS Icon & widget style)
      property string iconPlateMode: "default"
      property string iconPlateCustom: "#5c5c5e"
      // Per-app artwork: "desktopId=/abs/path/or/theme-name;…"
      property string iconOverrides: ""

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
    // Settings is its own Quickshell process — shell already applied Hypr/audio.
    // Re-running here pulls Audio + hyprctl on every Settings open (~seconds).
    if (!isSettingsApp) {
      applyHyprland()
      Audio.applyAudioLatency()
    }
  }
}
