import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../shared"
import "../kit"

// Privacy & security hub → activity / category / Flatpak leaves.
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: Theme.spaceMd

  property string page: "privacy"
  signal requestGo(string id)

  property string clipHint: ""
  property bool clipBusy: false

  readonly property var sections: [
    {
      key: "privacy-activity",
      label: "In use now"
    },
    {
      key: "privacy-microphone",
      label: "Microphone"
    },
    {
      key: "privacy-camera",
      label: "Camera"
    },
    {
      key: "privacy-location",
      label: "Location"
    },
    {
      key: "privacy-notifications",
      label: "Notifications"
    },
    {
      key: "privacy-screen",
      label: "Screen recording"
    },
    {
      key: "privacy-diagnostics",
      label: "Diagnostics"
    },
    {
      key: "privacy-flatpak",
      label: "Flatpak apps"
    }
  ]

  readonly property string accountsHint: {
    if (!Accounts.ready)
      return "OAuth tokens in ~/.local/share/proteus/accounts/ — not settings.json"
    const n = Accounts.seats ? Accounts.seats.length : 0
    if (n <= 0)
      return "No seats · calendar glance idle · tokens stay out of settings.json"
    return n + (n === 1 ? " seat" : " seats")
        + " · calendar fetch when glance opens · vault under ~/.local/share/proteus/accounts/"
  }

  readonly property string weatherLeaveHint: {
    if (!Config.weatherEnabled)
      return "Fetch off — no Open-Meteo calls"
    if (!Config.locationName.length)
      return "No place set — nothing sent"
    return "Open-Meteo gets stored lat/lon only · never IP-inferred"
  }

  onPageChanged: {
    if (page === "privacy" || page.startsWith("privacy-")) {
      Accounts.refresh()
      Permissions.refresh()
      root.clipHint = ""
    }
  }

  Component.onCompleted: {
    Accounts.refresh()
    Permissions.refresh()
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

  // ── Hub ──────────────────────────────────────────────────────────
  ColumnLayout {
    Layout.fillWidth: true
    spacing: Theme.spaceMd
    visible: root.page === "privacy"

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
            ? (Config.locationName + " · Date, time & weather")
            : "Not set · Date, time & weather"
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
      Layout.maximumWidth: 520
      text: "App permissions gate adaptive apps, Flatpak overrides, portal PermissionStore (mic/camera/screen), and best-effort capture enforce. Not a full OS sandbox — fail-open until Permissions.ready."
      color: Theme.textDim
      font.family: Theme.fontFamily
      font.pixelSize: 13
      wrapMode: Text.WordWrap
    }

    SettingsHubList {
      items: root.sections
      onActivated: key => root.requestGo(key)
    }
  }

  // ── Leaves ───────────────────────────────────────────────────────
  StickyPaneLoader {
    want: root.page === "privacy-activity"
    source: "PrivacyActivityLeaf.qml"
    onLoaded: item.requestGo.connect(id => root.requestGo(id))
  }

  StickyPaneLoader {
    want: root.page === "privacy-microphone"
        || root.page === "privacy-camera"
        || root.page === "privacy-location"
        || root.page === "privacy-notifications"
        || root.page === "privacy-screen"
        || root.page === "privacy-diagnostics"
    source: "PrivacyCategoryLeaf.qml"
    onLoaded: {
      item.categoryId = Qt.binding(() => {
        const p = String(root.page || "")
        if (p.indexOf("privacy-") === 0)
          return p.slice("privacy-".length)
        return "microphone"
      })
    }
  }

  StickyPaneLoader {
    want: root.page === "privacy-flatpak"
    source: "PrivacyFlatpakLeaf.qml"
  }
}
