import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

// Searchable font family picker for Appearance → Font.
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: Theme.spaceSm

  property var model: []
  property string selectedId: ""
  property string filterText: ""
  property bool scanning: false

  signal activated(string id)

  readonly property var filtered: {
    const q = String(root.filterText || "").trim().toLowerCase()
    const raw = root.model
    if (!raw || !raw.length)
      return []
    if (!q.length)
      return raw
    const out = []
    for (let i = 0; i < raw.length; i++) {
      const id = String(raw[i].id || "")
      const label = String(raw[i].label || id)
      if (id.toLowerCase().indexOf(q) >= 0 || label.toLowerCase().indexOf(q) >= 0)
        out.push(raw[i])
    }
    return out
  }

  SettingsFormRow {
    label: "Font"
    hint: root.scanning ? "Scanning…" : (root.selectedId.length ? root.selectedId : "None")
    showSeparator: true
    Text {
      text: "Aa"
      color: Theme.text
      font.family: root.selectedId.length ? root.selectedId : Theme.fontFamily
      font.pixelSize: 18
    }
  }

  TextField {
    id: searchField
    Layout.fillWidth: true
    Layout.leftMargin: Theme.spaceMd
    Layout.rightMargin: Theme.spaceMd
    placeholderText: "Search fonts…"
    color: Theme.text
    placeholderTextColor: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSize
    background: Rectangle {
      radius: Theme.radiusSm
      color: Theme.bgHover
      border.width: searchField.activeFocus ? 1 : 0
      border.color: Theme.accent
    }
    text: root.filterText
    onTextChanged: root.filterText = text
  }

  Item {
    Layout.fillWidth: true
    Layout.preferredHeight: Math.min(220, Math.max(48, fontList.contentHeight + 8))
    Layout.leftMargin: Theme.spaceSm
    Layout.rightMargin: Theme.spaceSm
    Layout.bottomMargin: Theme.spaceSm
    clip: true

    ListView {
      id: fontList
      anchors.fill: parent
      clip: true
      spacing: 0
      model: root.filtered
      boundsBehavior: Flickable.StopAtBounds
      ScrollBar.vertical: ScrollBar {
        policy: fontList.contentHeight > fontList.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
      }

      delegate: Item {
        id: row
        required property var modelData
        required property int index
        width: fontList.width
        height: 40

        readonly property bool selected: root.selectedId === String(modelData.id)

        Rectangle {
          anchors.fill: parent
          color: row.selected ? Theme.accentSoft : (ma.containsMouse ? Theme.bgHover : "transparent")
        }

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: Theme.spaceMd
          anchors.rightMargin: Theme.spaceMd
          spacing: Theme.spaceSm

          Text {
            text: "Aa"
            color: Theme.text
            font.family: modelData.id
            font.pixelSize: 16
          }
          Text {
            Layout.fillWidth: true
            text: modelData.label || modelData.id
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            elide: Text.ElideRight
          }
          Text {
            visible: !!(modelData.user)
            text: "Added"
            color: Theme.textMute
            font.family: Theme.fontFamily
            font.pixelSize: 11
          }
          Text {
            visible: row.selected
            text: "✓"
            color: Theme.accent
            font.pixelSize: 14
          }
        }

        MouseArea {
          id: ma
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.activated(String(modelData.id))
        }

        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.leftMargin: Theme.spaceMd
          height: 1
          color: Theme.separator
          opacity: row.index < root.filtered.length - 1 ? 0.5 : 0
        }
      }
    }

    Text {
      visible: !root.scanning && root.filtered.length === 0
      anchors.centerIn: parent
      text: root.filterText.length ? "No matching fonts" : "No fonts found"
      color: Theme.textMute
      font.family: Theme.fontFamily
      font.pixelSize: 12
    }
  }
}
