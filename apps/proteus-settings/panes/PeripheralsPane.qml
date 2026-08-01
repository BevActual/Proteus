import Quickshell
import QtQuick
import QtQuick.Layouts
import "../shared"
import "../kit"

// Peripherals category: Keyboard · Mouse (headphones stay under Sound).
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: 12

  property string page: "peripherals"
  signal requestGo(string id)

  readonly property var sections: [
    {
      key: "peripherals-keyboard",
      label: "Keyboard"
    },
    {
      key: "peripherals-mouse",
      label: "Mouse"
    },
    {
      key: "peripherals-gamepads",
      label: "Gamepads"
    }
  ]

  SettingsHubList {
    visible: root.page === "peripherals"
    items: root.sections
    onActivated: key => root.requestGo(key)
  }
}
