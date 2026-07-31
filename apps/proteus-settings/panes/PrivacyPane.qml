import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../shared"
import "../kit"

// Privacy: what leaves the machine · weather mute · session · honest
// permission categories (not enforced — SETTINGS-IA · APPLICATIONS).
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: Theme.spaceMd

  property bool active: false
  signal requestGo(string id)

  property string clipHint: ""
  property bool clipBusy: false

  readonly property var categories: [
    {
      label: "Microphone",
      hint: "App access to capture audio"
    },
    {
      label: "Camera",
      hint: "App access to capture video"
    },
    {
      label: "Location",
      hint: "Precise place from Date & time — not IP-inferred"
    },
    {
      label: "Notifications",
      hint: "Toast / portal notification grants"
    },
    {
      label: "Screen recording",
      hint: "Portal / capture grants"
    },
    {
      label: "Diagnostics",
      hint: "What leaves the machine"
    }
  ]

  readonly property string accountsHint: {
    if (!Accounts.ready)
      return "OAuth tokens in ~/.local/share/proteus/accounts/ — not settings.json"
    const n = Accounts.seats ? Accounts.seats.length : 0
    if (n <= 0)
      return "No seats · tokens stay out of settings.json"
    return n + (n === 1 ? " seat" : " seats")
        + " · tokens under ~/.local/share/proteus/accounts/"
  }

  readonly property string weatherLeaveHint: {
    if (!Config.weatherEnabled)
      return "Fetch off — no Open-Meteo calls"
    if (!Config.locationName.length)
      return "No place set — nothing sent"
    return "Open-Meteo gets stored lat/lon only · never IP-inferred"
  }

  onActiveChanged: {
    if (active) {
      Accounts.refresh()
      root.clipHint = ""
    }
  }

  function clearClipboard() {
    if (root.clipBusy)
      return
    root.clipBusy = true
    root.clipHint = "Clearing…"
    clipClearProc.running = false
    clipClearProc.running = true
  }

  Process {
    id: clipClearProc
    command: [
      "bash",
      "-lc",
      "ok=0; msg=''\n"
          + "if command -v cliphist >/dev/null 2>&1; then\n"
          + "  cliphist wipe >/dev/null 2>&1 || true\n"
          + "  ok=1\n"
          + "else\n"
          + "  msg='cliphist not installed'\n"
          + "fi\n"
          + "if command -v wl-copy >/dev/null 2>&1; then\n"
          + "  wl-copy --clear >/dev/null 2>&1 || wl-copy -c >/dev/null 2>&1 || true\n"
          + "elif command -v xclip >/dev/null 2>&1; then\n"
          + "  xclip -selection clipboard /dev/null >/dev/null 2>&1 || true\n"
          + "fi\n"
          + "if [[ $ok -eq 1 ]]; then echo CLEARED; else echo \"MISS:${msg:-clipboard tools missing}\"; fi\n"
    ]
    stdout: StdioCollector {
      onStreamFinished: {
        root.clipBusy = false
        const line = text.trim().split("\n").pop() || ""
        if (line.indexOf("CLEARED") === 0)
          root.clipHint = "Cleared"
        else if (line.indexOf("MISS:") === 0)
          root.clipHint = line.slice(5) || "Clipboard tools missing"
        else
          root.clipHint = "Done"
        clipFlash.restart()
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        if (root.clipBusy) {
          root.clipBusy = false
          root.clipHint = "Clear failed"
          clipFlash.restart()
        }
      }
    }
  }

  Timer {
    id: clipFlash
    interval: 2500
    onTriggered: root.clipHint = ""
  }

  SettingsGroup {
    title: "What leaves this machine"

    SettingsFormRow {
      label: "Weather"
      hint: root.weatherLeaveHint
      showSeparator: true
    }

    SettingsFormRow {
      label: "Location"
      hint: Config.locationName.length
          ? (Config.locationName + " · Date & time")
          : "Not set · Date & time"
      showSeparator: true
      interactive: true
      onActivated: root.requestGo("datetime")
      Text {
        text: "›"
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }
    }

    SettingsFormRow {
      label: "Online accounts"
      hint: root.accountsHint
      showSeparator: true
      interactive: true
      onActivated: root.requestGo("accounts")
      Text {
        text: "›"
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }
    }

    SettingsFormRow {
      label: "Hardware probe"
      hint: "Local cache only · ~/.config/proteus/hw-probe.json"
      showSeparator: true
    }

    SettingsFormRow {
      label: "Telemetry"
      hint: "Proteus does not phone home — no crash or analytics pipeline"
      showSeparator: false
    }
  }

  SettingsGroup {
    title: "Weather network"

    SettingsFormRow {
      label: "Fetch conditions"
      hint: Config.weatherEnabled
          ? "Open-Meteo when a place is set"
          : "Muted — place stays; no forecast traffic"
      showSeparator: false
      SettingsSegmented {
        Layout.preferredWidth: 140
        options: [
          {
            id: "on",
            label: "On"
          },
          {
            id: "off",
            label: "Off"
          }
        ]
        selected: Config.weatherEnabled ? "on" : "off"
        onActivated: id => Weather.setEnabled(id === "on")
      }
    }
  }

  SettingsGroup {
    title: "Session"

    SettingsFormRow {
      label: "Do Not Disturb"
      hint: Notifications.dnd
          ? "Toasts suppressed · alerts still queue"
          : "Toasts allowed"
      showSeparator: true
      SettingsSegmented {
        Layout.preferredWidth: 140
        options: [
          {
            id: "off",
            label: "Off"
          },
          {
            id: "on",
            label: "On"
          }
        ]
        selected: Notifications.dnd ? "on" : "off"
        onActivated: id => Notifications.setDnd(id === "on")
      }
    }

    SettingsFormRow {
      label: "Lock now"
      hint: "Lock screen"
      showSeparator: true
      interactive: true
      onActivated: ShellState.lockSession()
      Text {
        text: "Lock"
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }
    }

    SettingsFormRow {
      label: "Clear clipboard history"
      hint: root.clipHint.length
          ? root.clipHint
          : "cliphist wipe + clear primary selection"
      showSeparator: true
      interactive: !root.clipBusy
      onActivated: root.clearClipboard()
      Text {
        text: root.clipBusy ? "…" : "Clear"
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }
    }

    SettingsFormRow {
      label: "LocalSend"
      hint: "LAN share · Network"
      showSeparator: false
      interactive: true
      onActivated: root.requestGo("network-localsend")
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
    text: "Permissions will gate adaptive apps when a grant model exists. Today EnvGate hides unavailable apps by capability — this pane does not enforce grants."
    color: Theme.textDim
    font.family: Theme.fontFamily
    font.pixelSize: 13
    wrapMode: Text.WordWrap
  }

  SettingsGroup {
    title: "App permissions"

    Repeater {
      model: root.categories

      SettingsFormRow {
        required property var modelData
        required property int index
        label: modelData.label
        hint: modelData.hint
        showSeparator: index < root.categories.length - 1
        Text {
          text: "Not enforced"
          color: Theme.textMute
          font.family: Theme.fontFamily
          font.pixelSize: 12
        }
      }
    }
  }

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 480
    text: "Fact: docs/proteus/APPLICATIONS.md · shell/shared/EnvGate.qml — no per-app grant store."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }
}
