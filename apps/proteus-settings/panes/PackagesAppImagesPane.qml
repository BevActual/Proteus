import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import "../shared"

// Packages → AppImages: local library under ~/.local/share/proteus/appimages.
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: 12

  property bool active: false
  property string pendingId: ""
  property string pendingDetail: ""
  property bool pendingRemove: false

  readonly property bool confirming: pendingRemove
  readonly property bool applying: Packages.packageOpBusy
  readonly property var images: Packages.appImages

  function clearPending() {
    pendingId = ""
    pendingDetail = ""
    pendingRemove = false
  }

  function localPathFromUrl(url) {
    let s = String(url)
    if (s.startsWith("file://"))
      s = s.slice(7)
    try {
      return decodeURIComponent(s)
    } catch (e) {
      return s
    }
  }

  Text {
    Layout.fillWidth: true
    text: "AppImages live in ~/.local/share/proteus/appimages with a desktop entry for the launcher. No polkit — your user only."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 12
    wrapMode: Text.WordWrap
  }

  PackagesConfirm {
    open: root.confirming
    title: "Remove AppImage?"
    detail: root.pendingDetail
    footnote: "Deletes the file and its Proteus desktop entry. No authentication."
    onCancelled: root.clearPending()
    onConfirmed: {
      const id = root.pendingId
      root.clearPending()
      Packages.removeAppImage(id)
    }
  }

  FileDialog {
    id: pickDialog
    title: "Choose an AppImage"
    nameFilters: ["AppImage (*.AppImage *.appimage)", "All files (*)"]
    onAccepted: Packages.addAppImage(root.localPathFromUrl(selectedFile))
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
    visible: !root.confirming

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
        text: "Refresh"
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: 12
      }
      MouseArea {
        anchors.fill: parent
        enabled: !root.applying
        cursorShape: Qt.PointingHandCursor
        onClicked: Packages.refreshAppImages()
      }
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 40
      radius: Theme.radiusMd
      color: Theme.accentSoft
      border.width: 1
      border.color: Theme.accent
      opacity: root.applying ? 0.6 : 1
      Text {
        anchors.centerIn: parent
        text: "Add AppImage…"
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: 12
        font.bold: true
      }
      MouseArea {
        anchors.fill: parent
        enabled: !root.applying
        cursorShape: Qt.PointingHandCursor
        onClicked: pickDialog.open()
      }
    }
  }

  Text {
    Layout.fillWidth: true
    text: Packages.appImageStatus
    color: Theme.textDim
    font.family: Theme.fontFamily
    font.pixelSize: 12
    wrapMode: Text.WordWrap
    visible: root.images.length === 0 && !root.confirming && !root.applying
  }

  Repeater {
    model: root.images

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
          text: modelData.name
          color: Theme.text
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSize
          font.bold: true
          elide: Text.ElideRight
        }
        Text {
          Layout.fillWidth: true
          text: modelData.path
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
              onClicked: Packages.openAppImage(modelData.id)
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
                root.pendingId = modelData.id
                root.pendingDetail = "Remove " + modelData.name + " and its desktop entry."
                root.pendingRemove = true
              }
            }
          }
        }
      }
    }
  }

  Text {
    Layout.fillWidth: true
    text: "Fact: ~/.local/share/proteus/appimages · desktop: proteus-appimage-*.desktop"
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
      if (ok)
        Packages.refreshAppImages()
    }
  }

  onActiveChanged: {
    if (active)
      Packages.refreshAppImages()
    else
      clearPending()
  }
}
