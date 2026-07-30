import QtQuick

// Span-aware grid frames — Customize drag snaps to cell origins; even gutters.
QtObject {
  id: root

  property real surfaceWidth: 400
  property real surfaceHeight: 800
  property var widgets: []

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

  function tileWidth(colSpan) {
    const c = Math.max(1, colSpan)
    return c * cellWidth + (c - 1) * gutter
  }

  function tileHeight(rowSpan) {
    const r = Math.max(1, rowSpan)
    return r * cellHeight + (r - 1) * gutter
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

  // Pixel top-left → snapped cell origin (pixels).
  function snapPixel(px, py, colSpan, rowSpan) {
    const mc = maxCol(colSpan)
    const mr = maxRow(rowSpan)
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

  // Normalized 0..1 top-left → snapped norms (discrete cells).
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

  function normFromPixel(px, py, colSpan, rowSpan) {
    const snapped = snapPixel(px, py, colSpan, rowSpan)
    const mc = maxCol(colSpan)
    const mr = maxRow(rowSpan)
    return {
      col: snapped.col,
      row: snapped.row,
      x: mc > 0 ? snapped.col / mc : 0,
      y: mr > 0 ? snapped.row / mr : 0
    }
  }

  readonly property var frames: {
    const list = widgets || []
    const out = []
    for (let i = 0; i < list.length; i++) {
      const w = list[i]
      if (!w || !w.enabled)
        continue
      const colSpan = colSpanFor(w.type, w.size || "md")
      const rowSpan = rowSpanFor(w.type, w.size || "md")
      const width = tileWidth(colSpan)
      const height = tileHeight(rowSpan)
      const snapped = snapNorm(w.x, w.y, colSpan, rowSpan)
      out.push({
        id: String(w.id),
        type: String(w.type),
        x: cellOriginX(snapped.col),
        y: cellOriginY(snapped.row),
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
