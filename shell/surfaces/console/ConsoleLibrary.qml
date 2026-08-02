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

  readonly property string seatBin: {
    return root.rootDir + "/shell/scripts/proteus-console-seat"
  }

  readonly property string capabilitiesBin: {
    return root.rootDir + "/shell/scripts/proteus-console-capabilities"
  }

  readonly property string sessionBin: {
    return root.rootDir + "/shell/scripts/proteus-console-session"
  }

  readonly property string sampleLoop: root.rootDir + "/shell/assets/sample-loop.mp4"

  property bool hasBrowser: false
  property bool hasMpv: false
  property bool hasTerminal: false
  property bool hasGamescope: false // usable Gamescope (Vulkan), not merely installed
  property bool hasGamescopeBin: false
  property bool isVm: false
  property bool hasSteam: false
  property bool hasRetroarch: false
  property string browserBin: "chromium"
  // Phase 2 session Fact — seat | gamescope (nested; does not replace Hyprland)
  property string sessionMode: "seat"
  property string sessionEffective: "seat"

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
      out.push(root.seatMissing("steam", "Steam", "GAMES", "Install Steam (install-console-software / console stage)"))
    if (root.hasRetroarch)
      out.push(root.seatRetro())
    else
      out.push(root.seatMissing("retroarch", "RetroArch", "GAMES", "Install RetroArch (install-console-software / console stage)"))
    if (root.hasBrowser)
      out.push(root.seatBrowser())
    if (root.hasMpv)
      out.push(root.seatMedia())
    if (root.hasTerminal)
      out.push(root.seatTerminal())
    // Web apps live on Home as their own row (proteus-web-*); keep Install escape.
    out.push({
      id: "webapps-install",
      title: "Install Web apps",
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

  // Curated seats without the Install Web apps / Desktop escapes (Home APPS row).
  readonly property var appSeats: {
    const out = []
    if (root.hasSteam)
      out.push(root.seatSteam())
    else
      out.push(root.seatMissing("steam", "Steam", "GAMES", "Install Steam (install-console-software / console stage)"))
    if (root.hasRetroarch)
      out.push(root.seatRetro())
    else
      out.push(root.seatMissing("retroarch", "RetroArch", "GAMES", "Install RetroArch (install-console-software / console stage)"))
    if (root.hasBrowser)
      out.push(root.seatBrowser())
    if (root.hasMpv)
      out.push(root.seatMedia())
    if (root.hasTerminal)
      out.push(root.seatTerminal())
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

  function seatMetaSuffix() {
    if (root.sessionEffective === "gamescope")
      return " · session · gamescope"
    if (root.hasGamescope)
      return " · gamescope"
    if (root.isVm)
      return " · bare · kiosk"
    return " · bare"
  }

  function toggleSessionMode() {
    if (!root.hasGamescope) {
      statusHint = "Gamescope session needs Vulkan (unavailable here)"
      return
    }
    const next = root.sessionMode === "gamescope" ? "seat" : "gamescope"
    Quickshell.execDetached({
      command: [
        "bash", "-lc",
        "export PATH=\"" + root.rootDir
            + "/shell/scripts:$HOME/.local/bin:/usr/local/bin:$PATH\"; "
            + "'" + root.sessionBin.replace(/'/g, "'\\''") + "' set-mode " + next
            + " >/dev/null 2>&1; true"
      ]
    })
    root.sessionMode = next
    root.sessionEffective = (next === "gamescope" && root.hasGamescope) ? "gamescope" : "seat"
    statusHint = next === "gamescope"
        ? "Gamescope session on — nested wraps for game seats (Hyprland stays)"
        : "Seat mode — per-title Gamescope when usable"
    root.refreshAvailability()
  }

  function seatSteam() {
    return {
      id: "steam",
      title: "Steam",
      tag: "GAMES",
      color0: "#1a2a4a",
      color1: "#0c1424",
      meta: "gamepadui" + root.seatMetaSuffix(),
      kind: "steam",
      needsGamescope: root.hasGamescope,
      expectClass: "steam",
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
      meta: root.hasGamescope ? ("gamescope" + root.seatMetaSuffix()) : ("bare" + (root.isVm ? " · kiosk" : "")),
      kind: "retroarch",
      needsGamescope: root.hasGamescope,
      expectClass: "com.libretro.RetroArch|retroarch",
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
    if (!item || !item.id || item.kind === "missing" || item.kind === "empty"
        || item.kind === "posture" || item.kind === "settings" || item.kind === "action")
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

  function removeRecent(id) {
    const rid = String(id || "")
    if (!rid.length)
      return false
    const prev = Config.consoleRecents || []
    const next = []
    for (let i = 0; i < prev.length; i++) {
      if (prev[i] && String(prev[i].id) !== rid)
        next.push(prev[i])
    }
    if (next.length === prev.length)
      return false
    Config.consoleRecents = next
    statusHint = "Removed from Jump Back In"
    return true
  }

  function hasResumeMedia() {
    const last = String(Config.consoleLastMediaPath || "").trim()
    return last.length > 0 && last !== root.sampleLoop
  }

  function resumeMediaLabel() {
    const last = String(Config.consoleLastMediaPath || "").trim()
    if (!last.length)
      return "Resume last"
    const parts = last.split("/")
    return "Resume · " + (parts[parts.length - 1] || last)
  }

  function launchMediaPath(path, title) {
    const p = String(path || "").trim()
    if (!p.length) {
      statusHint = "No media path"
      return
    }
    if (p !== root.sampleLoop)
      Config.consoleLastMediaPath = p
    const item = {
      id: "media",
      title: title || (p === root.sampleLoop ? "Sample reel" : "Media"),
      tag: "MEDIA",
      color0: "#1a3a5c",
      color1: "#0d1828",
      meta: p,
      kind: "media-play",
      needsGamescope: root.hasGamescope,
      commandArgs: ["mpv", "--player-operation-mode=pseudo-gui", "--loop=inf", p]
    }
    root.activate(item)
  }

  function pickMediaFile() {
    const bin = root.rootDir + "/shell/scripts/proteus-pick-media"
    statusHint = "Choose a media file…"
    pickProc.command = ["bash", "-lc", "bin=\"" + bin + "\"; [[ -x \"$bin\" ]] || bin=$(command -v proteus-pick-media); \"$bin\""]
    pickProc.running = false
    pickProc.running = true
  }

  function refreshAvailability() {
    probeProc.running = false
    probeProc.running = true
  }

  function launchBinPath() {
    // Always prefer the live tree script when present (stale /usr/local/bin copies
    // used to hard-exec gamescope and die in QEMU).
    if (root.launchBin && root.launchBin.indexOf("/") === 0)
      return root.launchBin
    return "proteus-console-launch"
  }

  function seatBinPath() {
    if (root.seatBin && root.seatBin.indexOf("/") === 0)
      return root.seatBin
    return "proteus-console-seat"
  }

  function expectClassFor(item) {
    if (item && item.expectClass)
      return String(item.expectClass)
    const id = String((item && (item.id || item.desktopId)) || "").toLowerCase()
    if (id.indexOf("steam") >= 0)
      return "steam"
    if (id.indexOf("retroarch") >= 0 || id.indexOf("libretro") >= 0)
      return "com.libretro.RetroArch|retroarch"
    if (id.indexOf("chromium") >= 0 || id.indexOf("chrome") >= 0)
      return "chromium|google-chrome|Chromium"
    if (id.indexOf("firefox") >= 0)
      return "firefox"
    if (id.indexOf("mpv") >= 0)
      return "mpv"
    return id.replace(/\.desktop$/, "")
  }

  function runSeat(seatArgs, title) {
    ShellState.consoleLaunchPending = true
    ShellState.hideConsoleNav()
    pendingLaunchTitle = title || "App"
    statusHint = "Opening " + pendingLaunchTitle + "…"
    const pathPrefix = "export PATH=\"" + root.rootDir
        + "/shell/scripts:$HOME/.local/bin:/usr/local/bin:$PATH\"; "
    const cmd = [root.seatBinPath()].concat(seatArgs)
    Quickshell.execDetached({
      command: [
        "bash", "-lc",
        pathPrefix
            + cmd.map(c => "'" + String(c).replace(/'/g, "'\\''") + "'").join(" ")
            + " &"
      ]
    })
    // Seat waits for map + fullscreen; UI timeout is honesty-only.
    launchWatch.interval = 12000
    launchWatch.restart()
  }

  function activate(item) {
    if (!item)
      return
    // Media seat opens a submenu in ConsoleHome — do not launch directly.
    // media-play is the submenu's confirmed path.
    if (item.kind === "media")
      return
    // Only explicit posture seats flip chrome — never match kind:"desktop" (DesktopEntries).
    if (item.kind === "posture") {
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
      const page = item.settingsPage || item.paneId || "packages-webapps"
      statusHint = "Opening Settings…"
      ShellState.openSettings(page)
      return
    }
    if (item.kind === "action") {
      statusHint = item.title || "Action"
      UniversalSearch.runAction(item.actionId || item.id)
      return
    }
    if (item.kind === "missing") {
      statusHint = item.meta || ((item.title || "App") + " not installed")
      return
    }
    if (item.kind === "empty") {
      statusHint = "No apps available yet — install-console-software / desktop packages"
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

    // Supervised seat: never calls proteus-posture; Gamescope only when usable.
    const seatArgs = ["--expect-class", root.expectClassFor(item)]
    if (item.needsGamescope === false)
      seatArgs.push("--no-gamescope")
    seatArgs.push("--")
    for (let i = 0; i < args.length; i++)
      seatArgs.push(String(args[i]))
    root.runSeat(seatArgs, item.title || "App")
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
    const seatArgs = [
      "--expect-class", root.expectClassFor(item || { id: id, desktopId: id }),
      "--desktop", id
    ]
    root.runSeat(seatArgs, title || id)
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
    interval: 12000
    repeat: false
    onTriggered: root.onLaunchWatchFired()
  }

  Process {
    id: probeProc
    command: [
      "bash", "-c",
      "export PATH=\"" + root.rootDir + "/shell/scripts:$HOME/.local/bin:/usr/local/bin:$PATH\"; "
          + "browser=; for b in chromium chromium-browser brave firefox; do "
          + "command -v \"$b\" >/dev/null 2>&1 && browser=$b && break; done; "
          + "mpv=0; command -v mpv >/dev/null 2>&1 && mpv=1; "
          + "term=0; (command -v proteus-terminal >/dev/null 2>&1 || command -v ghostty >/dev/null 2>&1 || command -v foot >/dev/null 2>&1) && term=1; "
          + "caps=$(\"" + root.capabilitiesBin + "\" 2>/dev/null || echo '{}'); "
          + "printf '%s\\t%s\\t%s\\t%s\\n' \"${browser:-}\" \"$mpv\" \"$term\" \"$caps\""
    ]
    stdout: StdioCollector {
      onStreamFinished: {
        const line = text.trim()
        // browser \t mpv \t term \t {json}
        const parts = line.split("\t")
        root.browserBin = parts[0] && parts[0].length ? parts[0] : "chromium"
        root.hasBrowser = !!(parts[0] && parts[0].length)
        root.hasMpv = parts[1] === "1"
        root.hasTerminal = parts[2] === "1"
        let caps = {}
        try {
          caps = JSON.parse(parts.slice(3).join("\t") || "{}")
        } catch (e) {
          caps = {}
        }
        root.hasGamescope = !!caps.gamescopeUsable
        root.hasGamescopeBin = !!caps.gamescope
        root.isVm = !!caps.isVm
        root.hasSteam = !!caps.steam
        root.hasRetroarch = !!caps.retroarch
        root.sessionMode = (caps.sessionMode === "gamescope") ? "gamescope" : "seat"
        root.sessionEffective = (caps.sessionEffective === "gamescope") ? "gamescope" : "seat"
      }
    }
  }

  Process {
    id: pickProc
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        const path = String(this.text || "").trim()
        if (path.length)
          root.launchMediaPath(path, "Media")
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        const t = String(this.text || "").trim()
        if (t.indexOf("zenity") >= 0 || t.indexOf("kdialog") >= 0)
          root.statusHint = "Install zenity or kdialog to choose media"
      }
    }
    onExited: (code, status) => {
      if (code === 1)
        root.statusHint = "Media pick cancelled"
      else if (code === 2)
        root.statusHint = "Install zenity or kdialog to choose media"
    }
  }

  Component.onCompleted: root.refreshAvailability()
}
