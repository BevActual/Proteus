pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
  id: root

  property alias wallpaperKind: adapter.wallpaperKind
  property alias wallpaperColor: adapter.wallpaperColor
  property alias wallpaperId: adapter.wallpaperId
  property alias wallpaperCustomPath: adapter.wallpaperCustomPath
  property alias wallpaperMode: adapter.wallpaperMode
  property alias wallpaperFolder: adapter.wallpaperFolder
  property alias wallpaperVideoPath: adapter.wallpaperVideoPath
  property alias wallpaperReactiveId: adapter.wallpaperReactiveId
  property alias wallpaperSlideshow: adapter.wallpaperSlideshow
  property alias wallpaperSlideshowSecs: adapter.wallpaperSlideshowSecs
  property alias wallpaperShuffle: adapter.wallpaperShuffle
  property alias wallpaperDailyProvider: adapter.wallpaperDailyProvider
  property alias wallpaperDailyPath: adapter.wallpaperDailyPath
  property alias wallpaperDailyTitle: adapter.wallpaperDailyTitle
  property alias wallpaperDailyCopyright: adapter.wallpaperDailyCopyright
  property alias wallpaperDailyFetchedAt: adapter.wallpaperDailyFetchedAt
  property alias wallpaperDailyRefreshHours: adapter.wallpaperDailyRefreshHours
  property alias wallpaperDailyUrl: adapter.wallpaperDailyUrl
  property alias wallpaperDailyApiKey: adapter.wallpaperDailyApiKey
  property alias wallpaperDailyAuth: adapter.wallpaperDailyAuth
  property alias wallpaperDailyMarket: adapter.wallpaperDailyMarket
  property alias wallpaperDailySources: adapter.wallpaperDailySources
  property alias wallpaperDailySourceId: adapter.wallpaperDailySourceId
  property alias accentId: adapter.accentId
  property alias accentCustom: adapter.accentCustom

  readonly property string assetsDir: {
    const rootDir = Quickshell.shellRoot
    if (rootDir && rootDir.length) {
      if (rootDir.indexOf("/wallpaper") >= 0)
        return rootDir.replace(/\/wallpaper.*/, "/assets")
      return rootDir + "/../assets"
    }
    return "/mnt/proteus/shell/assets"
  }

  readonly property string defaultWallpaperFolder: Quickshell.env("HOME") + "/.local/share/proteus/backgrounds"

  readonly property string wallpaperFolderResolved: {
    const f = (wallpaperFolder && String(wallpaperFolder).length) ? String(wallpaperFolder) : defaultWallpaperFolder
    return f
  }

  readonly property var wallpapers: [
    {
      id: "default",
      path: assetsDir + "/wallpaper.jpg"
    },
    {
      id: "harbor",
      path: assetsDir + "/wallpaper-harbor.jpg"
    },
    {
      id: "ember",
      path: assetsDir + "/wallpaper-ember.jpg"
    },
    {
      id: "signal",
      path: assetsDir + "/wallpaper-signal.jpg"
    },
    {
      id: "reef",
      path: assetsDir + "/wallpaper-reef.jpg"
    }
  ]

  readonly property string wallpaperPath: {
    if ((wallpaperKind === "daily" || wallpaperId === "daily") && wallpaperDailyPath && String(wallpaperDailyPath).length)
      return String(wallpaperDailyPath)
    if (wallpaperId === "custom" && wallpaperCustomPath && String(wallpaperCustomPath).length)
      return String(wallpaperCustomPath)
    for (let i = 0; i < wallpapers.length; i++) {
      if (wallpapers[i].id === wallpaperId)
        return wallpapers[i].path
    }
    return wallpapers[0].path
  }

  readonly property var accents: [
    {
      id: "blue",
      color: "#3d8bfd"
    },
    {
      id: "teal",
      color: "#2dd4bf"
    },
    {
      id: "violet",
      color: "#a78bfa"
    },
    {
      id: "amber",
      color: "#fbbf24"
    },
    {
      id: "rose",
      color: "#fb7185"
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
      if (accents[i].id === accentId)
        return accents[i].color
    }
    return accents[0].color
  }

  readonly property color solidColor: {
    const h = normalizeAccentHex(wallpaperColor)
    return h.length ? h : "#0f1419"
  }

  readonly property int imageFillMode: {
    switch (wallpaperMode) {
    case "fit":
      return Image.PreserveAspectFit
    case "stretch":
      return Image.Stretch
    case "center":
      return Image.Pad
    default:
      return Image.PreserveAspectCrop
    }
  }

  property var folderEntries: []
  property int slideshowIndex: 0
  property string slideshowPath: ""

  readonly property string activeImagePath: {
    if (wallpaperSlideshow && slideshowPath && slideshowPath.length)
      return slideshowPath
    return wallpaperPath
  }

  function rescanFolder() {
    if (folderScanProc.running)
      return
    const dir = JSON.stringify(wallpaperFolderResolved)
    folderScanProc.command = [
      "python3",
      "-c",
      "import json, pathlib\n"
          + "root = pathlib.Path(" + dir + ")\n"
          + "ext = {'.png','.jpg','.jpeg','.webp','.bmp','.gif'}\n"
          + "out = []\n"
          + "if root.is_dir():\n"
          + "  for p in sorted(root.iterdir()):\n"
          + "    if p.is_file() and p.suffix.lower() in ext:\n"
          + "      out.append({'path': str(p), 'label': p.stem})\n"
          + "print(json.dumps(out))\n"
    ]
    folderScanProc.running = false
    folderScanProc.running = true
  }

  function advanceSlideshow() {
    const list = folderEntries
    if (!list || !list.length) {
      slideshowPath = wallpaperPath
      return
    }
    if (wallpaperShuffle) {
      slideshowIndex = Math.floor(Math.random() * list.length)
    } else {
      slideshowIndex = (slideshowIndex + 1) % list.length
    }
    slideshowPath = list[slideshowIndex].path || wallpaperPath
  }

  // Live playback level, 0..100. Driven by a single long-lived reader (see
  // peakProc) rather than one process tree per sample. Consumers subscribe so
  // the reader only runs while something is actually drawing a level.
  property real lastPeak: 0
  property int peakSubscribers: 0

  function subscribePeaks() {
    peakSubscribers = peakSubscribers + 1
  }

  function unsubscribePeaks() {
    peakSubscribers = Math.max(0, peakSubscribers - 1)
    if (peakSubscribers === 0)
      lastPeak = 0
  }

  readonly property string scriptsDir: {
    const rootDir = Quickshell.shellRoot
    if (rootDir && rootDir.length) {
      if (rootDir.indexOf("/wallpaper") >= 0)
        return rootDir.replace(/\/wallpaper.*/, "/scripts")
      return rootDir + "/../scripts"
    }
    return "/mnt/proteus/shell/scripts"
  }

  readonly property string settingsJsonPath: Quickshell.env("HOME") + "/.config/proteus/settings.json"
  readonly property string dailyCacheDir: Quickshell.env("HOME") + "/.local/share/proteus/backgrounds/daily"

  function resolveActiveDailySource() {
    const list = Array.isArray(wallpaperDailySources) ? wallpaperDailySources : []
    if (!list.length)
      return null
    const id = String(wallpaperDailySourceId || "")
    for (let i = 0; i < list.length; i++) {
      if (String(list[i].id) === id)
        return list[i]
    }
    return list[0]
  }

  function refreshDailyWallpaper() {
    if (dailyFetchProc.running)
      return
    const src = resolveActiveDailySource()
    const provider = src ? String(src.provider || "bing") : String(wallpaperDailyProvider || "bing")
    const url = src ? String(src.url || "") : String(wallpaperDailyUrl || "")
    const apiKey = src ? String(src.apiKey || "") : String(wallpaperDailyApiKey || "")
    const auth = src ? String(src.auth || "none") : String(wallpaperDailyAuth || "none")
    const market = src ? String(src.market || "en-US") : String(wallpaperDailyMarket || "en-US")
    if (provider === "custom" && !url.trim())
      return
    if (provider === "unsplash" && !apiKey.trim())
      return
    dailyFetchProc.command = [
      "python3",
      scriptsDir + "/fetch-daily-wallpaper.py",
      "--settings",
      settingsJsonPath,
      "--cache-dir",
      dailyCacheDir,
      "--provider",
      provider,
      "--url",
      url,
      "--auth",
      auth,
      "--market",
      market
    ]
    // Key goes through the environment — argv is world-readable via /proc.
    dailyFetchProc.environment = ({ "PROTEUS_DAILY_API_KEY": apiKey })
    dailyFetchProc.running = false
    dailyFetchProc.running = true
  }

  Process {
    id: dailyFetchProc
    command: ["true"]
    stdout: StdioCollector {
      onStreamFinished: {
        const raw = text.trim()
        if (!raw.length)
          return
        try {
          const lines = raw.split("\n").filter(l => l.trim().length)
          const res = JSON.parse(lines[lines.length - 1])
          if (!res || !res.ok)
            return
          if (res.path)
            root.wallpaperDailyPath = String(res.path)
          root.wallpaperDailyTitle = res.title ? String(res.title) : ""
          root.wallpaperDailyCopyright = res.copyright ? String(res.copyright) : ""
          root.wallpaperDailyFetchedAt = res.fetchedAt ? String(res.fetchedAt) : ""
          // Persist only daily fields — never writeAdapter() the partial schema.
          root.persistDailyMeta()
        } catch (e) {
        }
      }
    }
  }

  function persistDailyMeta() {
    if (dailyMetaProc.running)
      return
    const payload = JSON.stringify({
      path: String(wallpaperDailyPath || ""),
      title: String(wallpaperDailyTitle || ""),
      copyright: String(wallpaperDailyCopyright || ""),
      fetchedAt: String(wallpaperDailyFetchedAt || "")
    })
    dailyMetaProc.command = [
      "python3",
      "-c",
      "import json, pathlib, sys\n"
          + "meta = json.loads(sys.argv[1])\n"
          + "p = pathlib.Path(sys.argv[2])\n"
          + "d = json.loads(p.read_text()) if p.is_file() else {}\n"
          + "d['wallpaperDailyPath'] = meta.get('path') or ''\n"
          + "d['wallpaperDailyTitle'] = meta.get('title') or ''\n"
          + "d['wallpaperDailyCopyright'] = meta.get('copyright') or ''\n"
          + "d['wallpaperDailyFetchedAt'] = meta.get('fetchedAt') or ''\n"
          + "p.parent.mkdir(parents=True, exist_ok=True)\n"
          + "p.write_text(json.dumps(d, indent=4) + '\\n')\n",
      payload,
      settingsJsonPath
    ]
    dailyMetaProc.running = false
    dailyMetaProc.running = true
  }

  Process {
    id: dailyMetaProc
    command: ["true"]
  }

  FileView {
    path: Quickshell.env("HOME") + "/.config/proteus/settings.json"
    watchChanges: true
    onFileChanged: reload()
    // Read-only: Settings owns settings.json. Writing from this partial
    // JsonAdapter was wiping daily sources / kind on every reload.
    onLoadFailed: error => {
    }

    JsonAdapter {
      id: adapter
      property string wallpaperKind: "image"
      property string wallpaperColor: "#0f1419"
      property string wallpaperId: "default"
      property string wallpaperCustomPath: ""
      property string wallpaperMode: "fill"
      property string wallpaperFolder: ""
      property string wallpaperVideoPath: ""
      property string wallpaperReactiveId: "drift"
      property bool wallpaperSlideshow: false
      property int wallpaperSlideshowSecs: 60
      property bool wallpaperShuffle: false
      property string wallpaperDailyProvider: "bing"
      property string wallpaperDailyUrl: ""
      property string wallpaperDailyApiKey: ""
      property string wallpaperDailyAuth: "none"
      property string wallpaperDailyMarket: "en-US"
      property int wallpaperDailyRefreshHours: 6
      property string wallpaperDailyPath: ""
      property string wallpaperDailyTitle: ""
      property string wallpaperDailyCopyright: ""
      property string wallpaperDailyFetchedAt: ""
      property var wallpaperDailySources: []
      property string wallpaperDailySourceId: ""
      property string accentId: "blue"
      property string accentCustom: "#3d8bfd"

      onWallpaperSlideshowChanged: {
        if (wallpaperSlideshow)
          root.rescanFolder()
      }
      onWallpaperFolderChanged: root.rescanFolder()
    }
  }

  Component.onCompleted: {
    if (wallpaperSlideshow)
      rescanFolder()
  }

  Process {
    id: folderScanProc
    command: ["true"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const list = JSON.parse(text.trim() || "[]")
          root.folderEntries = Array.isArray(list) ? list : []
        } catch (e) {
          root.folderEntries = []
        }
        if (root.wallpaperSlideshow)
          root.advanceSlideshow()
      }
    }
  }

  // One long-lived parec reader emitting a peak per window. The helper follows
  // the default sink via @DEFAULT_MONITOR@ and idles at 0 when audio is gone,
  // so it never needs restarting on device changes.
  Process {
    id: peakProc
    running: root.peakSubscribers > 0
    command: ["python3", root.scriptsDir + "/audio-peak.py", "--window-ms", "100"]
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: line => {
        const v = parseInt(String(line).trim(), 10)
        if (!isNaN(v))
          root.lastPeak = Math.max(0, Math.min(100, v))
      }
    }
  }
}
