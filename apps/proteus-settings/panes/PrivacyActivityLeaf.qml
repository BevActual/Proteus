import Quickshell
import QtQuick
import QtQuick.Layouts
import "../shared"
import "../kit"

// Leaf — live mic / camera / screen capture activity.
ColumnLayout {
  id: root
  width: parent ? parent.width : implicitWidth
  spacing: Theme.spaceMd

  signal requestGo(string id)

  Component.onCompleted: Permissions.refreshActivity()

  readonly property var micApps: {
    const _r = Permissions.rev
    const _a = PrivacyIndicators.apps
    return PrivacyIndicators.appsForKind("microphone")
  }
  readonly property var cameraApps: {
    const _r = Permissions.rev
    const _a = PrivacyIndicators.apps
    return PrivacyIndicators.appsForKind("camera")
  }
  readonly property var screenApps: {
    const _r = Permissions.rev
    const _a = PrivacyIndicators.apps
    return PrivacyIndicators.appsForKind("screen")
  }

  function labels(list) {
    if (!list || !list.length)
      return "None"
    return list.map(a => String(a.label || a.id || a.binary || "App")).join(", ")
  }

  SettingsGroup {
    title: "In use now"

    Text {
      Layout.fillWidth: true
      Layout.maximumWidth: 520
      text: "Best-effort from PipeWire / pactl / camera devices. Not a grant — manage Allow/Ask/Deny under each category."
      color: Theme.textDim
      font.family: Theme.fontFamily
      font.pixelSize: 12
      wrapMode: Text.WordWrap
      Layout.bottomMargin: Theme.spaceXs
    }

    SettingsFormRow {
      label: "Microphone"
      hint: PrivacyIndicators.mic ? root.labels(root.micApps) : "Idle"
      showSeparator: true
      interactive: true
      onActivated: root.requestGo("privacy-microphone")
      Text {
        text: PrivacyIndicators.mic ? "●" : "○"
        color: PrivacyIndicators.mic ? PrivacyIndicators.micColor : Theme.textMute
        font.pixelSize: 12
      }
    }

    SettingsFormRow {
      label: "Camera"
      hint: PrivacyIndicators.camera ? root.labels(root.cameraApps) : "Idle"
      showSeparator: true
      interactive: true
      onActivated: root.requestGo("privacy-camera")
      Text {
        text: PrivacyIndicators.camera ? "●" : "○"
        color: PrivacyIndicators.camera ? PrivacyIndicators.cameraColor : Theme.textMute
        font.pixelSize: 12
      }
    }

    SettingsFormRow {
      label: "Screen recording"
      hint: PrivacyIndicators.screen ? root.labels(root.screenApps) : "Idle"
      showSeparator: false
      interactive: true
      onActivated: root.requestGo("privacy-screen")
      Text {
        text: PrivacyIndicators.screen ? "●" : "○"
        color: PrivacyIndicators.screen ? PrivacyIndicators.screenColor : Theme.textMute
        font.pixelSize: 12
      }
    }
  }

  SettingsFormRow {
    label: "Refresh"
    hint: "Re-probe capture activity"
    interactive: true
    showSeparator: false
    onActivated: {
      PrivacyIndicators.refresh()
      Permissions.refreshActivity()
    }
    Text {
      text: "↻"
      color: Theme.textMute
      font.pixelSize: 14
    }
  }
}
