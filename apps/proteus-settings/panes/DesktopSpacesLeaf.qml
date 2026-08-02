import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../shared"
import "../kit"

// Leaf UI for DesktopPane — Spaces (synced vs per-display) + multi-head honesty.
ColumnLayout {
  id: root
  width: parent ? parent.width : implicitWidth
  spacing: Theme.spaceMd

  readonly property bool shareSpaces: Config.workspaceMode !== "perDisplay"

  Component.onCompleted: SpacesDisplays.refresh()

  SettingsGroup {
    title: "Spaces"

    SettingsFormRow {
      label: "Displays share Spaces"
      hint: root.shareSpaces
          ? "Super+N switches every display together"
          : "Super+N switches only the focused display"
      showSeparator: true
      ThemeSwitch {
        checked: root.shareSpaces
        onToggled: Config.workspaceMode = checked ? "synced" : "perDisplay"
      }
    }

    SettingsFormRow {
      label: "This display only"
      hint: "Super+Ctrl+1–6 always switches the focused display (keyboard). Strip and wheel reach Spaces 1–10."
      showSeparator: true
      Text {
        text: "⌃⌘N"
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSm
      }
    }

    SettingsFormRow {
      label: "Displays"
      hint: SpacesDisplays.summaryLabel
      showSeparator: SpacesDisplays.monitors.length > 0
      Text {
        text: SpacesDisplays.monitorCount > 0
            ? (SpacesDisplays.monitorCount + "")
            : "—"
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSm
      }
    }

    Repeater {
      model: SpacesDisplays.monitors

      SettingsFormRow {
        required property var modelData
        required property int index
        label: String(modelData.name || ("Display " + (index + 1)))
        hint: "Space " + String(modelData.activeLogical || 1)
            + " · band " + String(modelData.bandStart || "?")
            + "–" + String(modelData.bandEnd || "?")
            + (modelData.focused ? " · focused" : "")
        showSeparator: index < SpacesDisplays.monitors.length - 1
        Text {
          text: "×10"
          color: Theme.textMute
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSizeSm
        }
      }
    }
  }

  Text {
    Layout.fillWidth: true
    visible: SpacesDisplays.hint.length > 0
    text: SpacesDisplays.hint
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }

  Text {
    Layout.fillWidth: true
    text: "Fact: multi-head dogfood via status/ensure — named Spaces · Super+7–10 · window migration on disconnect Out."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }
}
