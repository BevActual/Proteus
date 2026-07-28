import Quickshell
import Quickshell.Io
import QtQuick
import ".."

// Daily wallpaper sources / fetch / hydrate. host = Background singleton.
QtObject {
  id: daily
  property var host

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
    if (host.apply.lockDailyFetchProc.running)
      return
    ensureDailySources()
    let src = lockDailySourceResolved
    if (!src)
      src = host.activeDailySource

    const plan = dailyFetchPlan(src, host.defaultLockDailyDir)
    if (!plan.ok) {
      host.lockDailyError = plan.error
      host.lockDailyFetching = false
      return
    }
    if (!String(host.lockDailySourceId || "").length)
      host.lockDailySourceId = String(src.id)

    host.lockDailyFetching = true
    host.lockDailyError = ""
    host.lockBackgroundMode = "daily"
    Config.flushSettings()

    host.apply.lockDailyFetchProc.command = plan.command
    // Key goes through the environment — argv is world-readable via /proc.
    host.apply.lockDailyFetchProc.environment = ({ "PROTEUS_DAILY_API_KEY": plan.apiKey })
    host.apply.lockDailyFetchProc.running = false
    host.apply.lockDailyFetchProc.running = true
  }

  function setWallpaperKind(kind) {
    // Browse-only helper (Settings UI uses local browseKind). Do not apply —
    // writing host.wallpaperKind alone would hot-reload the desktop background.
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
    host.wallpaperColor = n
    host.wallpaperKind = "color"
    host.applyBackground()
    return true
  }

  function setWallpaper(id) {
    host.wallpaperId = id
    host.wallpaperKind = "image"
    host.applyBackground()
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
    host.wallpaperDailyRefreshHours = n
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
          host.wallpaperDailySources = d.wallpaperDailySources.map(s => normalizeDailySource(s))
          if (d.wallpaperDailySourceId)
            host.wallpaperDailySourceId = String(d.wallpaperDailySourceId)
        }
      }
    } catch (e) {
    }
    ensureDailySources()
  }

  function resolveActiveDailySource() {
    const list = host.wallpaperDailySourcesList
    if (!list.length)
      return null
    const id = String(host.wallpaperDailySourceId || "")
    for (let i = 0; i < list.length; i++) {
      if (String(list[i].id) === id)
        return list[i]
    }
    return list[0]
  }

  function ensureDailySources() {
    let list = Array.isArray(host.wallpaperDailySources) ? host.wallpaperDailySources.slice() : []
    if (list.length) {
      const id = String(host.wallpaperDailySourceId || "")
      let found = false
      for (let i = 0; i < list.length; i++) {
        if (String(list[i].id) === id) {
          found = true
          break
        }
      }
      if (!found)
        host.wallpaperDailySourceId = String(list[0].id)
      syncDailyLegacyFromActive()
      return list
    }
    // Migrate legacy flat fields into one source
    const legacy = defaultDailySource(host.wallpaperDailyProvider || "bing")
    if (host.wallpaperDailyUrl && String(host.wallpaperDailyUrl).length)
      legacy.url = String(host.wallpaperDailyUrl)
    if (host.wallpaperDailyApiKey && String(host.wallpaperDailyApiKey).length)
      legacy.apiKey = String(host.wallpaperDailyApiKey)
    if (host.wallpaperDailyAuth && String(host.wallpaperDailyAuth).length)
      legacy.auth = String(host.wallpaperDailyAuth)
    if (host.wallpaperDailyMarket && String(host.wallpaperDailyMarket).length)
      legacy.market = String(host.wallpaperDailyMarket)
    if (legacy.provider === "bing")
      legacy.label = "Bing"
    else if (legacy.provider === "unsplash")
      legacy.label = "Unsplash"
    list = [legacy]
    host.wallpaperDailySources = list
    host.wallpaperDailySourceId = legacy.id
    syncDailyLegacyFromActive()
    return list
  }

  function syncDailyLegacyFromActive() {
    const src = resolveActiveDailySource()
    if (!src)
      return
    host.wallpaperDailyProvider = String(src.provider || "bing")
    host.wallpaperDailyUrl = String(src.url || "")
    host.wallpaperDailyApiKey = String(src.apiKey || "")
    host.wallpaperDailyAuth = String(src.auth || "none")
    host.wallpaperDailyMarket = String(src.market || "en-US")
  }

  function patchActiveDailySource(patch) {
    ensureDailySources()
    let sid = String(host.wallpaperDailySourceId || "")
    const resolved = resolveActiveDailySource()
    if (resolved)
      sid = String(resolved.id)
    host.wallpaperDailySourceId = sid
    const list = host.wallpaperDailySourcesList.map(s => {
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
    host.wallpaperDailySources = list
    syncDailyLegacyFromActive()
    Config.flushSettings()
  }

  function addDailySource(provider) {
    ensureDailySources()
    const src = defaultDailySource(provider)
    // Unique label if duplicates
    const base = src.label
    let n = 2
    const labels = host.wallpaperDailySourcesList.map(s => String(s.label))
    while (labels.indexOf(src.label) >= 0) {
      src.label = base + " " + n
      n++
    }
    host.wallpaperDailySources = host.wallpaperDailySourcesList.concat([src])
    setDailySource(src.id, false)
  }

  function setDailySource(id, fetchIfActive) {
    ensureDailySources()
    const sid = String(id || "")
    let found = null
    const list = host.wallpaperDailySourcesList
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
    const changed = String(host.wallpaperDailySourceId) !== String(found.id)
    host.wallpaperDailySourceId = String(found.id)
    syncDailyLegacyFromActive()
    host.wallpaperDailyError = ""
    Config.flushSettings()
    if (fetchIfActive && changed && (host.wallpaperKind === "daily" || host.wallpaperId === "daily"))
      refreshDailyWallpaper(true)
  }

  function removeDailySource(id) {
    ensureDailySources()
    const sid = String(id || "")
    let list = host.wallpaperDailySourcesList.filter(s => String(s.id) !== sid)
    if (!list.length)
      list = [defaultDailySource("bing")]
    host.wallpaperDailySources = list
    if (String(host.wallpaperDailySourceId) === sid || !list.some(s => String(s.id) === String(host.wallpaperDailySourceId)))
      setDailySource(list[0].id, host.wallpaperKind === "daily" || host.wallpaperId === "daily")
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
    host.wallpaperDailySources = host.wallpaperDailySourcesList.map(s => {
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
    host.wallpaperSlideshow = false
    host.wallpaperId = "daily"
    host.wallpaperKind = "daily"
    refreshDailyWallpaper(true)
  }

  function refreshDailyWallpaper(applyAfter) {
    if (host.apply.wallpaperDailyFetchProc.running)
      return
    ensureDailySources()
    const src = resolveActiveDailySource()

    const plan = dailyFetchPlan(src, host.defaultDailyWallpaperDir)
    if (!plan.ok) {
      host.wallpaperDailyError = plan.error
      host.wallpaperDailyFetching = false
      return
    }
    // Keep sourceId aligned with the resolved profile
    if (String(host.wallpaperDailySourceId) !== String(src.id))
      host.wallpaperDailySourceId = String(src.id)
    syncDailyLegacyFromActive()

    host.wallpaperDailyFetching = true
    host.wallpaperDailyError = ""
    Config.flushSettings()

    // Source fields go on the CLI so fetch does not race FileView writeAdapter.
    host.apply.wallpaperDailyFetchProc.command = plan.command
    // Key goes through the environment — argv is world-readable via /proc.
    host.apply.wallpaperDailyFetchProc.environment = ({ "PROTEUS_DAILY_API_KEY": plan.apiKey })
    host.apply.wallpaperDailyFetchProc.applyAfter = !!applyAfter
    host.apply.wallpaperDailyFetchProc.running = false
    host.apply.wallpaperDailyFetchProc.running = true
  }


  // Lock / album setters (from façade)
  function setWallpaperSlideshow(on) {
    host.wallpaperSlideshow = !!on
    if (host.wallpaperKind === "image")
      host.applyBackground()
  }

  function setWallpaperSlideshowSecs(secs) {
    const n = Math.max(5, Math.min(600, Math.round(secs)))
    host.wallpaperSlideshowSecs = n
  }

  function setWallpaperShuffle(on) {
    host.wallpaperShuffle = !!on
  }

  function setLockDim(v) {
    const n = Number(v)
    if (isNaN(n))
      return
    host.lockDim = Math.round(Math.max(0, Math.min(0.75, n)) * 100) / 100
    Config.flushSettings()
  }

  function setLockBackgroundMode(mode) {
    const m = String(mode || "match")
    if (m !== "match" && m !== "image" && m !== "color" && m !== "daily" && m !== "video" && m !== "reactive")
      return
    host.lockBackgroundMode = m
    Config.flushSettings()
    if (m === "daily") {
      ensureDailySources()
      if (!String(host.lockDailySourceId || "").length && activeDailySource)
        host.lockDailySourceId = String(activeDailySource.id)
      if (!(host.lockDailyPath && String(host.lockDailyPath).length) && !(wallpaperDailyPath && String(wallpaperDailyPath).length))
        refreshLockDailyWallpaper()
    }
    if (m === "image" && host.lockWallpaperSlideshow)
      advanceLockSlideshow()
  }

  function setLockWallpaperMode(mode) {
    const allowed = ["fill", "fit", "stretch", "center"]
    const m = String(mode || "fill")
    if (allowed.indexOf(m) < 0)
      return
    host.lockWallpaperMode = m
    if (host.lockBackgroundMode === "match")
      host.lockBackgroundMode = "image"
    Config.flushSettings()
  }

  function setLockWallpaperAlbum(id) {
    ensureWallpaperAlbums()
    const sid = String(id || "")
    const list = host.wallpaperAlbumsList
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
    host.lockWallpaperAlbumId = String(album.id)
    host.lockBackgroundMode = "image"
    Config.flushSettings()
    scanWallpaperFolder(album.path)
    if (host.lockWallpaperSlideshow)
      advanceLockSlideshow()
  }

  function setLockWallpaperSlideshow(on) {
    host.lockWallpaperSlideshow = !!on
    host.lockBackgroundMode = "image"
    Config.flushSettings()
    if (host.lockWallpaperSlideshow) {
      scanWallpaperFolder()
      advanceLockSlideshow()
    } else {
      host.lockSlideshowPath = ""
    }
  }

  function setLockWallpaperSlideshowSecs(secs) {
    const n = Math.max(5, Math.min(600, Math.round(Number(secs) || 60)))
    host.lockWallpaperSlideshowSecs = n
    Config.flushSettings()
  }

  function setLockWallpaperShuffle(on) {
    host.lockWallpaperShuffle = !!on
    Config.flushSettings()
  }

  function setLockWallpaperVideo(path) {
    const p = String(path || "").trim()
    if (!p.length)
      return
    host.lockWallpaperVideoPath = p
    host.lockBackgroundMode = "video"
    Config.flushSettings()
  }

  function setLockWallpaperReactive(id) {
    const rid = String(id || "drift")
    let ok = false
    for (let i = 0; i < host.wallpaperReactives.length; i++) {
      if (host.wallpaperReactives[i].id === rid)
        ok = true
    }
    if (!ok)
      return
    host.lockWallpaperReactiveId = rid
    host.lockBackgroundMode = "reactive"
    Config.flushSettings()
  }

  function advanceLockSlideshow() {
    const list = host.wallpaperFolderEntries
    if (!list || !list.length) {
      host.lockSlideshowPath = lockBackdropPath
      return
    }
    if (host.lockWallpaperShuffle) {
      host.lockSlideshowIndex = Math.floor(Math.random() * list.length)
    } else {
      host.lockSlideshowIndex = (host.lockSlideshowIndex + 1) % list.length
    }
    const entry = list[host.lockSlideshowIndex]
    host.lockSlideshowPath = (entry && entry.path) ? String(entry.path) : lockBackdropPath
  }

  function setLockWallpaper(id) {
    const sid = String(id || "default")
    host.lockWallpaperId = sid
    host.lockBackgroundMode = "image"
    Config.flushSettings()
  }

  function setLockCustomWallpaper(path) {
    const p = String(path || "").trim()
    if (!p.length)
      return
    host.lockWallpaperCustomPath = p
    host.lockWallpaperId = "custom"
    host.lockBackgroundMode = "image"
    Config.flushSettings()
  }

  function setLockWallpaperColor(hex) {
    const n = Config.normalizeAccentHex(hex)
    if (!n.length)
      return false
    host.lockWallpaperColor = n
    host.lockBackgroundMode = "color"
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
    host.lockDailySourceId = String(found.id)
    host.lockBackgroundMode = "daily"
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
  function setCustomWallpaper(path) {
    const p = String(path || "").trim()
    if (!p.length)
      return
    host.wallpaperCustomPath = p
    host.wallpaperId = "custom"
    host.wallpaperKind = "image"
    host.applyBackground()
  }

  function clearCustomWallpaper() {
    host.wallpaperId = "default"
    host.wallpaperKind = "image"
    host.applyBackground()
  }

  function setWallpaperMode(mode) {
    host.wallpaperMode = mode
    if (host.wallpaperKind === "image")
      host.applyBackground()
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
    let list = Array.isArray(host.wallpaperAlbums) ? host.wallpaperAlbums.slice() : []
    if (list.length)
      return list
    // Migrate legacy single folder (or default library) into one album
    const path = (host.wallpaperFolder && String(host.wallpaperFolder).length)
        ? String(host.wallpaperFolder)
        : host.defaultWallpaperFolder
    list = [
      {
        id: albumIdFromPath(path),
        label: albumLabelFromPath(path),
        path: path
      }
    ]
    host.wallpaperAlbums = list
    if (!String(host.wallpaperAlbumId || "").length)
      host.wallpaperAlbumId = list[0].id
    if (!String(host.wallpaperFolder || "").length)
      host.wallpaperFolder = path
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
    host.wallpaperAlbums = list
    setWallpaperAlbum(id)
  }

  function setWallpaperAlbum(id) {
    ensureWallpaperAlbums()
    const sid = String(id || "")
    const list = host.wallpaperAlbumsList
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
    host.wallpaperAlbumId = String(album.id)
    host.wallpaperFolder = String(album.path || "")
    host.wallpaperKind = "image"
    scanWallpaperFolder()
    if (host.wallpaperSlideshow)
      host.applyBackground()
  }

  function removeWallpaperAlbum(id) {
    const sid = String(id || "")
    let list = ensureWallpaperAlbums().filter(a => String(a.id) !== sid)
    if (!list.length) {
      const path = host.defaultWallpaperFolder
      list = [
        {
          id: albumIdFromPath(path),
          label: albumLabelFromPath(path),
          path: path
        }
      ]
    }
    host.wallpaperAlbums = list
    if (String(host.wallpaperAlbumId) === sid || !list.some(a => String(a.id) === String(host.wallpaperAlbumId)))
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
    host.wallpaperAlbums = list
  }

  function setWallpaperVideo(path) {
    const p = String(path || "").trim()
    if (!p.length)
      return
    host.wallpaperVideoPath = p
    host.wallpaperKind = "video"
    host.applyBackground()
  }

  function clearWallpaperVideo() {
    host.wallpaperVideoPath = ""
    host.wallpaperKind = "image"
    host.applyBackground()
  }

  function setWallpaperReactive(id) {
    const rid = String(id || "")
    let ok = false
    for (let i = 0; i < host.wallpaperReactives.length; i++) {
      if (host.wallpaperReactives[i].id === rid)
        ok = true
    }
    if (!ok)
      return
    host.wallpaperReactiveId = rid
    host.wallpaperKind = "reactive"
    host.applyBackground()
  }

  function pickWallpaperFile() {
    // Qt FileDialog in StylePane opens the picker.
  }

  function pickWallpaperFolder() {
  }

  function pickWallpaperVideo() {
  }


}
