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
        passwordField.forceActiveFocus()
    }
  }
  property bool revealAuth: false
  property bool customizeMode: false
  property string selectedWidgetId: ""
  property bool showGallery: false
  property bool showWallpaperSheet: false

  readonly property string userName: {
    const u = Quickshell.env("USER")
    return (u && u.length) ? u : "user"
  }

  readonly property string helperPath: {
    const u = Qt.resolvedUrl("../../scripts/check-password.py")
    return String(u).replace(/^file:\/\//, "")
  }

  readonly property int wallpaperFillMode: {
    switch (Config.lockEffectiveFillMode) {
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
    stripWidgets: Config.lockStripWidgets
    clockWidget: Config.lockClockWidget
  }

  function tryUnlock() {
    if (root.customizeMode || root.unlockInProgress || root.cooldownActive)
      return
    const pw = passwordField.text
    if (!pw.length) {
      root.revealAuth = true
      passwordField.forceActiveFocus()
      return
    }
    root.showFailure = false
    root.statusText = ""
    root.unlockInProgress = true
    authProc.password = pw
    authProc.running = false
    authProc.running = true
  }

  function resetField() {
    passwordField.text = ""
    if (root.revealAuth)
      passwordField.forceActiveFocus()
  }

  function failUnlock(msg) {
    root.unlockInProgress = false
    root.showFailure = true
    root.statusText = msg || "Wrong password"
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
    root.selectedWidgetId = Config.lockClockWidget ? String(Config.lockClockWidget.id) : ""
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
      visible: Config.lockBackdropKind === "image" && Config.lockActiveImagePath.length
      anchors.fill: parent
      source: Config.lockActiveImagePath.length
          ? ("file://" + Config.lockActiveImagePath + "#" + Config.lockWallpaperId + "," + Config.lockSlideshowPath)
          : ""
      fillMode: root.wallpaperFillMode
      asynchronous: true
      cache: false
    }

    Rectangle {
      visible: Config.lockBackdropKind === "color"
      anchors.fill: parent
      color: Config.lockBackdropColor
    }

    Item {
      anchors.fill: parent
      visible: Config.lockBackdropKind === "video"
      Rectangle {
        anchors.fill: parent
        color: "#0a0e14"
      }
      VideoOutput {
        id: videoOut
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectCrop
        visible: Config.lockBackdropVideoPath.length > 0
      }
      MediaPlayer {
        id: lockVideo
        videoOutput: videoOut
        audioOutput: AudioOutput {
          muted: true
        }
        source: (Config.lockBackdropKind === "video" && Config.lockBackdropVideoPath.length)
            ? ("file://" + Config.lockBackdropVideoPath)
            : ""
        loops: MediaPlayer.Infinite
        onSourceChanged: {
          if (Config.lockBackdropKind === "video" && source.toString().length && ShellState.sessionLocked)
            play()
          else
            stop()
        }
      }
      Connections {
        target: ShellState
        function onSessionLockedChanged() {
          if (ShellState.sessionLocked && Config.lockBackdropKind === "video" && lockVideo.source.toString().length)
            lockVideo.play()
          else
            lockVideo.stop()
        }
      }
    }

    Loader {
      anchors.fill: parent
      active: Config.lockBackdropKind === "reactive"
      source: Qt.resolvedUrl("../../wallpaper/ReactiveBg.qml")
      onLoaded: {
        if (!item)
          return
        item.effectId = Config.lockBackdropReactiveId
        item.customAccent = true
        item.accentColor = Theme.accent
      }
      Binding {
        target: item
        property: "effectId"
        value: Config.lockBackdropReactiveId
        when: !!item
      }
    }

    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, root.customizeMode ? Math.min(0.72, Config.lockDimClamped + 0.25) : Config.lockDimClamped * 0.55)
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
      passwordField.forceActiveFocus()
    }
  }

  // Applets
  Item {
    id: appletLayer
    anchors.fill: parent
    z: 3

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
          const n = Config.lockStripWidgets.length
          const slot = Math.max(0, Math.min(n, Math.round(normY * Math.max(1, n))))
          Config.moveLockWidgetToSlot(modelData.id, slot)
        }
      }
    }
  }

  Text {
    z: 5
    visible: root.customizeMode && Config.lockStripWidgets.length === 0
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
    visible: root.customizeMode && Config.lockClockWidget && root.selectedWidgetId === String(Config.lockClockWidget.id)
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: 28
    width: Math.min(340, parent.width - 40)
    clockWidget: Config.lockClockWidget
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

  // Auth
  ColumnLayout {
    z: 2
    visible: root.revealAuth && !root.customizeMode
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Math.max(56, parent.height * 0.11)
    spacing: Theme.spaceMd
    width: Math.min(340, parent.width - 56)

    Rectangle {
      Layout.alignment: Qt.AlignHCenter
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
      Layout.alignment: Qt.AlignHCenter
      text: root.userName
      color: Qt.rgba(1, 1, 1, 0.92)
      font.family: Theme.fontFamily
      font.pixelSize: 16
      font.weight: Font.Medium
    }

    Rectangle {
      id: passCard
      Layout.fillWidth: true
      Layout.preferredHeight: 46
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
    }

    Text {
      Layout.alignment: Qt.AlignHCenter
      visible: root.cooldownActive || root.showFailure || root.statusText.length > 0
      text: {
        if (root.cooldownActive)
          return "Too many attempts — try again in " + root.cooldownRemaining + "s"
        return root.statusText.length ? root.statusText : "Wrong password"
      }
      color: "#ff453a"
      font.family: Theme.fontFamily
      font.pixelSize: 13
    }

    Text {
      Layout.alignment: Qt.AlignHCenter
      text: "Proteus"
      color: Qt.rgba(1, 1, 1, 0.32)
      font.family: Theme.fontFamily
      font.pixelSize: 12
      font.weight: Font.Medium
    }
  }

  Process {
    id: authProc
    property string password: ""
    // The helper falls back to the "login" stack when /etc/pam.d/proteus-lock
    // is not installed, so this is safe on a host that predates the PAM file.
    command: ["python3", root.helperPath, root.userName, "proteus-lock"]
    stdinEnabled: true
    stderr: StdioCollector {
      onStreamFinished: {
        const t = text.trim()
        if (t.length)
          console.warn("lock auth:", t)
      }
    }
    onStarted: {
      write(password + "\n")
      // Don't keep the plaintext alive in the QML heap past the handoff.
      password = ""
      stdinEnabled = false
    }
    onExited: (exitCode, exitStatus) => {
      stdinEnabled = true
      password = ""
      if (exitCode === 0) {
        root.succeedUnlock()
      } else if (exitCode === 2) {
        root.failUnlock("Authentication helper failed")
      } else {
        root.failUnlock("Wrong password")
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
        root.exitCustomize()
        passwordField.text = ""
        Config.ensureLockClockWidget()
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
      passwordField.forceActiveFocus()
      event.accepted = true
    }
  }

  focus: true
  Component.onCompleted: {
    Config.ensureLockClockWidget()
    forceActiveFocus()
  }
}
