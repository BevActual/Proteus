import QtQuick
import QtQuick.Layouts
import "../../shared"

Item {
  id: root
  height: 200

  property var item: null
  property int focusedAction: -1 // 0 resume, 1 details

  signal resumeRequested()
  signal detailsRequested()

  readonly property string title: item ? (item.title || "") : ""
  readonly property string tag: item ? (item.tag || "") : ""
  readonly property string meta: item ? (item.meta || "") : ""
  readonly property color color0: item && item.color0 ? item.color0 : Theme.bgElevated
  readonly property color color1: item && item.color1 ? item.color1 : Theme.bg

  RowLayout {
    anchors.fill: parent
    spacing: Theme.spaceXl

    Rectangle {
      Layout.preferredWidth: Math.min(360, parent.width * 0.38)
      Layout.fillHeight: true
      radius: Theme.radiusXl
      clip: true
      border.width: 1
      border.color: Theme.chromeBorder

      gradient: Gradient {
        GradientStop { position: 0.0; color: root.color0 }
        GradientStop { position: 1.0; color: root.color1 }
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      Layout.fillHeight: true
      spacing: Theme.spaceMd

      Rectangle {
        visible: root.tag.length > 0
        Layout.preferredHeight: 22
        Layout.preferredWidth: tagLbl.implicitWidth + 14
        radius: Theme.radiusSm
        color: Theme.accentSoft

        Text {
          id: tagLbl
          anchors.centerIn: parent
          text: root.tag
          color: Theme.accent
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSizeSm
          font.letterSpacing: 0.6
          font.weight: Font.DemiBold
        }
      }

      Text {
        text: root.title
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: 36
        font.weight: Font.Bold
      }

      Text {
        text: root.meta
        color: Theme.textDim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }

      Row {
        spacing: Theme.spaceMd

        Rectangle {
          width: resumeLbl.implicitWidth + 28
          height: 36
          radius: Theme.radiusLg
          color: Theme.accent
          border.width: root.focusedAction === 0 ? 2 : 0
          border.color: "#ffffff"

          Text {
            id: resumeLbl
            anchors.centerIn: parent
            text: "Ⓐ  Resume"
            color: "#ffffff"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.weight: Font.DemiBold
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.resumeRequested()
          }
        }

        Rectangle {
          width: detailsLbl.implicitWidth + 28
          height: 36
          radius: Theme.radiusLg
          color: Theme.elevatedFill
          border.width: root.focusedAction === 1 ? 2 : 1
          border.color: root.focusedAction === 1 ? Theme.accent : Theme.chromeBorder

          Text {
            id: detailsLbl
            anchors.centerIn: parent
            text: "Ⓨ  Details"
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.detailsRequested()
          }
        }
      }

      Item { Layout.fillHeight: true }
    }
  }
}
