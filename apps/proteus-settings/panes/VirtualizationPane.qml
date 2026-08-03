import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../shared"
import "../kit"
import ".." // SettingsNav singleton

// Settings → Virtualization — thin host ops hub (jumps + status).
// Mutations stay in proteus-workloads app. Auto-resolver / Portainer Out.
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: Theme.spaceMd

  property bool active: false

  onActiveChanged: {
    if (active) {
      Workloads.retain()
      Workloads.refresh()
      Workloads.refreshApps()
      Workloads.refreshShares()
      root.refreshChrome()
    } else {
      Workloads.release()
    }
  }

  Component.onCompleted: {
    if (root.active) {
      Workloads.retain()
      Workloads.refresh()
      Workloads.refreshApps()
      Workloads.refreshShares()
      root.refreshChrome()
    }
  }

  Component.onDestruction: Workloads.release()

  property string hostChrome: ""
  property string chromeHint: "Reading host-chrome…"

  readonly property string enginesHint: {
    const _ = Workloads.rev
    if (!Workloads.ready && Workloads.busy)
      return "Reading engines…"
    const parts = []
    if (Workloads.libvirtAvailable)
      parts.push("libvirt")
    if (Workloads.containersAvailable)
      parts.push(Workloads.containerEngine || "containers")
    if (!parts.length)
      return "None detected — install libvirt (virsh) and/or podman|docker"
    return parts.join(" · ")
  }

  readonly property string workloadsHint: {
    const _ = Workloads.rev
    if (Workloads.summaryLabel && Workloads.summaryLabel !== "—")
      return Workloads.summaryLabel
    return "Open Workloads for inventory + start/stop/kill/create/destroy"
  }

  function refreshChrome() {
    chromeProc.running = false
    chromeProc.running = true
  }

  function runPosture(args) {
    const proot = String(Quickshell.env("PROTEUS_ROOT") || "/mnt/proteus")
    const extra = String(args || "").trim()
    Quickshell.execDetached({
      command: [
        "bash", "-lc",
        "P=" + proot + "/shell/scripts/proteus-posture; "
            + "if [[ -x \"$P\" ]]; then setsid \"$P\" " + extra + " >/dev/null 2>&1 & "
            + "elif command -v proteus-posture >/dev/null 2>&1; then "
            + "setsid proteus-posture " + extra + " >/dev/null 2>&1 & fi"
      ]
    })
    chromeRefreshTimer.restart()
  }

  function runHostSeat(cmd) {
    const proot = String(Quickshell.env("PROTEUS_ROOT") || "/mnt/proteus")
    const c = String(cmd || "").trim()
    Quickshell.execDetached({
      command: [
        "bash", "-lc",
        "S=" + proot + "/shell/scripts/proteus-host-seat; "
            + "if [[ -x \"$S\" ]]; then setsid \"$S\" " + c + " >/dev/null 2>&1 & "
            + "elif command -v proteus-host-seat >/dev/null 2>&1; then "
            + "setsid proteus-host-seat " + c + " >/dev/null 2>&1 & fi"
      ]
    })
    chromeRefreshTimer.restart()
  }

  Timer {
    id: chromeRefreshTimer
    interval: 800
    repeat: false
    onTriggered: root.refreshChrome()
  }

  Process {
    id: chromeProc
    command: [
      "bash", "-lc",
      "f=\"$HOME/.config/proteus/host-chrome\"; "
          + "if [[ -f \"$f\" ]]; then tr -d '\\n' < \"$f\"; else echo full; fi"
    ]
    stdout: StdioCollector {
      onStreamFinished: {
        const v = String(text || "").trim().toLowerCase()
        root.hostChrome = v.length ? v : "full"
        if (root.hostChrome === "none")
          root.chromeHint = "Headless — QS stopped (restore: proteus-host-seat attach)"
        else
          root.chromeHint = "Seat attached (host-chrome=" + root.hostChrome + ")"
      }
    }
  }

  readonly property string appsHint: {
    const _ = Workloads.rev
    if (!Workloads.hostAppsReady)
      return "Reading one-click apps…"
    if (!Workloads.hostAppsAvailable)
      return "podman/docker missing — install an engine for one-click apps"
    const list = Workloads.hostApps || []
    let deployed = 0
    for (let i = 0; i < list.length; i++) {
      if (list[i] && list[i].deployed)
        deployed++
    }
    return deployed
        ? deployed + " deployed · " + list.length + " in catalog"
        : list.length + " in catalog (Jellyfin, Nextcloud, …)"
  }

  readonly property string sharesHint: {
    const _ = Workloads.rev
    if (!Workloads.sharesReady)
      return "Reading shares…"
    if (!Workloads.sharesAvailable)
      return "samba missing — install for shared folders"
    const n = (Workloads.sharesItems || []).length
    return (n ? n + " share" + (n === 1 ? "" : "s") : "No shared folders")
        + " · smb " + (Workloads.smbActive ? "active" : "stopped")
  }

  SettingsGroup {
    title: "Workloads"

    SettingsFormRow {
      label: "VMs · containers"
      hint: root.workloadsHint
      showSeparator: true
      interactive: true
      onActivated: ShellState.openWorkloadsApp("workloads")
      Text {
        text: "Workloads ›"
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }
    }

    SettingsFormRow {
      label: "One-click apps"
      hint: root.appsHint
      showSeparator: true
      interactive: true
      onActivated: ShellState.openWorkloadsApp("apps")
      Text {
        text: "Apps ›"
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }
    }

    SettingsFormRow {
      label: "Shared folders"
      hint: root.sharesHint
      showSeparator: false
      interactive: true
      onActivated: ShellState.openWorkloadsApp("shares")
      Text {
        text: "Shares ›"
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }
    }
  }

  SettingsGroup {
    title: "Engines"

    SettingsFormRow {
      label: "Detected"
      hint: root.enginesHint
      showSeparator: true
    }

    SettingsFormRow {
      label: "Software"
      hint: "Install libvirt / podman from Repos when missing"
      showSeparator: false
      interactive: true
      onActivated: SettingsNav.go("packages-repos")
      Text {
        text: "Repos ›"
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }
    }
  }

  SettingsGroup {
    title: "Headless"

    SettingsFormRow {
      label: "host-chrome"
      hint: root.chromeHint
      showSeparator: true
    }

    SettingsFormRow {
      label: "Stop chrome"
      hint: "proteus-host-seat detach · CLI stays"
      showSeparator: true
      interactive: true
      onActivated: root.runHostSeat("detach")
      Text {
        text: "Headless ›"
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }
    }

    SettingsFormRow {
      label: "Restore chrome"
      hint: "proteus-host-seat attach"
      showSeparator: false
      interactive: true
      onActivated: root.runHostSeat("attach")
      Text {
        text: "Chrome ›"
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }
    }
  }

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 480
    text: "Fact: thin Settings hub — jumps + engine/headless status. Mutations in Workloads app (Workloads · Apps · Shares tabs). Auto-resolver · Portainer-style UI · virt-manager embed Out."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }
}
