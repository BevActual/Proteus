pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import ".."

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
