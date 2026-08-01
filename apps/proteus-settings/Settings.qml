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
      label: "Beacon"
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
    },
    {
      key: "peripherals-gamepads",
      label: "Gamepads"
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
      key: "packages-webapps",
      label: "Web apps"
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
      key: "network-diagnostics",
      label: "Diagnostics"
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

  // Maximized / tiled windows: cap + center the pane column instead of pinning
  // a narrow card against the sidebar with a void to the right. The Mixer grid
  // is a full-bleed surface and keeps the whole width.
  readonly property int paneMaxW: 760
  readonly property bool paneFullBleed: page === "sound-matrix"
  readonly property real paneCenterPad: paneFullBleed
      ? 0
      : Math.max(0, (scroll.availableWidth - paneMaxW) / 2)

  // In-app `/` jump — type to go to a category or leaf without leaving the window.
  property bool jumpOpen: false
  property string jumpQuery: ""
  property int jumpIndex: 0

  readonly property var jumpCatalog: {
    const out = []
    const seen = {}
    const panesList = root.panes || []
    for (let i = 0; i < panesList.length; i++) {
      const p = panesList[i]
      const id = String(p.id || "")
      if (!id.length || seen[id])
        continue
      seen[id] = true
      out.push({
        id: id,
        label: String(p.label || id),
        kind: "category",
        keywords: String(p.keywords || "")
      })
    }
    const kids = root.allChildren || []
    for (let j = 0; j < kids.length; j++) {
      const c = kids[j]
      const key = String(c.key || "")
      if (!key.length || seen[key])
        continue
      seen[key] = true
      out.push({
        id: key,
        label: String(c.label || key),
        kind: "leaf",
        keywords: ""
      })
    }
    return out
  }

  readonly property var jumpHits: {
    const q = String(root.jumpQuery || "").trim().toLowerCase()
    const catalog = root.jumpCatalog
    if (!q.length)
      return catalog.slice(0, 12)
    const hits = []
    for (let i = 0; i < catalog.length; i++) {
      const row = catalog[i]
      const hay = (row.label + " " + row.id + " " + (row.keywords || "")).toLowerCase()
      if (hay.indexOf(q) >= 0)
        hits.push(row)
    }
    return hits
  }

  function openJump() {
    jumpQuery = ""
    jumpIndex = 0
    jumpOpen = true
    Qt.callLater(() => {
      if (jumpField)
        jumpField.forceActiveFocus()
    })
  }

  function closeJump() {
    jumpOpen = false
    jumpQuery = ""
    jumpIndex = 0
    root.forceActiveFocus()
  }

  function moveJump(delta) {
    const n = jumpHits.length
    if (n <= 0) {
      jumpIndex = 0
      return
    }
    jumpIndex = (jumpIndex + delta + n) % n
  }

  function activateJump() {
    const hits = jumpHits
    if (jumpIndex < 0 || jumpIndex >= hits.length)
      return
    const row = hits[jumpIndex]
    if (!row || !row.id)
      return
    SettingsNav.go(row.id)
    closeJump()
  }

  // Key capture for Keyboard leaf is owned by KeyboardPane (avoids loading
  // Keybinds on every Settings cold start).

  focus: true

  Keys.onPressed: event => {
    if (root.jumpOpen)
      return
    if (event.key === Qt.Key_Slash
        && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
      root.openJump()
      event.accepted = true
    }
  }

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
          // Back/title track the centered pane column; ✕ stays at the corner.
          Layout.leftMargin: Theme.spaceLg + root.paneCenterPad
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
            width: root.paneFullBleed
                ? scroll.availableWidth
                : Math.min(scroll.availableWidth, root.paneMaxW)
            x: Math.round(root.paneCenterPad)
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
              want: root.page === "peripherals-gamepads"
              source: "panes/GamepadsPane.qml"
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
              onLoaded: {
                item.active = Qt.binding(() => root.page === "users")
                item.requestGo.connect(id => SettingsNav.go(id))
              }
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
              onLoaded: {
                item.active = Qt.binding(() => root.page === "privacy")
                item.requestGo.connect(id => SettingsNav.go(id))
              }
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
    root.forceActiveFocus()
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
    if (root.jumpOpen) {
      root.closeJump()
      return
    }
    if (SettingsNav.back())
      return
    SettingsNav.close()
  }

  // `/` jump overlay — dim + typeahead over the window.
  Rectangle {
    anchors.fill: parent
    visible: root.jumpOpen
    z: 100
    color: Qt.rgba(0, 0, 0, 0.35)

    MouseArea {
      anchors.fill: parent
      onClicked: root.closeJump()
    }

    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: parent.top
      anchors.topMargin: 72
      width: Math.min(420, parent.width - 48)
      radius: Theme.radiusLg
      color: Theme.bgElevated
      border.width: 1
      border.color: Theme.separator
      implicitHeight: jumpCol.implicitHeight + Theme.spaceMd * 2

      MouseArea {
        anchors.fill: parent
        // swallow clicks so backdrop doesn't close while interacting
      }

      ColumnLayout {
        id: jumpCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.spaceMd
        spacing: Theme.spaceSm

        Text {
          text: "Go to…"
          color: Theme.textMute
          font.family: Theme.fontFamily
          font.pixelSize: 12
        }

        TextField {
          id: jumpField
          Layout.fillWidth: true
          placeholderText: "Category or page"
          text: root.jumpQuery
          color: Theme.text
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSize
          selectByMouse: true
          onTextChanged: {
            root.jumpQuery = text
            root.jumpIndex = 0
          }
          Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
              root.closeJump()
              event.accepted = true
            } else if (event.key === Qt.Key_Down) {
              root.moveJump(1)
              event.accepted = true
            } else if (event.key === Qt.Key_Up) {
              root.moveJump(-1)
              event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.activateJump()
              event.accepted = true
            }
          }
          background: Rectangle {
            radius: Theme.radiusMd
            color: Theme.bg
            border.width: 1
            border.color: jumpField.activeFocus ? Theme.accent : Theme.separator
          }
        }

        Repeater {
          model: root.jumpHits

          Rectangle {
            required property var modelData
            required property int index
            readonly property bool selected: index === root.jumpIndex
            Layout.fillWidth: true
            Layout.preferredHeight: 34
            radius: Theme.radiusMd
            color: selected ? Theme.accentSoft : (jumpRowMa.containsMouse ? Theme.bgHover : "transparent")

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: Theme.spaceMd
              anchors.rightMargin: Theme.spaceMd
              spacing: Theme.spaceSm

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
                text: modelData.kind === "category" ? "Category" : "Page"
                color: Theme.textMute
                font.family: Theme.fontFamily
                font.pixelSize: 11
              }
            }

            MouseArea {
              id: jumpRowMa
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.jumpIndex = index
                root.activateJump()
              }
              onContainsMouseChanged: {
                if (containsMouse)
                  root.jumpIndex = index
              }
            }
          }
        }

        Text {
          visible: root.jumpHits.length === 0
          Layout.fillWidth: true
          text: "No matches"
          color: Theme.textMute
          font.family: Theme.fontFamily
          font.pixelSize: 12
        }

        Text {
          Layout.fillWidth: true
          text: "↑↓ · Enter · Esc"
          color: Theme.textMute
          font.family: Theme.fontFamily
          font.pixelSize: 11
        }
      }
    }
  }
}
