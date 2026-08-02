import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../shared"
import "../kit"

// Leaf UI for DesktopPane — Dock & menu bar.
ColumnLayout {
  id: root
  width: parent ? parent.width : implicitWidth
  spacing: Theme.spaceMd

  readonly property var screenOpts: {
    const _n = Quickshell.screens.length
    return Config.chromeScreenOptions()
  }

  SettingsGroup {
    title: "Dock"

    SettingsFormRow {
      label: "Show dock"
      hint: Config.dockEnabled ? "Floating shelf at the bottom" : "Hidden"
      showSeparator: true
      ThemeSwitch {
        checked: Config.dockEnabled
        onToggled: Config.dockEnabled = checked
      }
    }

    SettingsFormRow {
      label: "Automatically hide"
      hint: Config.dockEnabled ? "Reveal at the bottom edge" : "Requires Show dock"
      showSeparator: true
      ThemeSwitch {
        checked: Config.dockAutoHide
        enabled: Config.dockEnabled
        onToggled: Config.dockAutoHide = checked
      }
    }

    SettingsFormRow {
      label: "Show on"
      hint: !Config.dockEnabled ? "Requires Show dock"
          : (Config.dockMonitor === "all" ? "Every display" : Config.dockMonitor)
      showSeparator: true
      SettingsCombo {
        preferredWidth: 168
        enabled: Config.dockEnabled
        model: root.screenOpts
        currentValue: Config.dockMonitor
        onActivated: v => {
          Config.dockMonitor = String(v || "all")
        }
      }
    }

    SettingsFormRow {
      label: "Icon size"
      hint: Config.dockEnabled ? (Config.dockIconSize + " px") : "Requires Show dock"
      showSeparator: false
      ThemeSlider {
        Layout.preferredWidth: 160
        enabled: Config.dockEnabled
        from: 36
        to: 72
        stepSize: 2
        value: Config.dockIconSize
        onMoved: Config.dockIconSize = Math.round(value)
      }
    }
  }

  SettingsGroup {
    title: "Menu bar"

    SettingsFormRow {
      label: "Automatically hide"
      hint: "Reveal at the top edge"
      showSeparator: true
      ThemeSwitch {
        checked: Config.barAutoHide
        onToggled: Config.barAutoHide = checked
      }
    }

    SettingsFormRow {
      label: "Show on"
      hint: Config.barMonitor === "all" ? "Every display" : Config.barMonitor
      showSeparator: true
      SettingsCombo {
        preferredWidth: 168
        model: root.screenOpts
        currentValue: Config.barMonitor
        onActivated: v => {
          Config.barMonitor = String(v || "all")
        }
      }
    }

    SettingsFormRow {
      label: "Height"
      hint: Config.barHeight + " px"
      showSeparator: false
      ThemeSlider {
        Layout.preferredWidth: 160
        from: 28
        to: 48
        stepSize: 1
        value: Config.barHeight
        onMoved: Config.barHeight = Math.round(value)
      }
    }
  }

  SettingsGroup {
    title: "Advanced"

    SettingsFormRow {
      label: "Edit compositor config…"
      hint: "proteus-general.conf · gaps, borders, rounding"
      interactive: true
      showSeparator: false
      onActivated: Config.openGeneralConfInEditor()
      Text {
        text: "›"
        color: Theme.textMute
        font.pixelSize: 16
      }
    }
  }
}
