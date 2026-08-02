import QtQuick
import QtQuick.Layouts
import "../../shared"

Item {
  id: root

  property string title: ""
  property string iconSource: ""
  property color color0: Theme.bgElevated
  property color color1: Theme.bg
  property bool focused: false
  property bool chromeStyle: false
  property bool focusScale: true
  property real neighborDim: 1
  property real cardWidth: 200
  property real cardHeight: 120

  signal activated()

  width: cardWidth
  height: cardHeight
  opacity: root.focused ? 1 : root.neighborDim

  Behavior on opacity {
    NumberAnimation {
      duration: 200
      easing.type: Easing.OutCubic
    }
  }

  transform: [
    Scale {
      origin.x: root.width / 2
      origin.y: root.height / 2
      xScale: root.focusScale && root.focused ? 1.14 : 1
      yScale: root.focusScale && root.focused ? 1.14 : 1
      Behavior on xScale {
        NumberAnimation {
          duration: 200
          easing.type: Easing.OutCubic
        }
      }
      Behavior on yScale {
        NumberAnimation {
          duration: 200
          easing.type: Easing.OutCubic
        }
      }
    },
    Translate {
      y: root.focusScale && root.focused ? -6 : 0
      Behavior on y {
        NumberAnimation {
          duration: 200
          easing.type: Easing.OutCubic
        }
      }
    }
  ]

  Rectangle {
    id: plate
    anchors.fill: parent
    radius: Theme.radiusXl
    clip: true
    border.width: root.focused ? 3 : 1
    border.color: root.focused ? Theme.accent : Theme.chromeBorder
    color: root.chromeStyle ? Theme.elevatedFill : Theme.bgElevated
    z: root.focused ? 2 : 0

    Rectangle {
      anchors.fill: parent
      radius: plate.radius
      visible: !root.chromeStyle
      gradient: Gradient {
        GradientStop { position: 0.0; color: root.color0 }
        GradientStop { position: 1.0; color: root.color1 }
      }
    }

    Rectangle {
      anchors.fill: parent
      radius: plate.radius
      color: root.focused
          ? (root.chromeStyle ? Theme.chromeAccentSoft : Theme.accentSoft)
          : "transparent"
    }

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Theme.spaceMd
      spacing: Theme.spaceXs

      Item {
        Layout.fillWidth: true
        Layout.fillHeight: true

        SquircleIcon {
          visible: root.iconSource.length > 0
          anchors.centerIn: parent
          width: Math.min(parent.width * 0.42, parent.height * 0.55)
          pixelSize: width
          source: root.iconSource
          styleEnabled: true
          opacity: 0.95
        }
      }

      Text {
        Layout.fillWidth: true
        text: root.title
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize + (root.focused ? 3 : 2)
        font.weight: Font.DemiBold
        elide: Text.ElideRight
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.activated()
    }
  }
}
