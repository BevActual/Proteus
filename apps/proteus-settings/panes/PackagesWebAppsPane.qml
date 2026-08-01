import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../shared"
import "../kit"

// Packages → Web apps: URL → user .desktop via proteus-webapp (no polkit).
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: 12

  property bool active: false
  property string urlText: ""
  property string nameText: ""
  property string status: ""
  property var apps: []
  property string pendingId: ""
  property string pendingDetail: ""
  property bool pendingRemove: false

  readonly property bool confirming: pendingRemove
  readonly property string emptyHint: "No web apps yet — paste a URL and Install."

  function clearPending() {
    pendingId = ""
    pendingDetail = ""
    pendingRemove = false
  }

  function refresh() {
    listProc.running = false
    listProc.running = true
  }

  function webappBin() {
    const rootEnv = String(Quickshell.env("PROTEUS_ROOT") || "").trim()
    const live = (rootEnv.length ? rootEnv : "/mnt/proteus") + "/shell/scripts/proteus-webapp"
    return live
  }

  function installApp() {
    const url = String(urlText || "").trim()
    if (!url.length) {
      status = "Enter a URL (https://…)"
      return
    }
    status = "Installing…"
    installProc.command = [
      "bash", "-lc",
      "export PATH=\"/usr/local/bin:$PATH\"; "
          + "bin=\"" + webappBin().replace(/"/g, '\\"') + "\"; "
          + "if [[ ! -x \"$bin\" ]]; then bin=$(command -v proteus-webapp); fi; "
          + "\"$bin\" install "
          + "'" + url.replace(/'/g, "'\\''") + "' "
          + "'" + String(nameText || "").replace(/'/g, "'\\''") + "'"
    ]
    installProc.running = false
    installProc.running = true
  }

  Text {
    Layout.fillWidth: true
    text: "Install a site as an app (Chromium --app or Firefox kiosk). Desktop entries live in ~/.local/share/applications/proteus-web-*.desktop — show up in Beacon, Dock, and Console Library."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 12
    wrapMode: Text.WordWrap
  }

  PackagesConfirm {
    open: root.confirming
    title: "Remove web app?"
    detail: root.pendingDetail
    footnote: "Deletes the Proteus desktop entry only. No authentication."
    onCancelled: root.clearPending()
    onConfirmed: {
      const id = root.pendingId
      root.clearPending()
      removeProc.command = [
        "bash", "-lc",
        "export PATH=\"/usr/local/bin:$PATH\"; "
            + "bin=\"" + root.webappBin().replace(/"/g, '\\"') + "\"; "
            + "if [[ ! -x \"$bin\" ]]; then bin=$(command -v proteus-webapp); fi; "
            + "\"$bin\" remove '" + String(id).replace(/'/g, "'\\''") + "'"
      ]
      removeProc.running = false
      removeProc.running = true
    }
  }

  ColumnLayout {
    Layout.fillWidth: true
    Layout.maximumWidth: 520
    spacing: Theme.spaceSm
    visible: !root.confirming

    TextField {
      Layout.fillWidth: true
      placeholderText: "https://example.com"
      text: root.urlText
      onTextChanged: root.urlText = text
      color: Theme.text
      font.family: Theme.fontFamily
    }

    TextField {
      Layout.fillWidth: true
      placeholderText: "Name (optional)"
      text: root.nameText
      onTextChanged: root.nameText = text
      color: Theme.text
      font.family: Theme.fontFamily
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Theme.spaceSm

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 40
        radius: Theme.radiusMd
        color: Theme.accentSoft
        border.width: 1
        border.color: Theme.accent
        Text {
          anchors.centerIn: parent
          text: "Install"
          color: Theme.text
          font.family: Theme.fontFamily
          font.pixelSize: 12
          font.bold: true
        }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.installApp()
        }
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 40
        radius: Theme.radiusMd
        color: Theme.bgPanel
        border.width: 1
        border.color: Theme.border
        Text {
          anchors.centerIn: parent
          text: "Refresh"
          color: Theme.text
          font.family: Theme.fontFamily
          font.pixelSize: 12
        }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.refresh()
        }
      }
    }
  }

  Text {
    Layout.fillWidth: true
    text: root.status.length ? root.status : (root.apps.length ? "" : root.emptyHint)
    color: Theme.textDim
    font.family: Theme.fontFamily
    font.pixelSize: 12
    wrapMode: Text.WordWrap
    visible: !root.confirming && (root.status.length > 0 || root.apps.length === 0)
  }

  Repeater {
    model: root.apps

    Rectangle {
      required property var modelData
      Layout.fillWidth: true
      Layout.maximumWidth: 520
      Layout.preferredHeight: rowCol.implicitHeight + 20
      radius: Theme.radiusMd
      color: Theme.bgPanel
      border.width: 1
      border.color: Theme.border
      visible: !root.confirming

      ColumnLayout {
        id: rowCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.spaceMd
        spacing: 6

        Text {
          Layout.fillWidth: true
          text: modelData.name || modelData.id
          color: Theme.text
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSize
          font.bold: true
          elide: Text.ElideRight
        }
        Text {
          Layout.fillWidth: true
          text: modelData.url || modelData.id
          color: Theme.textMute
          font.family: Theme.fontFamily
          font.pixelSize: 11
          elide: Text.ElideMiddle
        }

        RowLayout {
          spacing: Theme.spaceSm

          Rectangle {
            Layout.preferredWidth: openLab.implicitWidth + 20
            Layout.preferredHeight: 28
            radius: Theme.radiusSm
            color: Theme.accentSoft
            border.width: 1
            border.color: Theme.accent
            Text {
              id: openLab
              anchors.centerIn: parent
              text: "Open"
              color: Theme.text
              font.family: Theme.fontFamily
              font.pixelSize: 11
            }
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                Quickshell.execDetached({
                  command: [
                    "bash", "-lc",
                    "export PATH=\"/usr/local/bin:$PATH\"; "
                        + "bin=\"" + root.webappBin().replace(/"/g, '\\"') + "\"; "
                        + "if [[ ! -x \"$bin\" ]]; then bin=$(command -v proteus-webapp); fi; "
                        + "\"$bin\" open '" + String(modelData.id).replace(/'/g, "'\\''") + "'"
                  ]
                })
              }
            }
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
              text: "Remove"
              color: Theme.text
              font.family: Theme.fontFamily
              font.pixelSize: 11
            }
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.pendingId = modelData.id
                root.pendingDetail = modelData.name || modelData.id
                root.pendingRemove = true
              }
            }
          }
        }
      }
    }
  }

  Process {
    id: listProc
    command: [
      "bash", "-lc",
      "export PATH=\"/usr/local/bin:$PATH\"; "
          + "bin=\"" + root.webappBin().replace(/"/g, '\\"') + "\"; "
          + "if [[ ! -x \"$bin\" ]]; then bin=$(command -v proteus-webapp); fi; "
          + "\"$bin\" list --json"
    ]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const raw = text.trim()
          root.apps = raw.length ? JSON.parse(raw) : []
        } catch (e) {
          root.apps = []
          root.status = "Could not list web apps"
        }
      }
    }
  }

  Process {
    id: installProc
    stdout: StdioCollector {
      onStreamFinished: {
        const id = text.trim()
        root.status = id.length ? ("Installed " + id) : "Install finished"
        root.urlText = ""
        root.nameText = ""
        root.refresh()
      }
    }
    onExited: (exitCode, exitStatus) => {
      if (exitCode !== 0)
        root.status = "Install failed (browser missing or bad URL?)"
    }
  }

  Process {
    id: removeProc
    stdout: StdioCollector {
      onStreamFinished: {
        root.status = text.trim() || "Removed"
        root.refresh()
      }
    }
  }

  onActiveChanged: {
    if (active)
      root.refresh()
  }

  Component.onCompleted: {
    if (active)
      root.refresh()
  }
}
