import Quickshell
import QtQuick
import QtQuick.Layouts
import "../shared"
import "../kit"

// Power: profiles (PPD), battery (UPower), charge limits, logind idle / lid.
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: Theme.spaceMd

  property bool active: false
  property int chargeDraftStart: -1
  property int chargeDraftEnd: -1

  Timer {
    id: chargeApplyTimer
    interval: 450
    repeat: false
    onTriggered: {
      const s = root.chargeDraftStart >= 0
          ? root.chargeDraftStart
          : (Power.chargeStart > 0 ? Power.chargeStart : 40)
      const e = root.chargeDraftEnd >= 0
          ? root.chargeDraftEnd
          : (Power.chargeEnd > 0 ? Power.chargeEnd : 80)
      Power.setChargeThresholds(s, e)
    }
  }

  readonly property var actionOpts: [
    { id: "ignore", label: "Do nothing" },
    { id: "lock", label: "Lock" },
    { id: "suspend", label: "Sleep" },
    { id: "hibernate", label: "Hibernate" },
    { id: "hybrid-sleep", label: "Hybrid sleep" },
    { id: "suspend-then-hibernate", label: "Sleep then hibernate" },
    { id: "poweroff", label: "Shut down" }
  ]

  readonly property var idleSecOpts: {
    const opts = [{ id: "", label: "Default" }]
    for (let i = 0; i < Power.idleSecPresets.length; i++)
      opts.push(Power.idleSecPresets[i])
    const cur = Power.idleActionSec
    if (cur.length) {
      let found = false
      for (let j = 0; j < opts.length; j++) {
        if (opts[j].id === cur) {
          found = true
          break
        }
      }
      if (!found)
        opts.push({ id: cur, label: cur })
    }
    return opts
  }

  function policyHint(value, defaulted) {
    if (!value.length)
      return "Not set"
    return defaulted ? (value + " (default)") : value
  }

  onActiveChanged: {
    if (active) {
      Power.refreshLogind()
      Power.refreshProfiles()
    }
  }

  Component.onCompleted: {
    if (active) {
      Power.refreshLogind()
      Power.refreshProfiles()
    }
  }

  SettingsGroup {
    title: "Power mode"

    SettingsFormRow {
      visible: !Power.profilesAvailable
      label: "Unavailable"
      hint: Power.profileError.length
          ? Power.profileError
          : "Needs power-profiles-daemon (Performance / Balanced / Eco)"
      showSeparator: false
    }

    // Full-width segmented — same horizontal inset as SettingsFormRow (spaceMd).
    Item {
      id: modeBlock
      visible: Power.profilesAvailable
      Layout.fillWidth: true
      Layout.preferredHeight: modeCol.implicitHeight + Theme.spaceSm * 2

      ColumnLayout {
        id: modeCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Theme.spaceMd
        anchors.rightMargin: Theme.spaceMd
        spacing: Theme.spaceSm

        Text {
          Layout.fillWidth: true
          text: "Mode"
          color: Theme.text
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSize
        }

        SettingsSegmented {
          Layout.fillWidth: true
          enabled: !Power.profileBusy && Power.profileOptions.length > 0
          options: Power.profileOptions
          selected: Power.activeProfile
          onActivated: id => Power.setProfile(id)
        }

        Text {
          Layout.fillWidth: true
          text: Power.profileBusy ? "Applying…" : ("Using " + Power.activeProfileLabel)
          color: Theme.textMute
          font.family: Theme.fontFamily
          font.pixelSize: 11
          elide: Text.ElideRight
        }
      }

      Rectangle {
        anchors.left: parent.left
        anchors.leftMargin: Theme.spaceMd
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: Theme.separator
        visible: perfNoteRow.visible || Power.profileError.length > 0
      }
    }

    SettingsFormRow {
      id: perfNoteRow
      visible: Power.profilesAvailable
          && Power.availableProfiles.indexOf("performance") < 0
      label: "Hardware"
      hint: "Performance isn’t offered — driver reports Balanced and Eco only"
      showSeparator: Power.profileError.length > 0
    }

    SettingsFormRow {
      visible: Power.profilesAvailable && Power.profileError.length > 0
      label: "Error"
      hint: Power.profileError
      labelColor: Theme.danger
      showSeparator: false
    }
  }

  SettingsGroup {
    title: "Battery"

    SettingsFormRow {
      visible: !Power.hasBattery
      label: "No battery detected"
      hint: Power.onBattery ? "Running on battery per UPower" : "Desktop or virtual machine — on AC power"
      showSeparator: false
    }

    SettingsFormRow {
      visible: Power.hasBattery
      label: "Charge"
      hint: Power.stateLabel
      showSeparator: true
      Text {
        text: Power.percent >= 0 ? (Power.percent + "%") : "—"
        color: Power.percent >= 0 && Power.percent <= 15 && Power.onBattery
            ? Theme.danger : Theme.textDim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }
    }

    SettingsFormRow {
      visible: Power.hasBattery && Power.timeRemaining.length > 0
      label: "Estimate"
      hint: Power.timeRemaining
      showSeparator: true
    }

    SettingsFormRow {
      visible: Power.hasBattery && Power.health >= 0
      label: "Health"
      hint: "Capacity relative to when new"
      showSeparator: true
      Text {
        text: Power.health + "%"
        color: Power.health < 70 ? Theme.danger : Theme.textDim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }
    }

    SettingsFormRow {
      visible: Power.hasBattery
      label: "Power source"
      hint: Power.onBattery ? "Battery" : "AC adapter"
      showSeparator: false
    }
  }

  SettingsGroup {
    title: "Charge limits"
    visible: {
      const _r = Power.chargeRev
      return Power.chargeThresholdsAvailable
    }

    SettingsFormRow {
      visible: Power.chargeHasStart
      label: "Start charging below"
      hint: {
        const _r = Power.chargeRev
        if (Power.chargeBusy)
          return "Applying…"
        return Power.chargeStart >= 0
            ? (Power.chargeStart + "% · sysfs " + (Power.chargeSupply || "BAT"))
            : "sysfs charge_control_start_threshold"
      }
      showSeparator: true
      ThemeSlider {
        Layout.preferredWidth: 150
        from: 1
        to: 99
        stepSize: 1
        value: root.chargeDraftStart >= 0
            ? root.chargeDraftStart
            : (Power.chargeStart > 0 ? Power.chargeStart : 40)
        enabled: !Power.chargeBusy
        onMoved: {
          let s = Math.round(value)
          let e = root.chargeDraftEnd >= 0
              ? root.chargeDraftEnd
              : (Power.chargeEnd > 0 ? Power.chargeEnd : 80)
          if (Power.chargeHasEnd && s >= e)
            e = Math.min(100, s + 1)
          root.chargeDraftStart = s
          root.chargeDraftEnd = e
          chargeApplyTimer.restart()
        }
      }
    }

    SettingsFormRow {
      visible: Power.chargeHasEnd
      label: "Stop charging at"
      hint: {
        const _r = Power.chargeRev
        if (Power.chargeBusy)
          return "Applying…"
        return Power.chargeEnd >= 0
            ? (Power.chargeEnd + "% · prolongs battery life")
            : "sysfs charge_control_end_threshold"
      }
      showSeparator: true
      ThemeSlider {
        Layout.preferredWidth: 150
        from: 50
        to: 100
        stepSize: 1
        value: root.chargeDraftEnd >= 0
            ? root.chargeDraftEnd
            : (Power.chargeEnd > 0 ? Power.chargeEnd : 80)
        enabled: !Power.chargeBusy
        onMoved: {
          let e = Math.round(value)
          let s = root.chargeDraftStart >= 0
              ? root.chargeDraftStart
              : (Power.chargeStart > 0 ? Power.chargeStart : 40)
          if (Power.chargeHasStart && s >= e)
            s = Math.max(1, e - 1)
          root.chargeDraftStart = s
          root.chargeDraftEnd = e
          chargeApplyTimer.restart()
        }
      }
    }

    SettingsFormRow {
      visible: Power.chargeError.length > 0
      label: "Error"
      hint: Power.chargeError
      labelColor: Theme.danger
      showSeparator: false
    }

    SettingsFormRow {
      visible: Power.chargeError.length === 0
      label: "Refresh"
      hint: "Re-read sysfs thresholds"
      showSeparator: false
      interactive: !Power.chargeBusy
      onActivated: Power.refreshChargeThresholds()
      Text {
        text: "↻"
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: 12
      }
    }
  }

  SettingsGroup {
    title: "Idle & lid"

    SettingsFormRow {
      label: "Idle action"
      hint: Power.busy ? "Applying…"
          : root.policyHint(Power.actionLabel(Power.idleAction), Power.idleActionDefaulted)
      showSeparator: true
      SettingsCombo {
        preferredWidth: 168
        enabled: !Power.busy
        model: root.actionOpts
        currentValue: Power.idleAction
        onActivated: v => {
          if (!v.length || v === Power.idleAction)
            return
          Power.setLogindPolicy(["IdleAction=" + v])
        }
      }
    }

    SettingsFormRow {
      label: "Idle timeout"
      hint: Power.busy ? "Applying…"
          : root.policyHint(Power.idleSecLabel(Power.idleActionSec), Power.idleActionSecDefaulted)
      showSeparator: true
      SettingsCombo {
        preferredWidth: 168
        enabled: !Power.busy
        model: root.idleSecOpts
        currentValue: Power.idleActionSec
        onActivated: v => {
          if (v === Power.idleActionSec)
            return
          if (!v.length) {
            Power.unsetLogindKeys(["IdleActionSec"])
            return
          }
          Power.setLogindPolicy(["IdleActionSec=" + v])
        }
      }
    }

    SettingsFormRow {
      label: "Lid close"
      hint: Power.busy ? "Applying…"
          : root.policyHint(Power.actionLabel(Power.lidSwitch), Power.lidSwitchDefaulted)
      showSeparator: true
      SettingsCombo {
        preferredWidth: 168
        enabled: !Power.busy
        model: root.actionOpts
        currentValue: Power.lidSwitch
        onActivated: v => {
          if (!v.length || v === Power.lidSwitch)
            return
          Power.setLogindPolicy(["HandleLidSwitch=" + v])
        }
      }
    }

    SettingsFormRow {
      label: "Lid close on AC"
      hint: Power.busy ? "Applying…"
          : root.policyHint(Power.actionLabel(Power.lidSwitchExternalPower),
                            Power.lidSwitchExternalPowerDefaulted)
      showSeparator: true
      SettingsCombo {
        preferredWidth: 168
        enabled: !Power.busy
        model: root.actionOpts
        currentValue: Power.lidSwitchExternalPower
        onActivated: v => {
          if (!v.length || v === Power.lidSwitchExternalPower)
            return
          Power.setLogindPolicy(["HandleLidSwitchExternalPower=" + v])
        }
      }
    }

    SettingsFormRow {
      label: "Reset Proteus overrides"
      hint: "Remove 99-proteus.conf drop-in (shipped defaults return)"
      showSeparator: true
      interactive: !Power.busy
      onActivated: Power.clearLogindOverrides()
      Text {
        text: Power.busy ? "…" : "Reset"
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }
    }

    SettingsFormRow {
      visible: Power.helperMissing
      label: "Set up proteus-logind…"
      hint: "Terminal + sudo once · not a Software package"
      showSeparator: true
      interactive: true
      onActivated: Power.openInstallHelper()
      Text {
        text: "Run setup…"
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }
    }

    SettingsFormRow {
      label: "Edit logind.conf…"
      hint: "Base file escape hatch (drop-in still wins when present)"
      showSeparator: false
      interactive: true
      onActivated: Power.openLogindConf()
      Text {
        text: "›"
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }
    }
  }

  SettingsGroup {
    title: "Status"
    visible: Power.logindError.length > 0

    SettingsFormRow {
      label: "Logind"
      hint: Power.logindError
      labelColor: Theme.danger
      showSeparator: false
    }
  }

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 480
    Layout.topMargin: Theme.spaceXs
    text: "Fact: powerprofilesctl (PPD) · UPower · pkexec proteus-logind → "
        + "/etc/systemd/logind.conf.d/99-proteus.conf · Charge limits via "
        + "pkexec proteus-battery-threshold (sysfs charge_control_* when present). TLP Out."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }
}
