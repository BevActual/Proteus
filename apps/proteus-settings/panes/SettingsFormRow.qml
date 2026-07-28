import Quickshell
import QtQuick
import QtQuick.Layouts
import "../shared"

// Row inside a SettingsGroup — label left, trailing control right.
Item {
  id: root
  Layout.fillWidth: true
  Layout.preferredHeight: Math.max(44, trail.implicitHeight + 12)

  property string label: ""
  property string hint: ""
  property bool showSeparator: true
  property bool interactive: false
  // Optional row tint for transient state (e.g. Keyboard recording a chord).
  // Takes precedence over hover; leave fully transparent to opt out.
  property color highlight: "transparent"
  property color labelColor: Theme.text
  signal activated()

  default property alias trailing: trail.data

  Rectangle {
    anchors.fill: parent
    color: root.highlight.a > 0 ? root.highlight
        : (ma.containsMouse && root.interactive ? Theme.bgHover : "transparent")
  }

  MouseArea {
    id: ma
    z: 0
    anchors.fill: parent
    enabled: root.interactive
    hoverEnabled: root.interactive
    cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: root.activated()
  }

  RowLayout {
    z: 1
    anchors.fill: parent
    anchors.leftMargin: Theme.spaceMd
    anchors.rightMargin: Theme.spaceMd
    spacing: Theme.spaceMd

    ColumnLayout {
      Layout.fillWidth: true
      spacing: 1
      Text {
        Layout.fillWidth: true
        text: root.label
        color: root.labelColor
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        elide: Text.ElideRight
      }
      Text {
        visible: root.hint.length > 0
        Layout.fillWidth: true
        text: root.hint
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: 11
        elide: Text.ElideRight
      }
    }

    RowLayout {
      id: trail
      spacing: Theme.spaceSm
      Layout.alignment: Qt.AlignVCenter
    }
  }

  Rectangle {
    z: 2
    visible: root.showSeparator
    anchors.left: parent.left
    anchors.leftMargin: Theme.spaceMd
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: 1
    color: Theme.separator
  }
}
