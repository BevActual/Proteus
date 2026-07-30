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
  property string currentName: ""
  property string currentUid: ""
  property string currentGroups: ""
  property var otherUsers: []
  property string loadError: ""
  property string sessionBusy: ""
  property bool usersBusy: false
  property bool usersLoaded: false

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
  }

  function runSession(action) {
    if (!action || root.sessionBusy.length)
      return
    root.sessionBusy = action
    Config.session(action)
    sessionBusyClear.restart()
  }

  onActiveChanged: {
    if (active)
      refresh()
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
          return modelData.hint
        }
        showSeparator: index < root.sessionActions.length - 1
        interactive: root.sessionBusy.length === 0
        labelColor: modelData.destructive ? Theme.danger : Theme.text
        onActivated: root.runSession(modelData.action)
        Text {
          text: root.sessionBusy === modelData.action ? "…" : modelData.trailing
          color: {
            if (root.sessionBusy === modelData.action)
              return Theme.textMute
            return modelData.destructive ? Theme.danger : Theme.accent
          }
          font.family: Theme.fontFamily
          font.pixelSize: 12
        }
      }
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
      label: "Add or remove users"
      hint: "Not in Settings — use useradd / userdel or your distro tools"
      showSeparator: true
    }

    SettingsFormRow {
      label: "Login & greeter"
      hint: "greetd / autologin prefs — planned"
      showSeparator: false
    }
  }

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 480
    text: "Fact: Config.session → lock ipc / hyprctl exit / systemctl reboot|poweroff · id / getent for accounts. No useradd from Settings."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
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
          + "nologin=('/usr/bin/nologin','/sbin/nologin','/bin/false','/usr/sbin/nologin'); others=[]\n"
          + "for p in pwd.getpwall():\n"
          + "  if p.pw_uid<1000 or p.pw_uid==uid or p.pw_name=='nobody': continue\n"
          + "  if p.pw_shell in nologin: continue\n"
          + "  others.append({'name':p.pw_name,'uid':str(p.pw_uid)})\n"
          + "others.sort(key=lambda x:x['name']); print(json.dumps({'name':me.pw_name,'uid':str(uid),'groups':', '.join(gnames),'others':others}))"
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
          root.currentUid = ""
          root.currentGroups = ""
          root.otherUsers = []
          return
        }
        try {
          const obj = JSON.parse(raw)
          root.currentName = obj.name || ""
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
