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

  signal selectApplet()
  signal dragMoved(real normX, real normY)
  // Alignment guide lines while free-dragging ([] when none / drag ends)
  signal dragGuides(var guides)

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

  // Types whose QML declares the given optional property (Binding to a
  // missing property would warn).
  readonly property var dataTypes: ["clock", "notes", "worldclock"]
  readonly property var clickTypes: ["clock", "calendar", "weather", "system", "battery", "worldclock"]

  Binding {
    target: bodyLoader.item
    property: "widgetData"
    value: root.widgetData
    when: !!bodyLoader.item && root.dataTypes.indexOf(root.widgetType) >= 0
  }
  Binding {
    target: bodyLoader.item
    property: "canEdit"
    value: !root.customizeMode
    when: !!bodyLoader.item && root.widgetType === "notes"
  }
  // Widgets act on normal click (calendar popover, Mission Center, Settings,
  // city picker…) — never while customizing, never on the lock surface.
  Binding {
    target: bodyLoader.item
    property: "interactive"
    value: !root.customizeMode
    when: !!bodyLoader.item && root.clickTypes.indexOf(root.widgetType) >= 0
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
    radius: Theme.radiusLg + 2
    visible: root.customizeMode
    color: "transparent"
    border.width: root.selected ? 2 : 1
    border.color: root.selected ? Theme.accent : Theme.chromeBorder
  }

  Rectangle {
    visible: root.customizeMode && root.selected
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    anchors.margins: -6
    width: 28
    height: 22
    radius: Theme.radius
    color: Theme.elevatedFill
    border.width: 1
    border.color: Theme.chromeBorder
    z: 6
    Text {
      anchors.centerIn: parent
      text: String(root.widgetData && root.widgetData.size ? root.widgetData.size : "md").toUpperCase()
      color: Theme.text
      font.family: Theme.fontFamily
      font.pixelSize: 9
      font.weight: Font.DemiBold
    }
    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
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
    color: Theme.danger
    z: 6
    Text {
      anchors.centerIn: parent
      text: "−"
      color: "#ffffff"
      font.family: Theme.fontFamily
      font.pixelSize: 16
      font.weight: Font.DemiBold
    }
    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
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
      // Capture position BEFORE dragging flips x/y bindings (else dragX reads 0 → edge warp).
      const startX = root.frame ? root.frame.x : root.x
      const startY = root.frame ? root.frame.y : root.y
      root.dragX = startX
      root.dragY = startY
      pressOX = mouse.x
      pressOY = mouse.y
      root.selectApplet()
      root.dragging = true
      mouse.accepted = true
    }
    onPositionChanged: mouse => {
      if (!root.dragging || !root.parent)
        return
      // Parent-space cursor via scene map — stable while the item moves.
      const p = mapToItem(root.parent, mouse.x, mouse.y)
      let rawX = p.x - pressOX
      let rawY = p.y - pressOY
      const wid = root.widgetId
      if (root.layout) {
        // Free placement: magnetize to neighbor edges/centers first; drop the
        // guides if collision resolution then pushes the frame elsewhere.
        let guides = []
        if (!root.layout.snapToGrid) {
          const a = root.layout.alignAdjust(rawX, rawY, root.width, root.height, wid)
          rawX = a.x
          rawY = a.y
          guides = a.guides
        }
        const placed = root.layout.resolveNoOverlap(rawX, rawY, root.width, root.height, wid)
        if (Math.abs(placed.x - rawX) > 0.5 || Math.abs(placed.y - rawY) > 0.5)
          guides = []
        root.dragGuides(guides)
        root.dragX = placed.x
        root.dragY = placed.y
      } else {
        root.dragX = Math.max(0, Math.min(Math.max(0, root.surfaceWidth - root.width), rawX))
        root.dragY = Math.max(0, Math.min(Math.max(0, root.surfaceHeight - root.height), rawY))
      }
    }
    onReleased: mouse => {
      if (root.dragging && root.layout) {
        const placed = root.layout.resolveNoOverlap(root.dragX, root.dragY, root.width, root.height, root.widgetId)
        root.dragX = placed.x
        root.dragY = placed.y
        const n = root.layout.normFromPixel(placed.x, placed.y, 0, 0, root.width, root.height)
        root.dragMoved(n.x, n.y)
      }
      root.dragGuides([])
      root.dragging = false
    }
    onCanceled: {
      root.dragGuides([])
      root.dragging = false
    }
  }

  // No long-press MouseArea here: an unaccepted press never receives its
  // release, so a hold timer armed on press would fire even after a normal
  // click (phantom Customize). Long-press over non-interactive regions falls
  // through to the surface's press-and-hold; interactive widget areas carry
  // their own onPressAndHold → ShellState.enterDesktopCustomize().
}
