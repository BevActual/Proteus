import QtQuick
import QtQuick.Layouts
import "../../shared"

// Quiet top-right glass HUD — same elevated plate as notification toasts (#1158).
Item {
  id: root
  anchors.fill: parent
  visible: Hud.hudVisible
  z: 40

  readonly property alias cardItem: chip
  readonly property bool isMuted: Hud.value <= 0 || Hud.title === "Muted"

  Rectangle {
    id: chip
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.topMargin: Theme.barHeight + 12
    anchors.rightMargin: 12
    width: 196
    height: 56
    radius: Theme.radiusXl
    color: Theme.elevatedFill
    border.width: Theme.chromeClear ? 0 : 1
    border.color: Theme.chromeBorder
    opacity: root.visible ? 1 : 0

    Behavior on opacity {
      NumberAnimation {
        duration: 160
        easing.type: Easing.OutCubic
      }
    }
    Behavior on color {
      ColorAnimation {
        duration: 180
        easing.type: Easing.OutCubic
      }
    }

    RowLayout {
      anchors.fill: parent
      anchors.leftMargin: Theme.spaceMd
      anchors.rightMargin: Theme.spaceMd
      anchors.topMargin: Theme.spaceSm + 2
      anchors.bottomMargin: Theme.spaceSm + 2
      spacing: Theme.spaceSm

      // Calm glyph plate — accentSoft wash, not a VOL badge
      Rectangle {
        Layout.preferredWidth: 28
        Layout.preferredHeight: 28
        radius: Theme.radiusMd
        color: Theme.chromeAccentSoft

        // Simple speaker / sun mark (no emoji, no icon theme dependency)
        Item {
          anchors.centerIn: parent
          width: 14
          height: 14
          visible: Hud.kind !== "brightness"

          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            x: root.isMuted ? 4 : 1
            width: 4
            height: 6
            radius: 1
            color: Theme.text
            opacity: root.isMuted ? 0.45 : 1
          }
          Canvas {
            anchors.fill: parent
            visible: !root.isMuted
            onPaint: {
              const ctx = getContext("2d")
              ctx.reset()
              ctx.strokeStyle = Theme.text
              ctx.lineWidth = 1.4
              ctx.beginPath()
              ctx.arc(6, 7, 4, -0.7, 0.7)
              ctx.stroke()
              ctx.beginPath()
              ctx.arc(6, 7, 7, -0.7, 0.7)
              ctx.stroke()
            }
          }
          Rectangle {
            visible: root.isMuted
            anchors.centerIn: parent
            width: 12
            height: 1.5
            rotation: -40
            color: Theme.danger
            radius: 1
          }
        }

        Rectangle {
          anchors.centerIn: parent
          visible: Hud.kind === "brightness"
          width: 8
          height: 8
          radius: 4
          color: Theme.text
          opacity: 0.9
        }
      }

      ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 5

        Text {
          Layout.fillWidth: true
          text: Hud.title
          color: Theme.textDim
          font.family: Theme.fontFamily
          font.pixelSize: 11
          elide: Text.ElideRight
        }

        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 4
          radius: 2
          color: Theme.separator

          Rectangle {
            width: Math.max(4, parent.width * (Hud.value / 100))
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

      Text {
        text: Hud.value + "%"
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: 13
        font.weight: Font.Medium
        Layout.alignment: Qt.AlignVCenter
      }
    }
  }
}
