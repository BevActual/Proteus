import Quickshell
import QtQuick
import QtQuick.Layouts
import "../shared"

// Power: battery state and the effective logind idle / lid policy.
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: Theme.spaceMd

  property bool active: false

  function policyHint(value, defaulted) {
    if (!value.length)
      return "Not set"
    return defaulted ? (value + " (default)") : value
  }

  onActiveChanged: {
    if (active)
      Power.refreshLogind()
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
      hint: root.policyHint(Power.idleAction, Power.idleActionDefaulted)
      showSeparator: true
    }

    SettingsFormRow {
      label: "Idle timeout"
      hint: root.policyHint(Power.idleActionSec, Power.idleActionSecDefaulted)
      showSeparator: true
    }

    SettingsFormRow {
      label: "Lid close"
      hint: root.policyHint(Power.lidSwitch, Power.lidSwitchDefaulted)
      showSeparator: true
    }

    SettingsFormRow {
      visible: Power.lidSwitchExternalPower.length > 0
      label: "Lid close on AC"
      hint: root.policyHint(Power.lidSwitchExternalPower, Power.lidSwitchExternalPowerDefaulted)
      showSeparator: true
    }

    // Read-only until a privileged helper exists — see Power.qml.
    SettingsFormRow {
      label: "Edit logind.conf…"
      hint: "Changing these needs root; Settings does not write them yet"
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
    text: "Fact: UPower display device · /etc/systemd/logind.conf (commented keys are shipped defaults)."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }
}
