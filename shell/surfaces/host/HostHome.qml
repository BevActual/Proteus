import Quickshell
import QtQuick
import QtQuick.Layouts
import "../../shared"

// Host ops home — HexOS-style dashboard: live resource cards (processor ·
// memory · storage · network · health · workloads · apps · shares) over the
// same Settings spine. Cards are read-only glances; every mutation deep-links
// into the Workloads app (Workloads · Apps · Shares tabs).
Item {
  id: root
  anchors.fill: parent

  property bool active: visible && !ShellState.sessionLocked && !ShellState.sessionStartLockPending

  readonly property color warnColor: "#ffb340"
  readonly property color okColor: "#32d74b"

  // Rolling samples for the sparklines (CPU every 3s · net on metrics rev).
  property var cpuSamples: []
  property var netSamples: []

  onActiveChanged: {
    if (active) {
      SystemInfo.refresh()
      SystemLoad.retain()
      SystemLoad.refresh()
      Workloads.retain()
      Workloads.refresh()
      HostMetrics.retain()
      HostMetrics.refresh()
    } else {
      SystemLoad.release()
      Workloads.release()
      HostMetrics.release()
    }
  }

  Component.onCompleted: {
    if (root.active) {
      SystemInfo.refresh()
      SystemLoad.retain()
      SystemLoad.refresh()
      Workloads.retain()
      Workloads.refresh()
      HostMetrics.retain()
      HostMetrics.refresh()
    }
  }

  Component.onDestruction: {
    SystemLoad.release()
    Workloads.release()
    HostMetrics.release()
  }

  function runPosture(args) {
    const proot = String(Quickshell.env("PROTEUS_ROOT") || "/mnt/proteus")
    const extra = String(args || "").trim()
    // args are fixed product tokens (desktop | host --headless) — not user input.
    Quickshell.execDetached({
      command: [
        "bash", "-lc",
        "P=" + proot + "/vm/guest/proteus-posture; "
            + "if [[ -x \"$P\" ]]; then setsid \"$P\" " + extra + " >/dev/null 2>&1 & "
            + "elif command -v proteus-posture >/dev/null 2>&1; then "
            + "setsid proteus-posture " + extra + " >/dev/null 2>&1 & fi"
      ]
    })
  }

  function runHostSeat(cmd) {
    const proot = String(Quickshell.env("PROTEUS_ROOT") || "/mnt/proteus")
    const c = String(cmd || "").trim()
    Quickshell.execDetached({
      command: [
        "bash", "-lc",
        "S=" + proot + "/vm/guest/proteus-host-seat; "
            + "if [[ -x \"$S\" ]]; then setsid \"$S\" " + c + " >/dev/null 2>&1 & "
            + "elif command -v proteus-host-seat >/dev/null 2>&1; then "
            + "setsid proteus-host-seat " + c + " >/dev/null 2>&1 & fi"
      ]
    })
  }

  function openTerminal() {
    Quickshell.execDetached({
      command: [
        "bash", "-lc",
        "if command -v proteus-terminal >/dev/null 2>&1; then setsid proteus-terminal >/dev/null 2>&1 & "
            + "elif command -v ghostty >/dev/null 2>&1; then setsid ghostty >/dev/null 2>&1 & "
            + "elif command -v kitty >/dev/null 2>&1; then setsid kitty >/dev/null 2>&1 & "
            + "elif command -v foot >/dev/null 2>&1; then setsid foot >/dev/null 2>&1 & "
            + "elif command -v alacritty >/dev/null 2>&1; then setsid alacritty >/dev/null 2>&1 & "
            + "fi"
      ]
    })
  }

  function openWorkloads(tab) {
    ShellState.openWorkloadsApp(tab)
  }

  // Deployed one-click apps = containers named proteus-app-* (catalog deploys).
  readonly property var deployedApps: {
    const out = []
    const list = Workloads.containers || []
    for (let i = 0; i < list.length; i++) {
      const name = String(list[i] && list[i].name || "")
      if (name.indexOf("proteus-app-") === 0)
        out.push(list[i])
    }
    return out
  }

  function pushSample(arr, value, cap) {
    const copy = (arr || []).slice()
    copy.push(Math.max(0, Number(value) || 0))
    while (copy.length > cap)
      copy.shift()
    return copy
  }

  Timer {
    interval: 3000
    running: root.active
    repeat: true
    onTriggered: root.cpuSamples = root.pushSample(root.cpuSamples, SystemLoad.cpuPercent, 40)
  }

  Connections {
    target: HostMetrics
    function onRevChanged() {
      const p = HostMetrics.primaryInterface
      root.netSamples = root.pushSample(
          root.netSamples, p ? (Number(p.rxBps) || 0) + (Number(p.txBps) || 0) : 0, 40)
    }
  }

  Timer {
    interval: 5000
    running: root.active
    repeat: true
    onTriggered: SystemLoad.refresh()
  }

  // ------------------------------------------------------------- components

  component Card: Rectangle {
    id: cardRoot
    property string title: ""
    property string meta: ""
    property bool clickable: true
    signal activated()
    default property alias content: cardContent.data

    Layout.fillWidth: true
    Layout.preferredHeight: 172
    radius: Theme.radiusMd
    color: cardMa.containsMouse && cardRoot.clickable ? Theme.bgHover : Theme.elevatedFill
    border.width: 1
    border.color: Theme.chromeBorder

    MouseArea {
      id: cardMa
      anchors.fill: parent
      hoverEnabled: true
      enabled: cardRoot.clickable
      cursorShape: cardRoot.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: cardRoot.activated()
    }

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Theme.spaceMd
      spacing: 6

      RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spaceSm

        Text {
          text: cardRoot.title
          color: Theme.textDim
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSizeSm
          font.weight: Font.DemiBold
        }

        Item { Layout.fillWidth: true }

        Text {
          text: cardRoot.meta
          color: Theme.textMute
          font.family: Theme.fontFamily
          font.pixelSize: 11
          elide: Text.ElideRight
          Layout.maximumWidth: cardRoot.width * 0.55
        }
      }

      ColumnLayout {
        id: cardContent
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 4
      }
    }
  }

  component UsageBar: Item {
    property real pct: 0
    property color fill: Theme.accent
    Layout.fillWidth: true
    implicitHeight: 5

    Rectangle {
      anchors.fill: parent
      radius: 2.5
      color: Theme.chromeBorder
    }

    Rectangle {
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      radius: 2.5
      width: Math.max(3, parent.width * Math.min(1, Math.max(0, pct) / 100))
      color: parent.fill
    }
  }

  component Spark: Canvas {
    id: spark
    property var samples: []
    property color line: Theme.accent
    Layout.fillWidth: true
    implicitHeight: 26
    opacity: 0.9

    onSamplesChanged: requestPaint()
    onWidthChanged: requestPaint()

    onPaint: {
      const ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)
      const s = spark.samples || []
      if (s.length < 2)
        return
      let max = 1
      for (let i = 0; i < s.length; i++)
        max = Math.max(max, s[i])
      ctx.strokeStyle = String(spark.line)
      ctx.lineWidth = 1.5
      ctx.beginPath()
      for (let i = 0; i < s.length; i++) {
        const x = (i / (s.length - 1)) * (width - 2) + 1
        const y = height - 2 - (s[i] / max) * (height - 4)
        if (i === 0)
          ctx.moveTo(x, y)
        else
          ctx.lineTo(x, y)
      }
      ctx.stroke()
    }
  }

  component QuickButton: Rectangle {
    property string label: ""
    signal activated()
    implicitWidth: qbText.implicitWidth + 24
    implicitHeight: 28
    radius: 14
    color: qbMa.containsMouse ? Theme.bgHover : Theme.elevatedFill
    border.width: 1
    border.color: Theme.chromeBorder

    Text {
      id: qbText
      anchors.centerIn: parent
      text: parent.label
      color: Theme.text
      font.family: Theme.fontFamily
      font.pixelSize: 12
    }

    MouseArea {
      id: qbMa
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: parent.activated()
    }
  }

  // ------------------------------------------------------------- layout

  Flickable {
    anchors.fill: parent
    contentWidth: width
    contentHeight: body.implicitHeight + 56
    clip: true

    ColumnLayout {
      id: body
      x: Math.round((root.width - width) / 2)
      y: 28
      width: Math.min(1180, root.width - 48)
      spacing: Theme.spaceMd

      // Header: identity + quick ops strip
      RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spaceMd

        ColumnLayout {
          spacing: 2

          Text {
            text: SystemInfo.hostnameLabel
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 26
            font.weight: Font.DemiBold
          }

          Text {
            text: (SystemInfo.osLabel !== "—" ? SystemInfo.osLabel : "Proteus host")
                + " · up " + (SystemLoad.uptimeLabel || "—")
                + (HostMetrics.ready ? " · " + HostMetrics.summaryLabel : "")
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
            elide: Text.ElideRight
            Layout.fillWidth: true
          }
        }

        Item { Layout.fillWidth: true }

        RowLayout {
          spacing: Theme.spaceSm

          QuickButton {
            label: "Terminal"
            onActivated: root.openTerminal()
          }

          QuickButton {
            label: "Headless"
            onActivated: root.runHostSeat("detach")
          }

          QuickButton {
            label: "Host Settings"
            onActivated: ShellState.openSettingsSmart("virtualization")
          }

          QuickButton {
            label: "Desktop"
            onActivated: root.runPosture("desktop")
          }
        }
      }

      GridLayout {
        id: cardGrid
        Layout.fillWidth: true
        columns: Math.max(2, Math.min(4, Math.floor(width / 280)))
        columnSpacing: Theme.spaceSm
        rowSpacing: Theme.spaceSm

        // Processor
        Card {
          title: "Processor"
          meta: SystemLoad.cpuModel
          clickable: false

          Text {
            text: SystemLoad.ready ? Math.round(SystemLoad.cpuPercent) + "%" : "—"
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 26
            font.weight: Font.DemiBold
          }

          UsageBar { pct: SystemLoad.cpuPercent }
          Spark { samples: root.cpuSamples }
          Item { Layout.fillHeight: true }
        }

        // Memory
        Card {
          title: "Memory"
          meta: SystemLoad.swapTotalGiB > 0
              ? ("swap " + SystemLoad.swapUsedGiB.toFixed(1) + " / " + SystemLoad.swapTotalGiB.toFixed(1) + " GiB")
              : "no swap"
          clickable: false

          Text {
            text: SystemLoad.ready
                ? SystemLoad.memUsedGiB.toFixed(1) + " / " + SystemLoad.memTotalGiB.toFixed(1) + " GiB"
                : "—"
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 26
            font.weight: Font.DemiBold
          }

          UsageBar {
            pct: SystemLoad.memTotalGiB > 0 ? SystemLoad.memUsedGiB * 100 / SystemLoad.memTotalGiB : 0
          }
          Item { Layout.fillHeight: true }
        }

        // Storage
        Card {
          title: "Storage"
          meta: {
            const n = (HostMetrics.drives || []).length
            const pools = HostMetrics.pools || []
            let m = n + " drive" + (n === 1 ? "" : "s")
            if (pools.length) {
              const bad = pools.filter(p => String(p.health || "").toUpperCase() !== "ONLINE")
              m += " · " + pools.length + " pool" + (pools.length === 1 ? "" : "s")
                  + (bad.length ? " " + bad[0].health : " ONLINE")
            } else if (!HostMetrics.smartAvailable) {
              m += " · SMART —"
            }
            return m
          }
          onActivated: ShellState.openSettingsSmart("system")

          Repeater {
            model: (HostMetrics.mounts || []).slice(0, 3)

            ColumnLayout {
              required property var modelData
              Layout.fillWidth: true
              spacing: 2

              RowLayout {
                Layout.fillWidth: true

                Text {
                  text: modelData.target
                  color: Theme.textDim
                  font.family: Theme.fontFamily
                  font.pixelSize: 11
                  elide: Text.ElideMiddle
                  Layout.fillWidth: true
                }

                Text {
                  text: modelData.usedGiB + " / " + modelData.totalGiB + " GiB"
                  color: Theme.textMute
                  font.family: Theme.fontFamily
                  font.pixelSize: 11
                }
              }

              UsageBar {
                pct: modelData.usedPct
                fill: modelData.usedPct >= 95 ? Theme.danger
                    : modelData.usedPct >= 90 ? root.warnColor : Theme.accent
              }
            }
          }

          Text {
            visible: !(HostMetrics.mounts || []).length
            text: HostMetrics.ready ? (HostMetrics.hint || "No mounts found") : "Reading storage…"
            color: Theme.textMute
            font.family: Theme.fontFamily
            font.pixelSize: 11
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
          }

          Item { Layout.fillHeight: true }
        }

        // Network
        Card {
          title: "Network"
          meta: {
            const list = HostMetrics.netInterfaces || []
            const up = list.filter(i => i.up).length
            return list.length ? (up + " of " + list.length + " up") : ""
          }
          onActivated: ShellState.openSettingsSmart("network")

          Text {
            readonly property var p: HostMetrics.primaryInterface
            text: p ? p.name + "  ↓ " + HostMetrics.rateLabel(p.rxBps) + "  ↑ " + HostMetrics.rateLabel(p.txBps)
                    : (HostMetrics.ready ? "No interfaces" : "—")
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 15
            font.weight: Font.Medium
            elide: Text.ElideRight
            Layout.fillWidth: true
          }

          Spark { samples: root.netSamples }
          Item { Layout.fillHeight: true }
        }

        // Health
        Card {
          title: "Health"
          meta: HostMetrics.failedUnits > 0 ? HostMetrics.failedUnits + " failed units" : ""
          clickable: false

          RowLayout {
            spacing: 6
            visible: HostMetrics.ready && HostMetrics.alertCount === 0

            Rectangle { width: 8; height: 8; radius: 4; color: root.okColor }

            Text {
              text: "All good"
              color: Theme.text
              font.family: Theme.fontFamily
              font.pixelSize: 15
              font.weight: Font.Medium
            }
          }

          Repeater {
            model: (HostMetrics.alerts || []).slice(0, 3)

            RowLayout {
              required property var modelData
              Layout.fillWidth: true
              spacing: 6

              Rectangle {
                width: 8
                height: 8
                radius: 4
                color: modelData.severity === "crit" ? Theme.danger : root.warnColor
              }

              Text {
                text: modelData.message
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: 12
                elide: Text.ElideRight
                Layout.fillWidth: true
              }
            }
          }

          Text {
            visible: !HostMetrics.ready
            text: "Reading health…"
            color: Theme.textMute
            font.family: Theme.fontFamily
            font.pixelSize: 11
          }

          Item { Layout.fillHeight: true }
        }

        // Workloads
        Card {
          title: "Workloads"
          meta: Workloads.summaryLabel
          onActivated: root.openWorkloads("workloads")

          Repeater {
            model: (Workloads.domains || []).slice(0, 2)

            RowLayout {
              required property var modelData
              Layout.fillWidth: true
              spacing: 6

              Rectangle {
                width: 8
                height: 8
                radius: 4
                color: Workloads.isVmRunning(modelData) ? root.okColor : Theme.textMute
              }

              Text {
                text: "VM · " + String(modelData.name || "—") + " · " + String(modelData.state || "")
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: 12
                elide: Text.ElideRight
                Layout.fillWidth: true
              }
            }
          }

          Repeater {
            model: (Workloads.containers || []).slice(0, 2)

            RowLayout {
              required property var modelData
              Layout.fillWidth: true
              spacing: 6

              Rectangle {
                width: 8
                height: 8
                radius: 4
                color: Workloads.isContainerRunning(modelData) ? root.okColor : Theme.textMute
              }

              Text {
                text: (Workloads.containerEngine || "ctr") + " · " + String(modelData.name || "—")
                    + (modelData.status ? " · " + String(modelData.status) : "")
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: 12
                elide: Text.ElideRight
                Layout.fillWidth: true
              }
            }
          }

          Text {
            visible: !(Workloads.domains || []).length && !(Workloads.containers || []).length
            text: Workloads.hint.length ? Workloads.hint : "No VMs or containers"
            color: Theme.textMute
            font.family: Theme.fontFamily
            font.pixelSize: 11
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
          }

          Item { Layout.fillHeight: true }

          Text {
            text: "Workloads ›"
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: 11
            font.weight: Font.DemiBold
          }
        }

        // Apps (one-click services)
        Card {
          title: "Apps"
          meta: root.deployedApps.length
              ? root.deployedApps.length + " deployed"
              : (Workloads.containersAvailable ? "" : "engine missing")
          onActivated: root.openWorkloads("apps")

          Repeater {
            model: root.deployedApps.slice(0, 3)

            RowLayout {
              required property var modelData
              Layout.fillWidth: true
              spacing: 6

              Rectangle {
                width: 8
                height: 8
                radius: 4
                color: Workloads.isContainerRunning(modelData) ? root.okColor : Theme.textMute
              }

              Text {
                text: String(modelData.name || "").replace("proteus-app-", "")
                    + (modelData.status ? " · " + String(modelData.status) : "")
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: 12
                elide: Text.ElideRight
                Layout.fillWidth: true
              }
            }
          }

          Text {
            visible: !root.deployedApps.length
            text: Workloads.containersAvailable
                ? "One-click services — Jellyfin, Nextcloud, Syncthing…"
                : "Install podman|docker for one-click apps"
            color: Theme.textMute
            font.family: Theme.fontFamily
            font.pixelSize: 11
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
          }

          Item { Layout.fillHeight: true }

          Text {
            text: "Deploy ›"
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: 11
            font.weight: Font.DemiBold
          }
        }

        // Shares
        Card {
          title: "Shares"
          meta: HostMetrics.sharesAvailable
              ? (HostMetrics.smbActive ? "smb active" : "smb stopped")
              : "samba missing"
          onActivated: {
            if (HostMetrics.sharesAvailable)
              root.openWorkloads("shares")
            else
              ShellState.openSettingsSmart("packages-updates")
          }

          Repeater {
            model: (HostMetrics.shares || []).slice(0, 3)

            RowLayout {
              required property var modelData
              Layout.fillWidth: true
              spacing: 6

              Rectangle {
                width: 8
                height: 8
                radius: 4
                color: HostMetrics.smbActive ? root.okColor : Theme.textMute
              }

              Text {
                text: String(modelData.name || "—") + " · " + String(modelData.path || "")
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: 12
                elide: Text.ElideMiddle
                Layout.fillWidth: true
              }
            }
          }

          Text {
            visible: !(HostMetrics.shares || []).length
            text: HostMetrics.sharesAvailable
                ? "No shared folders yet"
                : "Install samba — Software ›"
            color: Theme.textMute
            font.family: Theme.fontFamily
            font.pixelSize: 11
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
          }

          Item { Layout.fillHeight: true }

          Text {
            text: HostMetrics.sharesAvailable ? "Shares ›" : "Software ›"
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: 11
            font.weight: Font.DemiBold
          }
        }
      }

      // Settings spine links
      Flow {
        Layout.fillWidth: true
        spacing: Theme.spaceMd

        Repeater {
          model: [
            { label: "Software", page: "packages-updates" },
            { label: "Network", page: "network" },
            { label: "About", page: "system" },
            { label: "Privacy", page: "privacy" },
            { label: "Mission Center", page: "" },
            { label: "Full Settings", page: "full" }
          ]

          Text {
            required property var modelData
            text: modelData.label + " ›"
            color: linkMa.containsMouse ? Theme.accent : Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: 12

            MouseArea {
              id: linkMa
              anchors.fill: parent
              anchors.margins: -4
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                const page = String(parent.modelData.page || "")
                if (parent.modelData.label === "Mission Center") {
                  if (MissionCenter.available)
                    MissionCenter.open()
                  else
                    MissionCenter.openSoftware()
                } else if (page === "full") {
                  // Desktop Settings face — escape, not host home.
                  ShellState.openSettings()
                } else if (page.length) {
                  ShellState.openSettingsSmart(page)
                }
              }
            }
          }
        }
      }

      Text {
        Layout.fillWidth: true
        text: "Fact: dashboard cards are read-only glances (storage/SMART/pools · network · health · shares via proteus-host-metrics) · mutations in Workloads (Workloads · Apps · Shares tabs) · Host Settings face (Virtualization · shared core) · Full Settings = desktop face escape · Headless → proteus-host-seat detach · Desktop hard switch · graphical-remote Out."
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: 11
        wrapMode: Text.WordWrap
      }
    }
  }
}
