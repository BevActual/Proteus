import Quickshell
import QtQuick
import "../../shared"

// Unlocked desktop widgets — grid snap in Customize; span-aware cells.
Item {
  id: root
  anchors.fill: parent

  property bool customizeMode: ShellState.desktopCustomizeMode
  property string selectedWidgetId: ""
  property bool showGallery: false

  DesktopLayout {
    id: layout
    surfaceWidth: root.width
    surfaceHeight: root.height
    widgets: Widgets.desktopWidgetsEnabledList
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

  // Customize grid — even gutters; guides only (not interactive).
  Item {
    id: gridOverlay
    anchors.fill: parent
    z: 2
    visible: root.customizeMode
    readonly property real margin: layout.margin
    readonly property real cellW: layout.cellWidth
    readonly property real cellH: layout.cellHeight
    readonly property real gutter: layout.gutter

    Repeater {
      model: layout.gridCols
      Rectangle {
        required property int index
        x: gridOverlay.margin + index * (gridOverlay.cellW + gridOverlay.gutter)
        y: gridOverlay.margin
        width: gridOverlay.cellW
        height: Math.max(0, root.height - gridOverlay.margin * 2)
        color: Qt.rgba(1, 1, 1, 0.04)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.12)
        radius: 6
      }
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
          const cs = modelData.colSpan || 2
          const rs = modelData.rowSpan || 1
          const snapped = layout.snapNorm(nx, ny, cs, rs)
          Widgets.moveDesktopWidget(modelData.id, snapped.x, snapped.y)
        }
      }
    }
  }

  Text {
    z: 5
    visible: root.customizeMode && Widgets.desktopWidgetsEnabledList.length === 0
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.verticalCenter: parent.verticalCenter
    text: "Tap Add Widget, then drag on the grid"
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
    width: Math.min(380, parent.width - 32)
    onAddWidget: root.showGallery = true
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
