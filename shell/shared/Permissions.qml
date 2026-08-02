pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// App permissions store + Flatpak + portal sync + capture enforce.
// Fact: ~/.config/proteus/permissions.json · shell/scripts/proteus-permissions.py
// store-set-* syncs portal PermissionStore and enforces active captures.
Singleton {
  id: root

  readonly property var categoryIds: [
    "microphone", "camera", "location", "notifications", "screen", "diagnostics"
  ]

  readonly property var categoryMeta: [
    {
      id: "microphone",
      label: "Microphone",
      hint: "App access to capture audio",
      page: "privacy-microphone"
    },
    {
      id: "camera",
      label: "Camera",
      hint: "App access to capture video",
      page: "privacy-camera"
    },
    {
      id: "location",
      label: "Location",
      hint: "Precise place from Date, time & weather — not IP-inferred",
      page: "privacy-location"
    },
    {
      id: "notifications",
      label: "Notifications",
      hint: "Toast / portal notification grants",
      page: "privacy-notifications"
    },
    {
      id: "screen",
      label: "Screen recording",
      hint: "Portal / capture grants",
      page: "privacy-screen"
    },
    {
      id: "diagnostics",
      label: "Diagnostics",
      hint: "What leaves the machine",
      page: "privacy-diagnostics"
    }
  ]

  property bool ready: false
  property string error: ""
  property var categories: ({
    "microphone": "allow",
    "camera": "allow",
    "location": "allow",
    "notifications": "allow",
    "screen": "allow",
    "diagnostics": "allow"
  })
  property var apps: ({})
  property int rev: 0

  property var activityApps: []
  property bool activityLoading: false

  property var flatpakApps: []
  property bool flatpakAvailable: false
  property string flatpakHint: ""
  property bool flatpakLoading: false

  // Ephemeral Allow-once for this session (not persisted). Key: "appId\tcat".
  property var sessionAllow: ({})
  property int sessionRev: 0

  readonly property string script: Config.scriptsDir + "/proteus-permissions.py"
  readonly property string storePath: Quickshell.env("HOME") + "/.config/proteus/permissions.json"

  readonly property bool diagnosticsAllowed: categoryState("diagnostics") === "allow"

  function normalizeAppId(id) {
    let s = String(id || "").trim()
    if (s.endsWith(".desktop"))
      s = s.slice(0, -8)
    return s
  }

  function sessionKey(appId, cat) {
    return normalizeAppId(appId) + "\t" + String(cat || "")
  }

  function grantSession(appId, cat) {
    const k = sessionKey(appId, cat)
    if (!k.length || k.charAt(0) === "\t")
      return
    const next = Object.assign({}, root.sessionAllow)
    next[k] = true
    root.sessionAllow = next
    root.sessionRev++
  }

  function clearSessionGrant(appId, cat) {
    const k = sessionKey(appId, cat)
    if (!root.sessionAllow[k])
      return
    const next = Object.assign({}, root.sessionAllow)
    delete next[k]
    root.sessionAllow = next
    root.sessionRev++
  }

  function categoryState(cat) {
    const c = String(cat || "")
    const v = root.categories[c]
    return (v === "deny") ? "deny" : "allow"
  }

  function appGrant(appId, cat) {
    const aid = normalizeAppId(appId)
    const c = String(cat || "")
    const row = root.apps[aid]
    if (row && row[c])
      return String(row[c])
    return categoryState(c)
  }

  // True when store says ask and this session has not Allow-once'd.
  function isAsk(appId, cat) {
    if (!root.ready)
      return false
    const _s = root.sessionRev
    if (root.sessionAllow[sessionKey(appId, cat)])
      return false
    return appGrant(appId, cat) === "ask"
  }

  // Adaptive enforcement: allow or session once-grant. Fail-open until ready.
  function granted(appId, cat) {
    if (!root.ready)
      return true
    const _s = root.sessionRev
    if (root.sessionAllow[sessionKey(appId, cat)])
      return true
    return appGrant(appId, cat) === "allow"
  }

  function categoryLabel(cat) {
    for (let i = 0; i < categoryMeta.length; i++) {
      if (categoryMeta[i].id === cat)
        return categoryMeta[i].label
    }
    return cat
  }

  function appsForCategory(cat) {
    const c = String(cat || "")
    const out = []
    const seen = {}
    const act = root.activityApps || []

    function activityHit(aid) {
      for (let j = 0; j < act.length; j++) {
        if (String(act[j].kind) === c && normalizeAppId(act[j].id) === aid)
          return act[j]
      }
      return null
    }

    const keys = Object.keys(root.apps || {})
    for (let i = 0; i < keys.length; i++) {
      const aid = keys[i]
      const row = root.apps[aid] || {}
      const hasOverride = !!row[c]
      const hit = activityHit(aid)
      if (!hasOverride && !hit)
        continue
      seen[aid] = true
      out.push({
        id: aid,
        label: hit ? String(hit.label || aid) : aid,
        grant: appGrant(aid, c),
        active: !!hit,
        source: "store"
      })
    }

    for (let k = 0; k < act.length; k++) {
      const a = act[k]
      if (String(a.kind) !== c)
        continue
      const desk = normalizeAppId(a.id)
      const aid = desk || ("bin:" + String(a.binary || a.label || "unknown"))
      if (seen[aid] || (desk && seen[desk])) {
        for (let m = 0; m < out.length; m++) {
          if (out[m].id === aid || out[m].id === desk) {
            out[m].active = true
            out[m].label = String(a.label || out[m].label)
          }
        }
        continue
      }
      seen[aid] = true
      out.push({
        id: desk || aid,
        label: String(a.label || aid),
        grant: desk ? appGrant(desk, c) : categoryState(c),
        active: true,
        source: "activity"
      })
    }

    out.sort((a, b) => {
      if (a.active !== b.active)
        return a.active ? -1 : 1
      return String(a.label).localeCompare(String(b.label))
    })
    return out
  }

  function refresh() {
    loadProc.running = false
    loadProc.running = true
  }

  function refreshActivity() {
    activityLoading = true
    activityProc.running = false
    activityProc.running = true
  }

  function refreshFlatpak() {
    flatpakLoading = true
    flatpakProc.running = false
    flatpakProc.running = true
  }

  function setCategory(cat, state) {
    const c = String(cat || "")
    const st = String(state || "").toLowerCase()
    if (categoryIds.indexOf(c) < 0)
      return
    if (st !== "allow" && st !== "deny")
      return
    setCatProc.category = c
    setCatProc.state = st
    setCatProc.running = false
    setCatProc.running = true
  }

  function setAppGrant(appId, cat, state) {
    const aid = normalizeAppId(appId)
    const c = String(cat || "")
    const st = String(state || "").toLowerCase()
    if (!aid.length || categoryIds.indexOf(c) < 0)
      return
    if (st !== "allow" && st !== "ask" && st !== "deny")
      return
    // Flatpak refs look like org.foo.Bar — use flatpak-set when listed
    let isFlatpak = false
    const fps = root.flatpakApps || []
    for (let i = 0; i < fps.length; i++) {
      if (String(fps[i].id) === aid) {
        isFlatpak = true
        break
      }
    }
    if (isFlatpak) {
      setFlatpakProc.ref = aid
      setFlatpakProc.category = c
      setFlatpakProc.state = st
      setFlatpakProc.running = false
      setFlatpakProc.running = true
      return
    }
    setAppProc.app = aid
    setAppProc.category = c
    setAppProc.state = st
    setAppProc.running = false
    setAppProc.running = true
  }

  function applyCategorySideEffects(cat, state) {
    // Deny forces mute/DND; Allow does not auto-restore (honest).
    if (state !== "deny")
      return
    if (cat === "location") {
      try {
        Weather.setEnabled(false)
      } catch (e) {
      }
    } else if (cat === "notifications") {
      try {
        Notifications.setDnd(true)
      } catch (e) {
      }
    }
  }

  function ingestStore(data) {
    if (!data || !data.ok && data.version === undefined && !data.categories)
      return
    const cats = data.categories || {}
    const next = {}
    for (let i = 0; i < categoryIds.length; i++) {
      const id = categoryIds[i]
      next[id] = (String(cats[id] || "allow").toLowerCase() === "deny") ? "deny" : "allow"
    }
    root.categories = next
    root.apps = data.apps && typeof data.apps === "object" ? data.apps : ({})
    root.ready = true
    root.error = ""
    root.rev++
  }

  Process {
    id: loadProc
    command: ["python3", root.script, "store-get"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const data = JSON.parse(String(text).trim() || "{}")
          if (data.ok === false) {
            root.error = String(data.error || "Could not load permissions")
            root.ready = true
            return
          }
          root.ingestStore(data)
        } catch (e) {
          root.error = "Could not parse permissions"
          root.ready = true
        }
      }
    }
  }

  Process {
    id: setCatProc
    property string category: ""
    property string state: ""
    command: ["python3", root.script, "store-set-category", category, state]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const data = JSON.parse(String(text).trim() || "{}")
          if (!data.ok) {
            root.error = String(data.error || "Could not set category")
            return
          }
          root.applyCategorySideEffects(setCatProc.category, setCatProc.state)
        } catch (e) {
          root.error = "Could not set category"
        }
        root.refresh()
      }
    }
  }

  Process {
    id: setAppProc
    property string app: ""
    property string category: ""
    property string state: ""
    command: ["python3", root.script, "store-set-app", app, category, state]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const data = JSON.parse(String(text).trim() || "{}")
          if (!data.ok)
            root.error = String(data.error || "Could not set app grant")
          else
            root.error = ""
        } catch (e) {
          root.error = "Could not set app grant"
        }
        root.refresh()
      }
    }
  }

  Process {
    id: activityProc
    command: ["python3", root.script, "activity"]
    stdout: StdioCollector {
      onStreamFinished: {
        root.activityLoading = false
        try {
          const data = JSON.parse(String(text).trim() || "{}")
          root.activityApps = data.apps || []
          root.rev++
        } catch (e) {
        }
      }
    }
  }

  Process {
    id: flatpakProc
    command: ["python3", root.script, "flatpak-list"]
    stdout: StdioCollector {
      onStreamFinished: {
        root.flatpakLoading = false
        try {
          const data = JSON.parse(String(text).trim() || "{}")
          root.flatpakAvailable = !!data.available
          root.flatpakApps = data.apps || []
          root.flatpakHint = String(data.hint || data.error || "")
          root.rev++
        } catch (e) {
        }
      }
    }
  }

  Process {
    id: setFlatpakProc
    property string ref: ""
    property string category: ""
    property string state: ""
    command: ["python3", root.script, "flatpak-set", ref, category, state]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const data = JSON.parse(String(text).trim() || "{}")
          if (!data.ok)
            root.error = String(data.error || "Flatpak override failed")
          else
            root.error = String(data.hint || "")
        } catch (e) {
          root.error = "Flatpak override failed"
        }
        root.refresh()
        root.refreshFlatpak()
      }
    }
  }

  Component.onCompleted: {
    root.refresh()
    root.refreshActivity()
  }
}
