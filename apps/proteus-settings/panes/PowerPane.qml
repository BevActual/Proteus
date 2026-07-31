import Quickshell
import QtQuick
import QtQuick.Layouts
import "../shared"
import "../kit"

// Power: profiles (PPD), battery (UPower), logind idle / lid.
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: Theme.spaceMd

  property bool active: false

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

    Item {
      visible: Power.profilesAvailable
      Layout.fillWidth: true
      Layout.preferredHeight: 48
      Layout.leftMargin: Theme.spaceSm
      Layout.rightMargin: Theme.spaceSm
      Layout.topMargin: Theme.spaceSm
      Layout.bottomMargin: Theme.spaceSm

      SettingsSegmented {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        enabled: !Power.profileBusy && Power.profileOptions.length > 0
        options: Power.profileOptions
        selected: Power.activeProfile
        onActivated: id => Power.setProfile(id)
      }
    }

    SettingsFormRow {
      visible: Power.profilesAvailable
      label: "Current"
      hint: Power.profileBusy ? "Applying…" : Power.activeProfileLabel
      showSeparator: false
    }

    Text {
      Layout.fillWidth: true
      Layout.maximumWidth: 480
      Layout.leftMargin: Theme.spaceSm
      Layout.rightMargin: Theme.spaceSm
      Layout.bottomMargin: Theme.spaceSm
      visible: Power.profilesAvailable
          && Power.availableProfiles.indexOf("performance") < 0
      text: "Performance isn’t offered on this hardware (driver reports Balanced and Eco only)."
      color: Theme.textMute
      font.family: Theme.fontFamily
      font.pixelSize: 11
      wrapMode: Text.WordWrap
    }
  }

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 480
    visible: Power.profileError.length > 0 && Power.profilesAvailable
    text: Power.profileError
    color: Theme.danger
    font.family: Theme.fontFamily
    font.pixelSize: 12
    wrapMode: Text.WordWrap
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
    title: "Idle & lid"

    SettingsFormRow {
      label: "Idle action"
      hint: Power.busy ? "Applying…"
          : root.policyHint(Power.actionLabel(Power.idleAction), Power.idleActionDefaulted)
      showSeparator: true
      SettingsCombo {
        preferredWidth: 200
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
        preferredWidth: 200
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
        preferredWidth: 200
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
        font.pixelSize: 12
      }
    }

    SettingsFormRow {
      visible: Power.helperMissing
      label: "Install proteus-logind…"
      hint: "Needs sudo once — polkit helper for idle/lid writes"
      showSeparator: true
      interactive: true
      onActivated: Power.openInstallHelper()
      Text {
        text: "Install"
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: 12
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

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 480
    visible: Power.logindError.length > 0
    text: Power.logindError
    color: Theme.danger
    font.family: Theme.fontFamily
    font.pixelSize: 12
    wrapMode: Text.WordWrap
  }

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 480
    text: "Fact: powerprofilesctl (PPD) · UPower · pkexec proteus-logind → "
        + "/etc/systemd/logind.conf.d/99-proteus.conf (reloads systemd-logind)."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }
}
