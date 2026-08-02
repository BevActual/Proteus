import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtMultimedia
import "../../shared"

// Proteus lock surface — Customize Lock Screen (Apple-style zones + applets).
Item {
  id: root
  anchors.fill: parent

  signal unlocked()

  property bool unlockInProgress: false
  property bool showFailure: false
  property string statusText: ""

  // Rate limiting. PAM's own delay is not something we can rely on from an
  // unprivileged locker, so the cooldown is enforced here: after a few misses
  // each further attempt costs progressively more wall-clock time. Deliberately
  // NOT reset by re-locking — only a successful unlock clears it.
  property int failedAttempts: 0
  property int cooldownRemaining: 0
  readonly property bool cooldownActive: root.cooldownRemaining > 0
  readonly property bool inputBlocked: root.unlockInProgress || root.cooldownActive

  readonly property int freeAttempts: 3

  function cooldownFor(attempts) {
    const over = attempts - root.freeAttempts
    if (over < 1)
      return 0
    return Math.min(60, [5, 10, 30][over - 1] || 60)
  }

  Timer {
    id: cooldownTimer
    interval: 1000
    repeat: true
    running: root.cooldownRemaining > 0
    onTriggered: {
      root.cooldownRemaining = Math.max(0, root.cooldownRemaining - 1)
      if (root.cooldownRemaining === 0 && root.revealAuth)
        root.focusAuthInput()
    }
  }
  property bool revealAuth: false
  property bool customizeMode: false
  property string selectedWidgetId: ""
  property bool showGallery: false
  property bool showWallpaperSheet: false

  // PIN unlock (optional). When configured, default to numpad; password remains
  // an alternate path via "Use password".
  property bool pinConfigured: false
  property int pinLength: 0
  property bool usePassword: false
  property string pinDigits: ""
  property string authMode: "password" // pin | password — last attempt for helper

  readonly property bool pinMode: root.pinConfigured && !root.usePassword

  readonly property string userName: {
    const u = Quickshell.env("USER")
    return (u && u.length) ? u : "user"
  }

  readonly property string helperPath: {
    const u = Qt.resolvedUrl("../../scripts/check-unlock.py")
    return String(u).replace(/^file:\/\//, "")
  }

  readonly property int wallpaperFillMode: {
    switch (Background.lockEffectiveFillMode) {
    case "fit":
      return Image.PreserveAspectFit
    case "stretch":
      return Image.Stretch
    case "center":
      return Image.Pad
    default:
      return Image.PreserveAspectCrop
    }
  }

  LockLayoutZones {
    id: zones
    surfaceWidth: root.width
    surfaceHeight: root.height
    stripWidgets: Widgets.lockStripWidgets
    clockWidget: Widgets.lockClockWidget
    // PIN numpad needs a deep reserve; password field is shorter.
    authReserve: root.pinMode
        ? Math.min(root.height * 0.52, Math.max(420, root.height * 0.48))
        : Math.min(root.height * 0.28, 260)
  }

  function refreshPinStatus() {
    pinStatusProc.running = false
    pinStatusProc.running = true
  }

  function focusAuthInput() {
    if (root.pinMode)
      pinKeySink.forceActiveFocus()
    else
      passwordField.forceActiveFocus()
  }

  function tryUnlock() {
    if (root.customizeMode || root.unlockInProgress || root.cooldownActive)
      return
    if (root.pinMode) {
      if (root.pinDigits.length !== root.pinLength) {
        root.revealAuth = true
        root.focusAuthInput()
        return
      }
      root.showFailure = false
      root.statusText = ""
      root.unlockInProgress = true
      root.authMode = "pin"
      authProc.secret = root.pinDigits
      authProc.running = false
      authProc.running = true
      return
    }
    const pw = passwordField.text
    if (!pw.length) {
      root.revealAuth = true
      root.focusAuthInput()
      return
    }
    root.showFailure = false
    root.statusText = ""
    root.unlockInProgress = true
    root.authMode = "password"
    authProc.secret = pw
    authProc.running = false
    authProc.running = true
  }

  function pinAppend(digit) {
    if (root.customizeMode || root.inputBlocked || !root.pinMode)
      return
    if (!/^[0-9]$/.test(digit))
      return
    if (root.pinDigits.length >= root.pinLength)
      return
    root.showFailure = false
    root.statusText = ""
    root.pinDigits = root.pinDigits + digit
    if (root.pinDigits.length === root.pinLength)
      Qt.callLater(() => root.tryUnlock())
  }

  function pinBackspace() {
    if (root.customizeMode || root.inputBlocked || !root.pinMode)
      return
    root.showFailure = false
    root.statusText = ""
    root.pinDigits = root.pinDigits.slice(0, -1)
  }

  function resetField() {
    passwordField.text = ""
    root.pinDigits = ""
    if (root.revealAuth)
      root.focusAuthInput()
  }

  function failUnlock(msg) {
    root.unlockInProgress = false
    root.showFailure = true
    root.statusText = msg || (root.authMode === "pin" ? "Wrong PIN" : "Wrong password")
    root.failedAttempts = root.failedAttempts + 1
    root.cooldownRemaining = root.cooldownFor(root.failedAttempts)
    root.resetField()
    shakeAnim.start()
  }

  function succeedUnlock() {
    root.unlockInProgress = false
    root.failedAttempts = 0
    root.cooldownRemaining = 0
    root.showFailure = false
    root.statusText = ""
    root.resetField()
    root.unlocked()
  }

  function enterCustomize() {
    root.customizeMode = true
    root.revealAuth = false
    root.selectedWidgetId = Widgets.lockClockWidget ? String(Widgets.lockClockWidget.id) : ""
  }

  function exitCustomize() {
    root.customizeMode = false
    root.selectedWidgetId = ""
    root.showGallery = false
    root.showWallpaperSheet = false
  }

  Timer {
    interval: Math.max(5, Config.lockWallpaperSlideshowSecs || 60) * 1000
    repeat: true
    running: Config.lockBackgroundMode === "image" && Config.lockWallpaperSlideshow && ShellState.sessionLocked
    onTriggered: Config.advanceLockSlideshow()
  }

  // Backdrop
  Rectangle {
    anchors.fill: parent
    color: "#000000"

    Image {
      visible: Background.lockBackdropKind === "image" && Background.lockActiveImagePath.length
      anchors.fill: parent
      source: Background.lockActiveImagePath.length
          ? ("file://" + Background.lockActiveImagePath + "#" + Config.lockWallpaperId + "," + Background.lockSlideshowPath)
          : ""
      fillMode: root.wallpaperFillMode
      asynchronous: true
      cache: false
    }

    Rectangle {
      visible: Background.lockBackdropKind === "color"
      anchors.fill: parent
      color: Background.lockBackdropColor
    }

    Item {
      anchors.fill: parent
      visible: Background.lockBackdropKind === "video"
      Rectangle {
        anchors.fill: parent
        color: "#0a0e14"
      }
      VideoOutput {
        id: videoOut
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectCrop
        visible: Background.lockBackdropVideoPath.length > 0
      }
      MediaPlayer {
        id: lockVideo
        videoOutput: videoOut
        audioOutput: AudioOutput {
          muted: true
        }
        source: (Background.lockBackdropKind === "video" && Background.lockBackdropVideoPath.length)
            ? ("file://" + Background.lockBackdropVideoPath)
            : ""
        loops: MediaPlayer.Infinite
        onSourceChanged: {
          if (Background.lockBackdropKind === "video" && source.toString().length && ShellState.sessionLocked)
            play()
          else
            stop()
        }
      }
      Connections {
        target: ShellState
        function onSessionLockedChanged() {
          if (ShellState.sessionLocked && Background.lockBackdropKind === "video" && lockVideo.source.toString().length)
            lockVideo.play()
          else
            lockVideo.stop()
        }
      }
    }

    Loader {
      id: reactiveLoader
      anchors.fill: parent
      active: Background.lockBackdropKind === "reactive"
      source: Qt.resolvedUrl("../../wallpaper/ReactiveBg.qml")
      onLoaded: {
        if (!item)
          return
        item.effectId = Background.lockBackdropReactiveId
        item.customAccent = true
        item.accentColor = Theme.accent
      }
      // Must be qualified: bare `item` resolves up the scope chain to the
      // enclosing DesktopShell, not this Loader, so the binding silently
      // targeted the wrong object and live effect changes never applied.
      Binding {
        target: reactiveLoader.item
        property: "effectId"
        value: Background.lockBackdropReactiveId
        when: !!reactiveLoader.item
      }
    }

    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, root.customizeMode ? Math.min(0.72, Background.lockDimClamped + 0.25) : Background.lockDimClamped * 0.55)
    }
  }

  MouseArea {
    anchors.fill: parent
    z: 0
    onPressAndHold: root.enterCustomize()
    onClicked: {
      if (root.customizeMode)
        return
      root.revealAuth = true
      root.focusAuthInput()
    }
  }

  // Applets — under auth UI. Idle lock shows the stack; PIN unlock hides it
  // so the pad owns the center; password mode only dims.
  Item {
    id: appletLayer
    anchors.fill: parent
    z: 3
    visible: root.customizeMode || !(root.revealAuth && root.pinMode)
    opacity: root.customizeMode ? 1 : (root.revealAuth ? 0.4 : 1)
    Behavior on opacity {
      NumberAnimation {
        duration: 180
        easing.type: Easing.OutCubic
      }
    }

    LockAppletHost {
      visible: !!zones.clockFrame
      frame: zones.clockFrame
      customizeMode: root.customizeMode
      selected: root.selectedWidgetId === (zones.clockFrame ? zones.clockFrame.id : "")
      surfaceWidth: root.width
      surfaceHeight: root.height
      onRequestCustomize: root.enterCustomize()
      onSelectApplet: root.selectedWidgetId = zones.clockFrame ? zones.clockFrame.id : ""
    }

    Repeater {
      model: zones.stripFrames
      LockAppletHost {
        required property var modelData
        frame: modelData
        customizeMode: root.customizeMode
        selected: root.selectedWidgetId === modelData.id
        surfaceWidth: root.width
        surfaceHeight: root.height
        onRequestCustomize: root.enterCustomize()
        onSelectApplet: root.selectedWidgetId = modelData.id
        onDragReorder: normY => {
          const n = Widgets.lockStripWidgets.length
          const slot = Math.max(0, Math.min(n, Math.round(normY * Math.max(1, n))))
          Widgets.moveLockWidgetToSlot(modelData.id, slot)
        }
      }
    }
  }

  Text {
    z: 5
    visible: root.customizeMode && Widgets.lockStripWidgets.length === 0
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: parent.top
    anchors.topMargin: zones.stripTop + 8
    text: "Tap Add Widget to place applets here"
    color: Qt.rgba(1, 1, 1, 0.55)
    font.family: Theme.fontFamily
    font.pixelSize: 13
  }

  LockCustomizeBar {
    z: 20
    visible: root.customizeMode
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: parent.top
    anchors.topMargin: 18
    width: Math.min(420, parent.width - 32)
    onChangeWallpaper: root.showWallpaperSheet = true
    onAddWidget: root.showGallery = true
    onDone: root.exitCustomize()
  }

  LockClockStyleHud {
    z: 21
    visible: root.customizeMode && Widgets.lockClockWidget && root.selectedWidgetId === String(Widgets.lockClockWidget.id)
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: 28
    width: Math.min(340, parent.width - 40)
    clockWidget: Widgets.lockClockWidget
  }

  Loader {
    anchors.fill: parent
    z: 40
    active: root.showGallery
    source: Qt.resolvedUrl("WidgetGallery.qml")
    onLoaded: {
      if (item) {
        item.scope = "lock"
        item.open()
        item.closed.connect(() => {
          root.showGallery = false
        })
      }
    }
  }

  Loader {
    anchors.fill: parent
    z: 40
    active: root.showWallpaperSheet
    source: Qt.resolvedUrl("LockWallpaperSheet.qml")
    onLoaded: {
      if (item) {
        item.open()
        item.closed.connect(() => {
          root.showWallpaperSheet = false
        })
      }
    }
  }

  // Auth — Column (not ColumnLayout/GridLayout) so avatar, dots, and pad share
  // one horizontal center. Seat is anchored to the screen center for PIN.
  Item {
    id: authHost
    anchors.fill: parent
    z: 12
    visible: root.revealAuth && !root.customizeMode

    Column {
      id: authColumn
      spacing: 14
      // Match pad geometry (3×60 keys + 2×10 gaps) so avatar/dots/pad share one axis.
      readonly property int pinColW: 60 * 3 + 10 * 2
      width: root.pinMode ? pinColW : Math.min(340, authHost.width - 56)
      anchors.horizontalCenter: parent.horizontalCenter
      // y (not AnchorChanges) — PIN dead-center; password docked low.
      y: root.pinMode
          ? Math.round((authHost.height - height) / 2)
          : Math.max(24, authHost.height - height - Math.max(40, authHost.height * 0.06))

      transform: Translate {
        id: shakeX
        x: 0
      }

      SequentialAnimation {
        id: shakeAnim
        NumberAnimation {
          target: shakeX
          property: "x"
          to: -12
          duration: 40
        }
        NumberAnimation {
          target: shakeX
          property: "x"
          to: 12
          duration: 50
        }
        NumberAnimation {
          target: shakeX
          property: "x"
          to: -8
          duration: 40
        }
        NumberAnimation {
          target: shakeX
          property: "x"
          to: 0
          duration: 40
        }
      }

      Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        width: 64
        height: 64
        radius: 32
        color: Qt.rgba(1, 1, 1, 0.14)
        Text {
          anchors.centerIn: parent
          text: root.userName.charAt(0).toUpperCase()
          color: "#f5f5f7"
          font.family: Theme.fontFamily
          font.pixelSize: 26
          font.weight: Font.Medium
        }
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.userName
        color: Qt.rgba(1, 1, 1, 0.92)
        font.family: Theme.fontFamily
        font.pixelSize: 16
        font.weight: Font.Medium
      }

      // —— PIN ——
      Text {
        visible: root.pinMode
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.cooldownActive
            ? ("Locked out — " + root.cooldownRemaining + "s")
            : (root.unlockInProgress ? "Unlocking…" : "Enter PIN")
        color: Qt.rgba(1, 1, 1, 0.72)
        font.family: Theme.fontFamily
        font.pixelSize: 14
      }

      Row {
        visible: root.pinMode
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 12
        Repeater {
          model: Math.max(0, root.pinLength)
          Rectangle {
            required property int index
            width: 12
            height: 12
            radius: 6
            color: index < root.pinDigits.length
                ? "#f5f5f7"
                : Qt.rgba(1, 1, 1, 0.22)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.28)
          }
        }
      }

      Item {
        id: pinKeySink
        visible: root.pinMode
        width: 1
        height: 1
        anchors.horizontalCenter: parent.horizontalCenter
        focus: root.pinMode && root.revealAuth
        Keys.onPressed: event => {
          if (!root.pinMode || root.inputBlocked) {
            event.accepted = false
            return
          }
          if (event.key === Qt.Key_Backspace) {
            root.pinBackspace()
            event.accepted = true
            return
          }
          if (event.key === Qt.Key_Escape && root.pinConfigured) {
            event.accepted = true
            return
          }
          const t = event.text || ""
          if (t.length === 1 && t >= "0" && t <= "9") {
            root.pinAppend(t)
            event.accepted = true
          }
        }
      }

      Grid {
        id: pinPad
        visible: root.pinMode
        anchors.horizontalCenter: parent.horizontalCenter
        columns: 3
        readonly property int keySize: 60
        readonly property int gap: 10
        spacing: gap
        // Empty cell keeps 0 centered under 8.
        Repeater {
          model: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", "⌫"]
          Rectangle {
            required property string modelData
            width: pinPad.keySize
            height: pinPad.keySize
            radius: pinPad.keySize / 2
            color: modelData.length ? Qt.rgba(1, 1, 1, modelData === "⌫" ? 0.10 : 0.16) : "transparent"
            border.width: modelData.length ? 1 : 0
            border.color: Qt.rgba(1, 1, 1, 0.12)
            opacity: (!modelData.length) ? 0 : (root.inputBlocked ? 0.45 : 1)
            Text {
              anchors.centerIn: parent
              visible: modelData.length > 0
              text: modelData
              color: "#f5f5f7"
              font.family: Theme.fontFamily
              font.pixelSize: modelData === "⌫" ? 18 : 20
              font.weight: Font.Medium
            }
            MouseArea {
              anchors.fill: parent
              enabled: !root.inputBlocked && modelData.length > 0
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (modelData === "⌫")
                  root.pinBackspace()
                else
                  root.pinAppend(modelData)
              }
            }
          }
        }
      }

      Text {
        visible: root.pinMode
        anchors.horizontalCenter: parent.horizontalCenter
        topPadding: 4
        text: "Use password"
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: 13
        font.weight: Font.Medium
        opacity: root.inputBlocked ? 0.45 : 1
        MouseArea {
          anchors.fill: parent
          anchors.margins: -8
          enabled: !root.inputBlocked
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            root.usePassword = true
            root.pinDigits = ""
            root.showFailure = false
            root.statusText = ""
            Qt.callLater(() => passwordField.forceActiveFocus())
          }
        }
      }

      // —— Password ——
      Rectangle {
        id: passCard
        visible: !root.pinMode
        width: parent.width
        height: 46
        radius: Theme.radiusPill
        color: Qt.rgba(28 / 255, 28 / 255, 30 / 255, 0.88)
        border.width: passwordField.activeFocus ? 2 : 1
        border.color: passwordField.activeFocus ? Theme.accent : Qt.rgba(1, 1, 1, 0.12)

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: 16
          anchors.rightMargin: 8
          spacing: 8

          TextField {
            id: passwordField
            Layout.fillWidth: true
            Layout.fillHeight: true
            echoMode: TextInput.Password
            passwordCharacter: "•"
            placeholderText: {
              if (root.cooldownActive)
                return "Locked out — " + root.cooldownRemaining + "s"
              return root.unlockInProgress ? "Unlocking…" : "Enter Password"
            }
            placeholderTextColor: Theme.textMute
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 15
            enabled: !root.inputBlocked
            background: Item {}
            onTextChanged: {
              root.showFailure = false
              root.statusText = ""
            }
            Keys.onReturnPressed: root.tryUnlock()
            Keys.onEnterPressed: root.tryUnlock()
          }

          Rectangle {
            Layout.preferredWidth: 32
            Layout.preferredHeight: 32
            radius: 16
            color: Theme.accent
            opacity: (!root.inputBlocked && passwordField.text.length) ? 1 : 0.35
            Text {
              anchors.centerIn: parent
              text: root.unlockInProgress ? "…" : "→"
              color: "#fff"
              font.pixelSize: 15
              font.bold: true
            }
            MouseArea {
              anchors.fill: parent
              enabled: !root.inputBlocked && passwordField.text.length > 0
              cursorShape: Qt.PointingHandCursor
              onClicked: root.tryUnlock()
            }
          }
        }
      }

      Text {
        visible: !root.pinMode && root.pinConfigured
        anchors.horizontalCenter: parent.horizontalCenter
        text: "Use PIN"
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: 13
        font.weight: Font.Medium
        opacity: root.inputBlocked ? 0.45 : 1
        MouseArea {
          anchors.fill: parent
          anchors.margins: -8
          enabled: !root.inputBlocked
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            root.usePassword = false
            passwordField.text = ""
            root.showFailure = false
            root.statusText = ""
            Qt.callLater(() => pinKeySink.forceActiveFocus())
          }
        }
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: root.cooldownActive || root.showFailure || root.statusText.length > 0
        text: {
          if (root.cooldownActive)
            return "Too many attempts — try again in " + root.cooldownRemaining + "s"
          if (root.statusText.length)
            return root.statusText
          return root.authMode === "pin" ? "Wrong PIN" : "Wrong password"
        }
        color: "#ff453a"
        font.family: Theme.fontFamily
        font.pixelSize: 13
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        topPadding: 8
        text: "Proteus"
        color: Qt.rgba(1, 1, 1, 0.32)
        font.family: Theme.fontFamily
        font.pixelSize: 12
        font.weight: Font.Medium
      }
    } // authColumn
  } // authHost

  Process {
    id: pinStatusProc
    command: ["python3", root.helperPath, "--status"]
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const o = JSON.parse(String(this.text || "").trim() || "{}")
          root.pinConfigured = !!o.configured
          root.pinLength = o.configured ? (parseInt(o.length, 10) || 0) : 0
          if (!root.pinConfigured)
            root.usePassword = false
        } catch (e) {
          root.pinConfigured = false
          root.pinLength = 0
        }
      }
    }
  }

  Process {
    id: authProc
    property string secret: ""
    // Password path uses PAM (falls back to login if proteus-lock missing).
    // PIN path verifies the hashed unlock PIN under ~/.local/share/proteus/auth/.
    command: ["python3", root.helperPath, root.userName, root.authMode]
    stdinEnabled: true
    stderr: StdioCollector {
      onStreamFinished: {
        const t = text.trim()
        if (t.length)
          console.warn("lock auth:", t)
      }
    }
    onStarted: {
      write(secret + "\n")
      secret = ""
      stdinEnabled = false
    }
    onExited: (exitCode, exitStatus) => {
      stdinEnabled = true
      secret = ""
      if (exitCode === 0) {
        root.succeedUnlock()
      } else if (exitCode === 2) {
        root.failUnlock("Authentication helper failed")
      } else {
        root.failUnlock(root.authMode === "pin" ? "Wrong PIN" : "Wrong password")
      }
    }
  }

  Connections {
    target: ShellState
    function onSessionLockedChanged() {
      if (ShellState.sessionLocked) {
        root.showFailure = false
        root.statusText = ""
        root.revealAuth = false
        root.unlockInProgress = false
        root.usePassword = false
        root.pinDigits = ""
        root.exitCustomize()
        passwordField.text = ""
        root.refreshPinStatus()
        Widgets.ensureLockClockWidget()
        if (Config.lockBackgroundMode === "image" && Config.lockWallpaperSlideshow)
          Config.advanceLockSlideshow()
      } else {
        root.exitCustomize()
      }
    }
  }

  Keys.onPressed: event => {
    if (root.customizeMode) {
      if (event.key === Qt.Key_Escape) {
        root.exitCustomize()
        event.accepted = true
      }
      return
    }
    if (!root.revealAuth) {
      root.revealAuth = true
      root.focusAuthInput()
      const t = event.text || ""
      // If PIN mode and this key is a digit, consume it into the PIN.
      if (root.pinMode && !root.inputBlocked) {
        if (t.length === 1 && t >= "0" && t <= "9") {
          root.pinAppend(t)
          event.accepted = true
          return
        }
      } else if (!root.pinMode && !root.inputBlocked && t.length) {
        // Password mode: don't swallow the wake-up keystroke.
        passwordField.text += t
        event.accepted = true
        return
      }
      event.accepted = true
    }
  }

  focus: true
  Component.onCompleted: {
    Widgets.ensureLockClockWidget()
    root.refreshPinStatus()
    forceActiveFocus()
  }
}
