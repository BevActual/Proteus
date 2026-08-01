import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../shared"
import "../kit"

// Peripherals → Gamepads leaf — detected controllers + Guide button Facts.
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: Theme.spaceMd

  property var controllers: []

  readonly property var guideOptions: [
    { id: "nav", label: "Navigation" },
    { id: "cc", label: "Control Center" },
    { id: "off", label: "Off" }
  ]

  function refreshControllers() {
    listProc.running = false
    listProc.running = true
  }

  Component.onCompleted: refreshControllers()

  Process {
    id: listProc
    command: [
      "python3", "-c",
      "import sys\n"
          + "try:\n"
          + "  import evdev\n"
          + "  from evdev import ecodes\n"
          + "except ImportError:\n"
          + "  print('[]'); sys.exit(0)\n"
          + "out=[]\n"
          + "for path in evdev.list_devices():\n"
          + "  try:\n"
          + "    d=evdev.InputDevice(path)\n"
          + "  except OSError:\n"
          + "    continue\n"
          + "  keys=d.capabilities().get(ecodes.EV_KEY,[])\n"
          + "  markers={ecodes.BTN_MODE, ecodes.BTN_GAMEPAD, getattr(ecodes,'BTN_SOUTH',0x130)}\n"
          + "  if not markers.intersection(keys):\n"
          + "    continue\n"
          + "  out.append({'name': d.name or path, 'path': path, 'guide': ecodes.BTN_MODE in keys})\n"
          + "import json; print(json.dumps(out))\n"
    ]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const parsed = JSON.parse(text.trim() || "[]")
          root.controllers = Array.isArray(parsed) ? parsed : []
        } catch (e) {
          root.controllers = []
        }
      }
    }
  }

  SettingsGroup {
    title: "Detected controllers"

    Item {
      Layout.fillWidth: true
      visible: root.controllers.length === 0
      height: emptyCol.implicitHeight + Theme.spaceMd

      Column {
        id: emptyCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: Theme.spaceMd
        spacing: Theme.spaceXs

        Text {
          text: "No game controllers detected"
          color: Theme.text
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSize
        }

        Text {
          width: parent.width
          text: "Plug in a USB or Bluetooth gamepad. Guide-button mapping still applies when one appears."
          color: Theme.textMute
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSizeSm
          wrapMode: Text.WordWrap
        }
      }
    }

    Repeater {
      model: root.controllers

      SettingsFormRow {
        required property var modelData
        required property int index
        label: modelData.name || "Controller"
        hint: (modelData.guide ? "Guide button · " : "") + (modelData.path || "")
        showSeparator: index < root.controllers.length - 1
      }
    }
  }

  SettingsGroup {
    title: "Guide button"

    SettingsFormRow {
      label: "Single press"
      hint: "Console posture — navigation / switcher"
      showSeparator: true
      SettingsSegmented {
        options: root.guideOptions
        selected: Config.gamepadsGuideSingle
        onActivated: id => {
          Config.gamepadsGuideSingle = id
          if (!Config.deferSettingsWrites)
            Config.flushSettings()
        }
      }
    }

    SettingsFormRow {
      label: "Double press"
      hint: "Console posture — Control Center"
      showSeparator: false
      SettingsSegmented {
        options: root.guideOptions
        selected: Config.gamepadsGuideDouble
        onActivated: id => {
          Config.gamepadsGuideDouble = id
          if (!Config.deferSettingsWrites)
            Config.flushSettings()
        }
      }
    }
  }

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 480
    text: "Fact: settings.json gamepadsGuideSingle / gamepadsGuideDouble · proteus-guide (evdev BTN_MODE, listen-only) · /dev/input."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }

  Text {
    Layout.fillWidth: true
    color: Theme.accent
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSizeSm
    text: "Refresh list"
    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: root.refreshControllers()
    }
  }
}
