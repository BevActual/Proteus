import Quickshell
import QtQuick
import QtQuick.Layouts
import "../shared"

// HSV color graph — saturation/value plane + hue strip + hex field.
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: Theme.spaceSm

  property string hex: "#3d8bfd"
  property bool updatingFromHex: false
  property real hue: 210
  property real sat: 0.75
  property real val: 0.99
  property string lastEmittedHex: ""
  // Live preview signal every distinct hex; commit coalesces disk/hypr work.
  property int commitDebounceMs: 80

  signal hexEdited(string hex)
  signal hexCommitted(string hex)

  Timer {
    id: commitTimer
    interval: Math.max(1, root.commitDebounceMs)
    repeat: false
    property string pending: ""
    onTriggered: {
      if (pending.length)
        root.hexCommitted(pending)
    }
  }

  Timer {
    id: svPaintTimer
    interval: 16
    repeat: false
    onTriggered: svCanvas.requestPaint()
  }

  function scheduleCommit(hx) {
    if (root.commitDebounceMs <= 0) {
      root.hexCommitted(hx)
      return
    }
    commitTimer.pending = hx
    commitTimer.restart()
  }

  function flushCommit() {
    if (!commitTimer.pending.length && !root.lastEmittedHex.length)
      return
    const hx = commitTimer.pending.length ? commitTimer.pending : root.lastEmittedHex
    commitTimer.stop()
    commitTimer.pending = ""
    root.hexCommitted(hx)
  }

  function clamp01(x) {
    return Math.max(0, Math.min(1, x))
  }

  function componentToHex(c) {
    const n = Math.round(Math.max(0, Math.min(255, c)))
    const h = n.toString(16)
    return h.length === 1 ? "0" + h : h
  }

  function rgbToHex(r, g, b) {
    return "#" + componentToHex(r * 255) + componentToHex(g * 255) + componentToHex(b * 255)
  }

  function hsvToRgb(h, s, v) {
    const hh = ((h % 360) + 360) % 360
    const c = v * s
    const x = c * (1 - Math.abs((hh / 60) % 2 - 1))
    const m = v - c
    let r = 0
    let g = 0
    let b = 0
    if (hh < 60) {
      r = c
      g = x
    } else if (hh < 120) {
      r = x
      g = c
    } else if (hh < 180) {
      g = c
      b = x
    } else if (hh < 240) {
      g = x
      b = c
    } else if (hh < 300) {
      r = x
      b = c
    } else {
      r = c
      b = x
    }
    return {
      r: r + m,
      g: g + m,
      b: b + m
    }
  }

  function parseHex(str) {
    let s = String(str || "").trim()
    if (s.charAt(0) === "#")
      s = s.slice(1)
    if (s.length === 3)
      s = s.charAt(0) + s.charAt(0) + s.charAt(1) + s.charAt(1) + s.charAt(2) + s.charAt(2)
    if (!/^[0-9a-fA-F]{6}$/.test(s))
      return null
    return {
      r: parseInt(s.slice(0, 2), 16) / 255,
      g: parseInt(s.slice(2, 4), 16) / 255,
      b: parseInt(s.slice(4, 6), 16) / 255
    }
  }

  function rgbToHsv(r, g, b) {
    const max = Math.max(r, g, b)
    const min = Math.min(r, g, b)
    const d = max - min
    let h = 0
    if (d > 0.00001) {
      if (max === r)
        h = ((g - b) / d) % 6
      else if (max === g)
        h = (b - r) / d + 2
      else
        h = (r - g) / d + 4
      h *= 60
      if (h < 0)
        h += 360
    }
    const s = max <= 0.00001 ? 0 : d / max
    return {
      h: h,
      s: s,
      v: max
    }
  }

  readonly property var previewRgb: hsvToRgb(hue, sat, val)
  readonly property color previewColor: Qt.rgba(previewRgb.r, previewRgb.g, previewRgb.b, 1)
  readonly property string previewHex: rgbToHex(previewRgb.r, previewRgb.g, previewRgb.b)

  function syncFromHex(str) {
    const rgb = parseHex(str)
    if (!rgb)
      return false
    const hsv = rgbToHsv(rgb.r, rgb.g, rgb.b)
    updatingFromHex = true
    hue = hsv.h
    sat = hsv.s
    val = hsv.v
    hexField.text = rgbToHex(rgb.r, rgb.g, rgb.b)
    updatingFromHex = false
    svCanvas.requestPaint()
    hueCanvas.requestPaint()
    return true
  }

  function emitFromHsv() {
    if (updatingFromHex)
      return
    const hx = previewHex
    hexField.text = hx
    if (hx === lastEmittedHex)
      return
    lastEmittedHex = hx
    root.hexEdited(hx)
    root.scheduleCommit(hx)
  }

  function pickSv(mx, my) {
    sat = clamp01(mx / Math.max(1, svCanvas.width))
    val = clamp01(1 - my / Math.max(1, svCanvas.height))
    emitFromHsv()
  }

  function pickHue(mx) {
    hue = clamp01(mx / Math.max(1, hueCanvas.width)) * 360
    emitFromHsv()
    svPaintTimer.restart()
  }

  onHexChanged: {
    if (updatingFromHex)
      return
    const cur = String(hexField.text || "").toLowerCase()
    const next = String(hex || "").toLowerCase()
    if (cur === next)
      return
    syncFromHex(hex)
    lastEmittedHex = String(hexField.text || "")
  }

  onHueChanged: svPaintTimer.restart()

  Component.onCompleted: {
    syncFromHex(hex)
    lastEmittedHex = String(hexField.text || "")
  }

  Item {
    Layout.fillWidth: true
    Layout.preferredHeight: 148

    RowLayout {
      anchors.fill: parent
      spacing: Theme.spaceSm

      Item {
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true

        Rectangle {
          anchors.fill: parent
          radius: Theme.radiusMd
          color: Theme.bgHover
          clip: true

          Canvas {
            id: svCanvas
            anchors.fill: parent
            antialiasing: true
            onPaint: {
              const ctx = getContext("2d")
              const w = width
              const h = height
              if (w < 2 || h < 2)
                return
              ctx.clearRect(0, 0, w, h)
              const pure = root.hsvToRgb(root.hue, 1, 1)
              const pureHex = root.rgbToHex(pure.r, pure.g, pure.b)
              ctx.fillStyle = pureHex
              ctx.fillRect(0, 0, w, h)
              const white = ctx.createLinearGradient(0, 0, w, 0)
              white.addColorStop(0, "rgba(255,255,255,1)")
              white.addColorStop(1, "rgba(255,255,255,0)")
              ctx.fillStyle = white
              ctx.fillRect(0, 0, w, h)
              const black = ctx.createLinearGradient(0, 0, 0, h)
              black.addColorStop(0, "rgba(0,0,0,0)")
              black.addColorStop(1, "rgba(0,0,0,1)")
              ctx.fillStyle = black
              ctx.fillRect(0, 0, w, h)
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.CrossCursor
              preventStealing: true
              onPressed: mouse => root.pickSv(mouse.x, mouse.y)
              onPositionChanged: mouse => {
                if (pressed)
                  root.pickSv(mouse.x, mouse.y)
              }
              onReleased: root.flushCommit()
              onCanceled: root.flushCommit()
            }
          }

          Rectangle {
            width: 14
            height: 14
            radius: 7
            x: root.sat * parent.width - width / 2
            y: (1 - root.val) * parent.height - height / 2
            color: root.previewColor
            border.width: 2
            border.color: "#ffffff"
            Rectangle {
              anchors.fill: parent
              anchors.margins: -1
              radius: width / 2
              color: "transparent"
              border.width: 1
              border.color: "#40000000"
            }
          }
        }
      }

      Rectangle {
        Layout.preferredWidth: 36
        Layout.fillHeight: true
        radius: Theme.radiusMd
        color: root.previewColor
        border.width: 1
        border.color: Theme.separator
      }
    }
  }

  Item {
    Layout.fillWidth: true
    Layout.preferredHeight: 18

    Rectangle {
      anchors.fill: parent
      radius: 4
      clip: true
      color: Theme.bgHover

      Canvas {
        id: hueCanvas
        anchors.fill: parent
        antialiasing: true
        Component.onCompleted: requestPaint()
        onPaint: {
          const ctx = getContext("2d")
          const w = width
          const h = height
          if (w < 2 || h < 2)
            return
          const g = ctx.createLinearGradient(0, 0, w, 0)
          const stops = [0, 1 / 6, 2 / 6, 3 / 6, 4 / 6, 5 / 6, 1]
          for (let i = 0; i < stops.length; i++) {
            const rgb = root.hsvToRgb(stops[i] * 360, 1, 1)
            g.addColorStop(stops[i], root.rgbToHex(rgb.r, rgb.g, rgb.b))
          }
          ctx.fillStyle = g
          ctx.fillRect(0, 0, w, h)
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          preventStealing: true
          onPressed: mouse => root.pickHue(mouse.x)
          onPositionChanged: mouse => {
            if (pressed)
              root.pickHue(mouse.x)
          }
          onReleased: root.flushCommit()
          onCanceled: root.flushCommit()
        }
      }
    }

    Rectangle {
      width: 6
      height: parent.height + 4
      radius: 2
      y: -2
      x: Math.max(0, Math.min(parent.width - width, (root.hue / 360) * parent.width - width / 2))
      color: "#ffffff"
      border.width: 1
      border.color: "#80000000"
    }
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: Theme.spaceSm

    Text {
      text: "Hex"
      color: Theme.textDim
      font.family: Theme.fontFamily
      font.pixelSize: 12
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 28
      radius: Theme.radiusSm
      color: Theme.bgHover

      TextInput {
        id: hexField
        anchors.fill: parent
        anchors.leftMargin: Theme.spaceSm
        anchors.rightMargin: Theme.spaceSm
        verticalAlignment: TextInput.AlignVCenter
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSm
        selectByMouse: true
        onEditingFinished: {
          const rgb = root.parseHex(text)
          if (!rgb) {
            text = root.hex
            return
          }
          const hx = root.rgbToHex(rgb.r, rgb.g, rgb.b)
          root.syncFromHex(hx)
          root.lastEmittedHex = hx
          root.hexEdited(hx)
          root.flushCommit()
        }
        Keys.onReturnPressed: editingFinished()
        Keys.onEnterPressed: editingFinished()
      }
    }
  }
}
