import Quickshell
import Quickshell.Widgets
import Quickshell.Io
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../shared"
import "LauncherCalc.js" as Calc

// Spotlight — Apps / Files / Clipboard / Actions modes + calc + tags.
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

  readonly property bool tagging: !!tagEditEntry

  // Allowlisted Actions only — no unconstrained shell runners (#1142).
  readonly property var actionCatalog: [
    {
      id: "lock",
      name: "Lock screen",
      subtitle: "Action · Config.session lock",
      icon: "system-lock-screen",
      keywords: "lock screen sleep",
      destructive: false
    },
    {
      id: "logout",
      name: "Log out",
      subtitle: "Action · end Hyprland session",
      icon: "system-log-out",
      keywords: "logout log out exit session",
      destructive: false
    },
    {
      id: "settings",
      name: "Open Settings",
      subtitle: "Action · proteus-settings",
      icon: "proteus-settings",
      keywords: "settings preferences system",
      destructive: false
    },
    {
      id: "control-center",
      name: "Open Control Center",
      subtitle: "Action · notifications + quick settings",
      icon: "preferences-system-notifications",
      keywords: "control center notifications dnd",
      destructive: false
    },
    {
      id: "dnd-toggle",
      name: "Toggle Do Not Disturb",
      subtitle: "Action · suppress toasts",
      icon: "notifications-disabled",
      keywords: "dnd do not disturb quiet mute notifications",
      destructive: false
    },
    {
      id: "clear-notifications",
      name: "Clear notifications",
      subtitle: "Action · dismiss all",
      icon: "edit-clear-all",
      keywords: "clear notifications dismiss",
      destructive: false
    },
    {
      id: "reboot",
      name: "Reboot",
      subtitle: "Action · systemctl reboot",
      icon: "system-reboot",
      keywords: "reboot restart",
      destructive: true
    },
    {
      id: "shutdown",
      name: "Shut down",
      subtitle: "Action · systemctl poweroff",
      icon: "system-shutdown",
      keywords: "shutdown power off halt",
      destructive: true
    }
  ]

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

  // Spotlight chrome (Tahoe-like floating pill + sheet)
  readonly property int spotRadius: 22
  readonly property int spotRowH: 52
  readonly property color spotFill: Theme.light
      ? Qt.rgba(1, 1, 1, Math.max(Theme.chromeAlpha, 0.92))
      : Qt.rgba(0.16, 0.16, 0.17, Math.max(Theme.chromeAlpha, 0.88))
  readonly property color spotInset: Theme.light
      ? Qt.rgba(0, 0, 0, 0.04)
      : Qt.rgba(1, 1, 1, 0.06)

  function setMode(id) {
    if (mode === id)
      return
    mode = id
    list.currentIndex = root.firstSelectableIndex()
    if (id === "files") {
      root.refreshPlaces()
      root.queueFileSearch()
    } else if (id === "clipboard") {
      root.refreshClipboard()
    }
    claimSearchFocus()
  }

  function fuzzySubsequence(hay, q) {
    let hi = 0
    for (let qi = 0; qi < q.length; qi++) {
      const ch = q.charAt(qi)
      hi = hay.indexOf(ch, hi)
      if (hi < 0)
        return false
      hi++
    }
    return true
  }

  function scoreQuery(hay, q) {
    if (!q.length)
      return 0
    if (hay === q)
      return 1000
    if (hay.startsWith(q))
      return 850
    const words = hay.split(/[\s\-_/]+/)
    for (let i = 0; i < words.length; i++) {
      if (words[i].startsWith(q))
        return 700
    }
    const idx = hay.indexOf(q)
    if (idx >= 0)
      return 500 - Math.min(idx, 80)
    if (fuzzySubsequence(hay, q))
      return 180 + Math.max(0, 40 - (hay.length - q.length))
    return -1
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
    filesHint = q.length ? "Searching home folder…" : ""
    if (!q.length) {
      fileHits = []
      filesHint = ""
      return
    }
    fileProc.running = false
    fileProc.command = [
      "python3",
      "-c",
      "import json, os, sys\n"
          + "q = sys.argv[1].lower()\n"
          + "home = os.path.expanduser('~')\n"
          + "home_depth = home.count(os.sep)\n"
          + "skip = {'.git','node_modules','.cache','Trash','.npm','.cargo','.local'}\n"
          + "hits = []\n"
          + "capped = False\n"
          + "for root, dirs, files in os.walk(home):\n"
          + "  if root.count(os.sep) - home_depth > 5:\n"
          + "    dirs[:] = []\n"
          + "    continue\n"
          + "  dirs[:] = [d for d in dirs if d not in skip and not d.startswith('.')]\n"
          + "  for name in list(files) + list(dirs):\n"
          + "    if name.startswith('.') and (not q or q[0] != '.'):\n"
          + "      continue\n"
          + "    if q not in name.lower():\n"
          + "      continue\n"
          + "    path = os.path.join(root, name)\n"
          + "    hits.append({'path': path, 'name': name, 'dir': os.path.isdir(path)})\n"
          + "    if len(hits) >= 40:\n"
          + "      capped = True\n"
          + "      print(json.dumps({'hits': hits, 'capped': True})); raise SystemExit\n"
          + "print(json.dumps({'hits': hits, 'capped': False}))\n",
      q
    ]
    fileProc.running = true
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
    Quickshell.execDetached({
      command: [
        "bash",
        "-lc",
        "printf '%s\\n' " + shellQuote(line) + " | cliphist decode | wl-copy"
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
            subtitle: path,
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
          subtitle: f.path,
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
          subtitle: "Clipboard",
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
            subtitle: ok
              ? root.tagsSubtitle(a.id, a.genericName || "Application")
              : root.unavailableSubtitle(EnvGate.appBlockReason(a)),
            icon: EnvGate.resolveAppIcon(a),
            blocked: !ok,
            score: 400 - i,
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

    // Empty Apps query: calm Recents hierarchy (section headers) — or honest empty.
    // Do not dump alphabetical apps as a fake home; search/tags remain the browse path.
    if (!q.length && !tagFilter.length) {
      const recentRows = []
      const recentIds = Config.launcherRecentList()
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
        recentRows.push({
          kind: "app",
          entry: a,
          path: "",
          name: a.name,
          subtitle: ok
            ? root.tagsSubtitle(a.id, "Recent")
            : root.unavailableSubtitle(EnvGate.appBlockReason(a)),
          icon: EnvGate.resolveAppIcon(a),
          blocked: !ok,
          score: 2000 - r,
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
      // Skip alphabetical dump + settings browse on empty home — honest empty if none.
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
        rows.push({
          kind: "app",
          entry: a,
          path: "",
          name: a.name,
          subtitle: ok
            ? root.tagsSubtitle(a.id, a.genericName || "Application")
            : root.unavailableSubtitle(EnvGate.appBlockReason(a)),
          icon: EnvGate.resolveAppIcon(a),
          blocked: !ok,
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
    return rows.slice(0, 40)
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
    const id = String(actionId || "")
    // Allowlist gate — only catalog ids.
    let known = false
    for (let i = 0; i < root.actionCatalog.length; i++) {
      if (root.actionCatalog[i].id === id) {
        known = true
        break
      }
    }
    if (!known)
      return
    if (id === "lock")
      Config.session("lock")
    else if (id === "logout")
      Config.session("logout")
    else if (id === "reboot")
      Config.session("reboot")
    else if (id === "shutdown")
      Config.session("shutdown")
    else if (id === "settings")
      ShellState.openSettings()
    else if (id === "control-center")
      ShellState.openControlCenter()
    else if (id === "dnd-toggle")
      Notifications.toggleDnd()
    else if (id === "clear-notifications")
      Notifications.clearAll()
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
    if (!row || row.blocked || row.kind === "section" || row.kind === "hint")
      return
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
      ShellState.closeLauncher()
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
      Config.recordLauncherRecent(row.entry.id)
      row.entry.execute()
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
    return "Search apps"
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
      if (clipHint.length && !clipHits.length)
        return clipHint
      if (search.text.trim().length)
        return "No clipboard matches in recent history."
      return "Clipboard history is empty — needs cliphist + wl-paste watchers."
    }
    if (mode === "actions") {
      if (search.text.trim().length)
        return "No actions match."
      return "No allowlisted actions in catalog."
    }
    const t = search.text.trim()
    if (!t.length)
      return "No recent apps yet — type to search, or Ctrl+2–4 for Files / Clipboard / Actions."
    if (t === "#")
      return "Add tags via # on a result, or Settings → Desktop → Launcher."
    if (showUnavailable)
      return "No matches — including unavailable apps for this device."
    return "No matches."
  }

  function unavailableSubtitle(reason) {
    const r = String(reason || "").trim()
    if (!r.length)
      return "Unavailable on this device"
    if (r.toLowerCase().startsWith("unavailable"))
      return r
    return "Unavailable · " + r
  }

  // Floating Spotlight (Tahoe-shaped): pill search + results sheet
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
                if (root.tagging)
                  root.endTagEdit()
                else
                  ShellState.closeLauncher()
              }
              Keys.onDownPressed: root.moveSelection(1)
              Keys.onUpPressed: root.moveSelection(-1)
              Keys.onReturnPressed: root.launchIndex(list.currentIndex)
              Keys.onEnterPressed: root.launchIndex(list.currentIndex)
              Keys.onPressed: event => {
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
                  text: "Unavailable"
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
                cursorShape: modelData.blocked ? Qt.ForbiddenCursor : Qt.PointingHandCursor
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
          if (list.length) {
            root.filesHint = capped
                ? "Showing first 40 matches under ~ (depth ≤5)."
                : ""
          } else {
            root.filesHint = "No files match under ~ (depth ≤5, skips dotdirs)."
          }
        } catch (e) {
          root.fileHits = []
          root.filesHint = "File search failed — needs python3 on PATH."
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
        list.currentIndex = 0
        root.claimSearchFocus()
      } else {
        tagEditEntry = null
      }
    }
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
}
