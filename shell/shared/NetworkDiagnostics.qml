pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Network diagnostics for Settings → Network → Diagnostics.
// Read-only iface rates, route/DNS, ss connections/listeners, calm ping;
// Wireshark escape (no in-pane packet decode).
Singleton {
  id: root

  property bool watching: false
  property bool ready: false
  property var interfaces: []
  property var connections: []
  property var listeners: []
  property string gateway: ""
  property string dnsLabel: "—"
  property string routeHint: "—"
  property string firewallLabel: "—"
  property string ssHint: ""
  property string pingTarget: ""
  property string pingResult: ""
  property bool pingBusy: false

  // Privacy → Diagnostics category (fail-open until Permissions.ready).
  readonly property bool allowed: {
    try {
      return Permissions.diagnosticsAllowed
    } catch (e) {
      return true
    }
  }
  readonly property string denyHint: "Blocked by Privacy · Diagnostics — allow in Settings → Privacy & security → Diagnostics"

  property bool captureAvailable: false
  property bool captureFlatpak: false
  property string capturePath: ""
  property string captureHint: "Checking…"

  // Soft ceiling for calm bars (bytes/s); raised if any iface exceeds it.
  property real rateScale: 1024 * 1024

  property var _prevRx: ({})
  property var _prevTx: ({})
  property var _prevMs: 0

  readonly property string captureStatusLabel: root.captureAvailable
      ? "Installed"
      : "Not installed"

  function _clearLive() {
    root.ready = false
    root.interfaces = []
    root.connections = []
    root.listeners = []
    root.gateway = ""
    root.dnsLabel = "—"
    root.routeHint = "—"
    root.firewallLabel = "—"
    root.ssHint = ""
    root.pingBusy = false
    root.pingResult = root.allowed ? "" : root.denyHint
  }

  function refresh() {
    if (!root.allowed) {
      _clearLive()
      return
    }
    snapProc.running = false
    snapProc.running = true
  }

  function refreshCapture() {
    // Wireshark presence detect stays read-only even when Diagnostics denied.
    captureProc.running = false
    captureProc.running = true
  }

  function ping(target) {
    const t = String(target || "").trim()
    if (!t.length || root.pingBusy)
      return
    if (!root.allowed) {
      root.pingResult = root.denyHint
      return
    }
    root.pingBusy = true
    root.pingTarget = t
    root.pingResult = "Pinging…"
    pingProc.command = [
      "bash",
      "-lc",
      "ping -c 1 -W 2 " + shellQuote(t)
          + " >/dev/null 2>&1 && echo OK || echo FAIL"
    ]
    pingProc.running = false
    pingProc.running = true
  }

  function pingGateway() {
    if (root.gateway.length)
      root.ping(root.gateway)
    else
      root.pingResult = "No default gateway"
  }

  function pingCloudflare() {
    root.ping("1.1.1.1")
  }

  function openCapture() {
    if (!root.captureAvailable)
      return
    if (root.captureFlatpak) {
      Quickshell.execDetached({
        command: ["flatpak", "run", "org.wireshark.Wireshark"]
      })
      return
    }
    const e = DesktopEntries.heuristicLookup("wireshark")
        || DesktopEntries.heuristicLookup("org.wireshark.Wireshark")
    if (e) {
      e.execute()
      return
    }
    if (root.capturePath.length) {
      Quickshell.execDetached({ command: [root.capturePath] })
      return
    }
    Quickshell.execDetached({
      command: ["bash", "-lc", "command -v wireshark >/dev/null && exec wireshark"]
    })
  }

  function openSoftware() {
    const q = "wireshark-qt"
    Packages.seedPackageSearch(q, "packages-search")
    ShellState.openSettings("packages-search", q)
  }

  function shellQuote(s) {
    return "'" + String(s).replace(/'/g, "'\\''") + "'"
  }

  function _fmtBytes(n) {
    const v = Number(n) || 0
    if (v < 1024)
      return Math.round(v) + " B"
    if (v < 1024 * 1024)
      return (v / 1024).toFixed(1) + " KiB"
    if (v < 1024 * 1024 * 1024)
      return (v / (1024 * 1024)).toFixed(1) + " MiB"
    return (v / (1024 * 1024 * 1024)).toFixed(2) + " GiB"
  }

  function _fmtRate(bps) {
    const v = Number(bps) || 0
    if (v < 0)
      return "—"
    if (v < 1024)
      return Math.round(v) + " B/s"
    if (v < 1024 * 1024)
      return (v / 1024).toFixed(1) + " KiB/s"
    return (v / (1024 * 1024)).toFixed(2) + " MiB/s"
  }

  function ifaceHint(row) {
    if (!row)
      return ""
    const parts = []
    parts.push("↓ " + root._fmtBytes(row.rx) + " · ↑ " + root._fmtBytes(row.tx))
    if (row.rxRate >= 0 && row.txRate >= 0)
      parts.push(root._fmtRate(row.rxRate) + " / " + root._fmtRate(row.txRate))
    return parts.join(" · ")
  }

  function rateFrac(bps) {
    const v = Number(bps)
    if (isNaN(v) || v < 0)
      return 0
    const scale = Math.max(1024, Number(root.rateScale) || 1024)
    return Math.max(0, Math.min(1, v / scale))
  }

  function connHint(row) {
    if (!row)
      return ""
    const bits = []
    if (row.local)
      bits.push(row.local)
    if (row.state)
      bits.push(row.state)
    return bits.join(" · ")
  }

  function listenHint(row) {
    if (!row)
      return ""
    if (row.process && String(row.process).length)
      return row.process
    return "Listening"
  }

  onWatchingChanged: {
    if (watching && root.allowed) {
      root.refresh()
      root.refreshCapture()
      poll.restart()
    } else {
      poll.stop()
      if (watching && !root.allowed)
        root._clearLive()
      if (watching)
        root.refreshCapture()
    }
  }

  onAllowedChanged: {
    if (!root.allowed) {
      poll.stop()
      root._clearLive()
    } else if (root.watching) {
      root.refresh()
      poll.restart()
    }
  }

  Timer {
    id: poll
    interval: 2000
    repeat: true
    running: false
    onTriggered: root.refresh()
  }

  Component.onCompleted: root.refreshCapture()

  Process {
    id: snapProc
    command: [
      "python3",
      "-c",
      "import json, re, shutil, subprocess\n"
          + "ifaces = []\n"
          + "try:\n"
          + "    with open('/proc/net/dev', encoding='utf-8') as f:\n"
          + "        lines = f.readlines()[2:]\n"
          + "    for line in lines:\n"
          + "        if ':' not in line: continue\n"
          + "        name, rest = line.split(':', 1)\n"
          + "        name = name.strip()\n"
          + "        if not name or name == 'lo': continue\n"
          + "        if name.startswith(('veth', 'docker', 'br-', 'virbr', 'vnet')): continue\n"
          + "        cols = rest.split()\n"
          + "        if len(cols) < 10: continue\n"
          + "        ifaces.append({'name': name, 'rx': int(cols[0]), 'tx': int(cols[8])})\n"
          + "except OSError:\n"
          + "    pass\n"
          + "gateway = ''\n"
          + "try:\n"
          + "    with open('/proc/net/route', encoding='utf-8') as f:\n"
          + "        next(f)\n"
          + "        for line in f:\n"
          + "            p = line.split()\n"
          + "            if len(p) < 3: continue\n"
          + "            if p[1] == '00000000':\n"
          + "                gw = int(p[2], 16)\n"
          + "                gateway = '%d.%d.%d.%d' % (gw & 0xff, (gw >> 8) & 0xff, (gw >> 16) & 0xff, (gw >> 24) & 0xff)\n"
          + "                break\n"
          + "except OSError:\n"
          + "    pass\n"
          + "dns = []\n"
          + "try:\n"
          + "    with open('/etc/resolv.conf', encoding='utf-8', errors='replace') as f:\n"
          + "        for line in f:\n"
          + "            s = line.strip()\n"
          + "            if s.startswith('nameserver'):\n"
          + "                parts = s.split()\n"
          + "                if len(parts) >= 2 and parts[1] not in dns:\n"
          + "                    dns.append(parts[1])\n"
          + "except OSError:\n"
          + "    pass\n"
          + "conns = []; listens = []; ss_hint = ''\n"
          + "if not shutil.which('ss'):\n"
          + "    ss_hint = 'ss not installed'\n"
          + "else:\n"
          + "    def parse_ss(args, established_only=False):\n"
          + "        r = subprocess.run(args, capture_output=True, text=True, timeout=4)\n"
          + "        rows = []\n"
          + "        netids = {'tcp','udp','tcp6','udp6','raw','raw6','u_str','u_dgr','u_seq','icmp6','v_str'}\n"
          + "        for line in (r.stdout or '').splitlines():\n"
          + "            line = line.strip()\n"
          + "            if not line or line.lower().startswith('netid'): continue\n"
          + "            parts = line.split()\n"
          + "            if len(parts) < 4: continue\n"
          + "            if parts[0].lower() in netids:\n"
          + "                if len(parts) < 6: continue\n"
          + "                state, local, peer = parts[1], parts[4], parts[5]\n"
          + "            else:\n"
          + "                if len(parts) < 5: continue\n"
          + "                state, local, peer = parts[0], parts[3], parts[4]\n"
          + "            st = state.upper()\n"
          + "            if established_only:\n"
          + "                if st not in ('ESTAB', 'ESTABLISHED'): continue\n"
          + "            else:\n"
          + "                if st != 'LISTEN': continue\n"
          + "            proc = ''\n"
          + "            m = re.search(r'users:\\(\\(\\\"([^\\\"]+)\\\"', line)\n"
          + "            if m: proc = m.group(1)\n"
          + "            rows.append({'local': local, 'peer': peer, 'state': state, 'process': proc})\n"
          + "        return rows\n"
          + "    try:\n"
          + "        conns = parse_ss(['ss', '-H', '-tun'], True)[:16]\n"
          + "        if not conns:\n"
          + "            conns = parse_ss(['ss', '-tun'], True)[:16]\n"
          + "        listens = parse_ss(['ss', '-H', '-tlnp'], False)[:16]\n"
          + "        if not listens:\n"
          + "            listens = parse_ss(['ss', '-tlnp'], False)[:16]\n"
          + "        if not listens:\n"
          + "            listens = parse_ss(['ss', '-tln'], False)[:16]\n"
          + "    except Exception as e:\n"
          + "        ss_hint = 'ss probe failed'\n"
          + "firewall = 'No host firewall tool found'\n"
          + "try:\n"
          + "    if shutil.which('firewall-cmd'):\n"
          + "        r = subprocess.run(['firewall-cmd', '--state'], capture_output=True, text=True, timeout=3)\n"
          + "        st = ((r.stdout or r.stderr or '').strip().splitlines() or ['unknown'])[0]\n"
          + "        firewall = 'firewalld · ' + st\n"
          + "    elif shutil.which('ufw'):\n"
          + "        r = subprocess.run(['ufw', 'status'], capture_output=True, text=True, timeout=3)\n"
          + "        st = ((r.stdout or '').strip().splitlines() or ['unknown'])[0]\n"
          + "        firewall = 'ufw · ' + st.replace('Status: ', '')\n"
          + "    elif shutil.which('nft'):\n"
          + "        r = subprocess.run(['nft', 'list', 'tables'], capture_output=True, text=True, timeout=3)\n"
          + "        tables = [ln for ln in (r.stdout or '').splitlines() if ln.strip()]\n"
          + "        if r.returncode != 0 and not tables:\n"
          + "            err = ((r.stderr or '').strip().splitlines() or [''])[0]\n"
          + "            firewall = 'nftables · ' + (err[:80] if err else 'unavailable')\n"
          + "        else:\n"
          + "            firewall = ('nftables · ' + str(len(tables)) + ' table' + ('s' if len(tables) != 1 else '')) if tables else 'nftables · no tables'\n"
          + "    elif shutil.which('iptables'):\n"
          + "        firewall = 'iptables present (legacy)'\n"
          + "except Exception:\n"
          + "    firewall = 'Firewall probe failed'\n"
          + "print(json.dumps({\n"
          + "    'interfaces': ifaces[:16], 'gateway': gateway, 'dns': dns[:4],\n"
          + "    'connections': conns, 'listeners': listens, 'ss_hint': ss_hint,\n"
          + "    'firewall': firewall,\n"
          + "}))\n"
    ]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const res = JSON.parse(text.trim() || "{}")
          const now = Date.now()
          const dt = root._prevMs > 0 ? Math.max(0.001, (now - root._prevMs) / 1000.0) : 0
          const list = Array.isArray(res.interfaces) ? res.interfaces : []
          const nextRx = {}
          const nextTx = {}
          const out = []
          let peak = 1024 * 1024
          for (let i = 0; i < list.length; i++) {
            const row = list[i]
            const name = String(row.name || "")
            const rx = Number(row.rx) || 0
            const tx = Number(row.tx) || 0
            nextRx[name] = rx
            nextTx[name] = tx
            let rxRate = -1
            let txRate = -1
            if (dt > 0 && root._prevRx[name] !== undefined) {
              rxRate = Math.max(0, (rx - root._prevRx[name]) / dt)
              txRate = Math.max(0, (tx - root._prevTx[name]) / dt)
              peak = Math.max(peak, rxRate, txRate)
            }
            out.push({
              name: name,
              rx: rx,
              tx: tx,
              rxRate: rxRate,
              txRate: txRate
            })
          }
          root._prevRx = nextRx
          root._prevTx = nextTx
          root._prevMs = now
          root.rateScale = peak
          root.interfaces = out
          root.gateway = String(res.gateway || "")
          const dns = Array.isArray(res.dns) ? res.dns : []
          root.dnsLabel = dns.length ? dns.join(" · ") : "—"
          root.routeHint = root.gateway.length
              ? ("via " + root.gateway)
              : "No default route"
          root.connections = Array.isArray(res.connections) ? res.connections : []
          root.listeners = Array.isArray(res.listeners) ? res.listeners : []
          root.ssHint = String(res.ss_hint || "")
          root.firewallLabel = String(res.firewall || "—")
          root.ready = true
        } catch (e) {
          /* keep last good sample */
        }
      }
    }
    stderr: StdioCollector {}
  }

  Process {
    id: pingProc
    command: ["true"]
    stdout: StdioCollector {
      onStreamFinished: {
        root.pingBusy = false
        const line = (text.trim().split("\n").pop() || "").trim()
        if (line === "OK")
          root.pingResult = "Reachable · " + root.pingTarget
        else
          root.pingResult = "No reply · " + root.pingTarget
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        if (root.pingBusy) {
          root.pingBusy = false
          root.pingResult = "Ping failed · " + root.pingTarget
        }
      }
    }
  }

  Process {
    id: captureProc
    command: [
      "python3",
      "-c",
      "import json, shutil, subprocess\n"
          + "path = shutil.which('wireshark') or ''\n"
          + "flatpak = False\n"
          + "if not path:\n"
          + "    try:\n"
          + "        out = subprocess.check_output(\n"
          + "            ['flatpak', 'list', '--app', '--columns=application'],\n"
          + "            stderr=subprocess.DEVNULL, text=True, timeout=4)\n"
          + "        flatpak = 'org.wireshark.Wireshark' in out\n"
          + "    except Exception:\n"
          + "        flatpak = False\n"
          + "ok = bool(path) or flatpak\n"
          + "hint = ('Wireshark · Flatpak' if flatpak else ('Wireshark · ' + path if path else 'Software → Repos · wireshark-qt'))\n"
          + "print(json.dumps({'available': ok, 'flatpak': flatpak, 'path': path or '', 'hint': hint}))\n"
    ]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const res = JSON.parse(text.trim() || "{}")
          root.captureAvailable = !!res.available
          root.captureFlatpak = !!res.flatpak
          root.capturePath = String(res.path || "")
          root.captureHint = String(res.hint || "")
        } catch (e) {
          root.captureAvailable = false
          root.captureFlatpak = false
          root.capturePath = ""
          root.captureHint = "Software → Repos · wireshark-qt"
        }
      }
    }
    stderr: StdioCollector {}
  }
}
