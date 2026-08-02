pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Custom special workspaces — settings.json specialWorkspaces SoT.
// Reserved scratch / minimized stay product-fixed (Scratchpad + dock).
// Index Super+Alt+1–8 / Super+Alt+Shift+1–8 via special-*-index.
// Optional per-slug toggle + move chords → specialWorkspaceChords /
// specialWorkspaceMoveChords + Hypr binds.
Singleton {
  id: root

  readonly property int maxCustom: 8
  readonly property int maxNameLen: 24
  readonly property var reserved: ["scratch", "minimized"]
  property int rev: 0

  // Chord recording (Spaces leaf — not Keyboard catalog ids)
  // recordingKind: "" | "toggle" | "move"
  property string recordingName: ""
  property string recordingKind: ""
  property string chordStatus: ""

  readonly property string helper: Config.scriptsDir + "/proteus-workspace"
  readonly property bool isRecording: recordingName.length > 0

  function isReserved(name) {
    const s = String(name || "").trim().toLowerCase()
    for (let i = 0; i < root.reserved.length; i++) {
      if (root.reserved[i] === s)
        return true
    }
    return false
  }

  function slugify(raw) {
    let s = String(raw || "").trim().toLowerCase()
    s = s.replace(/[^a-z0-9-]+/g, "-").replace(/-+/g, "-").replace(/^-|-$/g, "")
    if (!s.length)
      return ""
    if (s[0] < "a" || s[0] > "z")
      s = "w-" + s
    if (s.length > root.maxNameLen)
      s = s.slice(0, root.maxNameLen).replace(/-$/g, "")
    return s
  }

  function normalizeList(raw) {
    const out = []
    const seen = ({})
    const src = Array.isArray(raw) ? raw : []
    for (let i = 0; i < src.length; i++) {
      const s = root.slugify(src[i])
      if (!s.length || root.isReserved(s) || seen[s])
        continue
      seen[s] = true
      out.push(s)
      if (out.length >= root.maxCustom)
        break
    }
    return out
  }

  function names() {
    return root.normalizeList(Config.specialWorkspaces)
  }

  function sanitizeMods(mods) {
    const allowed = ({
      "SUPER": 1, "MOD4": 1, "CTRL": 1, "CONTROL": 1,
      "ALT": 1, "MOD1": 1, "SHIFT": 1
    })
    const parts = String(mods || "").trim().toUpperCase().split(/\s+/)
    const out = []
    for (let i = 0; i < parts.length; i++) {
      let p = parts[i]
      if (p === "CONTROL")
        p = "CTRL"
      if (p === "MOD4")
        p = "SUPER"
      if (p === "MOD1")
        p = "ALT"
      if (allowed[p] && out.indexOf(p) < 0)
        out.push(p)
    }
    return out.join(" ")
  }

  function sanitizeKey(key) {
    const k = String(key || "").trim()
    if (!k.length)
      return ""
    if (/^[0-9]$/.test(k))
      return k
    if (/^[A-Za-z]$/.test(k))
      return k.toUpperCase()
    if (/^F([1-9]|1[0-2])$/i.test(k))
      return k.toUpperCase()
    const ku = k.toUpperCase()
    const ok = ({
      "RETURN": "Return", "ENTER": "Return", "SPACE": "SPACE",
      "TAB": "Tab", "ESCAPE": "Escape", "ESC": "Escape",
      "COMMA": "comma", "PERIOD": "period", "SLASH": "slash",
      "MINUS": "minus", "EQUAL": "equal", "BACKSPACE": "BackSpace"
    })
    return ok[ku] || ""
  }

  function normalizeChords(raw, nameList) {
    const names = nameList || root.names()
    const allowed = ({})
    for (let i = 0; i < names.length; i++)
      allowed[names[i]] = true
    const src = raw && typeof raw === "object" ? raw : ({})
    const out = ({})
    const keys = Object.keys(src)
    for (let i = 0; i < keys.length; i++) {
      const slug = root.slugify(keys[i])
      if (!slug.length || !allowed[slug])
        continue
      const row = src[keys[i]]
      if (!row || typeof row !== "object")
        continue
      const mods = root.sanitizeMods(row.mods)
      const key = root.sanitizeKey(row.key)
      if (!mods.length || !key.length)
        continue
      out[slug] = { mods: mods, key: key }
    }
    return out
  }

  function chordsMap() {
    return root.normalizeChords(Config.specialWorkspaceChords, root.names())
  }

  function moveChordsMap() {
    return root.normalizeChords(Config.specialWorkspaceMoveChords, root.names())
  }

  function chordFor(name) {
    const s = root.slugify(name)
    const m = root.chordsMap()
    return m[s] || null
  }

  function moveChordFor(name) {
    const s = root.slugify(name)
    const m = root.moveChordsMap()
    return m[s] || null
  }

  function chordLabel(name) {
    const c = root.chordFor(name)
    if (!c)
      return "Index Super+Alt+(slot) · Set custom…"
    return Keybinds.formatChord(c.mods, c.key)
  }

  function moveChordLabel(name) {
    const c = root.moveChordFor(name)
    if (!c)
      return "Index Super+Alt+Shift+(slot) · Set custom…"
    return Keybinds.formatChord(c.mods, c.key)
  }

  function save(list) {
    const names = root.normalizeList(list)
    Config.specialWorkspaces = names
    Config.specialWorkspaceChords = root.normalizeChords(Config.specialWorkspaceChords, names)
    Config.specialWorkspaceMoveChords = root.normalizeChords(Config.specialWorkspaceMoveChords, names)
    root.rev++
    root.applyBinds()
  }

  function saveChords(map) {
    const names = root.names()
    Config.specialWorkspaceChords = root.normalizeChords(map, names)
    root.rev++
    root.applyBinds()
  }

  function saveMoveChords(map) {
    const names = root.names()
    Config.specialWorkspaceMoveChords = root.normalizeChords(map, names)
    root.rev++
    root.applyBinds()
  }

  function _slugInNames(s) {
    const names = root.names()
    for (let i = 0; i < names.length; i++) {
      if (names[i] === s)
        return true
    }
    return false
  }

  function setChord(name, mods, key) {
    const s = root.slugify(name)
    if (!s.length || root.isReserved(s) || !root._slugInNames(s))
      return false
    const m = root.sanitizeMods(mods)
    const k = root.sanitizeKey(key)
    if (!m.length || !k.length)
      return false
    const next = Object.assign({}, root.chordsMap())
    next[s] = { mods: m, key: k }
    root.saveChords(next)
    return true
  }

  function setMoveChord(name, mods, key) {
    const s = root.slugify(name)
    if (!s.length || root.isReserved(s) || !root._slugInNames(s))
      return false
    const m = root.sanitizeMods(mods)
    const k = root.sanitizeKey(key)
    if (!m.length || !k.length)
      return false
    const next = Object.assign({}, root.moveChordsMap())
    next[s] = { mods: m, key: k }
    root.saveMoveChords(next)
    return true
  }

  function clearChord(name) {
    const s = root.slugify(name)
    const cur = root.chordsMap()
    if (!cur[s])
      return false
    const next = Object.assign({}, cur)
    delete next[s]
    root.saveChords(next)
    return true
  }

  function clearMoveChord(name) {
    const s = root.slugify(name)
    const cur = root.moveChordsMap()
    if (!cur[s])
      return false
    const next = Object.assign({}, cur)
    delete next[s]
    root.saveMoveChords(next)
    return true
  }

  function applyBinds() {
    if (typeof Keybinds !== "undefined" && Keybinds && typeof Keybinds.persistAndApply === "function")
      Keybinds.persistAndApply()
  }

  function startRecording(name) {
    const s = root.slugify(name)
    if (!s.length)
      return
    if (typeof Keybinds !== "undefined" && Keybinds && Keybinds.recordingId)
      Keybinds.cancelRecording()
    root.recordingName = s
    root.recordingKind = "toggle"
    root.chordStatus = "Press a new toggle shortcut… Esc to cancel"
  }

  function startMoveRecording(name) {
    const s = root.slugify(name)
    if (!s.length)
      return
    if (typeof Keybinds !== "undefined" && Keybinds && Keybinds.recordingId)
      Keybinds.cancelRecording()
    root.recordingName = s
    root.recordingKind = "move"
    root.chordStatus = "Press a new move shortcut… Esc to cancel"
  }

  function cancelRecording() {
    root.recordingName = ""
    root.recordingKind = ""
    root.chordStatus = ""
  }

  function _conflictInMap(map, skipSlug, want) {
    const slugs = Object.keys(map)
    for (let i = 0; i < slugs.length; i++) {
      if (slugs[i] === skipSlug)
        continue
      const c = map[slugs[i]]
      if (Keybinds.chordKey(c.mods, c.key) === want)
        return slugs[i]
    }
    return ""
  }

  function handleKeyEvent(event) {
    if (!root.recordingName.length)
      return false
    event.accepted = true
    if (event.key === Qt.Key_Escape) {
      root.cancelRecording()
      return true
    }
    if (event.key === Qt.Key_Meta || event.key === Qt.Key_Control
        || event.key === Qt.Key_Alt || event.key === Qt.Key_Shift
        || event.key === Qt.Key_Super_L || event.key === Qt.Key_Super_R)
      return true
    const mods = Keybinds.modsFromEvent(event.modifiers)
    if (!mods) {
      root.chordStatus = "Include at least one modifier (⌘ / Ctrl / Alt)"
      return true
    }
    const key = Keybinds.qtKeyToHypr(event.key, event.text)
    if (!key) {
      root.chordStatus = "That key isn’t supported yet"
      return true
    }
    const conflict = Keybinds.findConflict("", mods, key)
    if (conflict) {
      const other = Keybinds.entryById(conflict)
      root.chordStatus = "Conflicts with “"
          + (other ? other.label : conflict) + "” — choose another"
      return true
    }
    const want = Keybinds.chordKey(mods, key)
    const kind = root.recordingKind === "move" ? "move" : "toggle"
    // Cross-check both special chord maps (toggle ↔ move)
    const hitToggle = root._conflictInMap(root.chordsMap(),
                                          kind === "toggle" ? root.recordingName : "",
                                          want)
    if (hitToggle) {
      root.chordStatus = "Conflicts with toggle special:" + hitToggle + " — choose another"
      return true
    }
    const hitMove = root._conflictInMap(root.moveChordsMap(),
                                        kind === "move" ? root.recordingName : "",
                                        want)
    if (hitMove) {
      root.chordStatus = "Conflicts with move special:" + hitMove + " — choose another"
      return true
    }
    if (kind === "move")
      root.setMoveChord(root.recordingName, mods, key)
    else
      root.setChord(root.recordingName, mods, key)
    root.recordingName = ""
    root.recordingKind = ""
    root.chordStatus = "Saved · writing Hyprland binds…"
    return true
  }

  function add(name) {
    const s = root.slugify(name)
    if (!s.length || root.isReserved(s))
      return ""
    const list = root.names()
    if (list.length >= root.maxCustom)
      return ""
    for (let i = 0; i < list.length; i++) {
      if (list[i] === s)
        return s
    }
    list.push(s)
    root.save(list)
    return s
  }

  function rename(oldName, newName) {
    const from = root.slugify(oldName)
    const to = root.slugify(newName)
    if (!from.length || !to.length || root.isReserved(from) || root.isReserved(to))
      return false
    const list = root.names()
    let idx = -1
    for (let i = 0; i < list.length; i++) {
      if (list[i] === from)
        idx = i
      else if (list[i] === to)
        return false
    }
    if (idx < 0)
      return false
    list[idx] = to
    const chords = Object.assign({}, root.chordsMap())
    if (chords[from]) {
      chords[to] = chords[from]
      delete chords[from]
    }
    const moveChords = Object.assign({}, root.moveChordsMap())
    if (moveChords[from]) {
      moveChords[to] = moveChords[from]
      delete moveChords[from]
    }
    Config.specialWorkspaces = list
    Config.specialWorkspaceChords = root.normalizeChords(chords, list)
    Config.specialWorkspaceMoveChords = root.normalizeChords(moveChords, list)
    root.rev++
    root.applyBinds()
    return true
  }

  function remove(name) {
    const s = root.slugify(name)
    if (!s.length || root.isReserved(s))
      return false
    const list = root.names()
    const next = []
    for (let i = 0; i < list.length; i++) {
      if (list[i] !== s)
        next.push(list[i])
    }
    if (next.length === list.length)
      return false
    root.save(next)
    return true
  }

  function toggle(name) {
    const s = root.slugify(name)
    if (!s.length)
      return
    actionProc.command = ["bash", root.helper, "special-toggle", s]
    actionProc.running = false
    actionProc.running = true
  }

  function moveTo(name) {
    const s = root.slugify(name)
    if (!s.length)
      return
    actionProc.command = ["bash", root.helper, "special-move", s]
    actionProc.running = false
    actionProc.running = true
  }

  // Bind lines for Keybinds.confText — never logs secrets.
  function customBindLines() {
    const map = root.chordsMap()
    const slugs = Object.keys(map).sort()
    const lines = []
    for (let i = 0; i < slugs.length; i++) {
      const s = slugs[i]
      const c = map[s]
      const mods = root.sanitizeMods(c.mods)
      const key = root.sanitizeKey(c.key)
      if (!mods.length || !key.length)
        continue
      lines.push("bind = " + mods + ", " + key + ", exec, proteus-workspace special-toggle " + s)
    }
    return lines
  }

  function customMoveBindLines() {
    const map = root.moveChordsMap()
    const slugs = Object.keys(map).sort()
    const lines = []
    for (let i = 0; i < slugs.length; i++) {
      const s = slugs[i]
      const c = map[s]
      const mods = root.sanitizeMods(c.mods)
      const key = root.sanitizeKey(c.key)
      if (!mods.length || !key.length)
        continue
      lines.push("bind = " + mods + ", " + key + ", exec, proteus-workspace special-move " + s)
    }
    return lines
  }

  Connections {
    target: Config
    function onSpecialWorkspacesChanged() {
      root.rev++
    }
    function onSpecialWorkspaceChordsChanged() {
      root.rev++
    }
    function onSpecialWorkspaceMoveChordsChanged() {
      root.rev++
    }
  }

  Process {
    id: actionProc
    command: ["true"]
  }
}
