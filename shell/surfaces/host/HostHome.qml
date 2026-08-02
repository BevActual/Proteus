import Quickshell
import QtQuick
import QtQuick.Layouts
import "../../shared"

// Host ops home — calm glance + Settings spine shortcuts (not a workloads app).
Item {
  id: root
  anchors.fill: parent

  property bool active: visible && !ShellState.sessionLocked && !ShellState.sessionStartLockPending

  onActiveChanged: {
    if (active) {
      SystemInfo.refresh()
      SystemLoad.retain()
      SystemLoad.refresh()
    } else {
      SystemLoad.release()
    }
  }

  Component.onCompleted: {
    if (root.active) {
      SystemInfo.refresh()
      SystemLoad.retain()
      SystemLoad.refresh()
    }
  }

  Component.onDestruction: SystemLoad.release()

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

  readonly property var actions: [
    { id: "software", label: "Software", hint: "Updates · packages", page: "packages-updates" },
    { id: "network", label: "Network", hint: "This machine · devices", page: "network" },
    { id: "about", label: "About", hint: "OS · load · Mission Center", page: "system" },
    { id: "privacy", label: "Privacy", hint: "Permissions · sensors", page: "privacy" },
    { id: "mission", label: "Mission Center", hint: MissionCenter.available ? "Open" : "Install…", page: "" },
    { id: "terminal", label: "Terminal", hint: "Local shell", page: "" },
    { id: "settings", label: "Settings", hint: "Full Settings spine", page: "" },
    { id: "desktop", label: "Desktop", hint: "Hard switch · desk", page: "" }
  ]

  function runAction(a) {
    const id = String(a && a.id || "")
    if (id === "desktop") {
      const proot = String(Quickshell.env("PROTEUS_ROOT") || "/mnt/proteus")
      Quickshell.execDetached({
        command: [
          "bash", "-lc",
          "P=" + proot + "/vm/guest/proteus-posture; "
              + "if [[ -x \"$P\" ]]; then setsid \"$P\" desktop >/dev/null 2>&1 & "
              + "elif command -v proteus-posture >/dev/null 2>&1; then "
              + "setsid proteus-posture desktop >/dev/null 2>&1 & fi"
        ]
      })
      return
    }
    if (id === "terminal") {
      root.openTerminal()
      return
    }
    if (id === "mission") {
      if (MissionCenter.available)
        MissionCenter.open()
      else
        MissionCenter.openSoftware()
      return
    }
    if (id === "settings") {
      ShellState.openSettings()
      return
    }
    if (a.page && String(a.page).length)
      ShellState.openSettings(String(a.page))
  }

  ColumnLayout {
    anchors.centerIn: parent
    width: Math.min(560, parent.width - 48)
    spacing: Theme.spaceLg

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Theme.spaceXs

      Text {
        text: SystemInfo.hostnameLabel
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: 28
        font.weight: Font.DemiBold
      }

      Text {
        Layout.fillWidth: true
        text: SystemLoad.ready ? SystemLoad.summaryLabel : "Reading load…"
        color: Theme.textDim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        wrapMode: Text.WordWrap
      }

      Text {
        Layout.fillWidth: true
        text: (SystemInfo.osLabel !== "—" ? SystemInfo.osLabel : "Proteus host")
            + " · up " + (SystemLoad.uptimeLabel || "—")
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSm
        wrapMode: Text.WordWrap
      }
    }

    GridLayout {
      Layout.fillWidth: true
      columns: 2
      columnSpacing: Theme.spaceSm
      rowSpacing: Theme.spaceSm

      Repeater {
        model: root.actions

        Rectangle {
          required property var modelData
          Layout.fillWidth: true
          Layout.preferredHeight: 64
          radius: Theme.radiusMd
          color: tileMa.containsMouse ? Theme.bgHover : Theme.elevatedFill
          border.width: 1
          border.color: Theme.chromeBorder

          ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.spaceMd
            spacing: 2

            Text {
              text: modelData.label
              color: Theme.text
              font.family: Theme.fontFamily
              font.pixelSize: 14
              font.weight: Font.Medium
            }

            Text {
              Layout.fillWidth: true
              text: modelData.hint
              color: Theme.textMute
              font.family: Theme.fontFamily
              font.pixelSize: 11
              elide: Text.ElideRight
            }
          }

          MouseArea {
            id: tileMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.runAction(modelData)
          }
        }
      }
    }

    Text {
      Layout.fillWidth: true
      text: "Fact: Host ops home reuses Settings — VM/container setup stays a separate app later. Headless-no-QS Out."
      color: Theme.textMute
      font.family: Theme.fontFamily
      font.pixelSize: 11
      wrapMode: Text.WordWrap
    }
  }

  Timer {
    interval: 5000
    running: root.active
    repeat: true
    onTriggered: SystemLoad.refresh()
  }
}
