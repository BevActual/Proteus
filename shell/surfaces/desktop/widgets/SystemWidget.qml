import QtQuick
import QtQuick.Layouts
import "../../../shared"

// System glance — CPU / memory / uptime from SystemLoad (storage at L).
// Holds a retain() reference so SystemLoad polls while the widget is placed,
// independent of the Control Center's `watching` flag.
Item {
  id: root
  property string size: "sm"
  property bool showWhenIdle: true
  // Desktop only: click opens Mission Center (or Software to install it)
  property bool interactive: false

  Component.onCompleted: SystemLoad.retain()
  Component.onDestruction: SystemLoad.release()

  implicitWidth: card.implicitWidth
  implicitHeight: card.implicitHeight
  width: parent ? Math.min(parent.width, size === "lg" ? 300 : (size === "md" ? 220 : 160)) : 160
  height: implicitHeight

  readonly property bool detailed: size !== "sm"
  readonly property real cpuFrac: SystemLoad.cpuPercent >= 0
      ? Math.min(1, SystemLoad.cpuPercent / 100) : 0
  readonly property real memFrac: SystemLoad.memTotalGiB > 0
      ? Math.min(1, SystemLoad.memUsedGiB / SystemLoad.memTotalGiB) : 0
  readonly property real diskFrac: SystemLoad.diskTotalGiB > 0
      ? Math.min(1, SystemLoad.diskUsedGiB / SystemLoad.diskTotalGiB) : 0

  component GlanceBar: ColumnLayout {
    property string label: ""
    property string value: ""
    property real frac: 0
    property bool hot: false

    Layout.fillWidth: true
    spacing: 3

    RowLayout {
      Layout.fillWidth: true
      Text {
        Layout.fillWidth: true
        text: label
        color: Qt.rgba(1, 1, 1, 0.55)
        font.family: Theme.fontFamily
        font.pixelSize: 11
      }
      Text {
        text: value
        color: Qt.rgba(1, 1, 1, 0.8)
        font.family: Theme.fontFamily
        font.pixelSize: 11
        font.weight: Font.Medium
      }
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 5
      radius: 2.5
      color: Qt.rgba(1, 1, 1, 0.12)
      Rectangle {
        width: parent.width * Math.max(0, Math.min(1, frac))
        height: parent.height
        radius: 2.5
        color: hot ? "#ff453a" : Theme.accent
        Behavior on width {
          NumberAnimation {
            duration: 400
            easing.type: Easing.OutCubic
          }
        }
      }
    }
  }

  Rectangle {
    id: card
    anchors.left: parent.left
    anchors.right: parent.right
    implicitHeight: body.implicitHeight + 20
    radius: 16
    color: Qt.rgba(28 / 255, 28 / 255, 30 / 255, 0.72)
    border.width: 1
    border.color: sysMa.containsMouse && root.interactive
        ? Qt.rgba(1, 1, 1, 0.25) : Qt.rgba(1, 1, 1, 0.1)

    MouseArea {
      id: sysMa
      anchors.fill: parent
      visible: root.interactive
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        if (MissionCenter.available)
          MissionCenter.open()
        else
          MissionCenter.openSoftware()
      }
      onPressAndHold: ShellState.enterDesktopCustomize()
    }

    ColumnLayout {
      id: body
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: 12
      spacing: 8

      RowLayout {
        Layout.fillWidth: true
        Text {
          Layout.fillWidth: true
          text: "System"
          color: Qt.rgba(1, 1, 1, 0.55)
          font.family: Theme.fontFamily
          font.pixelSize: 11
        }
        Text {
          text: SystemLoad.uptimeLabel !== "—" ? "Up " + SystemLoad.uptimeLabel : ""
          color: Qt.rgba(1, 1, 1, 0.42)
          font.family: Theme.fontFamily
          font.pixelSize: 10
        }
      }

      // Small: one calm summary line, no bars
      Text {
        visible: !root.detailed
        Layout.fillWidth: true
        text: SystemLoad.ready
            ? "CPU " + Math.round(Math.max(0, SystemLoad.cpuPercent)) + "%  ·  Mem "
                + Math.round(root.memFrac * 100) + "%"
            : "Reading…"
        color: "#f5f5f7"
        font.family: Theme.fontFamily
        font.pixelSize: 15
        font.weight: Font.Medium
        elide: Text.ElideRight
      }

      GlanceBar {
        visible: root.detailed
        label: "CPU"
        value: SystemLoad.cpuPercent >= 0 ? Math.round(SystemLoad.cpuPercent) + "%" : "…"
        frac: root.cpuFrac
        hot: SystemLoad.cpuPercent >= 90
      }

      GlanceBar {
        visible: root.detailed
        label: "Memory"
        value: SystemLoad.memTotalGiB > 0
            ? SystemLoad.memUsedGiB.toFixed(1) + " / " + SystemLoad.memTotalGiB.toFixed(1) + " GiB"
            : "…"
        frac: root.memFrac
        hot: root.memFrac >= 0.92
      }

      GlanceBar {
        visible: root.size === "lg"
        label: "Storage /"
        value: SystemLoad.diskTotalGiB > 0
            ? Math.round(root.diskFrac * 100) + "%"
            : "…"
        frac: root.diskFrac
        hot: root.diskFrac >= 0.92
      }
    }
  }
}
