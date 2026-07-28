import Quickshell
import QtQuick
import QtQuick.Layouts
import "../shared"

// About: what this is, what the probe found, and session power actions.
// Session actions live here until a Users category exists (SETTINGS-IA § 2).
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: Theme.spaceMd

  readonly property var sessionActions: [
    {
      label: "Lock",
      action: "lock",
      hint: "Show the lock screen now",
      destructive: false
    },
    {
      label: "Log out",
      action: "logout",
      hint: "End this Hyprland session",
      destructive: false
    },
    {
      label: "Reboot",
      action: "reboot",
      hint: "Restart the machine",
      destructive: true
    },
    {
      label: "Shut down",
      action: "shutdown",
      hint: "Power off the machine",
      destructive: true
    }
  ]

  readonly property string hardwareSummary: {
    if (Hardware.ready) {
      return Hardware.deviceClass
          + (Hardware.chassis ? " · chassis " + Hardware.chassis : "")
    }
    return Hardware.probing ? "Detecting hardware…" : "Hardware probe not ready"
  }

  SettingsGroup {
    title: "Proteus"

    SettingsFormRow {
      label: "Proteus desktop environment"
      hint: "Bevington Systems"
      showSeparator: true
    }

    SettingsFormRow {
      label: "Base"
      hint: "Arch Linux guest · Hyprland · Quickshell"
      showSeparator: false
    }
  }

  SettingsGroup {
    title: "This machine"

    SettingsFormRow {
      label: "Class"
      hint: root.hardwareSummary
      showSeparator: true
    }

    SettingsFormRow {
      label: "Posture hint"
      hint: Hardware.ready ? Hardware.postureHint : "—"
      showSeparator: true
    }

    SettingsFormRow {
      label: "Capabilities"
      hint: Hardware.capabilityList.length
          ? (Hardware.capabilityList.length + " detected")
          : "None detected"
      showSeparator: Hardware.capabilityList.length > 0 || Hardware.error.length > 0
    }

    // Capability chips get their own full-width row rather than a trailing
    // control — there can be many and they wrap.
    Item {
      visible: Hardware.capabilityList.length > 0
      Layout.fillWidth: true
      Layout.preferredHeight: capFlow.implicitHeight + Theme.spaceMd

      Flow {
        id: capFlow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: Theme.spaceMd
        anchors.rightMargin: Theme.spaceMd
        anchors.topMargin: Theme.spaceXs
        spacing: 6

        Repeater {
          model: Hardware.capabilityList

          Rectangle {
            required property var modelData
            height: 24
            width: capLab.implicitWidth + 14
            radius: Theme.radiusSm
            color: Theme.accentSoft
            border.width: 1
            border.color: Theme.accent

            Text {
              id: capLab
              anchors.centerIn: parent
              text: modelData
              color: Theme.text
              font.family: Theme.fontFamily
              font.pixelSize: 11
            }
          }
        }
      }
    }

    SettingsFormRow {
      visible: Hardware.error.length > 0
      label: "Probe error"
      hint: Hardware.error
      labelColor: Theme.danger
      showSeparator: true
    }

    SettingsFormRow {
      label: Hardware.probing ? "Probing…" : "Refresh hardware"
      hint: Hardware.ready ? "Cache: ~/.config/proteus/hw-probe.json" : ""
      showSeparator: false
      interactive: !Hardware.probing
      onActivated: Hardware.refresh()
      Text {
        text: Hardware.probing ? "…" : "›"
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }
    }
  }

  SettingsGroup {
    title: "Session"

    Repeater {
      model: root.sessionActions

      SettingsFormRow {
        required property var modelData
        required property int index
        label: modelData.label
        hint: modelData.hint
        showSeparator: index < root.sessionActions.length - 1
        interactive: true
        labelColor: modelData.destructive ? Theme.danger : Theme.text
        onActivated: Config.session(modelData.action)
        Text {
          text: "›"
          color: Theme.textMute
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSize
        }
      }
    }
  }

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 480
    text: "Fact: hw-probe.json from services/proteus-hw-probe · hyprctl / systemctl / loginctl for session."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }
}
