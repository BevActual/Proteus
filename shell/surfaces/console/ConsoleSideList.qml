import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../shared"

// Left column: Search + Filter fields + ListView (A–Z apps, or hub-grouped Settings).
Item {
  id: root

  property var items: []
  property int focusedIndex: 0
  property bool listFocused: false
  property bool searchFocused: false
  property bool filterFocused: false
  property string searchText: ""
  property string filterText: ""
  property string emptyCopy: "Nothing here yet"
  property string emptyHint: ""

  signal searchTextEdited(string text)
  signal filterTextEdited(string text)
  signal indexRequested(int index)
  signal itemActivated(var item)
  signal searchFocusRequested()
  signal filterFocusRequested()
  signal listFocusRequested()

  readonly property var currentItem: {
    if (!items || !items.length)
      return null
    const i = Math.max(0, Math.min(focusedIndex, items.length - 1))
    return items[i]
  }

  function isSection(item) {
    return !!(item && (item.kind === "section" || item.isSection || item.selectable === false))
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Theme.spaceMd
    spacing: Theme.spaceSm

    TextField {
      id: searchField
      Layout.fillWidth: true
      Layout.preferredHeight: 40
      placeholderText: "Search"
      text: root.searchText
      color: Theme.text
      placeholderTextColor: Theme.textMute
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSize + 1
      leftPadding: 12
      rightPadding: 12
      background: Rectangle {
        radius: Theme.radiusMd
        color: Theme.elevatedFill
        border.width: root.searchFocused ? 2 : 1
        border.color: root.searchFocused ? Theme.accent : Theme.chromeBorder
      }
      onTextChanged: {
        if (text !== root.searchText)
          root.searchTextEdited(text)
      }
      onActiveFocusChanged: {
        if (activeFocus)
          root.searchFocusRequested()
      }
    }

    TextField {
      id: filterField
      Layout.fillWidth: true
      Layout.preferredHeight: 36
      placeholderText: "Filter"
      text: root.filterText
      color: Theme.text
      placeholderTextColor: Theme.textMute
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSize
      leftPadding: 12
      rightPadding: 12
      background: Rectangle {
        radius: Theme.radiusMd
        color: Theme.elevatedFill
        border.width: root.filterFocused ? 2 : 1
        border.color: root.filterFocused ? Theme.accent : Theme.chromeBorder
      }
      onTextChanged: {
        if (text !== root.filterText)
          root.filterTextEdited(text)
      }
      onActiveFocusChanged: {
        if (activeFocus)
          root.filterFocusRequested()
      }
    }

    Text {
      visible: !root.items || !root.items.length
      Layout.fillWidth: true
      Layout.topMargin: Theme.spaceMd
      text: root.emptyCopy
      color: Theme.textMute
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSize + 1
      wrapMode: Text.WordWrap
    }

    Text {
      visible: (!root.items || !root.items.length) && root.emptyHint.length > 0
      Layout.fillWidth: true
      text: root.emptyHint
      color: Theme.textDim
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSizeSm
      wrapMode: Text.WordWrap
    }

    ListView {
      id: list
      Layout.fillWidth: true
      Layout.fillHeight: true
      visible: root.items && root.items.length > 0
      clip: true
      model: root.items
      currentIndex: root.focusedIndex
      boundsBehavior: Flickable.StopAtBounds
      highlightMoveDuration: 120
      highlightMoveVelocity: -1
      spacing: 2

      onCurrentIndexChanged: {
        if (currentIndex !== root.focusedIndex && currentIndex >= 0)
          root.indexRequested(currentIndex)
      }

      delegate: Rectangle {
        required property var modelData
        required property int index
        readonly property bool section: root.isSection(modelData)
        width: list.width
        height: section ? 28 : 44
        radius: section ? 0 : Theme.radiusMd
        color: {
          if (section)
            return "transparent"
          if (root.listFocused && index === root.focusedIndex)
            return Theme.chromeAccentSoft
          if (index === root.focusedIndex)
            return Theme.chromeHover
          return "transparent"
        }
        border.width: !section && root.listFocused && index === root.focusedIndex ? 1 : 0
        border.color: Theme.accent

        // Section header
        Text {
          visible: section
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.leftMargin: Theme.spaceSm
          anchors.bottomMargin: 2
          text: modelData.title || ""
          color: Theme.textDim
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSizeSm
          font.letterSpacing: 1.1
          font.weight: Font.DemiBold
          elide: Text.ElideRight
        }

        RowLayout {
          visible: !section
          anchors.fill: parent
          anchors.leftMargin: Theme.spaceSm
          anchors.rightMargin: Theme.spaceSm
          spacing: Theme.spaceSm

          Rectangle {
            Layout.preferredWidth: 28
            Layout.preferredHeight: 28
            radius: 6
            color: modelData.color0 || Theme.elevatedFill
            border.width: 1
            border.color: Theme.chromeBorder

            Image {
              anchors.fill: parent
              anchors.margins: 3
              visible: modelData.iconSource && String(modelData.iconSource).length
              source: modelData.iconSource || ""
              fillMode: Image.PreserveAspectFit
              asynchronous: true
            }
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            Text {
              Layout.fillWidth: true
              text: modelData.title || modelData.id || ""
              color: Theme.text
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSize + 1
              font.weight: index === root.focusedIndex ? Font.DemiBold : Font.Normal
              elide: Text.ElideRight
            }

            Text {
              Layout.fillWidth: true
              visible: modelData.tag === "LEAF" && modelData.meta && String(modelData.meta).length
              text: modelData.meta || ""
              color: Theme.textMute
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSizeSm
              elide: Text.ElideRight
            }
          }

          Text {
            visible: modelData.tag === "HUB"
            text: "Hub"
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
          }
        }

        MouseArea {
          anchors.fill: parent
          enabled: !section
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            root.listFocusRequested()
            root.indexRequested(index)
          }
          onDoubleClicked: root.itemActivated(modelData)
        }
      }

      onCountChanged: {
        if (root.focusedIndex >= count && count > 0)
          root.indexRequested(count - 1)
      }
    }
  }

  function focusSearchField() {
    searchField.forceActiveFocus()
  }

  function focusFilterField() {
    filterField.forceActiveFocus()
  }

  function clearFieldFocus() {
    searchField.focus = false
    filterField.focus = false
  }
}
