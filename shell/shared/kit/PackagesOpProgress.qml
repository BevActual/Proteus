import QtQuick
import QtQuick.Layouts
import ".."

// Live package-op status + Cancel; keeps last command / error after finish.
Rectangle {
  id: root
  Layout.fillWidth: true
  Layout.maximumWidth: 520
  visible: Packages.packageOpBusy
      || (showIdleStatus && (Packages.packageOpCommand.length > 0 || Packages.packageOpStatus.length > 0))
  property bool showIdleStatus: true
  Layout.preferredHeight: visible ? col.implicitHeight + 20 : 0
  radius: Theme.radiusMd
  color: Theme.bgElevated
  border.width: 1
  border.color: Packages.packageOpBusy
      ? Theme.accent
      : (Packages.packageOpLastOk ? Theme.border : Theme.danger)
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
        text: Packages.packageOpBusy
            ? "Working…"
            : (Packages.packageOpLastOk ? "Last result" : "Last error")
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
      visible: Packages.packageOpCommand.length > 0
      text: "$ " + Packages.packageOpCommand
      color: Theme.textMute
      font.family: Theme.fontFamily
      font.pixelSize: 11
      wrapMode: Text.WrapAnywhere
      opacity: 0.9
    }

    Text {
      Layout.fillWidth: true
      visible: !Packages.packageOpBusy && Packages.packageOpLastError.length > 0
      text: Packages.packageOpLastError
      color: Theme.danger
      font.family: Theme.fontFamily
      font.pixelSize: 11
      wrapMode: Text.WordWrap
    }

    Text {
      Layout.fillWidth: true
      text: Packages.packageOpStatus
      color: Theme.textDim
      font.family: Theme.fontFamily
      font.pixelSize: 11
      wrapMode: Text.WordWrap
      maximumLineCount: 10
      elide: Text.ElideRight
    }
  }
}
