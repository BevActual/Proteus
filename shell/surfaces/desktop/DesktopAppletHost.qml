import QtQuick
import "../../shared"

// Grid-snapped desktop applet — Customize drag snaps to cell origins.
Item {
  id: root

  property var frame: null
  property var layout: null
  property bool customizeMode: false
  property bool selected: false
  property real surfaceWidth: 400
  property real surfaceHeight: 800

  signal requestCustomize()
  signal selectApplet()
  signal dragMoved(real normX, real normY)

  readonly property int colSpan: frame && frame.colSpan ? frame.colSpan : 2
  readonly property int rowSpan: frame && frame.rowSpan ? frame.rowSpan : 1

  readonly property var widgetData: frame && frame.widget ? frame.widget : null
  readonly property string widgetId: widgetData ? String(widgetData.id) : ""
  readonly property string widgetType: widgetData ? String(widgetData.type) : ""

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
    when: !!bodyLoader.item && root.widgetType === "clock"
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
    value: root.widgetData ? !!root.widgetData.showWhenIdle : true
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

  Rectangle {
    visible: root.customizeMode && root.selected
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
      onClicked: Widgets.cycleDesktopWidgetSize(root.widgetId)
    }
  }

  Rectangle {
    visible: root.customizeMode
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
      onClicked: Widgets.removeDesktopWidget(root.widgetId)
    }
  }

  MouseArea {
    id: editMa
    anchors.fill: parent
    z: 4
    enabled: root.customizeMode
    preventStealing: true
    property real pressOX: 0
    property real pressOY: 0

    onClicked: root.selectApplet()
    onPressed: mouse => {
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
      const rawX = p.x - pressOX
      const rawY = p.y - pressOY
      if (root.layout) {
        const snapped = root.layout.snapPixel(rawX, rawY, root.colSpan, root.rowSpan)
        root.dragX = snapped.x
        root.dragY = snapped.y
      } else {
        const maxX = Math.max(0, root.surfaceWidth - root.width)
        const maxY = Math.max(0, root.surfaceHeight - root.height)
        root.dragX = Math.max(0, Math.min(maxX, rawX))
        root.dragY = Math.max(0, Math.min(maxY, rawY))
      }
    }
    onReleased: {
      if (root.dragging) {
        if (root.layout) {
          const n = root.layout.normFromPixel(root.dragX, root.dragY, root.colSpan, root.rowSpan)
          root.dragMoved(n.x, n.y)
        } else {
          const margin = Math.max(12, Math.min(root.surfaceWidth, root.surfaceHeight) * 0.02)
          const maxX = Math.max(1, root.surfaceWidth - root.width - margin)
          const maxY = Math.max(1, root.surfaceHeight - root.height - margin)
          const nx = (root.dragX - margin) / maxX
          const ny = (root.dragY - margin) / maxY
          root.dragMoved(Math.max(0, Math.min(1, nx)), Math.max(0, Math.min(1, ny)))
        }
      }
      root.dragging = false
    }
  }

  // Long-press enters Customize without blocking media/battery controls.
  Timer {
    id: holdTimer
    interval: 550
    onTriggered: {
      root.requestCustomize()
      root.selectApplet()
    }
  }

  MouseArea {
    anchors.fill: parent
    z: 5
    enabled: !root.customizeMode
    propagateComposedEvents: true
    onPressed: mouse => {
      holdTimer.restart()
      mouse.accepted = false
    }
    onReleased: mouse => {
      holdTimer.stop()
      mouse.accepted = false
    }
    onCanceled: holdTimer.stop()
    onPositionChanged: mouse => {
      holdTimer.stop()
      mouse.accepted = false
    }
  }
}
