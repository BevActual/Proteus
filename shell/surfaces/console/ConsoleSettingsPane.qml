import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../shared"

// Console-native Settings detail — pad-first; hub actions + Wi‑Fi / sink drills.
Item {
  id: root

  property var item: null
  property bool detailFocused: false
  property int actionIndex: 0
  // hub | wifi | sinks | wifiPassword
  property string mode: "hub"
  property string passwordSsid: ""
  property string passwordDraft: ""
  property var sinks: []
  property string defaultSinkName: ""

  signal fullSettingsRequested(string page)
  signal postureDesktopRequested()
  signal actionHint(string text)

  property var librarySession: null

  ConsoleSettingsNet { id: net }

  readonly property string pageId: {
    if (!item)
      return ""
    return String(item.settingsPage || item.paneId || "").trim()
  }
  readonly property string hubId: {
    const p = root.pageId
    if (!p.length)
      return ""
    try {
      const h = EnvGate.paneHubFor(p)
      return h && h.length ? h : p
    } catch (e) {
      return p
    }
  }
  readonly property string title: {
    if (mode === "wifi")
      return "Wi‑Fi networks"
    if (mode === "wifiPassword")
      return "Wi‑Fi password"
    if (mode === "sinks")
      return "Sound output"
    return item ? (item.title || root.pageId) : ""
  }
  readonly property string meta: {
    if (mode === "wifi")
      return net.busy ? "Scanning…" : (net.networks.length + " networks")
    if (mode === "wifiPassword")
      return passwordSsid
    if (mode === "sinks")
      return sinks.length ? (sinks.length + " outputs") : "Loading…"
    if (!item)
      return ""
    const bits = ["Console Settings"]
    if (root.hubId.length && root.hubId !== root.pageId)
      bits.push(root.hubId)
    return bits.join(" · ")
  }

  readonly property string statusStrip: {
    void SystemServices.volume
    void SystemServices.muted
    void SystemServices.wifiEnabled
    void SystemServices.netSummary
    void SystemServices.connected
    void Config.chromeMode
    void Config.notificationsDnd
    void KeepAwake.label
    void KeepAwake.active
    void Brightness.lastPercent
    void root.defaultSinkName
    void root.mode

    if (mode !== "hub")
      return ""
    const hub = root.hubId
    if (hub === "sound" || pageId.indexOf("sound") === 0) {
      const vol = SystemServices.volume
      const muted = SystemServices.muted
      const sink = defaultSinkName.length
          ? Audio.formatAudioDeviceName(defaultSinkName)
          : "Output"
      return (muted ? "Muted" : (vol + "%")) + " · " + sink
    }
    if (hub === "network" || pageId.indexOf("network") === 0) {
      if (!SystemServices.wifiSupported)
        return SystemServices.netSummary || "No Wi‑Fi radio"
      if (!SystemServices.wifiEnabled)
        return "Wi‑Fi off"
      return SystemServices.netSummary || (SystemServices.connected ? "Connected" : "Not connected")
    }
    if (hub === "style" || pageId.indexOf("style") === 0)
      return Config.chromeMode === "light" ? "Light chrome" : "Dark chrome"
    if (hub === "notifications")
      return Config.notificationsDnd ? "Do Not Disturb on" : "Notifications on"
    if (hub === "power")
      return KeepAwake.active ? ("Keep Awake · " + KeepAwake.label) : "Keep Awake off"
    if (hub === "displays") {
      if (Brightness.available && Brightness.lastPercent >= 0)
        return "Brightness " + Brightness.lastPercent + "%"
      return Brightness.available ? "Brightness" : "No backlight on this kit"
    }
    if (hub === "system") {
      try {
        if (SystemInfo && SystemInfo.hostname)
          return String(SystemInfo.hostname)
      } catch (e) {
      }
      return "Proteus Console"
    }
    return ""
  }

  readonly property bool inDrill: mode === "wifi" || mode === "sinks" || mode === "wifiPassword"

  readonly property var actions: {
    void SystemServices.volume
    void SystemServices.muted
    void SystemServices.wifiEnabled
    void SystemServices.wifiSupported
    void SystemServices.connected
    void SystemServices.netSummary
    void Config.chromeMode
    void Config.notificationsDnd
    void KeepAwake.mode
    void KeepAwake.active
    void KeepAwake.label
    void net.networks
    void net.busy
    void root.sinks
    void root.mode
    void root.passwordSsid

    const page = root.pageId
    const hub = root.hubId
    const out = []

    function add(id, label, hint, enabled) {
      out.push({
        id: id,
        label: label,
        hint: hint || "",
        enabled: enabled !== false
      })
    }

    if (mode === "wifi") {
      add("wifi-back", "← Back", "")
      if (SystemServices.wifiSupported) {
        add("wifi-toggle", SystemServices.wifiEnabled ? "Turn Wi‑Fi off" : "Turn Wi‑Fi on",
            SystemServices.netSummary || "")
        add("wifi-rescan", net.busy ? "Scanning…" : "Rescan", "", !net.busy)
        if (SystemServices.connected && SystemServices.netKind === "wifi")
          add("wifi-disconnect", "Disconnect", SystemServices.netSummary)
        for (let i = 0; i < net.networks.length; i++) {
          const n = net.networks[i]
          const hint = (n.active ? "Connected · " : "")
              + (n.signal ? (n.signal + "%") : "")
              + (n.open ? " · Open" : (n.security ? (" · " + n.security) : ""))
          add("wifi-ssid:" + n.ssid, n.ssid, hint.trim())
        }
      } else {
        add("wifi-na", "Wi‑Fi not available", "No radio", false)
      }
      return out
    }

    if (mode === "wifiPassword") {
      add("wifi-pass-connect", "Connect", passwordSsid)
      add("wifi-pass-cancel", "Cancel", "")
      return out
    }

    if (mode === "sinks") {
      add("sinks-back", "← Back", "")
      if (!sinks.length)
        add("sinks-empty", "No outputs found", "", false)
      for (let s = 0; s < sinks.length; s++) {
        const sk = sinks[s]
        add("sink:" + sk.name, sk.label || sk.name, sk.isDefault ? "Current" : (sk.state || ""))
      }
      return out
    }

    // hub mode
    if (!page.length)
      return out

    if (hub === "style" || page.indexOf("style") === 0) {
      const light = Config.chromeMode === "light"
      add("chrome-toggle", light ? "Use Dark chrome" : "Use Light chrome",
          light ? "Light" : "Dark")
      add("chrome-dark", "Dark", light ? "" : "Current")
      add("chrome-light", "Light", light ? "Current" : "")
    } else if (hub === "sound" || page.indexOf("sound") === 0) {
      const vol = SystemServices.volume
      const muted = SystemServices.muted
      add("vol-up", "Volume up", muted ? "Muted" : (vol + "%"))
      add("vol-down", "Volume down", muted ? "Muted" : (vol + "%"))
      add("vol-mute", muted ? "Unmute" : "Mute", muted ? "Muted" : (vol + "%"))
      add("sinks-open", "Choose output…", defaultSinkName
          ? Audio.formatAudioDeviceName(defaultSinkName) : "")
    } else if (hub === "network" || page.indexOf("network") === 0) {
      if (SystemServices.wifiSupported) {
        add("wifi-toggle", SystemServices.wifiEnabled ? "Turn Wi‑Fi off" : "Turn Wi‑Fi on",
            SystemServices.netSummary || (SystemServices.wifiEnabled ? "On" : "Off"))
        add("wifi-open", "Wi‑Fi networks…", "Scan · connect")
      } else {
        add("wifi-na", "Wi‑Fi not available", "No radio", false)
      }
      add("net-status", "Status", SystemServices.netSummary
          || (SystemServices.connected ? "Connected" : "Not connected"), false)
    } else if (hub === "notifications") {
      add("dnd-toggle", Config.notificationsDnd ? "Turn Do Not Disturb off" : "Turn Do Not Disturb on",
          Config.notificationsDnd ? "DND on" : "DND off")
    } else if (hub === "power") {
      add("awake-off", "Keep Awake off", KeepAwake.active ? KeepAwake.label : "Off")
      add("awake-30", "Keep Awake 30 minutes", KeepAwake.mode === "30m" ? "Current" : "")
      add("awake-indef", "Keep Awake until off", KeepAwake.mode === "indefinite" ? "Current" : "")
    } else if (hub === "displays") {
      add("bright-up", "Brighter", Brightness.lastPercent >= 0 ? (Brightness.lastPercent + "%") : "")
      add("bright-down", "Dimmer", Brightness.available ? "" : "Unavailable", Brightness.available)
    } else if (hub === "system") {
      let about = "Proteus Console"
      try {
        if (SystemInfo && SystemInfo.hostname)
          about = String(SystemInfo.hostname)
      } catch (e) {
      }
      add("about", "About", about, false)
      add("posture-desktop", "Return to Desktop", "Hard posture flip")
      add("session-toggle", "Toggle seat / Gamescope", "Console session preference")
    } else if (hub === "packages") {
      add("pkg-hint", "Software on Console",
          "Install streaming apps and web apps from here when possible.", false)
      if (page === "packages-webapps" || page.indexOf("webapp") >= 0)
        add("webapps-hint", "Web apps",
            "Deep editor opens Full Settings.", false)
      add("pkg-escape", "Open Software in Full Settings…", "Desktop Settings UI")
    } else if (hub === "users") {
      add("lock", "Lock screen", "")
      add("posture-desktop", "Return to Desktop", "Hard posture flip")
    } else if (hub === "peripherals") {
      add("pad-hint", "Gamepads",
          "Guide · D-pad · LB/RB tabs. Deep map in Full Settings.", false)
      add("pad-escape", "Open Gamepads in Full Settings…", "Desktop Settings UI")
    } else if (hub === "privacy") {
      add("privacy-hint", "Privacy", "Deep panes in Full Settings.", false)
      add("privacy-escape", "Open Privacy in Full Settings…", "Desktop Settings UI")
    } else if (hub === "datetime") {
      add("dt-hint", "Date & time", "Deep TZ/NTP in Full Settings.", false)
      add("dt-escape", "Open Date & time in Full Settings…", "Desktop Settings UI")
    } else if (hub === "accounts") {
      add("acct-hint", "Accounts", "Needs the full Settings UI.", false)
      add("acct-escape", "Open Accounts in Full Settings…", "Desktop Settings UI")
    } else {
      add("generic-hint", "Console Settings",
          "Lean controls for this page are not wired yet.", false)
    }

    const hasEscape = out.some(function (a) {
      return String(a.id).indexOf("escape") >= 0 || a.id === "pkg-escape"
    })
    if (!hasEscape)
      add("full-escape", "Open in Full Settings…", "Desktop Settings UI · pointer")

    return out
  }

  onItemChanged: {
    mode = "hub"
    actionIndex = 0
    passwordSsid = ""
    passwordDraft = ""
    refreshSinksQuiet()
  }
  onModeChanged: actionIndex = 0
  onActionsChanged: {
    if (!actions.length)
      actionIndex = 0
    else
      actionIndex = Math.max(0, Math.min(actionIndex, actions.length - 1))
  }

  function refreshSinksQuiet() {
    Audio.listSinks(function (list) {
      root.sinks = list || []
      let def = ""
      for (let i = 0; i < root.sinks.length; i++) {
        if (root.sinks[i].isDefault) {
          def = root.sinks[i].name
          break
        }
      }
      root.defaultSinkName = def
    })
  }

  function openWifiDrill() {
    mode = "wifi"
    actionIndex = 0
    net.rescan()
  }

  function openSinksDrill() {
    mode = "sinks"
    actionIndex = 0
    Audio.listSinks(function (list) {
      root.sinks = list || []
      let def = ""
      for (let i = 0; i < root.sinks.length; i++) {
        if (root.sinks[i].isDefault)
          def = root.sinks[i].name
      }
      root.defaultSinkName = def
    })
  }

  function exitDrill() {
    if (mode === "wifiPassword") {
      mode = "wifi"
      passwordSsid = ""
      passwordDraft = ""
      actionIndex = 0
      return true
    }
    if (mode === "wifi" || mode === "sinks") {
      mode = "hub"
      actionIndex = 0
      SystemServices.refresh()
      refreshSinksQuiet()
      return true
    }
    return false
  }

  function moveAction(delta) {
    if (!actions.length)
      return
    let i = actionIndex + delta
    const n = actions.length
    for (let step = 0; step < n; step++) {
      if (i < 0)
        i = n - 1
      if (i >= n)
        i = 0
      if (actions[i].enabled !== false) {
        actionIndex = i
        return
      }
      i += delta > 0 ? 1 : -1
    }
  }

  function activateFocused() {
    if (mode === "wifiPassword" && passField.visible) {
      // Prefer connect when activating from pad on password screen
      if (actionIndex === 0)
        runAction("wifi-pass-connect")
      else
        runAction("wifi-pass-cancel")
      return
    }
    if (!actions.length)
      return
    const a = actions[Math.max(0, Math.min(actionIndex, actions.length - 1))]
    if (!a || a.enabled === false)
      return
    runAction(a.id)
  }

  function runAction(id) {
    const aid = String(id || "")
    if (aid === "wifi-back" || aid === "sinks-back") {
      exitDrill()
      return
    }
    if (aid === "wifi-open") {
      openWifiDrill()
      return
    }
    if (aid === "wifi-rescan") {
      net.rescan()
      root.actionHint("Scanning Wi‑Fi…")
      return
    }
    if (aid === "wifi-disconnect") {
      net.disconnectWifi()
      root.actionHint("Disconnecting…")
      return
    }
    if (aid.indexOf("wifi-ssid:") === 0) {
      const ssid = aid.slice("wifi-ssid:".length)
      let open = true
      for (let i = 0; i < net.networks.length; i++) {
        if (net.networks[i].ssid === ssid) {
          open = !!net.networks[i].open
          break
        }
      }
      if (open) {
        net.connectOpen(ssid)
        root.actionHint("Connecting to " + ssid)
        SystemServices.refresh()
      } else {
        passwordSsid = ssid
        passwordDraft = ""
        mode = "wifiPassword"
        actionIndex = 0
        Qt.callLater(function () {
          passField.forceActiveFocus()
        })
      }
      return
    }
    if (aid === "wifi-pass-connect") {
      net.connectPassword(passwordSsid, passwordDraft)
      root.actionHint("Connecting to " + passwordSsid)
      mode = "wifi"
      passwordSsid = ""
      passwordDraft = ""
      Qt.callLater(function () {
        SystemServices.refresh()
        net.rescan()
      })
      return
    }
    if (aid === "wifi-pass-cancel") {
      exitDrill()
      return
    }
    if (aid === "sinks-open") {
      openSinksDrill()
      return
    }
    if (aid.indexOf("sink:") === 0) {
      const name = aid.slice("sink:".length)
      Audio.setDefaultSink(name)
      root.defaultSinkName = name
      root.actionHint("Output · " + Audio.formatAudioDeviceName(name))
      Qt.callLater(function () {
        SystemServices.refresh()
        refreshSinksQuiet()
      })
      return
    }
    if (aid === "chrome-toggle") {
      Config.setChromeMode(Config.chromeMode === "light" ? "dark" : "light")
      root.actionHint("Chrome · " + Config.chromeMode)
      return
    }
    if (aid === "chrome-dark") {
      Config.setChromeMode("dark")
      root.actionHint("Chrome · dark")
      return
    }
    if (aid === "chrome-light") {
      Config.setChromeMode("light")
      root.actionHint("Chrome · light")
      return
    }
    if (aid === "vol-up") {
      Audio.stepVolume(5)
      SystemServices.refresh()
      root.actionHint("Volume up")
      return
    }
    if (aid === "vol-down") {
      Audio.stepVolume(-5)
      SystemServices.refresh()
      root.actionHint("Volume down")
      return
    }
    if (aid === "vol-mute") {
      Audio.setMute(!SystemServices.muted)
      SystemServices.refresh()
      root.actionHint(SystemServices.muted ? "Muted" : "Unmuted")
      return
    }
    if (aid === "wifi-toggle") {
      const next = SystemServices.wifiEnabled ? "off" : "on"
      Quickshell.execDetached({
        command: ["nmcli", "radio", "wifi", next]
      })
      Qt.callLater(function () {
        SystemServices.refresh()
        if (mode === "wifi")
          net.rescan()
      })
      root.actionHint("Wi‑Fi " + next)
      return
    }
    if (aid === "dnd-toggle") {
      Notifications.setDnd(!Config.notificationsDnd)
      root.actionHint(Config.notificationsDnd ? "DND on" : "DND off")
      return
    }
    if (aid === "awake-off") {
      KeepAwake.select("off")
      root.actionHint("Keep Awake off")
      return
    }
    if (aid === "awake-30") {
      KeepAwake.select("30m")
      root.actionHint("Keep Awake 30m")
      return
    }
    if (aid === "awake-indef") {
      KeepAwake.select("indefinite")
      root.actionHint("Keep Awake on")
      return
    }
    if (aid === "bright-up") {
      Brightness.stepBrightness(5)
      root.actionHint("Brighter")
      return
    }
    if (aid === "bright-down") {
      Brightness.stepBrightness(-5)
      root.actionHint("Dimmer")
      return
    }
    if (aid === "lock") {
      UniversalSearch.runAction("lock")
      return
    }
    if (aid === "posture-desktop") {
      root.postureDesktopRequested()
      return
    }
    if (aid === "session-toggle") {
      if (librarySession && typeof librarySession.toggleSessionMode === "function")
        librarySession.toggleSessionMode()
      else
        root.actionHint("Session toggle unavailable")
      return
    }
    if (aid === "full-escape" || aid === "pkg-escape" || aid === "pad-escape"
        || aid === "privacy-escape" || aid === "dt-escape" || aid === "acct-escape") {
      root.fullSettingsRequested(root.pageId || root.hubId || "system")
      return
    }
  }

  Component.onCompleted: refreshSinksQuiet()

  Rectangle {
    anchors.fill: parent
    color: Theme.bg
  }

  Rectangle {
    anchors.fill: parent
    border.width: root.detailFocused ? 2 : 0
    border.color: Theme.accent
    color: "transparent"
    z: 2
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Theme.spaceXl
    spacing: Theme.spaceMd
    visible: !!root.item

    Text {
      Layout.fillWidth: true
      text: root.title.length ? root.title : "Settings"
      color: Theme.text
      font.family: Theme.fontFamily
      font.pixelSize: 36
      font.weight: Font.Bold
      elide: Text.ElideRight
    }

    Text {
      Layout.fillWidth: true
      text: root.meta
      color: Theme.textDim
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSize + 1
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: statusLbl.implicitHeight + 16
      visible: root.statusStrip.length > 0
      radius: Theme.radiusMd
      color: Theme.elevatedFill
      border.width: 1
      border.color: Theme.chromeBorder

      Text {
        id: statusLbl
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: Theme.spaceMd
        text: root.statusStrip
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize + 2
        font.weight: Font.DemiBold
        elide: Text.ElideRight
      }
    }

    TextField {
      id: passField
      Layout.fillWidth: true
      Layout.preferredHeight: 48
      visible: root.mode === "wifiPassword"
      placeholderText: "Password for " + root.passwordSsid
      echoMode: TextInput.Password
      text: root.passwordDraft
      color: Theme.text
      placeholderTextColor: Theme.textMute
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSize + 2
      leftPadding: 14
      rightPadding: 14
      background: Rectangle {
        radius: Theme.radiusMd
        color: Theme.elevatedFill
        border.width: passField.activeFocus ? 2 : 1
        border.color: passField.activeFocus ? Theme.accent : Theme.chromeBorder
      }
      onTextChanged: {
        if (text !== root.passwordDraft)
          root.passwordDraft = text
      }
      Keys.onReturnPressed: root.runAction("wifi-pass-connect")
      Keys.onEnterPressed: root.runAction("wifi-pass-connect")
      Keys.onEscapePressed: root.exitDrill()
    }

    Flickable {
      Layout.fillWidth: true
      Layout.fillHeight: true
      contentWidth: width
      contentHeight: actionCol.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      ColumnLayout {
        id: actionCol
        width: parent.width
        spacing: Theme.spaceSm

        Repeater {
          model: root.actions

          Rectangle {
            required property var modelData
            required property int index
            Layout.fillWidth: true
            Layout.preferredHeight: 56
            radius: Theme.radiusLg
            opacity: modelData.enabled === false ? 0.55 : 1
            color: {
              if (root.detailFocused && index === root.actionIndex)
                return Theme.chromeAccentSoft
              if (index === root.actionIndex)
                return Theme.chromeHover
              return Theme.elevatedFill
            }
            border.width: root.detailFocused && index === root.actionIndex ? 1 : 0
            border.color: Theme.accent

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: Theme.spaceMd
              anchors.rightMargin: Theme.spaceMd
              spacing: Theme.spaceMd

              Text {
                Layout.fillWidth: true
                text: modelData.label
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize + 2
                font.weight: index === root.actionIndex ? Font.DemiBold : Font.Normal
                elide: Text.ElideRight
              }

              Text {
                visible: modelData.hint && String(modelData.hint).length
                text: modelData.hint
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                elide: Text.ElideRight
                Layout.maximumWidth: parent.width * 0.45
              }
            }

            MouseArea {
              anchors.fill: parent
              enabled: modelData.enabled !== false
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.actionIndex = index
                root.runAction(modelData.id)
              }
            }
          }
        }
      }
    }
  }

  ColumnLayout {
    anchors.centerIn: parent
    width: Math.min(parent.width - 80, 420)
    spacing: Theme.spaceMd
    visible: !root.item

    Text {
      Layout.fillWidth: true
      text: "No Settings page selected"
      color: Theme.textMute
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSize + 4
      font.weight: Font.DemiBold
      horizontalAlignment: Text.AlignHCenter
    }
  }
}
