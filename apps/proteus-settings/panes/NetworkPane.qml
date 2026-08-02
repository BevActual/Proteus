import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../shared"
import "../kit"

// Network category hub → leaf loaders (Sound/Desktop pattern).
// Page ids: network · network-machine · network-devices · network-wifi ·
// network-bluetooth · network-localsend · network-tailscale · network-vpn ·
// network-headscale · network-diagnostics.
// OpenVPN .ovpn import + optional user/pass + cert path attach thin In.
// Headscale admin thin In (remote API · users · policy text). PKI / PKCS#11 / preauth / server install Out.
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
  property string wifiPasswordSsid: ""
  property string wifiPasswordDraft: ""

  property bool btAvailable: false
  property bool btPowered: false
  property string btAdapter: ""
  property string btHint: "Checking Bluetooth…"
  property var btDevices: []
  property bool btBusy: false
  property string btError: ""
  property bool btScanning: false

  property var vpnConnections: []
  property string vpnStatus: "Checking VPN…"
  property bool vpnBusy: false
  property string vpnError: ""
  property string vpnImportHint: ""
  // wireguard | openvpn — last import kind (error copy + optional creds)
  property string vpnImportKind: ""
  property string vpnOvpnPendingName: ""
  property string vpnOvpnPendingUser: ""
  property string vpnOvpnPendingPass: ""
  property string vpnOvpnPendingCa: ""
  property string vpnOvpnPendingCert: ""
  property string vpnOvpnPendingKey: ""
  property string vpnOvpnPendingTlsAuth: ""

  property bool tsAvailable: false
  property string tsState: ""
  property string tsHint: "Checking Tailscale…"
  property string tsIp: ""
  property int tsPeers: 0
  property var tsPeerList: []
  property string tsExitNode: ""
  property string tsExitNodeLabel: ""
  property bool tsBusy: false
  property string tsCopied: ""
  property string tsError: ""
  property string tsLoginDraft: ""

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

  readonly property bool tsLoginDirty: {
    const a = String(Config.tailscaleLoginServer || "").trim()
    const b = String(tsLoginDraft || "").trim()
    return a !== b
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
      key: "network-diagnostics",
      label: "Diagnostics"
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
    },
    {
      key: "network-headscale",
      label: "Headscale"
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

  function shellQuote(s) {
    return "'" + String(s).replace(/'/g, "'\\''") + "'"
  }

  function wifiNeedsPassword(sec) {
    const s = String(sec || "").trim().toUpperCase()
    if (!s.length || s === "--")
      return false
    if (s === "OPEN" || s.indexOf("OPEN") === 0)
      return false
    return true
  }

  function refresh() {
    wifiError = ""
    hostnameError = ""
    btError = ""
    vpnError = ""
    tsError = ""
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
    tsError = ""
    if (tsRunning) {
      Config.tailscaleDown()
      tsRefresh.restart()
      return
    }
    const login = String(Config.tailscaleLoginServer || "").trim()
    if (login.length)
      Config.tailscaleUpWithLoginServer(login)
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

  function copyPeerIp(ip) {
    const t = String(ip || "").trim()
    if (!t.length)
      return
    Config.copyToClipboard(t)
    tsCopied = "Copied"
    tsCopiedClear.restart()
  }

  function setExitNode(idOrIp) {
    if (!tsAvailable || tsBusy)
      return
    tsBusy = true
    tsError = ""
    const v = String(idOrIp || "").trim()
    tsExitProc.command = [
      "bash",
      "-lc",
      v.length
          ? ("tailscale set --exit-node=" + shellQuote(v))
          : "tailscale set --exit-node="
    ]
    tsExitProc.running = false
    tsExitProc.running = true
  }

  function applyLoginServer() {
    const next = String(tsLoginDraft || "").trim()
    Config.tailscaleLoginServer = next
    Config.flushSettings()
    if (!tsAvailable || tsBusy)
      return
    tsBusy = true
    tsError = ""
    if (next.length)
      Config.tailscaleUpWithLoginServer(next)
    else
      Config.tailscaleUp()
    tsRefresh.restart()
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

  function beginWifiConnect(ssid, security) {
    const name = String(ssid || "").trim()
    if (!name.length || wifiBusy)
      return
    if (wifiNeedsPassword(security)) {
      wifiPasswordSsid = name
      wifiPasswordDraft = ""
      wifiError = ""
      return
    }
    cancelWifiPassword()
    runWifiConnect(name, "")
  }

  function submitWifiPassword() {
    const name = String(wifiPasswordSsid || "").trim()
    if (!name.length || wifiBusy)
      return
    runWifiConnect(name, wifiPasswordDraft)
  }

  function cancelWifiPassword() {
    wifiPasswordSsid = ""
    wifiPasswordDraft = ""
  }

  function runWifiConnect(ssid, password) {
    const name = String(ssid || "").trim()
    if (!name.length || wifiBusy)
      return
    wifiBusy = true
    wifiError = ""
    const pass = String(password || "")
    wifiConnectProc.command = [
      "python3",
      "-c",
      "import subprocess,sys\n"
          + "ssid=sys.argv[1]; pw=sys.argv[2] if len(sys.argv)>2 else ''\n"
          + "cmd=['nmcli','device','wifi','connect',ssid]\n"
          + "if pw: cmd += ['password',pw]\n"
          + "r=subprocess.run(cmd,capture_output=True,text=True)\n"
          + "sys.stderr.write(r.stderr or r.stdout or '')\n"
          + "raise SystemExit(r.returncode)\n",
      name,
      pass
    ]
    wifiConnectProc.running = false
    wifiConnectProc.running = true
  }

  function rescanWifi() {
    if (wifiBusy || !wifiDevice.length)
      return
    wifiBusy = true
    wifiError = ""
    kick(wifiProc)
  }

  function disconnectWifi() {
    if (!wifiDevice.length || wifiBusy)
      return
    wifiBusy = true
    wifiError = ""
    cancelWifiPassword()
    wifiDisconnectProc.command = ["nmcli", "device", "disconnect", wifiDevice]
    wifiDisconnectProc.running = false
    wifiDisconnectProc.running = true
  }

  function setBluetoothPower(on) {
    if (!btAvailable || btBusy)
      return
    btBusy = true
    btError = ""
    btPowerProc.command = ["bluetoothctl", "power", on ? "on" : "off"]
    btPowerProc.running = false
    btPowerProc.running = true
  }

  function scanBluetooth() {
    if (!btAvailable || btBusy || btScanning)
      return
    btScanning = true
    btBusy = true
    btError = ""
    btScanProc.running = false
    btScanProc.running = true
  }

  function refreshBluetoothDevices() {
    kick(btDevicesProc)
  }

  function pairBluetooth(mac) {
    const m = String(mac || "").trim()
    if (!m.length || btBusy)
      return
    btBusy = true
    btError = ""
    btPairProc.command = [
      "bash",
      "-lc",
      "bluetoothctl pair " + shellQuote(m)
          + " && bluetoothctl trust " + shellQuote(m)
          + " && bluetoothctl connect " + shellQuote(m)
    ]
    btPairProc.running = false
    btPairProc.running = true
  }

  function disconnectBluetooth(mac) {
    const m = String(mac || "").trim()
    if (!m.length || btBusy)
      return
    btBusy = true
    btError = ""
    btDiscProc.command = ["bluetoothctl", "disconnect", m]
    btDiscProc.running = false
    btDiscProc.running = true
  }

  function removeBluetooth(mac) {
    const m = String(mac || "").trim()
    if (!m.length || btBusy)
      return
    btBusy = true
    btError = ""
    btRemoveProc.command = ["bluetoothctl", "remove", m]
    btRemoveProc.running = false
    btRemoveProc.running = true
  }

  function vpnToggle(name, active) {
    const n = String(name || "").trim()
    if (!n.length || vpnBusy)
      return
    vpnBusy = true
    vpnError = ""
    vpnToggleProc.command = ["nmcli", "connection", active ? "down" : "up", n]
    vpnToggleProc.running = false
    vpnToggleProc.running = true
  }

  function importWireGuard(path) {
    const p = String(path || "").trim()
    if (!p.length || vpnBusy)
      return
    vpnBusy = true
    vpnError = ""
    vpnImportKind = "wireguard"
    vpnOvpnPendingName = ""
    vpnOvpnPendingUser = ""
    vpnOvpnPendingPass = ""
    vpnOvpnPendingCa = ""
    vpnOvpnPendingCert = ""
    vpnOvpnPendingKey = ""
    vpnOvpnPendingTlsAuth = ""
    vpnImportHint = "Importing…"
    vpnImportProc.command = [
      "nmcli",
      "connection",
      "import",
      "type",
      "wireguard",
      "file",
      p
    ]
    vpnImportProc.running = false
    vpnImportProc.running = true
  }

  function importOpenVpn(path, user, pass, ca, cert, key, tlsAuth) {
    const p = String(path || "").trim()
    if (!p.length || vpnBusy)
      return
    vpnBusy = true
    vpnError = ""
    vpnImportKind = "openvpn"
    vpnOvpnPendingUser = String(user || "").trim()
    vpnOvpnPendingPass = String(pass || "")
    vpnOvpnPendingCa = String(ca || "").trim()
    vpnOvpnPendingCert = String(cert || "").trim()
    vpnOvpnPendingKey = String(key || "").trim()
    vpnOvpnPendingTlsAuth = String(tlsAuth || "").trim()
    const base = p.split("/").pop() || ""
    vpnOvpnPendingName = base.replace(/\.ovpn$/i, "").replace(/\.conf$/i, "")
    vpnImportHint = "Importing OpenVPN…"
    vpnImportProc.command = [
      "nmcli",
      "connection",
      "import",
      "type",
      "openvpn",
      "file",
      p
    ]
    vpnImportProc.running = false
    vpnImportProc.running = true
  }

  function _ovpnHasPendingCerts() {
    return !!(vpnOvpnPendingCa.length || vpnOvpnPendingCert.length
              || vpnOvpnPendingKey.length || vpnOvpnPendingTlsAuth.length)
  }

  function _startOvpnCertApply(name) {
    root.vpnImportHint = "Attaching certs…"
    root.vpnOvpnPendingName = name
    vpnOvpnCertProc.command = [
      "python3", "-c",
      "import subprocess,sys\n"
      + "name,ca,cert,key,ta=sys.argv[1:6]\n"
      + "bits=[]\n"
      + "if ca: bits.append(f'ca={ca}')\n"
      + "if cert: bits.append(f'cert={cert}')\n"
      + "if key: bits.append(f'key={key}')\n"
      + "if ta: bits.append(f'tls-auth={ta}')\n"
      + "if not bits:\n"
      + "  print('skip'); raise SystemExit(0)\n"
      + "data=','.join(bits)\n"
      + "r=subprocess.run(['nmcli','connection','modify',name,'+vpn.data',data],capture_output=True,text=True)\n"
      + "if r.returncode!=0:\n"
      + "  sys.stderr.write((r.stderr or r.stdout or 'vpn.data failed').strip()); sys.exit(r.returncode or 1)\n"
      + "print('ok')\n",
      name,
      root.vpnOvpnPendingCa,
      root.vpnOvpnPendingCert,
      root.vpnOvpnPendingKey,
      root.vpnOvpnPendingTlsAuth
    ]
    vpnOvpnCertProc.running = false
    vpnOvpnCertProc.running = true
  }

  function applyOpenVpnCerts(name, ca, cert, key, tlsAuth) {
    const n = String(name || "").trim()
    if (!n.length || vpnBusy)
      return
    vpnBusy = true
    vpnError = ""
    vpnImportKind = "openvpn"
    vpnOvpnPendingCa = String(ca || "").trim()
    vpnOvpnPendingCert = String(cert || "").trim()
    vpnOvpnPendingKey = String(key || "").trim()
    vpnOvpnPendingTlsAuth = String(tlsAuth || "").trim()
    if (!_ovpnHasPendingCerts()) {
      vpnBusy = false
      vpnError = "Pick at least one of CA / cert / key / tls-auth"
      return
    }
    _startOvpnCertApply(n)
  }

  onActiveChanged: {
    if (active) {
      if (!String(tsLoginDraft || "").length)
        tsLoginDraft = Config.tailscaleLoginServer
      refresh()
    } else {
      cancelWifiPassword()
    }
  }

  Component.onCompleted: {
    tsLoginDraft = Config.tailscaleLoginServer
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
    want: root.page === "network-diagnostics"
    source: "NetworkDiagnosticsLeaf.qml"
    onLoaded: {
      item.host = root
      item.active = Qt.binding(() => root.page === "network-diagnostics")
    }
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

  StickyPaneLoader {
    want: root.page === "network-headscale"
    source: "NetworkHeadscaleLeaf.qml"
    onLoaded: item.host = root
  }

  Timer {
    id: tsRefresh
    interval: 1800
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
    interval: 1500
    repeat: false
    onTriggered: {
      root.wifiBusy = false
      root.kick(devProc)
      root.kick(wifiProc)
    }
  }

  Timer {
    id: btRefresh
    interval: 800
    repeat: false
    onTriggered: {
      root.btBusy = false
      root.btScanning = false
      root.kick(btProc)
      root.kick(btDevicesProc)
    }
  }

  Timer {
    id: vpnRefresh
    interval: 1000
    repeat: false
    onTriggered: {
      root.vpnBusy = false
      root.kick(vpnProc)
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
    id: wifiConnectProc
    command: ["true"]
    running: false
    stderr: StdioCollector {
      id: wifiConnectErr
    }
    onExited: (exitCode, exitStatus) => {
      root.wifiBusy = false
      if (exitCode === 0) {
        root.wifiError = ""
        root.cancelWifiPassword()
        root.wifiRefresh.restart()
        return
      }
      const e = String(wifiConnectErr.text || "").trim().split("\n").pop() || ""
      root.wifiError = e.length ? e : "Connect failed"
      root.wifiRefresh.restart()
    }
  }

  Process {
    id: wifiDisconnectProc
    command: ["true"]
    running: false
    stderr: StdioCollector {
      id: wifiDisconnectErr
    }
    onExited: (exitCode, exitStatus) => {
      root.wifiBusy = false
      if (exitCode !== 0) {
        const e = String(wifiDisconnectErr.text || "").trim().split("\n").pop() || ""
        root.wifiError = e.length ? e : "Disconnect failed"
      } else {
        root.wifiError = ""
      }
      root.wifiRefresh.restart()
    }
  }

  Process {
    id: devProc
    command: [
      "python3",
      "-c",
      "import json,re,shutil,subprocess\n"
          + "o={'devices':[],'status':'nmcli not found'}\n"
          + "if not shutil.which('nmcli'):\n"
          + "  print(json.dumps(o)); raise SystemExit\n"
          + "r=subprocess.run(['nmcli','-t','-f','DEVICE,TYPE,STATE,CONNECTION','dev','status'],capture_output=True,text=True)\n"
          + "devs=[]\n"
          + "for line in (r.stdout or '').splitlines():\n"
          + "  if not line.strip(): continue\n"
          + "  p=line.split(':')\n"
          + "  name=p[0] if p else '?'\n"
          + "  typ=p[1] if len(p)>1 else ''\n"
          + "  state=p[2] if len(p)>2 else ''\n"
          + "  conn=p[3] if len(p)>3 else ''\n"
          + "  ipv4=''\n"
          + "  if name and name not in ('lo',):\n"
          + "    s=subprocess.run(['nmcli','-t','-f','IP4.ADDRESS','device','show',name],capture_output=True,text=True)\n"
          + "    for ln in (s.stdout or '').splitlines():\n"
          + "      if not ln.strip(): continue\n"
          + "      val=ln.split(':',1)[-1].strip()\n"
          + "      if '/' in val: val=val.split('/',1)[0]\n"
          + "      if re.match(r'^\\d+\\.\\d+\\.\\d+\\.\\d+$', val):\n"
          + "        ipv4=val; break\n"
          + "  devs.append({'device':name,'type':typ,'state':state,'connection':conn,'ipv4':ipv4})\n"
          + "o['devices']=devs\n"
          + "o['status']=('' if devs else 'No NetworkManager devices found.')\n"
          + "print(json.dumps(o))"
    ]
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const o = JSON.parse(String(this.text || "").trim() || "{}")
          const list = o.devices || []
          root.devices = list
          root.status = o.status || ""
          let wifiDev = ""
          for (let i = 0; i < list.length; i++) {
            const d = list[i]
            if (String(d.type).toLowerCase() === "wifi") {
              wifiDev = d.device
              if (root.isUp(d))
                break
            }
          }
          root.wifiDevice = wifiDev
        } catch (e) {
          root.devices = []
          root.status = "Could not read devices"
        }
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
          if (!wifiConnectProc.running && !wifiDisconnectProc.running)
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
          if (root.btAvailable)
            root.kick(btDevicesProc)
        } catch (e) {
          root.btAvailable = false
          root.btHint = "Could not read Bluetooth status"
        }
      }
    }
  }

  Process {
    id: btDevicesProc
    command: [
      "python3",
      "-c",
      "import json,re,shutil,subprocess\n"
          + "o={'devices':[]}\n"
          + "if not shutil.which('bluetoothctl'):\n"
          + "  print(json.dumps(o)); raise SystemExit\n"
          + "def run(args):\n"
          + "  return subprocess.run(args,capture_output=True,text=True,timeout=12)\n"
          + "def macs_from(text):\n"
          + "  out=set()\n"
          + "  for line in (text or '').splitlines():\n"
          + "    m=re.search(r'([0-9A-Fa-f]{2}(?::[0-9A-Fa-f]{2}){5})', line)\n"
          + "    if m: out.add(m.group(1).upper())\n"
          + "  return out\n"
          + "devs=run(['bluetoothctl','devices'])\n"
          + "paired=macs_from(run(['bluetoothctl','devices','Paired']).stdout)\n"
          + "if not paired:\n"
          + "  paired=macs_from(run(['bluetoothctl','paired-devices']).stdout)\n"
          + "connected=macs_from(run(['bluetoothctl','devices','Connected']).stdout)\n"
          + "out=[]\n"
          + "for line in (devs.stdout or '').splitlines():\n"
          + "  m=re.match(r'Device\\s+([0-9A-Fa-f:]{17})\\s+(.*)$', line)\n"
          + "  if not m: continue\n"
          + "  mac=m.group(1); name=(m.group(2) or '').strip() or mac\n"
          + "  mu=mac.upper()\n"
          + "  conn=mu in connected\n"
          + "  if not conn:\n"
          + "    info=run(['bluetoothctl','info',mac])\n"
          + "    blob=(info.stdout or '').lower()\n"
          + "    conn='connected: yes' in blob\n"
          + "    if mu not in paired and 'paired: yes' in blob: paired.add(mu)\n"
          + "  out.append({'mac':mac,'name':name,'paired':mu in paired,'connected':conn})\n"
          + "out.sort(key=lambda d:(not d['connected'], not d['paired'], d['name'].lower()))\n"
          + "o['devices']=out[:32]\n"
          + "print(json.dumps(o))"
    ]
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const o = JSON.parse(String(this.text || "").trim() || "{}")
          root.btDevices = o.devices || []
        } catch (e) {
          root.btDevices = []
        }
      }
    }
  }

  Process {
    id: btPowerProc
    command: ["true"]
    running: false
    stderr: StdioCollector {
      id: btPowerErr
    }
    onExited: (exitCode, exitStatus) => {
      if (exitCode !== 0) {
        const e = String(btPowerErr.text || "").trim().split("\n").pop() || ""
        root.btError = e.length ? e : "Power change failed"
      } else {
        root.btError = ""
      }
      root.btRefresh.restart()
    }
  }

  Process {
    id: btScanProc
    command: ["bluetoothctl", "--timeout", "8", "scan", "on"]
    running: false
    stderr: StdioCollector {
      id: btScanErr
    }
    onExited: (exitCode, exitStatus) => {
      if (exitCode !== 0) {
        const e = String(btScanErr.text || "").trim().split("\n").pop() || ""
        if (e.length)
          root.btError = e
      }
      root.btRefresh.restart()
    }
  }

  Process {
    id: btPairProc
    command: ["true"]
    running: false
    stderr: StdioCollector {
      id: btPairErr
    }
    onExited: (exitCode, exitStatus) => {
      if (exitCode !== 0) {
        const e = String(btPairErr.text || "").trim().split("\n").pop() || ""
        root.btError = e.length ? e : "Pair/connect failed"
      } else {
        root.btError = ""
      }
      root.btRefresh.restart()
    }
  }

  Process {
    id: btDiscProc
    command: ["true"]
    running: false
    stderr: StdioCollector {
      id: btDiscErr
    }
    onExited: (exitCode, exitStatus) => {
      if (exitCode !== 0) {
        const e = String(btDiscErr.text || "").trim().split("\n").pop() || ""
        root.btError = e.length ? e : "Disconnect failed"
      } else {
        root.btError = ""
      }
      root.btRefresh.restart()
    }
  }

  Process {
    id: btRemoveProc
    command: ["true"]
    running: false
    stderr: StdioCollector {
      id: btRemoveErr
    }
    onExited: (exitCode, exitStatus) => {
      if (exitCode !== 0) {
        const e = String(btRemoveErr.text || "").trim().split("\n").pop() || ""
        root.btError = e.length ? e : "Remove failed"
      } else {
        root.btError = ""
      }
      root.btRefresh.restart()
    }
  }

  Process {
    id: tsProc
    command: [
      "python3",
      "-c",
      "import json,shutil,subprocess\n"
          + "o={'available':False,'state':'','hint':'Tailscale not installed','ip':'','peers':0,'peer_list':[],'exit_node':'','exit_label':''}\n"
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
          + "plist=[]\n"
          + "if isinstance(peers,dict):\n"
          + "  for _k,p in peers.items():\n"
          + "    if not isinstance(p,dict): continue\n"
          + "    pips=p.get('TailscaleIPs') or []\n"
          + "    host=(p.get('HostName') or '').strip()\n"
          + "    dns=(p.get('DNSName') or '').rstrip('.')\n"
          + "    label=host or dns or (pips[0] if pips else 'peer')\n"
          + "    online=bool(p.get('Online'))\n"
          + "    exit_ok=bool(p.get('ExitNodeOption'))\n"
          + "    is_exit=bool(p.get('ExitNode'))\n"
          + "    pid=str(p.get('ID') or _k or '')\n"
          + "    ip=(pips[0] if pips else '')\n"
          + "    plist.append({'id':pid,'label':label,'ip':ip,'online':online,'exitOption':exit_ok,'exitNode':is_exit})\n"
          + "plist.sort(key=lambda x:(not x['online'], x['label'].lower()))\n"
          + "o['peer_list']=plist[:24]\n"
          + "o['peers']=len(plist)\n"
          + "exit_ip=''; exit_lab=''\n"
          + "for p in plist:\n"
          + "  if p.get('exitNode'):\n"
          + "    exit_ip=p.get('ip') or p.get('id') or ''; exit_lab=p.get('label') or exit_ip; break\n"
          + "ens=d.get('ExitNodeStatus') or {}\n"
          + "if isinstance(ens,dict) and ens.get('ID') and not exit_ip:\n"
          + "  exit_ip=str(ens.get('TailscaleIPs',[ens.get('ID')])[0] if ens.get('TailscaleIPs') else ens.get('ID') or '')\n"
          + "  exit_lab=str(ens.get('Hostname') or ens.get('DNSName') or exit_ip)\n"
          + "o['exit_node']=exit_ip; o['exit_label']=exit_lab\n"
          + "dns=(self.get('DNSName') or '').rstrip('.')\n"
          + "if st=='Running':\n"
          + "  bits=[dns] if dns else []; bits.append(o['ip'] or 'online')\n"
          + "  if exit_lab: bits.append('exit '+exit_lab)\n"
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
          root.tsPeerList = o.peer_list || []
          root.tsExitNode = o.exit_node || ""
          root.tsExitNodeLabel = o.exit_label || ""
        } catch (e) {
          root.tsAvailable = false
          root.tsHint = "Could not read Tailscale status"
          root.tsState = ""
          root.tsIp = ""
          root.tsPeers = 0
          root.tsPeerList = []
          root.tsExitNode = ""
          root.tsExitNodeLabel = ""
        }
      }
    }
  }

  Process {
    id: tsExitProc
    command: ["true"]
    running: false
    stderr: StdioCollector {
      id: tsExitErr
    }
    onExited: (exitCode, exitStatus) => {
      root.tsBusy = false
      if (exitCode !== 0) {
        const e = String(tsExitErr.text || "").trim().split("\n").pop() || ""
        root.tsError = e.length ? e : "Exit node change failed"
      } else {
        root.tsError = ""
      }
      root.kick(tsProc)
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
          + "status=('' if out else 'No VPN profiles yet — import WireGuard / OpenVPN or use NetworkManager')\n"
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

  Process {
    id: vpnToggleProc
    command: ["true"]
    running: false
    stderr: StdioCollector {
      id: vpnToggleErr
    }
    onExited: (exitCode, exitStatus) => {
      root.vpnBusy = false
      if (exitCode !== 0) {
        const e = String(vpnToggleErr.text || "").trim().split("\n").pop() || ""
        root.vpnError = e.length ? e : "VPN toggle failed"
      } else {
        root.vpnError = ""
      }
      root.vpnRefresh.restart()
    }
  }

  Process {
    id: vpnImportProc
    command: ["true"]
    running: false
    stdout: StdioCollector {
      id: vpnImportOut
    }
    stderr: StdioCollector {
      id: vpnImportErr
    }
    onExited: (exitCode, exitStatus) => {
      if (exitCode !== 0) {
        root.vpnBusy = false
        const e = String(vpnImportErr.text || "").trim().split("\n").pop() || ""
        const kind = root.vpnImportKind === "openvpn" ? "OpenVPN" : "WireGuard"
        root.vpnError = e.length ? e : (kind + " import failed")
        root.vpnImportHint = ""
        root.vpnOvpnPendingPass = ""
        root.vpnRefresh.restart()
        return
      }
      // Prefer nmcli "Connection 'name' …" from stdout; else basename.
      let name = root.vpnOvpnPendingName
      const out = String(vpnImportOut.text || "")
      const m = out.match(/Connection\s+'([^']+)'/i) || out.match(/Connection\s+"([^"]+)"/i)
      if (m && m[1])
        name = m[1]
      if (root.vpnImportKind === "openvpn" && root.vpnOvpnPendingUser.length && name.length) {
        root.vpnImportHint = "Setting credentials…"
        root.vpnOvpnPendingName = name
        vpnOvpnCredProc.command = [
          "python3", "-c",
          "import subprocess,sys\n"
          + "name=sys.argv[1]; user=sys.argv[2]; pw=sys.argv[3]\n"
          + "r1=subprocess.run(['nmcli','connection','modify',name,'vpn.user-name',user],capture_output=True,text=True)\n"
          + "if r1.returncode!=0:\n"
          + "  sys.stderr.write((r1.stderr or r1.stdout or 'user-name failed').strip()); sys.exit(r1.returncode or 1)\n"
          + "if pw:\n"
          + "  r2=subprocess.run(['nmcli','connection','modify',name,'vpn.secrets',f'password={pw}'],capture_output=True,text=True)\n"
          + "  if r2.returncode!=0:\n"
          + "    sys.stderr.write((r2.stderr or r2.stdout or 'password failed').strip()); sys.exit(r2.returncode or 1)\n"
          + "print('ok')\n",
          name,
          root.vpnOvpnPendingUser,
          root.vpnOvpnPendingPass
        ]
        vpnOvpnCredProc.running = false
        vpnOvpnCredProc.running = true
        return
      }
      if (root.vpnImportKind === "openvpn" && root._ovpnHasPendingCerts() && name.length) {
        root._startOvpnCertApply(name)
        return
      }
      root.vpnBusy = false
      root.vpnError = ""
      root.vpnImportHint = "Imported"
      root.vpnOvpnPendingPass = ""
      vpnImportFlash.restart()
      root.vpnRefresh.restart()
    }
  }

  Process {
    id: vpnOvpnCredProc
    command: ["true"]
    running: false
    stderr: StdioCollector {
      id: vpnOvpnCredErr
    }
    onExited: (exitCode, exitStatus) => {
      root.vpnOvpnPendingPass = ""
      if (exitCode !== 0) {
        root.vpnBusy = false
        const e = String(vpnOvpnCredErr.text || "").trim().split("\n").pop() || ""
        root.vpnError = e.length
            ? ("Imported, but credentials failed: " + e)
            : "Imported, but credentials failed — set them in NetworkManager"
        root.vpnImportHint = "Imported"
        vpnImportFlash.restart()
        root.vpnRefresh.restart()
        return
      }
      if (root._ovpnHasPendingCerts() && root.vpnOvpnPendingName.length) {
        root._startOvpnCertApply(root.vpnOvpnPendingName)
        return
      }
      root.vpnBusy = false
      root.vpnError = ""
      root.vpnImportHint = "Imported · credentials set"
      vpnImportFlash.restart()
      root.vpnRefresh.restart()
    }
  }

  Process {
    id: vpnOvpnCertProc
    command: ["true"]
    running: false
    stderr: StdioCollector {
      id: vpnOvpnCertErr
    }
    onExited: (exitCode, exitStatus) => {
      root.vpnBusy = false
      root.vpnOvpnPendingCa = ""
      root.vpnOvpnPendingCert = ""
      root.vpnOvpnPendingKey = ""
      root.vpnOvpnPendingTlsAuth = ""
      if (exitCode !== 0) {
        const e = String(vpnOvpnCertErr.text || "").trim().split("\n").pop() || ""
        root.vpnError = e.length
            ? ("Imported, but cert attach failed: " + e)
            : "Imported, but cert attach failed — set paths in NetworkManager"
        root.vpnImportHint = "Imported"
      } else {
        root.vpnError = ""
        root.vpnImportHint = "Imported · certs attached"
      }
      vpnImportFlash.restart()
      root.vpnRefresh.restart()
    }
  }

  Timer {
    id: vpnImportFlash
    interval: 2500
    onTriggered: root.vpnImportHint = ""
  }
}
