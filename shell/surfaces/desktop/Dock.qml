import Quickshell
import QtQuick
import QtQuick.Window
import "../../shared"

// Matte dock — HiDPI icons; mag from one quantized cursor (no hit-area feedback).
Item {
  id: root
  clip: false

  readonly property real dpr: Math.max(1, Screen.devicePixelRatio || 1)

  // Sizes from Settings → Desktop → Dock & menu bar (Theme clamps)
  readonly property int iconSize: Theme.dockIconSize
  readonly property int maxIconSize: Theme.dockIconMax
  readonly property int spacing: Math.max(8, Math.round(iconSize * 0.2))
  readonly property int padX: Math.max(14, Math.round(iconSize * 0.35))
  readonly property int padTop: Math.max(10, Math.round(iconSize * 0.25))
  readonly property int padBottom: Math.max(12, Math.round(iconSize * 0.28))
  readonly property real magRange: Math.max(96, iconSize * 2.2)

  readonly property real restScale: iconSize / maxIconSize
  readonly property real peakScale: 1.0

  // Device pixels for Image.sourceSize — follows compositor scale (DPR), not resolution guesses
  readonly property int bitmapSize: {
    const need = Math.ceil(maxIconSize * dpr)
    const buckets = [64, 96, 128, 192, 256]
    for (let i = 0; i < buckets.length; i++) {
      if (buckets[i] >= need)
        return buckets[i]
    }
    return Math.max(need, 256)
  }

  readonly property int count: DockApps.visiblePinned.length
  readonly property int tipH: 22
  readonly property int tipGap: 8
  property int mouseX: -1000
  property bool hovered: false
  property int tipIndex: -1

  readonly property real rowWidth: count > 0
      ? count * iconSize + Math.max(0, count - 1) * spacing
      : 0

  readonly property int shelfHeight: iconSize + padTop + padBottom
  readonly property int magHeadroom: (maxIconSize - iconSize) + tipH + tipGap + 12

  implicitWidth: rowWidth + padX * 2
  implicitHeight: shelfHeight + magHeadroom

  function centerAt(index) {
    return padX + index * (iconSize + spacing) + iconSize * 0.5
  }

  function scaleAt(index) {
    if (!hovered || mouseX < 0)
      return restScale
    const d = Math.abs(mouseX - centerAt(index))
    if (d >= magRange)
      return restScale
    const t = (Math.cos(Math.PI * d / magRange) + 1) * 0.5
    return restScale + (peakScale - restScale) * t
  }

  function setMouse(x) {
    // Deadzone: ignore <2px noise (common on 4K / scaled GTK)
    const qx = Math.round(x)
    if (mouseX >= 0 && Math.abs(qx - mouseX) < 2)
      return
    mouseX = qx
  }

  function indexAt(x) {
    for (let i = 0; i < count; i++) {
      const left = padX + i * (iconSize + spacing)
      if (x >= left && x < left + iconSize)
        return i
    }
    return -1
  }

  Rectangle {
    id: plate
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    width: parent.width
    height: root.shelfHeight
    radius: Theme.radiusXl + 2
    color: Theme.panelFill
    border.width: 0
  }

  // Sole input path for mag + click — fixed geometry, never scales
  MouseArea {
    id: dockMa
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    cursorShape: Qt.PointingHandCursor
    onEntered: root.hovered = true
    onExited: {
      root.hovered = false
      root.mouseX = -1000
      root.tipIndex = -1
    }
    onPositionChanged: mouse => {
      root.hovered = true
      root.setMouse(mouse.x)
      root.tipIndex = root.indexAt(mouse.x)
    }
    onClicked: mouse => {
      const i = root.indexAt(mouse.x)
      if (i >= 0)
        DockApps.focusOrLaunch(DockApps.visiblePinned[i])
    }
    onPressed: mouse => {
      root.setMouse(mouse.x)
      root.pressIndex = root.indexAt(mouse.x)
    }
    onReleased: root.pressIndex = -1
    onCanceled: root.pressIndex = -1
  }

  property int pressIndex: -1

  Repeater {
    model: DockApps.visiblePinned

    Item {
      id: cell
      required property var modelData
      required property int index

      readonly property real s: root.scaleAt(index)
      readonly property real rise: root.maxIconSize * (s - root.restScale)
      readonly property bool tipOn: root.tipIndex === index
      readonly property real press: root.pressIndex === index ? 0.92 : 1

      x: root.padX + index * (root.iconSize + root.spacing)
      width: root.iconSize
      height: root.iconSize + root.magHeadroom
      anchors.bottom: parent.bottom
      anchors.bottomMargin: root.padBottom
      // Fixed stacking — continuous z-from-scale caused flicker
      z: tipOn ? 20 : index
      clip: false

      Rectangle {
        visible: cell.tipOn
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height - root.iconSize - cell.rise - root.tipGap - height
        height: root.tipH
        width: tipLabel.implicitWidth + 14
        radius: 7
        color: Qt.rgba(28 / 255, 28 / 255, 30 / 255, 0.94)
        z: 30

        Text {
          id: tipLabel
          anchors.centerIn: parent
          text: modelData.label || modelData.id
          color: Theme.text
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSizeSm
          font.weight: Font.Medium
        }
      }

      Item {
        id: glyph
        width: root.maxIconSize
        height: root.maxIconSize
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        clip: false

        transform: Scale {
          origin.x: glyph.width * 0.5
          origin.y: glyph.height
          xScale: cell.s * cell.press
          yScale: cell.s * cell.press
        }

        Rectangle {
          anchors.centerIn: parent
          width: parent.width * 0.7
          height: parent.height * 0.7
          radius: width * 0.3
          color: DockApps.isActive(modelData)
              ? Theme.chromeAccentSoft
              : (cell.tipOn ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0))
        }

        Image {
          anchors.centerIn: parent
          width: parent.width * 0.84
          height: parent.height * 0.84
          fillMode: Image.PreserveAspectFit
          smooth: true
          mipmap: true
          asynchronous: true
          source: Quickshell.iconPath(modelData.icon || "application-x-executable")
          sourceSize.width: root.bitmapSize
          sourceSize.height: root.bitmapSize
        }
      }

      Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: glyph.bottom
        anchors.topMargin: 5
        width: active ? 5 : 4
        height: width
        radius: width / 2
        color: active ? Theme.accent : Theme.text
        opacity: shown ? (active ? 0.95 : 0.4) : 0
        z: 5

        readonly property bool active: DockApps.isActive(modelData)
        readonly property bool shown: modelData.special === "launcher"
            ? ShellState.launcherOpen
            : DockApps.isRunning(modelData)
      }
    }
  }
}
