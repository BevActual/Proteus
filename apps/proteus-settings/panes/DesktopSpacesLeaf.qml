import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../shared"
import "../kit"

// Leaf UI for DesktopPane — Spaces (synced vs per-display).
ColumnLayout {
  id: root
  width: parent ? parent.width : implicitWidth
  spacing: Theme.spaceMd

  readonly property bool shareSpaces: Config.workspaceMode !== "perDisplay"

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
      showSeparator: false
      Text {
        text: "⌃⌘N"
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSm
      }
    }
  }
}
