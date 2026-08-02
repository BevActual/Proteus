import Quickshell
import QtQuick
import QtQuick.Layouts
import "../shared"
import "../kit"

// Leaf — Flatpak sandbox overrides (mic / camera) + honesty for screen.
ColumnLayout {
  id: root
  width: parent ? parent.width : implicitWidth
  spacing: Theme.spaceMd

  readonly property var rows: {
    const _r = Permissions.rev
    return Permissions.flatpakApps || []
  }

  readonly property var micOpts: [
    {
      id: "allow",
      label: "Allow"
    },
    {
      id: "ask",
      label: "Ask"
    },
    {
      id: "deny",
      label: "Deny"
    }
  ]

  Component.onCompleted: Permissions.refreshFlatpak()

  SettingsGroup {
    title: "Flatpak apps"

    Text {
      Layout.fillWidth: true
      Layout.maximumWidth: 520
      text: "User Flatpaks only. Microphone → pulseaudio socket (also affects app audio). Camera deny → nodevice=all + keep dri. Screen stays portal-prompted. Ask leaves the sandbox unchanged."
      color: Theme.textDim
      font.family: Theme.fontFamily
      font.pixelSize: 12
      wrapMode: Text.WordWrap
      Layout.bottomMargin: Theme.spaceXs
    }

    Text {
      Layout.fillWidth: true
      visible: !Permissions.flatpakAvailable && !Permissions.flatpakLoading
      text: Permissions.flatpakHint.length ? Permissions.flatpakHint : "flatpak not installed"
      color: Theme.textMute
      font.family: Theme.fontFamily
      font.pixelSize: 12
    }

    Text {
      Layout.fillWidth: true
      visible: Permissions.flatpakLoading
      text: "Loading…"
      color: Theme.textMute
      font.family: Theme.fontFamily
      font.pixelSize: 12
    }

    Text {
      Layout.fillWidth: true
      visible: Permissions.flatpakAvailable && root.rows.length === 0 && !Permissions.flatpakLoading
      text: "No user Flatpak apps installed"
      color: Theme.textMute
      font.family: Theme.fontFamily
      font.pixelSize: 12
    }
  }

  Repeater {
    model: root.rows

    SettingsGroup {
      required property var modelData
      required property int index
      title: String(modelData.label || modelData.id)

      SettingsFormRow {
        label: "Microphone"
        hint: "pulseaudio socket override"
        showSeparator: true
        SettingsCombo {
          preferredWidth: 120
          model: root.micOpts
          currentValue: Permissions.appGrant(modelData.id, "microphone")
          onActivated: id => Permissions.setAppGrant(modelData.id, "microphone", id)
        }
      }

      SettingsFormRow {
        label: "Camera"
        hint: "device access override"
        showSeparator: true
        SettingsCombo {
          preferredWidth: 120
          model: root.micOpts
          currentValue: Permissions.appGrant(modelData.id, "camera")
          onActivated: id => Permissions.setAppGrant(modelData.id, "camera", id)
        }
      }

      SettingsFormRow {
        label: "Screen recording"
        hint: String(modelData.screenHint || "Portal prompts · not override-gated")
        showSeparator: false
        Text {
          text: "Portal"
          color: Theme.textMute
          font.family: Theme.fontFamily
          font.pixelSize: 12
        }
      }
    }
  }

  SettingsFormRow {
    label: "Refresh list"
    hint: "Re-scan user Flatpaks"
    interactive: true
    showSeparator: false
    onActivated: Permissions.refreshFlatpak()
    Text {
      text: "↻"
      color: Theme.textMute
      font.pixelSize: 14
    }
  }

  Text {
    Layout.fillWidth: true
    visible: Permissions.error.length > 0
    text: Permissions.error
    color: Theme.accent
    font.family: Theme.fontFamily
    font.pixelSize: 12
    wrapMode: Text.WordWrap
  }
}
