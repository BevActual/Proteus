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

  readonly property string areaSizeHint: {
    const w = Math.round(Number(Config.tabletActiveAreaSizeX) || 0)
    const h = Math.round(Number(Config.tabletActiveAreaSizeY) || 0)
    if (w <= 0 || h <= 0)
      return "Unset — full tablet (0×0 mm)"
    return w + "×" + h + " mm"
  }

  readonly property string areaPosHint: {
    const x = Math.round(Number(Config.tabletActiveAreaPosX) || 0)
    const y = Math.round(Number(Config.tabletActiveAreaPosY) || 0)
    return x + ", " + y + " mm from origin"
  }

  readonly property string pressureHint: {
    const a = Number(Config.tabletPressureMin)
    const b = Number(Config.tabletPressureMax)
    const min = isFinite(a) ? a : -1
    const max = isFinite(b) ? b : -1
    if (min < 0 && max < 0)
      return "Driver default (−1 / −1) · linear remap, all tools"
    return min.toFixed(2) + " … " + max.toFixed(2) + " · linear remap, all tools"
  }

  readonly property var eraserButtonChoices: [
    { id: "0", label: "Default (0)" },
    { id: "331", label: "BTN_STYLUS (331)" },
    { id: "332", label: "BTN_STYLUS2 (332)" },
    { id: "329", label: "BTN_STYLUS3 (329)" },
    { id: "273", label: "BTN_RIGHT (273)" }
  ]

  readonly property string eraserButtonHint: {
    const v = String(Math.round(Number(Config.tabletEraserButtonOverride) || 0))
    for (let i = 0; i < root.eraserButtonChoices.length; i++) {
      if (root.eraserButtonChoices[i].id === v)
        return root.eraserButtonChoices[i].label
    }
    return "Button code " + v
  }

  readonly property string regionSizeHint: {
    const w = Math.round(Number(Config.tabletRegionSizeX) || 0)
    const h = Math.round(Number(Config.tabletRegionSizeY) || 0)
    if (w <= 0 || h <= 0)
      return "Unset — map to full bound display (0×0)"
    return w + "×" + h + " px"
  }

  readonly property string regionPosHint: {
    const x = Math.round(Number(Config.tabletRegionPosX) || 0)
    const y = Math.round(Number(Config.tabletRegionPosY) || 0)
    return x + ", " + y + " px in monitor layout"
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

  SettingsGroup {
    title: "Active area"

    SettingsFormRow {
      label: "Width (mm)"
      hint: root.areaSizeHint
      showSeparator: true
      ThemeSlider {
        Layout.preferredWidth: 150
        from: 0
        to: 400
        stepSize: 1
        value: Math.max(0, Math.min(400, Math.round(Number(Config.tabletActiveAreaSizeX) || 0)))
        onMoved: Config.tabletActiveAreaSizeX = Math.round(value)
      }
    }

    SettingsFormRow {
      label: "Height (mm)"
      hint: "0×0 size = full tablet / unset"
      showSeparator: true
      ThemeSlider {
        Layout.preferredWidth: 150
        from: 0
        to: 400
        stepSize: 1
        value: Math.max(0, Math.min(400, Math.round(Number(Config.tabletActiveAreaSizeY) || 0)))
        onMoved: Config.tabletActiveAreaSizeY = Math.round(value)
      }
    }

    SettingsFormRow {
      label: "Origin X (mm)"
      hint: root.areaPosHint
      showSeparator: true
      ThemeSlider {
        Layout.preferredWidth: 150
        from: 0
        to: 400
        stepSize: 1
        value: Math.max(0, Math.min(400, Math.round(Number(Config.tabletActiveAreaPosX) || 0)))
        onMoved: Config.tabletActiveAreaPosX = Math.round(value)
      }
    }

    SettingsFormRow {
      label: "Origin Y (mm)"
      hint: "Offset of the active rectangle"
      showSeparator: false
      ThemeSlider {
        Layout.preferredWidth: 150
        from: 0
        to: 400
        stepSize: 1
        value: Math.max(0, Math.min(400, Math.round(Number(Config.tabletActiveAreaPosY) || 0)))
        onMoved: Config.tabletActiveAreaPosY = Math.round(value)
      }
    }
  }

  SettingsGroup {
    title: "Pressure range"

    SettingsFormRow {
      label: "Min"
      hint: root.pressureHint
      showSeparator: true
      ThemeSlider {
        Layout.preferredWidth: 150
        from: -1
        to: 1
        stepSize: 0.05
        value: {
          const v = Number(Config.tabletPressureMin)
          return isFinite(v) ? Math.max(-1, Math.min(1, v)) : -1
        }
        onMoved: Config.tabletPressureMin = Math.round(value * 100) / 100
      }
    }

    SettingsFormRow {
      label: "Max"
      hint: "−1 = driver default (libinput) · not a bezier curve"
      showSeparator: false
      ThemeSlider {
        Layout.preferredWidth: 150
        from: -1
        to: 1
        stepSize: 0.05
        value: {
          const v = Number(Config.tabletPressureMax)
          return isFinite(v) ? Math.max(-1, Math.min(1, v)) : -1
        }
        onMoved: Config.tabletPressureMax = Math.round(value * 100) / 100
      }
    }
  }

  SettingsGroup {
    title: "Eraser tool"

    SettingsFormRow {
      label: "Eraser as button"
      hint: Config.tabletEraserButtonMode === 1
          ? "Eraser end sends a button event"
          : "Hardware default (tool-type switch)"
      showSeparator: true
      ThemeSwitch {
        checked: Config.tabletEraserButtonMode === 1
        onToggled: Config.tabletEraserButtonMode = checked ? 1 : 0
      }
    }

    SettingsFormRow {
      label: "Button override"
      hint: Config.tabletEraserButtonMode === 1
          ? root.eraserButtonHint
          : "Only when Eraser as button is on · 0 = default"
      showSeparator: false
      SettingsCombo {
        preferredWidth: 180
        enabled: Config.tabletEraserButtonMode === 1
        model: root.eraserButtonChoices
        currentValue: String(Math.round(Number(Config.tabletEraserButtonOverride) || 0))
        onActivated: v => {
          Config.tabletEraserButtonOverride = Math.round(Number(v) || 0)
        }
      }
    }
  }

  SettingsGroup {
    title: "Monitor region"

    SettingsFormRow {
      label: "Width (px)"
      hint: root.regionSizeHint
      showSeparator: true
      ThemeSlider {
        Layout.preferredWidth: 150
        from: 0
        to: 3840
        stepSize: 10
        value: Math.max(0, Math.min(3840, Math.round(Number(Config.tabletRegionSizeX) || 0)))
        onMoved: Config.tabletRegionSizeX = Math.round(value)
      }
    }

    SettingsFormRow {
      label: "Height (px)"
      hint: "0×0 size = full bound display / unset"
      showSeparator: true
      ThemeSlider {
        Layout.preferredWidth: 150
        from: 0
        to: 3840
        stepSize: 10
        value: Math.max(0, Math.min(3840, Math.round(Number(Config.tabletRegionSizeY) || 0)))
        onMoved: Config.tabletRegionSizeY = Math.round(value)
      }
    }

    SettingsFormRow {
      label: "Origin X (px)"
      hint: root.regionPosHint
      showSeparator: true
      ThemeSlider {
        Layout.preferredWidth: 150
        from: 0
        to: 3840
        stepSize: 10
        value: Math.max(0, Math.min(3840, Math.round(Number(Config.tabletRegionPosX) || 0)))
        onMoved: Config.tabletRegionPosX = Math.round(value)
      }
    }

    SettingsFormRow {
      label: "Origin Y (px)"
      hint: "Offset in monitor layout"
      showSeparator: true
      ThemeSlider {
        Layout.preferredWidth: 150
        from: 0
        to: 3840
        stepSize: 10
        value: Math.max(0, Math.min(3840, Math.round(Number(Config.tabletRegionPosY) || 0)))
        onMoved: Config.tabletRegionPosY = Math.round(value)
      }
    }

    SettingsFormRow {
      label: "Absolute position"
      hint: Config.tabletRegionAbsolute
          ? "Layout-absolute (only when display unbound)"
          : "Off — relative to bound display"
      showSeparator: false
      ThemeSwitch {
        checked: Config.tabletRegionAbsolute
        onToggled: Config.tabletRegionAbsolute = checked
      }
    }
  }

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 480
    text: "Fact: settings.json + hyprctl input:tablet:* / input:tablettool:* → proteus-general.conf. Pressure range is global linear remap; eraser-as-button is the tool-mode knob Hyprland exposes. Bezier per-tool curves · gesture maps stay Out."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }
}
