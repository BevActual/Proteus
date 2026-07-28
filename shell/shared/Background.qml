pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Desktop + lock wallpaper / daily sources / apply background.
//
// Extracted from Config.qml. Persisted keys stay on Config (one FileView);
// this singleton owns catalogs, derived paths, setters, and fetch processes.
Singleton {
  id: root

  // Folder scan / daily fetch runtime (not persisted)
  property var wallpaperFolderEntries: []
  property bool wallpaperFolderScanning: false
  property bool wallpaperDailyFetching: false
  property string wallpaperDailyError: ""
  property bool lockDailyFetching: false
  property string lockDailyError: ""
  // Runtime-only lock album slideshow cursor (not persisted)
  property string lockSlideshowPath: ""
  property int lockSlideshowIndex: 0

  // Persisted wallpaper / lock backdrop keys — owned by Config FileView.
  property alias lockBackgroundMode: Config.lockBackgroundMode
  property alias lockWallpaperId: Config.lockWallpaperId
  property alias lockWallpaperCustomPath: Config.lockWallpaperCustomPath
  property alias lockWallpaperColor: Config.lockWallpaperColor
  property alias lockDailySourceId: Config.lockDailySourceId
  property alias lockDailyPath: Config.lockDailyPath
  property alias lockDim: Config.lockDim
  property alias lockWallpaperVideoPath: Config.lockWallpaperVideoPath
  property alias lockWallpaperReactiveId: Config.lockWallpaperReactiveId
  property alias lockWallpaperMode: Config.lockWallpaperMode
  property alias lockWallpaperAlbumId: Config.lockWallpaperAlbumId
  property alias lockWallpaperSlideshow: Config.lockWallpaperSlideshow
  property alias lockWallpaperSlideshowSecs: Config.lockWallpaperSlideshowSecs
  property alias lockWallpaperShuffle: Config.lockWallpaperShuffle
  property alias wallpaperKind: Config.wallpaperKind
  property alias wallpaperColor: Config.wallpaperColor
  property alias wallpaperId: Config.wallpaperId
  property alias wallpaperCustomPath: Config.wallpaperCustomPath
  property alias wallpaperMode: Config.wallpaperMode
  property alias wallpaperFolder: Config.wallpaperFolder
  property alias wallpaperAlbumId: Config.wallpaperAlbumId
  property alias wallpaperAlbums: Config.wallpaperAlbums
  property alias wallpaperVideoPath: Config.wallpaperVideoPath
  property alias wallpaperReactiveId: Config.wallpaperReactiveId
  property alias wallpaperSlideshow: Config.wallpaperSlideshow
  property alias wallpaperSlideshowSecs: Config.wallpaperSlideshowSecs
  property alias wallpaperShuffle: Config.wallpaperShuffle
  property alias wallpaperDailyProvider: Config.wallpaperDailyProvider
  property alias wallpaperDailyUrl: Config.wallpaperDailyUrl
  property alias wallpaperDailyApiKey: Config.wallpaperDailyApiKey
  property alias wallpaperDailyAuth: Config.wallpaperDailyAuth
  property alias wallpaperDailyMarket: Config.wallpaperDailyMarket
  property alias wallpaperDailyRefreshHours: Config.wallpaperDailyRefreshHours
  property alias wallpaperDailyPath: Config.wallpaperDailyPath
  property alias wallpaperDailyTitle: Config.wallpaperDailyTitle
  property alias wallpaperDailyCopyright: Config.wallpaperDailyCopyright
  property alias wallpaperDailyFetchedAt: Config.wallpaperDailyFetchedAt
  property alias wallpaperDailySources: Config.wallpaperDailySources
  property alias wallpaperDailySourceId: Config.wallpaperDailySourceId

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
      const h = Config.normalizeAccentHex(lockWallpaperColor)
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

  function setLockDim(v) {
    const n = Number(v)
    if (isNaN(n))
      return
    lockDim = Math.round(Math.max(0, Math.min(0.75, n)) * 100) / 100
    Config.flushSettings()
  }

  function setLockBackgroundMode(mode) {
    const m = String(mode || "match")
    if (m !== "match" && m !== "image" && m !== "color" && m !== "daily" && m !== "video" && m !== "reactive")
      return
    lockBackgroundMode = m
    Config.flushSettings()
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
    Config.flushSettings()
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
    Config.flushSettings()
    scanWallpaperFolder(album.path)
    if (lockWallpaperSlideshow)
      advanceLockSlideshow()
  }

  function setLockWallpaperSlideshow(on) {
    lockWallpaperSlideshow = !!on
    lockBackgroundMode = "image"
    Config.flushSettings()
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
    Config.flushSettings()
  }

  function setLockWallpaperShuffle(on) {
    lockWallpaperShuffle = !!on
    Config.flushSettings()
  }

  function setLockWallpaperVideo(path) {
    const p = String(path || "").trim()
    if (!p.length)
      return
    lockWallpaperVideoPath = p
    lockBackgroundMode = "video"
    Config.flushSettings()
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
    Config.flushSettings()
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
    Config.flushSettings()
  }

  function setLockCustomWallpaper(path) {
    const p = String(path || "").trim()
    if (!p.length)
      return
    lockWallpaperCustomPath = p
    lockWallpaperId = "custom"
    lockBackgroundMode = "image"
    Config.flushSettings()
  }

  function setLockWallpaperColor(hex) {
    const n = Config.normalizeAccentHex(hex)
    if (!n.length)
      return false
    lockWallpaperColor = n
    lockBackgroundMode = "color"
    Config.flushSettings()
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
    Config.flushSettings()
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
        Config.scriptsDir + "/fetch-daily-wallpaper.py",
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
    Config.flushSettings()

    lockDailyFetchProc.command = plan.command
    // Key goes through the environment — argv is world-readable via /proc.
    lockDailyFetchProc.environment = ({ "PROTEUS_DAILY_API_KEY": plan.apiKey })
    lockDailyFetchProc.running = false
    lockDailyFetchProc.running = true
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
    const n = Config.normalizeAccentHex(hex)
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
    Config.flushSettings()
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
    hydrateDailyFromRaw("")
  }

  function hydrateDailyFromRaw(raw) {
    try {
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
    Config.flushSettings()
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
    Config.flushSettings()
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
      Config.flushSettings()
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
    Config.flushSettings()
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
    Config.flushSettings()

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


  function applyBackground() {
    // Flush first so a cold start doesn't race on stale wallpaper*.
    // If proteus-bg is already up, nudge FileView watchers — do NOT kill/restart
    // (that breaks video loops and reactive animations on every pick).
    Config.flushSettings()
    const wallDir = Config.shellQuote(wallpaperDir)
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
        Config.flushSettings()
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
        Config.flushSettings()
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

}
