import QtQuick
import QtQuick.Layouts
import "../../shared"

// Titled horizontal shelf — active row large; inactive peek (dim + compact).
ColumnLayout {
  id: root
  spacing: Theme.spaceSm

  property string title: ""
  property var items: []
  property int focusedIndex: -1
  property bool chromeStyle: false
  property bool allowRemove: false
  property bool focusScale: true
  property real cardWidth: 160
  property real cardHeight: 120
  property bool shelfActive: false
  // Inactive shelves shrink toward peek size
  property real peekScale: 0.72

  readonly property real effectiveCardWidth: root.shelfActive
      ? root.cardWidth
      : Math.round(root.cardWidth * root.peekScale)
  readonly property real effectiveCardHeight: root.shelfActive
      ? root.cardHeight
      : Math.round(root.cardHeight * root.peekScale)

  signal itemActivated(var item)
  signal focusRequested(int index)
  signal removeRequested(var item)

  opacity: root.shelfActive ? 1 : 0.42
  Behavior on opacity {
    NumberAnimation {
      duration: 220
      easing.type: Easing.OutCubic
    }
  }

  Text {
    visible: root.title.length > 0
    text: root.title
    color: root.shelfActive ? Theme.text : Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSizeSm + (root.shelfActive ? 2 : 0)
    font.letterSpacing: 1.2
    font.weight: Font.DemiBold
    Behavior on color {
      ColorAnimation {
        duration: 180
        easing.type: Easing.OutCubic
      }
    }
  }

  ConsoleRow {
    Layout.fillWidth: true
    title: ""
    items: root.items
    focusedIndex: root.shelfActive ? root.focusedIndex : -1
    chromeStyle: root.chromeStyle
    allowRemove: root.allowRemove && root.shelfActive
    focusScale: root.focusScale && root.shelfActive
    cardWidth: root.effectiveCardWidth
    cardHeight: root.effectiveCardHeight
    onFocusRequested: i => root.focusRequested(i)
    onItemActivated: item => root.itemActivated(item)
    onRemoveRequested: item => root.removeRequested(item)
  }
}
