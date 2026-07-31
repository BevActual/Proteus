import QtQuick
import QtQuick.Layouts
import "../../../shared"

// Sticky note — click to write in place (desktop only; read-only on lock).
// Text persists per-widget as `noteText` in settings.json. While editing the
// widget layer is raised and grabs the keyboard (ShellState.desktopNoteEditing).
Item {
  id: root
  property string size: "sm"
  property bool showWhenIdle: true
  property var widgetData: null
  // Bound true by DesktopAppletHost outside Customize; never on lock.
  property bool canEdit: false

  readonly property string savedText: widgetData ? String(widgetData.noteText || "") : ""
  readonly property string widgetId: widgetData ? String(widgetData.id) : ""
  readonly property bool editing: edit.activeFocus

  implicitWidth: card.implicitWidth
  implicitHeight: card.implicitHeight
  width: parent ? Math.min(parent.width, size === "lg" ? 300 : (size === "md" ? 230 : 170)) : 170
  height: implicitHeight

  function save() {
    if (!root.widgetId.length)
      return
    if (edit.text === root.savedText)
      return
    Widgets.patchDesktopWidget(root.widgetId, {
      noteText: edit.text
    })
  }

  // Debounced save while typing; immediate save when focus leaves.
  Timer {
    id: saveDebounce
    interval: 900
    onTriggered: root.save()
  }

  onSavedTextChanged: {
    if (!edit.activeFocus && edit.text !== savedText)
      edit.text = savedText
  }

  Rectangle {
    id: card
    anchors.left: parent.left
    anchors.right: parent.right
    implicitHeight: body.implicitHeight + 20
    radius: 16
    // Warmer plate than the data cards — reads as paper, not telemetry.
    color: Qt.rgba(44 / 255, 40 / 255, 30 / 255, 0.78)
    border.width: 1
    border.color: root.editing ? Theme.accent : Qt.rgba(1, 1, 1, 0.1)

    ColumnLayout {
      id: body
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: 12
      spacing: 6

      RowLayout {
        Layout.fillWidth: true
        Text {
          Layout.fillWidth: true
          text: "Note"
          color: Qt.rgba(1, 1, 1, 0.55)
          font.family: Theme.fontFamily
          font.pixelSize: 11
        }
        Text {
          visible: root.editing
          text: "Esc when done"
          color: Qt.rgba(1, 1, 1, 0.42)
          font.family: Theme.fontFamily
          font.pixelSize: 10
        }
      }

      TextEdit {
        id: edit
        Layout.fillWidth: true
        Layout.preferredHeight: root.size === "lg" ? 130 : (root.size === "md" ? 92 : 56)
        text: root.savedText
        color: "#f5f5f7"
        font.family: Theme.fontFamily
        font.pixelSize: 13
        wrapMode: TextEdit.Wrap
        selectByMouse: true
        readOnly: !root.canEdit
        selectionColor: Theme.accent
        clip: true

        onTextChanged: {
          if (activeFocus)
            saveDebounce.restart()
        }

        onActiveFocusChanged: {
          ShellState.desktopNoteEditing = activeFocus
          if (!activeFocus) {
            saveDebounce.stop()
            root.save()
          }
        }

        Keys.onEscapePressed: focus = false

        // Placeholder
        Text {
          visible: !edit.text.length && !edit.activeFocus
          text: root.canEdit ? "Click to write a note…" : "Empty note"
          color: Qt.rgba(1, 1, 1, 0.35)
          font.family: Theme.fontFamily
          font.pixelSize: 13
        }

        // Click-to-edit without stealing TextEdit's own mouse handling once focused
        MouseArea {
          anchors.fill: parent
          visible: root.canEdit && !edit.activeFocus
          cursorShape: Qt.IBeamCursor
          onClicked: edit.forceActiveFocus()
          onPressAndHold: ShellState.enterDesktopCustomize()
        }
      }
    }
  }

  // External end-of-edit (click on empty desktop / Customize / lock)
  Connections {
    target: ShellState
    function onDesktopNoteEditingChanged() {
      if (!ShellState.desktopNoteEditing && edit.activeFocus)
        edit.focus = false
    }
  }
}
