import Quickshell
import QtQuick
import QtQuick.Layouts
import "../shared"

ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: 12

  // Parent Settings Item — needed so key capture receives events while recording
  property Item focusHost

  Text {
    Layout.fillWidth: true
    text: "Customize shortcuts like macOS — each one writes a real Hyprland bind."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 12
    wrapMode: Text.WordWrap
  }

  Rectangle {
    Layout.fillWidth: true
    Layout.preferredHeight: 36
    radius: Theme.radius
    color: Theme.bgPanel
    border.width: 1
    border.color: Theme.border
    TextInput {
      id: kbSearch
      anchors.fill: parent
      anchors.leftMargin: Theme.spaceMd
      anchors.rightMargin: Theme.spaceMd
      verticalAlignment: TextInput.AlignVCenter
      color: Theme.text
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSize
      selectByMouse: true
      clip: true
      text: Keybinds.search
      onTextChanged: Keybinds.search = text
      Text {
        anchors.fill: parent
        verticalAlignment: Text.AlignVCenter
        text: "Search shortcuts"
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        visible: !kbSearch.text.length && !kbSearch.activeFocus
      }
    }
  }

  Text {
    Layout.fillWidth: true
    visible: Keybinds.statusMessage.length > 0
    text: Keybinds.statusMessage
    color: Keybinds.recordingId.length ? Theme.accent : Theme.textDim
    font.family: Theme.fontFamily
    font.pixelSize: 12
    wrapMode: Text.WordWrap
  }

  Repeater {
    model: Keybinds.categories
    ColumnLayout {
      required property var modelData
      Layout.fillWidth: true
      spacing: 6
      visible: {
        const _ = Keybinds.listRevision
        return Keybinds.rowsForCategory(modelData).length > 0
      }

      Text {
        text: modelData
        color: Theme.textDim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSm
        font.bold: true
        Layout.topMargin: 6
      }

      Repeater {
        model: {
          const _ = Keybinds.listRevision
          return Keybinds.rowsForCategory(modelData)
        }
        Rectangle {
          required property var modelData
          Layout.fillWidth: true
          Layout.preferredHeight: 52
          radius: Theme.radiusMd
          color: Keybinds.recordingId === modelData.id ? Theme.accentSoft : Theme.bgPanel
          border.width: 1
          border.color: Keybinds.recordingId === modelData.id ? Theme.accent : (Keybinds.conflictId === modelData.id ? Theme.danger : Theme.border)

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 10
            spacing: 10

            ColumnLayout {
              Layout.fillWidth: true
              spacing: 2
              Text {
                text: modelData.label
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
              }
              Text {
                visible: Keybinds.isCustom(modelData.id)
                text: "Custom"
                color: Theme.accent
                font.family: Theme.fontFamily
                font.pixelSize: 10
              }
            }

            Rectangle {
              Layout.preferredHeight: 30
              Layout.preferredWidth: Math.max(96, chordLab.implicitWidth + 20)
              radius: Theme.radius
              color: Keybinds.recordingId === modelData.id ? Theme.accent : Theme.bgElevated
              border.width: 1
              border.color: Theme.border
              Text {
                id: chordLab
                anchors.centerIn: parent
                text: Keybinds.recordingId === modelData.id ? "Type shortcut…" : Keybinds.chordFor(modelData)
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 12
                font.bold: Keybinds.recordingId === modelData.id
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (root.focusHost)
                    root.focusHost.forceActiveFocus()
                  Keybinds.startRecording(modelData.id)
                }
              }
            }

            Rectangle {
              visible: Keybinds.isCustom(modelData.id)
              Layout.preferredWidth: 56
              Layout.preferredHeight: 28
              radius: Theme.radius
              color: resetMa.containsMouse ? Theme.bgHover : "transparent"
              border.width: 1
              border.color: Theme.border
              Text {
                anchors.centerIn: parent
                text: "Reset"
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: 11
              }
              MouseArea {
                id: resetMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Keybinds.resetOne(modelData.id)
              }
            }
          }
        }
      }
    }
  }

  RowLayout {
    Layout.fillWidth: true
    Layout.topMargin: Theme.spaceSm
    spacing: Theme.spaceSm

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 40
      radius: Theme.radiusMd
      color: Theme.bgPanel
      border.width: 1
      border.color: Theme.border
      Text {
        anchors.centerIn: parent
        text: "Edit config file…"
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: 12
      }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: Keybinds.openConfInEditor()
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
        text: "Restore all defaults"
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: 12
      }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: Keybinds.resetAll()
      }
    }
  }

  Text {
    Layout.fillWidth: true
    text: "File: ~/.config/hypr/proteus-keybinds.conf"
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }
}
