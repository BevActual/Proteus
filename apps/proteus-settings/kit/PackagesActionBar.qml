import QtQuick
import QtQuick.Layouts
import "../shared"

// Select-all strip + primary Install/Remove button (sits under a capped list viewport).
ColumnLayout {
  id: root
  Layout.fillWidth: true
  Layout.maximumWidth: 520
  spacing: 8

  property int selectedCount: 0
  property int totalCount: 0
  property bool applying: false
  property bool danger: false
  property string idleLabel: "Select items"
  property string activePrefix: "Apply"

  signal selectAllClicked
  signal actionClicked

  RowLayout {
    Layout.fillWidth: true
    visible: root.totalCount > 0 && !root.applying
    Text {
      Layout.fillWidth: true
      text: root.selectedCount + " of " + root.totalCount + " selected"
      color: Theme.textDim
      font.family: Theme.fontFamily
      font.pixelSize: 12
    }
    Text {
      text: root.selectedCount === root.totalCount && root.totalCount > 0 ? "Select none" : "Select all"
      color: Theme.accent
      font.family: Theme.fontFamily
      font.pixelSize: 12
      font.bold: true
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.selectAllClicked()
      }
    }
  }

  Rectangle {
    Layout.fillWidth: true
    Layout.preferredHeight: 44
    radius: Theme.radiusMd
    color: root.danger
        ? Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.14)
        : Theme.accentSoft
    border.width: 1
    border.color: root.danger ? Theme.danger : Theme.accent
    opacity: (root.applying || root.selectedCount === 0) ? 0.5 : 1
    Text {
      anchors.centerIn: parent
      text: {
        if (root.applying)
          return "Applying…"
        if (root.selectedCount === 0)
          return root.idleLabel
        return root.activePrefix + " " + root.selectedCount + "…"
      }
      color: Theme.text
      font.family: Theme.fontFamily
      font.bold: true
      font.pixelSize: 12
    }
    MouseArea {
      anchors.fill: parent
      enabled: !root.applying && root.selectedCount > 0
      cursorShape: Qt.PointingHandCursor
      onClicked: root.actionClicked()
    }
  }
}
