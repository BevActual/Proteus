import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "shared"

// Thin Host workloads inventory + start/stop/kill/create/destroy.
// Settings virt = About jump here. headless-no-QS = host-chrome Fact.
FocusScope {
  id: root
  focus: true

  property string pendingAction: ""
  property string pendingKind: ""
  property string pendingName: ""
  property string pendingExtra: ""

  property string createKind: "container"
  property string createName: ""
  property string createDisk: ""
  property string createImage: ""

  readonly property bool confirmOpen: pendingAction.length > 0 && pendingName.length > 0

  Component.onCompleted: {
    Workloads.retain()
    Workloads.refresh()
    root.forceActiveFocus()
  }
  Component.onDestruction: Workloads.release()

  function quitApp() {
    Qt.quit()
  }

  function escapeAction() {
    if (root.confirmOpen) {
      root.clearConfirm()
      return
    }
    root.quitApp()
  }

  Keys.onPressed: (event) => {
    if (event.key === Qt.Key_Escape) {
      root.escapeAction()
      event.accepted = true
    }
  }

  function openVirtManager() {
    const ids = ["virt-manager", "virt-manager.desktop", "gnome-boxes", "org.gnome.Boxes"]
    for (let i = 0; i < ids.length; i++) {
      const desk = DesktopEntries.heuristicLookup(ids[i])
      if (desk) {
        desk.execute()
        return true
      }
    }
    return false
  }

  function requestAction(action, kind, name, extra) {
    if (Workloads.mutating)
      return
    root.pendingAction = String(action || "")
    root.pendingKind = String(kind || "")
    root.pendingName = String(name || "")
    root.pendingExtra = String(extra || "")
  }

  function requestCreate() {
    const k = String(root.createKind || "").trim()
    const n = String(root.createName || "").trim()
    const extra = k === "vm"
        ? String(root.createDisk || "").trim()
        : String(root.createImage || "").trim()
    if (!n.length || !extra.length)
      return
    root.requestAction("create", k, n, extra)
  }

  function clearConfirm() {
    root.pendingAction = ""
    root.pendingKind = ""
    root.pendingName = ""
    root.pendingExtra = ""
  }

  function runConfirm() {
    const a = root.pendingAction
    const k = root.pendingKind
    const n = root.pendingName
    const extra = root.pendingExtra
    root.clearConfirm()
    if (a === "start")
      Workloads.start(k, n)
    else if (a === "stop")
      Workloads.stop(k, n)
    else if (a === "kill")
      Workloads.kill(k, n)
    else if (a === "create")
      Workloads.create(k, n, extra)
    else if (a === "destroy")
      Workloads.destroy(k, n)
  }

  function confirmVerb() {
    if (root.pendingAction === "start")
      return "Start"
    if (root.pendingAction === "stop")
      return "Stop"
    if (root.pendingAction === "kill")
      return "Force stop"
    if (root.pendingAction === "create")
      return "Create"
    if (root.pendingAction === "destroy")
      return "Remove"
    return "Confirm"
  }

  function confirmDetail() {
    if (root.pendingAction === "stop")
      return "Graceful shutdown — use Force stop if it will not yield."
    if (root.pendingAction === "kill")
      return root.pendingKind === "vm"
          ? "Force power-off (virsh destroy) — keeps the domain defined."
          : "Force kill the main process — keeps the container for Remove later."
    if (root.pendingAction === "start")
      return "Starts the workload if it is stopped."
    if (root.pendingAction === "create")
      return root.pendingKind === "vm"
          ? "Defines a thin libvirt domain from an existing qcow2 (not an install wizard)."
          : "Runs a detached container (pull may occur)."
    if (root.pendingAction === "destroy")
      return "Removes definition/container when stopped — Force stop first if running."
    return ""
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Theme.spaceLg
    spacing: Theme.spaceMd

    RowLayout {
      Layout.fillWidth: true
      spacing: Theme.spaceMd

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 2

        Text {
          text: "Workloads"
          color: Theme.text
          font.family: Theme.fontFamily
          font.pixelSize: 22
          font.weight: Font.DemiBold
        }

        Text {
          Layout.fillWidth: true
          text: {
            const _r = Workloads.rev
            if (Workloads.mutating)
              return "Applying…"
            if (Workloads.busy && !Workloads.ready)
              return "Reading libvirt and containers…"
            return Workloads.summaryLabel
          }
          color: Theme.textDim
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSize
          wrapMode: Text.WordWrap
        }
      }

      Rectangle {
        Layout.preferredHeight: 32
        Layout.preferredWidth: refreshTxt.implicitWidth + 24
        radius: Theme.radiusMd
        color: refreshMa.containsMouse ? Theme.chromeAccentSoft : Theme.chromeHover
        opacity: Workloads.mutating ? 0.5 : 1

        Text {
          id: refreshTxt
          anchors.centerIn: parent
          text: Workloads.busy ? "…" : "Refresh"
          color: Theme.accent
          font.family: Theme.fontFamily
          font.pixelSize: 12
          font.weight: Font.DemiBold
        }

        MouseArea {
          id: refreshMa
          anchors.fill: parent
          hoverEnabled: true
          enabled: !Workloads.mutating
          cursorShape: Qt.PointingHandCursor
          onClicked: Workloads.refresh()
        }
      }

      Rectangle {
        Layout.preferredWidth: 28
        Layout.preferredHeight: 28
        radius: 14
        color: closeMa.containsMouse ? Theme.bgHover : "transparent"

        Text {
          anchors.centerIn: parent
          text: "✕"
          color: Theme.textDim
          font.pixelSize: 12
        }

        MouseArea {
          id: closeMa
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.quitApp()
        }
      }
    }

    // Confirm strip
    Rectangle {
      Layout.fillWidth: true
      visible: root.confirmOpen
      implicitHeight: confirmCol.implicitHeight + 16
      radius: Theme.radiusMd
      color: Theme.elevatedFill
      border.width: 1
      border.color: Theme.chromeBorder

      ColumnLayout {
        id: confirmCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: Theme.spaceMd
        spacing: Theme.spaceSm

        Text {
          Layout.fillWidth: true
          text: root.confirmVerb() + " " + root.pendingKind + " · " + root.pendingName
              + (root.pendingExtra.length ? " · " + root.pendingExtra : "") + "?"
          color: Theme.text
          font.family: Theme.fontFamily
          font.pixelSize: 13
          font.weight: Font.Medium
          wrapMode: Text.WordWrap
        }

        Text {
          Layout.fillWidth: true
          text: root.confirmDetail()
          color: Theme.textMute
          font.family: Theme.fontFamily
          font.pixelSize: 11
          wrapMode: Text.WordWrap
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Theme.spaceSm

          Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            radius: Theme.radiusMd
            color: cancelMa.containsMouse ? Theme.chromeHover : Theme.bgHover

            Text {
              anchors.centerIn: parent
              text: "Cancel"
              color: Theme.textDim
              font.family: Theme.fontFamily
              font.pixelSize: 12
              font.weight: Font.DemiBold
            }

            MouseArea {
              id: cancelMa
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.clearConfirm()
            }
          }

          Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            radius: Theme.radiusMd
            color: okMa.containsMouse ? Theme.chromeAccentSoft : Theme.chromeHover

            Text {
              anchors.centerIn: parent
              text: root.confirmVerb()
              color: Theme.accent
              font.family: Theme.fontFamily
              font.pixelSize: 12
              font.weight: Font.DemiBold
            }

            MouseArea {
              id: okMa
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.runConfirm()
            }
          }
        }
      }
    }

    Text {
      Layout.fillWidth: true
      visible: {
        const _r = Workloads.rev
        return !!Workloads.mutateError.length
      }
      text: Workloads.mutateError
      color: Theme.danger
      font.family: Theme.fontFamily
      font.pixelSize: 11
      wrapMode: Text.WordWrap
    }

    // Create strip
    Rectangle {
      Layout.fillWidth: true
      implicitHeight: createCol.implicitHeight + 16
      radius: Theme.radiusMd
      color: Theme.elevatedFill
      border.width: 1
      border.color: Theme.chromeBorder

      ColumnLayout {
        id: createCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: Theme.spaceMd
        spacing: Theme.spaceSm

        Text {
          text: "Create"
          color: Theme.text
          font.family: Theme.fontFamily
          font.pixelSize: 13
          font.weight: Font.Medium
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Theme.spaceSm

          Rectangle {
            Layout.preferredHeight: 28
            Layout.preferredWidth: vmKindTxt.implicitWidth + 16
            radius: Theme.radiusMd
            color: root.createKind === "vm" ? Theme.chromeAccentSoft : Theme.chromeHover
            Text {
              id: vmKindTxt
              anchors.centerIn: parent
              text: "VM"
              color: Theme.accent
              font.family: Theme.fontFamily
              font.pixelSize: 11
              font.weight: Font.DemiBold
            }
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.createKind = "vm"
            }
          }

          Rectangle {
            Layout.preferredHeight: 28
            Layout.preferredWidth: ctrKindTxt.implicitWidth + 16
            radius: Theme.radiusMd
            color: root.createKind === "container" ? Theme.chromeAccentSoft : Theme.chromeHover
            Text {
              id: ctrKindTxt
              anchors.centerIn: parent
              text: "Container"
              color: Theme.accent
              font.family: Theme.fontFamily
              font.pixelSize: 11
              font.weight: Font.DemiBold
            }
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.createKind = "container"
            }
          }
        }

        TextField {
          Layout.fillWidth: true
          placeholderText: "Name"
          text: root.createName
          onTextChanged: root.createName = text
          color: Theme.text
          font.family: Theme.fontFamily
          background: Rectangle {
            radius: Theme.radiusSm
            color: Theme.bgHover
            border.width: 1
            border.color: Theme.chromeBorder
          }
        }

        TextField {
          Layout.fillWidth: true
          visible: root.createKind === "vm"
          placeholderText: "Existing qcow2 path"
          text: root.createDisk
          onTextChanged: root.createDisk = text
          color: Theme.text
          font.family: Theme.fontFamily
          background: Rectangle {
            radius: Theme.radiusSm
            color: Theme.bgHover
            border.width: 1
            border.color: Theme.chromeBorder
          }
        }

        TextField {
          Layout.fillWidth: true
          visible: root.createKind === "container"
          placeholderText: "Image (e.g. alpine:latest)"
          text: root.createImage
          onTextChanged: root.createImage = text
          color: Theme.text
          font.family: Theme.fontFamily
          background: Rectangle {
            radius: Theme.radiusSm
            color: Theme.bgHover
            border.width: 1
            border.color: Theme.chromeBorder
          }
        }

        Rectangle {
          Layout.preferredHeight: 32
          Layout.preferredWidth: createBtnTxt.implicitWidth + 24
          radius: Theme.radiusMd
          opacity: Workloads.mutating ? 0.5 : 1
          color: createBtnMa.containsMouse ? Theme.chromeAccentSoft : Theme.chromeHover
          Text {
            id: createBtnTxt
            anchors.centerIn: parent
            text: "Create…"
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: 12
            font.weight: Font.DemiBold
          }
          MouseArea {
            id: createBtnMa
            anchors.fill: parent
            hoverEnabled: true
            enabled: !Workloads.mutating
            cursorShape: Qt.PointingHandCursor
            onClicked: root.requestCreate()
          }
        }
      }
    }

    Flickable {
      Layout.fillWidth: true
      Layout.fillHeight: true
      clip: true
      contentWidth: width
      contentHeight: listCol.implicitHeight
      boundsBehavior: Flickable.StopAtBounds

      ColumnLayout {
        id: listCol
        width: parent.width
        spacing: Theme.spaceMd

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Theme.spaceXs

          Text {
            text: "Virtual machines"
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 13
            font.weight: Font.Medium
          }

          Text {
            Layout.fillWidth: true
            visible: {
              const _r = Workloads.rev
              return !Workloads.libvirtAvailable
            }
            text: "libvirt / virsh not available on this host"
            color: Theme.textMute
            font.family: Theme.fontFamily
            font.pixelSize: 11
            wrapMode: Text.WordWrap
          }

          Text {
            Layout.fillWidth: true
            visible: {
              const _r = Workloads.rev
              return Workloads.libvirtAvailable && Workloads.domains.length === 0
            }
            text: "No domains"
            color: Theme.textMute
            font.family: Theme.fontFamily
            font.pixelSize: 11
          }

          Repeater {
            model: {
              const _r = Workloads.rev
              return Workloads.domains || []
            }
            Rectangle {
              required property var modelData
              Layout.fillWidth: true
              Layout.preferredHeight: 48
              radius: Theme.radiusMd
              color: Theme.elevatedFill
              border.width: 1
              border.color: Theme.chromeBorder

              RowLayout {
                anchors.fill: parent
                anchors.margins: Theme.spaceMd
                spacing: Theme.spaceSm

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: 1
                  Text {
                    Layout.fillWidth: true
                    text: String(modelData.name || "—")
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    elide: Text.ElideRight
                  }
                  Text {
                    text: String(modelData.state || "")
                    color: Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                  }
                }

                Rectangle {
                  Layout.preferredHeight: 28
                  Layout.preferredWidth: vmActTxt.implicitWidth + 20
                  radius: Theme.radiusMd
                  color: vmActMa.containsMouse ? Theme.chromeAccentSoft : Theme.chromeHover
                  opacity: Workloads.mutating ? 0.5 : 1

                  Text {
                    id: vmActTxt
                    anchors.centerIn: parent
                    text: Workloads.isVmRunning(modelData) ? "Stop" : "Start"
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                  }

                  MouseArea {
                    id: vmActMa
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: !Workloads.mutating
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.requestAction(
                        Workloads.isVmRunning(modelData) ? "stop" : "start",
                        "vm",
                        String(modelData.name || ""))
                  }
                }

                Rectangle {
                  Layout.preferredHeight: 28
                  Layout.preferredWidth: vmKillTxt.implicitWidth + 20
                  radius: Theme.radiusMd
                  visible: Workloads.isVmRunning(modelData)
                  color: vmKillMa.containsMouse ? Theme.chromeAccentSoft : Theme.chromeHover
                  opacity: Workloads.mutating ? 0.5 : 1

                  Text {
                    id: vmKillTxt
                    anchors.centerIn: parent
                    text: "Force stop"
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                  }

                  MouseArea {
                    id: vmKillMa
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: !Workloads.mutating
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.requestAction("kill", "vm", String(modelData.name || ""))
                  }
                }

                Rectangle {
                  Layout.preferredHeight: 28
                  Layout.preferredWidth: vmRmTxt.implicitWidth + 20
                  radius: Theme.radiusMd
                  opacity: (Workloads.mutating || Workloads.isVmRunning(modelData)) ? 0.45 : 1
                  color: vmRmMa.containsMouse ? Theme.chromeAccentSoft : Theme.chromeHover

                  Text {
                    id: vmRmTxt
                    anchors.centerIn: parent
                    text: "Remove"
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                  }

                  MouseArea {
                    id: vmRmMa
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: !Workloads.mutating && !Workloads.isVmRunning(modelData)
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.requestAction("destroy", "vm", String(modelData.name || ""))
                  }
                }
              }
            }
          }
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Theme.spaceXs

          Text {
            text: "Containers"
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 13
            font.weight: Font.Medium
          }

          Text {
            Layout.fillWidth: true
            visible: {
              const _r = Workloads.rev
              return !Workloads.containersAvailable
            }
            text: "podman / docker not available on this host"
            color: Theme.textMute
            font.family: Theme.fontFamily
            font.pixelSize: 11
            wrapMode: Text.WordWrap
          }

          Text {
            Layout.fillWidth: true
            visible: {
              const _r = Workloads.rev
              return Workloads.containersAvailable && Workloads.containers.length === 0
            }
            text: "No containers"
            color: Theme.textMute
            font.family: Theme.fontFamily
            font.pixelSize: 11
          }

          Repeater {
            model: {
              const _r = Workloads.rev
              return Workloads.containers || []
            }
            Rectangle {
              required property var modelData
              Layout.fillWidth: true
              Layout.preferredHeight: 52
              radius: Theme.radiusMd
              color: Theme.elevatedFill
              border.width: 1
              border.color: Theme.chromeBorder

              RowLayout {
                anchors.fill: parent
                anchors.margins: Theme.spaceMd
                spacing: Theme.spaceSm

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: 1
                  Text {
                    Layout.fillWidth: true
                    text: (Workloads.containerEngine || "ctr") + " · "
                        + String(modelData.name || "—")
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    elide: Text.ElideRight
                  }
                  Text {
                    Layout.fillWidth: true
                    visible: !!String(modelData.status || "").length
                    text: String(modelData.status || "")
                        + (modelData.id ? " · " + String(modelData.id) : "")
                    color: Theme.textMute
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    elide: Text.ElideRight
                  }
                }

                Rectangle {
                  Layout.preferredHeight: 28
                  Layout.preferredWidth: ctrActTxt.implicitWidth + 20
                  radius: Theme.radiusMd
                  color: ctrActMa.containsMouse ? Theme.chromeAccentSoft : Theme.chromeHover
                  opacity: Workloads.mutating ? 0.5 : 1

                  Text {
                    id: ctrActTxt
                    anchors.centerIn: parent
                    text: Workloads.isContainerRunning(modelData) ? "Stop" : "Start"
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                  }

                  MouseArea {
                    id: ctrActMa
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: !Workloads.mutating
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.requestAction(
                        Workloads.isContainerRunning(modelData) ? "stop" : "start",
                        "container",
                        String(modelData.name || ""))
                  }
                }

                Rectangle {
                  Layout.preferredHeight: 28
                  Layout.preferredWidth: ctrKillTxt.implicitWidth + 20
                  radius: Theme.radiusMd
                  visible: Workloads.isContainerRunning(modelData)
                  color: ctrKillMa.containsMouse ? Theme.chromeAccentSoft : Theme.chromeHover
                  opacity: Workloads.mutating ? 0.5 : 1

                  Text {
                    id: ctrKillTxt
                    anchors.centerIn: parent
                    text: "Force stop"
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                  }

                  MouseArea {
                    id: ctrKillMa
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: !Workloads.mutating
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.requestAction(
                        "kill", "container", String(modelData.name || ""))
                  }
                }

                Rectangle {
                  Layout.preferredHeight: 28
                  Layout.preferredWidth: ctrRmTxt.implicitWidth + 20
                  radius: Theme.radiusMd
                  opacity: (Workloads.mutating || Workloads.isContainerRunning(modelData)) ? 0.45 : 1
                  color: ctrRmMa.containsMouse ? Theme.chromeAccentSoft : Theme.chromeHover

                  Text {
                    id: ctrRmTxt
                    anchors.centerIn: parent
                    text: "Remove"
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                  }

                  MouseArea {
                    id: ctrRmMa
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: !Workloads.mutating && !Workloads.isContainerRunning(modelData)
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.requestAction(
                        "destroy", "container", String(modelData.name || ""))
                  }
                }
              }
            }
          }
        }

        Text {
          Layout.fillWidth: true
          visible: {
            const _r = Workloads.rev
            return !!Workloads.hint.length
          }
          text: Workloads.hint
          color: Theme.textDim
          font.family: Theme.fontFamily
          font.pixelSize: 11
          wrapMode: Text.WordWrap
        }

        Text {
          Layout.fillWidth: true
          visible: {
            const _r = Workloads.rev
            return !!Workloads.error.length
          }
          text: Workloads.error
          color: Theme.danger
          font.family: Theme.fontFamily
          font.pixelSize: 11
          wrapMode: Text.WordWrap
        }
      }
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Theme.spaceSm

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 36
        radius: Theme.radiusMd
        color: virtMa.containsMouse ? Theme.chromeAccentSoft : Theme.chromeHover

        Text {
          anchors.centerIn: parent
          text: "Open virt-manager"
          color: Theme.accent
          font.family: Theme.fontFamily
          font.pixelSize: 12
          font.weight: Font.DemiBold
        }

        MouseArea {
          id: virtMa
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (!root.openVirtManager())
              ShellState.openSettings("packages-search", "virt-manager")
          }
        }
      }
    }

    Text {
      Layout.fillWidth: true
      text: "Fact: start/stop/kill/create/destroy In · Settings About jumps here · headless-no-QS via proteus-posture host --headless · no Virtualization Settings hub."
      color: Theme.textMute
      font.family: Theme.fontFamily
      font.pixelSize: 11
      wrapMode: Text.WordWrap
    }
  }

  Timer {
    interval: 12000
    running: true
    repeat: true
    onTriggered: {
      if (!Workloads.mutating)
        Workloads.refresh()
    }
  }
}
