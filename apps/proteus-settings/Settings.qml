import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "shared"
import "kit"

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
      key: "style-icons",
      label: "Icons"
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
    },
    {
      key: "desktop-launcher",
      label: "Launcher"
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
      label: "Repos"
    },
    {
      key: "packages-aur",
      label: "AUR"
    },
    {
      key: "packages-flatpak",
      label: "Flathub"
    },
    {
      key: "packages-appimages",
      label: "AppImages"
    },
    {
      key: "packages-orphans",
      label: "Orphans"
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
      key: "sound-matrix",
      label: "Mixer"
    },
    {
      key: "sound-latency",
      label: "Latency & buffer"
    }
  ]

  readonly property var networkChildren: [
    {
      key: "network-machine",
      label: "This machine"
    },
    {
      key: "network-devices",
      label: "Devices"
    },
    {
      key: "network-wifi",
      label: "Wi‑Fi"
    },
    {
      key: "network-bluetooth",
      label: "Bluetooth"
    },
    {
      key: "network-localsend",
      label: "LocalSend"
    },
    {
      key: "network-tailscale",
      label: "Tailscale"
    },
    {
      key: "network-vpn",
      label: "VPN"
    }
  ]

  // Every hub's leaf pages, flattened — the title lookup used to walk each
  // list separately, so adding a hub meant another near-identical loop.
  readonly property var allChildren: styleChildren
      .concat(desktopChildren, peripheralsChildren, packagesChildren, soundChildren, networkChildren)

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

  // Key capture for Keyboard leaf is owned by KeyboardPane (avoids loading
  // Keybinds on every Settings cold start).

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
          ScrollBar.vertical.policy: root.page === "sound-matrix"
              ? ScrollBar.AlwaysOff
              : ScrollBar.AsNeeded
          contentWidth: availableWidth

          // Sticky loaders: cold start only builds the active category (source: defers QML compile).
          ColumnLayout {
            width: scroll.availableWidth
            // Mixer leaf scrolls itself — pin content to the viewport so the shell doesn’t.
            height: root.page === "sound-matrix" ? scroll.availableHeight : undefined
            spacing: 0

            StickyPaneLoader {
              want: root.section === "style"
              asyncLoad: false
              source: "panes/StylePane.qml"
              onLoaded: {
                item.page = Qt.binding(() => root.page)
                item.requestGo.connect(id => SettingsNav.go(id))
              }
            }
            StickyPaneLoader {
              want: root.section === "desktop"
              source: "panes/DesktopPane.qml"
              onLoaded: {
                item.page = Qt.binding(() => root.page)
                item.requestGo.connect(id => SettingsNav.go(id))
              }
            }
            StickyPaneLoader {
              want: root.page === "displays"
              source: "panes/DisplaysPane.qml"
              onLoaded: item.active = Qt.binding(() => root.page === "displays")
            }
            StickyPaneLoader {
              want: root.section === "peripherals" && root.page === "peripherals"
              source: "panes/PeripheralsPane.qml"
              onLoaded: {
                item.page = Qt.binding(() => root.page)
                item.requestGo.connect(id => SettingsNav.go(id))
              }
            }
            StickyPaneLoader {
              want: root.page === "peripherals-keyboard"
              source: "panes/KeyboardPane.qml"
              onLoaded: item.focusHost = root
            }
            StickyPaneLoader {
              want: root.page === "peripherals-mouse"
              source: "panes/MousePane.qml"
            }
            StickyPaneLoader {
              want: root.section === "packages"
              source: "panes/PackagesPane.qml"
              onLoaded: {
                item.page = Qt.binding(() => root.page)
                item.requestGo.connect(id => SettingsNav.go(id))
              }
            }
            StickyPaneLoader {
              want: root.section === "sound"
              Layout.fillHeight: root.page === "sound-matrix"
              Layout.minimumHeight: root.page === "sound-matrix" ? 320 : 0
              source: "panes/SoundPane.qml"
              onLoaded: {
                item.page = Qt.binding(() => root.page)
                item.requestGo.connect(id => SettingsNav.go(id))
              }
            }
            StickyPaneLoader {
              want: root.section === "network"
              source: "panes/NetworkPane.qml"
              onLoaded: {
                item.page = Qt.binding(() => root.page)
                item.requestGo.connect(id => SettingsNav.go(id))
              }
            }
            StickyPaneLoader {
              want: root.page === "power"
              source: "panes/PowerPane.qml"
              onLoaded: item.active = Qt.binding(() => root.page === "power")
            }
            StickyPaneLoader {
              want: root.page === "users"
              source: "panes/UsersPane.qml"
              onLoaded: item.active = Qt.binding(() => root.page === "users")
            }
            StickyPaneLoader {
              want: root.page === "accounts"
              source: "panes/AccountsPane.qml"
              onLoaded: item.active = Qt.binding(() => root.page === "accounts")
            }
            StickyPaneLoader {
              want: root.page === "datetime"
              source: "panes/DateTimePane.qml"
              onLoaded: item.active = Qt.binding(() => root.page === "datetime")
            }
            StickyPaneLoader {
              want: root.page === "privacy"
              source: "panes/PrivacyPane.qml"
              onLoaded: item.active = Qt.binding(() => root.page === "privacy")
            }
            StickyPaneLoader {
              want: root.page === "system"
              source: "panes/SystemPane.qml"
              onLoaded: {
                item.active = Qt.binding(() => root.page === "system")
                item.requestGo.connect(id => SettingsNav.go(id))
              }
            }
          }
        }
      }
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
    if (SettingsNav.back())
      return
    SettingsNav.close()
  }
}
