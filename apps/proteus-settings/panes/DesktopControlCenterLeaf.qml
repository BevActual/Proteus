import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../shared"
import "../kit"

// Leaf — Control Center tile layout (Customize foundation).
ColumnLayout {
  id: root
  width: parent ? parent.width : implicitWidth
  spacing: Theme.spaceMd

  readonly property var layout: {
    void ControlCenterLayout.layoutRev
    return ControlCenterLayout.resolvedLayout()
  }

  readonly property var tiles: layout.tiles || []

  function catalogLabel(id) {
    const cat = ControlCenterLayout.catalog
    for (let i = 0; i < cat.length; i++) {
      if (cat[i].id === id)
        return String(cat[i].label || id)
    }
    return String(id)
  }

  function cycleSize(id, cur) {
    const order = ["sm", "md", "lg"]
    let idx = order.indexOf(String(cur || "md"))
    if (idx < 0)
      idx = 1
    ControlCenterLayout.setTileSize(id, order[(idx + 1) % order.length])
  }

  function cycleSpan(id, cur) {
    ControlCenterLayout.setTileSpan(id, Number(cur) === 2 ? 1 : 2)
  }

  SettingsGroup {
    title: "Control Center"

    Text {
      Layout.fillWidth: true
      Layout.leftMargin: Theme.spaceMd
      Layout.rightMargin: Theme.spaceMd
      Layout.topMargin: Theme.spaceSm
      Layout.bottomMargin: Theme.spaceSm
      text: "Customize which quick tiles and plates appear in Control Center. Capability filters still apply on this device."
      color: Theme.textMute
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSizeSm
      wrapMode: Text.WordWrap
    }
  }

  SettingsGroup {
    title: "Layout"

    SettingsFormRow {
      label: "Columns"
      hint: Number(root.layout.columns) === 3
          ? "Three columns in the quick settings grid"
          : "Two columns in the quick settings grid"
      showSeparator: false
      SettingsSegmented {
        Layout.preferredWidth: Math.min(200, parent.width)
        options: [
          { id: "2", label: "2" },
          { id: "3", label: "3" }
        ]
        selected: String(Number(root.layout.columns) === 3 ? 3 : 2)
        onActivated: id => ControlCenterLayout.setColumns(Number(id))
      }
    }
  }

  SettingsGroup {
    title: "Plates"

    SettingsFormRow {
      label: "Sound plate"
      hint: ControlCenterLayout.plateVisible("sound") ? "Visible" : "Hidden"
      showSeparator: true
      ThemeSwitch {
        checked: ControlCenterLayout.plateVisible("sound")
        onToggled: ControlCenterLayout.setPlateVisible("sound", checked)
      }
    }

    SettingsFormRow {
      label: "Display plate"
      hint: ControlCenterLayout.plateVisible("display") ? "Visible" : "Hidden"
      showSeparator: false
      ThemeSwitch {
        checked: ControlCenterLayout.plateVisible("display")
        onToggled: ControlCenterLayout.setPlateVisible("display", checked)
      }
    }
  }

  SettingsGroup {
    title: "Tiles"

    Repeater {
      model: root.tiles

      delegate: SettingsFormRow {
        required property var modelData
        required property int index
        readonly property string tileId: String(modelData.id || "")
        label: root.catalogLabel(tileId)
        hint: (modelData.visible !== false ? "Shown" : "Hidden")
            + " · " + String(modelData.size || "md")
            + " · span " + String(modelData.span || 1)
        showSeparator: index < root.tiles.length - 1

        ThemeSwitch {
          checked: modelData.visible !== false
          onToggled: ControlCenterLayout.setTileVisible(tileId, checked)
        }

        Text {
          text: String(modelData.size || "md").toUpperCase()
          color: Theme.accent
          font.family: Theme.fontFamily
          font.pixelSize: 11
          font.bold: true
          MouseArea {
            anchors.fill: parent
            anchors.margins: -6
            cursorShape: Qt.PointingHandCursor
            onClicked: root.cycleSize(tileId, modelData.size)
          }
        }

        Text {
          text: "Span " + String(modelData.span || 1)
          color: Theme.textDim
          font.family: Theme.fontFamily
          font.pixelSize: 11
          MouseArea {
            anchors.fill: parent
            anchors.margins: -6
            cursorShape: Qt.PointingHandCursor
            onClicked: root.cycleSpan(tileId, modelData.span)
          }
        }

        Text {
          text: "↑"
          color: index > 0 ? Theme.textDim : Theme.textMute
          font.pixelSize: 12
          opacity: index > 0 ? 1 : 0.35
          MouseArea {
            anchors.fill: parent
            anchors.margins: -6
            enabled: index > 0
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: ControlCenterLayout.moveTile(tileId, -1)
          }
        }

        Text {
          text: "↓"
          color: index < root.tiles.length - 1 ? Theme.textDim : Theme.textMute
          font.pixelSize: 12
          opacity: index < root.tiles.length - 1 ? 1 : 0.35
          MouseArea {
            anchors.fill: parent
            anchors.margins: -6
            enabled: index < root.tiles.length - 1
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: ControlCenterLayout.moveTile(tileId, 1)
          }
        }
      }
    }
  }

  SettingsGroup {
    title: "Advanced"

    SettingsFormRow {
      label: "Reset layout"
      hint: "Restore default tiles and plates"
      interactive: true
      showSeparator: false
      onActivated: ControlCenterLayout.resetLayout()
      Text {
        text: "Reset"
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }
    }
  }
}
