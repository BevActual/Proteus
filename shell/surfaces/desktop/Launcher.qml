import Quickshell
import Quickshell.Widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../shared"

// Spotlight-like launcher — soft card, search first, calm rows.
Item {
  id: root

  property bool showUnavailable: search.text.trim().length > 0

  readonly property var filtered: {
    const _caps = Hardware.capabilityList
    const q = search.text.trim().toLowerCase()
    const apps = DesktopEntries.applications.values
    const available = []
    const blocked = []
    for (let i = 0; i < apps.length; i++) {
      const a = apps[i]
      if (!a || !a.name)
        continue
      if (q.length) {
        const hay = (a.name + " " + (a.genericName || "") + " " + (a.keywords || []).join(" ")).toLowerCase()
        if (hay.indexOf(q) === -1)
          continue
      }
      if (EnvGate.appAvailable(a))
        available.push({
          entry: a,
          blocked: false,
          reason: ""
        })
      else if (q.length)
        blocked.push({
          entry: a,
          blocked: true,
          reason: EnvGate.appBlockReason(a)
        })
    }
    const byName = (x, y) => x.entry.name.localeCompare(y.entry.name)
    available.sort(byName)
    blocked.sort(byName)
    const out = available.concat(root.showUnavailable ? blocked : [])
    return out.slice(0, 40)
  }

  function launchIndex(i) {
    if (i < 0 || i >= filtered.length)
      return
    const row = filtered[i]
    if (row.blocked)
      return
    row.entry.execute()
    ShellState.closeLauncher()
    search.text = ""
    list.currentIndex = 0
  }

  Rectangle {
    anchors.fill: parent
    color: Theme.elevatedFill
    radius: Theme.radiusXl
    border.width: 0
    clip: true

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Theme.spaceMd
      spacing: Theme.spaceSm

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 44
        radius: Theme.radiusLg
        color: Theme.chromeClear ? Theme.bgHover : Theme.panelFill
        border.width: 0

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: Theme.spaceMd
          anchors.rightMargin: Theme.spaceMd
          spacing: Theme.spaceSm

          Text {
            text: "⌕"
            color: Theme.textMute
            font.pixelSize: 16
          }

          TextField {
            id: search
            Layout.fillWidth: true
            Layout.fillHeight: true
            placeholderText: "Search"
            color: Theme.text
            placeholderTextColor: Theme.textMute
            font.family: Theme.fontFamily
            font.pixelSize: 16
            focus: ShellState.launcherOpen
            background: Item {}
            onTextChanged: list.currentIndex = 0
            Keys.onEscapePressed: ShellState.closeLauncher()
            Keys.onDownPressed: list.incrementCurrentIndex()
            Keys.onUpPressed: list.decrementCurrentIndex()
            Keys.onReturnPressed: root.launchIndex(list.currentIndex)
            Keys.onEnterPressed: root.launchIndex(list.currentIndex)
          }
        }
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: Theme.separator
        opacity: Theme.chromeClear ? 0.35 : 0.8
      }

      ListView {
        id: list
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        spacing: 1
        model: root.filtered
        currentIndex: 0
        highlightMoveDuration: 80
        keyNavigationEnabled: true
        focus: true

        delegate: Item {
          required property var modelData
          required property int index
          width: list.width
          height: 46

          Rectangle {
            anchors.fill: parent
            radius: Theme.radiusMd
            opacity: modelData.blocked ? 0.5 : 1
            color: list.currentIndex === index ? Theme.chromeAccentSoft : (rowMa.containsMouse ? Theme.chromeHover : "transparent")
          }

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.spaceMd
            anchors.rightMargin: Theme.spaceMd
            spacing: Theme.spaceMd

            Rectangle {
              Layout.preferredWidth: 28
              Layout.preferredHeight: 28
              radius: Theme.radiusSm
              color: Theme.chromeHover
              border.width: 0

              IconImage {
                anchors.centerIn: parent
                width: 18
                height: 18
                source: Quickshell.iconPath(modelData.entry.icon || "application-x-executable")
              }
            }

            ColumnLayout {
              Layout.fillWidth: true
              spacing: 1

              Text {
                Layout.fillWidth: true
                text: modelData.entry.name
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                elide: Text.ElideRight
              }

              Text {
                Layout.fillWidth: true
                visible: modelData.blocked || !!(modelData.entry.genericName && modelData.entry.genericName.length)
                text: modelData.blocked ? modelData.reason : (modelData.entry.genericName || "")
                color: modelData.blocked ? Theme.danger : Theme.textMute
                font.family: Theme.fontFamily
                font.pixelSize: 11
                elide: Text.ElideRight
              }
            }
          }

          MouseArea {
            id: rowMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: modelData.blocked ? Qt.ForbiddenCursor : Qt.PointingHandCursor
            onEntered: list.currentIndex = index
            onClicked: root.launchIndex(index)
          }
        }

        Text {
          anchors.centerIn: parent
          width: parent.width - Theme.spaceXl
          visible: root.filtered.length === 0
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
          text: search.text.trim().length ? "No apps match." : "No applications found."
          color: Theme.textMute
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSize
        }
      }
    }
  }

  Connections {
    target: ShellState
    function onLauncherOpenChanged() {
      if (ShellState.launcherOpen) {
        search.text = ""
        list.currentIndex = 0
        search.forceActiveFocus()
      }
    }
  }
}
