import QtQuick
import QtQuick.Layouts
import "../../shared"

Item {
  id: root
  height: 36

  property string hint: ""

  RowLayout {
    anchors.fill: parent
    anchors.leftMargin: Theme.spaceXl
    anchors.rightMargin: Theme.spaceXl
    spacing: Theme.spaceLg

    Text {
      text: "Ⓐ Open   Ⓑ Back   Guide nav / switcher   ← ↑ ↓ → move   C Control Center"
      color: Theme.textMute
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSizeSm
      Layout.fillWidth: true
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
