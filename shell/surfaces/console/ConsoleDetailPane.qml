import QtQuick
import QtQuick.Layouts
import "../../shared"

// Right pane: title, blurb, primary Launch for the focused list item.
Item {
  id: root

  property var item: null
  property bool detailFocused: false
  property string emptyCopy: "Select an item"
  property string emptyHint: ""

  signal launchRequested()
  signal detailsRequested()

  readonly property string title: item ? (item.title || "") : ""
  readonly property string tag: item ? String(item.tag || "") : ""
  readonly property string meta: item ? String(item.meta || item.id || "") : ""
  readonly property string blurb: {
    if (!item)
      return ""
    if (item.kind === "settings")
      return "Console Settings — lean pad controls in chrome (not a separate app)."
    if (item.kind === "action")
      return "Run this Console action."
    if (item.kind === "steam-title" || item.kind === "retro-title")
      return "Installed title — launches through the Console seat"
          + (item.needsGamescope ? " · Gamescope when available" : "") + "."
    if (tag === "GAMES")
      return "Launch via Console seat" + (item.needsGamescope ? " · Gamescope when available" : "") + "."
    if (tag === "WEB" || String(item.id || "").indexOf("proteus-web-") === 0)
      return "Streaming / web app — opens through Console."
    if (root.isStreamingHint)
      return "Streaming app — opens through Console."
    return "Open with Console."
  }
  readonly property bool isStreamingHint: {
    if (!item)
      return false
    const hay = (String(item.id || "") + " " + String(item.title || "")).toLowerCase()
    return hay.indexOf("spotify") >= 0 || hay.indexOf("netflix") >= 0
        || hay.indexOf("plex") >= 0 || hay.indexOf("youtube") >= 0
        || hay.indexOf("hbo") >= 0 || hay.indexOf("disney") >= 0
  }
  readonly property color color0: item && item.color0 ? item.color0 : Theme.bgElevated
  readonly property color color1: item && item.color1 ? item.color1 : Theme.bg
  readonly property string iconSource: item && item.iconSource ? String(item.iconSource) : ""
  readonly property string launchLabel: {
    if (!item)
      return "Open"
    if (item.kind === "settings")
      return "Open"
    if (item.kind === "action")
      return "Run"
    return "Launch"
  }

  Rectangle {
    anchors.fill: parent
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0.0; color: root.color0 }
      GradientStop { position: 0.45; color: root.color1 }
      GradientStop { position: 1.0; color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.95) }
    }
  }

  Rectangle {
    anchors.fill: parent
    border.width: root.detailFocused ? 2 : 0
    border.color: Theme.accent
    color: "transparent"
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Theme.spaceXl
    spacing: Theme.spaceLg
    visible: !!root.item

    Item {
      Layout.fillWidth: true
      Layout.preferredHeight: 120

      Rectangle {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 96
        height: 96
        radius: Theme.radiusLg
        color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.35)
        border.width: 1
        border.color: Theme.chromeBorder

        Image {
          anchors.fill: parent
          anchors.margins: 12
          visible: root.iconSource.length > 0
          source: root.iconSource
          fillMode: Image.PreserveAspectFit
          asynchronous: true
        }

        Text {
          anchors.centerIn: parent
          visible: root.iconSource.length === 0
          text: root.title.length ? root.title.charAt(0).toUpperCase() : "?"
          color: Theme.text
          font.family: Theme.fontFamily
          font.pixelSize: 36
          font.weight: Font.Bold
        }
      }
    }

    Text {
      Layout.fillWidth: true
      text: root.title
      color: Theme.text
      font.family: Theme.fontFamily
      font.pixelSize: 40
      font.weight: Font.Bold
      wrapMode: Text.WordWrap
      maximumLineCount: 2
      elide: Text.ElideRight
    }

    Text {
      Layout.fillWidth: true
      visible: root.tag.length > 0 || root.meta.length > 0
      // Skip the tag when meta already carries it (e.g. "GAMES · games")
      text: root.tag.length && root.meta.toLowerCase() !== root.tag.toLowerCase()
          ? [root.tag, root.meta].filter(function (s) {
              return s && String(s).length
            }).join(" · ")
          : (root.meta.length ? root.meta : root.tag)
      color: Theme.textDim
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSize + 1
      wrapMode: Text.WordWrap
    }

    Text {
      Layout.fillWidth: true
      text: root.blurb
      color: Theme.text
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSize + 2
      wrapMode: Text.WordWrap
      opacity: 0.9
    }

    Row {
      spacing: Theme.spaceMd

      Rectangle {
        width: launchLbl.implicitWidth + 36
        height: 48
        radius: Theme.radiusLg
        color: root.detailFocused ? Theme.accent : Theme.chromeAccentSoft
        border.width: root.detailFocused ? 0 : 1
        border.color: Theme.accent

        Text {
          id: launchLbl
          anchors.centerIn: parent
          text: root.launchLabel
          color: root.detailFocused ? "#ffffff" : Theme.accent
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSize + 2
          font.weight: Font.DemiBold
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.launchRequested()
        }
      }

      Rectangle {
        width: detailsLbl.implicitWidth + 28
        height: 48
        radius: Theme.radiusLg
        color: "transparent"
        border.width: 1
        border.color: Theme.chromeBorder
        visible: item && item.kind !== "action"

        Text {
          id: detailsLbl
          anchors.centerIn: parent
          text: "Details"
          color: Theme.textDim
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSize + 1
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.detailsRequested()
        }
      }
    }

    Item { Layout.fillHeight: true }
  }

  ColumnLayout {
    anchors.centerIn: parent
    width: Math.min(parent.width - 80, 420)
    spacing: Theme.spaceMd
    visible: !root.item

    Text {
      Layout.fillWidth: true
      text: root.emptyCopy
      color: Theme.textMute
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSize + 4
      font.weight: Font.DemiBold
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
    }

    Text {
      Layout.fillWidth: true
      visible: root.emptyHint.length > 0
      text: root.emptyHint
      color: Theme.textDim
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSize + 1
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
    }
  }
}
