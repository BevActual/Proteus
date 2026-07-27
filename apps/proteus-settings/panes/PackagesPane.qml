import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../shared"

// Packages category — Updates · Search.
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: 12

  property string page: "packages"
  signal requestGo(string id)

  readonly property string updatesValue: {
    const n = Config.packageUpgradeCount
    if (n < 0)
      return ""
    if (n === 0)
      return "Up to date"
    return n + " pending"
  }

  readonly property var sections: [
    {
      key: "packages-updates",
      label: "Updates",
      hint: "Pending upgrades from the local sync DB"
    },
    {
      key: "packages-search",
      label: "Search",
      hint: "Find packages in the repos"
    }
  ]

  function valueFor(key) {
    if (key === "packages-updates")
      return root.updatesValue
    return ""
  }

  function warmCount() {
    if (Config.packageUpgradeCount >= 0)
      return
    warmCheck.running = false
    warmCheck.running = true
  }

  ColumnLayout {
    visible: root.page === "packages"
    Layout.fillWidth: true
    Layout.maximumWidth: 420
    spacing: 6

    Text {
      Layout.fillWidth: true
      text: "Arch packages via pacman. Changes propose here, then confirm in a terminal."
      color: Theme.textMute
      font.family: Theme.fontFamily
      font.pixelSize: 12
      wrapMode: Text.WordWrap
      Layout.bottomMargin: 2
    }

    Repeater {
      model: root.sections

      Rectangle {
        required property var modelData
        Layout.fillWidth: true
        Layout.preferredHeight: 44
        radius: Theme.radiusMd
        color: rowMa.containsMouse ? Theme.bgHover : Theme.bgPanel
        border.width: 1
        border.color: Theme.border

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: Theme.spaceMd
          anchors.rightMargin: Theme.spaceMd
          spacing: Theme.spaceSm

          ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            Text {
              text: modelData.label
              color: Theme.text
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSize
            }
            Text {
              text: modelData.hint
              color: Theme.textMute
              font.family: Theme.fontFamily
              font.pixelSize: 11
            }
          }

          Text {
            visible: root.valueFor(modelData.key).length > 0
            text: root.valueFor(modelData.key)
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: 11
          }

          Text {
            text: "›"
            color: Theme.textDim
            font.pixelSize: 16
          }
        }

        MouseArea {
          id: rowMa
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.requestGo(modelData.key)
        }
      }
    }
  }

  onPageChanged: {
    if (page === "packages")
      warmCount()
  }

  Component.onCompleted: {
    if (page === "packages")
      warmCount()
  }

  Process {
    id: warmCheck
    command: ["pacman", "-Qu"]
    stdout: StdioCollector {
      onStreamFinished: {
        const lines = text.trim().split("\n").filter(l => l.length && l.indexOf("->") >= 0)
        Config.notePackageUpgrades(lines.length)
      }
    }
  }
}
