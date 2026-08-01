import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../shared"

// Control Center Quick Settings — unified Sound plate + tile chrome.
ColumnLayout {
  id: root
  spacing: Theme.spaceSm

  property int volume: 50
  property bool muted: false
  property bool volumeSliding: false
  property string netSummary: "Checking…"
  property string batteryText: ""

  // Radios (Wi‑Fi via nmcli, Bluetooth via bluetoothctl) — honest skip when
  // the device doesn't exist (typical VM: wired only, no BT adapter).
  property bool wifiSupported: false
  property bool wifiEnabled: true
  property bool btAvailable: false
  property bool btPowered: false

  // Display brightness (Brightness singleton; hidden without a backlight).
  property int brightnessPct: -1
  property bool brightnessSliding: false

  signal volumeChangedByUser(int pct)
  signal muteToggled()
  signal networkClicked()
  signal dndToggled()

  function toggleWifi() {
    const next = !root.wifiEnabled
    root.wifiEnabled = next
    Quickshell.execDetached({
      command: ["nmcli", "radio", "wifi", next ? "on" : "off"]
    })
  }

  function toggleBluetooth() {
    if (!root.btAvailable)
      return
    const next = !root.btPowered
    root.btPowered = next
    Quickshell.execDetached({
      command: ["bluetoothctl", "power", next ? "on" : "off"]
    })
  }

  function refreshRadios() {
    radioProc.running = false
    radioProc.running = true
  }

  function refreshBrightness() {
    if (!Brightness.available || root.brightnessSliding)
      return
    Brightness.getBrightness(p => {
      if (!root.brightnessSliding && p >= 0)
        root.brightnessPct = Math.round(p)
    })
  }

  readonly property string volumeHint: {
    if (root.muted)
      return "Muted"
    return Math.min(100, root.volume) + "%"
  }

  function refreshAudio() {
    if (root.volumeSliding)
      return
    Audio.getVolume(v => {
      if (root.volumeSliding)
        return
      root.volume = Math.max(0, Math.min(150, Math.round(v)))
    })
    Audio.getMute(m => {
      root.muted = !!m
    })
  }

  function refreshNetwork() {
    netProc.running = false
    netProc.running = true
  }

  // Mix strip lifecycle (CC open → resident serve + input peaks).
  property bool mixServeActive: false
  property bool mixPeaksSubscribed: false

  readonly property var mixListenOptions: {
    const opts = [{
        id: "system",
        label: "Speakers"
      }]
    const mixes = Audio.mixMixes || []
    for (let i = 0; i < mixes.length; i++) {
      const m = mixes[i]
      if (!m || !m.id)
        continue
      opts.push({
        id: String(m.id),
        label: String(m.label || m.id)
      })
    }
    return opts
  }

  readonly property var mixSourceOptions: {
    const inputs = Audio.mixInputs || []
    const out = []
    for (let i = 0; i < inputs.length; i++) {
      const inp = inputs[i]
      if (!inp || !inp.id)
        continue
      const label = String(inp.label || inp.id || "Input")
      const sourceName = String(inp.sourceLabel || inp.source || "")
      // Avoid repeating the same string as title + subtitle.
      const detail = (sourceName.length && sourceName !== label) ? sourceName : ""
      out.push({
        id: String(inp.id),
        label: label,
        sourceName: detail,
        volume: Math.max(0, Math.min(150, Math.round(Number(inp.volume) || 100))),
        muted: !!inp.muted,
        on: !inp.muted
      })
    }
    return out
  }

  readonly property string mixSourcesChipLabel: {
    const list = root.mixSourceOptions || []
    if (!list.length)
      return "Add mic…"
    let onCount = 0
    for (let i = 0; i < list.length; i++) {
      if (list[i].on)
        onCount++
    }
    if (list.length === 1)
      return list[0].on ? list[0].label : (list[0].label + " · off")
    return "Sources · " + onCount + "/" + list.length
  }

  function mixInputById(id) {
    const want = String(id || "")
    const inputs = Audio.mixInputs || []
    for (let i = 0; i < inputs.length; i++) {
      if (inputs[i] && String(inputs[i].id) === want)
        return inputs[i]
    }
    return null
  }

  function toggleMixSource(id) {
    const inp = root.mixInputById(id)
    if (!inp || !inp.id)
      return
    Audio.setMixChannelMute(String(inp.id), !inp.muted)
  }

  function mixInputPeakIds() {
    const inputs = Audio.mixInputs || []
    const ids = []
    for (let i = 0; i < inputs.length; i++) {
      const id = inputs[i] && inputs[i].id
      if (id)
        ids.push(String(id))
    }
    return ids
  }

  function syncMixPeaks() {
    if (!root.mixServeActive)
      return
    const inputs = root.mixInputPeakIds()
    if (!inputs.length) {
      if (root.mixPeaksSubscribed) {
        Audio.unsubscribeMixPeaks()
        root.mixPeaksSubscribed = false
      }
      return
    }
    // Merge with any existing peak list (Settings Mixer may already be subscribed).
    const existing = String(Audio.mixPeakDevices || "").split("\n").filter(s => s.length)
    const merged = existing.slice()
    for (let i = 0; i < inputs.length; i++) {
      if (merged.indexOf(inputs[i]) < 0)
        merged.push(inputs[i])
    }
    if (!root.mixPeaksSubscribed) {
      Audio.subscribeMixPeaks(merged)
      root.mixPeaksSubscribed = true
    } else {
      Audio.refreshMixPeakDevices(merged)
    }
  }

  function syncMixLifecycle() {
    const want = root.visible && ShellState.controlCenterOpen
    if (want && !root.mixServeActive) {
      Audio.startMixServe()
      root.mixServeActive = true
      Audio.refreshMix()
      root.syncMixPeaks()
    } else if (!want && root.mixServeActive) {
      if (root.mixPeaksSubscribed) {
        Audio.unsubscribeMixPeaks()
        root.mixPeaksSubscribed = false
      }
      if (Audio.mixVolumeDragging)
        Audio.mixVolumeDragging = false
      Audio.stopMixServe()
      root.mixServeActive = false
    } else if (want && root.mixServeActive) {
      root.syncMixPeaks()
    }
  }

  onVisibleChanged: root.syncMixLifecycle()
  Component.onCompleted: root.syncMixLifecycle()
  Component.onDestruction: {
    if (root.mixPeaksSubscribed) {
      Audio.unsubscribeMixPeaks()
      root.mixPeaksSubscribed = false
    }
    if (root.mixServeActive) {
      Audio.stopMixServe()
      root.mixServeActive = false
    }
  }

  Connections {
    target: ShellState
    function onControlCenterOpenChanged() {
      if (ShellState.controlCenterOpen)
        Power.refreshProfiles()
      root.syncMixLifecycle()
    }
  }

  Connections {
    target: Audio
    function onMixInputsChanged() {
      if (root.mixServeActive)
        root.syncMixPeaks()
    }
  }

  Timer {
    interval: 1200
    running: visible
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      root.refreshAudio()
      root.refreshNetwork()
      root.refreshRadios()
      root.refreshBrightness()
      if (Power.profilesAvailable || !Power.profileBusy)
        Power.refreshProfiles()
    }
  }

  // Wi‑Fi radio + Bluetooth adapter state in one cheap probe per tick.
  Process {
    id: radioProc
    command: [
      "bash",
      "-lc",
      "echo WIFI=$(nmcli -t radio wifi 2>/dev/null || echo none); "
          + "if command -v bluetoothctl >/dev/null 2>&1; then "
          + "  bt=$(timeout 2 bluetoothctl show 2>/dev/null); "
          + "  if echo \"$bt\" | grep -q '^Controller '; then "
          + "    echo BT=yes; "
          + "    echo \"$bt\" | grep -q 'Powered: yes' && echo BTPOW=yes || echo BTPOW=no; "
          + "  else echo BT=no; fi; "
          + "else echo BT=no; fi"
    ]
    stdout: StdioCollector {
      onStreamFinished: {
        const lines = String(text).trim().split("\n")
        for (let i = 0; i < lines.length; i++) {
          const l = lines[i].trim()
          if (l.indexOf("WIFI=") === 0)
            root.wifiEnabled = l === "WIFI=enabled"
          else if (l === "BT=yes")
            root.btAvailable = true
          else if (l === "BT=no")
            root.btAvailable = false
          else if (l.indexOf("BTPOW=") === 0)
            root.btPowered = l === "BTPOW=yes"
        }
      }
    }
  }

  Process {
    id: netProc
    command: ["nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "dev", "status"]
    stdout: StdioCollector {
      onStreamFinished: {
        const lines = String(text).trim().split("\n").filter(l => l.length)
        let best = "No connection"
        let sawWifi = false
        for (let i = 0; i < lines.length; i++) {
          const p = lines[i].split(":")
          if (p.length < 3)
            continue
          const type = p[1]
          const state = p[2]
          const conn = p.length > 3 ? p.slice(3).join(":") : ""
          if (type === "wifi")
            sawWifi = true
          if (state.indexOf("connected") >= 0 && state.indexOf("disconnected") < 0) {
            if (type === "wifi") {
              best = conn.length ? conn : "Wi‑Fi"
              break
            }
            if (type === "ethernet")
              best = conn.length ? conn : "Ethernet"
            else if (best === "No connection")
              best = conn.length ? conn : type
          }
        }
        root.wifiSupported = sawWifi
        root.netSummary = best
      }
    }
  }

  // Unified Sound plate — master volume on plate; per-source levels in Sources ▾.
  Rectangle {
    id: soundPlate
    Layout.fillWidth: true
    implicitHeight: soundCol.implicitHeight + Theme.spaceSm * 2
    radius: Theme.radiusLg
    color: Theme.elevatedFill
    border.width: 1
    border.color: Theme.chromeBorder

    ColumnLayout {
      id: soundCol
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Theme.spaceSm
      spacing: Theme.spaceSm

      RowLayout {
        id: soundHeader
        Layout.fillWidth: true
        spacing: Theme.spaceSm

        Text {
          text: "Sound"
          color: Theme.text
          font.family: Theme.fontFamily
          font.pixelSize: 13
          font.weight: Font.Medium
        }

        // Listen target (exclusive).
        Item {
          id: listenCombo
          Layout.preferredWidth: 110
          Layout.preferredHeight: 28
          implicitHeight: 28

          readonly property string currentValue: {
            const v = String(Audio.mixListening || "system")
            return v.length ? v : "system"
          }
          readonly property string currentLabel: {
            const list = root.mixListenOptions || []
            for (let i = 0; i < list.length; i++) {
              if (String(list[i].id) === listenCombo.currentValue)
                return String(list[i].label || list[i].id)
            }
            return listenCombo.currentValue === "system" ? "Speakers" : listenCombo.currentValue
          }

          Rectangle {
            id: listenChip
            anchors.fill: parent
            radius: Theme.radiusSm
            color: {
              if (listenPopup.visible || listenMa.containsMouse)
                return Theme.bgHover
              if (listenCombo.currentValue !== "system")
                return Theme.accentSoft
              return Theme.bgElevated
            }
            border.width: 1
            border.color: listenPopup.visible || listenCombo.currentValue !== "system"
                ? Theme.accent
                : Theme.chromeBorder

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: Theme.spaceSm
              anchors.rightMargin: Theme.spaceSm
              spacing: Theme.spaceXs

              Text {
                Layout.fillWidth: true
                text: listenCombo.currentLabel
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 12
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
              }

              Text {
                text: "▾"
                color: Theme.textMute
                font.family: Theme.fontFamily
                font.pixelSize: 10
              }
            }

            MouseArea {
              id: listenMa
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              // Toggle on click only. CloseOnPressOutside would dismiss on press
              // over this chip (outside the popup), then onClicked would reopen.
              onClicked: {
                if (sourcesPopup.visible)
                  sourcesPopup.close()
                if (listenPopup.visible)
                  listenPopup.close()
                else
                  listenPopup.open()
              }
            }
          }

          Popup {
            id: listenPopup
            y: listenChip.height + 4
            x: 0
            width: Math.max(140, listenChip.width)
            padding: 4
            // Parent = listenCombo (includes chip) so chip press doesn't auto-dismiss.
            closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
            modal: false

            enter: Transition {
              NumberAnimation {
                property: "opacity"
                from: 0
                to: 1
                duration: 120
                easing.type: Easing.OutCubic
              }
              NumberAnimation {
                property: "scale"
                from: 0.96
                to: 1
                duration: 120
                easing.type: Easing.OutCubic
              }
            }
            exit: Transition {
              NumberAnimation {
                property: "opacity"
                from: 1
                to: 0
                duration: 90
                easing.type: Easing.InCubic
              }
            }

            background: Rectangle {
              radius: Theme.radiusMd
              color: Theme.bgElevated
              border.width: 1
              border.color: Theme.border
            }

            contentItem: ListView {
              id: listenList
              clip: true
              implicitHeight: Math.min(contentHeight, 180)
              model: root.mixListenOptions
              spacing: 1
              boundsBehavior: Flickable.StopAtBounds
              header: Item {
                width: listenList.width
                height: 22
                Text {
                  anchors.left: parent.left
                  anchors.leftMargin: Theme.spaceSm
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Listen"
                  color: Theme.textMute
                  font.family: Theme.fontFamily
                  font.pixelSize: 10
                  font.weight: Font.Medium
                }
              }

              delegate: Rectangle {
                required property var modelData
                readonly property bool selected: String(modelData.id) === listenCombo.currentValue
                width: listenList.width
                height: 32
                radius: Theme.radiusSm
                color: {
                  if (selected)
                    return Theme.accentSoft
                  if (listenRowMa.containsMouse)
                    return Theme.bgHover
                  return "transparent"
                }

                RowLayout {
                  anchors.fill: parent
                  anchors.leftMargin: Theme.spaceSm
                  anchors.rightMargin: Theme.spaceSm
                  spacing: Theme.spaceSm

                  Text {
                    Layout.fillWidth: true
                    text: modelData.label
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                  }

                  Text {
                    visible: selected
                    text: "✓"
                    color: Theme.accent
                    font.pixelSize: 13
                  }
                }

                MouseArea {
                  id: listenRowMa
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    const id = String(modelData.id || "")
                    listenPopup.close()
                    if (id.length && id !== listenCombo.currentValue)
                      Audio.listenMixBus(id)
                  }
                }
              }
            }
          }
        }

        // Sources dropdown — per-mix input volumes live here (master stays on the plate).
        Item {
          id: sourcesCombo
          Layout.fillWidth: true
          Layout.preferredHeight: 28
          Layout.maximumWidth: 200
          implicitHeight: 28

          Rectangle {
            id: sourcesChip
            anchors.fill: parent
            radius: Theme.radiusSm
            color: sourcesPopup.visible || sourcesMa.containsMouse ? Theme.bgHover : Theme.bgElevated
            border.width: 1
            border.color: sourcesPopup.visible ? Theme.accent : Theme.chromeBorder
            opacity: (root.mixSourceOptions || []).length ? 1 : 0.55

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: Theme.spaceSm
              anchors.rightMargin: Theme.spaceSm
              spacing: Theme.spaceXs

              Text {
                Layout.fillWidth: true
                text: root.mixSourcesChipLabel
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 12
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
              }

              Text {
                text: "▾"
                color: Theme.textMute
                font.family: Theme.fontFamily
                font.pixelSize: 10
              }
            }

            MouseArea {
              id: sourcesMa
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (!(root.mixSourceOptions || []).length) {
                  ShellState.openSettings("sound-matrix")
                  return
                }
                if (listenPopup.visible)
                  listenPopup.close()
                if (sourcesPopup.visible)
                  sourcesPopup.close()
                else
                  sourcesPopup.open()
              }
            }
          }

          Popup {
            id: sourcesPopup
            // Span the Sound plate / Quick Settings column (not just the chip).
            parent: soundPlate
            x: Theme.spaceSm
            y: Theme.spaceSm + soundHeader.height + Theme.spaceSm
            width: Math.max(160, soundPlate.width - Theme.spaceSm * 2)
            padding: 6
            // Parent = soundPlate so chip press doesn't auto-dismiss; click outside plate does.
            closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
            modal: false

            enter: Transition {
              NumberAnimation {
                property: "opacity"
                from: 0
                to: 1
                duration: 120
                easing.type: Easing.OutCubic
              }
              NumberAnimation {
                property: "scale"
                from: 0.96
                to: 1
                duration: 120
                easing.type: Easing.OutCubic
              }
            }
            exit: Transition {
              NumberAnimation {
                property: "opacity"
                from: 1
                to: 0
                duration: 90
                easing.type: Easing.InCubic
              }
            }

            background: Rectangle {
              radius: Theme.radiusMd
              color: Theme.bgElevated
              border.width: 1
              border.color: Theme.border
            }

            contentItem: ListView {
              id: sourcesList
              clip: true
              implicitHeight: Math.min(contentHeight, 280)
              model: root.mixSourceOptions
              spacing: Theme.spaceSm
              boundsBehavior: Flickable.StopAtBounds

              header: Item {
                width: sourcesList.width
                height: srcHdr.implicitHeight + 8
                ColumnLayout {
                  id: srcHdr
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.margins: 2
                  spacing: 2
                  Text {
                    text: "Mix sources"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    font.weight: Font.Medium
                  }
                  Text {
                    text: "Listening · " + listenCombo.currentLabel
                    color: Theme.textMute
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                  }
                }
              }

              footer: Item {
                width: sourcesList.width
                height: 28
                Text {
                  anchors.left: parent.left
                  anchors.leftMargin: 2
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Mixer ›"
                  color: Theme.accent
                  font.family: Theme.fontFamily
                  font.pixelSize: 12
                  font.weight: Font.Medium
                  MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      sourcesPopup.close()
                      ShellState.openSettings("sound-matrix")
                    }
                  }
                }
              }

              delegate: Rectangle {
                id: sourceDelegate
                required property var modelData
                readonly property bool sourceOn: !!modelData.on
                readonly property real peak: Audio.mixPeakFor(modelData.id)
                property int slideVol: -1
                readonly property int displayVol: {
                  if (sourceDelegate.slideVol >= 0)
                    return sourceDelegate.slideVol
                  return Math.max(0, Math.min(150, Math.round(Number(modelData.volume) || 100)))
                }

                width: sourcesList.width
                height: sourceBody.implicitHeight + 12
                radius: Theme.radiusSm
                color: sourceOn ? Theme.accentSoft : "transparent"
                border.width: 1
                border.color: sourceOn ? Theme.accent : "transparent"

                ColumnLayout {
                  id: sourceBody
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.margins: 6
                  spacing: 4

                  RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spaceSm

                    ColumnLayout {
                      Layout.fillWidth: true
                      spacing: 1

                      Text {
                        Layout.fillWidth: true
                        text: modelData.label
                        color: sourceDelegate.sourceOn ? Theme.text : Theme.textMute
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                      }

                      Text {
                        visible: !!(modelData.sourceName && String(modelData.sourceName).length)
                        Layout.fillWidth: true
                        text: String(modelData.sourceName || "")
                        color: Theme.textMute
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        elide: Text.ElideRight
                      }
                    }

                    Rectangle {
                      Layout.preferredWidth: 36
                      Layout.preferredHeight: 22
                      radius: Theme.radiusSm
                      color: sourceDelegate.sourceOn ? Theme.accent : Theme.bgHover
                      border.width: sourceDelegate.sourceOn ? 0 : 1
                      border.color: Theme.separator
                      Text {
                        anchors.centerIn: parent
                        text: sourceDelegate.sourceOn ? "On" : "Off"
                        color: sourceDelegate.sourceOn ? "#ffffff" : Theme.textMute
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.weight: Font.Medium
                      }
                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggleMixSource(modelData.id)
                      }
                    }
                  }

                  Rectangle {
                    Layout.fillWidth: true
                    height: 3
                    radius: 1.5
                    color: Theme.chromeBorder
                    opacity: sourceDelegate.sourceOn ? 1 : 0.4
                    Rectangle {
                      anchors.left: parent.left
                      anchors.top: parent.top
                      anchors.bottom: parent.bottom
                      width: parent.width * Math.max(0, Math.min(1, sourceDelegate.peak / 100))
                      radius: 1.5
                      color: Theme.accent
                    }
                  }

                  RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spaceSm

                    ThemeSlider {
                      Layout.fillWidth: true
                      from: 0
                      to: 100
                      value: Math.min(100, sourceDelegate.displayVol)
                      enabled: sourceDelegate.sourceOn
                      opacity: sourceDelegate.sourceOn ? 1 : 0.4
                      onMoved: {
                        sourceDelegate.slideVol = Math.round(value)
                        Audio.setMixChannelVolume(modelData.id, sourceDelegate.slideVol)
                      }
                      onPressedChanged: {
                        Audio.mixVolumeDragging = pressed
                        if (!pressed)
                          sourceDelegate.slideVol = -1
                      }
                    }

                    Text {
                      text: sourceDelegate.sourceOn
                          ? (Math.min(100, sourceDelegate.displayVol) + "%")
                          : "Off"
                      color: Theme.textDim
                      font.family: Theme.fontFamily
                      font.pixelSize: Theme.fontSizeSm
                      Layout.preferredWidth: 36
                      horizontalAlignment: Text.AlignRight
                    }
                  }
                }
              }
            }
          }
        }

        Text {
          text: "Mixer ›"
          color: Theme.textMute
          font.family: Theme.fontFamily
          font.pixelSize: 12
          MouseArea {
            anchors.fill: parent
            anchors.margins: -6
            cursorShape: Qt.PointingHandCursor
            onClicked: ShellState.openSettings("sound-matrix")
          }
        }
      }

      // Master output — always on the plate (not in a dropdown).
      RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spaceSm

        Text {
          text: root.muted ? "Unmute" : "Mute"
          color: root.muted ? Theme.accent : Theme.textMute
          font.family: Theme.fontFamily
          font.pixelSize: 12
          font.weight: Font.Medium
          Layout.preferredWidth: 52
          MouseArea {
            anchors.fill: parent
            anchors.margins: -6
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.muteToggled()
              root.muted = !root.muted
              Audio.setMute(root.muted)
            }
          }
        }

        ThemeSlider {
          id: volSlider
          Layout.fillWidth: true
          from: 0
          to: 100
          value: Math.min(100, root.volume)
          onMoved: {
            root.volume = Math.round(value)
            root.volumeChangedByUser(root.volume)
            Audio.setVolume(root.volume)
            if (root.muted) {
              root.muted = false
              Audio.setMute(false)
            }
          }
          onPressedChanged: {
            root.volumeSliding = pressed
            if (!pressed)
              root.refreshAudio()
          }
        }

        Text {
          text: root.volumeHint
          color: root.muted ? Theme.textMute : Theme.textDim
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSizeSm
          Layout.preferredWidth: 44
          horizontalAlignment: Text.AlignRight
        }
      }
    }
  }

  // Display plate — brightness slider (only with a real backlight; VM hides it).
  Rectangle {
    visible: Brightness.available && root.brightnessPct >= 0
    Layout.fillWidth: true
    implicitHeight: brightCol.implicitHeight + Theme.spaceSm * 2
    radius: Theme.radiusLg
    color: Theme.elevatedFill
    border.width: 1
    border.color: Theme.chromeBorder

    ColumnLayout {
      id: brightCol
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Theme.spaceSm
      spacing: Theme.spaceSm

      Text {
        text: "Display"
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: 13
        font.weight: Font.Medium
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spaceSm

        Text {
          text: "Brightness"
          color: Theme.textMute
          font.family: Theme.fontFamily
          font.pixelSize: 12
          Layout.preferredWidth: 52
        }

        ThemeSlider {
          Layout.fillWidth: true
          from: 5
          to: 100
          value: Math.max(5, root.brightnessPct)
          onMoved: {
            root.brightnessPct = Math.round(value)
            Brightness.setBrightness(root.brightnessPct)
          }
          onPressedChanged: {
            root.brightnessSliding = pressed
            if (!pressed)
              root.refreshBrightness()
          }
        }

        Text {
          text: root.brightnessPct + "%"
          color: Theme.textDim
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSizeSm
          Layout.preferredWidth: 44
          horizontalAlignment: Text.AlignRight
        }
      }
    }
  }

  // Tile grid
  GridLayout {
    Layout.fillWidth: true
    columns: 2
    rowSpacing: Theme.spaceSm
    columnSpacing: Theme.spaceSm

    Repeater {
      model: {
        const connected = root.netSummary !== "No connection" && root.netSummary !== "Checking…"
        const tiles = []
        tiles.push({
          id: "net",
          glyph: "⇅",
          title: root.wifiSupported ? "Wi‑Fi" : "Network",
          subtitle: root.wifiSupported && !root.wifiEnabled
              ? "Wi‑Fi off"
              : (root.netSummary === "No connection" ? "Not connected" : root.netSummary),
          accent: connected && (!root.wifiSupported || root.wifiEnabled),
          interactive: true,
          trailing: "›",
          span: root.btAvailable ? 1 : 2
        })
        if (root.btAvailable) {
          tiles.push({
            id: "bt",
            glyph: "ᛒ",
            title: "Bluetooth",
            subtitle: root.btPowered ? "On" : "Off",
            accent: root.btPowered,
            interactive: true,
            trailing: root.btPowered ? "On" : "Off"
          })
        }
        tiles.push({
          id: "localsend",
          glyph: "➤",
          title: "LocalSend",
          subtitle: !LocalSend.available
              ? "Not installed · tap for options"
              : (LocalSend.running
                  ? LocalSend.hint
                  : (LocalSend.receiveEndpoint.length
                      ? ("Share nearby · " + LocalSend.receiveEndpoint)
                      : "Share files nearby")),
          accent: LocalSend.available && LocalSend.running,
          interactive: true,
          trailing: LocalSend.available ? (LocalSend.shortLabel + " ›") : "›"
        })
        tiles.push({
          id: "power",
          glyph: "⏻",
          title: "Power",
          subtitle: !Power.profilesAvailable
              ? (root.batteryText.length ? root.batteryText : "Profiles unavailable")
              : (root.batteryText.length
                  ? (root.batteryText + " · " + Power.activeProfileLabel)
                  : Power.activeProfileLabel),
          accent: Power.profilesAvailable && Power.activeProfile === "performance",
          interactive: Power.profilesAvailable && Power.profileOptions.length > 0,
          trailing: Power.profilesAvailable ? "›" : ""
        })
        tiles.push({
          id: "dnd",
          glyph: "☾",
          title: "Do Not Disturb",
          // State lives on the accent disc — no trailing text (room for title).
          subtitle: Config.notificationsDnd ? "Toasts off" : "Toasts on",
          accent: Config.notificationsDnd,
          interactive: true,
          trailing: ""
        })
        tiles.push({
          id: "awake",
          glyph: "✦",
          title: "Keep Awake",
          subtitle: KeepAwake.active ? KeepAwake.label : "Off",
          accent: KeepAwake.active,
          interactive: true,
          trailing: "›"
        })
        tiles.push({
          id: "console",
          glyph: "▶",
          title: "Console",
          subtitle: "Hard switch · lean-back",
          accent: false,
          interactive: true,
          trailing: "›",
          span: 2
        })
        return tiles
      }

      Rectangle {
        id: tile
        required property var modelData
        Layout.fillWidth: true
        Layout.columnSpan: modelData.span || 1
        Layout.preferredHeight: 64
        radius: Theme.radiusLg
        // Same hover language as rows/menus — tiles brighten, accent stays selection.
        color: {
          if (tileMa.containsMouse && modelData.interactive)
            return modelData.accent ? Theme.chromeAccentSoft : Theme.chromeHover
          return modelData.accent ? Theme.chromeAccentSoft : Theme.elevatedFill
        }
        border.width: 1
        border.color: modelData.accent
            ? Theme.accent
            : (tileMa.containsMouse && modelData.interactive ? Theme.border : Theme.chromeBorder)

        Behavior on color {
          ColorAnimation {
            duration: 120
            easing.type: Easing.OutCubic
          }
        }

        // Press feedback — tiles feel physical (dock press language)
        scale: tileMa.pressed && modelData.interactive ? 0.97 : 1
        Behavior on scale {
          NumberAnimation {
            duration: 100
            easing.type: Easing.OutCubic
          }
        }

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: Theme.spaceSm
          anchors.rightMargin: Theme.spaceMd
          spacing: Theme.spaceSm

          // Icon disc — accent-filled when the control is active (macOS CC).
          Rectangle {
            Layout.preferredWidth: 30
            Layout.preferredHeight: 30
            radius: 15
            color: modelData.accent ? Theme.accent : Theme.bgElevated
            border.width: modelData.accent ? 0 : 1
            border.color: Theme.chromeBorder

            Behavior on color {
              ColorAnimation {
                duration: 140
                easing.type: Easing.OutCubic
              }
            }

            Text {
              anchors.centerIn: parent
              text: modelData.glyph || ""
              color: modelData.accent ? "#ffffff" : Theme.textDim
              font.family: Theme.fontFamily
              font.pixelSize: 14
            }
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Text {
              text: modelData.title
              color: Theme.text
              font.family: Theme.fontFamily
              font.pixelSize: 13
              font.weight: Font.Medium
              elide: Text.ElideRight
              Layout.fillWidth: true
            }
            Text {
              text: modelData.subtitle
              color: Theme.textDim
              font.family: Theme.fontFamily
              font.pixelSize: 11
              elide: Text.ElideRight
              Layout.fillWidth: true
            }
          }

          Text {
            visible: modelData.trailing && String(modelData.trailing).length > 0
            text: modelData.trailing || ""
            color: modelData.accent ? Theme.accent : Theme.textMute
            font.family: Theme.fontFamily
            font.pixelSize: 12
          }
        }

        MouseArea {
          id: tileMa
          anchors.fill: parent
          enabled: modelData.interactive
          hoverEnabled: true
          cursorShape: modelData.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: {
            if (modelData.id === "net") {
              // With a Wi‑Fi device the tile owns a quick menu (radio toggle);
              // wired-only hosts jump straight to Settings → Network.
              if (!root.wifiSupported) {
                root.networkClicked()
                return
              }
              if (wifiPopup.visible)
                wifiPopup.close()
              else
                wifiPopup.open()
            } else if (modelData.id === "bt")
              root.toggleBluetooth()
            else if (modelData.id === "localsend") {
              if (localSendPopup.visible)
                localSendPopup.close()
              else {
                LocalSend.refresh()
                localSendPopup.open()
              }
            } else if (modelData.id === "dnd")
              root.dndToggled()
            else if (modelData.id === "power") {
              if (powerPopup.visible)
                powerPopup.close()
              else {
                Power.refreshProfiles()
                powerPopup.open()
              }
            } else if (modelData.id === "awake") {
              if (awakePopup.visible)
                awakePopup.close()
              else
                awakePopup.open()
            } else if (modelData.id === "console") {
              ShellState.closeControlCenter()
              const proot = String(Quickshell.env("PROTEUS_ROOT") || "/mnt/proteus")
              Quickshell.execDetached({
                command: [
                  "bash", "-lc",
                  "command -v proteus-posture >/dev/null && setsid proteus-posture console >/dev/null 2>&1 & "
                      + "|| setsid " + proot + "/vm/guest/proteus-posture console >/dev/null 2>&1 &"
                ]
              })
            }
          }
        }

        // Wi‑Fi quick menu — radio toggle + Settings escape.
        Popup {
          id: wifiPopup
          visible: false
          enabled: modelData.id === "net"
          y: tile.height + 4
          x: 0
          width: Math.max(200, tile.width)
          padding: 4
          closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
          modal: false

          enter: Transition {
            NumberAnimation {
              property: "opacity"
              from: 0
              to: 1
              duration: 120
              easing.type: Easing.OutCubic
            }
            NumberAnimation {
              property: "scale"
              from: 0.96
              to: 1
              duration: 120
              easing.type: Easing.OutCubic
            }
          }
          exit: Transition {
            NumberAnimation {
              property: "opacity"
              from: 1
              to: 0
              duration: 90
              easing.type: Easing.InCubic
            }
          }

          background: Rectangle {
            radius: Theme.radiusMd
            color: Theme.bgElevated
            border.width: 1
            border.color: Theme.border
          }

          contentItem: Column {
            spacing: 1

            Rectangle {
              width: wifiPopup.width - 8
              height: 36
              radius: Theme.radiusSm
              color: wifiToggleMa.containsMouse ? Theme.bgHover : "transparent"

              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.spaceSm
                anchors.rightMargin: Theme.spaceSm
                spacing: Theme.spaceSm

                Text {
                  Layout.fillWidth: true
                  text: "Wi‑Fi"
                  color: Theme.text
                  font.family: Theme.fontFamily
                  font.pixelSize: 12
                  verticalAlignment: Text.AlignVCenter
                }

                ThemeSwitch {
                  checked: root.wifiEnabled
                  onToggled: {
                    root.toggleWifi()
                    // Re-establish the binding the interactive toggle broke.
                    checked = Qt.binding(() => root.wifiEnabled)
                  }
                }
              }

              MouseArea {
                id: wifiToggleMa
                anchors.fill: parent
                hoverEnabled: true
                propagateComposedEvents: true
                cursorShape: Qt.PointingHandCursor
                z: -1
                onClicked: root.toggleWifi()
              }
            }

            Rectangle {
              width: wifiPopup.width - 8
              height: 32
              radius: Theme.radiusSm
              color: wifiSettingsMa.containsMouse ? Theme.bgHover : "transparent"

              Text {
                anchors.left: parent.left
                anchors.leftMargin: Theme.spaceSm
                anchors.verticalCenter: parent.verticalCenter
                text: "Network Settings ›"
                color: Theme.accent
                font.family: Theme.fontFamily
                font.pixelSize: 12
                font.weight: Font.Medium
              }

              MouseArea {
                id: wifiSettingsMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  wifiPopup.close()
                  root.networkClicked()
                }
              }
            }
          }
        }

        // LocalSend actions (start/stop, open, copy address, settings).
        Popup {
          id: localSendPopup
          visible: false
          enabled: modelData.id === "localsend"
          y: tile.height + 4
          x: Math.max(0, tile.width - width)
          width: Math.max(220, tile.width)
          padding: 4
          closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
          modal: false

          enter: Transition {
            NumberAnimation {
              property: "opacity"
              from: 0
              to: 1
              duration: 120
              easing.type: Easing.OutCubic
            }
            NumberAnimation {
              property: "scale"
              from: 0.96
              to: 1
              duration: 120
              easing.type: Easing.OutCubic
            }
          }
          exit: Transition {
            NumberAnimation {
              property: "opacity"
              from: 1
              to: 0
              duration: 90
              easing.type: Easing.InCubic
            }
          }

          background: Rectangle {
            radius: Theme.radiusMd
            color: Theme.bgElevated
            border.width: 1
            border.color: Theme.border
          }

          contentItem: ListView {
            id: localSendList
            clip: true
            implicitHeight: Math.min(contentHeight, 280)
            model: modelData.id === "localsend" ? LocalSend.menuOptions : []
            spacing: 1
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
              required property var modelData
              width: localSendList.width
              height: 32
              radius: Theme.radiusSm
              color: {
                if (modelData.id === "stop" && LocalSend.running)
                  return Theme.accentSoft
                if (lsRowMa.containsMouse)
                  return Theme.bgHover
                return "transparent"
              }

              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.spaceSm
                anchors.rightMargin: Theme.spaceSm
                spacing: Theme.spaceSm

                Text {
                  Layout.fillWidth: true
                  text: modelData.title
                  color: Theme.text
                  font.family: Theme.fontFamily
                  font.pixelSize: 12
                  elide: Text.ElideRight
                  verticalAlignment: Text.AlignVCenter
                }

                Text {
                  visible: modelData.id === "stop" && LocalSend.running
                  text: "✓"
                  color: Theme.accent
                  font.pixelSize: 13
                }
              }

              MouseArea {
                id: lsRowMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  const act = modelData.id
                  LocalSend.select(act)
                  localSendPopup.close()
                  if (act === "settings" || act === "open" || act === "start")
                    ShellState.closeControlCenter()
                }
              }
            }
          }
        }

        // Power mode menu (Performance / Balanced / Eco).
        Popup {
          id: powerPopup
          visible: false
          enabled: modelData.id === "power"
          y: tile.height + 4
          x: Math.max(0, tile.width - width)
          width: Math.max(200, tile.width)
          padding: 4
          closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
          modal: false

          enter: Transition {
            NumberAnimation {
              property: "opacity"
              from: 0
              to: 1
              duration: 120
              easing.type: Easing.OutCubic
            }
            NumberAnimation {
              property: "scale"
              from: 0.96
              to: 1
              duration: 120
              easing.type: Easing.OutCubic
            }
          }
          exit: Transition {
            NumberAnimation {
              property: "opacity"
              from: 1
              to: 0
              duration: 90
              easing.type: Easing.InCubic
            }
          }

          background: Rectangle {
            radius: Theme.radiusMd
            color: Theme.bgElevated
            border.width: 1
            border.color: Theme.border
          }

          contentItem: ListView {
            id: powerList
            clip: true
            implicitHeight: Math.min(contentHeight, 200)
            model: modelData.id === "power" ? Power.profileOptions : []
            spacing: 1
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
              required property var modelData
              width: powerList.width
              height: 32
              radius: Theme.radiusSm
              color: {
                if (modelData.id === Power.activeProfile)
                  return Theme.accentSoft
                if (powerRowMa.containsMouse)
                  return Theme.bgHover
                return "transparent"
              }

              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.spaceSm
                anchors.rightMargin: Theme.spaceSm
                spacing: Theme.spaceSm

                Text {
                  Layout.fillWidth: true
                  text: modelData.label
                  color: Theme.text
                  font.family: Theme.fontFamily
                  font.pixelSize: 12
                  elide: Text.ElideRight
                  verticalAlignment: Text.AlignVCenter
                }

                Text {
                  visible: modelData.id === Power.activeProfile
                  text: "✓"
                  color: Theme.accent
                  font.pixelSize: 13
                }
              }

              MouseArea {
                id: powerRowMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  Power.setProfile(modelData.id)
                  powerPopup.close()
                }
              }
            }
          }
        }

        // Amphetamine-style duration menu (only on Keep Awake tile).
        Popup {
          id: awakePopup
          visible: false
          enabled: modelData.id === "awake"
          y: tile.height + 4
          x: Math.max(0, tile.width - width)
          width: Math.max(200, tile.width)
          padding: 4
          closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
          modal: false

          enter: Transition {
            NumberAnimation {
              property: "opacity"
              from: 0
              to: 1
              duration: 120
              easing.type: Easing.OutCubic
            }
            NumberAnimation {
              property: "scale"
              from: 0.96
              to: 1
              duration: 120
              easing.type: Easing.OutCubic
            }
          }
          exit: Transition {
            NumberAnimation {
              property: "opacity"
              from: 1
              to: 0
              duration: 90
              easing.type: Easing.InCubic
            }
          }

          background: Rectangle {
            radius: Theme.radiusMd
            color: Theme.bgElevated
            border.width: 1
            border.color: Theme.border
          }

          contentItem: ListView {
            id: awakeList
            clip: true
            implicitHeight: Math.min(contentHeight, 320)
            model: modelData.id === "awake" ? KeepAwake.menuOptions : []
            spacing: 1
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
              required property var modelData
              width: awakeList.width
              height: 32
              radius: Theme.radiusSm
              color: {
                const selected = (modelData.id === "off" && !KeepAwake.active)
                    || (modelData.id === KeepAwake.mode)
                if (selected)
                  return Theme.accentSoft
                if (rowMa.containsMouse)
                  return Theme.bgHover
                return "transparent"
              }

              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.spaceSm
                anchors.rightMargin: Theme.spaceSm
                spacing: Theme.spaceSm

                Text {
                  Layout.fillWidth: true
                  text: modelData.title
                  color: Theme.text
                  font.family: Theme.fontFamily
                  font.pixelSize: 12
                  elide: Text.ElideRight
                  verticalAlignment: Text.AlignVCenter
                }

                Text {
                  visible: (modelData.id === "off" && !KeepAwake.active)
                      || (modelData.id === KeepAwake.mode)
                  text: "✓"
                  color: Theme.accent
                  font.pixelSize: 13
                }
              }

              MouseArea {
                id: rowMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  KeepAwake.select(modelData.id)
                  awakePopup.close()
                }
              }
            }
          }
        }
      }
    }
  }
}
