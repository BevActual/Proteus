import Quickshell
import Quickshell.Hyprland
import QtQuick
import "../../shared"

// Compact workspace strip — quiet Mac-adjacent pills in the menu bar.
// Dynamic width (grows with the highest live workspace), occupied dots,
// scroll-wheel cycling, and a "+" pill that jumps to the next workspace.
Item {
  id: root

  readonly property int cell: Math.max(18, Theme.barHeight - 14)
  readonly property int maxCount: 10

  readonly property int highestId: {
    const list = Hyprland.workspaces.values
    let hi = 0
    for (let i = 0; i < list.length; i++) {
      if (list[i].id > hi)
        hi = list[i].id
    }
    return hi
  }

  readonly property int focusedId: {
    const list = Hyprland.workspaces.values
    for (let i = 0; i < list.length; i++) {
      if (list[i].focused)
        return list[i].id
    }
    return 1
  }

  // At least 4 pills; extend to the highest live workspace (capped).
  readonly property int count: Math.min(maxCount, Math.max(4, highestId, focusedId))
  readonly property bool showPlus: count < maxCount

  implicitHeight: cell
  implicitWidth: count * cell + (showPlus ? cell : 0) + 2

  function go(id) {
    const target = Math.max(1, Math.min(root.maxCount, Math.round(id)))
    Hyprland.dispatch("workspace " + target)
  }

  Rectangle {
    anchors.fill: parent
    radius: height / 2
    color: Theme.light ? Qt.rgba(0, 0, 0, 0.05) : Qt.rgba(1, 1, 1, 0.08)
    visible: !Theme.chromeClear
  }

  // Wheel over the strip cycles workspaces (up = previous, down = next).
  WheelHandler {
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    onWheel: event => {
      const d = event.angleDelta.y
      if (d > 0)
        root.go(root.focusedId - 1)
      else if (d < 0)
        root.go(root.focusedId + 1)
    }
  }

  Rectangle {
    id: focusPill
    width: root.cell - 2
    height: root.cell - 2
    radius: height / 2
    color: Theme.chromeAccentSoft
    y: 1
    x: 1 + (Math.max(1, Math.min(root.count, root.focusedId)) - 1) * root.cell

    Behavior on x {
      NumberAnimation {
        duration: 180
        easing.type: Easing.OutCubic
      }
    }
  }

  Row {
    anchors.left: parent.left
    anchors.leftMargin: 1
    anchors.verticalCenter: parent.verticalCenter
    spacing: 0

    Repeater {
      model: root.count

      Item {
        id: cell
        required property int index
        readonly property int wsId: index + 1
        readonly property var ws: {
          const list = Hyprland.workspaces.values
          for (let i = 0; i < list.length; i++) {
            if (list[i].id === wsId)
              return list[i]
          }
          return null
        }
        readonly property bool focused: ws ? ws.focused : false
        readonly property bool occupied: ws !== null

        width: root.cell
        height: root.cell

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.verticalCenter: parent.verticalCenter
          anchors.verticalCenterOffset: cell.occupied && !cell.focused ? -1 : 0
          text: cell.wsId
          color: cell.focused
              ? Theme.accent
              : (cell.occupied ? Theme.textDim : Theme.textMute)
          font.family: Theme.fontFamily
          font.pixelSize: Math.max(10, Theme.fontSizeSm - 1)
          font.weight: cell.focused ? Font.DemiBold : Font.Normal
          opacity: cell.focused ? 1 : (cell.occupied ? 0.85 : 0.4)
        }

        // Occupied (has windows) — tiny dot under the number
        Rectangle {
          visible: cell.occupied && !cell.focused
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: 3
          width: 3
          height: 3
          radius: 1.5
          color: Theme.textDim
          opacity: 0.8
        }

        Rectangle {
          anchors.fill: parent
          anchors.margins: 1
          radius: height / 2
          color: pillMa.containsMouse && !cell.focused
              ? (Theme.light ? Qt.rgba(0, 0, 0, 0.06) : Qt.rgba(1, 1, 1, 0.08))
              : "transparent"
          z: -1
        }

        MouseArea {
          id: pillMa
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (cell.ws)
              cell.ws.activate()
            else
              root.go(cell.wsId)
          }
        }
      }
    }

    // "+" — jump to the next (empty) workspace; Hyprland reaps it when unused.
    Item {
      visible: root.showPlus
      width: root.cell
      height: root.cell

      Text {
        anchors.centerIn: parent
        text: "+"
        color: plusMa.containsMouse ? Theme.text : Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSm
        opacity: plusMa.containsMouse ? 1 : 0.5
      }

      Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: height / 2
        color: plusMa.containsMouse
            ? (Theme.light ? Qt.rgba(0, 0, 0, 0.06) : Qt.rgba(1, 1, 1, 0.08))
            : "transparent"
        z: -1
      }

      MouseArea {
        id: plusMa
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.go(root.count + 1)
      }
    }
  }
}
