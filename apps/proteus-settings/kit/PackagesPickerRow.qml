import QtQuick
import QtQuick.Layouts
import "../shared"

// One Software list row: checkbox + title/version/desc + optional row action.
// Works in ColumnLayout (Layout.*) and as a plain Item (implicitHeight).
Rectangle {
  id: root
  Layout.fillWidth: true
  Layout.maximumWidth: 520
  Layout.preferredHeight: implicitHeight
  width: parent ? parent.width : implicitWidth
  implicitWidth: 520
  implicitHeight: Math.max(44, row.implicitHeight + Theme.spaceMd * 2)
  radius: Theme.radiusMd
  color: Theme.bgPanel
  border.width: 1
  border.color: selected ? Theme.accent : Theme.border
  opacity: rowEnabled ? 1 : 0.55
  clip: true

  property string title: ""
  property string subtitle: ""
  property string version: ""
  property string badge: ""
  property bool selected: false
  property bool rowEnabled: true
  property bool showAction: false
  property string actionLabel: ""
  property bool actionDanger: false
  property bool applying: false

  signal toggled
  signal actionClicked

  RowLayout {
    id: row
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Theme.spaceMd
    spacing: Theme.spaceMd

    Rectangle {
      Layout.preferredWidth: 20
      Layout.preferredHeight: 20
      Layout.alignment: Qt.AlignVCenter
      radius: 4
      color: root.selected ? Theme.accent : "transparent"
      border.width: 1
      border.color: root.selected ? Theme.accent : Theme.border
      Text {
        anchors.centerIn: parent
        text: root.selected ? "✓" : ""
        color: "#ffffff"
        font.pixelSize: 12
        font.bold: true
        visible: root.selected
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      Layout.minimumWidth: 80
      spacing: 2
      RowLayout {
        Layout.fillWidth: true
        Text {
          Layout.fillWidth: true
          text: root.title
          color: Theme.text
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSize
          font.bold: true
          elide: Text.ElideRight
        }
        Text {
          visible: root.badge.length > 0
          text: root.badge
          color: Theme.accent
          font.family: Theme.fontFamily
          font.pixelSize: 10
          font.bold: true
        }
        Text {
          visible: root.version.length > 0
          text: root.version
          color: Theme.textDim
          font.family: Theme.fontFamily
          font.pixelSize: 11
        }
      }
      Text {
        Layout.fillWidth: true
        visible: root.subtitle.length > 0
        text: root.subtitle
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: 11
        wrapMode: Text.WordWrap
        maximumLineCount: 2
        elide: Text.ElideRight
      }
    }

    Rectangle {
      visible: root.showAction && root.actionLabel.length > 0
      Layout.preferredHeight: 28
      Layout.preferredWidth: Math.max(64, actionTxt.implicitWidth + 16)
      Layout.alignment: Qt.AlignVCenter
      radius: Theme.radius
      color: root.actionDanger
          ? Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.14)
          : Theme.accentSoft
      border.width: 1
      border.color: root.actionDanger ? Theme.danger : Theme.accent
      opacity: root.applying ? 0.5 : 1
      Text {
        id: actionTxt
        anchors.centerIn: parent
        text: root.actionLabel
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: 11
        font.bold: true
      }
      MouseArea {
        anchors.fill: parent
        enabled: !root.applying
        cursorShape: Qt.PointingHandCursor
        onClicked: root.actionClicked()
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    anchors.rightMargin: root.showAction ? 80 : 0
    enabled: root.rowEnabled && !root.applying
    cursorShape: root.rowEnabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: root.toggled()
  }
}
