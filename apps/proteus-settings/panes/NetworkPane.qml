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

  property bool tsAvailable: false
  property string tsState: ""
  property string tsHint: "Checking Tailscale…"
  property string tsIp: ""
  property int tsPeers: 0
  property bool tsBusy: false

  readonly property bool tsRunning: tsState === "Running"
  readonly property bool tsNeedsLogin: tsState === "NeedsLogin" || tsState === "NoState"
  readonly property string tsActionLabel: {
    if (!tsAvailable)
      return ""
    if (tsBusy)
      return "Working…"
    if (tsRunning)
      return "Disconnect"
    if (tsNeedsLogin)
      return "Log in"
    return "Connect"
  }

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
    kick(tsProc)
  }

  function runTailscaleAction() {
    if (!tsAvailable || tsBusy)
      return
    tsBusy = true
    if (tsRunning)
      Config.tailscaleDown()
    else
      Config.tailscaleUp()
    // Re-read status shortly after kick
    tsRefresh.restart()
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
    title: "Tailscale"

    SettingsFormRow {
      label: "Status"
      hint: root.tsHint
      showSeparator: true
      Text {
        visible: root.tsAvailable && root.tsRunning
        text: "Connected"
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: 12
      }
    }

    SettingsFormRow {
      visible: root.tsAvailable && (root.tsIp.length > 0 || root.tsPeers > 0)
      label: "This device"
      hint: root.tsIp.length ? root.tsIp : "—"
      showSeparator: true
      Text {
        visible: root.tsPeers > 0
        text: root.tsPeers + (root.tsPeers === 1 ? " peer" : " peers")
        color: Theme.textDim
        font.family: Theme.fontFamily
        font.pixelSize: 12
      }
    }

    SettingsFormRow {
      visible: root.tsAvailable
      label: root.tsActionLabel
      hint: root.tsNeedsLogin
          ? "Opens Tailscale login (browser or CLI)"
          : (root.tsRunning ? "tailscale down" : "tailscale up")
      showSeparator: true
      interactive: root.tsAvailable && !root.tsBusy && root.tsActionLabel.length > 0
      onActivated: root.runTailscaleAction()
      Text {
        text: "›"
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }
    }

    SettingsFormRow {
      label: root.tsAvailable ? "Open Tailscale status" : "Tailscale not installed"
      hint: root.tsAvailable
          ? "tailscale status in a terminal"
          : "Install tailscale · Headscale = set login-server via CLI"
      showSeparator: false
      interactive: root.tsAvailable
      onActivated: Config.openTailscaleStatus()
      Text {
        text: root.tsAvailable ? "›" : ""
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
    text: "Fact: nmcli · bluetoothctl · tailscale status · editors for NM/blueman. No pairing / WireGuard / Headscale admin UI."
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

  Timer {
    id: tsRefresh
    interval: 1200
    repeat: false
    onTriggered: {
      root.tsBusy = false
      root.kick(tsProc)
    }
  }

  Process {
    id: tsProc
    command: [
      "python3",
      "-c",
      "import json,shutil,subprocess\n"
          + "o={'available':False,'state':'','hint':'Tailscale not installed','ip':'','peers':0}\n"
          + "if not shutil.which('tailscale'):\n"
          + "  print(json.dumps(o)); raise SystemExit\n"
          + "o['available']=True\n"
          + "r=subprocess.run(['tailscale','status','--json'],capture_output=True,text=True)\n"
          + "if r.returncode!=0:\n"
          + "  err=(r.stderr or r.stdout or 'tailscale status failed').strip().splitlines()\n"
          + "  o['hint']=err[0] if err else 'tailscale status failed'; o['state']='Error'; print(json.dumps(o)); raise SystemExit\n"
          + "try: d=json.loads(r.stdout or '{}')\n"
          + "except Exception: o['hint']='Could not parse status'; o['state']='Error'; print(json.dumps(o)); raise SystemExit\n"
          + "st=d.get('BackendState') or ''\n"
          + "o['state']=st\n"
          + "self=d.get('Self') or {}\n"
          + "ips=self.get('TailscaleIPs') or []\n"
          + "o['ip']=(ips[0] if ips else '')\n"
          + "peers=d.get('Peer') or {}\n"
          + "o['peers']=len(peers) if isinstance(peers,dict) else 0\n"
          + "dns=(self.get('DNSName') or '').rstrip('.')\n"
          + "if st=='Running':\n"
          + "  bits=[dns] if dns else []; bits.append(o['ip'] or 'online')\n"
          + "  o['hint']=' · '.join([b for b in bits if b])\n"
          + "elif st=='NeedsLogin': o['hint']='Needs login'\n"
          + "elif st=='Stopped': o['hint']='Stopped'\n"
          + "else: o['hint']=st or 'Unknown'\n"
          + "print(json.dumps(o))"
    ]
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const o = JSON.parse(String(this.text || "").trim() || "{}")
          root.tsAvailable = !!o.available
          root.tsState = o.state || ""
          root.tsHint = o.hint || ""
          root.tsIp = o.ip || ""
          root.tsPeers = Number(o.peers) || 0
        } catch (e) {
          root.tsAvailable = false
          root.tsHint = "Could not read Tailscale status"
          root.tsState = ""
          root.tsIp = ""
          root.tsPeers = 0
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
