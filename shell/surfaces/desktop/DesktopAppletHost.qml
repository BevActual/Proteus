import QtQuick
import "../../shared"

// Desktop applet — Customize drag (free or snap). Interaction matches lock applets.
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

  Loader {
    id: bodyLoader
    anchors.fill: parent
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

  // Selection chrome only — never scale the drag root (breaks mapToItem).
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
    hoverEnabled: false
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
      mouse.accepted = true
    }
    onPositionChanged: mouse => {
      if (!root.dragging || !root.parent)
        return
      // Lock-style: cursor in parent space minus press offset in local space.
      const p = mapToItem(root.parent, mouse.x, mouse.y)
      const rawX = p.x - pressOX
      const rawY = p.y - pressOY
      if (root.layout && root.layout.snapToGrid) {
        const s = root.layout.snapPixel(rawX, rawY, root.width, root.height)
        root.dragX = s.x
        root.dragY = s.y
      } else if (root.layout) {
        const c = root.layout.clampPixel(rawX, rawY, root.width, root.height)
        root.dragX = c.x
        root.dragY = c.y
      } else {
        root.dragX = Math.max(0, Math.min(Math.max(0, root.surfaceWidth - root.width), rawX))
        root.dragY = Math.max(0, Math.min(Math.max(0, root.surfaceHeight - root.height), rawY))
      }
    }
    onReleased: mouse => {
      if (root.dragging) {
        if (root.layout) {
          const n = root.layout.normFromPixel(root.dragX, root.dragY, 0, 0, root.width, root.height)
          root.dragMoved(n.x, n.y)
        }
      }
      root.dragging = false
    }
    onCanceled: root.dragging = false
  }

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
