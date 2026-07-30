import QtQuick
import QtQuick.Layouts
import "../../shared"

// Quiet top-right glass HUD chip — bar/CC material family (#1157).
Item {
  id: root
  anchors.fill: parent
  visible: Hud.hudVisible
  z: 40

  readonly property alias cardItem: chip

  Rectangle {
    id: chip
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.topMargin: Theme.barHeight + 14
    anchors.rightMargin: 14
    width: 220
    implicitHeight: col.implicitHeight + 22
    radius: Theme.radiusXl
    color: Theme.hudFill
    border.width: Theme.chromeClear ? 0 : 1
    border.color: Theme.chromeHairline
    opacity: root.visible ? 1 : 0

    Behavior on opacity {
      NumberAnimation {
        duration: 140
        easing.type: Easing.OutCubic
      }
    }

    // Soft curve-following rim (same idea as dock continuous glass)
    Rectangle {
      anchors.fill: parent
      anchors.margins: -1
      z: -1
      radius: parent.radius + 1
      color: "transparent"
      border.width: Theme.blur && !Theme.chromeClear ? 1 : 0
      border.color: Theme.dockEdgeGlow
      antialiasing: true
    }

    ColumnLayout {
      id: col
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: 14
      spacing: 10

      RowLayout {
        Layout.fillWidth: true
        spacing: 10

        Text {
          text: Hud.glyph
          color: Theme.textMute
          font.family: Theme.fontFamily
          font.pixelSize: 11
          font.weight: Font.DemiBold
          font.letterSpacing: 0.6
          Layout.alignment: Qt.AlignVCenter
        }

        Text {
          Layout.fillWidth: true
          text: Hud.title
          color: Theme.text
          font.family: Theme.fontFamily
          font.pixelSize: 13
          font.weight: Font.DemiBold
          elide: Text.ElideRight
        }

        Text {
          text: Hud.value + "%"
          color: Theme.textMute
          font.family: Theme.fontFamily
          font.pixelSize: 12
          Layout.alignment: Qt.AlignVCenter
        }
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 6
        radius: 3
        color: Theme.light ? Qt.rgba(0, 0, 0, 0.08) : Qt.rgba(1, 1, 1, 0.10)

        Rectangle {
          width: Math.max(6, parent.width * (Hud.value / 100))
          height: parent.height
          radius: parent.radius
          color: Theme.accent
          Behavior on width {
            NumberAnimation {
              duration: 120
              easing.type: Easing.OutCubic
            }
          }
        }
      }
    }
  }
}
