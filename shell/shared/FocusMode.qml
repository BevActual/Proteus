pragma Singleton

import Quickshell
import QtQuick

// Soft Focus Mode — timed quiet with allowlist / keyword filters (not a posture).
// Toast gating: Notifications.shouldToast → FocusMode.allows. Hard DND stays separate.
Singleton {
  id: root

  // off | 30m | 1h | 2h | indefinite
  property string mode: "off"
  property bool active: mode !== "off"
  property double endsAtMs: 0
  property int clock: 0
  // True when Focus was started by a schedule window (auto-stop when window ends).
  property bool scheduleOwned: false
  // Session recent notifier keys for CC quick-allow
  property var recentApps: []

  readonly property string label: {
    if (!root.active)
      return "Off"
    if (root.mode === "indefinite")
      return "Until turned off"
    return root.remainingLabel + " left"
  }

  readonly property string shortLabel: {
    if (!root.active)
      return "Off"
    if (root.mode === "indefinite")
      return "On"
    return root.remainingLabel
  }

  readonly property string remainingLabel: {
    void root.clock
    if (!root.active || root.mode === "indefinite" || root.endsAtMs <= 0)
      return ""
    const sec = Math.max(0, Math.ceil((root.endsAtMs - Date.now()) / 1000))
    const h = Math.floor(sec / 3600)
    const m = Math.floor((sec % 3600) / 60)
    if (h > 0)
      return h + "h " + m + "m"
    if (m > 0)
      return m + "m"
    return sec + "s"
  }

  readonly property var modes: [
    { id: "30m", secs: 30 * 60, title: "30 minutes" },
    { id: "1h", secs: 60 * 60, title: "1 hour" },
    { id: "2h", secs: 2 * 60 * 60, title: "2 hours" },
    { id: "indefinite", secs: 0, title: "Until turned off" }
  ]

  readonly property var menuOptions: {
    const rows = [{ id: "off", secs: -1, title: "Off" }]
    for (let i = 0; i < root.modes.length; i++)
      rows.push(root.modes[i])
    return rows
  }

  function defaultProfiles() {
    const flat = Config.focusAllowedAppsList()
    const crit = Config.focusBreakCritical !== false
    return [
      {
        id: "work",
        name: "Work",
        allowedApps: flat.slice(),
        breakCritical: crit,
        keywordAllow: [],
        keywordDeny: [],
        schedule: null
      },
      {
        id: "sleep",
        name: "Sleep",
        allowedApps: [],
        breakCritical: true,
        keywordAllow: [],
        keywordDeny: [],
        schedule: null
      },
      {
        id: "personal",
        name: "Personal",
        allowedApps: flat.slice(),
        breakCritical: crit,
        keywordAllow: [],
        keywordDeny: [],
        schedule: null
      }
    ]
  }

  function profiles() {
    const raw = Config.focusProfiles
    if (Array.isArray(raw) && raw.length)
      return raw
    return root.defaultProfiles()
  }

  function activeProfileId() {
    const id = String(Config.focusActiveProfileId || "work").trim()
    const list = root.profiles()
    for (let i = 0; i < list.length; i++) {
      if (list[i] && list[i].id === id)
        return id
    }
    return list.length ? String(list[0].id) : "work"
  }

  function activeProfile() {
    const id = root.activeProfileId()
    const list = root.profiles()
    for (let i = 0; i < list.length; i++) {
      if (list[i] && list[i].id === id)
        return list[i]
    }
    return list.length ? list[0] : null
  }

  function setActiveProfileId(id) {
    Config.focusActiveProfileId = String(id || "work")
    Config.flushSettings()
  }

  function saveProfiles(list) {
    Config.focusProfiles = Array.isArray(list) ? list : []
    const p = root.activeProfile()
    if (p) {
      Config.focusAllowedApps = Array.isArray(p.allowedApps) ? p.allowedApps.slice() : []
      Config.focusBreakCritical = p.breakCritical !== false
    }
    Config.flushSettings()
  }

  function ensureProfilesPersisted() {
    const raw = Config.focusProfiles
    if (Array.isArray(raw) && raw.length)
      return
    root.saveProfiles(root.defaultProfiles())
  }

  function updateActiveProfile(patch) {
    root.ensureProfilesPersisted()
    const list = root.profiles().slice()
    const id = root.activeProfileId()
    for (let i = 0; i < list.length; i++) {
      if (list[i] && list[i].id === id) {
        list[i] = Object.assign({}, list[i], patch || {})
        break
      }
    }
    root.saveProfiles(list)
  }

  function allowedAppsList() {
    const p = root.activeProfile()
    if (p && Array.isArray(p.allowedApps))
      return p.allowedApps
    return Config.focusAllowedAppsList()
  }

  function breakCritical() {
    const p = root.activeProfile()
    if (p && p.breakCritical !== undefined)
      return p.breakCritical !== false
    return Config.focusBreakCritical !== false
  }

  function normalizeAppKey(raw) {
    let s = String(raw || "").trim().toLowerCase()
    if (!s.length)
      return ""
    if (s.endsWith(".desktop"))
      s = s.slice(0, -8)
    const slash = s.lastIndexOf("/")
    if (slash >= 0)
      s = s.slice(slash + 1)
    return s
  }

  function appKeyFromNotification(n) {
    if (!n)
      return ""
    let key = ""
    try {
      if (n.desktopEntry)
        key = root.normalizeAppKey(n.desktopEntry)
    } catch (e) {
    }
    if (!key.length)
      key = root.normalizeAppKey(n.appName || "")
    return key
  }

  function rememberRecent(n) {
    const key = root.appKeyFromNotification(n)
    if (!key.length)
      return
    const name = String(n.appName || key)
    const next = [{ id: key, name: name }]
    const prev = root.recentApps || []
    for (let i = 0; i < prev.length && next.length < 12; i++) {
      if (prev[i] && prev[i].id !== key)
        next.push(prev[i])
    }
    root.recentApps = next
  }

  function isCritical(n) {
    if (!n)
      return false
    try {
      const u = n.urgency
      if (u === undefined || u === null)
        return false
      if (typeof u === "number")
        return u >= 2
      const s = String(u).toLowerCase()
      return s.indexOf("critical") >= 0 || s === "2"
    } catch (e) {
      return false
    }
  }

  function keywordHit(list, text) {
    if (!list || !list.length || !text.length)
      return false
    for (let i = 0; i < list.length; i++) {
      const k = String(list[i] || "").trim().toLowerCase()
      if (k.length && text.indexOf(k) >= 0)
        return true
    }
    return false
  }

  function allows(n) {
    if (!root.active)
      return true
    const p = root.activeProfile()
    if (root.breakCritical() && root.isCritical(n))
      return true

    const summary = String((n && n.summary) || "").toLowerCase()
    const body = String((n && n.body) || "").toLowerCase()
    const hay = (summary + " " + body).trim()

    const deny = (p && Array.isArray(p.keywordDeny)) ? p.keywordDeny : []
    if (root.keywordHit(deny, hay))
      return false

    const allowKw = (p && Array.isArray(p.keywordAllow)) ? p.keywordAllow : []
    if (root.keywordHit(allowKw, hay))
      return true

    const key = root.appKeyFromNotification(n)
    if (!key.length)
      return false
    const allowed = root.allowedAppsList()
    for (let i = 0; i < allowed.length; i++) {
      if (root.normalizeAppKey(allowed[i]) === key)
        return true
    }
    return false
  }

  function addAllowedApp(appId) {
    const key = root.normalizeAppKey(appId)
    if (!key.length)
      return
    const list = root.allowedAppsList().slice()
    for (let i = 0; i < list.length; i++) {
      if (root.normalizeAppKey(list[i]) === key)
        return
    }
    list.push(key)
    root.updateActiveProfile({ allowedApps: list })
  }

  function removeAllowedApp(appId) {
    const key = root.normalizeAppKey(appId)
    const list = root.allowedAppsList().slice()
    const next = []
    for (let i = 0; i < list.length; i++) {
      if (root.normalizeAppKey(list[i]) !== key)
        next.push(list[i])
    }
    root.updateActiveProfile({ allowedApps: next })
  }

  function setBreakCritical(on) {
    root.updateActiveProfile({ breakCritical: !!on })
  }

  function start(modeId) {
    let id = String(modeId || "indefinite")
    if (id === "off") {
      root.stop()
      return
    }
    let secs = 0
    let found = false
    for (let i = 0; i < root.modes.length; i++) {
      if (root.modes[i].id === id) {
        secs = root.modes[i].secs
        found = true
        break
      }
    }
    if (!found) {
      id = "indefinite"
      secs = 0
    }
    root.mode = id
    root.endsAtMs = secs > 0 ? (Date.now() + secs * 1000) : 0
    tick.restart()
  }

  function stop() {
    root.mode = "off"
    root.endsAtMs = 0
    root.scheduleOwned = false
    tick.stop()
  }

  function select(modeId) {
    const id = String(modeId || "off")
    root.scheduleOwned = false
    if (id === "off" || !id.length)
      root.stop()
    else
      root.start(id)
  }

  function toggle() {
    root.scheduleOwned = false
    if (root.active)
      root.stop()
    else
      root.start("indefinite")
  }

  // Pad / Beacon: off → 1h → indefinite → off
  function cycle() {
    root.scheduleOwned = false
    if (!root.active) {
      root.start("1h")
      return
    }
    if (root.mode === "1h") {
      root.start("indefinite")
      return
    }
    root.stop()
  }

  function _inScheduleWindow(sched, now) {
    if (!sched || typeof sched !== "object" || !sched.enabled)
      return false
    const days = Array.isArray(sched.days) ? sched.days : []
    const dow = now.getDay()
    if (days.length) {
      let ok = false
      for (let i = 0; i < days.length; i++) {
        if (Number(days[i]) === dow || String(days[i]) === String(dow)) {
          ok = true
          break
        }
      }
      if (!ok)
        return false
    }
    const parts = s => {
      const bits = String(s).split(":")
      const h = Math.max(0, Math.min(23, parseInt(bits[0], 10) || 0))
      const m = Math.max(0, Math.min(59, parseInt(bits[1], 10) || 0))
      return h * 60 + m
    }
    const cur = now.getHours() * 60 + now.getMinutes()
    const a = parts(sched.start || "09:00")
    const b = parts(sched.end || "17:00")
    if (a === b)
      return true
    if (a < b)
      return cur >= a && cur < b
    return cur >= a || cur < b
  }

  function checkSchedules() {
    if (root.active && !root.scheduleOwned)
      return
    const list = root.profiles()
    const now = new Date()
    let matchId = ""
    for (let i = 0; i < list.length; i++) {
      const p = list[i]
      if (!p || !p.schedule)
        continue
      if (root._inScheduleWindow(p.schedule, now)) {
        matchId = String(p.id)
        break
      }
    }
    if (matchId.length) {
      if (root.activeProfileId() !== matchId)
        root.setActiveProfileId(matchId)
      if (!root.active) {
        root.scheduleOwned = true
        root.start("indefinite")
      }
      return
    }
    if (root.active && root.scheduleOwned)
      root.stop()
  }

  Timer {
    id: tick
    interval: 1000
    repeat: true
    running: false
    onTriggered: {
      root.clock++
      if (root.mode !== "off" && root.mode !== "indefinite" && root.endsAtMs > 0
          && Date.now() >= root.endsAtMs) {
        root.stop()
      }
    }
  }

  Timer {
    interval: 30000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.checkSchedules()
  }

}
