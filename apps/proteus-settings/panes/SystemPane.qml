import Quickshell
import QtQuick
import QtQuick.Layouts
import "../shared"
import "../kit"

// About: product identity + hardware probe facts.
// Session actions live under Users (SETTINGS-IA §2).
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: Theme.spaceMd

  signal requestGo(string id)

  readonly property string hardwareSummary: {
    if (Hardware.ready) {
      return Hardware.deviceClass
          + (Hardware.chassis ? " · chassis " + Hardware.chassis : "")
    }
    return Hardware.probing ? "Detecting hardware…" : "Hardware probe not ready"
  }

  SettingsGroup {
    title: "Proteus"

    Item {
      Layout.fillWidth: true
      Layout.preferredHeight: 72

      RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.spaceMd
        anchors.rightMargin: Theme.spaceMd
        spacing: Theme.spaceMd

        Image {
          Layout.preferredWidth: 48
          Layout.preferredHeight: 48
          fillMode: Image.PreserveAspectFit
          smooth: true
          source: {
            const root = Quickshell.env("PROTEUS_ROOT")
            const base = root && root.length ? root : "/mnt/proteus"
            return "file://" + base + "/brand/proteus-mark.svg"
          }
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: 2
          Text {
            text: "Proteus"
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 16
            font.weight: Font.DemiBold
          }
          Text {
            text: "Bevington Systems · adaptive host OS"
            color: Theme.textMute
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
          }
        }
      }
    }

    SettingsFormRow {
      label: "Desktop environment"
      hint: "Hyprland · Quickshell"
      showSeparator: true
    }

    SettingsFormRow {
      label: "Base"
      hint: "Arch Linux guest"
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

    SettingsFormRow {
      label: "Lock, log out, reboot…"
      hint: "Moved to Users"
      showSeparator: false
      interactive: true
      onActivated: root.requestGo("users")
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
    text: "Fact: hw-probe.json from services/proteus-hw-probe · session actions under Users."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }
}
