import Quickshell
import QtQuick
import QtQuick.Layouts
import ".."

// Apple-style grouped list — continuous rounded card, label-only rows.
// Keyboard: Tab into the list, ↑↓ move, Enter activates (same as click).
FocusScope {
  id: root
  Layout.fillWidth: true
  Layout.maximumWidth: 320
  implicitHeight: col.implicitHeight
  activeFocusOnTab: true

  property var items: []
  property var secondaryItems: []
  property int selectedIndex: -1
  signal activated(string key)

  readonly property var flatItems: {
    const out = []
    const a = root.items || []
    const b = root.secondaryItems || []
    for (let i = 0; i < a.length; i++)
      out.push(a[i])
    for (let j = 0; j < b.length; j++)
      out.push(b[j])
    return out
  }

  function clampSelection() {
    const n = (root.flatItems || []).length
    if (n <= 0) {
      selectedIndex = -1
      return
    }
    if (selectedIndex < 0)
      selectedIndex = 0
    else if (selectedIndex >= n)
      selectedIndex = n - 1
  }

  function moveSelection(delta) {
    const n = root.flatItems.length
    if (n <= 0)
      return
    if (selectedIndex < 0)
      selectedIndex = delta > 0 ? 0 : n - 1
    else
      selectedIndex = (selectedIndex + delta + n) % n
  }

  function activateSelected() {
    const rows = root.flatItems
    if (selectedIndex < 0 || selectedIndex >= rows.length)
      return
    const row = rows[selectedIndex]
    if (row && row.key)
      root.activated(String(row.key))
  }

  function selectAndFocus(i) {
    selectedIndex = i
    root.forceActiveFocus()
  }

  onActiveFocusChanged: {
    if (activeFocus)
      clampSelection()
  }

  onItemsChanged: clampSelection()
  onSecondaryItemsChanged: clampSelection()

  Keys.onPressed: event => {
    if (event.key === Qt.Key_Up) {
      moveSelection(-1)
      event.accepted = true
    } else if (event.key === Qt.Key_Down) {
      moveSelection(1)
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      activateSelected()
      event.accepted = true
    } else if (event.key === Qt.Key_Home) {
      if (flatItems.length)
        selectedIndex = 0
      event.accepted = true
    } else if (event.key === Qt.Key_End) {
      if (flatItems.length)
        selectedIndex = flatItems.length - 1
      event.accepted = true
    }
  }

  ColumnLayout {
    id: col
    width: parent.width
    spacing: Theme.spaceLg

    Rectangle {
      Layout.fillWidth: true
      implicitHeight: primaryCol.implicitHeight
      radius: Theme.radiusLg
      color: Theme.bgElevated
      clip: true

      ColumnLayout {
        id: primaryCol
        width: parent.width
        spacing: 0

        Repeater {
          model: root.items

          Item {
            required property var modelData
            required property int index
            readonly property int flatIndex: index
            readonly property bool rowSelected: root.activeFocus && root.selectedIndex === flatIndex
            Layout.fillWidth: true
            Layout.preferredHeight: 38

            Rectangle {
              anchors.fill: parent
              color: rowSelected ? Theme.accentSoft
                  : (rowMa.containsMouse ? Theme.bgHover : "transparent")
            }

            Text {
              anchors.left: parent.left
              anchors.leftMargin: Theme.spaceMd
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.label
              color: rowSelected ? Theme.accent : Theme.text
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSize
              font.bold: rowSelected
            }

            Text {
              anchors.right: parent.right
              anchors.rightMargin: Theme.spaceMd
              anchors.verticalCenter: parent.verticalCenter
              visible: !!(modelData.hint && String(modelData.hint).length)
              text: modelData.hint || ""
              color: Theme.textMute
              font.family: Theme.fontFamily
              font.pixelSize: 12
            }

            Rectangle {
              visible: index < root.items.length - 1
              anchors.left: parent.left
              anchors.leftMargin: Theme.spaceMd
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              height: 1
              color: Theme.separator
            }

            MouseArea {
              id: rowMa
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.selectAndFocus(flatIndex)
                root.activated(modelData.key)
              }
              onContainsMouseChanged: {
                if (containsMouse)
                  root.selectedIndex = flatIndex
              }
            }
          }
        }
      }
    }

    Rectangle {
      visible: root.secondaryItems.length > 0
      Layout.fillWidth: true
      implicitHeight: secondaryCol.implicitHeight
      radius: Theme.radiusLg
      color: Theme.bgElevated
      clip: true

      ColumnLayout {
        id: secondaryCol
        width: parent.width
        spacing: 0

        Repeater {
          model: root.secondaryItems

          Item {
            required property var modelData
            required property int index
            readonly property int flatIndex: (root.items ? root.items.length : 0) + index
            readonly property bool rowSelected: root.activeFocus && root.selectedIndex === flatIndex
            Layout.fillWidth: true
            Layout.preferredHeight: 38

            Rectangle {
              anchors.fill: parent
              color: rowSelected ? Theme.accentSoft
                  : (secMa.containsMouse ? Theme.bgHover : "transparent")
            }

            Text {
              anchors.left: parent.left
              anchors.leftMargin: Theme.spaceMd
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.label
              color: rowSelected ? Theme.accent : Theme.text
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSize
              font.bold: rowSelected
            }

            Text {
              anchors.right: parent.right
              anchors.rightMargin: Theme.spaceMd
              anchors.verticalCenter: parent.verticalCenter
              visible: !!(modelData.hint && String(modelData.hint).length)
              text: modelData.hint || ""
              color: Theme.textMute
              font.family: Theme.fontFamily
              font.pixelSize: 12
            }

            Rectangle {
              visible: index < root.secondaryItems.length - 1
              anchors.left: parent.left
              anchors.leftMargin: Theme.spaceMd
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              height: 1
              color: Theme.separator
            }

            MouseArea {
              id: secMa
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.selectAndFocus(flatIndex)
                root.activated(modelData.key)
              }
              onContainsMouseChanged: {
                if (containsMouse)
                  root.selectedIndex = flatIndex
              }
            }
          }
        }
      }
    }
  }
}
