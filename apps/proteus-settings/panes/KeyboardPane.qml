import Quickshell
import QtQuick
import QtQuick.Layouts
import "../shared"
import "../kit"

// Peripherals → Keyboard leaf. Reference hybrid feature (SETTINGS-IA § 5):
// friendly catalog → keybinds.json → generated proteus-keybinds.conf.
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: Theme.spaceMd

  // Parent Settings Item — needed so key capture receives events while recording
  property Item focusHost
  property bool _keysHooked: false

  Connections {
    target: SettingsNav
    function onPageChanged() {
      if (SettingsNav.page !== "peripherals-keyboard" && Keybinds.recordingId.length)
        Keybinds.cancelRecording()
    }
  }

  Binding {
    target: root.focusHost
    property: "focus"
    value: Keybinds.recordingId.length > 0
    when: root.focusHost !== null
  }

  function hookFocusKeys() {
    if (!focusHost || _keysHooked)
      return
    _keysHooked = true
    focusHost.Keys.onPressed.connect(function (event) {
      if (SettingsNav.page === "peripherals-keyboard")
        Keybinds.handleKeyEvent(event)
    })
  }
  onFocusHostChanged: root.hookFocusKeys()
  Component.onCompleted: root.hookFocusKeys()

  function rowsFor(category) {
    // listRevision is read so the binding re-evaluates after an edit.
    const _ = Keybinds.listRevision
    return Keybinds.rowsForCategory(category)
  }

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 480
    text: "Customize shortcuts like macOS — each one writes a real Hyprland bind."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 12
    wrapMode: Text.WordWrap
  }

  Rectangle {
    Layout.fillWidth: true
    Layout.maximumWidth: 480
    Layout.preferredHeight: 36
    radius: Theme.radiusMd
    color: Theme.bgElevated
    border.width: 1
    border.color: kbSearch.activeFocus ? Theme.accent : Theme.border

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
    Layout.maximumWidth: 480
    visible: Keybinds.statusMessage.length > 0
    text: Keybinds.statusMessage
    color: Keybinds.recordingId.length ? Theme.accent : Theme.textDim
    font.family: Theme.fontFamily
    font.pixelSize: 12
    wrapMode: Text.WordWrap
  }

  Repeater {
    model: Keybinds.categories

    SettingsGroup {
      id: catGroup
      required property var modelData
      title: catGroup.modelData
      visible: root.rowsFor(catGroup.modelData).length > 0

      Repeater {
        model: root.rowsFor(catGroup.modelData)

        SettingsFormRow {
          id: bindRow
          required property var modelData
          required property int index

          readonly property bool recording: Keybinds.recordingId === modelData.id
          readonly property bool conflicted: Keybinds.conflictId === modelData.id
          readonly property bool custom: Keybinds.isCustom(modelData.id)

          label: modelData.label
          hint: bindRow.conflicted ? "Already used by another shortcut"
              : (bindRow.custom ? "Custom" : "")
          showSeparator: bindRow.index < root.rowsFor(catGroup.modelData).length - 1
          highlight: bindRow.recording ? Theme.accentSoft : "transparent"

          // Chord chip — click to record a new combination.
          Rectangle {
            Layout.preferredHeight: 30
            Layout.preferredWidth: Math.max(96, chordLab.implicitWidth + 20)
            radius: Theme.radius
            color: bindRow.recording ? Theme.accent : Theme.bgHover
            border.width: 1
            border.color: bindRow.conflicted ? Theme.danger : Theme.border

            Text {
              id: chordLab
              anchors.centerIn: parent
              text: bindRow.recording ? "Type shortcut…" : Keybinds.chordFor(bindRow.modelData)
              color: Theme.text
              font.family: Theme.fontFamily
              font.pixelSize: 12
              font.bold: bindRow.recording
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (root.focusHost)
                  root.focusHost.forceActiveFocus()
                Keybinds.startRecording(bindRow.modelData.id)
              }
            }
          }

          Rectangle {
            visible: bindRow.custom
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
              onClicked: Keybinds.resetOne(bindRow.modelData.id)
            }
          }
        }
      }
    }
  }

  SettingsGroup {
    SettingsFormRow {
      label: "Edit config file…"
      hint: "~/.config/hypr/proteus-keybinds.conf"
      showSeparator: true
      interactive: true
      onActivated: Keybinds.openConfInEditor()
      Text {
        text: "›"
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }
    }

    SettingsFormRow {
      label: "Restore all defaults"
      hint: "Discards every custom shortcut"
      showSeparator: false
      interactive: true
      labelColor: Theme.danger
      onActivated: Keybinds.resetAll()
      Text {
        text: "›"
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }
    }
  }

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 480
    text: "Fact: keybinds.json → proteus-keybinds.conf, sourced by Hyprland."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }
}
