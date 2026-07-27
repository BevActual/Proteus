import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../shared"

// Packages → Search: pacman -Ss; propose → confirm → pkexec proteus-pkg install.
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: 12

  property bool active: false
  property var results: []
  property string status: "Type a name and search."
  property bool busy: false
  property string query: ""
  property string pendingPkg: ""
  property string pendingDetail: ""

  readonly property bool confirming: pendingPkg.length > 0
  readonly property bool applying: Config.packageOpBusy

  function clearPending() {
    pendingPkg = ""
    pendingDetail = ""
  }

  function search() {
    clearPending()
    const q = query.trim()
    if (!q.length) {
      status = "Enter a search term."
      results = []
      return
    }
    busy = true
    status = "Searching…"
    results = []
    searchProc.command = ["pacman", "-Ss", "--", q]
    searchProc.running = false
    searchProc.running = true
  }

  Text {
    Layout.fillWidth: true
    text: "Search the sync databases. Install proposes here, then authenticates via polkit."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 12
    wrapMode: Text.WordWrap
  }

  PackagesConfirm {
    open: root.confirming
    title: "Install package?"
    detail: root.pendingDetail
    onCancelled: root.clearPending()
    onConfirmed: {
      const pkg = root.pendingPkg
      root.clearPending()
      Config.openPacmanInstall(pkg)
    }
  }

  Text {
    Layout.fillWidth: true
    visible: root.applying
    text: Config.packageOpStatus
    color: Theme.textDim
    font.family: Theme.fontFamily
    font.pixelSize: 12
    wrapMode: Text.WordWrap
  }

  RowLayout {
    Layout.fillWidth: true
    Layout.maximumWidth: 520
    spacing: Theme.spaceSm
    visible: !root.confirming

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 36
      radius: Theme.radius
      color: Theme.bgPanel
      border.width: 1
      border.color: searchInput.activeFocus ? Theme.accent : Theme.border
      TextInput {
        id: searchInput
        anchors.fill: parent
        anchors.leftMargin: Theme.spaceMd
        anchors.rightMargin: Theme.spaceMd
        verticalAlignment: TextInput.AlignVCenter
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        selectByMouse: true
        clip: true
        text: root.query
        onTextChanged: root.query = text
        Keys.onReturnPressed: root.search()
        Keys.onEnterPressed: root.search()
        Text {
          anchors.fill: parent
          verticalAlignment: Text.AlignVCenter
          text: "Search packages…"
          color: Theme.textMute
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSize
          visible: !searchInput.text.length && !searchInput.activeFocus
        }
      }
    }

    Rectangle {
      Layout.preferredWidth: 88
      Layout.preferredHeight: 36
      radius: Theme.radius
      color: Theme.accentSoft
      border.width: 1
      border.color: Theme.accent
      opacity: root.busy ? 0.6 : 1
      Text {
        anchors.centerIn: parent
        text: root.busy ? "…" : "Search"
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: 12
        font.bold: true
      }
      MouseArea {
        anchors.fill: parent
        enabled: !root.busy
        cursorShape: Qt.PointingHandCursor
        onClicked: root.search()
      }
    }
  }

  Text {
    Layout.fillWidth: true
    text: root.status
    color: Theme.textDim
    font.family: Theme.fontFamily
    font.pixelSize: 12
    wrapMode: Text.WordWrap
    visible: root.results.length === 0 && !root.confirming
  }

  Repeater {
    model: root.results

    Rectangle {
      required property var modelData
      Layout.fillWidth: true
      Layout.maximumWidth: 520
      Layout.preferredHeight: pkgCol.implicitHeight + 20
      radius: Theme.radiusMd
      color: Theme.bgPanel
      border.width: 1
      border.color: Theme.border
      visible: !root.confirming

      ColumnLayout {
        id: pkgCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.spaceMd
        spacing: 6

        RowLayout {
          Layout.fillWidth: true
          Text {
            Layout.fillWidth: true
            text: modelData.repo + "/" + modelData.name
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.bold: true
            elide: Text.ElideRight
          }
          Text {
            text: modelData.version
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: 11
          }
        }

        Text {
          Layout.fillWidth: true
          text: modelData.desc
          color: Theme.textMute
          font.family: Theme.fontFamily
          font.pixelSize: 11
          wrapMode: Text.WordWrap
          visible: modelData.desc.length > 0
        }

        Rectangle {
          Layout.preferredWidth: installLab.implicitWidth + 20
          Layout.preferredHeight: 28
          radius: Theme.radiusSm
          color: Theme.accentSoft
          border.width: 1
          border.color: Theme.accent
          Text {
            id: installLab
            anchors.centerIn: parent
            text: "Install…"
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 11
          }
          MouseArea {
            anchors.fill: parent
            enabled: !root.applying
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.pendingPkg = modelData.name
              root.pendingDetail = "Install " + modelData.repo + "/" + modelData.name + " (" + modelData.version + ") via proteus-pkg install (polkit)."
            }
          }
        }
      }
    }
  }

  Text {
    Layout.fillWidth: true
    text: "Fact: pacman -Ss · Apply: pkexec proteus-pkg install <pkg>"
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }

  Connections {
    target: Config
    function onPackageOpFinished(ok, message) {
      if (!root.active)
        return
      root.status = message
      if (ok && root.query.trim().length)
        root.search()
    }
  }

  Process {
    id: searchProc
    command: ["true"]
    stdout: StdioCollector {
      onStreamFinished: {
        const lines = text.split("\n")
        const out = []
        let cur = null
        for (let i = 0; i < lines.length; i++) {
          const line = lines[i]
          const head = line.match(/^([a-z0-9_-]+)\/(\S+)\s+(\S+)/)
          if (head) {
            if (cur)
              out.push(cur)
            cur = {
              repo: head[1],
              name: head[2],
              version: head[3],
              desc: ""
            }
            continue
          }
          if (cur && line.match(/^\s+/)) {
            cur.desc = line.trim()
          }
        }
        if (cur)
          out.push(cur)
        root.results = out.slice(0, 40)
        root.busy = false
        root.status = out.length ? "" : "No packages matched."
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        if (text.trim().length && root.results.length === 0) {
          root.busy = false
          root.status = text.trim().split("\n")[0]
        }
      }
    }
  }

  onActiveChanged: {
    if (!active)
      clearPending()
  }
}
