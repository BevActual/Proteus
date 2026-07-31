import Quickshell
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Layouts
import "../../shared"

// Now Playing — MPRIS media plate for the Control Center.
// Honest skip: collapses entirely when no player is registered.
Rectangle {
  id: root

  readonly property var player: {
    const list = Mpris.players ? Mpris.players.values : []
    if (!list || !list.length)
      return null
    // Prefer the actively playing player; otherwise the most recent one.
    for (let i = 0; i < list.length; i++) {
      if (list[i] && list[i].playbackState === MprisPlaybackState.Playing)
        return list[i]
    }
    return list[0]
  }
  readonly property bool playing: !!player
      && player.playbackState === MprisPlaybackState.Playing

  readonly property string title: {
    if (!player)
      return ""
    const t = String(player.trackTitle || "")
    return t.length ? t : "Unknown title"
  }
  readonly property string subtitle: {
    if (!player)
      return ""
    const artist = String(player.trackArtist || "")
    if (artist.length)
      return artist
    return String(player.identity || "")
  }
  readonly property string artUrl: player ? String(player.trackArtUrl || "") : ""

  visible: player !== null
  implicitHeight: body.implicitHeight + Theme.spaceSm * 2
  radius: Theme.radiusLg
  color: Theme.elevatedFill
  border.width: 1
  border.color: Theme.chromeBorder

  RowLayout {
    id: body
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Theme.spaceSm
    anchors.rightMargin: Theme.spaceSm
    spacing: Theme.spaceSm

    // Artwork (album art when the player exposes it; note glyph otherwise)
    Rectangle {
      Layout.preferredWidth: 40
      Layout.preferredHeight: 40
      radius: Theme.radiusSm
      color: Theme.bgHover
      border.width: 1
      border.color: Theme.chromeBorder
      clip: true

      Image {
        id: art
        anchors.fill: parent
        source: root.artUrl
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: status === Image.Ready
      }

      Text {
        anchors.centerIn: parent
        visible: !art.visible
        text: "♫"
        color: Theme.textMute
        font.pixelSize: 18
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: 1

      Text {
        Layout.fillWidth: true
        text: root.title
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: 13
        font.weight: Font.Medium
        elide: Text.ElideRight
      }
      Text {
        Layout.fillWidth: true
        text: root.subtitle
        color: Theme.textDim
        font.family: Theme.fontFamily
        font.pixelSize: 11
        elide: Text.ElideRight
      }
    }

    // Transport — prev / play-pause / next (greyed when unsupported)
    RowLayout {
      spacing: Theme.spaceXs

      Repeater {
        model: [
          { act: "prev", glyph: "⏮" },
          { act: "toggle", glyph: root.playing ? "⏸" : "▶" },
          { act: "next", glyph: "⏭" }
        ]

        Rectangle {
          required property var modelData
          readonly property bool allowed: {
            if (!root.player)
              return false
            if (modelData.act === "prev")
              return root.player.canGoPrevious
            if (modelData.act === "next")
              return root.player.canGoNext
            return root.player.canTogglePlaying
          }

          Layout.preferredWidth: 28
          Layout.preferredHeight: 28
          radius: 14
          color: btnMa.containsMouse && allowed ? Theme.chromeHover : "transparent"
          opacity: allowed ? 1 : 0.35

          scale: btnMa.pressed && allowed ? 0.92 : 1
          Behavior on scale {
            NumberAnimation {
              duration: 90
              easing.type: Easing.OutCubic
            }
          }

          Text {
            anchors.centerIn: parent
            text: parent.modelData.glyph
            color: Theme.text
            font.pixelSize: 13
          }

          MouseArea {
            id: btnMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: parent.allowed ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
              if (!parent.allowed || !root.player)
                return
              if (parent.modelData.act === "prev")
                root.player.previous()
              else if (parent.modelData.act === "next")
                root.player.next()
              else
                root.player.togglePlaying()
            }
          }
        }
      }
    }
  }
}
