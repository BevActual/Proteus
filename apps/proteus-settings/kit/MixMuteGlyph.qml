import QtQuick
import "../shared"

// Compact speaker mute mark (StatusHud language) — no emoji / icon theme.
Item {
  id: root
  property bool muted: false
  property color ink: muted ? Theme.danger : Theme.textDim

  implicitWidth: 16
  implicitHeight: 16
  width: 16
  height: 16

  // Cone body
  Rectangle {
    anchors.verticalCenter: parent.verticalCenter
    x: root.muted ? 5 : 2
    width: 4
    height: 6.5
    radius: 1
    color: root.ink
    opacity: root.muted ? 0.55 : 1
  }

  // Sound waves
  Canvas {
    id: waves
    anchors.fill: parent
    visible: !root.muted
    onPaint: {
      const ctx = getContext("2d")
      ctx.reset()
      ctx.strokeStyle = root.ink
      ctx.lineWidth = 1.35
      ctx.beginPath()
      ctx.arc(7, 8, 4, -0.7, 0.7)
      ctx.stroke()
      ctx.beginPath()
      ctx.arc(7, 8, 7, -0.7, 0.7)
      ctx.stroke()
    }
    onVisibleChanged: if (visible)
      requestPaint()
    Component.onCompleted: requestPaint()
  }

  // Mute slash
  Rectangle {
    visible: root.muted
    anchors.centerIn: parent
    width: 13
    height: 1.5
    rotation: -40
    color: Theme.danger
    radius: 1
  }
}
