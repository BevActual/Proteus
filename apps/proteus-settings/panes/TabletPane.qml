import Quickshell
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import "../shared"
import "../kit"

// Peripherals → Tablet leaf (pen/digitizer — not phone/tablet posture).
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: Theme.spaceMd

  readonly property var transformChoices: [
    { id: "0", label: "Normal" },
    { id: "1", label: "90°" },
    { id: "2", label: "180°" },
    { id: "3", label: "270°" }
  ]

  readonly property var outputChoices: {
    const out = [{ id: "", label: "Auto (unbound)" }]
    const mons = Hyprland.monitors || []
    for (let i = 0; i < mons.length; i++) {
      const n = String(mons[i].name || "").trim()
      if (!n.length)
        continue
      out.push({ id: n, label: n })
    }
    return out
  }

  readonly property string transformHint: {
    const v = String(Math.round(Number(Config.tabletTransform) || 0) % 4)
    for (let i = 0; i < root.transformChoices.length; i++) {
      if (root.transformChoices[i].id === v)
        return root.transformChoices[i].label
    }
    return "Normal"
  }

  readonly property string outputHint: {
    const cur = String(Config.tabletOutput || "")
    if (!cur.length)
      return "Auto (unbound)"
    return cur
  }

  SettingsGroup {
    title: "Drawing tablet"

    SettingsFormRow {
      label: "Bind to display"
      hint: root.outputHint
      showSeparator: true
      SettingsCombo {
        preferredWidth: 180
        model: root.outputChoices
        currentValue: String(Config.tabletOutput || "")
        onActivated: v => {
          Config.tabletOutput = String(v || "")
        }
      }
    }

    SettingsFormRow {
      label: "Orientation"
      hint: root.transformHint
      showSeparator: true
      SettingsCombo {
        preferredWidth: 140
        model: root.transformChoices
        currentValue: String(Math.round(Number(Config.tabletTransform) || 0) % 4)
        onActivated: v => {
          Config.tabletTransform = Math.round(Number(v) || 0) % 4
        }
      }
    }

    SettingsFormRow {
      label: "Relative mode"
      hint: Config.tabletRelativeInput
          ? "Mouse-like deltas"
          : "Off — absolute mapping"
      showSeparator: true
      ThemeSwitch {
        checked: Config.tabletRelativeInput
        onToggled: Config.tabletRelativeInput = checked
      }
    }

    SettingsFormRow {
      label: "Left-handed"
      hint: Config.tabletLeftHanded ? "Rotated 180°" : "Off"
      showSeparator: false
      ThemeSwitch {
        checked: Config.tabletLeftHanded
        onToggled: Config.tabletLeftHanded = checked
      }
    }
  }

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 480
    text: "Fact: settings.json + hyprctl input:tablet:* → proteus-general.conf. Active-area mm · pressure · per-tool curves stay Out."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }
}
