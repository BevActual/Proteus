import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../shared"

// Desktop category: list of sub-settings → leaf. Navigation via page + requestGo.
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: 12

  property string page: "desktop"
  signal requestGo(string id)

  readonly property bool active: page === "desktop" || page.startsWith("desktop-")

  readonly property var sections: [
    {
      key: "desktop-gaps",
      label: "Gaps",
      hint: "Space between and around windows"
    },
    {
      key: "desktop-chrome",
      label: "Borders & rounding",
      hint: "Edge weight and corner radius"
    },
    {
      key: "desktop-motion",
      label: "Motion",
      hint: "Window animations"
    },
    {
      key: "desktop-dock",
      label: "Dock",
      hint: "Bottom app dock"
    }
  ]

  function valueFor(key) {
    if (key === "desktop-gaps")
      return Config.gapsIn + " / " + Config.gapsOut
    if (key === "desktop-chrome")
      return Config.borderSize + "px · " + Config.rounding
    if (key === "desktop-motion")
      return Config.animationsEnabled ? "On" : "Off"
    if (key === "desktop-dock")
      return Config.dockEnabled ? "Shown" : "Hidden"
    return ""
  }

  // —— Category list ——
  ColumnLayout {
    visible: root.page === "desktop"
    Layout.fillWidth: true
    Layout.maximumWidth: 420
    spacing: 6

    Text {
      Layout.fillWidth: true
      text: "Choose what to configure."
      color: Theme.textMute
      font.family: Theme.fontFamily
      font.pixelSize: 12
      wrapMode: Text.WordWrap
      Layout.bottomMargin: 2
    }

    Repeater {
      model: root.sections

      Rectangle {
        required property var modelData
        Layout.fillWidth: true
        Layout.preferredHeight: 44
        radius: Theme.radiusMd
        color: rowMa.containsMouse ? Theme.bgHover : Theme.bgPanel
        border.width: 1
        border.color: Theme.border

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: Theme.spaceMd
          anchors.rightMargin: Theme.spaceMd
          spacing: Theme.spaceSm

          ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            Text {
              text: modelData.label
              color: Theme.text
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSize
            }
            Text {
              text: modelData.hint
              color: Theme.textMute
              font.family: Theme.fontFamily
              font.pixelSize: 11
            }
          }

          Text {
            text: root.valueFor(modelData.key)
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: 11
          }

          Text {
            text: "›"
            color: Theme.textDim
            font.pixelSize: 16
          }
        }

        MouseArea {
          id: rowMa
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.requestGo(modelData.key)
        }
      }
    }

    Text {
      Layout.fillWidth: true
      Layout.topMargin: 8
      text: "File: ~/.config/hypr/proteus-general.conf"
      color: Theme.textMute
      font.family: Theme.fontFamily
      font.pixelSize: 11
      wrapMode: Text.WordWrap
    }
  }

  // —— Gaps ——
  ColumnLayout {
    visible: root.page === "desktop-gaps"
    Layout.fillWidth: true
    spacing: 14

    Text {
      text: "Window gaps (inside)"
      color: Theme.textDim
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSizeSm
    }
    RowLayout {
      Layout.fillWidth: true
      Slider {
        Layout.fillWidth: true
        from: 0
        to: 32
        stepSize: 1
        value: Config.gapsIn
        onMoved: Config.gapsIn = Math.round(value)
      }
      Text {
        text: Config.gapsIn
        color: Theme.text
        font.family: Theme.fontFamily
        Layout.preferredWidth: 28
      }
    }

    Text {
      text: "Outer gaps"
      color: Theme.textDim
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSizeSm
    }
    RowLayout {
      Layout.fillWidth: true
      Slider {
        Layout.fillWidth: true
        from: 0
        to: 48
        stepSize: 1
        value: Config.gapsOut
        onMoved: Config.gapsOut = Math.round(value)
      }
      Text {
        text: Config.gapsOut
        color: Theme.text
        font.family: Theme.fontFamily
        Layout.preferredWidth: 28
      }
    }
  }

  // —— Borders & rounding ——
  ColumnLayout {
    visible: root.page === "desktop-chrome"
    Layout.fillWidth: true
    spacing: 14

    Text {
      text: "Border size"
      color: Theme.textDim
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSizeSm
    }
    RowLayout {
      Layout.fillWidth: true
      Slider {
        Layout.fillWidth: true
        from: 0
        to: 8
        stepSize: 1
        value: Config.borderSize
        onMoved: Config.borderSize = Math.round(value)
      }
      Text {
        text: Config.borderSize
        color: Theme.text
        font.family: Theme.fontFamily
        Layout.preferredWidth: 28
      }
    }

    Text {
      text: "Window rounding"
      color: Theme.textDim
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSizeSm
    }
    RowLayout {
      Layout.fillWidth: true
      Slider {
        Layout.fillWidth: true
        from: 0
        to: 24
        stepSize: 1
        value: Config.rounding
        onMoved: Config.rounding = Math.round(value)
      }
      Text {
        text: Config.rounding
        color: Theme.text
        font.family: Theme.fontFamily
        Layout.preferredWidth: 28
      }
    }
  }

  // —— Motion ——
  ColumnLayout {
    visible: root.page === "desktop-motion"
    Layout.fillWidth: true
    spacing: Theme.spaceMd

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 48
      radius: Theme.radiusMd
      color: Theme.bgPanel
      border.width: 1
      border.color: Theme.border
      RowLayout {
        anchors.fill: parent
        anchors.margins: Theme.spaceMd
        Text {
          Layout.fillWidth: true
          text: "Window animations"
          color: Theme.text
          font.family: Theme.fontFamily
        }
        Switch {
          checked: Config.animationsEnabled
          onToggled: Config.animationsEnabled = checked
        }
      }
    }
  }

  // —— Dock ——
  ColumnLayout {
    visible: root.page === "desktop-dock"
    Layout.fillWidth: true
    spacing: Theme.spaceMd

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 48
      radius: Theme.radiusMd
      color: Theme.bgPanel
      border.width: 1
      border.color: Theme.border
      RowLayout {
        anchors.fill: parent
        anchors.margins: Theme.spaceMd
        Text {
          Layout.fillWidth: true
          text: "Show dock"
          color: Theme.text
          font.family: Theme.fontFamily
        }
        Switch {
          checked: Config.dockEnabled
          onToggled: Config.dockEnabled = checked
        }
      }
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 40
      Layout.topMargin: 8
      radius: Theme.radiusMd
      color: Theme.bgPanel
      border.width: 1
      border.color: Theme.border
      Text {
        anchors.centerIn: parent
        text: "Edit compositor config…"
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: 12
      }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: Config.openGeneralConfInEditor()
      }
    }
  }
}
