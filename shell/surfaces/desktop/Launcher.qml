import Quickshell
import Quickshell.Widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../shared"

Item {
  id: root

  property bool showUnavailable: search.text.trim().length > 0

  readonly property var filtered: {
    // Re-evaluate when hardware caps change
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
    color: Theme.bgElevated
    radius: Theme.radiusLg + 2
    border.width: 1
    border.color: Theme.border

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: 14
      spacing: 10

      TextField {
        id: search
        Layout.fillWidth: true
        Layout.preferredHeight: 40
        placeholderText: "Search apps…"
        color: Theme.text
        placeholderTextColor: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: 15
        focus: ShellState.launcherOpen
        background: Rectangle {
          radius: Theme.radius
          color: Theme.bgPanel
          border.width: 1
          border.color: search.activeFocus ? Theme.accent : Theme.border
        }
        onTextChanged: list.currentIndex = 0
        Keys.onEscapePressed: ShellState.closeLauncher()
        Keys.onDownPressed: list.incrementCurrentIndex()
        Keys.onUpPressed: list.decrementCurrentIndex()
        Keys.onReturnPressed: root.launchIndex(list.currentIndex)
        Keys.onEnterPressed: root.launchIndex(list.currentIndex)
      }

      ListView {
        id: list
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        spacing: 2
        model: root.filtered
        currentIndex: 0
        highlightMoveDuration: 80
        keyNavigationEnabled: true
        focus: true

        delegate: Rectangle {
          required property var modelData
          required property int index
          width: list.width
          height: 44
          radius: Theme.radius
          opacity: modelData.blocked ? 0.55 : 1
          color: list.currentIndex === index ? Theme.accentSoft : "transparent"

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: Theme.spaceMd

            IconImage {
              Layout.preferredWidth: 22
              Layout.preferredHeight: 22
              source: Quickshell.iconPath(modelData.entry.icon || "application-x-executable")
            }

            ColumnLayout {
              Layout.fillWidth: true
              spacing: 0

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
          text: search.text.trim().length ? "No apps match that search." : "No applications found."
          color: Theme.textMute
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSize
        }
      }

      Text {
        Layout.fillWidth: true
        text: {
          const n = filtered.length
          const hint = search.text.trim().length ? " · unavailable shown when searching" : ""
          return n + " apps" + hint + " · Esc to close · Enter to launch"
        }
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: 11
        horizontalAlignment: Text.AlignHCenter
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
