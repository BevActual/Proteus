import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../shared"
import "../kit"

// Network: devices + Bluetooth status + VPN list + editor hand-offs.
// Pairing / WireGuard wizards stay Out — use system tools (SETTINGS-IA §2).
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: Theme.spaceMd

  property bool active: false
  property var devices: []
  property string status: "Checking network…"

  property bool btAvailable: false
  property bool btPowered: false
  property string btAdapter: ""
  property string btHint: "Checking Bluetooth…"

  property var vpnConnections: []
  property string vpnStatus: "Checking VPN…"

  function stateHint(dev) {
    const parts = [dev.type, dev.state]
    if (dev.connection && dev.connection.length)
      parts.push(dev.connection)
    return parts.filter(p => p && p.length).join(" · ")
  }

  function isUp(dev) {
    return String(dev.state || "").toLowerCase() === "connected"
  }

  function kick(proc) {
    proc.running = false
    proc.running = true
  }

  function refresh() {
    kick(devProc)
    kick(btProc)
    kick(vpnProc)
  }

  onActiveChanged: {
    if (active)
      refresh()
  }

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 480
    visible: !root.devices.length
    text: root.status
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 12
    wrapMode: Text.WordWrap
  }

  SettingsGroup {
    visible: root.devices.length > 0
    title: "Devices"

    Repeater {
      model: root.devices

      SettingsFormRow {
        required property var modelData
        required property int index
        label: modelData.device
        hint: root.stateHint(modelData)
        showSeparator: index < root.devices.length - 1
        Text {
          text: root.isUp(modelData) ? "Connected" : ""
          color: Theme.accent
          font.family: Theme.fontFamily
          font.pixelSize: 12
        }
      }
    }
  }

  SettingsGroup {
    title: "Bluetooth"

    SettingsFormRow {
      label: root.btAdapter.length ? root.btAdapter : "Adapter"
      hint: root.btHint
      showSeparator: true
      Text {
        visible: root.btAvailable
        text: root.btPowered ? "On" : "Off"
        color: root.btPowered ? Theme.accent : Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: 12
      }
    }

    SettingsFormRow {
      label: "Open Bluetooth settings"
      hint: root.btAvailable
          ? "blueman-manager, or bluetoothctl in a terminal"
          : "Install BlueZ / blueman when this machine has Bluetooth"
      showSeparator: false
      interactive: root.btAvailable
      onActivated: Config.openBluetoothEditor()
      Text {
        text: root.btAvailable ? "›" : ""
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }
    }
  }

  SettingsGroup {
    title: "VPN"

    SettingsFormRow {
      visible: !root.vpnConnections.length
      label: "No profiles"
      hint: root.vpnStatus
      showSeparator: true
    }

    Repeater {
      model: root.vpnConnections

      SettingsFormRow {
        required property var modelData
        required property int index
        label: modelData.name
        hint: modelData.type || "vpn"
        showSeparator: true
        Text {
          text: modelData.active ? "Connected" : ""
          color: Theme.accent
          font.family: Theme.fontFamily
          font.pixelSize: 12
        }
      }
    }

    SettingsFormRow {
      label: "Open VPN / NetworkManager"
      hint: "Add or edit VPN profiles in the NetworkManager editor"
      showSeparator: false
      interactive: true
      onActivated: Config.openNetworkEditor()
      Text {
        text: "›"
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }
    }
  }

  SettingsGroup {
    SettingsFormRow {
      label: "Open network settings"
      hint: "NetworkManager editor, or nmtui in a terminal"
      showSeparator: false
      interactive: true
      onActivated: Config.openNetworkEditor()
      Text {
        text: "›"
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }
    }
  }

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 480
    text: "Fact: nmcli · bluetoothctl · nm-connection-editor / blueman. No in-pane pairing or WireGuard wizard."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }

  Process {
    id: devProc
    command: ["nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "dev", "status"]
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        const lines = String(this.text || "").trim().split("\n").filter(l => l.length)
        if (!lines.length) {
          root.devices = []
          root.status = "No NetworkManager devices found."
          return
        }
        root.devices = lines.map(l => {
          const p = l.split(":")
          return {
            device: p[0] || "?",
            type: p[1] || "",
            state: p[2] || "",
            connection: p[3] || ""
          }
        })
        root.status = ""
      }
    }
  }

  Process {
    id: btProc
    command: [
      "python3",
      "-c",
      "import json,shutil,subprocess\n"
          + "o={'available':False,'powered':False,'adapter':'','hint':'Bluetooth tools not installed'}\n"
          + "if shutil.which('bluetoothctl'):\n"
          + "  o['available']=True; o['hint']='Off'\n"
          + "  r=subprocess.run(['bluetoothctl','show'],capture_output=True,text=True)\n"
          + "  for line in (r.stdout or '').splitlines():\n"
          + "    s=line.strip()\n"
          + "    if s.startswith('Powered:'): o['powered']='yes' in s.lower(); o['hint']='Powered' if o['powered'] else 'Off'\n"
          + "    if s.startswith('Alias:') or s.startswith('Name:'): o['adapter']=s.split(':',1)[1].strip()\n"
          + "  if r.returncode!=0 and not (r.stdout or '').strip(): o['hint']='No adapter (bluetoothctl show failed)'\n"
          + "print(json.dumps(o))"
    ]
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const o = JSON.parse(String(this.text || "").trim() || "{}")
          root.btAvailable = !!o.available
          root.btPowered = !!o.powered
          root.btAdapter = o.adapter || ""
          root.btHint = o.hint || ""
        } catch (e) {
          root.btAvailable = false
          root.btHint = "Could not read Bluetooth status"
        }
      }
    }
  }

  Process {
    id: vpnProc
    command: [
      "python3",
      "-c",
      "import json,shutil,subprocess\n"
          + "out=[]; status='No VPN profiles in NetworkManager'\n"
          + "if not shutil.which('nmcli'):\n"
          + "  print(json.dumps({'connections':[],'status':'nmcli not found'})); raise SystemExit\n"
          + "r=subprocess.run(['nmcli','-t','-f','NAME,TYPE,ACTIVE','connection','show'],capture_output=True,text=True)\n"
          + "for line in (r.stdout or '').splitlines():\n"
          + "  if not line.strip(): continue\n"
          + "  p=line.split(':'); name=p[0] if p else ''; typ=(p[1] if len(p)>1 else '').lower(); act=(p[2] if len(p)>2 else '')\n"
          + "  if typ in ('vpn','wireguard','vpnc','openvpn') or 'vpn' in typ or typ=='wireguard':\n"
          + "    out.append({'name':name,'type':typ or 'vpn','active':act in ('yes','true','1')})\n"
          + "status=('' if out else 'No VPN profiles yet — add one in NetworkManager')\n"
          + "print(json.dumps({'connections':out,'status':status}))"
    ]
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const o = JSON.parse(String(this.text || "").trim() || "{}")
          root.vpnConnections = o.connections || []
          root.vpnStatus = o.status || ""
        } catch (e) {
          root.vpnConnections = []
          root.vpnStatus = "Could not read VPN profiles"
        }
      }
    }
  }
}
