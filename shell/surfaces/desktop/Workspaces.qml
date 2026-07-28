import Quickshell
import Quickshell.Hyprland
import QtQuick
import "../../shared"

// Compact workspace strip — sliding accent pill, no noisy tray chrome.
Item {
  id: root

  readonly property int cell: Math.max(22, Theme.barHeight - 10)
  readonly property int count: 6
  readonly property int focusedId: {
    const list = Hyprland.workspaces.values
    for (let i = 0; i < list.length; i++) {
      if (list[i].focused)
        return list[i].id
    }
    return 1
  }

  implicitHeight: cell
  implicitWidth: count * cell + 4

  // Quiet track
  Rectangle {
    anchors.fill: parent
    radius: Theme.radiusPill
    color: Theme.chromeClear
        ? "transparent"
        : Qt.rgba(Theme.bgHover.r, Theme.bgHover.g, Theme.bgHover.b, 0.28 * Theme.chromeAlpha)
    visible: !Theme.chromeClear
  }

  // Sliding focus pill
  Rectangle {
    id: focusPill
    width: root.cell - 2
    height: root.cell - 2
    radius: Theme.radiusPill
    color: Theme.chromeAccentSoft
    y: 1
    x: 2 + (Math.max(1, Math.min(root.count, root.focusedId)) - 1) * root.cell

    Behavior on x {
      NumberAnimation {
        duration: 180
        easing.type: Easing.OutCubic
      }
    }
  }

  Row {
    anchors.centerIn: parent
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

        // Occupied / empty / focused — numbers stay calm
        Text {
          anchors.centerIn: parent
          text: cell.wsId
          color: cell.focused
              ? Theme.accent
              : (cell.occupied ? Theme.text : Theme.textMute)
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSizeSm
          font.weight: cell.focused ? Font.DemiBold : Font.Normal
          opacity: cell.focused ? 1 : (cell.occupied ? 0.9 : 0.45)
        }

        // Soft hover (under the sliding pill visually via z)
        Rectangle {
          anchors.fill: parent
          anchors.margins: 2
          radius: Theme.radiusPill
          color: pillMa.containsMouse && !cell.focused ? Theme.chromeHover : "transparent"
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
              Hyprland.dispatch("workspace " + cell.wsId)
          }
        }
      }
    }
  }
}
