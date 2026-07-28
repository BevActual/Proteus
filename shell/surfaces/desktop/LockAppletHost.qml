import QtQuick
import "../../shared"

// Positioned lock applet — clock chrome or strip slot; customize drag/reorder/size.
Item {
  id: root

  property var frame: null
  property bool customizeMode: false
  property bool selected: false
  property real surfaceWidth: 400
  property real surfaceHeight: 800

  signal requestCustomize()
  signal selectApplet()
  signal dragReorder(real normY)

  readonly property var widgetData: frame && frame.widget ? frame.widget : null
  readonly property string widgetId: widgetData ? String(widgetData.id) : ""
  readonly property string widgetType: widgetData ? String(widgetData.type) : ""
  readonly property bool isClock: widgetType === "clock"

  x: dragging ? dragX : (frame ? frame.x : 0)
  y: dragging ? dragY : (frame ? frame.y : 0)
  width: frame ? frame.width : 100
  height: frame ? frame.height : 80

  property bool dragging: false
  property real dragX: 0
  property real dragY: 0

  scale: (customizeMode && selected) ? 1.04 : (customizeMode ? 1.02 : 1)
  Behavior on scale {
    NumberAnimation {
      duration: 120
    }
  }

  Loader {
    id: bodyLoader
    anchors.fill: parent
    // Component path comes from Widgets.widgetCatalog — a new applet type needs
    // no change here, only a catalog entry and a file under widgets/.
    source: {
      const s = Widgets.widgetSourceFor(root.widgetType)
      return s.length ? Qt.resolvedUrl(s) : ""
    }
  }

  Binding {
    target: bodyLoader.item
    property: "widgetData"
    value: root.widgetData
    when: !!bodyLoader.item && root.isClock
  }
  Binding {
    target: bodyLoader.item
    property: "size"
    value: root.widgetData ? root.widgetData.size : "md"
    when: !!bodyLoader.item
  }
  Binding {
    target: bodyLoader.item
    property: "showControls"
    value: root.widgetData ? !!root.widgetData.showControls : true
    when: !!bodyLoader.item && root.widgetType === "media"
  }
  Binding {
    target: bodyLoader.item
    property: "showWhenIdle"
    value: root.widgetData ? !!root.widgetData.showWhenIdle : false
    when: !!bodyLoader.item && root.widgetType === "media"
  }

  Rectangle {
    anchors.fill: parent
    anchors.margins: -4
    radius: 14
    visible: root.customizeMode
    color: "transparent"
    border.width: root.selected ? 2 : 1
    border.color: root.selected ? Theme.accent : Qt.rgba(1, 1, 1, 0.45)
  }

  // Size cycle (non-clock)
  Rectangle {
    visible: root.customizeMode && root.selected && !root.isClock
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    anchors.margins: -6
    width: 28
    height: 22
    radius: 8
    color: Qt.rgba(0, 0, 0, 0.65)
    z: 6
    Text {
      anchors.centerIn: parent
      text: String(root.widgetData && root.widgetData.size ? root.widgetData.size : "md").toUpperCase()
      color: "white"
      font.pixelSize: 9
      font.bold: true
    }
    MouseArea {
      anchors.fill: parent
      onClicked: Widgets.cycleLockWidgetSize(root.widgetId)
    }
  }

  Rectangle {
    visible: root.customizeMode && !root.isClock
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: -6
    width: 22
    height: 22
    radius: 11
    color: Qt.rgba(0.9, 0.2, 0.2, 0.92)
    z: 6
    Text {
      anchors.centerIn: parent
      text: "−"
      color: "white"
      font.pixelSize: 16
      font.bold: true
    }
    MouseArea {
      anchors.fill: parent
      onClicked: Widgets.removeLockWidget(root.widgetId)
    }
  }

  MouseArea {
    anchors.fill: parent
    z: 4
    preventStealing: root.customizeMode
    property real pressOX: 0
    property real pressOY: 0

    onPressAndHold: {
      root.requestCustomize()
      root.selectApplet()
    }
    onClicked: {
      if (root.customizeMode) {
        root.selectApplet()
        mouse.accepted = true
      }
    }
    onPressed: mouse => {
      if (!root.customizeMode || root.isClock)
        return
      root.selectApplet()
      root.dragging = true
      root.dragX = root.x
      root.dragY = root.y
      pressOX = mouse.x
      pressOY = mouse.y
    }
    onPositionChanged: mouse => {
      if (!root.dragging || !root.parent)
        return
      const p = mapToItem(root.parent, mouse.x, mouse.y)
      root.dragX = p.x - pressOX
      root.dragY = p.y - pressOY
    }
    onReleased: {
      if (root.dragging && !root.isClock) {
        // Map drop Y into 0..1 of the tile stack band (below clock → auth band)
        const stackTop = Math.max(28, root.surfaceHeight * 0.08)
        const stackBottom = root.surfaceHeight * 0.62
        const cy = root.dragY + root.height / 2
        const t = (cy - stackTop) / Math.max(1, stackBottom - stackTop)
        root.dragReorder(Math.max(0, Math.min(1, t)))
      }
      root.dragging = false
    }
  }
}
