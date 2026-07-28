import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "shared"
import "kit"
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
      label: "Accent & chrome"
    },
    {
      key: "style-background",
      label: "Background"
    },
    {
      key: "style-lock",
      label: "Lock screen"
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
      label: "Dock & menu bar"
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

  readonly property var soundChildren: [
    {
      key: "sound-output",
      label: "Output"
    },
    {
      key: "sound-input",
      label: "Input"
    },
    {
      key: "sound-apps",
      label: "Applications"
    },
    {
      key: "sound-latency",
      label: "Latency & buffer"
    }
  ]

  // Every hub's leaf pages, flattened — the title lookup used to walk each
  // list separately, so adding a hub meant another near-identical loop.
  readonly property var allChildren: styleChildren
      .concat(desktopChildren, peripheralsChildren, packagesChildren, soundChildren)

  readonly property string pageTitle: {
    const p = page
    for (let i = 0; i < allChildren.length; i++) {
      if (allChildren[i].key === p)
        return allChildren[i].label
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
    color: Theme.bg
    radius: Theme.radiusXl
    border.width: 0
    clip: true

    RowLayout {
      anchors.fill: parent
      spacing: 0

      Rectangle {
        Layout.preferredWidth: 200
        Layout.fillHeight: true
        color: Theme.bgPanel

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: Theme.spaceMd
          spacing: 1

          Text {
            text: "Settings"
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 20
            font.bold: true
            Layout.leftMargin: Theme.spaceSm
            Layout.bottomMargin: Theme.spaceMd
            Layout.topMargin: Theme.spaceXs
          }

          Repeater {
            model: root.panes

            Rectangle {
              required property var modelData
              readonly property bool unfinished: modelData.status === "stub" || modelData.status === "planned" || modelData.status === "partial"
              readonly property bool selected: root.section === modelData.id
              Layout.fillWidth: true
              Layout.preferredHeight: 32
              radius: Theme.radiusMd
              color: selected ? Theme.accentSoft : (navMa.containsMouse ? Theme.bgHover : "transparent")
              border.width: 0

              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.spaceMd
                anchors.rightMargin: Theme.spaceSm
                spacing: 4

                Text {
                  Layout.fillWidth: true
                  text: modelData.label
                  color: selected ? Theme.accent : Theme.text
                  font.family: Theme.fontFamily
                  font.pixelSize: Theme.fontSize
                  font.bold: selected
                  elide: Text.ElideRight
                }

                Text {
                  visible: unfinished
                  text: modelData.status === "partial" ? "…" : "·"
                  color: Theme.textMute
                  font.family: Theme.fontFamily
                  font.pixelSize: 11
                }
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
            Layout.leftMargin: Theme.spaceSm
            text: "Proteus"
            color: Theme.textMute
            font.family: Theme.fontFamily
            font.pixelSize: 11
          }
          Text {
            Layout.leftMargin: Theme.spaceSm
            text: "Bevington Systems"
            color: Theme.textMute
            font.family: Theme.fontFamily
            font.pixelSize: 11
          }
        }
      }

      Rectangle {
        Layout.preferredWidth: 1
        Layout.fillHeight: true
        color: Theme.separator
      }

      ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true

        RowLayout {
          Layout.fillWidth: true
          Layout.leftMargin: Theme.spaceLg
          Layout.rightMargin: Theme.spaceLg
          Layout.topMargin: Theme.spaceLg
          spacing: Theme.spaceMd

          Text {
            visible: root.showBack
            text: "‹ " + SettingsNav.backLabel
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.bold: true
            MouseArea {
              anchors.fill: parent
              anchors.margins: -6
              cursorShape: Qt.PointingHandCursor
              onClicked: SettingsNav.back()
            }
          }

          Text {
            Layout.fillWidth: true
            text: root.pageTitle
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 22
            font.bold: true
          }

          Rectangle {
            Layout.preferredWidth: 28
            Layout.preferredHeight: 28
            radius: 14
            color: closeMa.containsMouse ? Theme.bgHover : "transparent"
            border.width: 0
            Text {
              anchors.centerIn: parent
              text: "✕"
              color: Theme.textDim
              font.pixelSize: 12
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
              visible: root.section === "sound"
              page: root.page
              onRequestGo: id => SettingsNav.go(id)
            }

            NetworkPane {
              Layout.fillWidth: true
              visible: root.page === "network"
              active: root.page === "network"
            }

            PowerPane {
              Layout.fillWidth: true
              visible: root.page === "power"
              active: root.page === "power"
            }

            PlannedPane {
              Layout.fillWidth: true
              visible: root.page === "users"
              status: "stub"
              summary: "Accounts and login. Session actions will move here from About."
              items: [
                {
                  label: "Local accounts",
                  hint: "List / add / remove users",
                  done: false
                },
                {
                  label: "Login & greeter",
                  hint: "greetd / autologin prefs",
                  done: false
                },
                {
                  label: "Session actions",
                  hint: "Lock · logout · reboot · shutdown",
                  done: false
                }
              ]
            }

            PlannedPane {
              Layout.fillWidth: true
              visible: root.page === "accounts"
              status: "stub"
              summary: "Mail, contacts, and cloud providers — not inventing those apps here."
              items: [
                {
                  label: "Mail providers",
                  hint: "Connect account for adaptive mail later",
                  done: false
                },
                {
                  label: "Contacts",
                  hint: "Provider sync hooks",
                  done: false
                },
                {
                  label: "Cloud storage",
                  hint: "Mount / sync providers",
                  done: false
                }
              ]
            }

            DateTimePane {
              Layout.fillWidth: true
              visible: root.page === "datetime"
              active: root.page === "datetime"
            }

            PlannedPane {
              Layout.fillWidth: true
              visible: root.page === "privacy"
              status: "stub"
              summary: "Permissions once adaptive apps need a grant model."
              items: [
                {
                  label: "App permissions",
                  hint: "Camera · mic · location · files",
                  done: false
                },
                {
                  label: "Screen recording",
                  hint: "Portal / capture grants",
                  done: false
                },
                {
                  label: "Diagnostics",
                  hint: "What leaves the machine",
                  done: false
                }
              ]
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
