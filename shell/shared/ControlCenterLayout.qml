pragma Singleton

import Quickshell
import QtQuick

// Control Center module catalog + persisted layout (order / visibility / span / size).
// Customize (Phase 5) mutates Config.controlCenterLayout; capability filters still win.
Singleton {
  id: root

  readonly property int layoutVersion: 1

  // Size tokens → tile row height
  function heightForSize(size) {
    const s = String(size || "md")
    if (s === "sm")
      return 48
    if (s === "lg")
      return 80
    return 64
  }

  // Code SoT — available modules (tiles + plates). Chrome sections stay in ControlCenter.qml.
  readonly property var catalog: [
    { id: "sound", kind: "plate", defaultSpan: 2, defaultSize: "lg", label: "Sound" },
    { id: "display", kind: "plate", defaultSpan: 2, defaultSize: "md", label: "Display" },
    { id: "net", kind: "tile", defaultSpan: 1, defaultSize: "md", label: "Network" },
    { id: "bt", kind: "tile", defaultSpan: 1, defaultSize: "md", label: "Bluetooth" },
    { id: "localsend", kind: "tile", defaultSpan: 1, defaultSize: "md", label: "LocalSend" },
    { id: "power", kind: "tile", defaultSpan: 1, defaultSize: "md", label: "Power" },
    { id: "focus", kind: "tile", defaultSpan: 1, defaultSize: "md", label: "Focus" },
    { id: "appearance", kind: "tile", defaultSpan: 1, defaultSize: "md", label: "Appearance" },
    { id: "awake", kind: "tile", defaultSpan: 1, defaultSize: "md", label: "Keep Awake" },
    { id: "console", kind: "tile", defaultSpan: 2, defaultSize: "md", label: "Console" },
    { id: "host", kind: "tile", defaultSpan: 2, defaultSize: "md", label: "Host" },
    { id: "desktop", kind: "tile", defaultSpan: 2, defaultSize: "md", label: "Desktop" }
  ]

  function defaultLayout() {
    return {
      version: root.layoutVersion,
      columns: 2,
      plates: ["sound", "display"],
      tiles: [
        { id: "net", visible: true, span: 1, size: "md" },
        { id: "bt", visible: true, span: 1, size: "md" },
        { id: "localsend", visible: true, span: 1, size: "md" },
        { id: "power", visible: true, span: 1, size: "md" },
        { id: "focus", visible: true, span: 1, size: "md" },
        { id: "appearance", visible: true, span: 1, size: "md" },
        { id: "awake", visible: true, span: 1, size: "md" },
        { id: "console", visible: true, span: 2, size: "md" },
        { id: "host", visible: true, span: 2, size: "md" },
        { id: "desktop", visible: true, span: 2, size: "md" }
      ]
    }
  }

  function _normalizeEntry(raw, fallbackId) {
    const id = String((raw && raw.id) || fallbackId || "").trim()
    if (!id.length)
      return null
    let span = Number(raw && raw.span)
    if (span !== 1 && span !== 2)
      span = 1
    let size = String((raw && raw.size) || "md")
    if (size !== "sm" && size !== "md" && size !== "lg")
      size = "md"
    const visible = raw && raw.visible === false ? false : true
    return { id: id, visible: visible, span: span, size: size }
  }

  // Merge user layout with defaults (unknown version → defaults; missing ids appended).
  function resolvedLayout() {
    const def = root.defaultLayout()
    const raw = Config.controlCenterLayout
    if (!raw || typeof raw !== "object")
      return def
    const ver = Number(raw.version)
    if (ver !== root.layoutVersion)
      return def

    const byId = {}
    const tilesIn = Array.isArray(raw.tiles) ? raw.tiles : []
    for (let i = 0; i < tilesIn.length; i++) {
      const e = root._normalizeEntry(tilesIn[i], "")
      if (e)
        byId[e.id] = e
    }

    const outTiles = []
    const seen = {}
    // Preserve user order first
    for (let i = 0; i < tilesIn.length; i++) {
      const id = String((tilesIn[i] && tilesIn[i].id) || "").trim()
      if (!id.length || seen[id])
        continue
      // Only known catalog tile ids (not plates)
      let known = false
      for (let c = 0; c < root.catalog.length; c++) {
        if (root.catalog[c].id === id && root.catalog[c].kind === "tile") {
          known = true
          break
        }
      }
      if (!known)
        continue
      seen[id] = true
      outTiles.push(byId[id] || root._normalizeEntry({ id: id }, id))
    }
    // Append defaults for missing
    for (let i = 0; i < def.tiles.length; i++) {
      const d = def.tiles[i]
      if (seen[d.id])
        continue
      seen[d.id] = true
      outTiles.push(d)
    }

    let plates = Array.isArray(raw.plates) ? raw.plates.slice() : def.plates.slice()
    plates = plates.filter(p => p === "sound" || p === "display")
    if (plates.indexOf("sound") < 0)
      plates.unshift("sound")
    if (plates.indexOf("display") < 0)
      plates.push("display")

    let columns = Number(raw.columns)
    if (columns !== 2 && columns !== 3)
      columns = 2

    return {
      version: root.layoutVersion,
      columns: columns,
      plates: plates,
      tiles: outTiles
    }
  }

  function plateVisible(id) {
    const lay = root.resolvedLayout()
    return (lay.plates || []).indexOf(id) >= 0
  }

  function tileMeta(id) {
    const lay = root.resolvedLayout()
    const tiles = lay.tiles || []
    for (let i = 0; i < tiles.length; i++) {
      if (tiles[i].id === id)
        return tiles[i]
    }
    return { id: id, visible: true, span: 1, size: "md" }
  }

  function writeLayout(layout) {
    Config.controlCenterLayout = layout && typeof layout === "object" ? layout : root.defaultLayout()
    Config.flushSettings()
  }

  function resetLayout() {
    Config.controlCenterLayout = root.defaultLayout()
    Config.flushSettings()
  }

  function setTileVisible(id, visible) {
    const lay = root.resolvedLayout()
    const tiles = lay.tiles.slice()
    for (let i = 0; i < tiles.length; i++) {
      if (tiles[i].id === id) {
        tiles[i] = Object.assign({}, tiles[i], { visible: !!visible })
        break
      }
    }
    lay.tiles = tiles
    root.writeLayout(lay)
  }

  function setTileSize(id, size) {
    const lay = root.resolvedLayout()
    const tiles = lay.tiles.slice()
    for (let i = 0; i < tiles.length; i++) {
      if (tiles[i].id === id) {
        tiles[i] = Object.assign({}, tiles[i], { size: String(size || "md") })
        break
      }
    }
    lay.tiles = tiles
    root.writeLayout(lay)
  }

  function setTileSpan(id, span) {
    const lay = root.resolvedLayout()
    const tiles = lay.tiles.slice()
    const s = span === 2 ? 2 : 1
    for (let i = 0; i < tiles.length; i++) {
      if (tiles[i].id === id) {
        tiles[i] = Object.assign({}, tiles[i], { span: s })
        break
      }
    }
    lay.tiles = tiles
    root.writeLayout(lay)
  }

  function setColumns(n) {
    const lay = root.resolvedLayout()
    const cols = Number(n) === 3 ? 3 : 2
    lay.columns = cols
    root.writeLayout(lay)
  }

  function moveTile(id, delta) {
    const lay = root.resolvedLayout()
    const tiles = lay.tiles.slice()
    let idx = -1
    for (let i = 0; i < tiles.length; i++) {
      if (tiles[i].id === id) {
        idx = i
        break
      }
    }
    if (idx < 0)
      return
    const j = idx + delta
    if (j < 0 || j >= tiles.length)
      return
    const tmp = tiles[idx]
    tiles[idx] = tiles[j]
    tiles[j] = tmp
    lay.tiles = tiles
    root.writeLayout(lay)
  }

  function setPlateVisible(id, visible) {
    const lay = root.resolvedLayout()
    let plates = (lay.plates || []).slice()
    const i = plates.indexOf(id)
    if (visible && i < 0)
      plates.push(id)
    if (!visible && i >= 0)
      plates.splice(i, 1)
    // Keep sound first if present
    plates = plates.filter(p => p === "sound" || p === "display")
    lay.plates = plates
    root.writeLayout(lay)
  }

  // Bump when Config layout changes so QML bindings refresh.
  readonly property var layoutRev: Config.controlCenterLayout
}
