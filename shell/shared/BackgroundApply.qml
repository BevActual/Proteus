import Quickshell
import Quickshell.Io
import QtQuick

// Folder scan + applyBackground backends. host = Background singleton.
Item {
  id: apply
  property var host

  function scanWallpaperFolder(dirOverride) {
    if (wallpaperScanProc.running)
      return
    host.wallpaperFolderScanning = true
    const resolved = (dirOverride && String(dirOverride).length)
        ? String(dirOverride)
        : host.wallpaperFolderResolved
    const dir = JSON.stringify(resolved)
    wallpaperScanProc.command = [
      "python3",
      "-c",
      "import json, pathlib, sys\n"
          + "root = pathlib.Path(" + dir + ")\n"
          + "ext = {'.png','.jpg','.jpeg','.webp','.bmp','.gif'}\n"
          + "out = []\n"
          + "if host.is_dir():\n"
          + "  for p in sorted(host.iterdir()):\n"
          + "    if p.is_file() and p.suffix.lower() in ext:\n"
          + "      out.append({'path': str(p), 'label': p.stem})\n"
          + "print(json.dumps(out))\n"
    ]
    wallpaperScanProc.running = false
    wallpaperScanProc.running = true
  }

  // Matches every runner generation: the respawn-loop wrapper (comm =
  // proteus-bg via pgrep -x), its quickshell child, and the legacy
  // `exec -a proteus-bg` style whose comm is quickshell but whose cmdline
  // starts with proteus-bg — pgrep -x missed that one entirely, so every
  // background change stacked another wallpaper instance until reboot.
  // [r] bracket keeps -f patterns from matching the probing shell itself.
  readonly property string bgProcPattern: "'(quickshell|proteus-bg) (-p )?.*shell/wallpape[r]'"

  function stopBackgroundBackends() {
    // Clear legacy shims + previous runner instances
    return "pkill -x swaybg 2>/dev/null || true; "
        + "pkill -x mpvpaper 2>/dev/null || true; "
        + "pkill -x proteus-bg 2>/dev/null || true; "
        + "pkill -f " + bgProcPattern + " 2>/dev/null || true; "
        + "for i in 1 2 3 4 5 6 7 8 9 10; do "
        + "  pgrep -x swaybg >/dev/null || pgrep -x mpvpaper >/dev/null || pgrep -x proteus-bg >/dev/null || pgrep -f " + bgProcPattern + " >/dev/null || break; "
        + "  sleep 0.05; "
        + "done; "
  }


  function applyBackground() {
    // Flush first so a cold start doesn't race on stale wallpaper*.
    // If proteus-bg is already up, nudge FileView watchers — do NOT kill/restart
    // (that breaks video loops and reactive animations on every pick).
    Config.flushSettings()
    const wallDir = Config.shellQuote(host.wallpaperDir)
    const rootEnv = Config.shellQuote(Quickshell.env("PROTEUS_ROOT") || "/mnt/proteus")
    Quickshell.execDetached({
      command: [
        "bash",
        "-c",
        "export QT_QPA_PLATFORM=\"${QT_QPA_PLATFORM:-wayland}\"; "
            + "pkill -x swaybg 2>/dev/null || true; "
            + "pkill -x mpvpaper 2>/dev/null || true; "
            // grep -vx $$ : this script's own cmdline contains the literal
            // fallback "quickshell -p …/shell/wallpaper", so a bare pgrep -f
            // always self-matches and the respawn silently no-ops.
            + "if pgrep -x proteus-bg >/dev/null || pgrep -f " + bgProcPattern + " | grep -vqx \"$$\"; then "
            + "  touch \"$HOME/.config/proteus/settings.json\" 2>/dev/null || true; "
            + "  exit 0; "
            + "fi; "
            // Prefer hyprctl so the wallpaper process gets a real Wayland display
            // (bare exec from odd parents can fail and leave Hyprland's splash visible).
            + "BG=\"\"; "
            + "if [[ -x /usr/local/bin/proteus-bg ]]; then BG=/usr/local/bin/proteus-bg; "
            + "elif [[ -x \"$HOME/.local/bin/proteus-bg\" ]]; then BG=\"$HOME/.local/bin/proteus-bg\"; "
            + "elif [[ -x /mnt/proteus/vm/guest/proteus-bg ]]; then BG=/mnt/proteus/vm/guest/proteus-bg; "
            + "elif command -v proteus-bg >/dev/null 2>&1; then BG=$(command -v proteus-bg); fi; "
            + "CMD=\"env QT_QPA_PLATFORM=wayland PROTEUS_ROOT=" + rootEnv + " \${BG:-quickshell -p " + wallDir + "}\"; "
            + "if command -v hyprctl >/dev/null 2>&1 && [[ -n \"${HYPRLAND_INSTANCE_SIGNATURE:-}\" || -d \"${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr\" ]]; then "
            + "  export HYPRLAND_INSTANCE_SIGNATURE=\"${HYPRLAND_INSTANCE_SIGNATURE:-$(ls -1t \"${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr\" 2>/dev/null | head -1)}\"; "
            + "  hyprctl dispatch exec \"$CMD\"; "
            + "elif [[ -n \"$BG\" ]]; then exec \"$BG\"; "
            + "else exec quickshell -p " + wallDir + "; fi"
      ]
    })
  }

  function applyWallpaper() {
    host.applyBackground()
  }

  // Watchdog — heal a dead wallpaper runner without a reboot. Background
  // changes can crash proteus-bg; the wrapper respawns crashes, and this
  // covers everything else (KILL, wrapper failure, OOM). Only respawns after
  // the runner has been seen alive this session, so nested/dev shells that
  // never start a wallpaper don't get one spawned under them.
  property bool bgSeenAlive: false

  Timer {
    interval: 15000
    running: true
    repeat: true
    onTriggered: {
      if (!bgWatchProc.running)
        bgWatchProc.running = true
    }
  }

  Process {
    id: bgWatchProc
    command: ["bash", "-c",
      "pgrep -x proteus-bg >/dev/null || pgrep -f '(quickshell|proteus-bg) (-p )?.*shell/wallpape[r]' >/dev/null"]
    onExited: (code, status) => {
      if (code === 0) {
        apply.bgSeenAlive = true
        return
      }
      if (!apply.bgSeenAlive)
        return
      apply.bgSeenAlive = false
      console.warn("Background: wallpaper runner died — respawning proteus-bg")
      host.applyBackground()
    }
  }
  Process {
    id: wallpaperScanProc
    command: ["true"]
    stdout: StdioCollector {
      onStreamFinished: {
        host.wallpaperFolderScanning = false
        try {
          const list = JSON.parse(text.trim() || "[]")
          host.wallpaperFolderEntries = Array.isArray(list) ? list : []
        } catch (e) {
          host.wallpaperFolderEntries = []
        }
      }
    }
  }

  Process {
    id: wallpaperDailyFetchProc
    property bool applyAfter: true
    command: ["true"]
    stdout: StdioCollector {
      onStreamFinished: {
        host.wallpaperDailyFetching = false
        const res = host.parseDailyResult(text, "Daily")
        if (!res.ok) {
          host.wallpaperDailyError = res.error
          return
        }
        host.wallpaperDailyError = ""
        if (res.path.length)
          host.wallpaperDailyPath = res.path
        host.wallpaperDailyTitle = res.title
        host.wallpaperDailyCopyright = res.copyright
        host.wallpaperDailyFetchedAt = res.fetchedAt
        Config.flushSettings()
        // Desktop-only: the background is drawn by proteus-bg, so it has to be
        // signalled. The lock surface renders in-process and needs no nudge.
        if (wallpaperDailyFetchProc.applyAfter || host.wallpaperKind === "daily" || host.wallpaperId === "daily") {
          host.wallpaperId = "daily"
          host.wallpaperKind = "daily"
          host.applyBackground()
        }
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        const err = text.trim()
        if (err.length && host.wallpaperDailyFetching)
          host.wallpaperDailyError = err.split("\n")[0]
      }
    }
  }

  Process {
    id: lockDailyFetchProc
    command: ["true"]
    stdout: StdioCollector {
      onStreamFinished: {
        host.lockDailyFetching = false
        const res = host.parseDailyResult(text, "Lock daily")
        if (!res.ok) {
          host.lockDailyError = res.error
          return
        }
        host.lockDailyError = ""
        if (res.path.length)
          host.lockDailyPath = res.path
        host.lockBackgroundMode = "daily"
        Config.flushSettings()
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        const err = text.trim()
        if (err.length && host.lockDailyFetching)
          host.lockDailyError = err.split("\n")[0]
      }
    }
  }

}
