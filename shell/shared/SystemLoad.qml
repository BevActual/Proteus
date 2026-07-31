pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Read-only load snapshot for Settings → About (CPU · mem · uptime).
// Poll only while `watching` (About pane active).
Singleton {
  id: root

  property bool watching: false
  property real cpuPercent: -1
  property real memUsedGiB: -1
  property real memTotalGiB: -1
  property string uptimeLabel: "—"
  property string cpuModel: ""
  property bool ready: false

  property var _prevIdle: -1
  property var _prevTotal: -1

  readonly property string summaryLabel: {
    const parts = []
    if (root.cpuPercent >= 0)
      parts.push("CPU " + Math.round(root.cpuPercent) + "%")
    if (root.memUsedGiB >= 0 && root.memTotalGiB > 0)
      parts.push("Mem " + root.memUsedGiB.toFixed(1) + " / " + root.memTotalGiB.toFixed(1) + " GiB")
    if (root.uptimeLabel.length && root.uptimeLabel !== "—")
      parts.push("Up " + root.uptimeLabel)
    return parts.length ? parts.join(" · ") : "—"
  }

  function refresh() {
    loadProc.running = false
    loadProc.running = true
  }

  onWatchingChanged: {
    if (watching) {
      root.refresh()
      poll.restart()
    } else {
      poll.stop()
    }
  }

  Timer {
    id: poll
    interval: 2500
    repeat: true
    running: false
    onTriggered: root.refresh()
  }

  Process {
    id: loadProc
    command: [
      "python3",
      "-c",
      "import json\n"
          + "cpu_model = ''\n"
          + "try:\n"
          + "    with open('/proc/cpuinfo', encoding='utf-8', errors='replace') as f:\n"
          + "        for line in f:\n"
          + "            if line.startswith('model name') or line.startswith('Hardware'):\n"
          + "                cpu_model = line.split(':', 1)[1].strip()\n"
          + "                break\n"
          + "except OSError:\n"
          + "    pass\n"
          + "idle = total = 0\n"
          + "try:\n"
          + "    with open('/proc/stat', encoding='utf-8') as f:\n"
          + "        parts = f.readline().split()\n"
          + "        nums = [int(x) for x in parts[1:]]\n"
          + "        total = sum(nums)\n"
          + "        idle = nums[3] + (nums[4] if len(nums) > 4 else 0)\n"
          + "except Exception:\n"
          + "    pass\n"
          + "mem_total = mem_avail = 0\n"
          + "try:\n"
          + "    with open('/proc/meminfo', encoding='utf-8') as f:\n"
          + "        for line in f:\n"
          + "            if line.startswith('MemTotal:'):\n"
          + "                mem_total = int(line.split()[1])\n"
          + "            elif line.startswith('MemAvailable:'):\n"
          + "                mem_avail = int(line.split()[1])\n"
          + "except Exception:\n"
          + "    pass\n"
          + "uptime_s = 0.0\n"
          + "try:\n"
          + "    with open('/proc/uptime', encoding='utf-8') as f:\n"
          + "        uptime_s = float(f.read().split()[0])\n"
          + "except Exception:\n"
          + "    pass\n"
          + "print(json.dumps({\n"
          + "    'cpu_model': cpu_model,\n"
          + "    'idle': idle, 'total': total,\n"
          + "    'mem_total_kb': mem_total, 'mem_avail_kb': mem_avail,\n"
          + "    'uptime_s': uptime_s,\n"
          + "}))\n"
    ]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const res = JSON.parse(text.trim() || "{}")
          root.cpuModel = String(res.cpu_model || "")
          const idle = Number(res.idle)
          const total = Number(res.total)
          if (root._prevIdle >= 0 && root._prevTotal >= 0 && total > root._prevTotal) {
            const dIdle = idle - root._prevIdle
            const dTotal = total - root._prevTotal
            const busy = dTotal > 0 ? (1 - (dIdle / dTotal)) : 0
            root.cpuPercent = Math.max(0, Math.min(100, busy * 100))
          }
          root._prevIdle = idle
          root._prevTotal = total

          const mt = Number(res.mem_total_kb) || 0
          const ma = Number(res.mem_avail_kb) || 0
          if (mt > 0) {
            root.memTotalGiB = mt / (1024 * 1024)
            root.memUsedGiB = Math.max(0, (mt - ma) / (1024 * 1024))
          }

          const up = Number(res.uptime_s) || 0
          root.uptimeLabel = root._fmtUptime(up)
          root.ready = true
        } catch (e) {
          /* keep last good sample */
        }
      }
    }
    stderr: StdioCollector {}
  }

  function _fmtUptime(secs) {
    const s = Math.floor(secs)
    if (s < 60)
      return s + "s"
    const m = Math.floor(s / 60)
    if (m < 60)
      return m + "m"
    const h = Math.floor(m / 60)
    const rm = m % 60
    if (h < 48)
      return rm ? (h + "h " + rm + "m") : (h + "h")
    const d = Math.floor(h / 24)
    const rh = h % 24
    return rh ? (d + "d " + rh + "h") : (d + "d")
  }
}
