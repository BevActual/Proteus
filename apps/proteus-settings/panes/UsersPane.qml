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

  readonly property var sessionActions: [
    {
      label: "Lock",
      action: "lock",
      hint: "Show the lock screen now",
      destructive: false
    },
    {
      label: "Log out",
      action: "logout",
      hint: "End this Hyprland session",
      destructive: false
    },
    {
      label: "Reboot",
      action: "reboot",
      hint: "Restart the machine",
      destructive: true
    },
    {
      label: "Shut down",
      action: "shutdown",
      hint: "Power off the machine",
      destructive: true
    }
  ]

  function refresh() {
    usersProc.running = false
    usersProc.running = true
  }

  onActiveChanged: {
    if (active)
      refresh()
  }

  Component.onCompleted: refresh()

  SettingsGroup {
    title: "Session"

    Repeater {
      model: root.sessionActions

      SettingsFormRow {
        required property var modelData
        required property int index
        label: modelData.label
        hint: modelData.hint
        showSeparator: index < root.sessionActions.length - 1
        interactive: true
        labelColor: modelData.destructive ? Theme.danger : Theme.text
        onActivated: Config.session(modelData.action)
        Text {
          text: "›"
          color: Theme.textMute
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSize
        }
      }
    }
  }

  SettingsGroup {
    title: "Current user"

    SettingsFormRow {
      label: "Username"
      hint: root.currentName.length ? root.currentName : "…"
      showSeparator: true
    }

    SettingsFormRow {
      label: "UID"
      hint: root.currentUid.length ? root.currentUid : "…"
      showSeparator: true
    }

    SettingsFormRow {
      label: "Groups"
      hint: root.currentGroups.length ? root.currentGroups : "…"
      showSeparator: false
    }
  }

  SettingsGroup {
    visible: root.otherUsers.length > 0
    title: "Other local users"

    Repeater {
      model: root.otherUsers

      SettingsFormRow {
        required property var modelData
        required property int index
        label: modelData.name || "—"
        hint: modelData.uid ? ("UID " + modelData.uid) : ""
        showSeparator: index < root.otherUsers.length - 1
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
    visible: root.loadError.length > 0
    text: root.loadError
    color: Theme.danger
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 480
    text: "Fact: id / getent passwd · session via Config.session (hyprctl / systemctl / loginctl). No useradd from Settings."
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
        const raw = String(this.text || "").trim()
        if (!raw.length) {
          root.loadError = "Could not read local users"
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
        }
      }
    }
  }
}
