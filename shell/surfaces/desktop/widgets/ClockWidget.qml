import Quickshell
import QtQuick
import QtQuick.Layouts
import "../../../shared"

Item {
  id: root
  property var widgetData: null
  property string size: widgetData ? String(widgetData.size || "lg") : "lg"

  readonly property string weight: widgetData ? String(widgetData.clockWeight || "light") : "light"
  readonly property color clockColor: {
    const c = widgetData && widgetData.clockColor ? String(widgetData.clockColor) : "#f5f5f7"
    return c
  }
  readonly property bool showDate: !(widgetData && widgetData.showDate === false)
  readonly property string dateStyle: widgetData ? String(widgetData.dateStyle || "full") : "full"
  readonly property bool depth: !(widgetData && widgetData.clockDepth === false)

  readonly property int timePx: {
    if (size === "sm")
      return 42
    if (size === "md")
      return 64
    return Math.min(96, Math.round(width * 0.22))
  }
  readonly property int datePx: size === "sm" ? 12 : (size === "md" ? 16 : 20)
  readonly property int fontWeight: {
    if (weight === "medium")
      return Font.Medium
    if (weight === "normal")
      return Font.Normal
    return Font.Light
  }

  implicitWidth: col.implicitWidth
  implicitHeight: col.implicitHeight
  width: parent ? parent.width : implicitWidth
  height: implicitHeight

  ColumnLayout {
    id: col
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.verticalCenter: parent.verticalCenter
    width: parent.width
    spacing: 4

    Text {
      Layout.alignment: Qt.AlignHCenter
      Layout.fillWidth: true
      horizontalAlignment: Text.AlignHCenter
      text: Qt.formatDateTime(clock.date, "h:mm")
      color: root.clockColor
      font.family: Theme.fontFamily
      font.pixelSize: root.timePx
      font.weight: root.fontWeight
      style: root.depth ? Text.Outline : Text.Normal
      styleColor: root.depth ? "#66000000" : "transparent"
    }

    Text {
      Layout.alignment: Qt.AlignHCenter
      Layout.fillWidth: true
      visible: root.showDate
      horizontalAlignment: Text.AlignHCenter
      text: root.dateStyle === "short"
          ? Qt.formatDateTime(clock.date, "MMM d")
          : Qt.formatDateTime(clock.date, "dddd, MMMM d")
      color: Qt.rgba(root.clockColor.r, root.clockColor.g, root.clockColor.b, 0.75)
      font.family: Theme.fontFamily
      font.pixelSize: root.datePx
      font.weight: Font.Medium
      style: root.depth ? Text.Outline : Text.Normal
      styleColor: root.depth ? "#66000000" : "transparent"
    }
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
  }
}
