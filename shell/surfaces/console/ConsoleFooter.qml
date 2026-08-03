import QtQuick
import QtQuick.Layouts
import "../../shared"

// Slim status + input-legend strip under the list IA.
// Left: library.statusHint (launch errors, install hints, Wi-Fi feedback —
// previously written but never shown). Right: pad/keyboard legend.
Item {
  id: root
  height: 32

  property string hint: ""
  property bool padActive: false

  Rectangle {
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    height: 1
    color: Theme.chromeHairline
    opacity: 0.4
  }

  RowLayout {
    anchors.fill: parent
    anchors.leftMargin: Theme.spaceXl
    anchors.rightMargin: Theme.spaceXl
    spacing: Theme.spaceLg

    Text {
      text: root.hint
      visible: root.hint.length > 0
      color: Theme.accent
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSizeSm
      font.weight: Font.Medium
      Layout.fillWidth: true
      elide: Text.ElideRight
    }

    Item {
      visible: !root.hint.length
      Layout.fillWidth: true
    }

    Text {
      text: root.padActive
          ? "Ⓐ Select   Ⓑ Back   LB · RB Tabs   Ⓨ Details   ☰ Exit"
          : "Enter Select   Esc Back   ← → Tabs   Y Details"
      color: Theme.textMute
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSizeSm
      elide: Text.ElideLeft
    }
  }
}
