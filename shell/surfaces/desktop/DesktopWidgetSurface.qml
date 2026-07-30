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

  DesktopLayout {
    id: layout
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
  }

  function setSnapToGrid(on) {
    const want = !!on
    Config.desktopWidgetsSnapToGrid = want
    Config.flushSettings()
    if (want)
      Widgets.snapAllDesktopWidgetsToGrid(layout)
  }

  // Empty-desktop long-press / customize backdrop
  MouseArea {
    anchors.fill: parent
    z: 0
    onPressAndHold: root.enterCustomize()
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
  }

  // Graph-paper guides — origin at screen center (stronger crosshair).
  Item {
    id: gridOverlay
    anchors.fill: parent
    z: 2
    visible: root.customizeMode && root.snapToGrid
    readonly property real pitch: layout.pitch
    readonly property real ox: layout.originX
    readonly property real oy: layout.originY
    readonly property int halfC: layout.halfCols
    readonly property int halfR: layout.halfRows

    // Vertical lines (ix from -halfCols … +halfCols)
    Repeater {
      model: layout.gridCols
      Rectangle {
        required property int index
        readonly property int ix: index - gridOverlay.halfC
        width: ix === 0 ? 2 : 1
        height: parent.height
        x: gridOverlay.ox + ix * gridOverlay.pitch - width * 0.5
        y: 0
        color: ix === 0 ? Qt.rgba(1, 1, 1, 0.28) : Qt.rgba(1, 1, 1, 0.1)
      }
    }

    // Horizontal lines (iy from -halfRows … +halfRows)
    Repeater {
      model: layout.gridRows
      Rectangle {
        required property int index
        readonly property int iy: index - gridOverlay.halfR
        height: iy === 0 ? 2 : 1
        width: parent.width
        y: gridOverlay.oy + iy * gridOverlay.pitch - height * 0.5
        x: 0
        color: iy === 0 ? Qt.rgba(1, 1, 1, 0.28) : Qt.rgba(1, 1, 1, 0.1)
      }
    }

    // Center anchor dot
    Rectangle {
      width: 8
      height: 8
      radius: 4
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.verticalCenter: parent.verticalCenter
      color: Qt.rgba(1, 1, 1, 0.35)
      border.width: 1
      border.color: Qt.rgba(1, 1, 1, 0.5)
    }
  }

  Item {
    id: appletLayer
    anchors.fill: parent
    z: 3

    Repeater {
      model: layout.frames
      DesktopAppletHost {
        required property var modelData
        frame: modelData
        layout: layout
        customizeMode: root.customizeMode
        selected: root.selectedWidgetId === modelData.id
        surfaceWidth: root.width
        surfaceHeight: root.height
        onRequestCustomize: root.enterCustomize()
        onSelectApplet: root.selectedWidgetId = modelData.id
        onDragMoved: (nx, ny) => {
          if (root.snapToGrid) {
            const snapped = layout.snapNorm(nx, ny, modelData.width, modelData.height)
            Widgets.moveDesktopWidget(modelData.id, snapped.x, snapped.y)
          } else {
            Widgets.moveDesktopWidget(modelData.id, nx, ny)
          }
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
