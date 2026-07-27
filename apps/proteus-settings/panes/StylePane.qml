import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../shared"

// Appearance category (page id style): list of sub-settings → leaf. Navigation via page + requestGo.
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: 12

  property string page: "style"
  signal requestGo(string id)

  readonly property bool active: page === "style" || page.startsWith("style-")

  readonly property var sections: [
    {
      key: "style-accent",
      label: "Accent color",
      hint: "Bar, dock, and borders"
    },
    {
      key: "style-background",
      label: "Background",
      hint: "Desktop image and fit"
    },
    {
      key: "style-font",
      label: "Font",
      hint: "UI typeface and size"
    }
  ]

  readonly property string accentLabel: {
    for (let i = 0; i < Config.accents.length; i++) {
      if (Config.accents[i].id === Config.accentId)
        return Config.accents[i].label
    }
    return Config.accentId
  }

  readonly property string wallpaperLabel: {
    for (let i = 0; i < Config.wallpapers.length; i++) {
      if (Config.wallpapers[i].id === Config.wallpaperId)
        return Config.wallpapers[i].label
    }
    return Config.wallpaperId
  }

  function valueFor(key) {
    if (key === "style-accent")
      return accentLabel
    if (key === "style-background")
      return wallpaperLabel + " · " + Config.wallpaperMode
    if (key === "style-font")
      return Config.fontFamily + " · " + Config.fontSize + "px"
    return ""
  }

  // —— Category list ——
  ColumnLayout {
    visible: root.page === "style"
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

          Rectangle {
            visible: modelData.key === "style-accent"
            Layout.preferredWidth: 14
            Layout.preferredHeight: 14
            radius: 7
            color: Config.accentColor
            border.width: 1
            border.color: Theme.border
          }

          Text {
            text: root.valueFor(modelData.key)
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: 11
            elide: Text.ElideRight
            Layout.maximumWidth: 110
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
  }

  // —— Accent leaf ——
  ColumnLayout {
    visible: root.page === "style-accent"
    Layout.fillWidth: true
    spacing: Theme.spaceMd

    Text {
      Layout.fillWidth: true
      text: "Pick an accent used for selection and focus."
      color: Theme.textMute
      font.family: Theme.fontFamily
      font.pixelSize: 12
      wrapMode: Text.WordWrap
    }

    Flow {
      Layout.fillWidth: true
      spacing: 10
      Repeater {
        model: Config.accents
        Rectangle {
          required property var modelData
          width: 72
          height: 64
          radius: Theme.radiusLg
          color: Theme.bgPanel
          border.width: Config.accentId === modelData.id ? 2 : 1
          border.color: Config.accentId === modelData.id ? modelData.color : Theme.border
          Column {
            anchors.centerIn: parent
            spacing: 6
            Rectangle {
              width: 22
              height: 22
              radius: 11
              color: modelData.color
              anchors.horizontalCenter: parent.horizontalCenter
            }
            Text {
              text: modelData.label
              color: Theme.textDim
              font.family: Theme.fontFamily
              font.pixelSize: 11
              anchors.horizontalCenter: parent.horizontalCenter
            }
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: Config.accentId = modelData.id
          }
        }
      }
    }
  }

  // —— Background leaf ——
  ColumnLayout {
    visible: root.page === "style-background"
    Layout.fillWidth: true
    spacing: Theme.spaceMd

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 140
      radius: Theme.radiusLg
      color: Theme.bgPanel
      border.width: 1
      border.color: Theme.border
      clip: true
      Image {
        anchors.fill: parent
        source: "file://" + Config.wallpaperPath
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
      }
    }

    Text {
      text: "Choose background"
      color: Theme.textDim
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSizeSm
    }

    Flow {
      Layout.fillWidth: true
      spacing: 10
      Repeater {
        model: Config.wallpapers
        Rectangle {
          required property var modelData
          width: 112
          height: 72
          radius: 10
          color: Theme.bgPanel
          border.width: Config.wallpaperId === modelData.id ? 2 : 1
          border.color: Config.wallpaperId === modelData.id ? Theme.accent : Theme.border
          clip: true
          Image {
            anchors.fill: parent
            anchors.margins: 2
            source: "file://" + modelData.path
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
          }
          Text {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.margins: 6
            text: modelData.label
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 10
            style: Text.Outline
            styleColor: "#80000000"
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: Config.setWallpaper(modelData.id)
          }
        }
      }
    }

    Text {
      text: "Fit mode"
      color: Theme.textDim
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSizeSm
    }

    Flow {
      Layout.fillWidth: true
      spacing: Theme.spaceSm
      Repeater {
        model: [
          {
            key: "fill",
            label: "Fill"
          },
          {
            key: "fit",
            label: "Fit"
          },
          {
            key: "stretch",
            label: "Stretch"
          },
          {
            key: "center",
            label: "Center"
          }
        ]
        Rectangle {
          required property var modelData
          width: 72
          height: 32
          radius: Theme.radius
          color: Config.wallpaperMode === modelData.key ? Theme.accentSoft : Theme.bgPanel
          border.width: 1
          border.color: Config.wallpaperMode === modelData.key ? Theme.accent : Theme.border
          Text {
            anchors.centerIn: parent
            text: modelData.label
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 12
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: Config.setWallpaperMode(modelData.key)
          }
        }
      }
    }
  }

  // —— Font leaf ——
  ColumnLayout {
    visible: root.page === "style-font"
    Layout.fillWidth: true
    spacing: Theme.spaceMd

    Text {
      text: "UI font"
      color: Theme.textDim
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSizeSm
    }

    Flow {
      Layout.fillWidth: true
      spacing: Theme.spaceSm
      Repeater {
        model: Config.fonts
        Rectangle {
          required property var modelData
          width: 120
          height: 56
          radius: 10
          color: Config.fontFamily === modelData.id ? Theme.accentSoft : Theme.bgPanel
          border.width: Config.fontFamily === modelData.id ? 2 : 1
          border.color: Config.fontFamily === modelData.id ? Theme.accent : Theme.border
          Column {
            anchors.centerIn: parent
            spacing: 4
            Text {
              text: "Aa"
              color: Theme.text
              font.family: modelData.id
              font.pixelSize: 18
              anchors.horizontalCenter: parent.horizontalCenter
            }
            Text {
              text: modelData.label
              color: Theme.textDim
              font.family: Theme.fontFamily
              font.pixelSize: 11
              anchors.horizontalCenter: parent.horizontalCenter
            }
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: Config.fontFamily = modelData.id
          }
        }
      }
    }

    Text {
      text: "Size"
      color: Theme.textDim
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSizeSm
    }

    RowLayout {
      Layout.fillWidth: true
      Slider {
        Layout.fillWidth: true
        from: 11
        to: 18
        stepSize: 1
        value: Config.fontSize
        onMoved: {
          const v = Math.round(value)
          Config.fontSize = v
          Config.fontSizeSm = Math.max(10, v - 1)
        }
      }
      Text {
        text: Config.fontSize + "px"
        color: Theme.text
        font.family: Theme.fontFamily
        Layout.preferredWidth: 40
      }
    }

    Text {
      Layout.fillWidth: true
      text: "The quick brown fox jumps over the lazy dog."
      color: Theme.text
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSize
      wrapMode: Text.WordWrap
    }
  }
}
