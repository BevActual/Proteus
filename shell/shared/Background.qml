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

  BackgroundCatalog { id: catalog }
  BackgroundDaily { id: daily; host: root }
  BackgroundApply { id: apply; host: root }

  readonly property alias lockBackgroundModes: catalog.lockBackgroundModes
  readonly property alias wallpaperKinds: catalog.wallpaperKinds
  readonly property alias wallpaperColors: catalog.wallpaperColors
  readonly property alias wallpaperReactives: catalog.wallpaperReactives
  readonly property alias wallpaperDailyProviders: catalog.wallpaperDailyProviders
  readonly property alias wallpaperDailyAuthModes: catalog.wallpaperDailyAuthModes


  readonly property string defaultLockDailyDir: defaultWallpaperFolder + "/daily/lock"

  readonly property var activeLockWallpaperAlbum: {
    const list = wallpaperAlbumsList
    const id = String(Config.lockWallpaperAlbumId || "")
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
    const m = String(Config.lockBackgroundMode || "match")
    if (m === "color")
      return "color"
    if (m === "image" || m === "daily")
      return "image"
    if (m === "video")
      return "video"
    if (m === "reactive")
      return "reactive"
    // match
    const k = String(Config.wallpaperKind || "image")
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
    const m = String(Config.lockBackgroundMode || "match")
    if (m === "match")
      return String(Config.wallpaperMode || "fill")
    return String(Config.lockWallpaperMode || "fill")
  }

  readonly property string lockBackdropVideoPath: {
    const m = String(Config.lockBackgroundMode || "match")
    if (m === "video")
      return String(Config.lockWallpaperVideoPath || "")
    if (m === "match" && Config.wallpaperKind === "video")
      return String(Config.wallpaperVideoPath || "")
    return ""
  }

  readonly property string lockBackdropReactiveId: {
    const m = String(Config.lockBackgroundMode || "match")
    if (m === "reactive")
      return String(Config.lockWallpaperReactiveId || "drift")
    if (m === "match" && Config.wallpaperKind === "reactive")
      return String(Config.wallpaperReactiveId || "drift")
    return "drift"
  }

  readonly property string lockBackdropPath: {
    // Still-image path only (built-in / custom / daily). Album slideshow uses lockActiveImagePath.
    const m = String(Config.lockBackgroundMode || "match")
    if (m === "daily") {
      if (Config.lockDailyPath && String(Config.lockDailyPath).length)
        return String(Config.lockDailyPath)
      if (Config.wallpaperDailyPath && String(Config.wallpaperDailyPath).length)
        return String(Config.wallpaperDailyPath)
      return wallpapers[0].path
    }
    if (m === "image") {
      if (Config.lockWallpaperId === "custom" && Config.lockWallpaperCustomPath && String(Config.lockWallpaperCustomPath).length)
        return String(Config.lockWallpaperCustomPath)
      for (let i = 0; i < wallpapers.length; i++) {
        if (wallpapers[i].id === Config.lockWallpaperId)
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
    const m = String(Config.lockBackgroundMode || "match")
    if (m === "match") {
      if (Config.wallpaperKind === "image" && Config.wallpaperSlideshow && lockSlideshowPath && lockSlideshowPath.length)
        return lockSlideshowPath
      // When matching desktop slideshow, prefer desktop path; LockSurface may still advance lock cursor unused.
      return wallpaperPath
    }
    if (m === "image" && Config.lockWallpaperSlideshow && lockSlideshowPath && lockSlideshowPath.length)
      return lockSlideshowPath
    return lockBackdropPath
  }

  readonly property string lockBackdropColor: {
    const m = String(Config.lockBackgroundMode || "match")
    if (m === "color") {
      const h = Config.normalizeAccentHex(Config.lockWallpaperColor)
      return h.length ? h : "#0f1419"
    }
    if (m === "match" && Config.wallpaperKind === "color")
      return Config.wallpaperColor
    return "#0f1419"
  }

  readonly property real lockDimClamped: {
    const d = Number(Config.lockDim)
    if (isNaN(d))
      return 0.35
    return Math.max(0, Math.min(0.75, d))
  }

  readonly property var lockDailySourceResolved: {
    const list = wallpaperDailySourcesList
    const id = String(Config.lockDailySourceId || "")
    if (id.length) {
      for (let i = 0; i < list.length; i++) {
        if (String(list[i].id) === id)
          return list[i]
      }
    }
    return activeDailySource
  }

  readonly property string lockBackgroundSummary: {
    const m = String(Config.lockBackgroundMode || "match")
    if (m === "match")
      return "Match desktop · " + wallpaperSummary
    if (m === "color")
      return "Color · " + lockBackdropColor
    if (m === "video") {
      const p = String(Config.lockWallpaperVideoPath || "")
      const i = Math.max(p.lastIndexOf("/"), p.lastIndexOf("\\"))
      const base = i >= 0 ? p.slice(i + 1) : p
      return "Video · " + (base.length ? base : "none")
    }
    if (m === "reactive") {
      let label = String(Config.lockWallpaperReactiveId || "drift")
      for (let i = 0; i < wallpaperReactives.length; i++) {
        if (wallpaperReactives[i].id === Config.lockWallpaperReactiveId) {
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
    if (Config.lockWallpaperSlideshow)
      return "Image · slideshow · " + Config.lockWallpaperSlideshowSecs + "s"
    if (Config.lockWallpaperId === "custom")
      return "Image · custom · " + Config.lockWallpaperMode
    for (let i = 0; i < wallpapers.length; i++) {
      if (wallpapers[i].id === Config.lockWallpaperId)
        return "Image · " + wallpapers[i].label + " · " + Config.lockWallpaperMode
    }
    return "Image"
  }

  readonly property string defaultWallpaperFolder: Quickshell.env("HOME") + "/.local/share/proteus/backgrounds"
  readonly property string defaultDailyWallpaperDir: defaultWallpaperFolder + "/daily"

  readonly property var wallpaperAlbumsList: {
    const raw = Config.wallpaperAlbums
    if (Array.isArray(raw) && raw.length)
      return raw
    return []
  }

  readonly property var activeWallpaperAlbum: {
    const list = wallpaperAlbumsList
    const id = String(Config.wallpaperAlbumId || "")
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
    const f = (Config.wallpaperFolder && String(Config.wallpaperFolder).length) ? String(Config.wallpaperFolder) : defaultWallpaperFolder
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
    const raw = Config.wallpaperDailySources
    if (Array.isArray(raw) && raw.length)
      return raw
    return []
  }

  readonly property var activeDailySource: {
    const list = wallpaperDailySourcesList
    if (!list.length)
      return null
    const id = String(Config.wallpaperDailySourceId || "")
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
    const pid = src && src.provider ? String(src.provider) : String(Config.wallpaperDailyProvider || "bing")
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
    if ((Config.wallpaperKind === "daily" || Config.wallpaperId === "daily") && Config.wallpaperDailyPath && Config.wallpaperDailyPath.length)
      return Config.wallpaperDailyPath
    if (Config.wallpaperId === "custom" && Config.wallpaperCustomPath && Config.wallpaperCustomPath.length)
      return Config.wallpaperCustomPath
    for (let i = 0; i < wallpapers.length; i++) {
      if (wallpapers[i].id === Config.wallpaperId)
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
    const p = Config.wallpaperVideoPath || ""
    const i = Math.max(p.lastIndexOf("/"), p.lastIndexOf("\\"))
    return i >= 0 ? p.slice(i + 1) : p
  }

  readonly property string wallpaperReactiveLabel: {
    for (let i = 0; i < wallpaperReactives.length; i++) {
      if (wallpaperReactives[i].id === Config.wallpaperReactiveId)
        return wallpaperReactives[i].label
    }
    return Config.wallpaperReactiveId
  }

  readonly property string wallpaperKindLabel: {
    for (let i = 0; i < wallpaperKinds.length; i++) {
      if (wallpaperKinds[i].id === Config.wallpaperKind)
        return wallpaperKinds[i].label
    }
    return Config.wallpaperKind
  }

  readonly property string wallpaperSummary: {
    if (Config.wallpaperKind === "color")
      return "Color · " + Config.wallpaperColor
    if (Config.wallpaperKind === "video")
      return "Video · " + (wallpaperVideoBasename.length ? wallpaperVideoBasename : "none")
    if (Config.wallpaperKind === "reactive")
      return "Animated · " + wallpaperReactiveLabel
    if (Config.wallpaperKind === "daily" || Config.wallpaperId === "daily") {
      const t = Config.wallpaperDailyTitle && Config.wallpaperDailyTitle.length
          ? Config.wallpaperDailyTitle
          : activeDailySourceLabel
      return "Daily · " + activeDailySourceLabel + (t !== activeDailySourceLabel ? (" · " + t) : "")
    }
    if (Config.wallpaperSlideshow)
      return "Image · slideshow · " + Config.wallpaperSlideshowSecs + "s"
    if (Config.wallpaperId === "custom")
      return "Image · " + (wallpaperBasename.length ? wallpaperBasename : "Custom") + " · " + Config.wallpaperMode
    for (let i = 0; i < wallpapers.length; i++) {
      if (wallpapers[i].id === Config.wallpaperId)
        return "Image · " + wallpapers[i].label + " · " + Config.wallpaperMode
    }
    return "Image · " + Config.wallpaperMode
  }

  // Forwarders — setters → BackgroundDaily
  function setWallpaperSlideshow(on) { return daily.setWallpaperSlideshow(on) }
  function setWallpaperSlideshowSecs(secs) { return daily.setWallpaperSlideshowSecs(secs) }
  function setWallpaperShuffle(on) { return daily.setWallpaperShuffle(on) }
  function setLockDim(v) { return daily.setLockDim(v) }
  function setLockBackgroundMode(mode) { return daily.setLockBackgroundMode(mode) }
  function setLockWallpaperMode(mode) { return daily.setLockWallpaperMode(mode) }
  function setLockWallpaperAlbum(id) { return daily.setLockWallpaperAlbum(id) }
  function setLockWallpaperSlideshow(on) { return daily.setLockWallpaperSlideshow(on) }
  function setLockWallpaperSlideshowSecs(secs) { return daily.setLockWallpaperSlideshowSecs(secs) }
  function setLockWallpaperShuffle(on) { return daily.setLockWallpaperShuffle(on) }
  function setLockWallpaperVideo(path) { return daily.setLockWallpaperVideo(path) }
  function setLockWallpaperReactive(id) { return daily.setLockWallpaperReactive(id) }
  function advanceLockSlideshow() { return daily.advanceLockSlideshow() }
  function setLockWallpaper(id) { return daily.setLockWallpaper(id) }
  function setLockCustomWallpaper(path) { return daily.setLockCustomWallpaper(path) }
  function setLockWallpaperColor(hex) { return daily.setLockWallpaperColor(hex) }
  function setLockDailySource(id) { return daily.setLockDailySource(id) }
  function setCustomWallpaper(path) { return daily.setCustomWallpaper(path) }
  function clearCustomWallpaper() { return daily.clearCustomWallpaper() }
  function setWallpaperMode(mode) { return daily.setWallpaperMode(mode) }
  function setWallpaperFolder(path) { return daily.setWallpaperFolder(path) }
  function albumIdFromPath(path) { return daily.albumIdFromPath(path) }
  function albumLabelFromPath(path) { return daily.albumLabelFromPath(path) }
  function ensureWallpaperAlbums() { return daily.ensureWallpaperAlbums() }
  function addWallpaperAlbum(path) { return daily.addWallpaperAlbum(path) }
  function setWallpaperAlbum(id) { return daily.setWallpaperAlbum(id) }
  function removeWallpaperAlbum(id) { return daily.removeWallpaperAlbum(id) }
  function renameWallpaperAlbum(id, label) { return daily.renameWallpaperAlbum(id, label) }
  function setWallpaperVideo(path) { return daily.setWallpaperVideo(path) }
  function clearWallpaperVideo() { return daily.clearWallpaperVideo() }
  function setWallpaperReactive(id) { return daily.setWallpaperReactive(id) }
  function pickWallpaperFile() { return daily.pickWallpaperFile() }
  function pickWallpaperFolder() { return daily.pickWallpaperFolder() }
  function pickWallpaperVideo() { return daily.pickWallpaperVideo() }

  // Forwarders — BackgroundDaily / BackgroundApply
  function dailyFetchPlan(src, cacheDir) { return daily.dailyFetchPlan(src, cacheDir) }
  function parseDailyResult(raw, label) { return daily.parseDailyResult(raw, label) }
  function refreshLockDailyWallpaper() { return daily.refreshLockDailyWallpaper() }
  function setWallpaperKind(kind) { return daily.setWallpaperKind(kind) }
  function setWallpaperColor(hex) { return daily.setWallpaperColor(hex) }
  function setWallpaper(id) { return daily.setWallpaper(id) }
  function setWallpaperDailyProvider(id) { return daily.setWallpaperDailyProvider(id) }
  function setWallpaperDailyUrl(url) { return daily.setWallpaperDailyUrl(url) }
  function setWallpaperDailyApiKey(key) { return daily.setWallpaperDailyApiKey(key) }
  function setWallpaperDailyAuth(mode) { return daily.setWallpaperDailyAuth(mode) }
  function setWallpaperDailyMarket(mkt) { return daily.setWallpaperDailyMarket(mkt) }
  function setWallpaperDailyRefreshHours(hours) { return daily.setWallpaperDailyRefreshHours(hours) }
  function dailySourceIdNew() { return daily.dailySourceIdNew() }
  function defaultDailySource(provider) { return daily.defaultDailySource(provider) }
  function normalizeDailySource(s) { return daily.normalizeDailySource(s) }
  function hydrateDailySourcesFromFile() { return daily.hydrateDailySourcesFromFile() }
  function hydrateDailyFromRaw(raw) { return daily.hydrateDailyFromRaw(raw) }
  function resolveActiveDailySource() { return daily.resolveActiveDailySource() }
  function ensureDailySources() { return daily.ensureDailySources() }
  function syncDailyLegacyFromActive() { return daily.syncDailyLegacyFromActive() }
  function patchActiveDailySource(patch) { return daily.patchActiveDailySource(patch) }
  function addDailySource(provider) { return daily.addDailySource(provider) }
  function setDailySource(id, fetchIfActive) { return daily.setDailySource(id, fetchIfActive) }
  function removeDailySource(id) { return daily.removeDailySource(id) }
  function renameDailySource(id, label) { return daily.renameDailySource(id, label) }
  function setWallpaperDaily() { return daily.setWallpaperDaily() }
  function refreshDailyWallpaper(applyAfter) { return daily.refreshDailyWallpaper(applyAfter) }
  function scanWallpaperFolder(dirOverride) { return apply.scanWallpaperFolder(dirOverride) }
  function stopBackgroundBackends() { return apply.stopBackgroundBackends() }
  function applyBackground() { return apply.applyBackground() }
  function applyWallpaper() { return apply.applyWallpaper() }
}
