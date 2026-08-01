import Quickshell
import Quickshell.Io
import QtQuick
import "../../shared"

// Console Home seats — Browser · Media · Terminal · Steam · RetroArch · Desktop · Web apps.
// Item (not QtObject): hosts Timer + Process children.
Item {
  id: root
  visible: false
  width: 0
  height: 0

  readonly property string rootDir: {
    const e = Quickshell.env("PROTEUS_ROOT")
    return (e && e.length) ? e : "/mnt/proteus"
  }

  readonly property string launchBin: {
    const live = root.rootDir + "/shell/scripts/proteus-console-launch"
    return live
  }

  readonly property string sampleLoop: root.rootDir + "/shell/assets/sample-loop.mp4"

  property bool hasBrowser: false
  property bool hasMpv: false
  property bool hasTerminal: false
  property bool hasGamescope: false
  property bool hasSteam: false
  property bool hasRetroarch: false
  property string browserBin: "chromium"

  property string statusHint: ""
  property string pendingLaunchTitle: ""

  function mediaPath() {
    const last = String(Config.consoleLastMediaPath || "").trim()
    if (last.length)
      return last
    return root.sampleLoop
  }

  readonly property string consoleStartPage: "file://" + root.rootDir + "/shell/assets/console-start.html"

  function browserArgs() {
    const b = root.browserBin
    const start = root.consoleStartPage
    if (b.indexOf("firefox") >= 0)
      return [b, "--kiosk", start]
    // Fullscreen + start page (avoid --app=about:blank blank window;
    // --app=file:// is flaky under sandbox — open the page directly).
    // Force Wayland ozone: Chromium still defaults to X11 when DISPLAY is unset.
    return [
      b,
      "--ozone-platform=wayland",
      "--enable-features=UseOzonePlatform",
      "--start-fullscreen",
      "--new-window",
      start
    ]
  }

  // Jump Back In = persisted recents, else seed from available seats
  readonly property var games: {
    const out = []
    try {
      const rec = (Config && Config.consoleRecents) ? Config.consoleRecents : []
      for (let i = 0; i < rec.length && out.length < 12; i++) {
        const r = rec[i]
        if (!r || !r.id)
          continue
        out.push(root.hydrateRecent(r))
      }
    } catch (e) {
    }
    if (out.length)
      return out
    // First-run seeds
    if (root.hasSteam)
      out.push(root.seatSteam())
    if (root.hasRetroarch)
      out.push(root.seatRetro())
    if (root.hasMpv)
      out.push(root.seatMedia())
    if (root.hasBrowser)
      out.push(root.seatBrowser())
    if (root.hasTerminal)
      out.push(root.seatTerminal())
    return out
  }

  readonly property var apps: {
    const out = []
    if (root.hasSteam)
      out.push(root.seatSteam())
    else
      out.push(root.seatMissing("steam", "Steam", "GAMES", "Install Steam (apply-console-kit)"))
    if (root.hasRetroarch)
      out.push(root.seatRetro())
    else
      out.push(root.seatMissing("retroarch", "RetroArch", "GAMES", "Install RetroArch (apply-console-kit)"))
    if (root.hasBrowser)
      out.push(root.seatBrowser())
    if (root.hasMpv)
      out.push(root.seatMedia())
    if (root.hasTerminal)
      out.push(root.seatTerminal())
    out.push({
      id: "webapps",
      title: "Web apps",
      tag: "WEB",
      color0: "#1a3a4a",
      color1: "#0d1c22",
      kind: "settings",
      needsGamescope: false,
      settingsPage: "packages-webapps",
      commandArgs: []
    })
    out.push({
      id: "desktop",
      title: "Desktop",
      tag: "POSTURE",
      color0: "#2a2a2e",
      color1: "#141416",
      kind: "posture",
      needsGamescope: false,
      commandArgs: []
    })
    return out
  }

  readonly property var featured: {
    if (games.length)
      return games[0]
    if (apps.length)
      return apps[0]
    return {
      id: "empty",
      title: "Console",
      tag: "HOME",
      color0: "#1c1c1e",
      color1: "#000000",
      meta: "Install Browser / Media / Steam for Jump Back In",
      kind: "empty",
      commandArgs: []
    }
  }

  function seatBrowser() {
    return {
      id: "browser",
      title: "Browser",
      tag: "WEB",
      color0: "#1a5c3a",
      color1: "#0d2818",
      meta: root.browserBin,
      kind: "browser",
      needsGamescope: false,
      commandArgs: root.browserArgs()
    }
  }

  function seatMedia() {
    const path = root.mediaPath()
    return {
      id: "media",
      title: path === root.sampleLoop ? "Sample reel" : "Media",
      tag: "MEDIA",
      color0: "#1a3a5c",
      color1: "#0d1828",
      meta: "mpv" + (root.hasGamescope ? " · gamescope" : ""),
      kind: "media",
      needsGamescope: root.hasGamescope,
      commandArgs: ["mpv", "--player-operation-mode=pseudo-gui", "--loop=inf", path]
    }
  }

  function seatTerminal() {
    return {
      id: "terminal",
      title: "Terminal",
      tag: "TOOLS",
      color0: "#2a2a2e",
      color1: "#141416",
      meta: "proteus-terminal",
      kind: "terminal",
      needsGamescope: false,
      commandArgs: ["proteus-terminal"]
    }
  }

  function seatSteam() {
    return {
      id: "steam",
      title: "Steam",
      tag: "GAMES",
      color0: "#1a2a4a",
      color1: "#0c1424",
      meta: "gamepadui" + (root.hasGamescope ? " · gamescope" : ""),
      kind: "steam",
      needsGamescope: true,
      commandArgs: ["steam", "-gamepadui"]
    }
  }

  function seatRetro() {
    return {
      id: "retroarch",
      title: "RetroArch",
      tag: "GAMES",
      color0: "#3a1a2a",
      color1: "#1c0d14",
      meta: root.hasGamescope ? "gamescope" : "bare",
      kind: "retroarch",
      needsGamescope: true,
      commandArgs: ["retroarch"]
    }
  }

  function seatMissing(id, title, tag, meta) {
    return {
      id: id,
      title: title,
      tag: tag,
      color0: "#2a2a2e",
      color1: "#141416",
      meta: meta,
      kind: "missing",
      needsGamescope: false,
      commandArgs: []
    }
  }

  function hydrateRecent(r) {
    const id = String(r.id || "")
    if (id === "steam" && root.hasSteam)
      return root.seatSteam()
    if (id === "retroarch" && root.hasRetroarch)
      return root.seatRetro()
    if (id === "browser" && root.hasBrowser)
      return root.seatBrowser()
    if (id === "media" && root.hasMpv)
      return root.seatMedia()
    if (id === "terminal" && root.hasTerminal)
      return root.seatTerminal()
    // Generic recent (desktop / webapp)
    return {
      id: id,
      title: r.title || id,
      tag: r.tag || (r.kind === "desktop" ? "APP" : "RECENT"),
      color0: r.color0 || "#1a3a5c",
      color1: r.color1 || "#0d1828",
      meta: r.meta || "",
      kind: r.kind || "desktop",
      desktopId: r.desktopId || "",
      needsGamescope: !!r.gamescope,
      commandArgs: r.command ? String(r.command).split("\n") : []
    }
  }

  function recordRecent(item) {
    if (!item || !item.id || item.kind === "missing" || item.kind === "empty" || item.kind === "posture" || item.kind === "settings")
      return
    const entry = {
      id: String(item.id),
      title: String(item.title || item.id),
      kind: String(item.kind || ""),
      tag: String(item.tag || ""),
      desktopId: String(item.desktopId || ""),
      gamescope: !!item.needsGamescope,
      command: (item.commandArgs && item.commandArgs.length) ? item.commandArgs.join("\n") : "",
      ts: Date.now()
    }
    const prev = Config.consoleRecents || []
    const next = [entry]
    for (let i = 0; i < prev.length && next.length < 12; i++) {
      if (prev[i] && String(prev[i].id) !== entry.id)
        next.push(prev[i])
    }
    Config.consoleRecents = next
    if (item.kind === "media" && item.commandArgs && item.commandArgs.length) {
      const path = String(item.commandArgs[item.commandArgs.length - 1] || "")
      if (path.length && path !== root.sampleLoop)
        Config.consoleLastMediaPath = path
    }
  }

  function clearHint() {
    statusHint = ""
  }

  function refreshAvailability() {
    probeProc.running = false
    probeProc.running = true
  }

  function launchBinPath() {
    if (Quickshell.env("PATH"))
      return "proteus-console-launch"
    return root.launchBin
  }

  function activate(item) {
    if (!item)
      return
    if (item.kind === "posture" || item.id === "desktop") {
      statusHint = "Returning to Desktop…"
      pendingLaunchTitle = ""
      launchWatch.stop()
      ShellState.hideConsoleNav()
      Quickshell.execDetached({
        command: [
          "bash", "-lc",
          "setsid $(command -v proteus-posture || echo "
              + root.rootDir + "/vm/guest/proteus-posture) desktop >/dev/null 2>&1 &"
        ]
      })
      return
    }
    if (item.kind === "settings") {
      statusHint = "Opening Software → Web apps…"
      ShellState.openSettings(item.settingsPage || "packages-webapps")
      return
    }
    if (item.kind === "missing") {
      statusHint = item.meta || ((item.title || "App") + " not installed")
      return
    }
    if (item.kind === "empty") {
      statusHint = "No apps available yet — apply-console-kit / desktop packages"
      return
    }

    root.recordRecent(item)

    const args = item.commandArgs || []
    if (!args.length && item.desktopId) {
      activateDesktopId(item.desktopId, item.title || item.desktopId, item)
      return
    }
    if (!args.length) {
      statusHint = (item.title || "App") + " — not available"
      return
    }

    // Release Exclusive keyboard grab so Hyprland can focus the new client
    // (otherwise apps stay tiled/unfocused under console chrome).
    ShellState.consoleLaunchPending = true
    ShellState.hideConsoleNav()

    const cmd = [root.launchBinPath()]
    if (item.needsGamescope)
      cmd.push("--gamescope")
    for (let i = 0; i < args.length; i++)
      cmd.push(String(args[i]))

    pendingLaunchTitle = item.title || "App"
    statusHint = "Opening " + pendingLaunchTitle + "…"
    Quickshell.execDetached({
      command: [
        "bash", "-lc",
        "export PATH=\"/usr/local/bin:" + root.rootDir + "/shell/scripts:$PATH\"; "
            + cmd.map(c => "'" + String(c).replace(/'/g, "'\\''") + "'").join(" ")
            + " &"
      ]
    })
    launchWatch.restart()
    fullscreenAssist.restart()
  }

  function activateDesktopId(desktopId, title, item) {
    const id = String(desktopId || "")
    if (!id.length) {
      statusHint = "Missing desktop id"
      return
    }
    if (item)
      root.recordRecent(item)
    else
      root.recordRecent({
        id: id,
        title: title || id,
        kind: "desktop",
        desktopId: id,
        tag: "APP"
      })
    ShellState.consoleLaunchPending = true
    ShellState.hideConsoleNav()
    pendingLaunchTitle = title || id
    statusHint = "Opening " + pendingLaunchTitle + "…"
    Quickshell.execDetached({
      command: [
        "bash", "-lc",
        "export PATH=\"/usr/local/bin:" + root.rootDir + "/shell/scripts:$PATH\"; "
            + "proteus-console-launch --desktop '" + id.replace(/'/g, "'\\''") + "' &"
      ]
    })
    launchWatch.restart()
    fullscreenAssist.restart()
  }

  // After launch, force fullscreen on the focused client (windowrule can race).
  Timer {
    id: fullscreenAssist
    interval: 450
    repeat: false
    onTriggered: {
      Quickshell.execDetached({
        command: [
          "bash", "-lc",
          "command -v hyprctl >/dev/null || exit 0; "
              + "for i in 1 2 3 4 5; do "
              + "  aw=$(hyprctl activewindow -j 2>/dev/null || true); "
              + "  echo \"$aw\" | grep -q '\"class\"' || { sleep 0.25; continue; }; "
              + "  echo \"$aw\" | grep -qE 'quickshell|Proteus Settings' && exit 0; "
              + "  hyprctl dispatch fullscreen 0 >/dev/null 2>&1 || hyprctl dispatch fullscreen 1 >/dev/null 2>&1; "
              + "  exit 0; "
              + "done"
        ]
      })
    }
  }

  function cancelLaunchWatch() {
    launchWatch.stop()
    pendingLaunchTitle = ""
    ShellState.consoleLaunchPending = false
    if (String(statusHint).indexOf("Opening") === 0)
      statusHint = ""
  }

  function onLaunchWatchFired() {
    ShellState.consoleLaunchPending = false
    if (!ShellState.consoleNavVisible) {
      // App may have focused (nav hidden) — clear pending title only
      pendingLaunchTitle = ""
      return
    }
    const t = pendingLaunchTitle.length ? pendingLaunchTitle : "App"
    statusHint = t + " — did not open (check GL / package)"
    pendingLaunchTitle = ""
    ShellState.showConsoleNav()
  }

  Timer {
    id: launchWatch
    interval: 2200
    repeat: false
    onTriggered: root.onLaunchWatchFired()
  }

  Process {
    id: probeProc
    command: [
      "bash", "-c",
      "browser=; for b in chromium chromium-browser brave firefox; do "
          + "command -v \"$b\" >/dev/null 2>&1 && browser=$b && break; done; "
          + "mpv=0; command -v mpv >/dev/null 2>&1 && mpv=1; "
          + "term=0; (command -v proteus-terminal >/dev/null 2>&1 || command -v ghostty >/dev/null 2>&1 || command -v foot >/dev/null 2>&1) && term=1; "
          + "gs=0; command -v gamescope >/dev/null 2>&1 && gs=1; "
          + "st=0; command -v steam >/dev/null 2>&1 && st=1; "
          + "ra=0; command -v retroarch >/dev/null 2>&1 && ra=1; "
          + "printf '%s %s %s %s %s %s\\n' \"${browser:-}\" \"$mpv\" \"$term\" \"$gs\" \"$st\" \"$ra\""
    ]
    stdout: StdioCollector {
      onStreamFinished: {
        const parts = text.trim().split(/\s+/)
        root.browserBin = parts[0] && parts[0].length ? parts[0] : "chromium"
        root.hasBrowser = !!(parts[0] && parts[0].length)
        root.hasMpv = parts[1] === "1"
        root.hasTerminal = parts[2] === "1"
        root.hasGamescope = parts[3] === "1"
        root.hasSteam = parts[4] === "1"
        root.hasRetroarch = parts[5] === "1"
      }
    }
  }

  Component.onCompleted: root.refreshAvailability()
}
