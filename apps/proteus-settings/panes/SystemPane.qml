import Quickshell
import QtQuick
import QtQuick.Layouts
import "../shared"
import "../kit"
import ".." // root module — SettingsNav singleton

// About: product identity · machine facts · load strip · Mission Center ·
// hard Session posture + soft Hyprland profile.
// Session power actions live under Users only (SETTINGS-IA §2) — not linked here.
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: Theme.spaceMd

  property bool active: false
  signal requestGo(string id)

  readonly property string hardwareSummary: {
    if (Hardware.ready) {
      return Hardware.deviceClass
          + (Hardware.chassis ? " · chassis " + Hardware.chassis : "")
    }
    return Hardware.probing ? "Detecting hardware…" : "Hardware probe not ready"
  }

  onActiveChanged: {
    SystemLoad.watching = active
    if (active) {
      SessionPosture.refresh()
      HyprProfile.refresh()
      SystemInfo.refresh()
      MissionCenter.refresh()
      SystemLoad.refresh()
    }
  }

  Component.onCompleted: {
    SessionPosture.refresh()
    HyprProfile.refresh()
    SystemInfo.refresh()
    MissionCenter.refresh()
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
            const rootEnv = Quickshell.env("PROTEUS_ROOT")
            const base = rootEnv && rootEnv.length ? rootEnv : "/mnt/proteus"
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
                + (SystemInfo.proteusTip.length ? (" · " + SystemInfo.tipLabel) : "")
            color: Theme.textMute
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
          }
        }
      }
    }

    SettingsFormRow {
      label: "Launch adapt profile"
      hint: AdaptEnv.present
          ? AdaptEnv.hint
          : "No PROTEUS_ADAPT_* here — launch Settings from Dock/Beacon to inject"
      showSeparator: true
    }

    SettingsFormRow {
      label: "Focus pane density"
      hint: FocusMode.active
          ? "Minimal — Settings hides Appearance/Software/…; Desktop → Focus · Privacy · Users · About stay"
          : "Full — all Settings hubs (Focus off)"
      showSeparator: true
    }

    SettingsFormRow {
      label: "Remote input"
      hint: {
        if (Hardware.remoteFromProbe)
          return "Present via probe (CEC / IR / lirc / Bluetooth HID)"
        if (Hardware.has("remote") && Hardware.remoteProbeStub)
          return "Present via PROTEUS_REMOTE_PROBE stub (no CEC/IR/BT HID on this machine)"
        return "Off — plug CEC/IR/BT remote or set PROTEUS_REMOTE_PROBE=1 to dogfood adapts.input remote"
      }
      showSeparator: true
    }

    SettingsFormRow {
      label: "Virtualization"
      hint: "Thin hub — Workloads jump · engines · headless"
      showSeparator: true
      interactive: true
      onActivated: root.requestGo("virtualization")
      Text {
        text: "Virtualization ›"
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }
    }

    SettingsFormRow {
      label: "Desktop environment"
      hint: "Hyprland · Quickshell"
      showSeparator: true
    }

    SettingsFormRow {
      label: "Hyprland"
      hint: SystemInfo.busy && !SystemInfo.hyprVersion.length
          ? "Reading…"
          : SystemInfo.hyprLabel
      showSeparator: true
    }

    SettingsFormRow {
      label: "Quickshell"
      hint: SystemInfo.busy && !SystemInfo.qsVersion.length
          ? "Reading…"
          : SystemInfo.qsLabel
      showSeparator: true
    }

    SettingsFormRow {
      label: "Operating system"
      hint: SystemInfo.busy && !SystemInfo.osPretty.length
          ? "Reading…"
          : SystemInfo.osLabel
      showSeparator: true
    }

    SettingsFormRow {
      label: "Kernel"
      hint: SystemInfo.busy && !SystemInfo.kernelRelease.length
          ? "Reading…"
          : SystemInfo.kernelLabel
      showSeparator: SystemInfo.error.length > 0
    }

    SettingsFormRow {
      visible: SystemInfo.error.length > 0
      label: "Identity"
      hint: SystemInfo.error
      labelColor: Theme.danger
      showSeparator: false
    }
  }

  SettingsGroup {
    title: "This machine"

    SettingsFormRow {
      label: "Hostname"
      hint: SystemInfo.busy && !SystemInfo.hostname.length
          ? "Reading…"
          : SystemInfo.hostnameLabel
      showSeparator: true
    }

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
      label: "Processor"
      hint: SystemLoad.cpuModel.length
          ? SystemLoad.cpuModel
          : (SystemLoad.ready ? "—" : "Sampling…")
      showSeparator: true
    }

    SettingsFormRow {
      visible: Power.hasBattery
      label: "Battery"
      hint: {
        if (Power.percent < 0)
          return Power.stateLabel
        let s = Power.percent + "% · " + Power.stateLabel
        if (Power.timeRemaining.length)
          s += " · " + Power.timeRemaining
        return s
      }
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
      showSeparator: true
      interactive: !Hardware.probing
      onActivated: Hardware.refresh()
      Text {
        text: Hardware.probing ? "…" : "›"
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }
    }

    SettingsFormRow {
      label: "Copy system info"
      hint: SystemInfo.copiedFlash
          ? "Copied"
          : "OS · hostname · versions · load · class"
      showSeparator: false
      interactive: true
      onActivated: SystemInfo.copySummary()
      Text {
        text: SystemInfo.copiedFlash ? "Copied" : "Copy"
        color: SystemInfo.copiedFlash ? Theme.accent : Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }
    }
  }

  SettingsGroup {
    title: "Activity"

    SettingsFormRow {
      label: "Load"
      hint: SystemLoad.ready ? SystemLoad.summaryLabel : "Sampling…"
      showSeparator: true
    }

    SettingsFormRow {
      label: "Memory"
      hint: SystemLoad.ready ? SystemLoad.memoryDetailLabel : "Sampling…"
      showSeparator: true
    }

    SettingsFormRow {
      label: "Storage"
      hint: SystemLoad.ready ? SystemLoad.storageLabel : "Sampling…"
      showSeparator: true
    }

    SettingsFormRow {
      label: "Activity Monitor"
      hint: MissionCenter.hint
      showSeparator: true
      interactive: true
      onActivated: {
        if (MissionCenter.available)
          MissionCenter.open()
        else
          SettingsNav.goInstallSearch("io.missioncenter.MissionCenter", "packages-flatpak")
      }
      Text {
        text: MissionCenter.available ? "Open" : "Install…"
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }
    }

    SettingsFormRow {
      label: "Check for updates…"
      hint: "Software → Updates"
      showSeparator: false
      interactive: true
      onActivated: root.requestGo("packages-updates")
      Text {
        text: "›"
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }
    }
  }

  SettingsGroup {
    title: "Session posture"

    SettingsFormRow {
      label: "Posture"
      hint: SessionPosture.busy
          ? "Switching…"
          : SessionPosture.hardHonesty
      showSeparator: SessionPosture.confirmOpen
          || SessionPosture.statusNote.length > 0
          || SessionPosture.error.length > 0
          || SessionPosture.helperMissing
      SettingsCombo {
        preferredWidth: 168
        enabled: !SessionPosture.busy && !SessionPosture.helperMissing
            && SessionPosture.postureOptions.length > 0
        model: SessionPosture.postureOptions
        currentValue: SessionPosture.confirmOpen
            ? SessionPosture.pendingPosture
            : SessionPosture.activePosture
        onActivated: v => {
          if (!v.length)
            return
          if (v === SessionPosture.activePosture) {
            SessionPosture.cancelPending()
            return
          }
          SessionPosture.requestSwitch(v)
        }
      }
    }

    SettingsFormRow {
      visible: SessionPosture.confirmOpen && !SessionPosture.busy
      label: "Confirm hard switch"
      hint: "Restart chrome as "
          + SessionPosture.postureLabel(SessionPosture.pendingPosture)
          + " — soft profile picker below will not do this"
      showSeparator: true
      RowLayout {
        spacing: Theme.spaceSm
        Text {
          text: "Switch"
          color: Theme.accent
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSize
          font.weight: Font.DemiBold
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: SessionPosture.confirmSwitch()
          }
        }
        Text {
          text: "Cancel"
          color: Theme.textMute
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSize
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: SessionPosture.cancelPending()
          }
        }
      }
    }

    SettingsFormRow {
      visible: SessionPosture.statusNote.length > 0 && !SessionPosture.error.length
      label: "Status"
      hint: SessionPosture.statusNote
      showSeparator: SessionPosture.error.length > 0 || SessionPosture.helperMissing
    }

    SettingsFormRow {
      visible: SessionPosture.error.length > 0
      label: "Error"
      hint: SessionPosture.error
      labelColor: Theme.danger
      showSeparator: SessionPosture.helperMissing
    }

    SettingsFormRow {
      visible: SessionPosture.helperMissing
      label: "Helper missing"
      hint: SessionPosture.helperHint
      showSeparator: false
    }
  }

  SettingsGroup {
    title: "Hyprland profile"

    SettingsFormRow {
      label: "Profile"
      hint: HyprProfile.busy
          ? "Applying…"
          : HyprProfile.softHonesty
      showSeparator: HyprProfile.statusNote.length > 0
          || HyprProfile.error.length > 0
          || HyprProfile.helperMissing
      SettingsCombo {
        preferredWidth: 168
        enabled: !HyprProfile.busy && !HyprProfile.helperMissing
            && HyprProfile.profileOptions.length > 0
        model: HyprProfile.profileOptions
        currentValue: HyprProfile.activeProfile
        onActivated: v => {
          if (!v.length || v === HyprProfile.activeProfile)
            return
          HyprProfile.set(v)
        }
      }
    }

    SettingsFormRow {
      visible: HyprProfile.statusNote.length > 0 && !HyprProfile.error.length
      label: "Status"
      hint: HyprProfile.statusNote
      showSeparator: HyprProfile.error.length > 0 || HyprProfile.helperMissing
    }

    SettingsFormRow {
      visible: HyprProfile.error.length > 0
      label: "Error"
      hint: HyprProfile.error
      labelColor: Theme.danger
      showSeparator: HyprProfile.helperMissing
    }

    SettingsFormRow {
      visible: HyprProfile.helperMissing
      label: "Set up desktop conf…"
      hint: (HyprProfile.helperHint.length ? HyprProfile.helperHint + " · " : "")
          + "Terminal helper · not a Software package"
      showSeparator: false
      interactive: true
      onActivated: HyprProfile.openInstallHelper()
      Text {
        text: "Run setup…"
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }
    }
  }

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 520
    text: "Fact: identity from os-release · hostname · /proc load · hw-probe.json · "
        + "Session posture = hard proteus-posture (chrome restart) · Hyprland profile "
        + "= soft window rules only. Activity Monitor opens Mission Center when "
        + "installed — Settings does not embed a live dashboard."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }
}
