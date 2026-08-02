import QtQuick
import QtQuick.Layouts
import "../../shared"

ColumnLayout {
  id: root
  spacing: Theme.spaceSm

  property string title: ""
  property var items: []
  property int focusedIndex: -1
  property bool chromeStyle: false
  property bool allowRemove: false
  property bool focusScale: true
  property real cardWidth: 200
  property real cardHeight: 120

  signal itemActivated(var item)
  signal focusRequested(int index)
  signal removeRequested(var item)

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
    // Extra height so focus scale / lift is not clipped
    Layout.preferredHeight: root.cardHeight * (root.focusScale ? 1.22 : 1) + 10
    contentWidth: row.implicitWidth + (root.focusScale ? root.cardWidth * 0.12 : 0)
    contentHeight: height
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentWidth > width

    Row {
      id: row
      anchors.verticalCenter: parent.verticalCenter
      spacing: Theme.spaceMd + (root.focusScale ? 8 : 0)
      leftPadding: root.focusScale ? 8 : 0

      Repeater {
        model: root.items

        ConsoleCard {
          required property var modelData
          required property int index
          title: modelData.title || ""
          iconSource: modelData.iconSource || ""
          color0: modelData.color0 || Theme.bgElevated
          color1: modelData.color1 || Theme.bg
          chromeStyle: root.chromeStyle || !!modelData.chromeStyle
          focusScale: root.focusScale
          focused: root.focusedIndex === index
          neighborDim: root.focusedIndex < 0 ? 1 : (root.focusedIndex === index ? 1 : 0.62)
          cardWidth: root.cardWidth
          cardHeight: root.cardHeight
          onActivated: {
            root.focusRequested(index)
            root.itemActivated(modelData)
          }

          Rectangle {
            visible: root.allowRemove && root.focusedIndex === index
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 6
            width: 22
            height: 22
            radius: 11
            color: Theme.bgHover
            border.width: 1
            border.color: Theme.chromeBorder
            z: 5
            Text {
              anchors.centerIn: parent
              text: "✕"
              color: Theme.text
              font.pixelSize: 11
              font.weight: Font.DemiBold
            }
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.removeRequested(modelData)
            }
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
      flick.contentX = Math.min(Math.max(0, flick.contentWidth - flick.width), right - flick.width + Theme.spaceMd)
  }

  onFocusedIndexChanged: ensureVisible(focusedIndex)
}
