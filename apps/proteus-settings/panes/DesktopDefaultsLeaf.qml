import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../shared"
import "../kit"

// Leaf — Default applications (xdg-mime via proteus-defaults.py).
ColumnLayout {
  id: root
  width: parent ? parent.width : implicitWidth
  spacing: Theme.spaceMd

  Component.onCompleted: DefaultApps.refresh()

  SettingsGroup {
    title: "Default apps"

    Text {
      Layout.fillWidth: true
      Layout.maximumWidth: 520
      text: "Choose which app opens web links, folders, and common file types. Changes apply for your user (mimeapps.list)."
      color: Theme.textDim
      font.family: Theme.fontFamily
      font.pixelSize: 12
      wrapMode: Text.WordWrap
      Layout.bottomMargin: Theme.spaceXs
    }

    Text {
      Layout.fillWidth: true
      visible: DefaultApps.loading && DefaultApps.categories.length === 0
      text: "Loading…"
      color: Theme.textMute
      font.family: Theme.fontFamily
      font.pixelSize: 12
    }

    Text {
      Layout.fillWidth: true
      visible: DefaultApps.error.length > 0
      text: DefaultApps.error
      color: Theme.accent
      font.family: Theme.fontFamily
      font.pixelSize: 12
      wrapMode: Text.WordWrap
    }

    Repeater {
      model: DefaultApps.categories

      SettingsFormRow {
        required property var modelData
        required property int index
        label: modelData.label
        hint: {
          const cur = String(modelData.currentLabel || "")
          const h = String(modelData.hint || "")
          if (cur.length && cur !== "Not set")
            return cur + (h.length ? " · " + h : "")
          return h.length ? h : "Not set"
        }
        showSeparator: index < DefaultApps.categories.length - 1

        SettingsCombo {
          preferredWidth: 200
          enabled: !DefaultApps.loading && (modelData.candidates || []).length > 0
          model: {
            const _r = DefaultApps.rev
            return modelData.candidates || []
          }
          currentValue: String(modelData.current || "")
          onActivated: id => {
            if (!id.length || id === String(modelData.current || ""))
              return
            DefaultApps.setDefault(modelData.id, id)
          }
        }
      }
    }
  }

  SettingsGroup {
    title: "Advanced"

    SettingsFormRow {
      label: "Refresh list"
      hint: "Re-scan installed apps and current defaults"
      interactive: true
      showSeparator: true
      onActivated: DefaultApps.refresh()
      Text {
        text: "↻"
        color: Theme.textMute
        font.pixelSize: 14
      }
    }

    SettingsFormRow {
      label: "Edit mimeapps.list…"
      hint: "~/.config/mimeapps.list"
      interactive: true
      showSeparator: false
      onActivated: {
        const path = Quickshell.env("HOME") + "/.config/mimeapps.list"
        Quickshell.execDetached({
          command: [
            "bash",
            "-lc",
            "mkdir -p \"$HOME/.config\"; touch \"$HOME/.config/mimeapps.list\"; "
                + "(command -v xdg-open >/dev/null && xdg-open \"$HOME/.config/mimeapps.list\") "
                + "|| exec proteus-terminal -e nvim \"$HOME/.config/mimeapps.list\""
          ]
        })
      }
      Text {
        text: "›"
        color: Theme.textMute
        font.pixelSize: 16
      }
    }
  }
}
