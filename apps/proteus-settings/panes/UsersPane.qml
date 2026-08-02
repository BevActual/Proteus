import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../shared"
import "../kit"

// Users: session actions + read-only local accounts (SETTINGS-IA §2).
// Add/remove users stays Out — no useradd UI.
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: Theme.spaceMd

  property bool active: false
  signal requestGo(string id)

  property string currentName: ""
  property string currentFullName: ""
  property string currentHome: ""
  property string currentUid: ""
  property string currentGroups: ""
  property var otherUsers: []
  property string loadError: ""
  property string sessionBusy: ""
  property string pendingPower: ""
  property bool usersBusy: false
  property bool usersLoaded: false
  property bool greeterBusy: false
  property bool greeterLoaded: false
  property bool greeterActive: false
  property bool greeterEnabled: false
  property bool greeterAutologin: false
  property string greeterUser: ""
  property string greeterHint: "Checking greetd…"
  property string greeterConf: "/etc/greetd/config.toml"
  property string greeterCommand: ""
  property bool greeterHelperInstalled: false
  property string greeterWriteMsg: ""
  property bool greeterWriteError: false
  property var greeterPendingArgs: []

  // Lock-screen PIN (hashed under ~/.local/share/proteus/auth — not settings.json)
  property bool pinConfigured: false
  property int pinLength: 0
  property bool pinBusy: false
  property bool pinLoaded: false
  property string pinForm: "" // "" | "set" | "clear"
  property string pinPasswordDraft: ""
  property string pinDraft: ""
  property string pinConfirmDraft: ""
  property string pinStatusMsg: ""
  property bool pinStatusError: false

  readonly property string pinCliPath: {
    const u = Qt.resolvedUrl("../../../shell/scripts/proteus-pin.py")
    const fromUrl = String(u).replace(/^file:\/\//, "")
    const rootEnv = String(Quickshell.env("PROTEUS_ROOT") || "").trim()
    if (rootEnv.length)
      return rootEnv + "/shell/scripts/proteus-pin.py"
    return fromUrl
  }

  readonly property string greetdStatusFallback: {
    const u = Qt.resolvedUrl("../../../shell/scripts/proteus-greetd-status.py")
    const fromUrl = String(u).replace(/^file:\/\//, "")
    const rootEnv = String(Quickshell.env("PROTEUS_ROOT") || "").trim()
    if (rootEnv.length)
      return rootEnv + "/shell/scripts/proteus-greetd-status.py"
    return fromUrl
  }

  readonly property string pinStatusTrailing: {
    if (root.pinBusy && !root.pinLoaded)
      return "…"
    if (!root.pinLoaded)
      return "…"
    if (root.pinConfigured)
      return "On · " + root.pinLength + " digits"
    return "Off"
  }

  readonly property string greeterStatusTrailing: {
    if (root.greeterBusy || !root.greeterLoaded)
      return "…"
    if (root.greeterActive)
      return "Active"
    if (root.greeterEnabled)
      return "Enabled"
    return "Off"
  }

  readonly property string currentUserHint: {
    if (root.loadError.length)
      return root.loadError
    if (root.usersBusy || !root.usersLoaded)
      return "Reading getent / id…"
    if (root.currentName.length)
      return root.currentName + " · this session"
    return "Unknown"
  }

  readonly property var sessionActions: [
    {
      label: "Lock",
      action: "lock",
      hint: "Lock screen now · quickshell ipc / loginctl",
      trailing: "Now",
      destructive: false
    },
    {
      label: "Log out",
      action: "logout",
      hint: "End this Hyprland session · hyprctl dispatch exit",
      trailing: "Exit",
      destructive: false
    },
    {
      label: "Reboot",
      action: "reboot",
      hint: "Restart the machine · systemctl reboot",
      trailing: "Reboot",
      destructive: true
    },
    {
      label: "Shut down",
      action: "shutdown",
      hint: "Power off · systemctl poweroff",
      trailing: "Power off",
      destructive: true
    }
  ]

  function refresh() {
    root.usersBusy = true
    root.loadError = ""
    usersProc.running = false
    usersProc.running = true
    root.refreshGreeter()
    root.refreshPin()
  }

  function refreshPin() {
    root.pinBusy = true
    pinStatusProc.running = false
    pinStatusProc.running = true
  }

  function openPinSet() {
    root.pinForm = "set"
    root.pinPasswordDraft = ""
    root.pinDraft = ""
    root.pinConfirmDraft = ""
    root.pinStatusMsg = ""
    root.pinStatusError = false
  }

  function openPinClear() {
    root.pinForm = "clear"
    root.pinPasswordDraft = ""
    root.pinDraft = ""
    root.pinConfirmDraft = ""
    root.pinStatusMsg = ""
    root.pinStatusError = false
  }

  function cancelPinForm() {
    root.pinForm = ""
    root.pinPasswordDraft = ""
    root.pinDraft = ""
    root.pinConfirmDraft = ""
    root.pinStatusMsg = ""
    root.pinStatusError = false
  }

  function submitPinSet() {
    if (root.pinBusy)
      return
    const pw = String(root.pinPasswordDraft || "")
    const pin = String(root.pinDraft || "")
    const conf = String(root.pinConfirmDraft || "")
    if (!pw.length) {
      root.pinStatusMsg = "Enter your account password"
      root.pinStatusError = true
      return
    }
    if (!/^\d{4,8}$/.test(pin)) {
      root.pinStatusMsg = "PIN must be 4–8 digits"
      root.pinStatusError = true
      return
    }
    if (pin !== conf) {
      root.pinStatusMsg = "PINs do not match"
      root.pinStatusError = true
      return
    }
    root.pinBusy = true
    root.pinStatusMsg = "Saving…"
    root.pinStatusError = false
    pinSetProc.stdinPayload = pw + "\n" + pin + "\n" + conf + "\n"
    pinSetProc.running = false
    pinSetProc.running = true
  }

  function submitPinClear() {
    if (root.pinBusy)
      return
    const secret = String(root.pinPasswordDraft || "")
    if (!secret.length) {
      root.pinStatusMsg = "Enter your password or current PIN"
      root.pinStatusError = true
      return
    }
    root.pinBusy = true
    root.pinStatusMsg = "Turning off…"
    root.pinStatusError = false
    pinClearProc.stdinPayload = secret + "\n"
    pinClearProc.running = false
    pinClearProc.running = true
  }

  function refreshGreeter() {
    root.greeterBusy = true
    greeterHelperProbe.running = false
    greeterHelperProbe.running = true
    greeterProc.running = false
    greeterProc.running = true
  }

  function _greetdResolveScript() {
    return "BIN=\"\"; "
        + "if [ -x /usr/local/libexec/proteus-greetd ]; then BIN=/usr/local/libexec/proteus-greetd; "
        + "elif command -v proteus-greetd >/dev/null 2>&1; then BIN=$(command -v proteus-greetd); fi; "
        + "printf '%s' \"$BIN\""
  }

  function setAutologin(enabled) {
    root.greeterWriteMsg = ""
    root.greeterWriteError = false
    if (!root.greeterHelperInstalled) {
      root.greeterWriteMsg = "Install proteus-greetd first (polkit writer)"
      root.greeterWriteError = true
      return
    }
    if (enabled) {
      const u = root.currentName.length ? root.currentName : ""
      if (!u.length) {
        root.greeterWriteMsg = "Current user unknown — cannot enable autologin"
        root.greeterWriteError = true
        return
      }
      root.greeterPendingArgs = ["set-autologin", u]
    } else {
      root.greeterPendingArgs = ["clear-autologin"]
    }
    root.greeterBusy = true
    greeterResolveProc.command = ["bash", "-c", root._greetdResolveScript()]
    greeterResolveProc.running = false
    greeterResolveProc.running = true
  }

  function installGreeterHelper() {
    const proot = String(Quickshell.env("PROTEUS_ROOT") || "/mnt/proteus")
    Quickshell.execDetached({
      command: [
        "bash", "-lc",
        "if [[ -x " + JSON.stringify(proot + "/vm/guest/install-proteus-greetd.sh") + " ]]; then "
            + "pkexec bash " + JSON.stringify(proot + "/vm/guest/install-proteus-greetd.sh") + "; "
            + "elif [[ -x /mnt/proteus/vm/guest/install-proteus-greetd.sh ]]; then "
            + "pkexec bash /mnt/proteus/vm/guest/install-proteus-greetd.sh; fi"
      ]
    })
    root.greeterWriteMsg = "Install started — re-open Users after auth"
    root.greeterWriteError = false
  }

  function openGreeterConf() {
    const path = root.greeterConf.length ? root.greeterConf : "/etc/greetd/config.toml"
    Quickshell.execDetached({
      command: [
        "bash",
        "-lc",
        "(command -v xdg-open >/dev/null && xdg-open " + path + ")"
            + " || exec proteus-terminal -e less " + path
      ]
    })
  }

  function runSession(action) {
    if (!action || root.sessionBusy.length)
      return
    if (action === "reboot" || action === "shutdown") {
      root.pendingPower = action
      return
    }
    root._runSessionNow(action)
  }

  function _runSessionNow(action) {
    if (!action || root.sessionBusy.length)
      return
    root.pendingPower = ""
    root.sessionBusy = action
    Config.session(action)
    sessionBusyClear.restart()
  }

  function cancelPower() {
    root.pendingPower = ""
  }

  function confirmPower() {
    const a = root.pendingPower
    if (!a.length)
      return
    root._runSessionNow(a)
  }

  onActiveChanged: {
    if (active)
      refresh()
    else
      root.pendingPower = ""
  }

  Component.onCompleted: refresh()

  Timer {
    id: sessionBusyClear
    interval: 1200
    onTriggered: root.sessionBusy = ""
  }

  SettingsGroup {
    title: "Session"

    Repeater {
      model: root.sessionActions

      SettingsFormRow {
        required property var modelData
        required property int index
        label: modelData.label
        hint: {
          if (root.sessionBusy === modelData.action)
            return "Working…"
          if (root.pendingPower === modelData.action)
            return "Confirm below"
          return modelData.hint
        }
        showSeparator: index < root.sessionActions.length - 1
        interactive: root.sessionBusy.length === 0
        labelColor: modelData.destructive ? Theme.danger : Theme.text
        onActivated: root.runSession(modelData.action)
        Text {
          text: {
            if (root.sessionBusy === modelData.action)
              return "…"
            if (root.pendingPower === modelData.action)
              return "…"
            return modelData.trailing
          }
          color: {
            if (root.sessionBusy === modelData.action || root.pendingPower === modelData.action)
              return Theme.textMute
            return modelData.destructive ? Theme.danger : Theme.accent
          }
          font.family: Theme.fontFamily
          font.pixelSize: 12
        }
      }
    }
  }

  PackagesConfirm {
    open: root.pendingPower.length > 0
    title: root.pendingPower === "shutdown" ? "Shut down this machine?" : "Reboot this machine?"
    detail: root.pendingPower === "shutdown"
        ? "Ends all sessions and powers off."
        : "Ends all sessions and restarts."
    footnote: "Confirm here first — then systemctl runs."
    onCancelled: root.cancelPower()
    onConfirmed: root.confirmPower()
  }

  SettingsGroup {
    title: "Lock screen PIN"

    SettingsFormRow {
      label: "PIN unlock"
      hint: root.pinConfigured
          ? "Unlock desktop and console lock screens with a short PIN · password still works"
          : "Optional short PIN for couch or desk unlock · does not replace your account password"
      showSeparator: true
      Text {
        text: root.pinStatusTrailing
        color: root.pinConfigured ? Theme.accent : Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: 12
      }
    }

    SettingsFormRow {
      visible: root.pinForm.length === 0 && !root.pinConfigured
      label: "Set PIN"
      hint: "Requires your account password · 4–8 digits"
      showSeparator: false
      interactive: !root.pinBusy
      onActivated: root.openPinSet()
      Text {
        text: "Set"
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: 12
      }
    }

    SettingsFormRow {
      visible: root.pinForm.length === 0 && root.pinConfigured
      label: "Change PIN"
      hint: "Requires your account password"
      showSeparator: true
      interactive: !root.pinBusy
      onActivated: root.openPinSet()
      Text {
        text: "Change"
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: 12
      }
    }

    SettingsFormRow {
      visible: root.pinForm.length === 0 && root.pinConfigured
      label: "Turn off PIN"
      hint: "Confirm with password or current PIN"
      showSeparator: false
      interactive: !root.pinBusy
      onActivated: root.openPinClear()
      Text {
        text: "Off"
        color: Theme.danger
        font.family: Theme.fontFamily
        font.pixelSize: 12
      }
    }

    // Set / change form
    ColumnLayout {
      visible: root.pinForm === "set"
      Layout.fillWidth: true
      spacing: Theme.spaceSm

      Text {
        Layout.fillWidth: true
        Layout.leftMargin: Theme.spaceMd
        Layout.rightMargin: Theme.spaceMd
        text: "Account password"
        color: Theme.textDim
        font.family: Theme.fontFamily
        font.pixelSize: 12
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 40
        Layout.leftMargin: Theme.spaceMd
        Layout.rightMargin: Theme.spaceMd
        radius: Theme.radiusMd
        color: Theme.bgHover
        border.width: 1
        border.color: pinPassInput.activeFocus ? Theme.accent : Theme.border
        TextInput {
          id: pinPassInput
          anchors.fill: parent
          anchors.leftMargin: 10
          anchors.rightMargin: 10
          color: Theme.text
          font.family: Theme.fontFamily
          font.pixelSize: 13
          echoMode: TextInput.Password
          verticalAlignment: TextInput.AlignVCenter
          clip: true
          text: root.pinPasswordDraft
          onTextChanged: root.pinPasswordDraft = text
        }
      }

      Text {
        Layout.fillWidth: true
        Layout.leftMargin: Theme.spaceMd
        Layout.rightMargin: Theme.spaceMd
        text: "New PIN (4–8 digits)"
        color: Theme.textDim
        font.family: Theme.fontFamily
        font.pixelSize: 12
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 40
        Layout.leftMargin: Theme.spaceMd
        Layout.rightMargin: Theme.spaceMd
        radius: Theme.radiusMd
        color: Theme.bgHover
        border.width: 1
        border.color: pinNewInput.activeFocus ? Theme.accent : Theme.border
        TextInput {
          id: pinNewInput
          anchors.fill: parent
          anchors.leftMargin: 10
          anchors.rightMargin: 10
          color: Theme.text
          font.family: Theme.fontFamily
          font.pixelSize: 13
          echoMode: TextInput.Password
          inputMethodHints: Qt.ImhDigitsOnly
          verticalAlignment: TextInput.AlignVCenter
          clip: true
          text: root.pinDraft
          onTextChanged: {
            const d = text.replace(/\D/g, "").slice(0, 8)
            if (d !== text)
              text = d
            root.pinDraft = d
          }
        }
      }

      Text {
        Layout.fillWidth: true
        Layout.leftMargin: Theme.spaceMd
        Layout.rightMargin: Theme.spaceMd
        text: "Confirm PIN"
        color: Theme.textDim
        font.family: Theme.fontFamily
        font.pixelSize: 12
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 40
        Layout.leftMargin: Theme.spaceMd
        Layout.rightMargin: Theme.spaceMd
        radius: Theme.radiusMd
        color: Theme.bgHover
        border.width: 1
        border.color: pinConfirmInput.activeFocus ? Theme.accent : Theme.border
        TextInput {
          id: pinConfirmInput
          anchors.fill: parent
          anchors.leftMargin: 10
          anchors.rightMargin: 10
          color: Theme.text
          font.family: Theme.fontFamily
          font.pixelSize: 13
          echoMode: TextInput.Password
          inputMethodHints: Qt.ImhDigitsOnly
          verticalAlignment: TextInput.AlignVCenter
          clip: true
          text: root.pinConfirmDraft
          onTextChanged: {
            const d = text.replace(/\D/g, "").slice(0, 8)
            if (d !== text)
              text = d
            root.pinConfirmDraft = d
          }
          Keys.onReturnPressed: root.submitPinSet()
        }
      }

      SettingsFormRow {
        label: "Save PIN"
        hint: "Writes ~/.local/share/proteus/auth/pin (0600) · never settings.json"
        showSeparator: true
        interactive: !root.pinBusy
        onActivated: root.submitPinSet()
        Text {
          text: root.pinBusy ? "…" : "Save"
          color: Theme.accent
          font.family: Theme.fontFamily
          font.pixelSize: 12
        }
      }

      SettingsFormRow {
        label: "Cancel"
        hint: ""
        showSeparator: false
        interactive: !root.pinBusy
        onActivated: root.cancelPinForm()
      }
    }

    // Clear form
    ColumnLayout {
      visible: root.pinForm === "clear"
      Layout.fillWidth: true
      spacing: Theme.spaceSm

      Text {
        Layout.fillWidth: true
        Layout.leftMargin: Theme.spaceMd
        Layout.rightMargin: Theme.spaceMd
        text: "Password or current PIN"
        color: Theme.textDim
        font.family: Theme.fontFamily
        font.pixelSize: 12
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 40
        Layout.leftMargin: Theme.spaceMd
        Layout.rightMargin: Theme.spaceMd
        radius: Theme.radiusMd
        color: Theme.bgHover
        border.width: 1
        border.color: pinClearInput.activeFocus ? Theme.accent : Theme.border
        TextInput {
          id: pinClearInput
          anchors.fill: parent
          anchors.leftMargin: 10
          anchors.rightMargin: 10
          color: Theme.text
          font.family: Theme.fontFamily
          font.pixelSize: 13
          echoMode: TextInput.Password
          verticalAlignment: TextInput.AlignVCenter
          clip: true
          text: root.pinPasswordDraft
          onTextChanged: root.pinPasswordDraft = text
          Keys.onReturnPressed: root.submitPinClear()
        }
      }

      SettingsFormRow {
        label: "Turn off PIN"
        hint: "Removes the unlock PIN hash"
        showSeparator: true
        interactive: !root.pinBusy
        labelColor: Theme.danger
        onActivated: root.submitPinClear()
        Text {
          text: root.pinBusy ? "…" : "Off"
          color: Theme.danger
          font.family: Theme.fontFamily
          font.pixelSize: 12
        }
      }

      SettingsFormRow {
        label: "Cancel"
        hint: ""
        showSeparator: false
        interactive: !root.pinBusy
        onActivated: root.cancelPinForm()
      }
    }

    Text {
      visible: root.pinStatusMsg.length > 0
      Layout.fillWidth: true
      Layout.leftMargin: Theme.spaceMd
      Layout.rightMargin: Theme.spaceMd
      Layout.bottomMargin: Theme.spaceSm
      text: root.pinStatusMsg
      color: root.pinStatusError ? Theme.danger : Theme.textMute
      font.family: Theme.fontFamily
      font.pixelSize: 12
      wrapMode: Text.WordWrap
    }
  }

  SettingsGroup {
    title: "Current user"

    SettingsFormRow {
      label: "Username"
      hint: root.currentUserHint
      showSeparator: true
      labelColor: root.loadError.length ? Theme.danger : Theme.text
    }

    SettingsFormRow {
      label: "Full name"
      hint: {
        if (root.usersBusy || !root.usersLoaded)
          return "…"
        return root.currentFullName.length ? root.currentFullName : "—"
      }
      showSeparator: true
    }

    SettingsFormRow {
      label: "Home"
      hint: {
        if (root.usersBusy || !root.usersLoaded)
          return "…"
        return root.currentHome.length ? root.currentHome : "—"
      }
      showSeparator: true
    }

    SettingsFormRow {
      label: "UID"
      hint: {
        if (root.usersBusy || !root.usersLoaded)
          return "…"
        return root.currentUid.length ? root.currentUid : "—"
      }
      showSeparator: true
    }

    SettingsFormRow {
      label: "Groups"
      hint: {
        if (root.usersBusy || !root.usersLoaded)
          return "…"
        if (root.currentGroups.length)
          return root.currentGroups
        return "No supplementary groups"
      }
      showSeparator: true
    }

    SettingsFormRow {
      label: "Refresh users"
      hint: root.usersBusy ? "Reading…" : "Reload id / getent passwd"
      showSeparator: false
      interactive: !root.usersBusy
      onActivated: root.refresh()
      Text {
        text: root.usersBusy ? "…" : "↻"
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }
    }
  }

  SettingsGroup {
    title: "Other local users"

    SettingsFormRow {
      visible: !root.usersBusy && root.usersLoaded && root.otherUsers.length === 0 && !root.loadError.length
      label: "Accounts"
      hint: "No other login-capable users (UID ≥ 1000)"
      showSeparator: false
    }

    Repeater {
      model: root.otherUsers

      SettingsFormRow {
        required property var modelData
        required property int index
        label: modelData.name || "—"
        hint: modelData.uid ? ("UID " + modelData.uid + " · login shell") : "Local account"
        showSeparator: index < root.otherUsers.length - 1
        Text {
          text: "Read-only"
          color: Theme.textMute
          font.family: Theme.fontFamily
          font.pixelSize: 12
        }
      }
    }
  }

  SettingsGroup {
    title: "Accounts"

    SettingsFormRow {
      label: "Online accounts"
      hint: "Provider seats · Google PKCE when configured"
      showSeparator: true
      interactive: true
      onActivated: root.requestGo("accounts")
      Text {
        text: "›"
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }
    }

    SettingsFormRow {
      label: "Add or remove users"
      hint: "Not in Settings — use useradd / userdel or your distro tools"
      showSeparator: true
    }

    SettingsFormRow {
      label: "Login & greeter"
      hint: {
        if (root.greeterBusy || !root.greeterLoaded)
          return "Checking greetd…"
        return root.greeterHint
      }
      showSeparator: true
      Text {
        text: root.greeterStatusTrailing
        color: root.greeterActive ? Theme.accent : Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: 12
      }
    }

    SettingsFormRow {
      label: "Autologin"
      hint: {
        if (!root.greeterHelperInstalled)
          return "Needs proteus-greetd (polkit) · writes [initial_session] only; no greetd restart"
        if (root.greeterAutologin)
          return "On · " + (root.greeterUser || "user") + " → proteus-session (next boot / greeter cycle)"
        return "Off · cold boot uses tuigreet · enable for this user (" + (root.currentName || "?") + ")"
      }
      showSeparator: true
      RowLayout {
        spacing: Theme.spaceSm
        Text {
          text: root.greeterAutologin ? "On" : "Off"
          color: root.greeterAutologin ? Theme.accent : Theme.textMute
          font.family: Theme.fontFamily
          font.pixelSize: 12
        }
        Rectangle {
          visible: root.greeterHelperInstalled
          Layout.preferredHeight: 28
          Layout.preferredWidth: autoLoginBtn.implicitWidth + 20
          radius: Theme.radiusPill - 8
          color: root.greeterBusy ? Theme.bgHover : Theme.accent
          Text {
            id: autoLoginBtn
            anchors.centerIn: parent
            text: root.greeterBusy ? "…" : (root.greeterAutologin ? "Turn off" : "Turn on")
            color: "#ffffff"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
            font.weight: Font.Medium
          }
          MouseArea {
            anchors.fill: parent
            enabled: !root.greeterBusy
            cursorShape: Qt.PointingHandCursor
            onClicked: root.setAutologin(!root.greeterAutologin)
          }
        }
      }
    }

    SettingsFormRow {
      visible: !root.greeterHelperInstalled && root.greeterLoaded
      label: "Install proteus-greetd…"
      hint: "pkexec · polkit writer for greetd autologin"
      showSeparator: true
      interactive: true
      onActivated: root.installGreeterHelper()
      Text {
        text: "›"
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }
    }

    SettingsFormRow {
      label: "Edit greetd config…"
      hint: "Escape · " + (root.greeterConf.length ? root.greeterConf : "/etc/greetd/config.toml")
          + " · Settings writes only [initial_session] via proteus-greetd"
      showSeparator: false
      interactive: true
      onActivated: root.openGreeterConf()
      Text {
        text: "›"
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }
    }
  }

  Text {
    visible: root.greeterWriteMsg.length > 0
    Layout.fillWidth: true
    Layout.maximumWidth: 480
    text: root.greeterWriteMsg
    color: root.greeterWriteError ? Theme.danger : Theme.accent
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSizeSm
    wrapMode: Text.WordWrap
  }

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 480
    text: "Fact: Config.session · id/getent · greetd via proteus-greetd (pkexec [initial_session]) · lock PIN via proteus-pin.py (~/.local/share/proteus/auth/pin). Reboot/shutdown confirm in-pane. No useradd from Settings."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }

  Process {
    id: pinStatusProc
    command: ["python3", root.pinCliPath, "status"]
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        root.pinBusy = false
        root.pinLoaded = true
        try {
          const o = JSON.parse(String(this.text || "").trim() || "{}")
          root.pinConfigured = !!o.configured
          root.pinLength = o.configured ? (parseInt(o.length, 10) || 0) : 0
        } catch (e) {
          root.pinConfigured = false
          root.pinLength = 0
        }
      }
    }
  }

  Process {
    id: pinSetProc
    property string stdinPayload: ""
    command: ["python3", root.pinCliPath, "set"]
    stdinEnabled: true
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        root.pinBusy = false
        const raw = String(this.text || "").trim()
        try {
          const o = JSON.parse(raw || "{}")
          if (o.ok) {
            root.pinConfigured = true
            root.pinLength = parseInt(o.length, 10) || root.pinDraft.length
            root.cancelPinForm()
            root.pinStatusMsg = "PIN saved"
            root.pinStatusError = false
          } else {
            const err = o.error || "failed"
            if (err === "wrong_password")
              root.pinStatusMsg = "Wrong account password"
            else if (err === "pin_mismatch")
              root.pinStatusMsg = "PINs do not match"
            else
              root.pinStatusMsg = String(err)
            root.pinStatusError = true
            root.pinPasswordDraft = ""
          }
        } catch (e) {
          root.pinStatusMsg = "Could not save PIN"
          root.pinStatusError = true
        }
      }
    }
    onStarted: {
      write(stdinPayload)
      stdinPayload = ""
      stdinEnabled = false
    }
    onExited: (exitCode, exitStatus) => {
      stdinEnabled = true
      stdinPayload = ""
      if (exitCode === 2 && root.pinBusy) {
        root.pinBusy = false
        root.pinStatusMsg = "PIN helper failed"
        root.pinStatusError = true
      }
    }
  }

  Process {
    id: pinClearProc
    property string stdinPayload: ""
    command: ["python3", root.pinCliPath, "clear"]
    stdinEnabled: true
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        root.pinBusy = false
        const raw = String(this.text || "").trim()
        try {
          const o = JSON.parse(raw || "{}")
          if (o.ok) {
            root.pinConfigured = false
            root.pinLength = 0
            root.cancelPinForm()
            root.pinStatusMsg = "PIN turned off"
            root.pinStatusError = false
          } else {
            root.pinStatusMsg = "Wrong password or PIN"
            root.pinStatusError = true
            root.pinPasswordDraft = ""
          }
        } catch (e) {
          root.pinStatusMsg = "Could not turn off PIN"
          root.pinStatusError = true
        }
      }
    }
    onStarted: {
      write(stdinPayload)
      stdinPayload = ""
      stdinEnabled = false
    }
    onExited: (exitCode, exitStatus) => {
      stdinEnabled = true
      stdinPayload = ""
      if (exitCode === 2 && root.pinBusy) {
        root.pinBusy = false
        root.pinStatusMsg = "PIN helper failed"
        root.pinStatusError = true
      }
    }
  }

  Process {
    id: greeterProc
    command: [
      "bash", "-lc",
      "P=" + JSON.stringify(String(Quickshell.env("PROTEUS_ROOT") || "/mnt/proteus")) + "; "
          + "for c in /usr/local/libexec/proteus-greetd "
          + "\"$P/services/proteus-greetd/target/release/proteus-greetd\" "
          + "\"$P/services/proteus-greetd/bin/proteus-greetd\"; do "
          + "if [[ -x \"$c\" ]]; then exec \"$c\" show; fi; done; "
          + "if command -v proteus-greetd >/dev/null 2>&1; then exec proteus-greetd show; fi; "
          + "exec python3 " + JSON.stringify(root.greetdStatusFallback)
    ]
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        root.greeterBusy = false
        root.greeterLoaded = true
        try {
          const o = JSON.parse(String(this.text || "").trim() || "{}")
          root.greeterActive = !!o.active
          root.greeterEnabled = !!o.enabled
          root.greeterAutologin = !!o.autologin
          root.greeterUser = o.user || ""
          root.greeterCommand = o.command || ""
          root.greeterHint = o.hint || "Unknown"
          root.greeterConf = o.conf || "/etc/greetd/config.toml"
        } catch (e) {
          root.greeterHint = "Could not read greetd status"
          root.greeterActive = false
          root.greeterEnabled = false
          root.greeterAutologin = false
        }
      }
    }
  }

  Process {
    id: greeterHelperProbe
    command: [
      "bash", "-c",
      "if [ -x /usr/local/libexec/proteus-greetd ] || command -v proteus-greetd >/dev/null 2>&1; then echo 1; else echo 0; fi"
    ]
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        root.greeterHelperInstalled = String(this.text || "").trim() === "1"
      }
    }
  }

  Process {
    id: greeterResolveProc
    command: ["true"]
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        const bin = String(this.text || "").trim()
        if (!bin.length) {
          root.greeterBusy = false
          root.greeterHelperInstalled = false
          root.greeterWriteMsg = "proteus-greetd not installed"
          root.greeterWriteError = true
          return
        }
        const args = ["pkexec", bin]
        for (let i = 0; i < root.greeterPendingArgs.length; i++)
          args.push(root.greeterPendingArgs[i])
        greeterWriteProc.command = args
        greeterWriteProc.running = false
        greeterWriteProc.running = true
      }
    }
  }

  Process {
    id: greeterWriteProc
    command: ["true"]
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const o = JSON.parse(String(this.text || "").trim() || "{}")
          if (o.ok) {
            root.greeterWriteMsg = o.hint || "Saved"
            root.greeterWriteError = false
          } else {
            root.greeterWriteMsg = String(o.error || "write failed")
            root.greeterWriteError = true
          }
        } catch (e) {
          root.greeterWriteMsg = "Could not parse proteus-greetd response"
          root.greeterWriteError = true
        }
      }
    }
    onExited: () => {
      root.greeterBusy = false
      root.refreshGreeter()
      greeterHelperProbe.running = false
      greeterHelperProbe.running = true
    }
  }

  Process {
    id: usersProc
    // One JSON object: name, uid, groups, others[{name,uid}]
    command: [
      "python3",
      "-c",
      "import json,os,pwd,grp; uid=os.getuid(); me=pwd.getpwuid(uid); gnames=[];\n"
          + "for g in os.getgroups():\n"
          + "  try: gnames.append(grp.getgrgid(g).gr_name)\n"
          + "  except KeyError: pass\n"
          + "gecos=(me.pw_gecos or '').split(',',1)[0].strip()\n"
          + "nologin=('/usr/bin/nologin','/sbin/nologin','/bin/false','/usr/sbin/nologin'); others=[]\n"
          + "for p in pwd.getpwall():\n"
          + "  if p.pw_uid<1000 or p.pw_uid==uid or p.pw_name=='nobody': continue\n"
          + "  if p.pw_shell in nologin: continue\n"
          + "  others.append({'name':p.pw_name,'uid':str(p.pw_uid)})\n"
          + "others.sort(key=lambda x:x['name']); print(json.dumps({'name':me.pw_name,'full_name':gecos,'home':me.pw_dir,'uid':str(uid),'groups':', '.join(gnames),'others':others}))"
    ]
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        root.usersBusy = false
        root.usersLoaded = true
        const raw = String(this.text || "").trim()
        if (!raw.length) {
          root.loadError = "Could not read local users"
          root.currentName = ""
          root.currentFullName = ""
          root.currentHome = ""
          root.currentUid = ""
          root.currentGroups = ""
          root.otherUsers = []
          return
        }
        try {
          const obj = JSON.parse(raw)
          root.currentName = obj.name || ""
          root.currentFullName = obj.full_name || ""
          root.currentHome = obj.home || ""
          root.currentUid = obj.uid || ""
          root.currentGroups = obj.groups || ""
          root.otherUsers = obj.others || []
          root.loadError = ""
        } catch (e) {
          root.loadError = "Could not parse user list"
          root.otherUsers = []
        }
      }
    }
  }
}
