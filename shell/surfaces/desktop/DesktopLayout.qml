import QtQuick

// Desktop widget frames — free place by default; optional center-anchored graph snap
// over the usable surface (shell insets exclude menu bar + dock).
QtObject {
  id: root

  property real surfaceWidth: 400
  property real surfaceHeight: 800
  property var widgets: []
  property bool snapToGrid: false

  // Graph-paper pitch (px). Origin = usable-surface center (dead-middle always snaps).
  readonly property real pitch: 40
  readonly property real margin: Math.max(8, Math.min(surfaceWidth, surfaceHeight) * 0.015)
  readonly property real originX: surfaceWidth * 0.5
  readonly property real originY: surfaceHeight * 0.5

  readonly property int halfCols: Math.max(1, Math.floor((surfaceWidth * 0.5 - margin) / pitch))
  readonly property int halfRows: Math.max(1, Math.floor((surfaceHeight * 0.5 - margin) / pitch))
  readonly property int gridCols: halfCols * 2 + 1
  readonly property int gridRows: halfRows * 2 + 1
  readonly property real cellWidth: pitch
  readonly property real cellHeight: pitch
  readonly property real gutter: 0

  function colSpanFor(type, size) {
    const s = String(size || "md")
    if (s === "sm")
      return 1
    if (s === "lg")
      return 4
    return 2
  }

  function rowSpanFor(type, size) {
    const t = String(type || "")
    const s = String(size || "md")
    if (t === "clock") {
      if (s === "lg")
        return 3
      if (s === "md")
        return 2
      return 2
    }
    if (s === "lg")
      return 2
    return 1
  }

  function contentWidth(type, size) {
    const maxW = Math.min(surfaceWidth - margin * 2, 420)
    if (type === "clock") {
      if (size === "sm")
        return Math.min(maxW * 0.55, 240)
      if (size === "md")
        return Math.min(maxW * 0.72, 320)
      return Math.min(maxW, 400)
    }
    if (size === "sm")
      return Math.min(maxW * 0.55, 220)
    if (size === "lg")
      return Math.min(maxW, 360)
    return Math.min(maxW * 0.78, 300)
  }

  function contentHeight(type, size) {
    if (type === "clock") {
      if (size === "sm")
        return 88
      if (size === "md")
        return 120
      return 160
    }
    if (size === "lg")
      return 120
    if (size === "sm")
      return 72
    return 96
  }

  // Keep the whole widget inside the usable surface.
  function clampPixel(px, py, width, height) {
    const minX = margin
    const minY = margin
    const maxX = Math.max(minX, surfaceWidth - width - margin)
    const maxY = Math.max(minY, surfaceHeight - height - margin)
    return {
      x: Math.max(minX, Math.min(maxX, px)),
      y: Math.max(minY, Math.min(maxY, py))
    }
  }

  // Snap widget center to nearest graph intersection; clamp to usable area.
  function snapPixel(px, py, width, height) {
    const cx = px + width * 0.5
    const cy = py + height * 0.5
    let ix = Math.round((cx - originX) / pitch)
    let iy = Math.round((cy - originY) / pitch)
    // Keep center on a drawn intersection (halfCols/halfRows).
    ix = Math.max(-halfCols, Math.min(halfCols, ix))
    iy = Math.max(-halfRows, Math.min(halfRows, iy))
    const gx = ix * pitch
    const gy = iy * pitch
    return clampPixel(originX + gx - width * 0.5, originY + gy - height * 0.5, width, height)
  }

  function freeNormFromPixel(px, py, width, height) {
    const spanX = Math.max(1, surfaceWidth - width - 2 * margin)
    const spanY = Math.max(1, surfaceHeight - height - 2 * margin)
    return {
      x: Math.max(0, Math.min(1, (px - margin) / spanX)),
      y: Math.max(0, Math.min(1, (py - margin) / spanY))
    }
  }

  function pixelFromFreeNorm(nx, ny, width, height) {
    const spanX = Math.max(0, surfaceWidth - width - 2 * margin)
    const spanY = Math.max(0, surfaceHeight - height - 2 * margin)
    return {
      x: margin + Math.max(0, Math.min(1, Number(nx))) * spanX,
      y: margin + Math.max(0, Math.min(1, Number(ny))) * spanY
    }
  }

  function snapNorm(nx, ny, width, height) {
    const raw = pixelFromFreeNorm(nx, ny, width, height)
    const snapped = snapPixel(raw.x, raw.y, width, height)
    return freeNormFromPixel(snapped.x, snapped.y, width, height)
  }

  function normFromPixel(px, py, colSpan, rowSpan, width, height) {
    if (snapToGrid) {
      const snapped = snapPixel(px, py, width, height)
      return freeNormFromPixel(snapped.x, snapped.y, width, height)
    }
    return freeNormFromPixel(px, py, width, height)
  }

  readonly property var frames: {
    const list = widgets || []
    const out = []
    for (let i = 0; i < list.length; i++) {
      const w = list[i]
      if (!w || !w.enabled)
        continue
      const size = w.size || "md"
      const colSpan = colSpanFor(w.type, size)
      const rowSpan = rowSpanFor(w.type, size)
      const width = contentWidth(w.type, size)
      const height = contentHeight(w.type, size)
      let x
      let y
      if (snapToGrid) {
        const snapped = snapNorm(w.x, w.y, width, height)
        const p = pixelFromFreeNorm(snapped.x, snapped.y, width, height)
        x = p.x
        y = p.y
      } else {
        const p = pixelFromFreeNorm(w.x, w.y, width, height)
        x = p.x
        y = p.y
      }
      out.push({
        id: String(w.id),
        type: String(w.type),
        x: x,
        y: y,
        width: width,
        height: height,
        colSpan: colSpan,
        rowSpan: rowSpan,
        widget: w
      })
    }
    return out
  }
}
