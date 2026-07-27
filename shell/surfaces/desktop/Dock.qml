import Quickshell
import Quickshell.Widgets
import QtQuick
import "../../shared"

Item {
  id: root

  readonly property int iconSize: 48
  readonly property int maxIconSize: 70
  readonly property int spacing: 8
  readonly property int pad: 16
  readonly property real magRange: 110

  property real mouseX: -1000
  property bool hovered: false

  implicitWidth: plate.width
  implicitHeight: maxIconSize + 24

  function scaleAt(cx) {
    if (!hovered)
      return 1.0
    const d = Math.abs(mouseX - cx)
    if (d >= magRange)
      return 1.0
    const t = 1 - d / magRange
    return 1 + (maxIconSize / iconSize - 1) * (t * t)
  }

  Rectangle {
    id: plate
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    width: row.width + root.pad * 2
    height: root.iconSize + 22
    radius: Theme.radiusPill
    color: Qt.rgba(15 / 255, 20 / 255, 28 / 255, 0.78)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.10)

    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: 1
      height: parent.height * 0.42
      radius: parent.radius - 1
      opacity: 0.9
      gradient: Gradient {
        GradientStop {
          position: 0.0
          color: Qt.rgba(1, 1, 1, 0.08)
        }
        GradientStop {
          position: 1.0
          color: "transparent"
        }
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
      onEntered: root.hovered = true
      onExited: {
        root.hovered = false
        root.mouseX = -1000
      }
      onPositionChanged: mouse => root.mouseX = mouse.x
    }

    Row {
      id: row
      anchors.centerIn: parent
      spacing: root.spacing
      z: 2

      Repeater {
        model: DockApps.visiblePinned

        Item {
          id: cell
          required property var modelData
          required property int index

          property real cx: x + width / 2 + root.pad
          property real iconScale: root.scaleAt(cx)

          width: root.iconSize * iconScale + 2
          height: root.iconSize * iconScale + 12

          Behavior on width {
            NumberAnimation {
              duration: 80
              easing.type: Easing.OutQuad
            }
          }
          Behavior on height {
            NumberAnimation {
              duration: 80
              easing.type: Easing.OutQuad
            }
          }

          Column {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            spacing: 5

            Rectangle {
              id: iconWell
              width: root.iconSize * cell.iconScale
              height: root.iconSize * cell.iconScale
              anchors.horizontalCenter: parent.horizontalCenter
              radius: width * 0.24
              color: Theme.bgHover
              border.width: DockApps.isActive(modelData) ? 2 : 1
              border.color: DockApps.isActive(modelData) ? Theme.accent : Qt.rgba(1, 1, 1, 0.06)

              IconImage {
                anchors.centerIn: parent
                width: parent.width * 0.7
                height: parent.height * 0.7
                source: Quickshell.iconPath(modelData.icon || "application-x-executable")
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                hoverEnabled: true
                onClicked: DockApps.focusOrLaunch(modelData)
                onPositionChanged: mouse => {
                  root.hovered = true
                  root.mouseX = cell.mapToItem(plate, mouse.x, 0).x
                }
              }

              Behavior on width {
                NumberAnimation {
                  duration: 80
                  easing.type: Easing.OutQuad
                }
              }
              Behavior on height {
                NumberAnimation {
                  duration: 80
                  easing.type: Easing.OutQuad
                }
              }
            }

            Rectangle {
              anchors.horizontalCenter: parent.horizontalCenter
              width: 4
              height: 4
              radius: 2
              color: Theme.text
              opacity: 0.9
              visible: modelData.special === "launcher" ? ShellState.launcherOpen : DockApps.isRunning(modelData)

            }
          }
        }
      }
    }
  }
}
