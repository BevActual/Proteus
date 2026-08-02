pragma Singleton
import Quickshell
import QtQuick

// Shared Apps-mode index: Settings panes + allowlisted actions (+ scoring).
// Beacon and console Search both consume this — one allowlist table.
QtObject {
  id: root

  readonly property var actionCatalog: [
    {
      id: "lock",
      name: "Lock screen",
      subtitle: "Action · Config.session lock",
      icon: "system-lock-screen",
      keywords: "lock screen sleep",
      destructive: false
    },
    {
      id: "logout",
      name: "Log out",
      subtitle: "Action · end Hyprland session",
      icon: "system-log-out",
      keywords: "logout log out exit session",
      destructive: false
    },
    {
      id: "enter-console",
      name: "Enter Console",
      subtitle: "Action · proteus-posture console",
      icon: "input-gaming",
      keywords: "console game mode couch tv posture hard switch",
      destructive: false
    },
    {
      id: "enter-host",
      name: "Enter Host",
      subtitle: "Action · proteus-posture host",
      icon: "computer",
      keywords: "host ops server lean posture hard switch",
      destructive: false
    },
    {
      id: "enter-desktop",
      name: "Return to Desktop",
      subtitle: "Action · proteus-posture desktop",
      icon: "user-desktop",
      keywords: "desktop desk posture hard switch exit console host",
      destructive: false
    },
    {
      id: "settings",
      name: "Open Settings",
      subtitle: "Action · proteus-settings",
      icon: "proteus-settings",
      keywords: "settings preferences system",
      destructive: false
    },
    {
      id: "control-center",
      name: "Open Control Center",
      subtitle: "Action · notifications + quick settings",
      icon: "preferences-system-notifications",
      keywords: "control center notifications dnd",
      destructive: false
    },
    {
      id: "dnd-toggle",
      name: "Toggle Do Not Disturb",
      subtitle: "Action · hard quiet (ignores Focus filters)",
      icon: "notifications-disabled",
      keywords: "dnd do not disturb quiet mute notifications hard",
      destructive: false
    },
    {
      id: "focus-cycle",
      name: "Focus",
      subtitle: "Action · cycle Focus (1h · until off · off)",
      icon: "preferences-desktop-notification-bell",
      keywords: "focus mode quiet allowlist filter notifications work sleep",
      destructive: false
    },
    {
      id: "keep-awake-cycle",
      name: "Keep Awake",
      subtitle: "Action · cycle duration (or toggle off at end)",
      icon: "preferences-system-power-management",
      keywords: "keep awake caffeine amphetamine inhibit idle sleep prevent",
      destructive: false
    },
    {
      id: "keep-awake-toggle",
      name: "Toggle Keep Awake",
      subtitle: "Action · until turned off / off",
      icon: "preferences-system-power-management",
      keywords: "keep awake toggle indefinite caffeine",
      destructive: false
    },
    {
      id: "localsend-open",
      name: "Open LocalSend",
      subtitle: "Action · share files on the LAN",
      icon: "folder-publicshare",
      keywords: "localsend airdrop share files nearby lan send",
      destructive: false
    },
    {
      id: "calendar-glance",
      name: "Today’s calendar",
      subtitle: "Action · open calendar glance",
      icon: "x-office-calendar",
      keywords: "calendar today date events agenda glance",
      destructive: false
    },
    {
      id: "weather-glance",
      name: "Weather glance",
      subtitle: "Action · open weather popover",
      icon: "weather-few-clouds",
      keywords: "weather forecast temperature conditions glance",
      destructive: false
    },
    {
      id: "open-calendar-app",
      name: "Open Calendar app",
      subtitle: "Action · system Calendar or Date & time Settings",
      icon: "x-office-calendar",
      keywords: "calendar app gnome-calendar events open",
      destructive: false
    },
    {
      id: "open-weather-app",
      name: "Open Weather app",
      subtitle: "Action · system Weather or Date & time Settings",
      icon: "weather-few-clouds",
      keywords: "weather app gnome-weather forecast open",
      destructive: false
    },
    {
      id: "screenshot-region",
      name: "Screenshot region",
      subtitle: "Action · proteus-screenshot region",
      icon: "applets-screenshooter",
      keywords: "screenshot capture region select area snip",
      destructive: false
    },
    {
      id: "screenshot-screen",
      name: "Screenshot screen",
      subtitle: "Action · proteus-screenshot screen",
      icon: "applets-screenshooter",
      keywords: "screenshot capture full screen display",
      destructive: false
    },
    {
      id: "settings-wifi",
      name: "Wi‑Fi settings",
      subtitle: "Action · Settings → Network → Wi‑Fi",
      icon: "network-wireless",
      keywords: "wifi wi-fi wireless network ssid settings",
      destructive: false
    },
    {
      id: "settings-displays",
      name: "Displays settings",
      subtitle: "Action · Settings → Displays",
      icon: "preferences-desktop-display",
      keywords: "displays monitors resolution scale settings",
      destructive: false
    },
    {
      id: "settings-mixer",
      name: "Sound Mixer",
      subtitle: "Action · Settings → Sound → Mixer",
      icon: "audio-volume-high",
      keywords: "sound mixer matrix audio volume settings",
      destructive: false
    },
    {
      id: "settings-privacy",
      name: "Privacy & security",
      subtitle: "Action · Settings → Privacy & security",
      icon: "preferences-system-privacy",
      keywords: "privacy security weather mute clipboard localsend lock settings",
      destructive: false
    },
    {
      id: "settings-updates",
      name: "Software updates",
      subtitle: "Action · Settings → Software → Updates",
      icon: "system-software-update",
      keywords: "updates packages pacman software settings",
      destructive: false
    },
    {
      id: "clear-notifications",
      name: "Clear notifications",
      subtitle: "Action · dismiss all",
      icon: "edit-clear-all",
      keywords: "clear notifications dismiss",
      destructive: false
    },
    {
      id: "reboot",
      name: "Reboot",
      subtitle: "Action · systemctl reboot",
      icon: "system-reboot",
      keywords: "reboot restart",
      destructive: true
    },
    {
      id: "shutdown",
      name: "Shut down",
      subtitle: "Action · systemctl poweroff",
      icon: "system-shutdown",
      keywords: "shutdown power off halt",
      destructive: true
    }
  ]

  function fuzzySubsequence(hay, q) {
    let hi = 0
    for (let qi = 0; qi < q.length; qi++) {
      const ch = q.charAt(qi)
      hi = hay.indexOf(ch, hi)
      if (hi < 0)
        return false
      hi++
    }
    return true
  }

  function scoreQuery(hay, q) {
    if (!q.length)
      return 0
    if (hay === q)
      return 1000
    if (hay.startsWith(q))
      return 850
    const words = hay.split(/[\s\-_/]+/)
    for (let i = 0; i < words.length; i++) {
      if (words[i].startsWith(q))
        return 700
    }
    const idx = hay.indexOf(q)
    if (idx >= 0)
      return 500 - Math.min(idx, 80)
    if (root.fuzzySubsequence(hay, q))
      return 180 + Math.max(0, 40 - (hay.length - q.length))
    return -1
  }

  function runPosture(target) {
    const proot = String(Quickshell.env("PROTEUS_ROOT") || "/mnt/proteus")
    const t = String(target || "desktop")
    // Prefer live tree (dogfood) over stale /usr/local.
    Quickshell.execDetached({
      command: [
        "bash", "-lc",
        "P=" + proot + "/vm/guest/proteus-posture; "
            + "if [[ -x \"$P\" ]]; then setsid \"$P\" " + t + " >/dev/null 2>&1 & "
            + "elif command -v proteus-posture >/dev/null 2>&1; then "
            + "setsid proteus-posture " + t + " >/dev/null 2>&1 & "
            + "fi"
      ]
    })
  }

  function runAction(actionId) {
    const id = String(actionId || "")
    let known = false
    for (let i = 0; i < root.actionCatalog.length; i++) {
      if (root.actionCatalog[i].id === id) {
        known = true
        break
      }
    }
    if (!known)
      return
    if (id === "lock")
      Config.session("lock")
    else if (id === "logout")
      Config.session("logout")
    else if (id === "reboot")
      Config.session("reboot")
    else if (id === "shutdown")
      Config.session("shutdown")
    else if (id === "enter-console")
      root.runPosture("console")
    else if (id === "enter-host")
      root.runPosture("host")
    else if (id === "enter-desktop")
      root.runPosture("desktop")
    else if (id === "settings")
      ShellState.openSettings()
    else if (id === "control-center")
      ShellState.openControlCenter()
    else if (id === "dnd-toggle")
      Notifications.toggleDnd()
    else if (id === "focus-cycle")
      FocusMode.cycle()
    else if (id === "keep-awake-cycle")
      KeepAwake.cycle()
    else if (id === "keep-awake-toggle")
      KeepAwake.toggle()
    else if (id === "localsend-open") {
      if (LocalSend.available)
        LocalSend.open()
      else
        ShellState.openSettings("network-localsend")
    } else if (id === "settings-wifi")
      ShellState.openSettings("network-wifi")
    else if (id === "settings-displays")
      ShellState.openSettings("displays")
    else if (id === "settings-mixer")
      ShellState.openSettings("sound-matrix")
    else if (id === "settings-privacy")
      ShellState.openSettings("privacy")
    else if (id === "settings-updates")
      ShellState.openSettings("packages-updates")
    else if (id === "clear-notifications")
      Notifications.clearAll()
    else if (id === "calendar-glance")
      ShellState.toggleCalendar()
    else if (id === "weather-glance")
      ShellState.toggleWeather()
    else if (id === "open-calendar-app")
      ShellState.openCalendarApp()
    else if (id === "open-weather-app")
      ShellState.openWeatherApp()
    else if (id === "screenshot-region" || id === "screenshot-screen") {
      const mode = id === "screenshot-screen" ? "screen" : "region"
      const script = Config.scriptsDir + "/proteus-screenshot"
      Quickshell.execDetached({
        command: [
          "bash",
          "-lc",
          "if command -v proteus-screenshot >/dev/null 2>&1; then "
              + "proteus-screenshot " + mode + "; "
              + "elif [[ -x " + JSON.stringify(script) + " ]]; then "
              + JSON.stringify(script) + " " + mode + "; "
              + "fi"
        ]
      })
    }
  }

  // Console Search cards for Settings panes + allowlisted actions (query required).
  function consoleExtras(query) {
    const q = String(query || "").trim().toLowerCase()
    if (!q.length)
      return []
    const out = []
    const showUnavailable = true
    const idx = EnvGate.settingsSearchIndex || []
    for (let i = 0; i < idx.length; i++) {
      const p = idx[i]
      const ok = EnvGate.paneAvailable(p.hubId)
      if (!ok && !showUnavailable)
        continue
      const label = String(p.label).toLowerCase()
      const hay = (label + " " + (p.keywords || "") + " settings").toLowerCase()
      let score = Math.max(root.scoreQuery(label, q), root.scoreQuery(hay, q))
      if (score < 0)
        continue
      if (label === q || label.startsWith(q))
        score += 30
      out.push({
        id: "settings:" + p.id,
        title: p.label,
        tag: ok ? "SETTINGS" : "UNAVAILABLE",
        color0: Theme.elevatedFill,
        color1: Theme.bgElevated,
        kind: "settings",
        settingsPage: p.id,
        needsGamescope: false,
        commandArgs: [],
        score: score,
        chromeStyle: true,
        meta: ok ? "Settings" : "Unavailable"
      })
    }

    const acts = root.actionCatalog
    for (let i = 0; i < acts.length; i++) {
      const a = acts[i]
      if (String(a.id).startsWith("settings-"))
        continue
      if (a.id === "enter-console" && ShellState.consoleSurfaceActive)
        continue
      if (a.id === "enter-host" && ShellState.hostSurfaceActive)
        continue
      if (a.id === "enter-desktop"
          && !ShellState.consoleSurfaceActive && !ShellState.hostSurfaceActive)
        continue
      const hay = (String(a.name || "") + " " + String(a.keywords || "")).toLowerCase()
      const score = root.scoreQuery(hay, q)
      if (score < 0)
        continue
      out.push({
        id: "action:" + a.id,
        title: a.name,
        tag: a.destructive ? "POWER" : "ACTION",
        color0: Theme.elevatedFill,
        color1: Theme.bgElevated,
        kind: "action",
        actionId: a.id,
        needsGamescope: false,
        commandArgs: [],
        score: score,
        chromeStyle: true,
        meta: a.subtitle || "Action"
      })
    }

    out.sort((x, y) => {
      if ((y.score || 0) !== (x.score || 0))
        return (y.score || 0) - (x.score || 0)
      return String(x.title).localeCompare(String(y.title))
    })
    return out.slice(0, 24)
  }
}
