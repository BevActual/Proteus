import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "shared"
import "panes"

Item {
  id: root

  readonly property var panes: {
    const _ = Hardware.capabilityList
    const __ = Hardware.ready
    return EnvGate.availableSettingsPanes()
  }

  readonly property string page: SettingsNav.page
  readonly property string section: SettingsNav.section
  readonly property bool showBack: SettingsNav.canGoBack

  readonly property var styleChildren: [
    {
      key: "style-accent",
      label: "Accent color"
    },
    {
      key: "style-background",
      label: "Background"
    },
    {
      key: "style-font",
      label: "Font"
    }
  ]

  readonly property var desktopChildren: [
    {
      key: "desktop-gaps",
      label: "Gaps"
    },
    {
      key: "desktop-chrome",
      label: "Borders & rounding"
    },
    {
      key: "desktop-motion",
      label: "Motion"
    },
    {
      key: "desktop-dock",
      label: "Dock"
    }
  ]

  readonly property var peripheralsChildren: [
    {
      key: "peripherals-keyboard",
      label: "Keyboard"
    },
    {
      key: "peripherals-mouse",
      label: "Mouse"
    }
  ]

  readonly property var packagesChildren: [
    {
      key: "packages-updates",
      label: "Updates"
    },
    {
      key: "packages-search",
      label: "Search"
    }
  ]

  readonly property string pageTitle: {
    const p = page
    for (let i = 0; i < styleChildren.length; i++) {
      if (styleChildren[i].key === p)
        return styleChildren[i].label
    }
    for (let d = 0; d < desktopChildren.length; d++) {
      if (desktopChildren[d].key === p)
        return desktopChildren[d].label
    }
    for (let k = 0; k < peripheralsChildren.length; k++) {
      if (peripheralsChildren[k].key === p)
        return peripheralsChildren[k].label
    }
    for (let g = 0; g < packagesChildren.length; g++) {
      if (packagesChildren[g].key === p)
        return packagesChildren[g].label
    }
    for (let j = 0; j < panes.length; j++) {
      if (panes[j].id === p)
        return panes[j].label
    }
    return "Settings"
  }

  focus: Keybinds.recordingId.length > 0 && page === "peripherals-keyboard"
  Keys.onPressed: event => Keybinds.handleKeyEvent(event)

  Rectangle {
    anchors.fill: parent
    color: Theme.bgElevated
    radius: Theme.radiusXl
    border.width: 1
    border.color: Theme.border
    clip: true

    RowLayout {
      anchors.fill: parent
      spacing: 0

      Rectangle {
        Layout.preferredWidth: 176
        Layout.fillHeight: true
        color: Theme.bgPanel

          ColumnLayout {
          anchors.fill: parent
          anchors.margins: Theme.spaceMd
          spacing: 2

          Text {
            text: "Settings"
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 15
            font.bold: true
            Layout.bottomMargin: 8
          }

          Repeater {
            model: root.panes

            Rectangle {
              required property var modelData
              Layout.fillWidth: true
              Layout.preferredHeight: 28
              radius: Theme.radiusSm
              color: root.section === modelData.id ? Theme.accentSoft : (navMa.containsMouse ? Theme.bgHover : "transparent")
              border.width: root.section === modelData.id ? 1 : 0
              border.color: Theme.accent

              Text {
                anchors.left: parent.left
                anchors.leftMargin: Theme.spaceMd
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.label
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
              }

              MouseArea {
                id: navMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: SettingsNav.goSection(modelData.id)
              }
            }
          }

          Item {
            Layout.fillHeight: true
          }

          Text {
            text: "Proteus"
            color: Theme.textMute
            font.family: Theme.fontFamily
            font.pixelSize: 11
          }
          Text {
            text: "Bevington Systems"
            color: Theme.textMute
            font.family: Theme.fontFamily
            font.pixelSize: 11
          }
        }
      }

      ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true

        RowLayout {
          Layout.fillWidth: true
          Layout.leftMargin: Theme.spaceLg
          Layout.rightMargin: Theme.spaceLg
          Layout.topMargin: 14
          spacing: 10

          Rectangle {
            visible: root.showBack
            Layout.preferredWidth: visible ? Math.max(78, backRow.implicitWidth + 22) : 0
            Layout.preferredHeight: 32
            radius: Theme.radius
            color: backMa.containsMouse ? Theme.bgHover : Theme.bgPanel
            border.width: 1
            border.color: Theme.accent

            Row {
              id: backRow
              anchors.centerIn: parent
              spacing: 4
              Text {
                text: "‹"
                color: Theme.accent
                font.pixelSize: 18
                font.bold: true
              }
              Text {
                text: SettingsNav.backLabel
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            MouseArea {
              id: backMa
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: SettingsNav.back()
            }
          }

          Text {
            Layout.fillWidth: true
            text: root.pageTitle
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 18
            font.bold: true
          }

          Rectangle {
            Layout.preferredWidth: 32
            Layout.preferredHeight: 32
            radius: Theme.radius
            color: closeMa.containsMouse ? Theme.bgHover : "transparent"
            border.width: 1
            border.color: Theme.border
            Text {
              anchors.centerIn: parent
              text: "✕"
              color: Theme.textDim
            }
            MouseArea {
              id: closeMa
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: SettingsNav.close()
            }
          }
        }

        ScrollView {
          id: scroll
          Layout.fillWidth: true
          Layout.fillHeight: true
          Layout.margins: Theme.spaceLg
          Layout.topMargin: Theme.spaceSm
          clip: true
          ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
          contentWidth: availableWidth

          // Exactly one pane — gated here, not inside panes/ (SettingsNav is unreliable there)
          ColumnLayout {
            width: scroll.availableWidth
            spacing: 0

            StylePane {
              Layout.fillWidth: true
              visible: root.section === "style"
              page: root.page
              onRequestGo: id => SettingsNav.go(id)
            }

            DesktopPane {
              Layout.fillWidth: true
              visible: root.section === "desktop"
              page: root.page
              onRequestGo: id => SettingsNav.go(id)
            }

            DisplaysPane {
              Layout.fillWidth: true
              visible: root.page === "displays"
              active: root.page === "displays"
            }

            PeripheralsPane {
              Layout.fillWidth: true
              visible: root.section === "peripherals" && root.page === "peripherals"
              page: root.page
              onRequestGo: id => SettingsNav.go(id)
            }

            KeyboardPane {
              Layout.fillWidth: true
              visible: root.page === "peripherals-keyboard"
              focusHost: root
            }

            MousePane {
              Layout.fillWidth: true
              visible: root.page === "peripherals-mouse"
            }

            PackagesPane {
              Layout.fillWidth: true
              visible: root.section === "packages" && root.page === "packages"
              page: root.page
              onRequestGo: id => SettingsNav.go(id)
            }

            PackagesUpdatesPane {
              Layout.fillWidth: true
              visible: root.page === "packages-updates"
              active: root.page === "packages-updates"
            }

            PackagesSearchPane {
              Layout.fillWidth: true
              visible: root.page === "packages-search"
              active: root.page === "packages-search"
            }

            SoundPane {
              id: soundPane
              Layout.fillWidth: true
              visible: root.page === "sound"
              active: root.page === "sound"
            }

            NetworkPane {
              Layout.fillWidth: true
              visible: root.page === "network"
              active: root.page === "network"
            }

            SystemPane {
              Layout.fillWidth: true
              visible: root.page === "system"
            }
          }
        }
      }
    }
  }

  Connections {
    target: SettingsNav
    function onPageChanged() {
      if (SettingsNav.page !== "peripherals-keyboard" && Keybinds.recordingId.length)
        Keybinds.cancelRecording()
    }
  }

  function ensureSettingsPageValid(nav) {
    EnvGate.ensureSettingsPageValid(nav || SettingsNav)
  }

  Component.onCompleted: {
    root.ensureSettingsPageValid()
  }

  Connections {
    target: Hardware
    function onReadyChanged() {
      root.ensureSettingsPageValid()
    }
    function onCapabilityListChanged() {
      root.ensureSettingsPageValid()
    }
  }

  Keys.onEscapePressed: {
    if (Keybinds.recordingId.length) {
      Keybinds.cancelRecording()
      return
    }
    if (SettingsNav.back())
      return
    SettingsNav.close()
  }
}
