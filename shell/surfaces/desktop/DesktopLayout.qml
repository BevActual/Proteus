import QtQuick

// Desktop widget frames — free place by default; optional snap-to-grid (iOS-like cells).
QtObject {
  id: root

  property real surfaceWidth: 400
  property real surfaceHeight: 800
  property var widgets: []
  property bool snapToGrid: false

  readonly property int gridCols: 8
  readonly property int gridRows: 12
  readonly property real gutter: 8
  readonly property real margin: Math.max(12, Math.min(surfaceWidth, surfaceHeight) * 0.02)

  readonly property real cellWidth: {
    const inner = Math.max(1, surfaceWidth - margin * 2 - gutter * (gridCols - 1))
    return inner / gridCols
  }

  readonly property real cellHeight: {
    const inner = Math.max(1, surfaceHeight - margin * 2 - gutter * (gridRows - 1))
    return inner / gridRows
  }

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

  // Content sizes (Mac-like free place) — not forced to cell multiples.
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

  function maxCol(colSpan) {
    return Math.max(0, gridCols - Math.max(1, colSpan))
  }

  function maxRow(rowSpan) {
    return Math.max(0, gridRows - Math.max(1, rowSpan))
  }

  function cellOriginX(col) {
    return margin + col * (cellWidth + gutter)
  }

  function cellOriginY(row) {
    return margin + row * (cellHeight + gutter)
  }

  function clampCell(col, row, colSpan, rowSpan) {
    return {
      col: Math.max(0, Math.min(maxCol(colSpan), Math.round(col))),
      row: Math.max(0, Math.min(maxRow(rowSpan), Math.round(row)))
    }
  }

  function snapPixel(px, py, colSpan, rowSpan) {
    const stepX = cellWidth + gutter
    const stepY = cellHeight + gutter
    const rawCol = stepX > 0 ? (px - margin) / stepX : 0
    const rawRow = stepY > 0 ? (py - margin) / stepY : 0
    const c = clampCell(rawCol, rawRow, colSpan, rowSpan)
    return {
      col: c.col,
      row: c.row,
      x: cellOriginX(c.col),
      y: cellOriginY(c.row)
    }
  }

  function snapNorm(nx, ny, colSpan, rowSpan) {
    const mc = maxCol(colSpan)
    const mr = maxRow(rowSpan)
    const rawCol = mc > 0 ? Number(nx) * mc : 0
    const rawRow = mr > 0 ? Number(ny) * mr : 0
    const c = clampCell(rawCol, rawRow, colSpan, rowSpan)
    return {
      col: c.col,
      row: c.row,
      x: mc > 0 ? c.col / mc : 0,
      y: mr > 0 ? c.row / mr : 0
    }
  }

  function freeNormFromPixel(px, py, width, height) {
    const maxX = Math.max(1, surfaceWidth - width - margin)
    const maxY = Math.max(1, surfaceHeight - height - margin)
    const nx = (px - margin) / maxX
    const ny = (py - margin) / maxY
    return {
      x: Math.max(0, Math.min(1, nx)),
      y: Math.max(0, Math.min(1, ny))
    }
  }

  function normFromPixel(px, py, colSpan, rowSpan, width, height) {
    if (snapToGrid) {
      const snapped = snapPixel(px, py, colSpan, rowSpan)
      const mc = maxCol(colSpan)
      const mr = maxRow(rowSpan)
      return {
        x: mc > 0 ? snapped.col / mc : 0,
        y: mr > 0 ? snapped.row / mr : 0
      }
    }
    return freeNormFromPixel(px, py, width, height)
  }

  function clampPixel(px, py, width, height) {
    const maxX = Math.max(0, surfaceWidth - width)
    const maxY = Math.max(0, surfaceHeight - height)
    return {
      x: Math.max(0, Math.min(maxX, px)),
      y: Math.max(0, Math.min(maxY, py))
    }
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
      const maxX = Math.max(0, surfaceWidth - width - margin)
      const maxY = Math.max(0, surfaceHeight - height - margin)
      let x
      let y
      if (snapToGrid) {
        const snapped = snapNorm(w.x, w.y, colSpan, rowSpan)
        x = cellOriginX(snapped.col)
        y = cellOriginY(snapped.row)
      } else {
        const nx = Math.max(0, Math.min(1, Number(w.x)))
        const ny = Math.max(0, Math.min(1, Number(w.y)))
        x = margin + nx * maxX
        y = margin + ny * maxY
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
