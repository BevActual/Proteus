import Quickshell
import QtQuick
import QtQuick.Window
import "../../shared"

// Dock — floating glass shelf; macOS-like pins + running apps + Keep/Remove.
Item {
  id: root
  clip: false

  readonly property real dpr: Math.max(1, Screen.devicePixelRatio || 1)

  readonly property int iconSize: Theme.dockIconSize
  readonly property int maxIconSize: Theme.dockIconMax
  readonly property int spacing: Math.max(6, Math.round(iconSize * 0.14))
  readonly property int padX: Math.max(14, Math.round(iconSize * 0.32))
  readonly property int padTop: Math.max(6, Math.round(iconSize * 0.14))
  readonly property int padBottom: Math.max(8, Math.round(iconSize * 0.18))
  readonly property real magRange: Math.max(96, iconSize * 2.2)

  readonly property real restScale: iconSize / maxIconSize
  readonly property real peakScale: 1.0

  readonly property int bitmapSize: {
    const need = Math.ceil(maxIconSize * dpr)
    const buckets = [64, 96, 128, 192, 256]
    for (let i = 0; i < buckets.length; i++) {
      if (buckets[i] >= need)
        return buckets[i]
    }
    return Math.max(need, 256)
  }

  readonly property var items: DockApps.dockItems
  readonly property int count: items.length
  readonly property int tipH: 22
  readonly property int tipGap: 10
  property int mouseX: -1000
  property bool hovered: false
  property int tipIndex: -1
  property int pressIndex: -1
  property int menuIndex: -1
  property bool menuOpen: false

  readonly property real rowWidth: count > 0
      ? count * iconSize + Math.max(0, count - 1) * spacing
      : 0

  readonly property int shelfHeight: iconSize + padTop + padBottom
  readonly property int magHeadroom: (maxIconSize - iconSize) + tipH + tipGap + 12
  readonly property real plateRadius: shelfHeight * 0.5

  implicitWidth: Math.round(rowWidth + padX * 2)
  implicitHeight: Math.round(shelfHeight + magHeadroom)

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

  function menuEntry() {
    if (menuIndex < 0 || menuIndex >= items.length)
      return null
    return items[menuIndex]
  }

  function openPinMenu(index, x, y) {
    if (index < 0 || index >= items.length)
      return
    const entry = items[index]
    const keep = DockApps.canKeepInDock(entry)
    const remove = DockApps.canUnpin(entry)
    if (!keep && !remove)
      return
    root.menuIndex = index
    root.menuOpen = true
    Qt.callLater(() => {
      ctxMenu.x = Math.max(8, Math.min(x - ctxMenu.width * 0.5, root.width - ctxMenu.width - 8))
      ctxMenu.y = Math.max(4, y - ctxMenu.height - 8)
    })
  }

  function closePinMenu() {
    root.menuOpen = false
    root.menuIndex = -1
  }

  Rectangle {
    id: plate
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    width: parent.width
    height: root.shelfHeight
    radius: root.plateRadius
    color: Theme.dockPlateFill
    antialiasing: true
    border.width: Theme.chromeClear ? 0 : 1
    border.color: Theme.chromeHairline
    z: 1

    // Top specular — floating glass edge (menu bar is full-bleed; dock needs this)
    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      height: Math.max(1, Math.round(parent.height * 0.08))
      radius: parent.radius
      visible: Theme.dockPlateSpecular.a > 0.01
      gradient: Gradient {
        GradientStop {
          position: 0.0
          color: Theme.dockPlateSpecular
        }
        GradientStop {
          position: 1.0
          color: "transparent"
        }
      }
    }

    Behavior on color {
      ColorAnimation {
        duration: 180
        easing.type: Easing.OutCubic
      }
    }
    Behavior on border.color {
      ColorAnimation {
        duration: 180
        easing.type: Easing.OutCubic
      }
    }
  }

  MouseArea {
    id: dockMa
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    z: 10
    onEntered: root.hovered = true
    onExited: {
      if (root.menuOpen)
        return
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
      if (root.menuOpen) {
        root.closePinMenu()
        return
      }
      const i = root.indexAt(mouse.x)
      if (i < 0)
        return
      if (mouse.button === Qt.RightButton) {
        root.openPinMenu(i, mouse.x, mouse.y)
        return
      }
      DockApps.focusOrLaunch(root.items[i])
    }
    onPressed: mouse => {
      root.setMouse(mouse.x)
      root.pressIndex = root.indexAt(mouse.x)
    }
    onReleased: root.pressIndex = -1
    onCanceled: root.pressIndex = -1
  }

  // Context menu — Keep in Dock / Remove from Dock (macOS Options pattern)
  Rectangle {
    id: ctxMenu
    visible: root.menuOpen
    z: 50
    width: Math.max(keepRow.implicitWidth, removeRow.implicitWidth) + 28
    height: (keepRow.visible ? 36 : 0) + (removeRow.visible ? 36 : 0)
    radius: 10
    color: Theme.light ? Qt.rgba(1, 1, 1, 0.96) : Qt.rgba(0.16, 0.16, 0.18, 0.96)
    border.width: 1
    border.color: Theme.light ? Qt.rgba(0, 0, 0, 0.10) : Qt.rgba(1, 1, 1, 0.12)

    Column {
      anchors.fill: parent
      anchors.margins: 0

      Item {
        id: keepRow
        width: parent.width
        height: 36
        visible: {
          const e = root.menuEntry()
          return e && DockApps.canKeepInDock(e)
        }

        Text {
          anchors.centerIn: parent
          text: "Keep in Dock"
          color: Theme.text
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSizeSm
        }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            const e = root.menuEntry()
            if (e)
              DockApps.pinDesktopId(e.desktopId || e.id)
            root.closePinMenu()
          }
        }
      }

      Rectangle {
        width: parent.width
        height: 1
        visible: keepRow.visible && removeRow.visible
        color: Theme.separator
      }

      Item {
        id: removeRow
        width: parent.width
        height: 36
        visible: {
          const e = root.menuEntry()
          return e && DockApps.canUnpin(e)
        }

        Text {
          anchors.centerIn: parent
          text: "Remove from Dock"
          color: Theme.text
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSizeSm
        }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            const e = root.menuEntry()
            if (e)
              DockApps.unpinEntry(e)
            root.closePinMenu()
          }
        }
      }
    }
  }

  Repeater {
    model: root.items

    Item {
      id: cell
      required property var modelData
      required property int index

      readonly property real s: root.scaleAt(index)
      readonly property real rise: root.maxIconSize * (s - root.restScale)
      readonly property bool tipOn: root.tipIndex === index && !root.menuOpen
      readonly property real press: root.pressIndex === index ? 0.92 : 1
      readonly property bool brandIcon: modelData.special === "launcher"
          || modelData.special === "settings"
          || modelData.icon === "proteus-launcher"
          || modelData.icon === "proteus-settings"

      x: root.padX + index * (root.iconSize + root.spacing)
      width: root.iconSize
      height: root.iconSize + root.magHeadroom
      anchors.bottom: parent.bottom
      anchors.bottomMargin: root.padBottom
      z: tipOn ? 20 : (10 + index)
      clip: false

      Rectangle {
        visible: cell.tipOn
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height - root.iconSize - cell.rise - root.tipGap - height
        height: root.tipH
        width: tipLabel.implicitWidth + 16
        radius: 6
        color: Theme.light
            ? Qt.rgba(0.15, 0.15, 0.16, 0.92)
            : Qt.rgba(0.18, 0.18, 0.2, 0.94)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.08)
        z: 30

        Text {
          id: tipLabel
          anchors.centerIn: parent
          text: modelData.label || modelData.id
          color: "#f5f5f7"
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

        SquircleIcon {
          anchors.centerIn: parent
          width: parent.width * Theme.iconFrameScale
          height: width
          pixelSize: root.bitmapSize
          showBorder: false
          fillCrop: false
          glyphScale: cell.brandIcon ? Theme.iconGlyphScaleBrand : Theme.iconGlyphScaleApp
          plate: Theme.iconPlateFill
          source: DockApps.iconSource(modelData)
        }
      }

      Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: -6
        width: active ? 4 : 3
        height: width
        radius: width / 2
        color: active ? Theme.accent : (Theme.light ? Qt.rgba(0, 0, 0, 0.45) : Qt.rgba(1, 1, 1, 0.7))
        opacity: shown ? (active ? 1 : 0.55) : 0
        z: 5

        readonly property bool active: DockApps.isActive(modelData)
        readonly property bool shown: modelData.special === "launcher"
            ? ShellState.launcherOpen
            : DockApps.isRunning(modelData)
      }
    }
  }
}
