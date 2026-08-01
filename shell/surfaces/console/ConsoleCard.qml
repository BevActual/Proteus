import QtQuick
import QtQuick.Layouts
import "../../shared"

Rectangle {
  id: root

  property string title: ""
  property string tag: ""
  property color color0: Theme.bgElevated
  property color color1: Theme.bg
  property bool focused: false
  property real cardWidth: 200
  property real cardHeight: 120

  signal activated()

  width: cardWidth
  height: cardHeight
  radius: Theme.radiusXl
  clip: true
  border.width: focused ? 2 : 1
  border.color: focused ? Theme.accent : Theme.chromeBorder

  gradient: Gradient {
    GradientStop { position: 0.0; color: root.color0 }
    GradientStop { position: 1.0; color: root.color1 }
  }

  Rectangle {
    anchors.fill: parent
    radius: root.radius
    color: root.focused ? Theme.accentSoft : "transparent"
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Theme.spaceMd
    spacing: Theme.spaceXs

    Rectangle {
      visible: root.tag.length > 0
      Layout.preferredHeight: 22
      Layout.preferredWidth: tagLabel.implicitWidth + 14
      radius: Theme.radiusSm
      color: Qt.rgba(0, 0, 0, 0.35)

      Text {
        id: tagLabel
        anchors.centerIn: parent
        text: root.tag
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSm
        font.letterSpacing: 0.6
      }
    }

    Item { Layout.fillHeight: true }

    Text {
      Layout.fillWidth: true
      text: root.title
      color: Theme.text
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSize + 2
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
