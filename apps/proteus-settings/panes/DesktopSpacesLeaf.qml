import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../shared"
import "../kit"
import ".." // SettingsNav singleton

// Leaf UI for DesktopPane — Spaces mode + multi-head + Named Spaces + special CRUD.
ColumnLayout {
  id: root
  width: parent ? parent.width : implicitWidth
  spacing: Theme.spaceMd

  // Parent Settings Item — key capture while recording a per-special chord
  property Item focusHost
  property bool _keysHooked: false

  readonly property bool shareSpaces: Config.workspaceMode !== "perDisplay"
  property string newSpecialDraft: ""
  property string confirmDeleteSpecial: ""

  readonly property var specialNames: {
    const _r = SpacesSpecials.rev
    return SpacesSpecials.names()
  }

  Connections {
    target: SettingsNav
    function onPageChanged() {
      if (SettingsNav.page !== "desktop-spaces" && SpacesSpecials.isRecording)
        SpacesSpecials.cancelRecording()
    }
  }

  Binding {
    target: root.focusHost
    property: "focus"
    value: SpacesSpecials.isRecording
    when: root.focusHost !== null
  }

  function hookFocusKeys() {
    if (!focusHost || _keysHooked)
      return
    _keysHooked = true
    focusHost.Keys.onPressed.connect(function (event) {
      if (SettingsNav.page === "desktop-spaces")
        SpacesSpecials.handleKeyEvent(event)
    })
  }
  onFocusHostChanged: root.hookFocusKeys()

  Component.onCompleted: {
    root.hookFocusKeys()
    SpacesDisplays.refresh()
    SpacesNames.rev
    SpacesSpecials.rev
  }

  SettingsGroup {
    title: "Spaces"

    SettingsFormRow {
      label: "Displays share Spaces"
      hint: root.shareSpaces
          ? "Super+N switches every display together"
          : "Super+N switches only the focused display"
      showSeparator: true
      ThemeSwitch {
        checked: root.shareSpaces
        onToggled: Config.workspaceMode = checked ? "synced" : "perDisplay"
      }
    }

    SettingsFormRow {
      label: "This display only"
      hint: "Super+Ctrl+1–10 always switches the focused display (keyboard). Super+0 is Space 10. Strip and wheel match."
      showSeparator: true
      Text {
        text: "⌃⌘N"
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSm
      }
    }

    SettingsFormRow {
      label: "Displays"
      hint: SpacesDisplays.summaryLabel
      showSeparator: SpacesDisplays.monitors.length > 0
      Text {
        text: SpacesDisplays.monitorCount > 0
            ? (SpacesDisplays.monitorCount + "")
            : "—"
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSm
      }
    }

    Repeater {
      model: SpacesDisplays.monitors

      SettingsFormRow {
        required property var modelData
        required property int index
        label: String(modelData.name || ("Display " + (index + 1)))
        hint: "Space " + String(modelData.activeLogical || 1)
            + " · band " + String(modelData.bandStart || "?")
            + "–" + String(modelData.bandEnd || "?")
            + (modelData.focused ? " · focused" : "")
        showSeparator: index < SpacesDisplays.monitors.length - 1
        Text {
          text: "×10"
          color: Theme.textMute
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSizeSm
        }
      }
    }
  }

  SettingsGroup {
    title: "Scratchpad"

    SettingsFormRow {
      label: "Toggle Scratchpad"
      hint: "Menu-bar ◇ pill or Super+S — shows/hides special:scratch (≠ dock minimize)"
      showSeparator: true
      Text {
        text: "⌘S"
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSm
      }
    }

    SettingsFormRow {
      label: "Move window to Scratchpad"
      hint: "Parks the focused window on the Scratchpad (toggle with ⌘S or the ◇ pill)"
      showSeparator: false
      Text {
        text: "⌥⌘S"
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSm
      }
    }
  }

  SettingsGroup {
    title: "Special workspaces"

    SettingsFormRow {
      label: "Reserved"
      hint: "scratch (Scratchpad) and minimized (dock) stay product-fixed — not in this list"
      showSeparator: true
      Text {
        text: "2"
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSm
      }
    }

    Repeater {
      model: root.specialNames

      ColumnLayout {
        required property string modelData
        required property int index
        Layout.fillWidth: true
        spacing: 0

        SettingsFormRow {
          label: "special:" + modelData
          hint: "Rename updates Settings SoT · open windows stay on the old name until moved"
          showSeparator: true
          TextField {
            Layout.preferredWidth: 120
            text: modelData
            color: Theme.text
            placeholderText: "name"
            placeholderTextColor: Theme.textMute
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            background: Item {}
            onEditingFinished: {
              if (String(text || "").trim() !== modelData)
                SpacesSpecials.rename(modelData, text)
            }
          }
        }

        SettingsFormRow {
          label: "Toggle chord"
          hint: {
            const _r = SpacesSpecials.rev
            if (SpacesSpecials.recordingName === modelData
                && SpacesSpecials.recordingKind === "toggle")
              return SpacesSpecials.chordStatus || "Press a new shortcut…"
            return SpacesSpecials.chordLabel(modelData)
          }
          showSeparator: true
          Text {
            text: (SpacesSpecials.recordingName === modelData
                   && SpacesSpecials.recordingKind === "toggle") ? "…" : "Set"
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: 13
            MouseArea {
              anchors.fill: parent
              anchors.margins: -8
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (root.focusHost)
                  root.focusHost.forceActiveFocus()
                SpacesSpecials.startRecording(modelData)
              }
            }
          }
          Text {
            visible: {
              const _r = SpacesSpecials.rev
              return !!SpacesSpecials.chordFor(modelData)
                  && !(SpacesSpecials.recordingName === modelData
                       && SpacesSpecials.recordingKind === "toggle")
            }
            text: "Clear"
            color: Theme.textMute
            font.family: Theme.fontFamily
            font.pixelSize: 13
            MouseArea {
              anchors.fill: parent
              anchors.margins: -8
              cursorShape: Qt.PointingHandCursor
              onClicked: SpacesSpecials.clearChord(modelData)
            }
          }
        }

        SettingsFormRow {
          label: "Move chord"
          hint: {
            const _r = SpacesSpecials.rev
            if (SpacesSpecials.recordingName === modelData
                && SpacesSpecials.recordingKind === "move")
              return SpacesSpecials.chordStatus || "Press a new shortcut…"
            return SpacesSpecials.moveChordLabel(modelData)
          }
          showSeparator: true
          Text {
            text: (SpacesSpecials.recordingName === modelData
                   && SpacesSpecials.recordingKind === "move") ? "…" : "Set"
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: 13
            MouseArea {
              anchors.fill: parent
              anchors.margins: -8
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (root.focusHost)
                  root.focusHost.forceActiveFocus()
                SpacesSpecials.startMoveRecording(modelData)
              }
            }
          }
          Text {
            visible: {
              const _r = SpacesSpecials.rev
              return !!SpacesSpecials.moveChordFor(modelData)
                  && !(SpacesSpecials.recordingName === modelData
                       && SpacesSpecials.recordingKind === "move")
            }
            text: "Clear"
            color: Theme.textMute
            font.family: Theme.fontFamily
            font.pixelSize: 13
            MouseArea {
              anchors.fill: parent
              anchors.margins: -8
              cursorShape: Qt.PointingHandCursor
              onClicked: SpacesSpecials.clearMoveChord(modelData)
            }
          }
        }

        SettingsFormRow {
          label: "Actions"
          hint: root.confirmDeleteSpecial === modelData
              ? ("Confirm delete of special:" + modelData)
              : ("Strip pill · Super+Alt+" + (index + 1) + " toggle · Super+Alt+Shift+"
                 + (index + 1) + " move (index fallback)")
          showSeparator: true
          Text {
            text: "Toggle"
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: 13
            MouseArea {
              anchors.fill: parent
              anchors.margins: -8
              cursorShape: Qt.PointingHandCursor
              onClicked: SpacesSpecials.toggle(modelData)
            }
          }
          Text {
            text: "Move"
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: 13
            MouseArea {
              anchors.fill: parent
              anchors.margins: -8
              cursorShape: Qt.PointingHandCursor
              onClicked: SpacesSpecials.moveTo(modelData)
            }
          }
          Text {
            visible: root.confirmDeleteSpecial !== modelData
            text: "Delete"
            color: Theme.danger
            font.family: Theme.fontFamily
            font.pixelSize: 13
            MouseArea {
              anchors.fill: parent
              anchors.margins: -8
              cursorShape: Qt.PointingHandCursor
              onClicked: root.confirmDeleteSpecial = modelData
            }
          }
          RowLayout {
            visible: root.confirmDeleteSpecial === modelData
            spacing: Theme.spaceMd
            Text {
              text: "Cancel"
              color: Theme.textMute
              font.family: Theme.fontFamily
              font.pixelSize: 13
              MouseArea {
                anchors.fill: parent
                anchors.margins: -8
                cursorShape: Qt.PointingHandCursor
                onClicked: root.confirmDeleteSpecial = ""
              }
            }
            Text {
              text: "Delete"
              color: Theme.danger
              font.family: Theme.fontFamily
              font.pixelSize: 13
              MouseArea {
                anchors.fill: parent
                anchors.margins: -8
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  SpacesSpecials.remove(modelData)
                  root.confirmDeleteSpecial = ""
                }
              }
            }
          }
        }
      }
    }

    SettingsFormRow {
      visible: SpacesSpecials.chordStatus.length > 0
      label: "Chord"
      hint: SpacesSpecials.chordStatus
      showSeparator: true
      labelColor: Theme.accent
    }

    SettingsFormRow {
      label: "Add special"
      hint: root.specialNames.length >= 8
          ? "Limit 8 custom specials (slug a–z, digits, hyphen)"
          : "Creates special:<slug> · reserved scratch/minimized rejected"
      showSeparator: false
      TextField {
        Layout.preferredWidth: 140
        placeholderText: "notes"
        text: root.newSpecialDraft
        color: Theme.text
        placeholderTextColor: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        background: Item {}
        enabled: root.specialNames.length < 8
        onTextChanged: root.newSpecialDraft = text
        onAccepted: {
          if (SpacesSpecials.add(root.newSpecialDraft).length)
            root.newSpecialDraft = ""
        }
      }
      Text {
        text: "Add"
        color: root.specialNames.length < 8 ? Theme.accent : Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: 13
        MouseArea {
          anchors.fill: parent
          anchors.margins: -8
          enabled: root.specialNames.length < 8
          cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: {
            if (SpacesSpecials.add(root.newSpecialDraft).length)
              root.newSpecialDraft = ""
          }
        }
      }
    }
  }

  SettingsGroup {
    title: "Names"

    Repeater {
      model: 10

      SettingsFormRow {
        id: nameRow
        required property int index
        readonly property int spaceId: index + 1
        label: "Space " + spaceId
        hint: {
          const _r = SpacesNames.rev
          const cur = SpacesNames.labelForLogical(nameRow.spaceId)
          return cur.length ? ("Label · " + cur) : "Optional label (empty = number)"
        }
        showSeparator: index < 9
        TextField {
          Layout.preferredWidth: 140
          text: {
            const _r = SpacesNames.rev
            return SpacesNames.labelForLogical(nameRow.spaceId)
          }
          color: Theme.text
          placeholderText: String(nameRow.spaceId)
          placeholderTextColor: Theme.textMute
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSize
          background: Item {}
          onEditingFinished: SpacesNames.setName(nameRow.spaceId, text)
        }
      }
    }
  }

  Text {
    Layout.fillWidth: true
    visible: SpacesDisplays.hint.length > 0
    text: SpacesDisplays.hint
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }

  Text {
    Layout.fillWidth: true
    text: "Fact: Super+1–10 stays logical SoT · Named Spaces labels · strip drag reorders visual order (workspaceOrder) · disconnect migrates orphan-band windows to the primary display · Scratchpad ◇ strip pill + Super+S / Super+Alt+S · custom specials strip pills (up to 8) + Super+Alt+1–8 / Super+Alt+Shift+1–8 (index fallback) · optional per-special toggle chords (specialWorkspaceChords → special-toggle <slug>) · optional per-special move chords (specialWorkspaceMoveChords → special-move <slug>)."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }
}
