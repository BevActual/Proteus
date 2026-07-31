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

  function screenIndex(sel) {
    const opts = screenOpts
    for (let i = 0; i < opts.length; i++) {
      if (opts[i].id === sel)
        return i
    }
    return 0
  }

  function syncMonitors() {
    dockMonBox.currentIndex = root.screenIndex(Config.dockMonitor)
    barMonBox.currentIndex = root.screenIndex(Config.barMonitor)
  }

  Connections {
    target: Config
    function onDockMonitorChanged() {
      dockMonBox.currentIndex = root.screenIndex(Config.dockMonitor)
    }
    function onBarMonitorChanged() {
      barMonBox.currentIndex = root.screenIndex(Config.barMonitor)
    }
  }

  Component.onCompleted: syncMonitors()

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
      ComboBox {
        id: dockMonBox
        Layout.preferredWidth: 168
        enabled: Config.dockEnabled
        textRole: "label"
        valueRole: "id"
        model: root.screenOpts
        onActivated: Config.dockMonitor = String(currentValue || "all")
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
      ComboBox {
        id: barMonBox
        Layout.preferredWidth: 168
        textRole: "label"
        valueRole: "id"
        model: root.screenOpts
        onActivated: Config.barMonitor = String(currentValue || "all")
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
