import Quickshell
import Quickshell.Widgets
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../shared"
import "BeaconCalc.js" as Calc

// Beacon — system search (Spotlight-class): Apps / Files / Clipboard / Actions
// modes + calc + tags. Apps mode is the universal surface: apps, Settings
// panes, allowlisted actions, and a Files escape all answer one query.
Item {
  id: root

  // apps | files | clipboard | actions
  property string mode: "apps"
  property bool showUnavailable: search.text.trim().length > 0
  property var tagEditEntry: null
  property var pinMenuEntry: null
  property var fileHits: []
  property var placeHits: []
  property string filesHint: ""
  property var clipHits: []
  property string clipHint: ""
  // Runtime probe — paste inject needs wtype; without it, recall is copy-only.
  property bool hasWtype: false

  readonly property bool tagging: !!tagEditEntry

  // Allowlisted Actions — SoT in UniversalSearch (shared with console Search).
  readonly property var actionCatalog: UniversalSearch.actionCatalog

  readonly property var modes: [
    {
      id: "apps",
      label: "Apps",
      key: "1",
      icon: "view-app-grid-symbolic"
    },
    {
      id: "files",
      label: "Files",
      key: "2",
      icon: "folder-documents-symbolic"
    },
    {
      id: "clipboard",
      label: "Clipboard",
      key: "3",
      icon: "edit-paste-symbolic"
    },
    {
      id: "actions",
      label: "Actions",
      key: "4",
      icon: "system-run-symbolic"
    }
  ]

  // Beacon chrome (Tahoe-like floating pill + sheet)
  readonly property int spotRadius: 22
  readonly property int spotRowH: 52
  readonly property color spotFill: Theme.light
      ? Qt.rgba(1, 1, 1, Math.max(Theme.chromeAlpha, 0.92))
      : Qt.rgba(0.16, 0.16, 0.17, Math.max(Theme.chromeAlpha, 0.88))
  readonly property color spotInset: Theme.light
      ? Qt.rgba(0, 0, 0, 0.04)
      : Qt.rgba(1, 1, 1, 0.06)

  function setMode(id) {
    const changed = mode !== id
    mode = id
    if (changed)
      list.currentIndex = root.firstSelectableIndex()
    // Always refresh — re-selecting the active pill must pick up new copies /
    // filesystem changes while Beacon stayed open on that mode.
    if (id === "files") {
      root.refreshPlaces()
      root.warmFileIndex()
      root.queueFileSearch()
    } else if (id === "clipboard") {
      root.refreshClipboard()
    }
    claimSearchFocus()
  }

  function scoreQuery(hay, q) {
    return UniversalSearch.scoreQuery(hay, q)
  }

  function defaultAppSubtitle(path, fallback) {
    const p = String(path || "")
    const base = root.fileBaseName(p)
    const dot = base.lastIndexOf(".")
    if (dot < 0 || dot === base.length - 1)
      return fallback || p
    const ext = base.slice(dot + 1).toLowerCase()
    const map = {
      "mp4": "video",
      "mkv": "video",
      "webm": "video",
      "avi": "video",
      "mov": "video",
      "m4v": "video",
      "jpg": "images",
      "jpeg": "images",
      "png": "images",
      "webp": "images",
      "gif": "images",
      "svg": "images",
      "avif": "images",
      "pdf": "pdf",
      "mp3": "audio",
      "flac": "audio",
      "wav": "audio",
      "ogg": "audio",
      "m4a": "audio",
      "txt": "text",
      "md": "text",
      "zip": "archive",
      "tar": "archive",
      "gz": "archive",
      "7z": "archive",
      "rar": "archive"
    }
    const cat = map[ext] || ""
    if (!cat)
      return fallback || p
    try {
      const row = DefaultApps.categoryAt(cat)
      const label = row && row.currentLabel ? String(row.currentLabel) : ""
      if (label.length && label !== "Not set")
        return p + " · opens in " + label
    } catch (e) {
    }
    return fallback || p
  }

  function privacyInUseLabel() {
    const bits = []
    if (PrivacyIndicators.mic)
      bits.push("Mic")
    if (PrivacyIndicators.camera)
      bits.push("Camera")
    if (PrivacyIndicators.screen)
      bits.push("Screen")
    if (!bits.length)
      return "In use — Privacy"
    return bits.join(" · ") + " in use — Privacy"
  }

  function privacyInUseSubtitle() {
    const apps = PrivacyIndicators.apps || []
    const names = []
    for (let i = 0; i < apps.length && names.length < 3; i++) {
      const n = String(apps[i].label || apps[i].id || "").trim()
      if (n.length && names.indexOf(n) < 0)
        names.push(n)
    }
    if (names.length)
      return names.join(", ") + " · Privacy → In use now"
    return "Privacy → In use now"
  }

  function recentIndexFor(desktopId) {
    const recents = Config.launcherRecentList()
    const id = String(desktopId || "")
    for (let i = 0; i < recents.length; i++) {
      if (recents[i] === id)
        return i
    }
    return -1
  }

  function parseQuery(raw) {
    const t = String(raw || "").trim()
    if (t.startsWith("#")) {
      const rest = t.slice(1).trim()
      const sp = rest.indexOf(" ")
      if (sp < 0) {
        return {
          tag: Config.normalizeLauncherTag(rest),
          tagPartial: Config.normalizeLauncherTag(rest),
          text: ""
        }
      }
      return {
        tag: Config.normalizeLauncherTag(rest.slice(0, sp)),
        tagPartial: "",
        text: rest.slice(sp + 1).trim().toLowerCase()
      }
    }
    return {
      tag: "",
      tagPartial: "",
      text: t.toLowerCase()
    }
  }

  function tagsSubtitle(desktopId, fallback) {
    const tags = Config.tagsForApp(desktopId)
    if (!tags.length)
      return fallback
    return "#" + tags.join("  #")
  }

  // Available apps: soft prefers / adapts hint, else tags/fallback. Blocked: EnvGate reason.
  function appResultSubtitle(entry, fallback) {
    if (!entry)
      return fallback || ""
    if (!EnvGate.appAvailable(entry))
      return root.unavailableSubtitle(EnvGate.appBlockReason(entry))
    const soft = EnvGate.appPrefersHint(entry)
    if (soft.length)
      return soft
    const adapt = EnvGate.appAdaptHint(entry)
    if (adapt.length)
      return adapt
    return root.tagsSubtitle(entry.id, fallback || "Application")
  }

  function queueFileSearch() {
    fileDebounce.restart()
  }

  function refreshPlaces() {
    placeProc.running = false
    placeProc.command = [
      "python3",
      "-c",
      "import json, os\n"
          + "home = os.path.expanduser('~')\n"
          + "dirs = {}\n"
          + "p = os.path.join(home, '.config', 'user-dirs.dirs')\n"
          + "if os.path.isfile(p):\n"
          + "  for line in open(p, encoding='utf-8', errors='ignore'):\n"
          + "    line = line.strip()\n"
          + "    if not line or line.startswith('#') or '=' not in line: continue\n"
          + "    k, v = line.split('=', 1)\n"
          + "    v = v.strip().strip('\"').replace('$HOME', home)\n"
          + "    dirs[k.strip()] = os.path.expanduser(v)\n"
          + "def pick(keys, fallback):\n"
          + "  for k in keys:\n"
          + "    path = dirs.get(k) or fallback\n"
          + "    if path and os.path.isdir(path): return path\n"
          + "  return fallback if fallback and os.path.isdir(fallback) else None\n"
          + "cands = [\n"
          + "  ('Home', home),\n"
          + "  ('Desktop', pick(['XDG_DESKTOP_DIR'], os.path.join(home, 'Desktop'))),\n"
          + "  ('Documents', pick(['XDG_DOCUMENTS_DIR'], os.path.join(home, 'Documents'))),\n"
          + "  ('Downloads', pick(['XDG_DOWNLOAD_DIR'], os.path.join(home, 'Downloads'))),\n"
          + "  ('Pictures', pick(['XDG_PICTURES_DIR'], os.path.join(home, 'Pictures'))),\n"
          + "  ('Music', pick(['XDG_MUSIC_DIR'], os.path.join(home, 'Music'))),\n"
          + "  ('Videos', pick(['XDG_VIDEOS_DIR'], os.path.join(home, 'Videos'))),\n"
          + "]\n"
          + "seen = set()\n"
          + "out = []\n"
          + "for name, path in cands:\n"
          + "  if not path: continue\n"
          + "  path = os.path.realpath(path)\n"
          + "  if path in seen: continue\n"
          + "  if not os.path.isdir(path): continue\n"
          + "  seen.add(path)\n"
          + "  out.append({'name': name, 'path': path, 'dir': True})\n"
          + "print(json.dumps(out))\n"
    ]
    placeProc.running = true
  }

  function runFileSearch() {
    const q = search.text.trim()
    if (!q.length) {
      fileHits = []
      filesHint = ""
      return
    }
    // Drop previous query's hits immediately so the list doesn't lie while
    // the indexed search runs.
    fileHits = []
    filesHint = "Searching home folder…"
    fileProc.running = false
    // Cached home index (beacon-file-index.py) — rebuilds when stale; fd preferred.
    fileProc.command = [
      "python3",
      Config.scriptsDir + "/beacon-file-index.py",
      "search",
      q
    ]
    fileProc.running = true
  }

  function warmFileIndex() {
    Quickshell.execDetached({
      command: ["python3", Config.scriptsDir + "/beacon-file-index.py", "rebuild"]
    })
  }

  function shellQuote(s) {
    return "'" + String(s).replace(/'/g, "'\\''") + "'"
  }

  function refreshClipboard() {
    clipHint = "Loading…"
    clipProc.running = false
    clipProc.running = true
  }

  function pasteClipboardLine(line) {
    // Close first so the focused client receives the paste, not Beacon.
    ShellState.closeLauncher()
    const inject = root.hasWtype
        ? "; sleep 0.12; wtype -M ctrl -k v -m ctrl"
        : ""
    Quickshell.execDetached({
      command: [
        "bash",
        "-lc",
        "printf '%s\\n' " + shellQuote(line) + " | cliphist decode | wl-copy" + inject
      ]
    })
  }

  function openPath(path) {
    const p = String(path || "").trim()
    if (!p.length)
      return
    Config.recordLauncherFileRecent(p)
    Quickshell.execDetached({
      command: ["xdg-open", p]
    })
  }

  function fileBaseName(path) {
    const p = String(path || "")
    const i = p.lastIndexOf("/")
    if (i < 0)
      return p
    const name = p.slice(i + 1)
    return name.length ? name : p
  }

  readonly property var filtered: {
    const _caps = Hardware.capabilityList
    const _recents = Config.launcherRecents
    const _fileRecents = Config.launcherFileRecents
    const _tagMap = Config.launcherAppTags
    const _catalog = Config.launcherTagCatalog
    const _files = root.fileHits
    const _places = root.placeHits
    const _clips = root.clipHits
    const _mode = root.mode
    const _defaultsRev = DefaultApps.rev
    const _privacyActive = PrivacyIndicators.anyActive
    const _privacyApps = PrivacyIndicators.apps
    const _pinned = DockApps.visiblePinned
    const _hasWtype = root.hasWtype
    const _tops = Hyprland.toplevels.values
    const _permRev = Permissions.rev
    const _permApps = Permissions.apps
    if (root.tagging)
      return []

    if (_mode === "files") {
      const q = search.text.trim()
      const rows = []
      // Empty query: Recents (if any) + Places — not a flat home dump.
      if (!q.length) {
        const recentPaths = Config.launcherFileRecentList()
        const recentRows = []
        for (let r = 0; r < recentPaths.length && recentRows.length < 12; r++) {
          const path = recentPaths[r]
          recentRows.push({
            kind: "file",
            entry: null,
            path: path,
            name: root.fileBaseName(path),
            subtitle: root.defaultAppSubtitle(path, path),
            icon: "document-open-recent",
            blocked: false,
            score: 2500 - r,
            clipLine: "",
            calcValue: "",
            section: "recents"
          })
        }
        if (recentRows.length) {
          rows.push({
            kind: "section",
            entry: null,
            path: "",
            name: "Recents",
            subtitle: "",
            icon: "",
            blocked: true,
            score: 4000,
            clipLine: "",
            calcValue: ""
          })
          for (let i = 0; i < recentRows.length; i++)
            rows.push(recentRows[i])
        }
        if (_places.length) {
          rows.push({
            kind: "section",
            entry: null,
            path: "",
            name: "Places",
            subtitle: "",
            icon: "",
            blocked: true,
            score: 3000,
            clipLine: "",
            calcValue: ""
          })
          for (let i = 0; i < _places.length; i++) {
            const p = _places[i]
            rows.push({
              kind: "file",
              entry: null,
              path: p.path,
              name: p.name,
              subtitle: p.path,
              icon: "folder",
              blocked: false,
              score: 2000 - i,
              clipLine: "",
              calcValue: "",
              section: "places"
            })
          }
        }
        return rows
      }
      // Search: Folders section then Files — depth ≤5 · 40-cap honesty via filesHint.
      const folders = []
      const filesOnly = []
      for (let i = 0; i < _files.length; i++) {
        const f = _files[i]
        const row = {
          kind: "file",
          entry: null,
          path: f.path,
          name: f.name,
          subtitle: f.dir ? f.path : root.defaultAppSubtitle(f.path, f.path),
          icon: f.dir ? "folder" : "text-x-generic",
          blocked: false,
          score: 1000 - i,
          clipLine: "",
          calcValue: "",
          section: f.dir ? "folders" : "files"
        }
        if (f.dir)
          folders.push(row)
        else
          filesOnly.push(row)
      }
      if (folders.length) {
        rows.push({
          kind: "section",
          entry: null,
          path: "",
          name: "Folders",
          subtitle: "",
          icon: "",
          blocked: true,
          score: 3000,
          clipLine: "",
          calcValue: ""
        })
        for (let i = 0; i < folders.length; i++)
          rows.push(folders[i])
      }
      if (filesOnly.length) {
        rows.push({
          kind: "section",
          entry: null,
          path: "",
          name: "Files",
          subtitle: "",
          icon: "",
          blocked: true,
          score: 2000,
          clipLine: "",
          calcValue: ""
        })
        for (let i = 0; i < filesOnly.length; i++)
          rows.push(filesOnly[i])
      }
      return rows
    }

    if (_mode === "clipboard") {
      const q = search.text.trim().toLowerCase()
      const rows = []
      for (let i = 0; i < _clips.length; i++) {
        const c = _clips[i]
        const hay = String(c.preview || "").toLowerCase()
        if (q.length && hay.indexOf(q) < 0)
          continue
        rows.push({
          kind: "clipboard",
          entry: null,
          path: "",
          name: c.preview,
          subtitle: root.hasWtype
              ? "Enter pastes"
              : "Enter copies — press Ctrl+V",
          icon: "edit-paste",
          blocked: false,
          score: 1000 - i,
          clipLine: c.line,
          calcValue: "",
          actionId: ""
        })
        if (rows.length >= 40)
          break
      }
      return rows
    }

    if (_mode === "actions") {
      const q = search.text.trim().toLowerCase()
      const rows = []
      const catalog = root.actionCatalog
      for (let i = 0; i < catalog.length; i++) {
        const a = catalog[i]
        const hay = (String(a.name || "") + " " + String(a.keywords || "")).toLowerCase()
        let score = 400 - i
        if (q.length) {
          score = root.scoreQuery(hay, q)
          if (score < 0)
            continue
          score += 200
        }
        rows.push({
          kind: "action",
          entry: null,
          path: "",
          name: a.name,
          subtitle: a.subtitle || "Action",
          icon: a.icon || "system-run",
          blocked: false,
          score: score,
          clipLine: "",
          calcValue: "",
          actionId: a.id,
          destructive: !!a.destructive
        })
      }
      rows.sort((x, y) => {
        if (y.score !== x.score)
          return y.score - x.score
        return String(x.name).localeCompare(String(y.name))
      })
      return rows
    }

    // —— Apps mode (settings, tags, calc) ——
    const parsed = root.parseQuery(search.text)
    const q = parsed.text
    const tagFilter = parsed.tag
    const tagPartial = parsed.tagPartial
    const apps = DesktopEntries.applications.values
    const rows = []
    const rawQ = search.text.trim()

    // Privacy activity pin — empty query, or when the query matches privacy/in-use terms.
    if (_privacyActive && !tagFilter.length) {
      let showPrivacy = !q.length
      if (q.length) {
        const hay = ("privacy in use microphone camera screen mic " + root.privacyInUseLabel()).toLowerCase()
        showPrivacy = root.scoreQuery(hay, q) >= 0
      }
      if (showPrivacy) {
        rows.push({
          kind: "settings",
          entry: null,
          path: "",
          paneId: "privacy-activity",
          name: root.privacyInUseLabel(),
          subtitle: root.privacyInUseSubtitle(),
          icon: "preferences-system-privacy",
          blocked: false,
          score: q.length ? 5200 : 5000,
          clipLine: "",
          calcValue: ""
        })
      }
    }

    const calc = Calc.tryCalc(rawQ)
    if (calc) {
      const kindLabel = calc.kind === "convert" ? "Convert" : "Calculator"
      rows.push({
        kind: "calc",
        entry: null,
        path: "",
        name: calc.display,
        subtitle: kindLabel + " · Enter copies · = " + calc.expression,
        icon: "accessories-calculator",
        blocked: false,
        score: 5000,
        clipLine: "",
        calcValue: String(calc.display)
      })
    } else if (Calc.looksLikeCalc(rawQ)) {
      rows.push({
        kind: "hint",
        entry: null,
        path: "",
        name: "Can't evaluate",
        subtitle: "Try 2+2, 32 F to C, or 10 km in miles",
        icon: "accessories-calculator",
        blocked: true,
        score: 4500,
        clipLine: "",
        calcValue: ""
      })
    }

    if (rawQ.startsWith("#") && !q.length) {
      const catalog = Config.launcherTagCatalogList()
      for (let i = 0; i < catalog.length; i++) {
        const tag = catalog[i]
        if (tagPartial.length) {
          const ts = root.scoreQuery(tag, tagPartial)
          if (ts < 0 && !tag.startsWith(tagPartial))
            continue
        }
        let score = 500
        if (tag === tagPartial)
          score = 1000
        else if (tagPartial.length && tag.startsWith(tagPartial))
          score = 800
        rows.push({
          kind: "tag",
          entry: null,
          path: "",
          tag: tag,
          name: "#" + tag,
          subtitle: "Tag",
          icon: "bookmark-new",
          blocked: false,
          score: score,
          clipLine: "",
          calcValue: ""
        })
      }
      if (tagFilter.length && catalog.indexOf(tagFilter) >= 0) {
        for (let i = 0; i < apps.length; i++) {
          const a = apps[i]
          if (!a || !a.name || !Config.appHasTag(a.id, tagFilter))
            continue
          const ok = EnvGate.appAvailable(a)
          if (!ok && !root.showUnavailable)
            continue
          rows.push({
            kind: "app",
            entry: a,
            path: "",
            name: a.name,
            subtitle: root.appResultSubtitle(a, a.genericName || "Application"),
            icon: EnvGate.resolveAppIcon(a),
            blocked: !ok,
            privacyBlocked: !ok && !!EnvGate.appPrivacyBlockPane(a),
            score: 400 - i + (ok ? EnvGate.appPrefersBoost(a) : 0),
            clipLine: "",
            calcValue: ""
          })
        }
      }
      rows.sort((x, y) => {
        if (y.score !== x.score)
          return y.score - x.score
        return String(x.name).localeCompare(String(y.name))
      })
      return rows.slice(0, 40)
    }

    // Empty Apps query: calm Recents + Pinned — or honest empty.
    // Do not dump alphabetical apps as a fake home; search/tags remain the browse path.
    if (!q.length && !tagFilter.length) {
      const recentRows = []
      const recentIds = Config.launcherRecentList()
      const recentSeen = {}
      for (let r = 0; r < recentIds.length && recentRows.length < 12; r++) {
        const id = recentIds[r]
        let a = null
        for (let i = 0; i < apps.length; i++) {
          if (apps[i] && apps[i].id === id) {
            a = apps[i]
            break
          }
        }
        if (!a || !a.name)
          continue
        const ok = EnvGate.appAvailable(a)
        if (!ok && !root.showUnavailable)
          continue
        recentSeen[DockApps.normalizeDesktopId(a.id)] = true
        recentRows.push({
          kind: "app",
          entry: a,
          path: "",
          name: a.name,
          subtitle: root.appResultSubtitle(a, "Recent"),
          icon: EnvGate.resolveAppIcon(a),
          blocked: !ok,
          privacyBlocked: !ok && !!EnvGate.appPrivacyBlockPane(a),
          score: 2000 - r + (ok ? EnvGate.appPrefersBoost(a) : 0),
          clipLine: "",
          calcValue: "",
          section: "recents"
        })
      }
      if (recentRows.length) {
        rows.push({
          kind: "section",
          entry: null,
          path: "",
          name: "Recents",
          subtitle: "",
          icon: "",
          blocked: true,
          score: 3000,
          clipLine: "",
          calcValue: ""
        })
        for (let i = 0; i < recentRows.length; i++)
          rows.push(recentRows[i])
      }

      const pinRows = []
      for (let p = 0; p < _pinned.length && pinRows.length < 8; p++) {
        const e = _pinned[p]
        if (!e || e.special || !e.name)
          continue
        const pid = DockApps.normalizeDesktopId(e.desktopId || e.id || "")
        if (!pid.length || recentSeen[pid])
          continue
        if (pid === "proteus-settings" || pid === "settings" || pid === "proteus-beacon")
          continue
        const ok = EnvGate.appAvailable(e)
        if (!ok && !root.showUnavailable)
          continue
        pinRows.push({
          kind: "app",
          entry: e,
          path: "",
          name: e.name,
          subtitle: root.appResultSubtitle(e, "Pinned"),
          icon: EnvGate.resolveAppIcon(e),
          blocked: !ok,
          privacyBlocked: !ok && !!EnvGate.appPrivacyBlockPane(e),
          score: 1500 - p + (ok ? EnvGate.appPrefersBoost(e) : 0),
          clipLine: "",
          calcValue: "",
          section: "pinned"
        })
      }
      if (pinRows.length) {
        rows.push({
          kind: "section",
          entry: null,
          path: "",
          name: "Pinned",
          subtitle: "",
          icon: "",
          blocked: true,
          score: 2500,
          clipLine: "",
          calcValue: ""
        })
        for (let i = 0; i < pinRows.length; i++)
          rows.push(pinRows[i])
      }

      const winRows = []
      const wins = DockApps.listSearchableWindows()
      for (let w = 0; w < wins.length && winRows.length < 8; w++) {
        const win = wins[w]
        winRows.push({
          kind: "window",
          entry: null,
          path: "",
          name: win.title,
          subtitle: win.subtitle,
          icon: win.icon || "preferences-system-windows",
          blocked: false,
          score: 1200 - w,
          clipLine: "",
          calcValue: "",
          windowAddress: win.address,
          section: "windows"
        })
      }
      if (winRows.length) {
        rows.push({
          kind: "section",
          entry: null,
          path: "",
          name: "Windows",
          subtitle: "",
          icon: "",
          blocked: true,
          score: 2200,
          clipLine: "",
          calcValue: ""
        })
        for (let i = 0; i < winRows.length; i++)
          rows.push(winRows[i])
      }
    } else {
      for (let i = 0; i < apps.length; i++) {
        const a = apps[i]
        if (!a || !a.name)
          continue
        if (tagFilter.length && !Config.appHasTag(a.id, tagFilter))
          continue
        const name = String(a.name).toLowerCase()
        const generic = String(a.genericName || "").toLowerCase()
        const keys = (a.keywords || []).join(" ").toLowerCase()
        const tags = Config.tagsForApp(a.id)
        const tagHay = tags.join(" ").toLowerCase()
        const hay = (name + " " + generic + " " + keys + " " + tagHay).trim()
        const ri = root.recentIndexFor(a.id)
        let score = -1
        if (!q.length && tagFilter.length) {
          score = 600 - (ri >= 0 ? ri : 40)
        } else {
          score = Math.max(root.scoreQuery(name, q), root.scoreQuery(hay, q), root.scoreQuery(tagHay, q))
          if (score < 0)
            continue
          if (ri >= 0)
            score += 40 - ri
          if (tags.some(t => t === q || t.startsWith(q)))
            score += 60
        }
        const ok = EnvGate.appAvailable(a)
        if (!ok && !root.showUnavailable)
          continue
        if (ok)
          score += EnvGate.appPrefersBoost(a)
        rows.push({
          kind: "app",
          entry: a,
          path: "",
          name: a.name,
          subtitle: root.appResultSubtitle(a, a.genericName || "Application"),
          icon: EnvGate.resolveAppIcon(a),
          blocked: !ok,
          privacyBlocked: !ok && !!EnvGate.appPrivacyBlockPane(a),
          score: score,
          clipLine: "",
          calcValue: ""
        })
      }

      if (q.length && !tagFilter.length) {
        const idx = EnvGate.settingsSearchIndex
        for (let i = 0; i < idx.length; i++) {
          const p = idx[i]
          const ok = EnvGate.paneAvailable(p.hubId)
          if (!ok && !root.showUnavailable)
            continue
          const label = String(p.label).toLowerCase()
          const hay = (label + " " + (p.keywords || "") + " settings").toLowerCase()
          let score = Math.max(root.scoreQuery(label, q), root.scoreQuery(hay, q))
          if (score < 0)
            continue
          if (label === q || label.startsWith(q))
            score += 30
          rows.push({
            kind: "settings",
            entry: null,
            path: "",
            paneId: p.id,
            name: p.label,
            subtitle: ok
              ? "Settings"
              : root.unavailableSubtitle(EnvGate.paneBlockReason(p.hubId)),
            icon: "proteus-settings",
            blocked: !ok,
            score: score,
            clipLine: "",
            calcValue: ""
          })
        }

        // Actions answer the main query too — "reboot" shouldn't need Ctrl+4.
        // settings-* actions are skipped: the Settings index above owns those.
        const acts = root.actionCatalog
        for (let i = 0; i < acts.length; i++) {
          const a = acts[i]
          if (String(a.id).startsWith("settings-"))
            continue
          if (a.id === "enter-console" && ShellState.consoleSurfaceActive)
            continue
          if (a.id === "enter-host" && ShellState.hostSurfaceActive)
            continue
          if (a.id === "enter-desktop"
              && !ShellState.consoleSurfaceActive && !ShellState.hostSurfaceActive)
            continue
          const hay = (String(a.name || "") + " " + String(a.keywords || "")).toLowerCase()
          const score = root.scoreQuery(hay, q)
          if (score < 0)
            continue
          rows.push({
            kind: "action",
            entry: null,
            path: "",
            name: a.name,
            subtitle: a.subtitle || "Action",
            icon: a.icon || "system-run",
            blocked: false,
            score: score,
            clipLine: "",
            calcValue: "",
            actionId: a.id,
            destructive: !!a.destructive
          })
        }

        // Running windows (title / class)
        const winsQ = DockApps.listSearchableWindows()
        for (let w = 0; w < winsQ.length; w++) {
          const win = winsQ[w]
          const hay = (String(win.title || "") + " " + String(win.className || "") + " window").toLowerCase()
          let score = Math.max(root.scoreQuery(String(win.title || "").toLowerCase(), q), root.scoreQuery(hay, q))
          if (score < 0)
            continue
          score += 80
          rows.push({
            kind: "window",
            entry: null,
            path: "",
            name: win.title,
            subtitle: win.subtitle,
            icon: win.icon || "preferences-system-windows",
            blocked: false,
            score: score,
            clipLine: "",
            calcValue: "",
            windowAddress: win.address
          })
        }

        // Per-app privacy grants — "firefox camera", "microphone", etc.
        const cats = Permissions.categoryMeta || []
        const storeApps = _permApps || {}
        const seenPerm = {}
        function pushPermRow(appId, appLabel, cat, score) {
          const key = appId + "|" + cat.id
          if (seenPerm[key])
            return
          seenPerm[key] = true
          const grant = Permissions.appGrant(appId, cat.id)
          rows.push({
            kind: "settings",
            entry: null,
            path: "",
            paneId: "privacy-" + cat.id,
            name: appLabel + " · " + cat.label,
            subtitle: grant === "ask"
                ? ("Privacy · ask · Enter to decide")
                : ("Privacy · " + grant + " · Enter to manage"),
            icon: "preferences-system-privacy",
            blocked: false,
            score: score,
            clipLine: "",
            calcValue: ""
          })
        }
        // Stored grants
        const storeIds = Object.keys(storeApps)
        for (let i = 0; i < storeIds.length; i++) {
          const aid = storeIds[i]
          let label = aid
          for (let j = 0; j < apps.length; j++) {
            if (apps[j] && DockApps.normalizeDesktopId(apps[j].id) === DockApps.normalizeDesktopId(aid)) {
              label = apps[j].name || aid
              break
            }
          }
          for (let c = 0; c < cats.length; c++) {
            const cat = cats[c]
            const hay = (label + " " + cat.label + " " + cat.id + " permission grant privacy").toLowerCase()
            const score = root.scoreQuery(hay, q)
            if (score < 0)
              continue
            pushPermRow(aid, label, cat, score + 40)
          }
        }
        // Manifest apps with permissions[] even if not yet in store
        for (let i = 0; i < apps.length; i++) {
          const a = apps[i]
          if (!a || !a.name)
            continue
          const pane = EnvGate.appPrivacyBlockPane(a)
          const man = EnvGate.manifestForApp(a)
          const perms = (man && man.permissions) ? man.permissions : []
          if (!perms.length && !pane.length)
            continue
          const list = perms.length ? perms : (pane.length ? [pane.replace("privacy-", "")] : [])
          for (let c = 0; c < cats.length; c++) {
            const cat = cats[c]
            if (list.indexOf(cat.id) < 0)
              continue
            const hay = (a.name + " " + cat.label + " " + cat.id + " permission grant privacy").toLowerCase()
            const score = root.scoreQuery(hay, q)
            if (score < 0)
              continue
            pushPermRow(DockApps.normalizeDesktopId(a.id), a.name, cat, score + 50)
          }
        }
      }
    }

    // Preserve Recents section order on empty home; otherwise rank by score.
    if (q.length || tagFilter.length) {
      rows.sort((x, y) => {
        if (y.score !== x.score)
          return y.score - x.score
        return String(x.name).localeCompare(String(y.name))
      })
    }
    const out = rows.slice(0, 40)
    // Files escape — pinned after ranked hits so any query can pivot to Files.
    if (q.length && !tagFilter.length) {
      out.push({
        kind: "filesearch",
        entry: null,
        path: "",
        name: "Search Files for \u201C" + rawQ + "\u201D",
        subtitle: "Beacon · Files mode (Ctrl+2)",
        icon: "system-search",
        blocked: false,
        score: 0,
        clipLine: "",
        calcValue: ""
      })
    }
    return out
  }

  readonly property var tagChipModel: {
    const _c = Config.launcherTagCatalog
    return mode === "apps" ? Config.launcherTagCatalogList() : []
  }

  readonly property var tagEditChips: {
    const _c = Config.launcherTagCatalog
    const _m = Config.launcherAppTags
    if (!root.tagEditEntry)
      return []
    const catalog = Config.launcherTagCatalogList()
    const on = Config.tagsForApp(root.tagEditEntry.id)
    const rows = []
    for (let i = 0; i < catalog.length; i++) {
      rows.push({
        tag: catalog[i],
        active: on.indexOf(catalog[i]) >= 0
      })
    }
    return rows
  }

  function runAction(actionId) {
    UniversalSearch.runAction(actionId)
  }

  function firstSelectableIndex() {
    const rows = filtered
    for (let i = 0; i < rows.length; i++) {
      if (rows[i] && rows[i].kind !== "section")
        return i
    }
    return 0
  }

  function moveSelection(delta) {
    const rows = filtered
    if (!rows.length)
      return
    let i = list.currentIndex
    for (let step = 0; step < rows.length; step++) {
      i = (i + delta + rows.length) % rows.length
      if (rows[i] && rows[i].kind !== "section") {
        list.currentIndex = i
        return
      }
    }
  }

  function launchIndex(i) {
    if (i < 0 || i >= filtered.length)
      return
    const row = filtered[i]
    if (!row || row.kind === "section" || row.kind === "hint")
      return
    // Privacy Ask → prompt; hard Deny → Settings leaf.
    if (row.blocked && row.kind === "app" && row.entry) {
      const askCat = EnvGate.appPrivacyAskCategory(row.entry)
      if (askCat.length) {
        const entry = row.entry
        if (PrivacyAsk.promptLaunch(entry, askCat, function (e) {
          const ent = e || entry
          Config.recordLauncherRecent(ent.id)
          DockApps.launchEntry(ent)
        })) {
          search.text = ""
          list.currentIndex = 0
          return
        }
      }
      const pane = EnvGate.appPrivacyBlockPane(row.entry)
      if (pane.length) {
        ShellState.openSettings(pane)
        search.text = ""
        list.currentIndex = 0
        return
      }
      return
    }
    if (row.blocked)
      return
    if (row.kind === "window") {
      DockApps.focusWindowAddress(row.windowAddress)
      ShellState.closeLauncher()
      search.text = ""
      list.currentIndex = 0
      return
    }
    if (row.kind === "filesearch") {
      // Keep the query; setMode re-runs it against ~.
      root.setMode("files")
      return
    }
    if (row.kind === "calc") {
      Config.copyToClipboard(row.calcValue)
      ShellState.closeLauncher()
      search.text = ""
      return
    }
    if (row.kind === "file") {
      root.openPath(row.path)
      ShellState.closeLauncher()
      search.text = ""
      return
    }
    if (row.kind === "clipboard") {
      root.pasteClipboardLine(row.clipLine)
      search.text = ""
      return
    }
    if (row.kind === "action") {
      root.runAction(row.actionId)
      ShellState.closeLauncher()
      search.text = ""
      list.currentIndex = 0
      return
    }
    if (row.kind === "tag") {
      search.text = "#" + row.tag + " "
      list.currentIndex = 0
      return
    }
    if (row.kind === "settings") {
      ShellState.openSettings(row.paneId)
      search.text = ""
      list.currentIndex = 0
      return
    }
    if (row.entry) {
      const appId = DockApps.normalizeDesktopId(row.entry.id)
      // Desktop entry and Action both land here — never spawn a second Settings.
      if (appId === "proteus-settings" || appId === "settings") {
        ShellState.openSettings()
        ShellState.closeLauncher()
        search.text = ""
        list.currentIndex = 0
        return
      }
      Config.recordLauncherRecent(row.entry.id)
      // DockApps injects PROTEUS_ADAPT_* when EnvGate resolves adapts.
      DockApps.launchEntry(row.entry)
    }
    ShellState.closeLauncher()
    search.text = ""
    list.currentIndex = 0
  }

  function beginTagEdit(entry) {
    if (!entry || entry.blocked)
      return
    tagEditEntry = entry
    tagNewField.text = ""
    Qt.callLater(() => tagNewField.forceActiveFocus())
  }

  function endTagEdit() {
    tagEditEntry = null
    claimSearchFocus()
  }

  function openAppMenu(entry) {
    if (!entry || entry.blocked)
      return
    pinMenuEntry = entry
    appPinMenu.popup()
  }

  function togglePinFromMenu() {
    const e = pinMenuEntry
    pinMenuEntry = null
    if (!e)
      return
    if (DockApps.isPinned(e.id))
      DockApps.unpinDesktopId(e.id)
    else
      DockApps.pinDesktopEntry(e)
  }

  function addTagFromField() {
    const t = Config.ensureLauncherTag(tagNewField.text)
    if (!t.length || !tagEditEntry)
      return
    if (!Config.appHasTag(tagEditEntry.id, t))
      Config.toggleAppTag(tagEditEntry.id, t)
    tagNewField.text = ""
  }

  function placeholderForMode() {
    if (mode === "files")
      return "Search files"
    if (mode === "clipboard")
      return "Filter clipboard"
    if (mode === "actions")
      return "Filter actions"
    return "Search apps, settings, actions"
  }

  function emptyText() {
    if (mode === "files") {
      if (search.text.trim().length) {
        if (filesHint.length)
          return filesHint
        return "No files match under ~ (depth ≤5, skips dotdirs)."
      }
      if (placeHits.length || Config.launcherFileRecentList().length)
        return ""
      if (filesHint.length)
        return filesHint
      return "No places available — type a name to search your home folder (depth ≤5)."
    }
    if (mode === "clipboard") {
      // Prefer clipHint whenever history is empty so "not installed" isn't
      // masked by a typed filter, and empty ≠ missing.
      if (clipHint.length && !clipHits.length)
        return clipHint
      if (search.text.trim().length)
        return "No clipboard matches in recent history."
      return "Clipboard history is empty — copy something, or check wl-paste watchers."
    }
    if (mode === "actions") {
      if (search.text.trim().length)
        return "No actions match."
      return "No allowlisted actions in catalog."
    }
    const t = search.text.trim()
    if (!t.length)
      return "No recent apps yet — type to search apps, settings, and actions; Tab or Ctrl+2–4 switches modes."
    if (t === "#")
      return "Add tags via # on a result, or Settings → Desktop → Beacon."
    if (showUnavailable)
      return "No matches — including unavailable apps for this device."
    return "No matches."
  }

  function unavailableSubtitle(reason) {
    const r = String(reason || "").trim()
    if (!r.length)
      return "Unavailable on this device"
    if (r.indexOf("Privacy · Ask") === 0)
      return r + " · Enter to decide"
    if (r.indexOf("Blocked by Privacy") === 0)
      return r + " · Enter to manage"
    if (r.toLowerCase().startsWith("unavailable"))
      return r
    return "Unavailable · " + r
  }

  // Floating Beacon sheet (Tahoe-shaped): pill search + results sheet
  Item {
    id: chrome
    anchors.fill: parent

    Rectangle {
      anchors.fill: card
      anchors.topMargin: 12
      anchors.leftMargin: 3
      anchors.rightMargin: 3
      radius: root.spotRadius
      color: Theme.light ? Qt.rgba(0, 0, 0, 0.12) : Qt.rgba(0, 0, 0, 0.5)
      z: 0
    }

    Rectangle {
      id: card
      anchors.fill: parent
      radius: root.spotRadius
      color: root.spotFill
      border.width: Theme.light ? 0 : 1
      border.color: Qt.rgba(1, 1, 1, 0.08)
      clip: true
      z: 1

      ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Item {
          id: searchBar
          Layout.fillWidth: true
          Layout.preferredHeight: root.spotRowH
          visible: !root.tagging

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 18
            anchors.rightMargin: 14
            spacing: 10

            Text {
              text: "⌕"
              color: Theme.textMute
              font.pixelSize: 18
              Layout.alignment: Qt.AlignVCenter
            }

            TextField {
              id: search
              Layout.fillWidth: true
              Layout.fillHeight: true
              placeholderText: root.placeholderForMode()
              color: Theme.text
              placeholderTextColor: Theme.textMute
              font.family: Theme.fontFamily
              font.pixelSize: 20
              focus: ShellState.launcherOpen && !root.tagging
              background: Item {}
              verticalAlignment: Text.AlignVCenter
              onTextChanged: {
                list.currentIndex = root.firstSelectableIndex()
                if (root.mode === "files")
                  root.queueFileSearch()
              }
              Keys.onEscapePressed: {
                if (root.tagging) {
                  root.endTagEdit()
                  return
                }
                // First Esc clears the query, second closes — macOS Spotlight.
                if (search.text.length) {
                  search.text = ""
                  return
                }
                ShellState.closeLauncher()
              }
              Keys.onDownPressed: root.moveSelection(1)
              Keys.onUpPressed: root.moveSelection(-1)
              Keys.onReturnPressed: root.launchIndex(list.currentIndex)
              Keys.onEnterPressed: root.launchIndex(list.currentIndex)
              Keys.onPressed: event => {
                if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                  const ids = ["apps", "files", "clipboard", "actions"]
                  const back = event.key === Qt.Key_Backtab
                      || (event.modifiers & Qt.ShiftModifier)
                  const i = ids.indexOf(root.mode)
                  root.setMode(ids[(i + (back ? -1 : 1) + ids.length) % ids.length])
                  event.accepted = true
                  return
                }
                if (event.modifiers & Qt.ControlModifier) {
                  if (event.key === Qt.Key_1) {
                    root.setMode("apps")
                    event.accepted = true
                    return
                  }
                  if (event.key === Qt.Key_2) {
                    root.setMode("files")
                    event.accepted = true
                    return
                  }
                  if (event.key === Qt.Key_3) {
                    root.setMode("clipboard")
                    event.accepted = true
                    return
                  }
                  if (event.key === Qt.Key_4) {
                    root.setMode("actions")
                    event.accepted = true
                    return
                  }
                  if (event.key === Qt.Key_T && root.mode === "apps") {
                    const row = root.filtered[list.currentIndex]
                    if (row && row.kind === "app" && row.entry && !row.blocked)
                      root.beginTagEdit(row.entry)
                    event.accepted = true
                  }
                }
              }
            }

            Row {
              spacing: 4
              Layout.alignment: Qt.AlignVCenter

              Repeater {
                model: root.modes
                delegate: Rectangle {
                  required property var modelData
                  readonly property bool active: root.mode === modelData.id
                  height: 34
                  width: active ? Math.max(34, modeRow.implicitWidth + 16) : 34
                  radius: 17
                  color: active
                      ? Theme.chromeAccentSoft
                      : (modeMa.containsMouse ? root.spotInset : "transparent")
                  border.width: active ? 0 : 0
                  border.color: "transparent"

                  Row {
                    id: modeRow
                    anchors.centerIn: parent
                    spacing: 6

                    IconImage {
                      anchors.verticalCenter: parent.verticalCenter
                      width: 16
                      height: 16
                      source: EnvGate.iconSource(modelData.icon)
                    }

                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      visible: active
                      text: modelData.label
                      color: Theme.text
                      font.family: Theme.fontFamily
                      font.pixelSize: 11
                      font.weight: Font.DemiBold
                    }
                  }

                  MouseArea {
                    id: modeMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    ToolTip.visible: containsMouse && !active
                    ToolTip.delay: 400
                    ToolTip.text: modelData.label + "  Ctrl+" + modelData.key
                    onClicked: root.setMode(modelData.id)
                  }
                }
              }
            }
          }

          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: Theme.separator
            opacity: 0.65
          }
        }

        // Tag-edit header bar (replaces search while tagging)
        Item {
          Layout.fillWidth: true
          Layout.preferredHeight: root.spotRowH
          visible: root.tagging

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 18
            anchors.rightMargin: 16
            spacing: Theme.spaceSm

            Text {
              Layout.fillWidth: true
              text: tagEditEntry ? ("Tags · " + tagEditEntry.name) : "Tags"
              color: Theme.text
              font.family: Theme.fontFamily
              font.pixelSize: 16
              font.weight: Font.Medium
              elide: Text.ElideRight
            }

            Text {
              text: "Done"
              color: Theme.accent
              font.family: Theme.fontFamily
              font.pixelSize: 14
              font.weight: Font.DemiBold
              MouseArea {
                anchors.fill: parent
                anchors.margins: -8
                cursorShape: Qt.PointingHandCursor
                onClicked: root.endTagEdit()
              }
            }
          }

          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: Theme.separator
            opacity: 0.65
          }
        }

        ColumnLayout {
          Layout.fillWidth: true
          Layout.fillHeight: true
          Layout.margins: 10
          spacing: 8

          Text {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            visible: !root.tagging
            text: {
              if (root.mode === "files") {
                if (!search.text.trim().length)
                  return "Files · Recents + Places · type to search ~"
                if (root.filesHint.length)
                  return root.filesHint
                return "Files · Folders then Files · depth ≤5"
              }
              if (root.mode === "clipboard")
                return root.clipHint.length && !root.clipHits.length
                    ? root.clipHint
                    : "Clipboard · cliphist"
              if (root.mode === "actions")
                return "Actions · allowlisted"
              if (root.showUnavailable)
                return "Apps · includes unavailable"
              return "Apps"
            }
            color: Theme.textMute
            font.family: Theme.fontFamily
            font.pixelSize: 11
            font.weight: Font.DemiBold
            font.capitalization: Font.AllUppercase
          }

          Flickable {
            id: chipFlick
            Layout.fillWidth: true
            Layout.preferredHeight: root.tagChipModel.length && !root.tagging ? 28 : 0
            visible: height > 0
            contentWidth: chipRow.width
            contentHeight: height
            clip: true
            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.StopAtBounds

            Row {
              id: chipRow
              spacing: 6
              height: parent.height
              leftPadding: 4

              Repeater {
                model: root.tagChipModel
                delegate: Rectangle {
                  required property string modelData
                  readonly property bool selected: {
                    const p = root.parseQuery(search.text)
                    return p.tag === modelData
                  }
                  height: 26
                  width: chipLabel.implicitWidth + 16
                  radius: 13
                  color: selected ? Theme.chromeAccentSoft : root.spotInset

                  Text {
                    id: chipLabel
                    anchors.centerIn: parent
                    text: "#" + modelData
                    color: Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      if (selected)
                        search.text = ""
                      else
                        search.text = "#" + modelData + " "
                      root.claimSearchFocus()
                    }
                  }
                }
              }
            }
          }

          ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.spaceMd
            visible: root.tagging

            Text {
              Layout.fillWidth: true
              text: "Optional labels to group apps. Type #tag to filter."
              color: Theme.textMute
              font.family: Theme.fontFamily
              font.pixelSize: 11
              wrapMode: Text.WordWrap
            }

            Flow {
              Layout.fillWidth: true
              spacing: 6

              Repeater {
                model: root.tagEditChips
                delegate: Rectangle {
                  required property var modelData
                  height: 28
                  width: editChipLabel.implicitWidth + 18
                  radius: 14
                  color: modelData.active ? Theme.chromeAccentSoft : root.spotInset

                  Text {
                    id: editChipLabel
                    anchors.centerIn: parent
                    text: "#" + modelData.tag
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Config.toggleAppTag(root.tagEditEntry.id, modelData.tag)
                  }
                }
              }
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: Theme.spaceSm

              TextField {
                id: tagNewField
                Layout.fillWidth: true
                placeholderText: "New tag"
                color: Theme.text
                placeholderTextColor: Theme.textMute
                font.family: Theme.fontFamily
                font.pixelSize: 13
                background: Rectangle {
                  radius: 10
                  color: root.spotInset
                }
                leftPadding: 12
                rightPadding: 12
                topPadding: 8
                bottomPadding: 8
                Keys.onEscapePressed: root.endTagEdit()
                Keys.onReturnPressed: root.addTagFromField()
                Keys.onEnterPressed: root.addTagFromField()
              }

              Rectangle {
                Layout.preferredHeight: 34
                Layout.preferredWidth: addLbl.implicitWidth + 20
                radius: 10
                color: root.spotInset
                Text {
                  id: addLbl
                  anchors.centerIn: parent
                  text: "Add"
                  color: Theme.text
                  font.family: Theme.fontFamily
                  font.pixelSize: 12
                }
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.addTagFromField()
                }
              }
            }

            Item {
              Layout.fillHeight: true
            }
          }

          ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 2
            model: root.filtered
            currentIndex: 0
            highlightMoveDuration: 70
            keyNavigationEnabled: false
            focus: true
            visible: !root.tagging
            onCountChanged: currentIndex = root.firstSelectableIndex()
            onModelChanged: currentIndex = root.firstSelectableIndex()

            delegate: Item {
              required property var modelData
              required property int index
              width: list.width
              height: modelData.kind === "section" ? 28 : (modelData.kind === "calc" ? 64 : 52)

              // Calm section header (Recents / …) — not selectable
              Text {
                visible: modelData.kind === "section"
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                text: modelData.name
                color: Theme.textMute
                font.family: Theme.fontFamily
                font.pixelSize: 11
                font.weight: Font.DemiBold
                font.letterSpacing: 0.4
              }

              Rectangle {
                anchors.fill: parent
                radius: 12
                visible: modelData.kind !== "section"
                opacity: modelData.blocked ? 0.45 : 1
                color: list.currentIndex === index
                    ? Theme.chromeAccentSoft
                    : (rowMa.containsMouse ? root.spotInset : "transparent")
              }

              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 8
                spacing: 12
                visible: modelData.kind !== "section"

                SquircleIcon {
                  Layout.preferredWidth: modelData.kind === "calc" ? 40 : 34
                  Layout.preferredHeight: modelData.kind === "calc" ? 40 : 34
                  pixelSize: 96
                  fillCrop: false
                  showBorder: false
                  glyphScale: modelData.kind === "calc" ? 0.62 : Theme.iconGlyphScaleApp
                  plate: Theme.iconPlateFill
                  source: EnvGate.iconSource(modelData.icon || "application-x-executable")
                }

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: modelData.kind === "calc" ? 2 : 1

                  Text {
                    Layout.fillWidth: true
                    text: modelData.name
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: modelData.kind === "calc" ? 22 : 15
                    font.weight: modelData.kind === "calc" ? Font.DemiBold : Font.Normal
                    elide: Text.ElideRight
                  }

                  Text {
                    Layout.fillWidth: true
                    visible: !!(modelData.subtitle && modelData.subtitle.length)
                    text: modelData.subtitle
                    color: modelData.blocked || modelData.destructive ? Theme.danger : Theme.textMute
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    elide: Text.ElideRight
                  }
                }

                Text {
                  visible: modelData.kind === "calc" && list.currentIndex === index
                  text: "Copy"
                  color: Theme.textMute
                  font.family: Theme.fontFamily
                  font.pixelSize: 11
                }

                Text {
                  visible: !!modelData.blocked
                  text: modelData.privacyBlocked ? "Blocked · Privacy" : "Unavailable"
                  color: Theme.danger
                  font.family: Theme.fontFamily
                  font.pixelSize: 10
                  font.weight: Font.DemiBold
                }

                Rectangle {
                  visible: modelData.kind === "app" && !modelData.blocked
                  Layout.preferredWidth: 28
                  Layout.preferredHeight: 28
                  radius: 14
                  color: tagBtnMa.containsMouse ? root.spotInset : "transparent"

                  Text {
                    anchors.centerIn: parent
                    text: "#"
                    color: Theme.textMute
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                  }

                  MouseArea {
                    id: tagBtnMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      list.currentIndex = index
                      root.beginTagEdit(modelData.entry)
                    }
                  }
                }
              }

              MouseArea {
                id: rowMa
                anchors.fill: parent
                anchors.rightMargin: modelData.kind === "app" && !modelData.blocked ? 36 : 0
                hoverEnabled: modelData.kind !== "section"
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                enabled: modelData.kind !== "section"
                cursorShape: (modelData.blocked && !modelData.privacyBlocked)
                    ? Qt.ForbiddenCursor
                    : Qt.PointingHandCursor
                onEntered: list.currentIndex = index
                onClicked: mouse => {
                  if (mouse.button === Qt.RightButton && modelData.kind === "app" && modelData.entry && !modelData.blocked) {
                    root.openAppMenu(modelData.entry)
                    return
                  }
                  root.launchIndex(index)
                }
              }
            }

            Text {
              anchors.centerIn: parent
              width: parent.width - 48
              visible: root.filtered.length === 0
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
              text: root.emptyText()
              color: Theme.textMute
              font.family: Theme.fontFamily
              font.pixelSize: 14
            }
          }
        }

        // Calm key legend — modes/tags stay discoverable without a manual.
        Item {
          Layout.fillWidth: true
          Layout.preferredHeight: 28
          visible: !root.tagging

          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 1
            color: Theme.separator
            opacity: 0.65
          }

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 18
            anchors.rightMargin: 18
            spacing: Theme.spaceMd

            Text {
              text: "↵ Open   ⇥ Mode   Esc Clear / Close"
              color: Theme.textMute
              font.family: Theme.fontFamily
              font.pixelSize: 10
            }

            Item {
              Layout.fillWidth: true
            }

            Text {
              visible: root.mode === "apps"
              text: "#tag Filter   Ctrl+T Tag app"
              color: Theme.textMute
              font.family: Theme.fontFamily
              font.pixelSize: 10
            }
          }
        }
      }
    }
  }

  Timer {
    id: fileDebounce
    interval: 200
    repeat: false
    onTriggered: root.runFileSearch()
  }

  Process {
    id: placeProc
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const raw = text.trim() || "[]"
          const parsed = JSON.parse(raw)
          root.placeHits = Array.isArray(parsed) ? parsed : []
        } catch (e) {
          root.placeHits = []
        }
        if (root.mode === "files")
          list.currentIndex = root.firstSelectableIndex()
      }
    }
  }

  Process {
    id: fileProc
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const raw = text.trim() || "{}"
          let list = []
          let capped = false
          const parsed = JSON.parse(raw)
          if (Array.isArray(parsed)) {
            list = parsed
          } else if (parsed && typeof parsed === "object") {
            list = Array.isArray(parsed.hits) ? parsed.hits : []
            capped = !!parsed.capped
          }
          root.fileHits = list
          const eng = (parsed && parsed.engine) ? String(parsed.engine) : "index"
          if (list.length) {
            root.filesHint = capped
                ? ("Showing first 40 · " + eng + " · depth ≤5")
                : ""
          } else {
            root.filesHint = "No files match under ~ (" + eng + ", depth ≤5)."
          }
        } catch (e) {
          root.fileHits = []
          root.filesHint = "File search failed — needs python3 + beacon-file-index.py."
        }
      }
    }
  }

  Process {
    id: clipProc
    command: [
      "bash",
      "-lc",
      "if ! command -v cliphist >/dev/null 2>&1; then printf '%s\\n' '__CLIPHIST_MISSING__'; exit 0; fi\n"
          + "out=$(cliphist list 2>/dev/null | head -n 80 || true)\n"
          + "if [ -z \"$out\" ]; then printf '%s\\n' '__CLIPHIST_EMPTY__'; exit 0; fi\n"
          + "printf '%s\\n' \"$out\""
    ]
    stdout: StdioCollector {
      onStreamFinished: {
        const raw = text.trim()
        if (!raw.length || raw === "__CLIPHIST_MISSING__") {
          root.clipHits = []
          root.clipHint = "cliphist not installed — Clipboard mode needs cliphist + wl-paste watchers."
          return
        }
        if (raw === "__CLIPHIST_EMPTY__") {
          root.clipHits = []
          root.clipHint = "Clipboard history is empty — copy something, or check wl-paste watchers."
          return
        }
        const lines = raw.split("\n")
        const out = []
        for (let i = 0; i < lines.length; i++) {
          const line = lines[i]
          if (!line.length)
            continue
          const tab = line.indexOf("\t")
          const preview = tab >= 0 ? line.slice(tab + 1) : line
          const shown = preview.length > 120 ? preview.slice(0, 117) + "…" : preview
          out.push({
            line: line,
            preview: shown.length ? shown : "(binary / image)"
          })
        }
        root.clipHits = out
        root.clipHint = out.length
            ? ""
            : "Clipboard history is empty — copy something, or check wl-paste watchers."
      }
    }
  }

  Connections {
    target: ShellState
    function onLauncherOpenChanged() {
      if (ShellState.launcherOpen) {
        search.text = ""
        tagEditEntry = null
        mode = "apps"
        // Clear prior Files/Clipboard session so reopen doesn't flash stale
        // hits or "Showing first 40…" from the last query.
        fileHits = []
        filesHint = ""
        clipHits = []
        clipHint = ""
        list.currentIndex = 0
        root.claimSearchFocus()
      } else {
        tagEditEntry = null
        fileProc.running = false
        clipProc.running = false
      }
    }

    // CLI/smoke probe: chrome IPC seeds a query into the universal surface.
    function onBeaconQuerySeeded(query) {
      root.mode = "apps"
      tagEditEntry = null
      search.text = query
      list.currentIndex = root.firstSelectableIndex()
    }

    function onPadAction(button) {
      if (!ShellState.launcherOpen || ShellState.sessionLocked || ShellState.controlCenterOpen)
        return
      const b = String(button || "")
      if (b === "b" || b === "select") {
        if (search.text.length) {
          search.text = ""
          return
        }
        ShellState.closeLauncher()
        return
      }
      if (b === "a" || b === "start") {
        root.launchIndex(list.currentIndex)
        return
      }
      if (b === "up") {
        root.moveSelection(-1)
        return
      }
      if (b === "down") {
        root.moveSelection(1)
        return
      }
      if (b === "left") {
        // Cycle modes
        const modes = ["apps", "files", "clipboard", "actions"]
        let i = modes.indexOf(root.mode)
        root.setMode(modes[(i - 1 + modes.length) % modes.length])
        return
      }
      if (b === "right") {
        const modes = ["apps", "files", "clipboard", "actions"]
        let i = modes.indexOf(root.mode)
        root.setMode(modes[(i + 1) % modes.length])
      }
    }
  }

  // Mirror a result summary for smoke assertions (chrome beaconState).
  onFilteredChanged: {
    const rows = filtered
    const kinds = []
    for (let i = 0; i < rows.length && kinds.length < 10; i++) {
      if (rows[i].kind !== "section")
        kinds.push(rows[i].kind)
    }
    ShellState.beaconProbe = JSON.stringify({
      mode: mode,
      query: search.text,
      count: rows.length,
      kinds: kinds
    })
  }

  function claimSearchFocus() {
    search.forceActiveFocus()
    focusRetry.restart()
  }

  Timer {
    id: focusRetry
    interval: 16
    repeat: true
    property int tries: 0
    onTriggered: {
      tries++
      search.forceActiveFocus()
      if (search.activeFocus || tries >= 12) {
        tries = 0
        stop()
      }
    }
  }

  Menu {
    id: appPinMenu
    readonly property bool pinnedNow: !!(pinMenuEntry && DockApps.isPinned(pinMenuEntry.id))
    MenuItem {
      text: appPinMenu.pinnedNow ? "Remove from Dock" : "Add to Dock"
      onTriggered: root.togglePinFromMenu()
    }
    MenuItem {
      text: "Edit Tags…"
      onTriggered: {
        const e = root.pinMenuEntry
        root.pinMenuEntry = null
        if (e)
          root.beginTagEdit(e)
      }
    }
  }

  Process {
    id: wtypeProbe
    command: ["bash", "-lc", "command -v wtype >/dev/null 2>&1 && echo yes || echo no"]
    stdout: StdioCollector {
      onStreamFinished: {
        root.hasWtype = String(text).trim() === "yes"
      }
    }
  }

  Component.onCompleted: {
    wtypeProbe.running = true
  }
}
