import QtQuick
import QtQuick.Layouts
import "../../shared"

// Cinematic featured band — tracks focused shelf card (Theme poster art).
Item {
  id: root
  height: bandHeight

  property real bandHeight: 320
  property var item: null
  property string metaLine: ""
  property int focusedAction: -1 // 0 open, 1 details
  property bool bandFocused: false

  signal resumeRequested()
  signal detailsRequested()

  readonly property string title: item ? (item.title || "") : ""
  readonly property string meta: metaLine.length ? metaLine : (item ? (item.meta || "") : "")
  readonly property color color0: item && item.color0 ? item.color0 : Theme.bgElevated
  readonly property color color1: item && item.color1 ? item.color1 : Theme.bg
  readonly property string iconSource: item && item.iconSource ? String(item.iconSource) : ""

  // Full wash — reduces dead black space
  Rectangle {
    anchors.fill: parent
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0.0; color: root.color0 }
      GradientStop { position: 0.4; color: root.color1 }
      GradientStop { position: 1.0; color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.92) }
    }
  }

  Rectangle {
    anchors.fill: parent
    gradient: Gradient {
      GradientStop { position: 0.0; color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.12) }
      GradientStop { position: 0.5; color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.35) }
      GradientStop { position: 1.0; color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.88) }
    }
  }

  Rectangle {
    anchors.fill: parent
    border.width: root.bandFocused ? 2 : 0
    border.color: Theme.accent
    color: "transparent"
  }

  SquircleIcon {
    visible: root.iconSource.length > 0
    anchors.right: parent.right
    anchors.rightMargin: Theme.spaceXl * 2
    anchors.verticalCenter: parent.verticalCenter
    width: Math.min(140, root.bandHeight * 0.38)
    pixelSize: width
    source: root.iconSource
    opacity: 0.9
  }

  ColumnLayout {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.leftMargin: Theme.spaceXl
    anchors.rightMargin: Theme.spaceXl + 160
    anchors.bottomMargin: Theme.spaceLg
    spacing: Theme.spaceMd

    Text {
      Layout.fillWidth: true
      text: root.title.length ? root.title : "Console"
      color: Theme.text
      font.family: Theme.fontFamily
      font.pixelSize: 52
      font.weight: Font.Bold
      elide: Text.ElideRight
      maximumLineCount: 2
      wrapMode: Text.WordWrap
    }

    Text {
      Layout.fillWidth: true
      visible: root.meta.length > 0
      text: root.meta
      color: Theme.textDim
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSize + 2
      elide: Text.ElideRight
    }

    Row {
      spacing: Theme.spaceMd

      Rectangle {
        width: openLbl.implicitWidth + 32
        height: 44
        radius: Theme.radiusLg
        color: Theme.accent
        border.width: root.focusedAction === 0 ? 2 : 0
        border.color: "#ffffff"
        scale: root.focusedAction === 0 ? 1.04 : 1
        Behavior on scale {
          NumberAnimation {
            duration: 180
            easing.type: Easing.OutCubic
          }
        }

        Text {
          id: openLbl
          anchors.centerIn: parent
          text: "Ⓐ  Open"
          color: "#ffffff"
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSize + 1
          font.weight: Font.DemiBold
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.resumeRequested()
        }
      }

      Rectangle {
        width: detailsLbl.implicitWidth + 32
        height: 44
        radius: Theme.radiusLg
        color: Theme.elevatedFill
        border.width: root.focusedAction === 1 ? 2 : 1
        border.color: root.focusedAction === 1 ? Theme.accent : Theme.chromeBorder
        scale: root.focusedAction === 1 ? 1.04 : 1
        Behavior on scale {
          NumberAnimation {
            duration: 180
            easing.type: Easing.OutCubic
          }
        }

        Text {
          id: detailsLbl
          anchors.centerIn: parent
          text: "Ⓨ  Details"
          color: Theme.text
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSize + 1
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.detailsRequested()
        }
      }
    }
  }
}
