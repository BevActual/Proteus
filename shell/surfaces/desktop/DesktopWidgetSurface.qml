import Quickshell
import QtQuick
import "../../shared"

// Unlocked desktop widgets — free place by default; optional snap-to-grid.
Item {
  id: root
  anchors.fill: parent

  property bool customizeMode: ShellState.desktopCustomizeMode
  property string selectedWidgetId: ""
  property bool showGallery: false
  property bool snapToGrid: Config.desktopWidgetsSnapToGrid
  property bool appletDragging: false

  DesktopLayout {
    id: deskLayout
    surfaceWidth: root.width
    surfaceHeight: root.height
    widgets: Widgets.desktopWidgetsEnabledList
    snapToGrid: root.snapToGrid
  }

  function enterCustomize() {
    ShellState.enterDesktopCustomize()
    if (Widgets.desktopWidgetsEnabledList.length)
      root.selectedWidgetId = String(Widgets.desktopWidgetsEnabledList[0].id)
  }

  function exitCustomize() {
    ShellState.exitDesktopCustomize()
    root.selectedWidgetId = ""
    root.showGallery = false
    root.appletDragging = false
  }

  function setSnapToGrid(on) {
    const want = !!on
    Config.desktopWidgetsSnapToGrid = want
    if (want)
      Widgets.snapAllDesktopWidgetsToGrid(deskLayout)
    gridCanvas.requestPaint()
  }

  // Empty desktop: long-press enters Customize; click clears selection.
  // Keep below applets; do not cover them (z:0). Guides/dim are paint-only.
  MouseArea {
    anchors.fill: parent
    z: 0
    enabled: !root.appletDragging
    onPressAndHold: {
      if (!root.customizeMode)
        root.enterCustomize()
    }
    onClicked: {
      if (root.customizeMode)
        root.selectedWidgetId = ""
    }
  }

  Rectangle {
    anchors.fill: parent
    z: 1
    visible: root.customizeMode
    color: Qt.rgba(0, 0, 0, 0.35)
    // Paint only — must not steal applet drags.
    enabled: false
  }

  // Single Canvas so line Items cannot participate in picking.
  Canvas {
    id: gridCanvas
    anchors.fill: parent
    z: 2
    visible: root.customizeMode && root.snapToGrid
    enabled: false
    antialiasing: true

    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onVisibleChanged: if (visible)
      requestPaint()

    Connections {
      target: deskLayout
      function onPitchChanged() { gridCanvas.requestPaint() }
      function onOriginXChanged() { gridCanvas.requestPaint() }
      function onOriginYChanged() { gridCanvas.requestPaint() }
      function onHalfColsChanged() { gridCanvas.requestPaint() }
      function onHalfRowsChanged() { gridCanvas.requestPaint() }
    }

    onPaint: {
      const ctx = getContext("2d")
      ctx.reset()
      const pitch = deskLayout.pitch
      const ox = deskLayout.originX
      const oy = deskLayout.originY
      const hc = deskLayout.halfCols
      const hr = deskLayout.halfRows
      for (let ix = -hc; ix <= hc; ix++) {
        const x = ox + ix * pitch
        ctx.beginPath()
        ctx.strokeStyle = ix === 0 ? "rgba(255,255,255,0.28)" : "rgba(255,255,255,0.10)"
        ctx.lineWidth = ix === 0 ? 2 : 1
        ctx.moveTo(x, 0)
        ctx.lineTo(x, height)
        ctx.stroke()
      }
      for (let iy = -hr; iy <= hr; iy++) {
        const y = oy + iy * pitch
        ctx.beginPath()
        ctx.strokeStyle = iy === 0 ? "rgba(255,255,255,0.28)" : "rgba(255,255,255,0.10)"
        ctx.lineWidth = iy === 0 ? 2 : 1
        ctx.moveTo(0, y)
        ctx.lineTo(width, y)
        ctx.stroke()
      }
      ctx.beginPath()
      ctx.fillStyle = "rgba(255,255,255,0.35)"
      ctx.strokeStyle = "rgba(255,255,255,0.5)"
      ctx.lineWidth = 1
      ctx.arc(ox, oy, 4, 0, Math.PI * 2)
      ctx.fill()
      ctx.stroke()
    }
  }

  Item {
    id: appletLayer
    anchors.fill: parent
    z: 3

    // Stable model = widget list (not rebuilt frame objects every bind).
    Repeater {
      model: Widgets.desktopWidgetsEnabledList
      DesktopAppletHost {
        required property var modelData
        frame: deskLayout ? deskLayout.frameForWidget(modelData) : null
        layout: deskLayout
        customizeMode: root.customizeMode
        selected: root.selectedWidgetId === String(modelData.id)
        surfaceWidth: root.width
        surfaceHeight: root.height
        onRequestCustomize: root.enterCustomize()
        onSelectApplet: root.selectedWidgetId = String(modelData.id)
        onDraggingChanged: root.appletDragging = dragging
        onDragMoved: (nx, ny) => {
          Widgets.moveDesktopWidget(modelData.id, nx, ny)
        }
      }
    }
  }

  Text {
    z: 5
    visible: root.customizeMode && Widgets.desktopWidgetsEnabledList.length === 0
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.verticalCenter: parent.verticalCenter
    text: root.snapToGrid ? "Tap Add Widget, then drag on the grid" : "Tap Add Widget, then drag anywhere"
    color: Qt.rgba(1, 1, 1, 0.55)
    font.family: Theme.fontFamily
    font.pixelSize: 14
  }

  DesktopCustomizeBar {
    z: 20
    visible: root.customizeMode
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: parent.top
    anchors.topMargin: 18
    width: Math.min(460, parent.width - 32)
    snapToGrid: root.snapToGrid
    onAddWidget: root.showGallery = true
    onToggleSnapGrid: root.setSnapToGrid(!root.snapToGrid)
    onDone: root.exitCustomize()
  }

  Loader {
    anchors.fill: parent
    z: 40
    active: root.showGallery
    source: Qt.resolvedUrl("WidgetGallery.qml")
    onLoaded: {
      if (item) {
        item.scope = "desktop"
        item.open()
        item.closed.connect(() => {
          root.showGallery = false
        })
      }
    }
  }

  Connections {
    target: ShellState
    function onSessionLockedChanged() {
      if (ShellState.sessionLocked)
        root.exitCustomize()
    }
    function onDesktopCustomizeModeChanged() {
      if (!ShellState.desktopCustomizeMode) {
        root.selectedWidgetId = ""
        root.showGallery = false
        root.appletDragging = false
      }
    }
  }

  Keys.onEscapePressed: {
    if (root.showGallery)
      root.showGallery = false
    else if (root.customizeMode)
      root.exitCustomize()
  }
  focus: root.customizeMode
}
