import QtQuick

Item {
  id: root
  anchors.fill: parent
  property bool active: false
  property real guideX: -1
  property real guideY: -1

  visible: active

  Rectangle {
    visible: root.guideX >= 0
    x: root.guideX - 0.5
    width: 1
    height: parent.height
    color: Qt.rgba(1, 1, 1, 0.45)
  }

  Rectangle {
    visible: root.guideY >= 0
    y: root.guideY - 0.5
    width: parent.width
    height: 1
    color: Qt.rgba(1, 1, 1, 0.45)
  }
}
