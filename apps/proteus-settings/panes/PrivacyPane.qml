import Quickshell
import QtQuick
import QtQuick.Layouts
import "../shared"
import "../kit"

// Privacy: permission categories listed honestly as not enforced yet.
// No fake grant toggles (SETTINGS-IA §2 · APPLICATIONS EnvGate).
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: Theme.spaceMd

  property bool active: false

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

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 480
    text: "Permissions will gate adaptive apps when a grant model exists. Today EnvGate hides unavailable apps by capability — this pane does not enforce grants yet."
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
