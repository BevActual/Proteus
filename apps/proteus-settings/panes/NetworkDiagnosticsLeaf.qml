import Quickshell
import QtQuick
import QtQuick.Layouts
import "../shared"
import "../kit"
import ".." // root module — SettingsNav singleton

// Leaf UI for NetworkPane — Diagnostics (rates · ss · Wireshark escape).
ColumnLayout {
  id: root
  property Item host
  property bool active: false
  width: parent ? parent.width : implicitWidth
  spacing: Theme.spaceMd

  onActiveChanged: NetworkDiagnostics.watching = active
  Component.onCompleted: NetworkDiagnostics.watching = active
  Component.onDestruction: NetworkDiagnostics.watching = false

  component RateBar: Item {
    id: bar
    property real frac: 0
    property color fill: Theme.accent
    Layout.fillWidth: true
    Layout.preferredHeight: 4
    height: 4

    Rectangle {
      anchors.fill: parent
      radius: 2
      color: Theme.bgHover
    }

    Rectangle {
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: Math.max(0, Math.min(parent.width, parent.width * bar.frac))
      radius: 2
      color: bar.fill
      Behavior on width {
        NumberAnimation {
          duration: 280
          easing.type: Easing.OutCubic
        }
      }
    }
  }

  SettingsGroup {
    title: "Interfaces"

    SettingsFormRow {
      visible: !NetworkDiagnostics.ready || NetworkDiagnostics.interfaces.length === 0
      label: "Traffic"
      hint: NetworkDiagnostics.ready
          ? "No non-loopback interfaces"
          : "Sampling…"
      showSeparator: false
    }

    Repeater {
      model: NetworkDiagnostics.interfaces

      ColumnLayout {
        required property var modelData
        required property int index
        Layout.fillWidth: true
        spacing: 0

        SettingsFormRow {
          label: modelData.name
          hint: NetworkDiagnostics.ifaceHint(modelData)
          showSeparator: false
        }

        ColumnLayout {
          Layout.fillWidth: true
          Layout.leftMargin: Theme.spaceMd
          Layout.rightMargin: Theme.spaceMd
          Layout.bottomMargin: Theme.spaceSm
          spacing: 3

          RateBar {
            frac: NetworkDiagnostics.rateFrac(modelData.rxRate)
            fill: Theme.accent
          }

          RateBar {
            frac: NetworkDiagnostics.rateFrac(modelData.txRate)
            fill: Theme.textMute
          }

          Text {
            Layout.fillWidth: true
            text: "↓ receive · ↑ send"
            color: Theme.textMute
            font.family: Theme.fontFamily
            font.pixelSize: 10
          }
        }

        Rectangle {
          Layout.fillWidth: true
          Layout.leftMargin: Theme.spaceMd
          height: 1
          color: Theme.separator
          visible: index < NetworkDiagnostics.interfaces.length - 1
        }
      }
    }
  }

  SettingsGroup {
    title: "Path"

    SettingsFormRow {
      label: "Default route"
      hint: NetworkDiagnostics.ready ? NetworkDiagnostics.routeHint : "Sampling…"
      showSeparator: true
    }

    SettingsFormRow {
      label: "DNS"
      hint: NetworkDiagnostics.ready ? NetworkDiagnostics.dnsLabel : "Sampling…"
      showSeparator: true
    }

    SettingsFormRow {
      label: "Firewall"
      hint: NetworkDiagnostics.ready ? NetworkDiagnostics.firewallLabel : "Sampling…"
      showSeparator: false
    }
  }

  SettingsGroup {
    title: "Active connections"

    SettingsFormRow {
      visible: NetworkDiagnostics.ssHint.length > 0
          && NetworkDiagnostics.connections.length === 0
      label: "ss"
      hint: NetworkDiagnostics.ssHint
      showSeparator: false
    }

    SettingsFormRow {
      visible: NetworkDiagnostics.ready
          && !NetworkDiagnostics.ssHint.length
          && NetworkDiagnostics.connections.length === 0
      label: "Connections"
      hint: "None established right now"
      showSeparator: false
    }

    SettingsFormRow {
      visible: !NetworkDiagnostics.ready
      label: "Connections"
      hint: "Sampling…"
      showSeparator: false
    }

    Repeater {
      model: NetworkDiagnostics.connections

      SettingsFormRow {
        required property var modelData
        required property int index
        label: modelData.peer || "—"
        hint: NetworkDiagnostics.connHint(modelData)
        showSeparator: index < NetworkDiagnostics.connections.length - 1
      }
    }
  }

  SettingsGroup {
    title: "Listening"

    SettingsFormRow {
      visible: NetworkDiagnostics.ready
          && !NetworkDiagnostics.ssHint.length
          && NetworkDiagnostics.listeners.length === 0
      label: "Ports"
      hint: "Nothing listening on TCP"
      showSeparator: false
    }

    SettingsFormRow {
      visible: !NetworkDiagnostics.ready
      label: "Ports"
      hint: "Sampling…"
      showSeparator: false
    }

    Repeater {
      model: NetworkDiagnostics.listeners

      SettingsFormRow {
        required property var modelData
        required property int index
        label: modelData.local || "—"
        hint: NetworkDiagnostics.listenHint(modelData)
        showSeparator: index < NetworkDiagnostics.listeners.length - 1
      }
    }
  }

  SettingsGroup {
    title: "Quick check"

    SettingsFormRow {
      label: "Ping gateway"
      hint: NetworkDiagnostics.gateway.length
          ? NetworkDiagnostics.gateway
          : "No default gateway"
      showSeparator: true
      interactive: NetworkDiagnostics.gateway.length > 0 && !NetworkDiagnostics.pingBusy
      onActivated: NetworkDiagnostics.pingGateway()
      Text {
        text: NetworkDiagnostics.pingBusy
            && NetworkDiagnostics.pingTarget === NetworkDiagnostics.gateway
            ? "…"
            : "Ping"
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }
    }

    SettingsFormRow {
      label: "Ping 1.1.1.1"
      hint: "Cloudflare DNS · reachability only"
      showSeparator: true
      interactive: !NetworkDiagnostics.pingBusy
      onActivated: NetworkDiagnostics.pingCloudflare()
      Text {
        text: NetworkDiagnostics.pingBusy
            && NetworkDiagnostics.pingTarget === "1.1.1.1"
            ? "…"
            : "Ping"
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }
    }

    SettingsFormRow {
      label: "Last result"
      hint: NetworkDiagnostics.pingResult.length
          ? NetworkDiagnostics.pingResult
          : "—"
      showSeparator: false
    }
  }

  SettingsGroup {
    title: "Packet capture"

    SettingsFormRow {
      label: "Wireshark"
      hint: NetworkDiagnostics.captureHint
      showSeparator: false
      interactive: true
      onActivated: {
        if (NetworkDiagnostics.captureAvailable)
          NetworkDiagnostics.openCapture()
        else
          SettingsNav.goInstallSearch("wireshark-qt")
      }
      Text {
        text: NetworkDiagnostics.captureAvailable ? "Open" : "Install…"
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }
    }
  }

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 480
    text: "Fact: /proc/net/dev · ss · firewall · route/DNS · ping. Decode: Wireshark (Install… → Repos · wireshark-qt)."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }
}
