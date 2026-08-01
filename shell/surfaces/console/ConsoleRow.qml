import QtQuick
import QtQuick.Layouts
import "../../shared"

ColumnLayout {
  id: root
  spacing: Theme.spaceSm

  property string title: ""
  property var items: []
  property int focusedIndex: -1
  property real cardWidth: 200
  property real cardHeight: 120

  signal itemActivated(var item)
  signal focusRequested(int index)

  Text {
    visible: root.title.length > 0
    text: root.title
    color: Theme.textDim
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSizeSm
    font.letterSpacing: 1.2
    font.weight: Font.DemiBold
  }

  Flickable {
    id: flick
    Layout.fillWidth: true
    Layout.preferredHeight: root.cardHeight + 4
    contentWidth: row.implicitWidth
    contentHeight: height
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentWidth > width

    Row {
      id: row
      spacing: Theme.spaceMd

      Repeater {
        model: root.items

        ConsoleCard {
          required property var modelData
          required property int index
          title: modelData.title || ""
          tag: modelData.tag || ""
          color0: modelData.color0 || Theme.bgElevated
          color1: modelData.color1 || Theme.bg
          focused: root.focusedIndex === index
          cardWidth: root.cardWidth
          cardHeight: root.cardHeight
          onActivated: {
            root.focusRequested(index)
            root.itemActivated(modelData)
          }
        }
      }
    }
  }

  function ensureVisible(index) {
    if (!items || index < 0 || index >= items.length)
      return
    const card = row.children[index]
    if (!card)
      return
    const left = card.x
    const right = card.x + card.width
    if (left < flick.contentX)
      flick.contentX = Math.max(0, left - Theme.spaceMd)
    else if (right > flick.contentX + flick.width)
      flick.contentX = Math.min(flick.contentWidth - flick.width, right - flick.width + Theme.spaceMd)
  }

  onFocusedIndexChanged: ensureVisible(focusedIndex)
}
