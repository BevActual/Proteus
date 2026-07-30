import QtQuick
import QtQuick.Layouts
import "../shared"

// Live package-op status + Cancel while Packages.packageOpBusy.
Rectangle {
  id: root
  Layout.fillWidth: true
  Layout.maximumWidth: 520
  visible: Packages.packageOpBusy || (Packages.packageOpStatus.length > 0 && showIdleStatus)
  property bool showIdleStatus: false
  Layout.preferredHeight: visible ? col.implicitHeight + 20 : 0
  radius: Theme.radiusMd
  color: Theme.bgElevated
  border.width: 1
  border.color: Packages.packageOpBusy ? Theme.accent : Theme.border
  clip: true

  ColumnLayout {
    id: col
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Theme.spaceMd
    spacing: 8

    RowLayout {
      Layout.fillWidth: true
      Text {
        Layout.fillWidth: true
        text: Packages.packageOpBusy ? "Working…" : "Last result"
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: 12
        font.bold: true
      }
      Text {
        visible: Packages.packageOpBusy
        text: "Cancel"
        color: Theme.danger
        font.family: Theme.fontFamily
        font.pixelSize: 12
        font.bold: true
        MouseArea {
          anchors.fill: parent
          anchors.margins: -4
          cursorShape: Qt.PointingHandCursor
          onClicked: Packages.cancelPackageOp()
        }
      }
    }

    Text {
      Layout.fillWidth: true
      text: Packages.packageOpStatus
      color: Theme.textDim
      font.family: Theme.fontFamily
      font.pixelSize: 11
      wrapMode: Text.WordWrap
      maximumLineCount: 8
      elide: Text.ElideRight
    }
  }
}
