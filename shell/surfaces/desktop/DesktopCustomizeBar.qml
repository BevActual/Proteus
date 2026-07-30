import QtQuick
import QtQuick.Layouts
import "../../shared"

Rectangle {
  id: root
  height: 48
  radius: 24
  color: Qt.rgba(28 / 255, 28 / 255, 30 / 255, 0.88)
  border.width: 1
  border.color: Qt.rgba(1, 1, 1, 0.12)

  signal addWidget()
  signal done()
  signal toggleSnapGrid()

  property bool snapToGrid: false

  RowLayout {
    anchors.fill: parent
    anchors.leftMargin: 10
    anchors.rightMargin: 10
    spacing: 8

    Text {
      text: "Customize"
      color: Qt.rgba(1, 1, 1, 0.55)
      font.family: Theme.fontFamily
      font.pixelSize: 12
      Layout.leftMargin: 6
    }

    Rectangle {
      Layout.preferredHeight: 32
      Layout.preferredWidth: addLabel.implicitWidth + 20
      radius: 16
      color: Qt.rgba(1, 1, 1, 0.1)
      Text {
        id: addLabel
        anchors.centerIn: parent
        text: "Add Widget"
        color: "#f5f5f7"
        font.family: Theme.fontFamily
        font.pixelSize: 12
        font.weight: Font.Medium
      }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.addWidget()
      }
    }

    Rectangle {
      Layout.preferredHeight: 32
      Layout.preferredWidth: snapLabel.implicitWidth + 20
      radius: 16
      color: root.snapToGrid ? Theme.accentSoft : Qt.rgba(1, 1, 1, 0.1)
      border.width: root.snapToGrid ? 1 : 0
      border.color: Theme.accent
      Text {
        id: snapLabel
        anchors.centerIn: parent
        text: root.snapToGrid ? "Snap on" : "Snap to Grid"
        color: "#f5f5f7"
        font.family: Theme.fontFamily
        font.pixelSize: 12
        font.weight: Font.Medium
      }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggleSnapGrid()
      }
    }

    Item {
      Layout.fillWidth: true
    }

    Rectangle {
      Layout.preferredHeight: 32
      Layout.preferredWidth: doneLabel.implicitWidth + 24
      radius: 16
      color: Theme.accent
      Text {
        id: doneLabel
        anchors.centerIn: parent
        text: "Done"
        color: "#fff"
        font.family: Theme.fontFamily
        font.pixelSize: 12
        font.weight: Font.Medium
      }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.done()
      }
    }
  }
}
