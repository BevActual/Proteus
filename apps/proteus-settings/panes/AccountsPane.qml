import Quickshell
import QtQuick
import QtQuick.Layouts
import "../shared"
import "../kit"

// Online accounts: honest coming-soon providers (SETTINGS-IA §2).
// No OAuth / GOA / inventing mail-contacts apps.
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: Theme.spaceMd

  property bool active: false

  readonly property var providers: [
    {
      label: "Mail",
      hint: "Connect a provider when adaptive mail exists"
    },
    {
      label: "Contacts",
      hint: "Provider sync hooks — later"
    },
    {
      label: "Cloud storage",
      hint: "Mount / sync providers — later"
    }
  ]

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 480
    text: "Mail, contacts, and cloud providers bind here later. Proteus does not invent those apps in Settings."
    color: Theme.textDim
    font.family: Theme.fontFamily
    font.pixelSize: 13
    wrapMode: Text.WordWrap
  }

  SettingsGroup {
    title: "Providers"

    Repeater {
      model: root.providers

      SettingsFormRow {
        required property var modelData
        required property int index
        label: modelData.label
        hint: modelData.hint
        showSeparator: index < root.providers.length - 1
        Text {
          text: "Coming soon"
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
    text: "Fact: no OAuth or account store yet — rows are placeholders so the IA seat is real chrome, not a blank stub."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }
}
