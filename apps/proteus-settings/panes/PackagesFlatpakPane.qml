import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../shared"

// Packages → Flatpak: search / installed / install / remove / update (--user).
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: 12

  property bool active: false
  property var results: []
  property var installed: []
  property var remotes: []
  property string status: ""
  property bool busy: false
  property string query: ""
  property string pendingRef: ""
  property string pendingDetail: ""
  property string pendingAction: "" // install | remove | update | flathub

  readonly property bool confirming: pendingAction.length > 0
  readonly property bool applying: Packages.packageOpBusy
  readonly property bool flatpakOk: Packages.flatpakAvailable
  readonly property bool hasFlathub: {
    for (let i = 0; i < remotes.length; i++) {
      if (String(remotes[i]).toLowerCase() === "flathub")
        return true
    }
    return false
  }

  function clearPending() {
    pendingRef = ""
    pendingDetail = ""
    pendingAction = ""
  }

  function refreshMeta() {
    if (!flatpakOk)
      return
    remotesProc.running = false
    remotesProc.running = true
    installedProc.running = false
    installedProc.running = true
  }

  function search() {
    clearPending()
    if (!flatpakOk) {
      status = "Install flatpak to use Flatpak from Settings."
      results = []
      return
    }
    const q = query.trim()
    if (!q.length) {
      status = "Enter a search term."
      results = []
      return
    }
    busy = true
    status = "Searching Flatpak…"
    results = []
    searchProc.command = ["flatpak", "search", "--columns=application:f,name,version,description", q]
    searchProc.running = false
    searchProc.running = true
  }

  Text {
    Layout.fillWidth: true
    text: flatpakOk
        ? "Flatpak installs are --user by default. Remotes and apps stay in your home."
        : "Flatpak is not installed. Install the flatpak package, then reopen this page."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 12
    wrapMode: Text.WordWrap
  }

  PackagesConfirm {
    open: root.confirming
    title: root.pendingAction === "update" ? "Update Flatpaks?"
        : (root.pendingAction === "flathub" ? "Add Flathub?"
            : (root.pendingAction === "remove" ? "Remove Flatpak?" : "Install Flatpak?"))
    detail: root.pendingDetail
    footnote: "Runs flatpak as your user. Confirm here first."
    onCancelled: root.clearPending()
    onConfirmed: {
      const act = root.pendingAction
      const ref = root.pendingRef
      root.clearPending()
      if (act === "update")
        Packages.flatpakUpdate()
      else if (act === "flathub")
        Packages.flatpakAddFlathub()
      else if (act === "remove")
        Packages.flatpakRemove(ref)
      else
        Packages.flatpakInstall(ref)
    }
  }

  Text {
    Layout.fillWidth: true
    visible: root.applying
    text: Packages.packageOpStatus
    color: Theme.textDim
    font.family: Theme.fontFamily
    font.pixelSize: 12
    wrapMode: Text.WordWrap
  }

  RowLayout {
    Layout.fillWidth: true
    Layout.maximumWidth: 520
    spacing: Theme.spaceSm
    visible: root.flatpakOk && !root.confirming

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 40
      radius: Theme.radiusMd
      color: Theme.bgPanel
      border.width: 1
      border.color: Theme.border
      opacity: root.applying ? 0.6 : 1
      Text {
        anchors.centerIn: parent
        text: "Update…"
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: 12
      }
      MouseArea {
        anchors.fill: parent
        enabled: !root.applying
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          root.pendingAction = "update"
          root.pendingDetail = "Runs flatpak update -y --user."
        }
      }
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 40
      radius: Theme.radiusMd
      color: Theme.accentSoft
      border.width: 1
      border.color: Theme.accent
      visible: !root.hasFlathub
      opacity: root.applying ? 0.6 : 1
      Text {
        anchors.centerIn: parent
        text: "Add Flathub…"
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: 12
        font.bold: true
      }
      MouseArea {
        anchors.fill: parent
        enabled: !root.applying
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          root.pendingAction = "flathub"
          root.pendingDetail = "Adds the Flathub remote for your user (--if-not-exists)."
        }
      }
    }
  }

  RowLayout {
    Layout.fillWidth: true
    Layout.maximumWidth: 520
    spacing: Theme.spaceSm
    visible: root.flatpakOk && !root.confirming

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
          text: "Search Flatpak…"
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
    visible: !root.confirming && !root.applying
        && root.results.length === 0 && root.installed.length === 0
  }

  Text {
    visible: root.installed.length > 0 && !root.confirming
    text: "Installed"
    color: Theme.text
    font.family: Theme.fontFamily
    font.pixelSize: 13
    font.bold: true
  }

  Repeater {
    model: root.installed

    Rectangle {
      required property var modelData
      Layout.fillWidth: true
      Layout.maximumWidth: 520
      Layout.preferredHeight: instCol.implicitHeight + 20
      radius: Theme.radiusMd
      color: Theme.bgPanel
      border.width: 1
      border.color: Theme.border
      visible: !root.confirming

      ColumnLayout {
        id: instCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.spaceMd
        spacing: 6

        Text {
          Layout.fillWidth: true
          text: modelData.name
          color: Theme.text
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSize
          font.bold: true
          elide: Text.ElideRight
        }
        Text {
          Layout.fillWidth: true
          text: modelData.ref
          color: Theme.textMute
          font.family: Theme.fontFamily
          font.pixelSize: 11
          elide: Text.ElideMiddle
        }

        Rectangle {
          Layout.preferredWidth: remLab.implicitWidth + 20
          Layout.preferredHeight: 28
          radius: Theme.radiusSm
          color: Theme.bgElevated
          border.width: 1
          border.color: Theme.border
          Text {
            id: remLab
            anchors.centerIn: parent
            text: "Remove…"
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 11
          }
          MouseArea {
            anchors.fill: parent
            enabled: !root.applying
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.pendingAction = "remove"
              root.pendingRef = modelData.ref
              root.pendingDetail = "Uninstall " + modelData.ref + " (--user)."
            }
          }
        }
      }
    }
  }

  Text {
    visible: root.results.length > 0 && !root.confirming
    text: "Search results"
    color: Theme.text
    font.family: Theme.fontFamily
    font.pixelSize: 13
    font.bold: true
  }

  Repeater {
    model: root.results

    Rectangle {
      required property var modelData
      Layout.fillWidth: true
      Layout.maximumWidth: 520
      Layout.preferredHeight: resCol.implicitHeight + 20
      radius: Theme.radiusMd
      color: Theme.bgPanel
      border.width: 1
      border.color: Theme.border
      visible: !root.confirming

      ColumnLayout {
        id: resCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.spaceMd
        spacing: 6

        Text {
          Layout.fillWidth: true
          text: modelData.name
          color: Theme.text
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSize
          font.bold: true
          elide: Text.ElideRight
        }
        Text {
          Layout.fillWidth: true
          text: modelData.ref + (modelData.version.length ? (" · " + modelData.version) : "")
          color: Theme.textDim
          font.family: Theme.fontFamily
          font.pixelSize: 11
          elide: Text.ElideMiddle
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
          Layout.preferredWidth: insLab.implicitWidth + 20
          Layout.preferredHeight: 28
          radius: Theme.radiusSm
          color: Theme.accentSoft
          border.width: 1
          border.color: Theme.accent
          Text {
            id: insLab
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
              root.pendingAction = "install"
              root.pendingRef = modelData.ref
              root.pendingDetail = "Install " + modelData.ref + " via flatpak install --user."
            }
          }
        }
      }
    }
  }

  Text {
    Layout.fillWidth: true
    text: "Fact: flatpak search/list · Apply: flatpak --user (not proteus-pkg). Snap is Out."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }

  Connections {
    target: Packages
    function onPackageOpFinished(ok, message) {
      if (!root.active)
        return
      root.status = message
      root.refreshMeta()
      if (ok && root.query.trim().length)
        root.search()
    }
  }

  Process {
    id: remotesProc
    command: ["flatpak", "remotes", "--user", "--columns=name"]
    stdout: StdioCollector {
      onStreamFinished: {
        root.remotes = text.trim().split("\n").map(s => s.trim()).filter(s => s.length)
      }
    }
  }

  Process {
    id: installedProc
    command: ["flatpak", "list", "--user", "--app", "--columns=application:f,name"]
    stdout: StdioCollector {
      onStreamFinished: {
        const lines = text.trim().split("\n").filter(l => l.length)
        const out = []
        for (let i = 0; i < lines.length; i++) {
          // application\tname  or space-separated depending on flatpak version
          const parts = lines[i].split(/\t+|\s{2,}/)
          const ref = (parts[0] || "").trim()
          if (!ref.length || ref === "Application")
            continue
          out.push({
            ref: ref,
            name: (parts[1] || ref).trim()
          })
        }
        root.installed = out
        if (!out.length && !root.results.length && !root.status.length)
          root.status = "No user Flatpaks installed."
      }
    }
  }

  Process {
    id: searchProc
    command: ["true"]
    stdout: StdioCollector {
      onStreamFinished: {
        const lines = text.trim().split("\n").filter(l => l.length)
        const out = []
        for (let i = 0; i < lines.length; i++) {
          const parts = lines[i].split(/\t/)
          if (parts.length < 2)
            continue
          const ref = parts[0].trim()
          if (!ref.length || ref === "Application")
            continue
          out.push({
            ref: ref,
            name: (parts[1] || ref).trim(),
            version: (parts[2] || "").trim(),
            desc: (parts[3] || "").trim()
          })
        }
        root.results = out.slice(0, 40)
        root.busy = false
        root.status = out.length ? "" : "No Flatpaks matched."
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
    if (active) {
      Packages.refreshHelpers()
      if (Packages.flatpakAvailable)
        refreshMeta()
      else
        status = "Install flatpak to use Flatpak from Settings."
    } else {
      clearPending()
    }
  }
}
