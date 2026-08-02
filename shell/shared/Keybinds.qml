pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
  id: root

  // Friendly catalog → real Hyprland binds. Overrides live in
  // ~/.config/proteus/keybinds.json; applied file is
  // ~/.config/hypr/proteus-keybinds.conf (sourced by Hyprland).
  readonly property var catalog: [
    {
      id: "terminal",
      category: "Apps",
      label: "New Terminal",
      mods: "SUPER",
      key: "Return",
      dispatcher: "exec",
      arg: "proteus-terminal"
    },
    {
      id: "launcher",
      category: "Apps",
      label: "Beacon (system search)",
      mods: "SUPER",
      key: "SPACE",
      dispatcher: "global",
      arg: "proteus:launcher"
    },
    {
      id: "launcher-alt",
      category: "Apps",
      label: "Beacon (alternate)",
      mods: "SUPER",
      key: "D",
      dispatcher: "global",
      arg: "proteus:launcher"
    },
    {
      id: "settings",
      category: "Apps",
      label: "Open Settings",
      mods: "SUPER",
      key: "comma",
      dispatcher: "global",
      arg: "proteus:settings"
    },
    {
      id: "lock",
      category: "Session",
      label: "Lock Screen",
      mods: "SUPER",
      key: "L",
      dispatcher: "global",
      arg: "proteus:lock"
    },
    {
      id: "customize-desktop",
      category: "Session",
      label: "Customize Desktop Widgets",
      mods: "SUPER SHIFT",
      key: "W",
      dispatcher: "global",
      arg: "proteus:customize-desktop"
    },
    {
      id: "focus-cycle",
      category: "Session",
      label: "Focus Mode (cycle)",
      mods: "SUPER SHIFT",
      key: "F",
      dispatcher: "global",
      arg: "proteus:focus-cycle"
    },
    {
      id: "enter-console",
      category: "Session",
      label: "Enter Console",
      mods: "SUPER SHIFT",
      key: "C",
      dispatcher: "exec",
      arg: "proteus-posture console"
    },
    {
      id: "console-nav",
      category: "Session",
      label: "Console navigation / switcher",
      mods: "SUPER",
      key: "Home",
      dispatcher: "global",
      arg: "proteus:console-nav"
    },
    {
      id: "kill",
      category: "Windows",
      label: "Close Window",
      mods: "SUPER",
      key: "Q",
      dispatcher: "killactive",
      arg: ""
    },
    {
      id: "fullscreen",
      category: "Windows",
      label: "Toggle Fullscreen",
      mods: "SUPER",
      key: "F",
      dispatcher: "fullscreen",
      arg: ""
    },
    {
      id: "exit",
      category: "Session",
      label: "Exit Hyprland",
      mods: "SUPER SHIFT",
      key: "E",
      dispatcher: "exit",
      arg: ""
    },
    {
      id: "ws1",
      category: "Workspaces",
      label: "Space 1",
      mods: "SUPER",
      key: "1",
      dispatcher: "exec",
      arg: "proteus-workspace goto 1"
    },
    {
      id: "ws2",
      category: "Workspaces",
      label: "Space 2",
      mods: "SUPER",
      key: "2",
      dispatcher: "exec",
      arg: "proteus-workspace goto 2"
    },
    {
      id: "ws3",
      category: "Workspaces",
      label: "Space 3",
      mods: "SUPER",
      key: "3",
      dispatcher: "exec",
      arg: "proteus-workspace goto 3"
    },
    {
      id: "ws4",
      category: "Workspaces",
      label: "Space 4",
      mods: "SUPER",
      key: "4",
      dispatcher: "exec",
      arg: "proteus-workspace goto 4"
    },
    {
      id: "ws5",
      category: "Workspaces",
      label: "Space 5",
      mods: "SUPER",
      key: "5",
      dispatcher: "exec",
      arg: "proteus-workspace goto 5"
    },
    {
      id: "ws6",
      category: "Workspaces",
      label: "Space 6",
      mods: "SUPER",
      key: "6",
      dispatcher: "exec",
      arg: "proteus-workspace goto 6"
    },
    {
      id: "ws1-local",
      category: "Workspaces",
      label: "Space 1 (this display)",
      mods: "SUPER CTRL",
      key: "1",
      dispatcher: "exec",
      arg: "proteus-workspace goto 1 --local"
    },
    {
      id: "ws2-local",
      category: "Workspaces",
      label: "Space 2 (this display)",
      mods: "SUPER CTRL",
      key: "2",
      dispatcher: "exec",
      arg: "proteus-workspace goto 2 --local"
    },
    {
      id: "ws3-local",
      category: "Workspaces",
      label: "Space 3 (this display)",
      mods: "SUPER CTRL",
      key: "3",
      dispatcher: "exec",
      arg: "proteus-workspace goto 3 --local"
    },
    {
      id: "ws4-local",
      category: "Workspaces",
      label: "Space 4 (this display)",
      mods: "SUPER CTRL",
      key: "4",
      dispatcher: "exec",
      arg: "proteus-workspace goto 4 --local"
    },
    {
      id: "ws5-local",
      category: "Workspaces",
      label: "Space 5 (this display)",
      mods: "SUPER CTRL",
      key: "5",
      dispatcher: "exec",
      arg: "proteus-workspace goto 5 --local"
    },
    {
      id: "ws6-local",
      category: "Workspaces",
      label: "Space 6 (this display)",
      mods: "SUPER CTRL",
      key: "6",
      dispatcher: "exec",
      arg: "proteus-workspace goto 6 --local"
    },
    {
      id: "move1",
      category: "Workspaces",
      label: "Move Window to Space 1",
      mods: "SUPER SHIFT",
      key: "1",
      dispatcher: "exec",
      arg: "proteus-workspace move 1"
    },
    {
      id: "move2",
      category: "Workspaces",
      label: "Move Window to Space 2",
      mods: "SUPER SHIFT",
      key: "2",
      dispatcher: "exec",
      arg: "proteus-workspace move 2"
    },
    {
      id: "move3",
      category: "Workspaces",
      label: "Move Window to Space 3",
      mods: "SUPER SHIFT",
      key: "3",
      dispatcher: "exec",
      arg: "proteus-workspace move 3"
    },
    {
      id: "move4",
      category: "Workspaces",
      label: "Move Window to Space 4",
      mods: "SUPER SHIFT",
      key: "4",
      dispatcher: "exec",
      arg: "proteus-workspace move 4"
    },
    {
      id: "move5",
      category: "Workspaces",
      label: "Move Window to Space 5",
      mods: "SUPER SHIFT",
      key: "5",
      dispatcher: "exec",
      arg: "proteus-workspace move 5"
    },
    {
      id: "move6",
      category: "Workspaces",
      label: "Move Window to Space 6",
      mods: "SUPER SHIFT",
      key: "6",
      dispatcher: "exec",
      arg: "proteus-workspace move 6"
    },
    {
      id: "screenshot-region",
      category: "Capture",
      label: "Screenshot region (annotate)",
      mods: "SUPER SHIFT",
      key: "S",
      dispatcher: "exec",
      arg: "proteus-screenshot region"
    },
    {
      id: "screenshot-screen",
      category: "Capture",
      label: "Screenshot screen (annotate)",
      mods: "",
      key: "Print",
      dispatcher: "exec",
      arg: "proteus-screenshot screen"
    },
    {
      id: "clipboard-history",
      category: "Capture",
      label: "Clipboard history",
      mods: "SUPER SHIFT",
      key: "V",
      dispatcher: "exec",
      arg: "proteus-clipboard"
    },
    {
      id: "color-picker",
      category: "Capture",
      label: "Color picker",
      mods: "SUPER SHIFT",
      key: "C",
      dispatcher: "exec",
      arg: "proteus-colorpick"
    },
    {
      id: "volume-up",
      category: "Media",
      label: "Volume up",
      mods: "",
      key: "XF86AudioRaiseVolume",
      dispatcher: "global",
      arg: "proteus:volume-up"
    },
    {
      id: "volume-down",
      category: "Media",
      label: "Volume down",
      mods: "",
      key: "XF86AudioLowerVolume",
      dispatcher: "global",
      arg: "proteus:volume-down"
    },
    {
      id: "volume-mute",
      category: "Media",
      label: "Volume mute",
      mods: "",
      key: "XF86AudioMute",
      dispatcher: "global",
      arg: "proteus:volume-mute"
    },
    {
      id: "brightness-up",
      category: "Media",
      label: "Brightness up",
      mods: "",
      key: "XF86MonBrightnessUp",
      dispatcher: "global",
      arg: "proteus:brightness-up"
    },
    {
      id: "brightness-down",
      category: "Media",
      label: "Brightness down",
      mods: "",
      key: "XF86MonBrightnessDown",
      dispatcher: "global",
      arg: "proteus:brightness-down"
    }
  ]

  property var overrides: ({})
  property string recordingId: ""
  property string search: ""
  property string statusMessage: ""
  property string conflictId: ""
  property bool loaded: false
  property int listRevision: 0

  onSearchChanged: listRevision++
  onOverridesChanged: listRevision++
  onRecordingIdChanged: listRevision++

  readonly property string jsonPath: Quickshell.env("HOME") + "/.config/proteus/keybinds.json"
  readonly property string confPath: Quickshell.env("HOME") + "/.config/hypr/proteus-keybinds.conf"

  readonly property var categories: {
    const seen = []
    for (let i = 0; i < catalog.length; i++) {
      const c = catalog[i].category
      if (seen.indexOf(c) < 0)
        seen.push(c)
    }
    return seen
  }

  function entryById(id) {
    for (let i = 0; i < catalog.length; i++) {
      if (catalog[i].id === id)
        return catalog[i]
    }
    return null
  }

  function effective(entry) {
    const o = overrides[entry.id]
    if (o && o.mods && o.key)
      return {
        mods: String(o.mods),
        key: String(o.key)
      }
    return {
      mods: entry.mods,
      key: entry.key
    }
  }

  function isCustom(id) {
    return !!(overrides[id] && overrides[id].mods && overrides[id].key)
  }

  function formatChord(mods, key) {
    const parts = String(mods).trim().split(/\s+/).filter(p => p.length)
    const pretty = parts.map(p => {
      const u = p.toUpperCase()
      if (u === "SUPER" || u === "MOD4")
        return "⌘"
      if (u === "CTRL" || u === "CONTROL")
        return "Ctrl"
      if (u === "ALT" || u === "MOD1")
        return "Alt"
      if (u === "SHIFT")
        return "Shift"
      return p
    })
    let k = String(key)
    const ku = k.toUpperCase()
    if (ku === "RETURN" || ku === "ENTER")
      k = "Return"
    else if (ku === "SPACE")
      k = "Space"
    else if (ku === "COMMA")
      k = ","
    else if (ku === "ESCAPE" || ku === "ESC")
      k = "Esc"
    else if (k.length === 1)
      k = k.toUpperCase()
    pretty.push(k)
    return pretty.join(" + ")
  }

  function chordFor(entry) {
    const e = effective(entry)
    return formatChord(e.mods, e.key)
  }

  function matchesSearch(entry) {
    const q = search.trim().toLowerCase()
    if (!q)
      return true
    return entry.label.toLowerCase().indexOf(q) >= 0
        || entry.category.toLowerCase().indexOf(q) >= 0
        || chordFor(entry).toLowerCase().indexOf(q) >= 0
        || entry.id.toLowerCase().indexOf(q) >= 0
  }

  function rowsForCategory(category) {
    const rows = []
    for (let i = 0; i < catalog.length; i++) {
      const e = catalog[i]
      if (e.category === category && matchesSearch(e))
        rows.push(e)
    }
    return rows
  }

  function chordKey(mods, key) {
    return String(mods).trim().toUpperCase().replace(/\s+/g, " ") + "|" + String(key).trim().toUpperCase()
  }

  function findConflict(id, mods, key) {
    const want = chordKey(mods, key)
    for (let i = 0; i < catalog.length; i++) {
      const e = catalog[i]
      if (e.id === id)
        continue
      const eff = effective(e)
      if (chordKey(eff.mods, eff.key) === want)
        return e.id
    }
    return ""
  }

  function qtKeyToHypr(key, text) {
    if (key === Qt.Key_Return || key === Qt.Key_Enter)
      return "Return"
    if (key === Qt.Key_Space)
      return "SPACE"
    if (key === Qt.Key_Tab)
      return "Tab"
    if (key === Qt.Key_Backspace)
      return "BackSpace"
    if (key === Qt.Key_Escape)
      return "Escape"
    if (key === Qt.Key_Comma)
      return "comma"
    if (key === Qt.Key_Period)
      return "period"
    if (key === Qt.Key_Slash)
      return "slash"
    if (key === Qt.Key_Minus)
      return "minus"
    if (key === Qt.Key_Equal)
      return "equal"
    if (key >= Qt.Key_F1 && key <= Qt.Key_F12)
      return "F" + (key - Qt.Key_F1 + 1)
    if (key >= Qt.Key_0 && key <= Qt.Key_9)
      return String(key - Qt.Key_0)
    if (key >= Qt.Key_A && key <= Qt.Key_Z)
      return String.fromCharCode(65 + (key - Qt.Key_A))
    if (text && text.length === 1 && /[a-zA-Z0-9]/.test(text))
      return text.toUpperCase()
    return ""
  }

  function modsFromEvent(modifiers) {
    const parts = []
    if (modifiers & Qt.MetaModifier)
      parts.push("SUPER")
    if (modifiers & Qt.ControlModifier)
      parts.push("CTRL")
    if (modifiers & Qt.AltModifier)
      parts.push("ALT")
    if (modifiers & Qt.ShiftModifier)
      parts.push("SHIFT")
    return parts.join(" ")
  }

  function startRecording(id) {
    recordingId = id
    conflictId = ""
    statusMessage = "Press a new shortcut… Esc to cancel"
  }

  function cancelRecording() {
    recordingId = ""
    conflictId = ""
    statusMessage = ""
  }

  function handleKeyEvent(event) {
    if (!recordingId)
      return false

    event.accepted = true

    if (event.key === Qt.Key_Escape) {
      cancelRecording()
      return true
    }

    // Modifier-only — wait for a real key
    if (event.key === Qt.Key_Meta || event.key === Qt.Key_Control
        || event.key === Qt.Key_Alt || event.key === Qt.Key_Shift
        || event.key === Qt.Key_Super_L || event.key === Qt.Key_Super_R)
      return true

    const mods = modsFromEvent(event.modifiers)
    if (!mods) {
      statusMessage = "Include at least one modifier (⌘ / Ctrl / Alt)"
      return true
    }

    const key = qtKeyToHypr(event.key, event.text)
    if (!key) {
      statusMessage = "That key isn’t supported yet"
      return true
    }

    const conflict = findConflict(recordingId, mods, key)
    if (conflict) {
      conflictId = conflict
      const other = entryById(conflict)
      statusMessage = "Conflicts with “" + (other ? other.label : conflict) + "” — choose another"
      return true
    }

    commit(recordingId, mods, key)
    return true
  }

  function commit(id, mods, key) {
    const next = Object.assign({}, overrides)
    next[id] = {
      mods: mods,
      key: key
    }
    overrides = next
    recordingId = ""
    conflictId = ""
    statusMessage = "Saved · writing Hyprland binds…"
    persistAndApply()
  }

  function resetOne(id) {
    if (!overrides[id])
      return
    const next = Object.assign({}, overrides)
    delete next[id]
    overrides = next
    statusMessage = "Restored default"
    persistAndApply()
  }

  function resetAll() {
    overrides = ({})
    statusMessage = "All shortcuts restored to defaults"
    persistAndApply()
  }

  function bindLine(entry) {
    const e = effective(entry)
    const mods = String(e.mods || "").trim()
    const key = e.key
    // Hyprland: empty mods → "bind = , Print, …"
    const modPart = mods.length ? mods : ""
    if (entry.dispatcher === "exec")
      return "bind = " + modPart + ", " + key + ", exec, " + entry.arg
    if (entry.dispatcher === "global")
      return "bind = " + modPart + ", " + key + ", global, " + entry.arg
    if (entry.arg && entry.arg.length)
      return "bind = " + modPart + ", " + key + ", " + entry.dispatcher + ", " + entry.arg
    return "bind = " + modPart + ", " + key + ", " + entry.dispatcher + ","
  }

  function confText() {
    let out = "# Generated by Proteus Settings — Keyboard\n"
    out += "# Edit here or in Settings → Keyboard. Reloaded via hyprctl.\n\n"
    let cat = ""
    for (let i = 0; i < catalog.length; i++) {
      const e = catalog[i]
      if (e.category !== cat) {
        cat = e.category
        out += "# " + cat + "\n"
      }
      out += bindLine(e) + "\n"
    }
    // Fixed mouse binds (not in the rebind catalog): Hyprland draws no
    // titlebars, so ⌘+drag anywhere on a window is how floating windows move
    // (edge/corner resize without a modifier comes from resize_on_border).
    out += "# Mouse\n"
    out += "bindm = SUPER, mouse:272, movewindow\n"
    out += "bindm = SUPER, mouse:273, resizewindow\n"
    return out
  }

  function utf8Hex(str) {
    const s = unescape(encodeURIComponent(str))
    let hex = ""
    for (let i = 0; i < s.length; i++)
      hex += ("0" + s.charCodeAt(i).toString(16)).slice(-2)
    return hex
  }

  function persistAndApply() {
    const jsonHex = utf8Hex(JSON.stringify(overrides))
    const confHex = utf8Hex(confText())
    writeProc.command = ["python3", "-c",
      "import os, pathlib, subprocess\n"
      + "home = pathlib.Path(os.environ['HOME'])\n"
      + "(home / '.config/proteus').mkdir(parents=True, exist_ok=True)\n"
      + "(home / '.config/hypr').mkdir(parents=True, exist_ok=True)\n"
      + "(home / '.config/proteus/keybinds.json').write_text(bytes.fromhex('" + jsonHex + "').decode(), encoding='utf-8')\n"
      + "(home / '.config/hypr/proteus-keybinds.conf').write_text(bytes.fromhex('" + confHex + "').decode(), encoding='utf-8')\n"
      + "hypr = home / '.config/hypr/hyprland.conf'\n"
      + "if hypr.is_file():\n"
      + "    text = hypr.read_text(encoding='utf-8')\n"
      + "    if 'proteus-keybinds.conf' not in text:\n"
      + "        hypr.write_text(text.rstrip() + '\\n\\n# Proteus keyboard shortcuts (Settings → Keyboard)\\nsource = ~/.config/hypr/proteus-keybinds.conf\\n', encoding='utf-8')\n"
      + "subprocess.run(['hyprctl', 'reload'], check=False, capture_output=True)\n"
      + "print('ok')\n"
    ]
    writeProc.running = false
    writeProc.running = true
  }

  function openConfInEditor() {
    Quickshell.execDetached({
      command: ["bash", "-lc", "mkdir -p \"$HOME/.config/hypr\"; touch \"$HOME/.config/hypr/proteus-keybinds.conf\"; (command -v xdg-open >/dev/null && xdg-open \"$HOME/.config/hypr/proteus-keybinds.conf\") || exec proteus-terminal -e nvim \"$HOME/.config/hypr/proteus-keybinds.conf\""]
    })
  }

  Process {
    id: loadProc
    command: ["bash", "-lc", "test -f \"$HOME/.config/proteus/keybinds.json\" && cat \"$HOME/.config/proteus/keybinds.json\" || echo '{}'"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const parsed = JSON.parse(text.trim() || "{}")
          root.overrides = parsed && typeof parsed === "object" ? parsed : ({})
        } catch (e) {
          root.overrides = ({})
        }
        root.loaded = true
        root.persistAndApply()
      }
    }
  }

  Process {
    id: writeProc
    command: ["true"]
    stdout: StdioCollector {
      onStreamFinished: {
        if (text.trim() === "ok") {
          if (root.statusMessage.indexOf("writing") >= 0 || root.statusMessage.indexOf("Saved") >= 0 || root.statusMessage.indexOf("Restored") >= 0 || root.statusMessage.indexOf("defaults") >= 0)
            root.statusMessage = "Applied to Hyprland"
        }
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        if (text && text.trim().length)
          root.statusMessage = "Write issue: " + text.trim().split("\n")[0]
      }
    }
  }

  Component.onCompleted: {
    loadProc.running = true
  }
}
