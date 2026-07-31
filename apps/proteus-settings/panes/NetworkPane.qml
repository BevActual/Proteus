import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../shared"
import "../kit"

// Network category hub → leaf loaders (Sound/Desktop pattern).
// Page ids: network · network-machine · network-devices · network-wifi ·
// network-bluetooth · network-localsend · network-tailscale · network-vpn.
// Pairing / password Wi‑Fi wizard / Headscale admin stay Out (SETTINGS-IA §2).
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: Theme.spaceMd

  property string page: "network"
  signal requestGo(string id)

  readonly property bool active: page === "network" || page.startsWith("network-")

  property var devices: []
  property string status: "Checking network…"

  property string hostname: ""
  property string hostnameDraft: ""
  property string hostnameError: ""
  property bool hostnameBusy: false

  property var wifiNetworks: []
  property string wifiStatus: "Checking Wi‑Fi…"
  property string wifiDevice: ""
  property bool wifiBusy: false
  property string wifiError: ""

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
  property string tsCopied: ""

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

  readonly property bool hostnameDirty: {
    const a = String(hostname || "").trim()
    const b = String(hostnameDraft || "").trim()
    return b.length > 0 && a !== b
  }

  readonly property var sections: [
    {
      key: "network-machine",
      label: "This machine"
    },
    {
      key: "network-devices",
      label: "Devices"
    },
    {
      key: "network-wifi",
      label: "Wi‑Fi"
    },
    {
      key: "network-bluetooth",
      label: "Bluetooth"
    },
    {
      key: "network-localsend",
      label: "LocalSend"
    },
    {
      key: "network-tailscale",
      label: "Tailscale"
    },
    {
      key: "network-vpn",
      label: "VPN"
    }
  ]

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
    wifiError = ""
    hostnameError = ""
    kick(hostProc)
    kick(devProc)
    kick(wifiProc)
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
    tsRefresh.restart()
  }

  function copyTailscaleIp() {
    if (!tsIp.length)
      return
    Config.copyToClipboard(tsIp)
    tsCopied = "Copied"
    tsCopiedClear.restart()
  }

  function applyHostname() {
    const n = String(hostnameDraft || "").trim()
    if (!n.length || !hostnameDirty || hostnameBusy)
      return
    hostnameBusy = true
    hostnameError = ""
    hostSetProc.command = ["hostnamectl", "set-hostname", n]
    hostSetProc.running = false
    hostSetProc.running = true
  }

  function connectWifi(ssid) {
    const name = String(ssid || "").trim()
    if (!name.length || wifiBusy)
      return
    wifiBusy = true
    wifiError = ""
    Config.wifiConnect(name)
    wifiRefresh.restart()
  }

  function disconnectWifi() {
    if (!wifiDevice.length || wifiBusy)
      return
    wifiBusy = true
    wifiError = ""
    Config.wifiDisconnect(wifiDevice)
    wifiRefresh.restart()
  }

  onActiveChanged: {
    if (active)
      refresh()
  }

  Component.onCompleted: {
    if (active)
      refresh()
  }

  SettingsHubList {
    visible: root.page === "network"
    items: root.sections
    onActivated: key => root.requestGo(key)
  }

  StickyPaneLoader {
    want: root.page === "network-machine"
    source: "NetworkMachineLeaf.qml"
    onLoaded: item.host = root
  }

  StickyPaneLoader {
    want: root.page === "network-devices"
    source: "NetworkDevicesLeaf.qml"
    onLoaded: item.host = root
  }

  StickyPaneLoader {
    want: root.page === "network-wifi"
    source: "NetworkWifiLeaf.qml"
    onLoaded: item.host = root
  }

  StickyPaneLoader {
    want: root.page === "network-bluetooth"
    source: "NetworkBluetoothLeaf.qml"
    onLoaded: item.host = root
  }

  StickyPaneLoader {
    want: root.page === "network-localsend"
    source: "NetworkLocalSendLeaf.qml"
    onLoaded: {
      item.host = root
      LocalSend.refresh()
    }
  }

  StickyPaneLoader {
    want: root.page === "network-tailscale"
    source: "NetworkTailscaleLeaf.qml"
    onLoaded: item.host = root
  }

  StickyPaneLoader {
    want: root.page === "network-vpn"
    source: "NetworkVpnLeaf.qml"
    onLoaded: item.host = root
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

  Timer {
    id: tsCopiedClear
    interval: 1500
    repeat: false
    onTriggered: root.tsCopied = ""
  }

  Timer {
    id: wifiRefresh
    interval: 2000
    repeat: false
    onTriggered: {
      root.wifiBusy = false
      root.kick(devProc)
      root.kick(wifiProc)
    }
  }

  Process {
    id: hostProc
    command: [
      "bash",
      "-lc",
      "hostnamectl --static 2>/dev/null || hostnamectl hostname 2>/dev/null || hostname"
    ]
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        const name = String(this.text || "").trim().split("\n")[0]
        root.hostname = name
        if (!root.hostnameDirty)
          root.hostnameDraft = name
      }
    }
  }

  Process {
    id: hostSetProc
    command: ["true"]
    running: false
    stderr: StdioCollector {
      id: hostSetErr
    }
    onExited: (exitCode, exitStatus) => {
      root.hostnameBusy = false
      if (exitCode === 0) {
        root.hostnameError = ""
        root.kick(hostProc)
        return
      }
      const e = String(hostSetErr.text || "").trim().split("\n")[0]
      root.hostnameError = e.length ? e : "Change refused (needs authorization)"
      root.kick(hostProc)
    }
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
        let wifiDev = ""
        for (let i = 0; i < root.devices.length; i++) {
          const d = root.devices[i]
          if (String(d.type).toLowerCase() === "wifi") {
            wifiDev = d.device
            if (root.isUp(d))
              break
          }
        }
        root.wifiDevice = wifiDev
      }
    }
  }

  Process {
    id: wifiProc
    command: [
      "python3",
      "-c",
      "import json,shutil,subprocess\n"
          + "o={'networks':[],'status':'nmcli not found','device':''}\n"
          + "if not shutil.which('nmcli'):\n"
          + "  print(json.dumps(o)); raise SystemExit\n"
          + "devs=subprocess.run(['nmcli','-t','-f','DEVICE,TYPE,STATE','dev','status'],capture_output=True,text=True)\n"
          + "wifi_dev=''\n"
          + "for line in (devs.stdout or '').splitlines():\n"
          + "  p=line.split(':')\n"
          + "  if len(p)>=2 and p[1]=='wifi':\n"
          + "    wifi_dev=p[0]\n"
          + "    if len(p)>2 and p[2]=='connected': break\n"
          + "o['device']=wifi_dev\n"
          + "if not wifi_dev:\n"
          + "  o['status']='No Wi‑Fi device'; print(json.dumps(o)); raise SystemExit\n"
          + "subprocess.run(['nmcli','device','wifi','rescan'],capture_output=True,text=True)\n"
          + "r=subprocess.run(['nmcli','-t','-f','IN-USE,SSID,SIGNAL,SECURITY','device','wifi','list'],capture_output=True,text=True)\n"
          + "best={}\n"
          + "for line in (r.stdout or '').splitlines():\n"
          + "  if not line.strip(): continue\n"
          + "  p=line.split(':')\n"
          + "  inuse=(p[0]=='*') if p else False\n"
          + "  ssid=p[1] if len(p)>1 else ''\n"
          + "  sig=p[2] if len(p)>2 else ''\n"
          + "  sec=p[3] if len(p)>3 else ''\n"
          + "  if not ssid: continue\n"
          + "  try: strength=int(sig)\n"
          + "  except: strength=0\n"
          + "  cur=best.get(ssid)\n"
          + "  if cur is None or inuse or strength>(cur.get('strength') or 0):\n"
          + "    best[ssid]={'ssid':ssid,'signal':str(strength),'security':sec,'active':inuse,'strength':strength}\n"
          + "nets=list(best.values())\n"
          + "nets.sort(key=lambda x:(not x['active'], -x['strength'], x['ssid']))\n"
          + "for n in nets: n.pop('strength',None)\n"
          + "o['networks']=nets[:24]\n"
          + "o['status']=('' if nets else 'No networks found — try Rescan')\n"
          + "print(json.dumps(o))"
    ]
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const o = JSON.parse(String(this.text || "").trim() || "{}")
          root.wifiNetworks = o.networks || []
          root.wifiStatus = o.status || ""
          if (o.device)
            root.wifiDevice = o.device
          root.wifiBusy = false
        } catch (e) {
          root.wifiNetworks = []
          root.wifiStatus = "Could not scan Wi‑Fi"
          root.wifiBusy = false
        }
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
