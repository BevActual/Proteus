import QtQuick
import QtQuick.Layouts
import "../../shared"

Item {
  id: root
  height: 36

  property string hint: ""
  property string contextLine: ""

  RowLayout {
    anchors.fill: parent
    anchors.leftMargin: Theme.spaceXl
    anchors.rightMargin: Theme.spaceXl
    spacing: Theme.spaceLg

    Text {
      text: root.contextLine.length
          ? root.contextLine
          : "◎ Guide nav · Ⓐ Open · C Control Center"
      color: Theme.accent
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSizeSm
      font.weight: Font.Medium
      Layout.fillWidth: true
      elide: Text.ElideRight
    }

    Text {
      visible: root.hint.length > 0
      text: root.hint
      color: Theme.textDim
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSizeSm
      elide: Text.ElideRight
      Layout.maximumWidth: parent.width * 0.35
    }
  }
}
