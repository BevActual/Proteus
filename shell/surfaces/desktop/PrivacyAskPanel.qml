import QtQuick
import QtQuick.Layouts
import "../../shared"

// Overlay plate for PrivacyAsk — Allow once / Always Allow / Deny.
Item {
  id: root
  anchors.fill: parent
  visible: PrivacyAsk.visible
  z: 40

  readonly property alias cardItem: card

  Rectangle {
    anchors.fill: parent
    color: Theme.scrimFill
    opacity: root.visible ? 1 : 0
    MouseArea {
      anchors.fill: parent
      onClicked: PrivacyAsk.cancel()
    }
  }

  Rectangle {
    id: card
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.verticalCenter: parent.verticalCenter
    width: Math.min(400, parent.width - 48)
    implicitHeight: col.implicitHeight + Theme.spaceLg * 2
    radius: Theme.radiusXl
    color: Theme.menuPlateFill
    border.width: 1
    border.color: Theme.chromeBorder

    ColumnLayout {
      id: col
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Theme.spaceLg
      spacing: Theme.spaceMd

      Text {
        Layout.fillWidth: true
        text: "Allow " + PrivacyAsk.categoryLabel + "?"
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: 18
        font.weight: Font.DemiBold
        wrapMode: Text.WordWrap
      }

      Text {
        Layout.fillWidth: true
        text: {
          const label = PrivacyAsk.appLabel.length ? PrivacyAsk.appLabel : "An app"
          const cat = PrivacyAsk.categoryLabel.toLowerCase()
          if (PrivacyAsk.isCapture)
            return label + " is using " + cat + "."
          return label + " wants " + cat + " access."
        }
        color: Theme.textDim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        wrapMode: Text.WordWrap
      }

      Text {
        Layout.fillWidth: true
        text: PrivacyAsk.honesty
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: 11
        wrapMode: Text.WordWrap
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spaceSm

        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 36
          radius: Theme.radiusMd
          color: denyMa.containsMouse ? Theme.chromeHover : Theme.elevatedFill
          border.width: 1
          border.color: Theme.chromeBorder
          Text {
            anchors.centerIn: parent
            text: "Deny"
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 13
            font.weight: Font.Medium
          }
          MouseArea {
            id: denyMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: PrivacyAsk.denyAlways()
          }
        }

        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 36
          radius: Theme.radiusMd
          color: onceMa.containsMouse ? Theme.chromeHover : Theme.elevatedFill
          border.width: 1
          border.color: Theme.chromeBorder
          Text {
            anchors.centerIn: parent
            text: "Allow once"
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 13
            font.weight: Font.Medium
          }
          MouseArea {
            id: onceMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: PrivacyAsk.allowOnce()
          }
        }
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 40
        radius: Theme.radiusMd
        color: alwaysMa.containsMouse ? Theme.chromeAccentSoft : Theme.accent
        Text {
          anchors.centerIn: parent
          text: "Always Allow"
          color: Theme.light ? "#ffffff" : Theme.bg
          font.family: Theme.fontFamily
          font.pixelSize: 13
          font.weight: Font.DemiBold
        }
        MouseArea {
          id: alwaysMa
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: PrivacyAsk.allowAlways()
        }
      }
    }
  }
}
