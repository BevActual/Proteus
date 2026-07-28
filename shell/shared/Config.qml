pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick

Singleton {
  id: root

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

  // Folder scan results for Appearance → Background → Image
  property var wallpaperFolderEntries: []
  property bool wallpaperFolderScanning: false
  property bool wallpaperDailyFetching: false
  property string wallpaperDailyError: ""
  property bool lockDailyFetching: false
  property string lockDailyError: ""
  // Runtime-only lock album slideshow cursor (not persisted)
  property string lockSlideshowPath: ""
  property int lockSlideshowIndex: 0
  // Gate FileView writes until settings.json has been loaded (and daily sources hydrated).
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

  readonly property var lockBackgroundModes: [
    {
      id: "match",
      label: "Match"
    },
    {
      id: "color",
      label: "Color"
    },
    {
      id: "image",
      label: "Image"
    },
    {
      id: "daily",
      label: "Daily"
    },
    {
      id: "video",
      label: "Video"
    },
    {
      id: "reactive",
      label: "Animated"
    }
  ]

  // Applet sizes — common to both surfaces (lockWidgetSizes kept as the old name).
  readonly property var widgetSizes: [
    {
      id: "sm",
      label: "S"
    },
    {
      id: "md",
      label: "M"
    },
    {
      id: "lg",
      label: "L"
    }
  ]

  readonly property var lockWidgetSizes: widgetSizes

  readonly property string defaultLockDailyDir: defaultWallpaperFolder + "/daily/lock"

  readonly property var activeLockWallpaperAlbum: {
    const list = wallpaperAlbumsList
    const id = String(lockWallpaperAlbumId || "")
    for (let i = 0; i < list.length; i++) {
      if (String(list[i].id) === id)
        return list[i]
    }
    return activeWallpaperAlbum
  }

  readonly property string lockWallpaperFolderResolved: {
    const album = activeLockWallpaperAlbum
    if (album && album.path && String(album.path).length)
      return String(album.path)
    return wallpaperFolderResolved
  }

  // Effective lock backdrop kind (match → desktop; else lock-specific).
  readonly property string lockBackdropKind: {
    const m = String(lockBackgroundMode || "match")
    if (m === "color")
      return "color"
    if (m === "image" || m === "daily")
      return "image"
    if (m === "video")
      return "video"
    if (m === "reactive")
      return "reactive"
    // match
    const k = String(wallpaperKind || "image")
    if (k === "color")
      return "color"
    if (k === "video")
      return "video"
    if (k === "reactive")
      return "reactive"
    if (k === "image" || k === "daily")
      return "image"
    if (wallpaperPath && String(wallpaperPath).length)
      return "image"
    return "color"
  }

  readonly property string lockEffectiveFillMode: {
    const m = String(lockBackgroundMode || "match")
    if (m === "match")
      return String(wallpaperMode || "fill")
    return String(lockWallpaperMode || "fill")
  }

  readonly property string lockBackdropVideoPath: {
    const m = String(lockBackgroundMode || "match")
    if (m === "video")
      return String(lockWallpaperVideoPath || "")
    if (m === "match" && wallpaperKind === "video")
      return String(wallpaperVideoPath || "")
    return ""
  }

  readonly property string lockBackdropReactiveId: {
    const m = String(lockBackgroundMode || "match")
    if (m === "reactive")
      return String(lockWallpaperReactiveId || "drift")
    if (m === "match" && wallpaperKind === "reactive")
      return String(wallpaperReactiveId || "drift")
    return "drift"
  }

  readonly property string lockBackdropPath: {
    // Still-image path only (built-in / custom / daily). Album slideshow uses lockActiveImagePath.
    const m = String(lockBackgroundMode || "match")
    if (m === "daily") {
      if (lockDailyPath && String(lockDailyPath).length)
        return String(lockDailyPath)
      if (wallpaperDailyPath && String(wallpaperDailyPath).length)
        return String(wallpaperDailyPath)
      return wallpapers[0].path
    }
    if (m === "image") {
      if (lockWallpaperId === "custom" && lockWallpaperCustomPath && String(lockWallpaperCustomPath).length)
        return String(lockWallpaperCustomPath)
      for (let i = 0; i < wallpapers.length; i++) {
        if (wallpapers[i].id === lockWallpaperId)
          return wallpapers[i].path
      }
      return wallpapers[0].path
    }
    if (m === "color" || m === "video" || m === "reactive")
      return ""
    if (lockBackdropKind === "image")
      return wallpaperPath
    return ""
  }

  readonly property string lockActiveImagePath: {
    const m = String(lockBackgroundMode || "match")
    if (m === "match") {
      if (wallpaperKind === "image" && wallpaperSlideshow && lockSlideshowPath && lockSlideshowPath.length)
        return lockSlideshowPath
      // When matching desktop slideshow, prefer desktop path; LockSurface may still advance lock cursor unused.
      return wallpaperPath
    }
    if (m === "image" && lockWallpaperSlideshow && lockSlideshowPath && lockSlideshowPath.length)
      return lockSlideshowPath
    return lockBackdropPath
  }

  readonly property string lockBackdropColor: {
    const m = String(lockBackgroundMode || "match")
    if (m === "color") {
      const h = normalizeAccentHex(lockWallpaperColor)
      return h.length ? h : "#0f1419"
    }
    if (m === "match" && wallpaperKind === "color")
      return wallpaperColor
    return "#0f1419"
  }

  readonly property real lockDimClamped: {
    const d = Number(lockDim)
    if (isNaN(d))
      return 0.35
    return Math.max(0, Math.min(0.75, d))
  }

  readonly property var lockDailySourceResolved: {
    const list = wallpaperDailySourcesList
    const id = String(lockDailySourceId || "")
    if (id.length) {
      for (let i = 0; i < list.length; i++) {
        if (String(list[i].id) === id)
          return list[i]
      }
    }
    return activeDailySource
  }

  readonly property string lockBackgroundSummary: {
    const m = String(lockBackgroundMode || "match")
    if (m === "match")
      return "Match desktop · " + wallpaperSummary
    if (m === "color")
      return "Color · " + lockBackdropColor
    if (m === "video") {
      const p = String(lockWallpaperVideoPath || "")
      const i = Math.max(p.lastIndexOf("/"), p.lastIndexOf("\\"))
      const base = i >= 0 ? p.slice(i + 1) : p
      return "Video · " + (base.length ? base : "none")
    }
    if (m === "reactive") {
      let label = String(lockWallpaperReactiveId || "drift")
      for (let i = 0; i < wallpaperReactives.length; i++) {
        if (wallpaperReactives[i].id === lockWallpaperReactiveId) {
          label = wallpaperReactives[i].label
          break
        }
      }
      return "Animated · " + label
    }
    if (m === "daily") {
      const src = lockDailySourceResolved
      const label = src && src.label ? String(src.label) : "Daily"
      return "Daily · " + label
    }
    if (lockWallpaperSlideshow)
      return "Image · slideshow · " + lockWallpaperSlideshowSecs + "s"
    if (lockWallpaperId === "custom")
      return "Image · custom · " + lockWallpaperMode
    for (let i = 0; i < wallpapers.length; i++) {
      if (wallpapers[i].id === lockWallpaperId)
        return "Image · " + wallpapers[i].label + " · " + lockWallpaperMode
    }
    return "Image"
  }

  readonly property bool lockHasClockWidget: {
    const list = lockWidgetsList
    for (let i = 0; i < list.length; i++) {
      if (list[i].type === "clock" && list[i].enabled)
        return true
    }
    return false
  }

  // Single registration point for applet types. Lock and desktop keep separate
  // *instances* and separate layout models, but a widget is declared once here:
  // `source` is resolved by both applet hosts, and `lock`/`desktop` carry only
  // the fields that genuinely differ per surface. Adding a widget = one entry
  // here plus one QML file under surfaces/desktop/widgets/.
  readonly property var widgetCatalog: [
    {
      id: "clock",
      label: "Clock",
      category: "Time",
      icon: "🕒",
      defaultSize: "lg",
      unique: true,
      source: "widgets/ClockWidget.qml",
      // chrome: pinned to the lock surface — cannot be resized or removed there
      lock: {
        hint: "Lock chrome — time and date",
        chrome: true
      },
      desktop: {
        hint: "Time and date"
      }
    },
    {
      id: "media",
      label: "Now playing",
      hint: "Album art + track controls",
      category: "Music",
      icon: "♪",
      defaultSize: "md",
      unique: true,
      source: "widgets/MediaWidget.qml"
    },
    {
      id: "battery",
      label: "Battery",
      hint: "Charge level",
      category: "System",
      icon: "🔋",
      defaultSize: "sm",
      unique: true,
      source: "widgets/BatteryWidget.qml"
    },
    {
      id: "weather",
      label: "Weather",
      hint: "Conditions for your location",
      category: "Outside",
      icon: "⛅",
      defaultSize: "md",
      unique: true,
      source: "widgets/WeatherWidget.qml"
    }
  ]

  // Flattens widgetCatalog for one surface: base fields, with that surface's
  // overrides merged over the top. The per-surface keys are dropped so callers
  // see a plain catalog entry exactly as before.
  function widgetCatalogFor(surface) {
    const key = String(surface || "desktop")
    const out = []
    for (let i = 0; i < widgetCatalog.length; i++) {
      const src = widgetCatalog[i]
      const entry = {}
      for (const k in src) {
        if (k === "lock" || k === "desktop")
          continue
        entry[k] = src[k]
      }
      const over = src[key]
      if (over) {
        for (const k in over)
          entry[k] = over[k]
      }
      out.push(entry)
    }
    return out
  }

  // Component path for an applet type, resolved relative to the applet hosts.
  function widgetSourceFor(type) {
    const t = String(type || "")
    for (let i = 0; i < widgetCatalog.length; i++) {
      if (widgetCatalog[i].id === t)
        return String(widgetCatalog[i].source || "")
    }
    return ""
  }

  // Catalog of lock applets (Customize Lock Screen gallery).
  readonly property var lockWidgetCatalog: widgetCatalogFor("lock")

  readonly property var lockClockWeights: [
    { id: "light", label: "Light" },
    { id: "normal", label: "Regular" },
    { id: "medium", label: "Medium" }
  ]

  readonly property var lockClockDateStyles: [
    { id: "full", label: "Full" },
    { id: "short", label: "Short" }
  ]

  readonly property var lockWidgetsList: {
    const raw = lockWidgets
    if (!raw || !raw.length)
      return []
    const out = []
    for (let i = 0; i < raw.length; i++) {
      const n = normalizeLockWidget(raw[i])
      if (n)
        out.push(n)
    }
    return out
  }

  readonly property var lockWidgetsEnabledList: {
    return lockWidgetsList.filter(w => !!w.enabled)
  }

  readonly property var lockClockWidget: {
    const list = lockWidgetsEnabledList
    for (let i = 0; i < list.length; i++) {
      if (list[i].type === "clock")
        return list[i]
    }
    return null
  }

  readonly property var lockStripWidgets: {
    const list = lockWidgetsEnabledList.filter(w => w.type !== "clock")
    list.sort((a, b) => (a.slot - b.slot) || String(a.id).localeCompare(String(b.id)))
    return list
  }

  // Desktop widgets — free place (not stacked). Same applet types; separate instances.
  readonly property var desktopWidgetCatalog: widgetCatalogFor("desktop")

  readonly property var desktopWidgetsList: {
    const raw = desktopWidgets
    if (!raw || !raw.length)
      return []
    const out = []
    for (let i = 0; i < raw.length; i++) {
      const n = normalizeDesktopWidget(raw[i])
      if (n)
        out.push(n)
    }
    return out
  }

  readonly property var desktopWidgetsEnabledList: {
    return desktopWidgetsList.filter(w => !!w.enabled)
  }

  readonly property var wallpaperKinds: [
    {
      id: "color",
      label: "Color"
    },
    {
      id: "image",
      label: "Image"
    },
    {
      id: "daily",
      label: "Daily"
    },
    {
      id: "video",
      label: "Video"
    },
    {
      id: "reactive",
      label: "Animated"
    }
  ]

  readonly property var wallpaperColors: [
    {
      id: "slate",
      label: "Slate",
      color: "#0f1419"
    },
    {
      id: "ink",
      label: "Ink",
      color: "#0a0e14"
    },
    {
      id: "navy",
      label: "Navy",
      color: "#0c1a2e"
    },
    {
      id: "forest",
      label: "Forest",
      color: "#0f1f18"
    },
    {
      id: "plum",
      label: "Plum",
      color: "#1a1224"
    },
    {
      id: "charcoal",
      label: "Charcoal",
      color: "#1c1c1e"
    }
  ]

  readonly property var wallpaperReactives: [
    {
      id: "drift",
      label: "Drift",
      hint: "Slow shifting gradient"
    },
    {
      id: "pulse",
      label: "Pulse",
      hint: "Accent wash follows playback level"
    },
    {
      id: "orbit",
      label: "Orbit",
      hint: "Soft accent motion"
    },
    {
      id: "aurora",
      label: "Aurora",
      hint: "Layered color bands"
    },
    {
      id: "beacon",
      label: "Beacon",
      hint: "Soft breathing glow"
    }
  ]

  readonly property var wallpaperDailyProviders: [
    {
      id: "bing",
      label: "Bing",
      hint: "Windows-style daily photo · no key",
      needsKey: false
    },
    {
      id: "unsplash",
      label: "Unsplash",
      hint: "Random landscape · requires Access Key",
      needsKey: true
    },
    {
      id: "custom",
      label: "Custom",
      hint: "Your feed URL · optional API key",
      needsKey: false
    }
  ]

  readonly property var wallpaperDailyAuthModes: [
    {
      id: "none",
      label: "None"
    },
    {
      id: "bearer",
      label: "Bearer"
    },
    {
      id: "client-id",
      label: "Client-ID"
    },
    {
      id: "query",
      label: "Query"
    }
  ]

  readonly property string defaultWallpaperFolder: Quickshell.env("HOME") + "/.local/share/proteus/backgrounds"
  readonly property string defaultDailyWallpaperDir: defaultWallpaperFolder + "/daily"

  readonly property var wallpaperAlbumsList: {
    const raw = wallpaperAlbums
    if (Array.isArray(raw) && raw.length)
      return raw
    return []
  }

  readonly property var activeWallpaperAlbum: {
    const list = wallpaperAlbumsList
    const id = String(wallpaperAlbumId || "")
    for (let i = 0; i < list.length; i++) {
      if (String(list[i].id) === id)
        return list[i]
    }
    if (list.length)
      return list[0]
    return null
  }

  readonly property string wallpaperFolderResolved: {
    const album = activeWallpaperAlbum
    if (album && album.path && String(album.path).length)
      return String(album.path)
    const f = (wallpaperFolder && String(wallpaperFolder).length) ? String(wallpaperFolder) : defaultWallpaperFolder
    return f
  }

  readonly property string activeAlbumLabel: {
    const a = activeWallpaperAlbum
    if (a && a.label && String(a.label).length)
      return String(a.label)
    const p = wallpaperFolderResolved
    const parts = p.split("/")
    return parts.length ? parts[parts.length - 1] : "Album"
  }

  readonly property string wallpaperDir: {
    // Settings runs as apps/proteus-settings; wallpapers module under shell/wallpaper.
    const root = Quickshell.shellRoot
    if (root && root.length) {
      const marker = "/apps/proteus-settings"
      const idx = root.indexOf(marker)
      if (idx >= 0)
        return root.slice(0, idx) + "/shell/wallpaper"
      if (root.indexOf("/shell") >= 0)
        return root.replace(/\/shell.*/, "/shell/wallpaper")
      return root + "/../wallpaper"
    }
    return "/mnt/proteus/shell/wallpaper"
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

  readonly property var wallpaperDailySourcesList: {
    const raw = wallpaperDailySources
    if (Array.isArray(raw) && raw.length)
      return raw
    return []
  }

  readonly property var activeDailySource: {
    const list = wallpaperDailySourcesList
    if (!list.length)
      return null
    const id = String(wallpaperDailySourceId || "")
    for (let i = 0; i < list.length; i++) {
      if (String(list[i].id) === id)
        return list[i]
    }
    return list[0]
  }

  readonly property string activeDailySourceLabel: {
    const src = activeDailySource
    if (src && src.label && String(src.label).length)
      return String(src.label)
    return dailyWallpaperProviderLabel
  }

  readonly property string dailyWallpaperProviderLabel: {
    const src = activeDailySource
    const pid = src && src.provider ? String(src.provider) : String(wallpaperDailyProvider || "bing")
    for (let i = 0; i < wallpaperDailyProviders.length; i++) {
      if (wallpaperDailyProviders[i].id === pid)
        return wallpaperDailyProviders[i].label
    }
    return pid || "Bing"
  }
  function shellQuote(s) {
    return "'" + String(s).replace(/'/g, "'\\''") + "'"
  }

  readonly property string generalConfPath: Quickshell.env("HOME") + "/.config/hypr/proteus-general.conf"
  readonly property string settingsJsonPath: Quickshell.env("HOME") + "/.config/proteus/settings.json"

  readonly property string assetsDir: {
    // Settings runs as apps/proteus-settings; wallpapers live under shell/assets.
    const root = Quickshell.shellRoot
    if (root && root.length) {
      const marker = "/apps/proteus-settings"
      const idx = root.indexOf(marker)
      if (idx >= 0)
        return root.slice(0, idx) + "/shell/assets"
      return root + "/assets"
    }
    return "/mnt/proteus/shell/assets"
  }

  readonly property var wallpapers: [
    {
      id: "default",
      label: "Abyss",
      path: assetsDir + "/wallpaper.jpg"
    },
    {
      id: "harbor",
      label: "Harbor",
      path: assetsDir + "/wallpaper-harbor.jpg"
    },
    {
      id: "ember",
      label: "Ember",
      path: assetsDir + "/wallpaper-ember.jpg"
    },
    {
      id: "signal",
      label: "Signal",
      path: assetsDir + "/wallpaper-signal.jpg"
    },
    {
      id: "reef",
      label: "Reef",
      path: assetsDir + "/wallpaper-reef.jpg"
    }
  ]

  readonly property string wallpaperPath: {
    if ((wallpaperKind === "daily" || wallpaperId === "daily") && wallpaperDailyPath && wallpaperDailyPath.length)
      return wallpaperDailyPath
    if (wallpaperId === "custom" && wallpaperCustomPath && wallpaperCustomPath.length)
      return wallpaperCustomPath
    for (let i = 0; i < wallpapers.length; i++) {
      if (wallpapers[i].id === wallpaperId)
        return wallpapers[i].path
    }
    return wallpapers[0].path
  }

  readonly property string wallpaperBasename: {
    const p = wallpaperPath
    const i = Math.max(p.lastIndexOf("/"), p.lastIndexOf("\\"))
    return i >= 0 ? p.slice(i + 1) : p
  }

  readonly property string wallpaperVideoBasename: {
    const p = wallpaperVideoPath || ""
    const i = Math.max(p.lastIndexOf("/"), p.lastIndexOf("\\"))
    return i >= 0 ? p.slice(i + 1) : p
  }

  readonly property string wallpaperReactiveLabel: {
    for (let i = 0; i < wallpaperReactives.length; i++) {
      if (wallpaperReactives[i].id === wallpaperReactiveId)
        return wallpaperReactives[i].label
    }
    return wallpaperReactiveId
  }

  readonly property string wallpaperKindLabel: {
    for (let i = 0; i < wallpaperKinds.length; i++) {
      if (wallpaperKinds[i].id === wallpaperKind)
        return wallpaperKinds[i].label
    }
    return wallpaperKind
  }

  readonly property string wallpaperSummary: {
    if (wallpaperKind === "color")
      return "Color · " + wallpaperColor
    if (wallpaperKind === "video")
      return "Video · " + (wallpaperVideoBasename.length ? wallpaperVideoBasename : "none")
    if (wallpaperKind === "reactive")
      return "Animated · " + wallpaperReactiveLabel
    if (wallpaperKind === "daily" || wallpaperId === "daily") {
      const t = wallpaperDailyTitle && wallpaperDailyTitle.length
          ? wallpaperDailyTitle
          : activeDailySourceLabel
      return "Daily · " + activeDailySourceLabel + (t !== activeDailySourceLabel ? (" · " + t) : "")
    }
    if (wallpaperSlideshow)
      return "Image · slideshow · " + wallpaperSlideshowSecs + "s"
    if (wallpaperId === "custom")
      return "Image · " + (wallpaperBasename.length ? wallpaperBasename : "Custom") + " · " + wallpaperMode
    for (let i = 0; i < wallpapers.length; i++) {
      if (wallpapers[i].id === wallpaperId)
        return "Image · " + wallpapers[i].label + " · " + wallpaperMode
    }
    return "Image · " + wallpaperMode
  }

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

  function utf8Hex(str) {
    const s = unescape(encodeURIComponent(str))
    let hex = ""
    for (let i = 0; i < s.length; i++)
      hex += ("0" + s.charCodeAt(i).toString(16)).slice(-2)
    return hex
  }

  function generalConfText() {
    const c = String(accentColor).replace("#", "")
    let out = "# Generated by Proteus Settings — Desktop\n"
    out += "# Edit here or in Settings → Desktop. Applied via hyprctl + reload.\n\n"
    out += "general {\n"
    out += "  gaps_in = " + gapsIn + "\n"
    out += "  gaps_out = " + gapsOut + "\n"
    out += "  border_size = " + borderSize + "\n"
    out += "  col.active_border = rgba(" + c + "cc)\n"
    out += "  col.inactive_border = rgba(2a3544aa)\n"
    out += "}\n\n"
    out += "decoration {\n"
    out += "  rounding = " + rounding + "\n"
    out += "  blur {\n"
    out += "    enabled = " + (chromeBlur ? "true" : "false") + "\n"
    out += "    size = " + (chromeBlur ? "10" : "0") + "\n"
    out += "    passes = " + (chromeBlur ? "2" : "1") + "\n"
    out += "  }\n"
    out += "}\n\n"
    out += "animations {\n"
    out += "  enabled = " + (animationsEnabled ? "true" : "false") + "\n"
    out += "}\n\n"
    out += "input {\n"
    out += "  sensitivity = " + mouseSensitivity + "\n"
    out += "  accel_profile = " + (mouseAccelFlat ? "flat" : "adaptive") + "\n"
    out += "}\n\n"
    if (chromeBlur) {
      out += "# Quickshell chrome blur (Settings → Appearance) — Hyprland ≥0.56\n"
      out += "layerrule = blur on, ignore_alpha 0.2, match:namespace quickshell\n"
    }
    return out
  }

  function applyHyprlandLive() {
    const c = String(accentColor).replace("#", "")
    Quickshell.execDetached({
      command: ["hyprctl", "keyword", "general:gaps_in", String(gapsIn)]
    })
    Quickshell.execDetached({
      command: ["hyprctl", "keyword", "general:gaps_out", String(gapsOut)]
    })
    Quickshell.execDetached({
      command: ["hyprctl", "keyword", "general:border_size", String(borderSize)]
    })
    Quickshell.execDetached({
      command: ["hyprctl", "keyword", "general:col.active_border", "rgba(" + c + "cc)"]
    })
    Quickshell.execDetached({
      command: ["hyprctl", "keyword", "decoration:rounding", String(rounding)]
    })
    Quickshell.execDetached({
      command: ["hyprctl", "keyword", "animations:enabled", animationsEnabled ? "true" : "false"]
    })
    Quickshell.execDetached({
      command: ["hyprctl", "keyword", "input:sensitivity", String(mouseSensitivity)]
    })
    Quickshell.execDetached({
      command: ["hyprctl", "keyword", "input:accel_profile", mouseAccelFlat ? "flat" : "adaptive"]
    })
  }

  function persistGeneralConf() {
    // Debounce so JsonAdapter batch-loads (accent before chromeBlur) don't
    // write a half-applied proteus-general.conf.
    persistGeneralTimer.restart()
  }

  function persistGeneralConfNow() {
    const confHex = utf8Hex(generalConfText())
    generalWriteProc.command = ["python3", "-c",
      "import os, pathlib, subprocess\n"
      + "home = pathlib.Path(os.environ['HOME'])\n"
      + "(home / '.config/hypr').mkdir(parents=True, exist_ok=True)\n"
      + "(home / '.config/hypr/proteus-general.conf').write_text(bytes.fromhex('" + confHex + "').decode(), encoding='utf-8')\n"
      + "hypr = home / '.config/hypr/hyprland.conf'\n"
      + "if hypr.is_file():\n"
      + "    text = hypr.read_text(encoding='utf-8')\n"
      + "    if 'proteus-general.conf' not in text:\n"
      + "        hypr.write_text(text.rstrip() + '\\n\\n# Proteus desktop (Settings → Desktop)\\nsource = ~/.config/hypr/proteus-general.conf\\n', encoding='utf-8')\n"
      + "print('ok')\n"
    ]
    generalWriteProc.running = false
    generalWriteProc.running = true
  }

  Timer {
    id: persistGeneralTimer
    interval: 80
    repeat: false
    onTriggered: root.persistGeneralConfNow()
  }

  function applyHyprland() {
    applyHyprlandLive()
    persistGeneralConf()
  }

  function openGeneralConfInEditor() {
    Quickshell.execDetached({
      command: ["bash", "-lc", "mkdir -p \"$HOME/.config/hypr\"; touch \"$HOME/.config/hypr/proteus-general.conf\"; (command -v xdg-open >/dev/null && xdg-open \"$HOME/.config/hypr/proteus-general.conf\") || exec foot -e nvim \"$HOME/.config/hypr/proteus-general.conf\""]
    })
  }

  function openSettingsJsonInEditor() {
    Quickshell.execDetached({
      command: [
        "bash",
        "-lc",
        "mkdir -p \"$HOME/.config/proteus\"; touch \"$HOME/.config/proteus/settings.json\"; "
            + "(command -v xdg-open >/dev/null && xdg-open \"$HOME/.config/proteus/settings.json\") "
            + "|| exec foot -e nvim \"$HOME/.config/proteus/settings.json\""
      ]
    })
  }

  function setChromeMode(mode) {
    const m = String(mode || "")
    if (m !== "dark" && m !== "light")
      return
    chromeMode = m
  }

  function setChromeOpacity(v) {
    const n = Math.max(0, Math.min(1, Math.round(Number(v) * 100) / 100))
    chromeOpacity = n
    applyChromeEffects()
  }

  function setChromeBlur(on) {
    chromeBlur = !!on
    // Blur needs some see-through; nudge if still fully opaque
    if (chromeBlur && chromeOpacity > 0.92)
      chromeOpacity = 0.78
    applyChromeEffects()
  }

  // Menu bar / dock placement: "all" or an output name from Quickshell.screens.
  function chromeOnScreen(screen, selector) {
    const sel = String(selector || "all").trim()
    if (!sel.length || sel === "all")
      return true
    if (!screen)
      return false
    const screens = Quickshell.screens
    let found = false
    for (let i = 0; i < screens.length; i++) {
      if (String(screens[i].name) === sel) {
        found = true
        break
      }
    }
    if (!found) {
      // Saved output unplugged — keep chrome on the first screen
      return screens.length > 0 && screen === screens[0]
    }
    return String(screen.name) === sel
  }

  function chromeScreenOptions() {
    const out = [
      {
        id: "all",
        label: "All displays"
      }
    ]
    const screens = Quickshell.screens
    for (let i = 0; i < screens.length; i++) {
      const s = screens[i]
      const name = String(s.name || ("Display " + (i + 1)))
      const geo = s.width && s.height ? (" · " + s.width + "×" + s.height) : ""
      out.push({
        id: name,
        label: name + geo
      })
    }
    return out
  }

  function applyChromeEffects() {
    persistGeneralConf()
    const blurOn = chromeBlur ? "1" : "0"
    const size = chromeBlur ? "10" : "0"
    Quickshell.execDetached({
      command: ["hyprctl", "keyword", "decoration:blur:enabled", blurOn]
    })
    Quickshell.execDetached({
      command: ["hyprctl", "keyword", "decoration:blur:size", size]
    })
    Quickshell.execDetached({
      command: ["hyprctl", "keyword", "decoration:blur:passes", chromeBlur ? "2" : "1"]
    })
    if (chromeBlur) {
      // Hyprland ≥0.56 layerrule syntax
      Quickshell.execDetached({
        command: ["hyprctl", "keyword", "layerrule", "blur on, ignore_alpha 0.2, match:namespace quickshell"]
      })
    }
    Quickshell.execDetached({
      command: ["hyprctl", "reload"]
    })
  }

  function setWallpaperSlideshow(on) {
    wallpaperSlideshow = !!on
    if (wallpaperKind === "image")
      applyBackground()
  }

  function setWallpaperSlideshowSecs(secs) {
    const n = Math.max(5, Math.min(600, Math.round(secs)))
    wallpaperSlideshowSecs = n
  }

  function setWallpaperShuffle(on) {
    wallpaperShuffle = !!on
  }

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

  function setLockDim(v) {
    const n = Number(v)
    if (isNaN(n))
      return
    lockDim = Math.round(Math.max(0, Math.min(0.75, n)) * 100) / 100
    flushSettings()
  }

  function setLockBackgroundMode(mode) {
    const m = String(mode || "match")
    if (m !== "match" && m !== "image" && m !== "color" && m !== "daily" && m !== "video" && m !== "reactive")
      return
    lockBackgroundMode = m
    flushSettings()
    if (m === "daily") {
      ensureDailySources()
      if (!String(lockDailySourceId || "").length && activeDailySource)
        lockDailySourceId = String(activeDailySource.id)
      if (!(lockDailyPath && String(lockDailyPath).length) && !(wallpaperDailyPath && String(wallpaperDailyPath).length))
        refreshLockDailyWallpaper()
    }
    if (m === "image" && lockWallpaperSlideshow)
      advanceLockSlideshow()
  }

  function setLockWallpaperMode(mode) {
    const allowed = ["fill", "fit", "stretch", "center"]
    const m = String(mode || "fill")
    if (allowed.indexOf(m) < 0)
      return
    lockWallpaperMode = m
    if (lockBackgroundMode === "match")
      lockBackgroundMode = "image"
    flushSettings()
  }

  function setLockWallpaperAlbum(id) {
    ensureWallpaperAlbums()
    const sid = String(id || "")
    const list = wallpaperAlbumsList
    let album = null
    for (let i = 0; i < list.length; i++) {
      if (String(list[i].id) === sid) {
        album = list[i]
        break
      }
    }
    if (!album && list.length)
      album = list[0]
    if (!album)
      return
    lockWallpaperAlbumId = String(album.id)
    lockBackgroundMode = "image"
    flushSettings()
    scanWallpaperFolder(album.path)
    if (lockWallpaperSlideshow)
      advanceLockSlideshow()
  }

  function setLockWallpaperSlideshow(on) {
    lockWallpaperSlideshow = !!on
    lockBackgroundMode = "image"
    flushSettings()
    if (lockWallpaperSlideshow) {
      scanWallpaperFolder()
      advanceLockSlideshow()
    } else {
      lockSlideshowPath = ""
    }
  }

  function setLockWallpaperSlideshowSecs(secs) {
    const n = Math.max(5, Math.min(600, Math.round(Number(secs) || 60)))
    lockWallpaperSlideshowSecs = n
    flushSettings()
  }

  function setLockWallpaperShuffle(on) {
    lockWallpaperShuffle = !!on
    flushSettings()
  }

  function setLockWallpaperVideo(path) {
    const p = String(path || "").trim()
    if (!p.length)
      return
    lockWallpaperVideoPath = p
    lockBackgroundMode = "video"
    flushSettings()
  }

  function setLockWallpaperReactive(id) {
    const rid = String(id || "drift")
    let ok = false
    for (let i = 0; i < wallpaperReactives.length; i++) {
      if (wallpaperReactives[i].id === rid)
        ok = true
    }
    if (!ok)
      return
    lockWallpaperReactiveId = rid
    lockBackgroundMode = "reactive"
    flushSettings()
  }

  function advanceLockSlideshow() {
    const list = wallpaperFolderEntries
    if (!list || !list.length) {
      lockSlideshowPath = lockBackdropPath
      return
    }
    if (lockWallpaperShuffle) {
      lockSlideshowIndex = Math.floor(Math.random() * list.length)
    } else {
      lockSlideshowIndex = (lockSlideshowIndex + 1) % list.length
    }
    const entry = list[lockSlideshowIndex]
    lockSlideshowPath = (entry && entry.path) ? String(entry.path) : lockBackdropPath
  }

  function setLockWallpaper(id) {
    const sid = String(id || "default")
    lockWallpaperId = sid
    lockBackgroundMode = "image"
    flushSettings()
  }

  function setLockCustomWallpaper(path) {
    const p = String(path || "").trim()
    if (!p.length)
      return
    lockWallpaperCustomPath = p
    lockWallpaperId = "custom"
    lockBackgroundMode = "image"
    flushSettings()
  }

  function setLockWallpaperColor(hex) {
    const n = normalizeAccentHex(hex)
    if (!n.length)
      return false
    lockWallpaperColor = n
    lockBackgroundMode = "color"
    flushSettings()
    return true
  }

  function setLockDailySource(id) {
    ensureDailySources()
    const sid = String(id || "")
    const list = wallpaperDailySourcesList
    let found = null
    for (let i = 0; i < list.length; i++) {
      if (String(list[i].id) === sid) {
        found = list[i]
        break
      }
    }
    if (!found && list.length)
      found = list[0]
    if (!found) {
      lockDailyError = "Add a daily source under Background → Daily first"
      return
    }
    lockDailySourceId = String(found.id)
    lockBackgroundMode = "daily"
    lockDailyError = ""
    flushSettings()
    refreshLockDailyWallpaper()
  }

  // Shared by both surfaces: validate a daily source and build the fetch
  // invocation. The lock and desktop paths differ in where the image lands and
  // what they do afterwards, not in how the fetch is spelled — so only that
  // last part stays per-surface.
  //
  // Returns { ok: true, command, apiKey } or { ok: false, error }.
  function dailyFetchPlan(src, cacheDir) {
    if (!src)
      return {
        ok: false,
        error: "No daily source configured"
      }

    const provider = String(src.provider || "bing")
    const url = String(src.url || "")
    const apiKey = String(src.apiKey || "")
    const auth = String(src.auth || "none")
    const market = String(src.market || "en-US")

    if (provider === "custom" && !url.trim())
      return {
        ok: false,
        error: "Custom feed needs a URL"
      }
    if (provider === "unsplash" && !apiKey.trim())
      return {
        ok: false,
        error: "Unsplash requires an API key"
      }

    return {
      ok: true,
      apiKey: apiKey,
      command: [
        "python3",
        scriptsDir + "/fetch-daily-wallpaper.py",
        "--settings",
        settingsJsonPath,
        "--cache-dir",
        String(cacheDir),
        "--provider",
        provider,
        "--url",
        url,
        "--auth",
        auth,
        "--market",
        market
      ]
    }
  }

  // Shared by both daily fetch processes: pull the result object out of stdout.
  // Returns { ok, error, path, title, copyright, fetchedAt }.
  function parseDailyResult(raw, label) {
    const body = String(raw || "").trim()
    const what = String(label || "Daily")
    if (!body.length)
      return {
        ok: false,
        error: what + " fetch returned no data"
      }
    try {
      // The script prints one JSON blob; take the last non-empty line.
      const lines = body.split("\n").filter(l => l.trim().length)
      const res = JSON.parse(lines[lines.length - 1])
      if (!res || !res.ok)
        return {
          ok: false,
          error: (res && res.error) ? String(res.error) : (what + " fetch failed")
        }
      return {
        ok: true,
        error: "",
        path: res.path ? String(res.path) : "",
        title: res.title ? String(res.title) : "",
        copyright: res.copyright ? String(res.copyright) : "",
        fetchedAt: res.fetchedAt ? String(res.fetchedAt) : ""
      }
    } catch (e) {
      return {
        ok: false,
        error: what + " fetch parse error"
      }
    }
  }

  function refreshLockDailyWallpaper() {
    if (lockDailyFetchProc.running)
      return
    ensureDailySources()
    let src = lockDailySourceResolved
    if (!src)
      src = activeDailySource

    const plan = dailyFetchPlan(src, defaultLockDailyDir)
    if (!plan.ok) {
      lockDailyError = plan.error
      lockDailyFetching = false
      return
    }
    if (!String(lockDailySourceId || "").length)
      lockDailySourceId = String(src.id)

    lockDailyFetching = true
    lockDailyError = ""
    lockBackgroundMode = "daily"
    flushSettings()

    lockDailyFetchProc.command = plan.command
    // Key goes through the environment — argv is world-readable via /proc.
    lockDailyFetchProc.environment = ({ "PROTEUS_DAILY_API_KEY": plan.apiKey })
    lockDailyFetchProc.running = false
    lockDailyFetchProc.running = true
  }

  function lockWidgetIdNew() {
    return "lw-" + Math.random().toString(16).slice(2, 9)
  }

  function lockWidgetSpanForSize(size) {
    const s = String(size || "md")
    if (s === "sm")
      return 1
    if (s === "lg")
      return 4
    return 2
  }

  function normalizeLockWidget(w) {
    const type = String((w && w.type) || "")
    let meta = null
    for (let i = 0; i < lockWidgetCatalog.length; i++) {
      if (lockWidgetCatalog[i].id === type) {
        meta = lockWidgetCatalog[i]
        break
      }
    }
    if (!meta)
      return null
    let size = String((w && w.size) || meta.defaultSize || "md")
    if (size !== "sm" && size !== "md" && size !== "lg")
      size = String(meta.defaultSize || "md")
    let slot = Number(w && w.slot)
    if (isNaN(slot) || slot < 0) {
      // Migrate legacy free-place → slot by former y then x
      const y = Number(w && w.y)
      const x = Number(w && w.x)
      if (!isNaN(y) || !isNaN(x))
        slot = Math.round((isNaN(y) ? 0.5 : y) * 1000) + Math.round((isNaN(x) ? 0.5 : x) * 10)
      else
        slot = 0
    }
    let weight = String((w && w.clockWeight) || "light")
    if (weight !== "light" && weight !== "normal" && weight !== "medium")
      weight = "light"
    let dateStyle = String((w && w.dateStyle) || "full")
    if (dateStyle !== "full" && dateStyle !== "short")
      dateStyle = "full"
    let clockColor = String((w && w.clockColor) || "#f5f5f7")
    if (!clockColor.length || clockColor.charAt(0) !== "#")
      clockColor = "#f5f5f7"
    return {
      id: String((w && w.id) || lockWidgetIdNew()),
      type: type,
      label: String(meta.label || type),
      enabled: w && w.enabled === false ? false : true,
      slot: Math.round(slot),
      size: size,
      span: lockWidgetSpanForSize(size),
      showControls: w && w.showControls === false ? false : true,
      showWhenIdle: !!(w && w.showWhenIdle),
      clockWeight: weight,
      clockColor: clockColor,
      showDate: w && w.showDate === false ? false : true,
      dateStyle: dateStyle,
      clockDepth: w && w.clockDepth === false ? false : true
    }
  }

  function compactLockWidgetSlots(list) {
    const clocks = []
    const strip = []
    for (let i = 0; i < list.length; i++) {
      if (list[i].type === "clock")
        clocks.push(list[i])
      else
        strip.push(list[i])
    }
    strip.sort((a, b) => (a.slot - b.slot) || String(a.id).localeCompare(String(b.id)))
    for (let i = 0; i < strip.length; i++) {
      strip[i] = normalizeLockWidget(Object.assign({}, strip[i], {
        slot: i,
        span: lockWidgetSpanForSize(strip[i].size)
      }))
    }
    return clocks.concat(strip)
  }

  function hydrateLockWidgetsFromFile() {
    try {
      const raw = configFile.text()
      if (raw && String(raw).trim().length) {
        const d = JSON.parse(String(raw))
        if (Array.isArray(d.lockWidgets)) {
          lockWidgets = compactLockWidgetSlots(d.lockWidgets.map(w => normalizeLockWidget(w)).filter(w => w !== null))
        }
      }
    } catch (e) {
    }
    if (!Array.isArray(lockWidgets))
      lockWidgets = []
    ensureLockClockWidget()
  }

  function ensureLockClockWidget() {
    const list = lockWidgetsList.slice()
    for (let i = 0; i < list.length; i++) {
      if (list[i].type === "clock")
        return list[i]
    }
    const enabled = lockShowClock !== false
    const w = normalizeLockWidget({
      id: lockWidgetIdNew(),
      type: "clock",
      enabled: enabled,
      size: "lg",
      slot: 0,
      clockWeight: "light",
      clockColor: "#f5f5f7",
      showDate: true,
      dateStyle: "full",
      clockDepth: true
    })
    list.unshift(w)
    lockWidgets = compactLockWidgetSlots(list)
    lockShowClock = !!enabled
    return w
  }

  function addLockWidget(type, size) {
    const t = String(type || "")
    let found = null
    for (let i = 0; i < lockWidgetCatalog.length; i++) {
      if (lockWidgetCatalog[i].id === t) {
        found = lockWidgetCatalog[i]
        break
      }
    }
    if (!found)
      return null
    let list = lockWidgetsList.slice()
    for (let i = 0; i < list.length; i++) {
      if (String(list[i].type) === t) {
        if (!list[i].enabled)
          setLockWidgetEnabled(list[i].id, true)
        if (size)
          setLockWidgetSize(list[i].id, size)
        return list[i]
      }
    }
    const stripCount = list.filter(w => w.type !== "clock").length
    const w = normalizeLockWidget({
      id: lockWidgetIdNew(),
      type: t,
      enabled: true,
      showControls: true,
      showWhenIdle: t === "media",
      size: size || found.defaultSize || "md",
      slot: stripCount
    })
    list.push(w)
    lockWidgets = compactLockWidgetSlots(list)
    if (t === "clock")
      lockShowClock = true
    flushSettings()
    return w
  }

  function removeLockWidget(id) {
    const sid = String(id || "")
    let target = null
    for (let i = 0; i < lockWidgetsList.length; i++) {
      if (String(lockWidgetsList[i].id) === sid) {
        target = lockWidgetsList[i]
        break
      }
    }
    if (target && target.type === "clock")
      return
    const next = lockWidgetsList.filter(w => String(w.id) !== sid)
    lockWidgets = compactLockWidgetSlots(next)
    lockShowClock = lockHasClockWidget
    flushSettings()
  }

  function setLockWidgetEnabled(id, on) {
    patchLockWidget(id, {
      enabled: !!on
    })
    const list = lockWidgetsList
    for (let i = 0; i < list.length; i++) {
      if (String(list[i].id) === String(id) && list[i].type === "clock") {
        lockShowClock = !!on
        break
      }
    }
  }

  function patchLockWidget(id, patch) {
    const sid = String(id || "")
    const p = patch || {}
    let list = lockWidgetsList.map(w => {
      if (String(w.id) !== sid)
        return w
      return normalizeLockWidget(Object.assign({}, w, p, {
        id: w.id,
        type: w.type
      }))
    }).filter(w => w !== null)
    if (p && ("size" in p || "slot" in p))
      list = compactLockWidgetSlots(list)
    lockWidgets = list
    flushSettings()
  }

  function moveLockWidget(id, x, y) {
    // Map vertical position into strip reorder
    let ny = Number(y)
    if (isNaN(ny))
      ny = Number(x)
    if (isNaN(ny))
      return
    const strip = lockStripWidgets
    const slot = Math.max(0, Math.min(strip.length, Math.round(ny * Math.max(1, strip.length))))
    moveLockWidgetToSlot(id, slot)
  }

  function moveLockWidgetToSlot(id, slot) {
    const sid = String(id || "")
    let list = lockWidgetsList.slice()
    let item = null
    for (let i = 0; i < list.length; i++) {
      if (String(list[i].id) === sid) {
        item = list[i]
        break
      }
    }
    if (!item || item.type === "clock")
      return
    const others = list.filter(w => String(w.id) !== sid && w.type !== "clock")
    others.sort((a, b) => (a.slot - b.slot) || String(a.id).localeCompare(String(b.id)))
    const idx = Math.max(0, Math.min(others.length, Math.round(Number(slot) || 0)))
    others.splice(idx, 0, item)
    for (let i = 0; i < others.length; i++)
      others[i] = normalizeLockWidget(Object.assign({}, others[i], { slot: i }))
    const clocks = list.filter(w => w.type === "clock")
    lockWidgets = clocks.concat(others)
    flushSettings()
  }

  function setLockWidgetSize(id, size) {
    const s = String(size || "md")
    if (s !== "sm" && s !== "md" && s !== "lg")
      return
    patchLockWidget(id, {
      size: s,
      span: lockWidgetSpanForSize(s)
    })
  }

  function cycleLockWidgetSize(id) {
    let w = null
    const wid = String(id)
    for (let i = 0; i < lockWidgetsList.length; i++) {
      if (String(lockWidgetsList[i].id) === wid) {
        w = lockWidgetsList[i]
        break
      }
    }
    if (!w || w.type === "clock")
      return
    const order = ["sm", "md", "lg"]
    const i = order.indexOf(String(w.size || "md"))
    setLockWidgetSize(id, order[(i + 1) % order.length])
  }

  function lockHasWidgetType(type) {
    const t = String(type || "")
    const list = lockWidgetsList
    for (let i = 0; i < list.length; i++) {
      if (String(list[i].type) === t)
        return true
    }
    return false
  }

  function desktopWidgetIdNew() {
    return "dw-" + Math.random().toString(16).slice(2, 9)
  }

  function desktopWidgetSpanForSize(size) {
    return lockWidgetSpanForSize(size)
  }

  function clamp01(v, fallback) {
    const n = Number(v)
    if (isNaN(n))
      return fallback
    return Math.max(0, Math.min(1, n))
  }

  function nextDesktopWidgetPos(list) {
    const n = (list && list.length) ? list.length : 0
    return {
      x: Math.min(0.72, 0.08 + (n % 3) * 0.28),
      y: Math.min(0.68, 0.12 + Math.floor(n / 3) * 0.22)
    }
  }

  function normalizeDesktopWidget(w) {
    const type = String((w && w.type) || "")
    let meta = null
    for (let i = 0; i < desktopWidgetCatalog.length; i++) {
      if (desktopWidgetCatalog[i].id === type) {
        meta = desktopWidgetCatalog[i]
        break
      }
    }
    if (!meta)
      return null
    let size = String((w && w.size) || meta.defaultSize || "md")
    if (size !== "sm" && size !== "md" && size !== "lg")
      size = String(meta.defaultSize || "md")
    let weight = String((w && w.clockWeight) || "light")
    if (weight !== "light" && weight !== "normal" && weight !== "medium")
      weight = "light"
    let dateStyle = String((w && w.dateStyle) || "full")
    if (dateStyle !== "full" && dateStyle !== "short")
      dateStyle = "full"
    let clockColor = String((w && w.clockColor) || "#f5f5f7")
    if (!clockColor.length || clockColor.charAt(0) !== "#")
      clockColor = "#f5f5f7"
    return {
      id: String((w && w.id) || desktopWidgetIdNew()),
      type: type,
      label: String(meta.label || type),
      enabled: w && w.enabled === false ? false : true,
      x: clamp01(w && w.x, 0.5),
      y: clamp01(w && w.y, 0.2),
      size: size,
      span: desktopWidgetSpanForSize(size),
      showControls: w && w.showControls === false ? false : true,
      showWhenIdle: !!(w && w.showWhenIdle),
      clockWeight: weight,
      clockColor: clockColor,
      showDate: w && w.showDate === false ? false : true,
      dateStyle: dateStyle,
      clockDepth: w && w.clockDepth === false ? false : true
    }
  }

  function hydrateDesktopWidgetsFromFile() {
    try {
      const raw = configFile.text()
      if (raw && String(raw).trim().length) {
        const d = JSON.parse(String(raw))
        if (Array.isArray(d.desktopWidgets)) {
          desktopWidgets = d.desktopWidgets.map(w => normalizeDesktopWidget(w)).filter(w => w !== null)
          return
        }
      }
    } catch (e) {
    }
    if (!Array.isArray(desktopWidgets))
      desktopWidgets = []
  }

  function addDesktopWidget(type, size) {
    const t = String(type || "")
    let found = null
    for (let i = 0; i < desktopWidgetCatalog.length; i++) {
      if (desktopWidgetCatalog[i].id === t) {
        found = desktopWidgetCatalog[i]
        break
      }
    }
    if (!found)
      return null
    let list = desktopWidgetsList.slice()
    for (let i = 0; i < list.length; i++) {
      if (String(list[i].type) === t) {
        if (!list[i].enabled)
          setDesktopWidgetEnabled(list[i].id, true)
        if (size)
          setDesktopWidgetSize(list[i].id, size)
        return list[i]
      }
    }
    const pos = nextDesktopWidgetPos(list)
    const w = normalizeDesktopWidget({
      id: desktopWidgetIdNew(),
      type: t,
      enabled: true,
      showControls: true,
      showWhenIdle: t === "media",
      size: size || found.defaultSize || "md",
      x: pos.x,
      y: pos.y
    })
    list.push(w)
    desktopWidgets = list
    flushSettings()
    return w
  }

  function removeDesktopWidget(id) {
    const sid = String(id || "")
    desktopWidgets = desktopWidgetsList.filter(w => String(w.id) !== sid)
    flushSettings()
  }

  function setDesktopWidgetEnabled(id, on) {
    patchDesktopWidget(id, {
      enabled: !!on
    })
  }

  function patchDesktopWidget(id, patch) {
    const sid = String(id || "")
    const p = patch || {}
    desktopWidgets = desktopWidgetsList.map(w => {
      if (String(w.id) !== sid)
        return w
      return normalizeDesktopWidget(Object.assign({}, w, p, {
        id: w.id,
        type: w.type
      }))
    }).filter(w => w !== null)
    flushSettings()
  }

  function moveDesktopWidget(id, x, y) {
    patchDesktopWidget(id, {
      x: clamp01(x, 0.5),
      y: clamp01(y, 0.2)
    })
  }

  function setDesktopWidgetSize(id, size) {
    const s = String(size || "md")
    if (s !== "sm" && s !== "md" && s !== "lg")
      return
    patchDesktopWidget(id, {
      size: s,
      span: desktopWidgetSpanForSize(s)
    })
  }

  function cycleDesktopWidgetSize(id) {
    let w = null
    const wid = String(id)
    for (let i = 0; i < desktopWidgetsList.length; i++) {
      if (String(desktopWidgetsList[i].id) === wid) {
        w = desktopWidgetsList[i]
        break
      }
    }
    if (!w)
      return
    const order = ["sm", "md", "lg"]
    const i = order.indexOf(String(w.size || "md"))
    setDesktopWidgetSize(id, order[(i + 1) % order.length])
  }

  function desktopHasWidgetType(type) {
    const t = String(type || "")
    const list = desktopWidgetsList
    for (let i = 0; i < list.length; i++) {
      if (String(list[i].type) === t)
        return true
    }
    return false
  }

  function setWallpaperKind(kind) {
    // Browse-only helper (Settings UI uses local browseKind). Do not apply —
    // writing wallpaperKind alone would hot-reload the desktop background.
    const k = String(kind || "")
    if (k !== "color" && k !== "image" && k !== "daily" && k !== "video" && k !== "reactive")
      return
    if (k === "image")
      scanWallpaperFolder()
  }

  function setWallpaperColor(hex) {
    const n = normalizeAccentHex(hex)
    if (!n.length)
      return false
    wallpaperColor = n
    wallpaperKind = "color"
    applyBackground()
    return true
  }

  function setWallpaper(id) {
    wallpaperId = id
    wallpaperKind = "image"
    applyBackground()
  }

  function setWallpaperDailyProvider(id) {
    patchActiveDailySource({
      provider: String(id || "bing")
    })
  }

  function setWallpaperDailyUrl(url) {
    patchActiveDailySource({
      url: String(url || "").trim()
    })
  }

  function setWallpaperDailyApiKey(key) {
    patchActiveDailySource({
      apiKey: String(key || "")
    })
  }

  function setWallpaperDailyAuth(mode) {
    patchActiveDailySource({
      auth: String(mode || "none")
    })
  }

  function setWallpaperDailyMarket(mkt) {
    patchActiveDailySource({
      market: String(mkt || "en-US").trim() || "en-US"
    })
  }

  function setWallpaperDailyRefreshHours(hours) {
    const n = Math.max(1, Math.min(48, Math.round(Number(hours) || 6)))
    wallpaperDailyRefreshHours = n
    flushSettings()
  }

  function dailySourceIdNew() {
    return "daily-" + Date.now().toString(36) + "-" + Math.floor(Math.random() * 1e4).toString(36)
  }

  function defaultDailySource(provider) {
    const p = String(provider || "bing")
    let label = "Bing"
    let auth = "none"
    let url = ""
    if (p === "unsplash") {
      label = "Unsplash"
      auth = "client-id"
      url = "https://api.unsplash.com/photos/random?orientation=landscape"
    } else if (p === "custom") {
      label = "Custom feed"
      auth = "none"
    }
    return {
      id: dailySourceIdNew(),
      label: label,
      provider: p,
      url: url,
      apiKey: "",
      auth: auth,
      market: "en-US"
    }
  }

  function normalizeDailySource(s) {
    return {
      id: String((s && s.id) || dailySourceIdNew()),
      label: String((s && s.label) || "Source"),
      provider: String((s && s.provider) || "bing"),
      url: String((s && s.url) || ""),
      apiKey: String((s && s.apiKey) || ""),
      auth: String((s && s.auth) || "none"),
      market: String((s && s.market) || "en-US")
    }
  }

  function hydrateDailySourcesFromFile() {
    try {
      const raw = configFile.text()
      if (raw && String(raw).trim().length) {
        const d = JSON.parse(String(raw))
        if (Array.isArray(d.wallpaperDailySources) && d.wallpaperDailySources.length) {
          wallpaperDailySources = d.wallpaperDailySources.map(s => normalizeDailySource(s))
          if (d.wallpaperDailySourceId)
            wallpaperDailySourceId = String(d.wallpaperDailySourceId)
        }
      }
    } catch (e) {
    }
    ensureDailySources()
  }

  function resolveActiveDailySource() {
    const list = wallpaperDailySourcesList
    if (!list.length)
      return null
    const id = String(wallpaperDailySourceId || "")
    for (let i = 0; i < list.length; i++) {
      if (String(list[i].id) === id)
        return list[i]
    }
    return list[0]
  }

  function ensureDailySources() {
    let list = Array.isArray(wallpaperDailySources) ? wallpaperDailySources.slice() : []
    if (list.length) {
      const id = String(wallpaperDailySourceId || "")
      let found = false
      for (let i = 0; i < list.length; i++) {
        if (String(list[i].id) === id) {
          found = true
          break
        }
      }
      if (!found)
        wallpaperDailySourceId = String(list[0].id)
      syncDailyLegacyFromActive()
      return list
    }
    // Migrate legacy flat fields into one source
    const legacy = defaultDailySource(wallpaperDailyProvider || "bing")
    if (wallpaperDailyUrl && String(wallpaperDailyUrl).length)
      legacy.url = String(wallpaperDailyUrl)
    if (wallpaperDailyApiKey && String(wallpaperDailyApiKey).length)
      legacy.apiKey = String(wallpaperDailyApiKey)
    if (wallpaperDailyAuth && String(wallpaperDailyAuth).length)
      legacy.auth = String(wallpaperDailyAuth)
    if (wallpaperDailyMarket && String(wallpaperDailyMarket).length)
      legacy.market = String(wallpaperDailyMarket)
    if (legacy.provider === "bing")
      legacy.label = "Bing"
    else if (legacy.provider === "unsplash")
      legacy.label = "Unsplash"
    list = [legacy]
    wallpaperDailySources = list
    wallpaperDailySourceId = legacy.id
    syncDailyLegacyFromActive()
    return list
  }

  function syncDailyLegacyFromActive() {
    const src = resolveActiveDailySource()
    if (!src)
      return
    wallpaperDailyProvider = String(src.provider || "bing")
    wallpaperDailyUrl = String(src.url || "")
    wallpaperDailyApiKey = String(src.apiKey || "")
    wallpaperDailyAuth = String(src.auth || "none")
    wallpaperDailyMarket = String(src.market || "en-US")
  }

  function patchActiveDailySource(patch) {
    ensureDailySources()
    let sid = String(wallpaperDailySourceId || "")
    const resolved = resolveActiveDailySource()
    if (resolved)
      sid = String(resolved.id)
    wallpaperDailySourceId = sid
    const list = wallpaperDailySourcesList.map(s => {
      if (String(s.id) !== sid)
        return s
      const next = {
        id: s.id,
        label: s.label,
        provider: s.provider,
        url: s.url || "",
        apiKey: s.apiKey || "",
        auth: s.auth || "none",
        market: s.market || "en-US"
      }
      if (patch.label !== undefined)
        next.label = String(patch.label)
      if (patch.provider !== undefined) {
        next.provider = String(patch.provider)
        if (next.provider === "unsplash" && (next.auth === "none" || !next.auth))
          next.auth = "client-id"
      }
      if (patch.url !== undefined)
        next.url = String(patch.url)
      if (patch.apiKey !== undefined)
        next.apiKey = String(patch.apiKey)
      if (patch.auth !== undefined)
        next.auth = String(patch.auth)
      if (patch.market !== undefined)
        next.market = String(patch.market || "en-US")
      return next
    })
    wallpaperDailySources = list
    syncDailyLegacyFromActive()
    flushSettings()
  }

  function addDailySource(provider) {
    ensureDailySources()
    const src = defaultDailySource(provider)
    // Unique label if duplicates
    const base = src.label
    let n = 2
    const labels = wallpaperDailySourcesList.map(s => String(s.label))
    while (labels.indexOf(src.label) >= 0) {
      src.label = base + " " + n
      n++
    }
    wallpaperDailySources = wallpaperDailySourcesList.concat([src])
    setDailySource(src.id, false)
  }

  function setDailySource(id, fetchIfActive) {
    ensureDailySources()
    const sid = String(id || "")
    let found = null
    const list = wallpaperDailySourcesList
    for (let i = 0; i < list.length; i++) {
      if (String(list[i].id) === sid) {
        found = list[i]
        break
      }
    }
    if (!found && list.length)
      found = list[0]
    if (!found)
      return
    const changed = String(wallpaperDailySourceId) !== String(found.id)
    wallpaperDailySourceId = String(found.id)
    syncDailyLegacyFromActive()
    wallpaperDailyError = ""
    flushSettings()
    if (fetchIfActive && changed && (wallpaperKind === "daily" || wallpaperId === "daily"))
      refreshDailyWallpaper(true)
  }

  function removeDailySource(id) {
    ensureDailySources()
    const sid = String(id || "")
    let list = wallpaperDailySourcesList.filter(s => String(s.id) !== sid)
    if (!list.length)
      list = [defaultDailySource("bing")]
    wallpaperDailySources = list
    if (String(wallpaperDailySourceId) === sid || !list.some(s => String(s.id) === String(wallpaperDailySourceId)))
      setDailySource(list[0].id, wallpaperKind === "daily" || wallpaperId === "daily")
    else {
      syncDailyLegacyFromActive()
      flushSettings()
    }
  }

  function renameDailySource(id, label) {
    const sid = String(id || "")
    const name = String(label || "").trim()
    if (!sid.length || !name.length)
      return
    ensureDailySources()
    wallpaperDailySources = wallpaperDailySourcesList.map(s => {
      if (String(s.id) !== sid)
        return s
      return {
        id: s.id,
        label: name,
        provider: s.provider,
        url: s.url || "",
        apiKey: s.apiKey || "",
        auth: s.auth || "none",
        market: s.market || "en-US"
      }
    })
    syncDailyLegacyFromActive()
    flushSettings()
  }

  function setWallpaperDaily() {
    ensureDailySources()
    wallpaperSlideshow = false
    wallpaperId = "daily"
    wallpaperKind = "daily"
    refreshDailyWallpaper(true)
  }

  function refreshDailyWallpaper(applyAfter) {
    if (wallpaperDailyFetchProc.running)
      return
    ensureDailySources()
    const src = resolveActiveDailySource()

    const plan = dailyFetchPlan(src, defaultDailyWallpaperDir)
    if (!plan.ok) {
      wallpaperDailyError = plan.error
      wallpaperDailyFetching = false
      return
    }
    // Keep sourceId aligned with the resolved profile
    if (String(wallpaperDailySourceId) !== String(src.id))
      wallpaperDailySourceId = String(src.id)
    syncDailyLegacyFromActive()

    wallpaperDailyFetching = true
    wallpaperDailyError = ""
    flushSettings()

    // Source fields go on the CLI so fetch does not race FileView writeAdapter.
    wallpaperDailyFetchProc.command = plan.command
    // Key goes through the environment — argv is world-readable via /proc.
    wallpaperDailyFetchProc.environment = ({ "PROTEUS_DAILY_API_KEY": plan.apiKey })
    wallpaperDailyFetchProc.applyAfter = !!applyAfter
    wallpaperDailyFetchProc.running = false
    wallpaperDailyFetchProc.running = true
  }

  function setCustomWallpaper(path) {
    const p = String(path || "").trim()
    if (!p.length)
      return
    wallpaperCustomPath = p
    wallpaperId = "custom"
    wallpaperKind = "image"
    applyBackground()
  }

  function clearCustomWallpaper() {
    wallpaperId = "default"
    wallpaperKind = "image"
    applyBackground()
  }

  function setWallpaperMode(mode) {
    wallpaperMode = mode
    if (wallpaperKind === "image")
      applyBackground()
  }

  function setWallpaperFolder(path) {
    // Back-compat: treating "choose folder" as add/select album
    addWallpaperAlbum(path)
  }

  function albumIdFromPath(path) {
    const p = String(path || "").trim()
    let h = 0
    for (let i = 0; i < p.length; i++)
      h = ((h << 5) - h + p.charCodeAt(i)) | 0
    return "album-" + Math.abs(h).toString(16)
  }

  function albumLabelFromPath(path) {
    const p = String(path || "").replace(/\/+$/, "")
    const parts = p.split("/")
    const base = parts.length ? parts[parts.length - 1] : ""
    return base.length ? base : "Album"
  }

  function ensureWallpaperAlbums() {
    let list = Array.isArray(wallpaperAlbums) ? wallpaperAlbums.slice() : []
    if (list.length)
      return list
    // Migrate legacy single folder (or default library) into one album
    const path = (wallpaperFolder && String(wallpaperFolder).length)
        ? String(wallpaperFolder)
        : defaultWallpaperFolder
    list = [
      {
        id: albumIdFromPath(path),
        label: albumLabelFromPath(path),
        path: path
      }
    ]
    wallpaperAlbums = list
    if (!String(wallpaperAlbumId || "").length)
      wallpaperAlbumId = list[0].id
    if (!String(wallpaperFolder || "").length)
      wallpaperFolder = path
    return list
  }

  function addWallpaperAlbum(path) {
    const p = String(path || "").trim()
    if (!p.length)
      return
    let list = ensureWallpaperAlbums()
    const id = albumIdFromPath(p)
    for (let i = 0; i < list.length; i++) {
      if (String(list[i].path) === p || String(list[i].id) === id) {
        setWallpaperAlbum(list[i].id)
        return
      }
    }
    list = list.concat([
      {
        id: id,
        label: albumLabelFromPath(p),
        path: p
      }
    ])
    wallpaperAlbums = list
    setWallpaperAlbum(id)
  }

  function setWallpaperAlbum(id) {
    ensureWallpaperAlbums()
    const sid = String(id || "")
    const list = wallpaperAlbumsList
    let album = null
    for (let i = 0; i < list.length; i++) {
      if (String(list[i].id) === sid) {
        album = list[i]
        break
      }
    }
    if (!album && list.length)
      album = list[0]
    if (!album)
      return
    wallpaperAlbumId = String(album.id)
    wallpaperFolder = String(album.path || "")
    wallpaperKind = "image"
    scanWallpaperFolder()
    if (wallpaperSlideshow)
      applyBackground()
  }

  function removeWallpaperAlbum(id) {
    const sid = String(id || "")
    let list = ensureWallpaperAlbums().filter(a => String(a.id) !== sid)
    if (!list.length) {
      const path = defaultWallpaperFolder
      list = [
        {
          id: albumIdFromPath(path),
          label: albumLabelFromPath(path),
          path: path
        }
      ]
    }
    wallpaperAlbums = list
    if (String(wallpaperAlbumId) === sid || !list.some(a => String(a.id) === String(wallpaperAlbumId)))
      setWallpaperAlbum(list[0].id)
    else
      scanWallpaperFolder()
  }

  function renameWallpaperAlbum(id, label) {
    const sid = String(id || "")
    const name = String(label || "").trim()
    if (!sid.length || !name.length)
      return
    const list = ensureWallpaperAlbums().map(a => {
      if (String(a.id) !== sid)
        return a
      return {
        id: a.id,
        label: name,
        path: a.path
      }
    })
    wallpaperAlbums = list
  }

  function setWallpaperVideo(path) {
    const p = String(path || "").trim()
    if (!p.length)
      return
    wallpaperVideoPath = p
    wallpaperKind = "video"
    applyBackground()
  }

  function clearWallpaperVideo() {
    wallpaperVideoPath = ""
    wallpaperKind = "image"
    applyBackground()
  }

  function setWallpaperReactive(id) {
    const rid = String(id || "")
    let ok = false
    for (let i = 0; i < wallpaperReactives.length; i++) {
      if (wallpaperReactives[i].id === rid)
        ok = true
    }
    if (!ok)
      return
    wallpaperReactiveId = rid
    wallpaperKind = "reactive"
    applyBackground()
  }

  function pickWallpaperFile() {
    // Qt FileDialog in StylePane opens the picker.
  }

  function pickWallpaperFolder() {
  }

  function pickWallpaperVideo() {
  }

  function scanWallpaperFolder(dirOverride) {
    if (wallpaperScanProc.running)
      return
    wallpaperFolderScanning = true
    const resolved = (dirOverride && String(dirOverride).length)
        ? String(dirOverride)
        : wallpaperFolderResolved
    const dir = JSON.stringify(resolved)
    wallpaperScanProc.command = [
      "python3",
      "-c",
      "import json, pathlib, sys\n"
          + "root = pathlib.Path(" + dir + ")\n"
          + "ext = {'.png','.jpg','.jpeg','.webp','.bmp','.gif'}\n"
          + "out = []\n"
          + "if root.is_dir():\n"
          + "  for p in sorted(root.iterdir()):\n"
          + "    if p.is_file() and p.suffix.lower() in ext:\n"
          + "      out.append({'path': str(p), 'label': p.stem})\n"
          + "print(json.dumps(out))\n"
    ]
    wallpaperScanProc.running = false
    wallpaperScanProc.running = true
  }

  function stopBackgroundBackends() {
    // Clear legacy shims + previous runner instances
    return "pkill -x swaybg 2>/dev/null || true; "
        + "pkill -x mpvpaper 2>/dev/null || true; "
        + "pkill -x proteus-bg 2>/dev/null || true; "
        + "pkill -f 'quickshell -p .*/shell/wallpaper' 2>/dev/null || true; "
        + "for i in 1 2 3 4 5 6 7 8 9 10; do "
        + "  pgrep -x swaybg >/dev/null || pgrep -x mpvpaper >/dev/null || pgrep -x proteus-bg >/dev/null || break; "
        + "  sleep 0.05; "
        + "done; "
  }

  function flushSettings() {
    if (!settingsReady)
      return
    try {
      configFile.writeAdapter()
    } catch (e) {
    }
  }

  function applyBackground() {
    // Flush first so a cold start doesn't race on stale wallpaper*.
    // If proteus-bg is already up, nudge FileView watchers — do NOT kill/restart
    // (that breaks video loops and reactive animations on every pick).
    flushSettings()
    const wallDir = shellQuote(wallpaperDir)
    Quickshell.execDetached({
      command: [
        "bash",
        "-c",
        "export QT_QPA_PLATFORM=\"${QT_QPA_PLATFORM:-wayland}\"; "
            + "pkill -x swaybg 2>/dev/null || true; "
            + "pkill -x mpvpaper 2>/dev/null || true; "
            + "if pgrep -x proteus-bg >/dev/null || pgrep -f 'quickshell -p .*/shell/wallpaper' >/dev/null; then "
            + "  touch \"$HOME/.config/proteus/settings.json\" 2>/dev/null || true; "
            + "  exit 0; "
            + "fi; "
            + "if [[ -x /usr/local/bin/proteus-bg ]]; then exec /usr/local/bin/proteus-bg; "
            + "elif [[ -x \"$HOME/.local/bin/proteus-bg\" ]]; then exec \"$HOME/.local/bin/proteus-bg\"; "
            + "elif [[ -x /mnt/proteus/vm/guest/proteus-bg ]]; then exec /mnt/proteus/vm/guest/proteus-bg; "
            + "elif command -v proteus-bg >/dev/null 2>&1; then exec proteus-bg; "
            + "else exec quickshell -p " + wallDir + "; fi"
      ]
    })
  }

  function applyWallpaper() {
    applyBackground()
  }

  Process {
    id: wallpaperScanProc
    command: ["true"]
    stdout: StdioCollector {
      onStreamFinished: {
        root.wallpaperFolderScanning = false
        try {
          const list = JSON.parse(text.trim() || "[]")
          root.wallpaperFolderEntries = Array.isArray(list) ? list : []
        } catch (e) {
          root.wallpaperFolderEntries = []
        }
      }
    }
  }

  Process {
    id: wallpaperDailyFetchProc
    property bool applyAfter: true
    command: ["true"]
    stdout: StdioCollector {
      onStreamFinished: {
        root.wallpaperDailyFetching = false
        const res = root.parseDailyResult(text, "Daily")
        if (!res.ok) {
          root.wallpaperDailyError = res.error
          return
        }
        root.wallpaperDailyError = ""
        if (res.path.length)
          root.wallpaperDailyPath = res.path
        root.wallpaperDailyTitle = res.title
        root.wallpaperDailyCopyright = res.copyright
        root.wallpaperDailyFetchedAt = res.fetchedAt
        root.flushSettings()
        // Desktop-only: the background is drawn by proteus-bg, so it has to be
        // signalled. The lock surface renders in-process and needs no nudge.
        if (wallpaperDailyFetchProc.applyAfter || root.wallpaperKind === "daily" || root.wallpaperId === "daily") {
          root.wallpaperId = "daily"
          root.wallpaperKind = "daily"
          root.applyBackground()
        }
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        const err = text.trim()
        if (err.length && root.wallpaperDailyFetching)
          root.wallpaperDailyError = err.split("\n")[0]
      }
    }
  }

  Process {
    id: lockDailyFetchProc
    command: ["true"]
    stdout: StdioCollector {
      onStreamFinished: {
        root.lockDailyFetching = false
        const res = root.parseDailyResult(text, "Lock daily")
        if (!res.ok) {
          root.lockDailyError = res.error
          return
        }
        root.lockDailyError = ""
        if (res.path.length)
          root.lockDailyPath = res.path
        root.lockBackgroundMode = "daily"
        root.flushSettings()
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        const err = text.trim()
        if (err.length && root.lockDailyFetching)
          root.lockDailyError = err.split("\n")[0]
      }
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
      root.hydrateDailySourcesFromFile()
      root.hydrateLockWidgetsFromFile()
      root.hydrateDesktopWidgetsFromFile()
      root.settingsReady = true
    }
    onLoadFailed: error => {
      writeAdapter()
      root.settingsReady = true
      root.ensureDailySources()
      root.hydrateLockWidgetsFromFile()
      root.hydrateDesktopWidgetsFromFile()
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

  Process {
    id: generalWriteProc
    command: ["true"]
  }

  Component.onCompleted: {
    applyHyprland()
    Audio.applyAudioLatency()
    Hardware.refresh()
  }
}
