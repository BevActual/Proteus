pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Proteus package operations — pacman queries stay in the Settings panes;
// this owns the privileged mutator path (services/proteus-pkg via pkexec),
// user-session AUR/Flatpak runners, and the local AppImage library.
Singleton {
  id: root

  // Packages hub badge (−1 = not checked yet)
  property int packageUpgradeCount: -1

  property bool packageOpBusy: false
  property string packageOpStatus: ""
  property string packageBinPath: ""
  property var packageOpLines: []

  property string pkgPendingAction: ""
  property string pkgPendingPkg: ""
  property var pkgPendingPkgs: []

  // Seed Software → Search / AUR / Flatpak from the hub search field.
  property string searchSeed: ""
  property string searchSeedTarget: "packages-search" // packages-search | packages-aur | packages-flatpak

  function seedPackageSearch(query, target) {
    searchSeed = String(query || "").trim()
    const t = String(target || "packages-search")
    searchSeedTarget = (t === "packages-aur" || t === "packages-flatpak") ? t : "packages-search"
  }

  function takeSearchSeed() {
    const q = searchSeed
    searchSeed = ""
    return q
  }

  // AUR / Flatpak / Flathub detection (refreshed on demand)
  property string aurHelper: "" // yay | paru | ""
  property bool flatpakAvailable: false
  property bool flathubConfigured: false // user remote named flathub
  property bool helpersReady: false

  // AppImage library
  property var appImages: []
  property string appImageStatus: ""
  readonly property string appImageDir: Quickshell.env("HOME") + "/.local/share/proteus/appimages"
  readonly property string appImageDesktopDir: Quickshell.env("HOME") + "/.local/share/applications"

  signal packageOpFinished(bool ok, string message)

  function notePackageUpgrades(count) {
    packageUpgradeCount = count
  }

  // Search ranking shared by Software → Search / AUR / Flatpak.
  function packageMatchScore(query, name, desc) {
    const q = String(query || "").trim().toLowerCase()
    const n = String(name || "").toLowerCase()
    const d = String(desc || "").toLowerCase()
    if (!q.length)
      return 0
    if (n === q)
      return 1000
    if (n.startsWith(q))
      return 800
    if (n.indexOf(q) >= 0)
      return 600
    // Token starts-with (hyphen/underscore splits)
    const parts = n.split(/[-_.]/)
    for (let i = 0; i < parts.length; i++) {
      if (parts[i].startsWith(q))
        return 500
    }
    if (d.indexOf(q) >= 0)
      return 200
    return 0
  }

  function repoPreferScore(repo) {
    const r = String(repo || "").toLowerCase()
    if (r === "core")
      return 40
    if (r === "extra")
      return 30
    if (r === "multilib")
      return 20
    if (r === "aur")
      return 5
    return 10
  }

  function sortSearchResults(query, items) {
    const list = items || []
    const scored = []
    for (let i = 0; i < list.length; i++) {
      const it = list[i]
      const name = it.name || it.ref || ""
      const score = packageMatchScore(query, name, it.desc || "")
          + repoPreferScore(it.repo)
          + (it.installed ? 15 : 0)
      scored.push({
        item: it,
        score: score,
        name: String(name).toLowerCase()
      })
    }
    scored.sort((a, b) => {
      if (b.score !== a.score)
        return b.score - a.score
      return a.name < b.name ? -1 : (a.name > b.name ? 1 : 0)
    })
    const out = []
    for (let i = 0; i < scored.length; i++)
      out.push(scored[i].item)
    return out
  }

  function _trimOpLines(maxKeep) {
    const n = maxKeep || 12
    if (packageOpLines.length > n)
      packageOpLines = packageOpLines.slice(packageOpLines.length - n)
    packageOpStatus = packageOpLines.join("\n")
  }

  function _pushOpLine(line) {
    const s = String(line || "").trim()
    if (!s.length)
      return
    if (/^\s*\d+%\s*$/.test(s))
      return
    packageOpLines = packageOpLines.concat([s])
    _trimOpLines(12)
  }

  function cancelPackageOp() {
    if (!packageOpBusy)
      return
    if (userOpProc.running)
      userOpProc.running = false
    if (pkgMutatorProc.running)
      pkgMutatorProc.running = false
    if (pkgResolveProc.running)
      pkgResolveProc.running = false
    if (appImageMutProc.running)
      appImageMutProc.running = false
    _finishPkgMutator(false, "Cancelled.")
  }

  // Leaf UI memory (Install|Installed + per-mode query) across visits in this Settings session.
  property var leafUiState: ({})

  function saveLeafUi(key, mode, installQuery, installedQuery) {
    const k = String(key || "")
    if (!k.length)
      return
    const next = Object.assign({}, leafUiState)
    // Back-compat: third arg used to be a single query string.
    let iq = ""
    let rq = ""
    if (arguments.length >= 4) {
      iq = String(installQuery || "")
      rq = String(installedQuery || "")
    } else {
      const q = String(installQuery || "")
      iq = mode === "install" ? q : ""
      rq = mode === "installed" ? q : ""
    }
    next[k] = {
      mode: String(mode || "installed"),
      installQuery: iq,
      installedQuery: rq
    }
    leafUiState = next
  }

  function loadLeafUi(key) {
    const k = String(key || "")
    const st = leafUiState && leafUiState[k]
    if (!st)
      return null
    return {
      mode: st.mode || "installed",
      installQuery: st.installQuery || "",
      installedQuery: st.installedQuery || "",
      // legacy single-query field
      query: st.query || ""
    }
  }

  // Curated Install-browse seeds (filtered to not-installed at query time).
  readonly property var popularRepoPackages: [
    "firefox", "chromium", "htop", "btop", "ripgrep", "fd", "jq", "neovim",
    "vlc", "mpv", "gimp", "inkscape", "thunderbird", "code", "docker",
    "podman", "bat", "eza", "fzf", "tmux", "fish", "kitty", "alacritty",
    "obs-studio", "libreoffice-fresh", "wireshark-qt", "nmap", "curl",
    "wget", "git-delta", "lazygit", "bottom", "bandwhich", "imv", "zathura"
  ]

  readonly property var popularFlatpakApps: [
    "org.mozilla.firefox", "org.chromium.Chromium", "com.spotify.Client",
    "com.discordapp.Discord", "org.videolan.VLC", "org.gimp.GIMP",
    "org.blender.Blender", "com.obsproject.Studio", "org.libreoffice.LibreOffice",
    "org.gnome.Calculator", "org.gnome.TextEditor", "org.kde.krita",
    "com.valvesoftware.Steam", "org.signal.Signal", "im.riot.Riot"
  ]

  readonly property var popularAurHints: [
    "visual-studio-code-bin", "google-chrome", "spotify", "discord",
    "zoom", "slack-desktop", "1password", "brave-bin", "cursor-bin",
    "hyprshot", "walker", "yay", "paru", "nerd-fonts-complete",
    "ttf-ms-fonts", "downgrade", "rate-mirrors-bin"
  ]

  function shellQuote(s) {
    return "'" + String(s).replace(/'/g, "'\\''") + "'"
  }

  function refreshHelpers() {
    helperDetectProc.running = false
    helperDetectProc.running = true
  }

  readonly property var repoPkgCandidates: {
    const shell = Quickshell.shellRoot
    const bases = []
    if (shell && shell.length) {
      bases.push(shell + "/../../services/proteus-pkg")
      bases.push(shell + "/../services/proteus-pkg")
    }
    bases.push("/mnt/proteus/services/proteus-pkg")
    return bases
  }

  // Escape hatch: real terminal + sudo (when mutator missing / user prefers).
  function openPacmanTerminal(args) {
    const cmd = (args && args.length) ? args.join(" ") : "sudo pacman -Syu"
    Quickshell.execDetached({
      command: [
        "bash",
        "-lc",
        "exec proteus-terminal -e bash -lc " + JSON.stringify(cmd + '; echo; read -r -p \"Press Enter to close…\" _')
      ]
    })
  }

  function openUserTerminal(args) {
    const cmd = (args && args.length) ? args.join(" ") : "true"
    Quickshell.execDetached({
      command: [
        "bash",
        "-lc",
        "exec proteus-terminal -e bash -lc " + JSON.stringify(cmd + '; echo; read -r -p \"Press Enter to close…\" _')
      ]
    })
  }

  function openPacmanUpgrade() {
    runPacmanMutator("upgrade")
  }

  function openPacmanUpgradePackages(names) {
    if (!names || !names.length)
      return
    const clean = []
    for (let i = 0; i < names.length; i++) {
      const name = String(names[i] || "").replace(/[^a-zA-Z0-9@.+_-]/g, "")
      if (name.length)
        clean.push(name)
    }
    if (!clean.length)
      return
    runPacmanMutator("upgrade-packages", clean)
  }

  function openPacmanSync() {
    runPacmanMutator("sync")
  }

  function openPacmanInstall(pkg) {
    if (!pkg || !String(pkg).length)
      return
    const name = String(pkg).replace(/[^a-zA-Z0-9@.+_-]/g, "")
    if (!name.length)
      return
    runPacmanMutator("install", name)
  }

  function openPacmanInstallMany(names) {
    const clean = _sanitizePkgNames(names)
    if (!clean.length)
      return
    if (clean.length === 1)
      runPacmanMutator("install", clean[0])
    else
      runPacmanMutator("install", clean)
  }

  function openPacmanRemove(pkg) {
    if (!pkg || !String(pkg).length)
      return
    const name = String(pkg).replace(/[^a-zA-Z0-9@.+_-]/g, "")
    if (!name.length)
      return
    runPacmanMutator("remove", name)
  }

  function openPacmanRemoveMany(names) {
    const clean = _sanitizePkgNames(names)
    if (!clean.length)
      return
    if (clean.length === 1)
      runPacmanMutator("remove", clean[0])
    else
      runPacmanMutator("remove", clean)
  }

  function _sanitizePkgNames(names) {
    const clean = []
    if (!names || !names.length)
      return clean
    const list = typeof names === "string" ? [names] : names
    for (let i = 0; i < list.length; i++) {
      const name = String(list[i] || "").replace(/[^a-zA-Z0-9@.+_-]/g, "")
      if (name.length)
        clean.push(name)
    }
    return clean
  }

  function openPacmanOrphans() {
    runPacmanMutator("orphans")
  }

  // ── User-session ops (AUR / Flatpak) ─────────────────────────────────────

  function runUserPkgOp(args, label) {
    if (packageOpBusy)
      return
    if (!args || !args.length)
      return
    packageOpBusy = true
    packageOpLines = [label || "Running…"]
    packageOpStatus = packageOpLines[0]
    pkgPendingAction = "user"
    pkgPendingPkg = ""
    userOpProc.command = args
    userOpProc.running = false
    userOpProc.running = true
  }

  function aurInstall(pkg) {
    const name = String(pkg || "").replace(/[^a-zA-Z0-9@.+_-]/g, "")
    if (!name.length || !aurHelper.length)
      return
    runUserPkgOp([aurHelper, "-S", "--noconfirm", "--", name], "Installing " + name + "…")
  }

  function aurInstallMany(names) {
    const clean = _sanitizePkgNames(names)
    if (!clean.length || !aurHelper.length)
      return
    const args = [aurHelper, "-S", "--noconfirm", "--"].concat(clean)
    runUserPkgOp(args, "Installing " + clean.length + " AUR package" + (clean.length === 1 ? "" : "s") + "…")
  }

  function aurRemove(pkg) {
    const name = String(pkg || "").replace(/[^a-zA-Z0-9@.+_-]/g, "")
    if (!name.length || !aurHelper.length)
      return
    runUserPkgOp([aurHelper, "-Rns", "--noconfirm", "--", name], "Removing " + name + "…")
  }

  function aurRemoveMany(names) {
    const clean = _sanitizePkgNames(names)
    if (!clean.length || !aurHelper.length)
      return
    const args = [aurHelper, "-Rns", "--noconfirm", "--"].concat(clean)
    runUserPkgOp(args, "Removing " + clean.length + " package" + (clean.length === 1 ? "" : "s") + "…")
  }

  function aurUpdate() {
    if (!aurHelper.length)
      return
    // AUR-only upgrades when supported (yay/paru -Sua)
    runUserPkgOp([aurHelper, "-Sua", "--noconfirm"], "Updating AUR packages…")
  }

  function flatpakInstall(ref) {
    const id = String(ref || "").trim()
    if (!id.length || !flatpakAvailable)
      return
    const args = flathubConfigured
        ? ["flatpak", "install", "-y", "--user", "flathub", "--", id]
        : ["flatpak", "install", "-y", "--user", "--", id]
    runUserPkgOp(args, "Installing " + id + "…")
  }

  function flatpakInstallMany(refs) {
    const clean = []
    if (!refs || !refs.length || !flatpakAvailable)
      return
    for (let i = 0; i < refs.length; i++) {
      const id = String(refs[i] || "").trim()
      if (id.length)
        clean.push(id)
    }
    if (!clean.length)
      return
    const args = flathubConfigured
        ? ["flatpak", "install", "-y", "--user", "flathub", "--"].concat(clean)
        : ["flatpak", "install", "-y", "--user", "--"].concat(clean)
    runUserPkgOp(args, "Installing " + clean.length + " Flatpak" + (clean.length === 1 ? "" : "s") + "…")
  }

  function flatpakRemove(ref) {
    const id = String(ref || "").trim()
    if (!id.length || !flatpakAvailable)
      return
    runUserPkgOp(["flatpak", "uninstall", "-y", "--user", "--", id], "Removing " + id + "…")
  }

  function flatpakRemoveMany(refs) {
    const clean = []
    if (!refs || !refs.length || !flatpakAvailable)
      return
    for (let i = 0; i < refs.length; i++) {
      const id = String(refs[i] || "").trim()
      if (id.length)
        clean.push(id)
    }
    if (!clean.length)
      return
    const args = ["flatpak", "uninstall", "-y", "--user", "--"].concat(clean)
    runUserPkgOp(args, "Removing " + clean.length + " Flatpak" + (clean.length === 1 ? "" : "s") + "…")
  }

  function flatpakUpdate() {
    if (!flatpakAvailable)
      return
    runUserPkgOp(["flatpak", "update", "-y", "--user"], "Updating Flatpaks…")
  }

  function flatpakAddFlathub() {
    if (!flatpakAvailable)
      return
    runUserPkgOp([
      "flatpak",
      "remote-add",
      "--user",
      "--if-not-exists",
      "flathub",
      "https://dl.flathub.org/repo/flathub.flatpakrepo"
    ], "Adding Flathub…")
  }

  function noteFlathubConfigured(on) {
    flathubConfigured = !!on
  }

  // ── AppImages ────────────────────────────────────────────────────────────

  function _safeAppImageId(name) {
    return String(name || "app").replace(/[^a-zA-Z0-9._+-]/g, "-").replace(/-+/g, "-").replace(/^-|-$/g, "") || "app"
  }

  function refreshAppImages() {
    appImageStatus = "Scanning…"
    const dirQ = shellQuote(appImageDir)
    appImageListProc.command = [
      "bash",
      "-lc",
      "mkdir -p " + dirQ + "; "
          + "shopt -s nullglob; "
          + "for f in " + dirQ + "/*.AppImage " + dirQ + "/*.appimage; do "
          + "[ -f \"$f\" ] || continue; "
          + "b=$(basename \"$f\"); id=${b%.*}; "
          + "printf '%s\\t%s\\n' \"$id\" \"$f\"; "
          + "done"
    ]
    appImageListProc.running = false
    appImageListProc.running = true
  }

  function addAppImage(srcPath) {
    const src = String(srcPath || "")
    if (!src.length)
      return
    if (packageOpBusy)
      return
    packageOpBusy = true
    packageOpLines = ["Adding AppImage…"]
    packageOpStatus = packageOpLines[0]
    const base = src.split("/").pop() || "app.AppImage"
    const id = _safeAppImageId(base.replace(/\.AppImage$/i, ""))
    const dest = appImageDir + "/" + id + ".AppImage"
    const desktop = appImageDesktopDir + "/proteus-appimage-" + id + ".desktop"
    const label = id.replace(/-/g, " ")
    const script = "set -euo pipefail\n"
        + "mkdir -p " + shellQuote(appImageDir) + " " + shellQuote(appImageDesktopDir) + "\n"
        + "cp -f " + shellQuote(src) + " " + shellQuote(dest) + "\n"
        + "chmod +x " + shellQuote(dest) + "\n"
        + "cat > " + shellQuote(desktop) + " <<EOF\n"
        + "[Desktop Entry]\n"
        + "Type=Application\n"
        + "Name=" + label + "\n"
        + "Exec=\"" + dest + "\"\n"
        + "Icon=application-x-executable\n"
        + "Terminal=false\n"
        + "Categories=Utility;\n"
        + "X-Proteus-AppImage=1\n"
        + "EOF\n"
        + "printf '%s' ok\n"
    appImageMutProc.command = ["bash", "-lc", script]
    appImageMutProc.running = false
    appImageMutProc.running = true
  }

  function removeAppImage(id) {
    const safe = _safeAppImageId(id)
    if (!safe.length || packageOpBusy)
      return
    packageOpBusy = true
    packageOpLines = ["Removing AppImage…"]
    packageOpStatus = packageOpLines[0]
    const dest = appImageDir + "/" + safe + ".AppImage"
    const desktop = appImageDesktopDir + "/proteus-appimage-" + safe + ".desktop"
    const script = "rm -f " + shellQuote(dest) + " " + shellQuote(desktop) + "; printf '%s' ok"
    appImageMutProc.command = ["bash", "-lc", script]
    appImageMutProc.running = false
    appImageMutProc.running = true
  }

  function openAppImage(id) {
    const safe = _safeAppImageId(id)
    if (!safe.length)
      return
    const dest = appImageDir + "/" + safe + ".AppImage"
    Quickshell.execDetached({
      command: ["bash", "-lc", "exec " + shellQuote(dest)]
    })
  }

  function runPacmanMutator(action, pkg) {
    if (packageOpBusy)
      return
    if (action !== "sync" && action !== "upgrade" && action !== "install"
        && action !== "remove" && action !== "orphans" && action !== "upgrade-packages")
      return

    let pkgs = []
    if (action === "upgrade-packages") {
      if (!pkg || !pkg.length)
        return
      if (typeof pkg === "string")
        pkgs = [String(pkg)]
      else
        pkgs = pkg
      if (!pkgs.length)
        return
    } else if (action === "install" || action === "remove") {
      if (!pkg)
        return
      if (typeof pkg === "string") {
        if (!String(pkg).length)
          return
      } else if (pkg.length) {
        pkgs = pkg
      } else {
        return
      }
    }

    packageOpBusy = true
    packageOpLines = ["Looking up proteus-pkg…"]
    packageOpStatus = packageOpLines[0]
    pkgPendingAction = action
    if ((action === "install" || action === "remove") && typeof pkg === "string") {
      pkgPendingPkg = String(pkg)
      pkgPendingPkgs = []
    } else if ((action === "install" || action === "remove") && pkgs.length) {
      pkgPendingPkg = ""
      pkgPendingPkgs = pkgs
    } else {
      pkgPendingPkg = ""
      pkgPendingPkgs = pkgs
    }

    let script = "BIN=\"\"; "
        + "if [ -x /usr/local/libexec/proteus-pkg ]; then BIN=/usr/local/libexec/proteus-pkg; "
        + "elif command -v proteus-pkg >/dev/null 2>&1; then BIN=$(command -v proteus-pkg); fi; "
    const bases = repoPkgCandidates
    for (let i = 0; i < bases.length; i++) {
      const b = Config.shellQuote(bases[i])
      script += "if [ -z \"$BIN\" ]; then "
          + "for t in bin/proteus-pkg target/release/proteus-pkg target/debug/proteus-pkg proteus-pkg; do "
          + "c=" + b + "/$t; if [ -x \"$c\" ]; then BIN=$c; break; fi; done; fi; "
    }
    script += "printf '%s' \"$BIN\""

    pkgResolveProc.command = ["bash", "-c", script]
    pkgResolveProc.running = false
    pkgResolveProc.running = true
  }

  function _startPkgMutator(bin) {
    packageBinPath = bin
    packageOpLines = ["Authenticate to apply…"]
    packageOpStatus = packageOpLines[0]
    const args = ["pkexec", bin, pkgPendingAction]
    if (pkgPendingAction === "install" || pkgPendingAction === "remove") {
      if (pkgPendingPkgs.length) {
        for (let i = 0; i < pkgPendingPkgs.length; i++)
          args.push(pkgPendingPkgs[i])
      } else if (pkgPendingPkg.length) {
        args.push(pkgPendingPkg)
      }
    } else if (pkgPendingAction === "upgrade-packages") {
      for (let i = 0; i < pkgPendingPkgs.length; i++)
        args.push(pkgPendingPkgs[i])
    }
    pkgMutatorProc.command = args
    pkgMutatorProc.running = false
    pkgMutatorProc.running = true
  }

  function _finishPkgMutator(ok, message) {
    const action = pkgPendingAction
    packageOpBusy = false
    if (message && String(message).length)
      _pushOpLine(message)
    else if (!packageOpStatus.length)
      packageOpStatus = ok ? "Done." : "Failed."
    pkgPendingAction = ""
    pkgPendingPkg = ""
    pkgPendingPkgs = []
    if (ok && (action === "upgrade" || action === "upgrade-packages" || action === "sync"
            || action === "install" || action === "remove" || action === "orphans"
            || action === "user"))
      notePackageUpgrades(-1)
    packageOpFinished(ok, packageOpStatus)
  }

  Process {
    id: helperDetectProc
    command: [
      "bash",
      "-lc",
      "H=\"\"; command -v yay >/dev/null && H=yay; "
          + "[ -z \"$H\" ] && command -v paru >/dev/null && H=paru; "
          + "F=0; command -v flatpak >/dev/null && F=1; "
          + "FH=0; "
          + "[ \"$F\" = 1 ] && flatpak remotes --user --columns=name 2>/dev/null "
          + "| tr '[:upper:]' '[:lower:]' | grep -qx flathub && FH=1; "
          + "printf '%s %s %s' \"$H\" \"$F\" \"$FH\""
    ]
    stdout: StdioCollector {
      onStreamFinished: {
        const parts = text.trim().split(/\s+/)
        root.aurHelper = parts[0] || ""
        root.flatpakAvailable = parts[1] === "1"
        root.flathubConfigured = parts[2] === "1"
        root.helpersReady = true
      }
    }
  }

  Process {
    id: userOpProc
    command: ["true"]
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: line => root._pushOpLine(line)
    }
    stderr: SplitParser {
      splitMarker: "\n"
      onRead: line => root._pushOpLine(line)
    }
    onExited: (exitCode, exitStatus) => {
      if (!root.packageOpBusy)
        return
      if (exitCode === 0) {
        root._finishPkgMutator(true, "Done.")
        return
      }
      if (exitCode === 127) {
        root._finishPkgMutator(false, "Command not found.")
        return
      }
      root._finishPkgMutator(false, "Failed (exit " + exitCode + ")")
    }
  }

  Process {
    id: appImageListProc
    command: ["true"]
    stdout: StdioCollector {
      onStreamFinished: {
        const lines = text.trim().split("\n").filter(l => l.length)
        const out = []
        for (let i = 0; i < lines.length; i++) {
          const parts = lines[i].split("\t")
          if (parts.length < 2)
            continue
          out.push({
            id: parts[0],
            path: parts[1],
            name: String(parts[0]).replace(/-/g, " ")
          })
        }
        root.appImages = out
        root.appImageStatus = out.length ? "" : "No AppImages yet."
      }
    }
  }

  Process {
    id: appImageMutProc
    command: ["true"]
    stdout: StdioCollector {
      onStreamFinished: {
        // consumed on exit
      }
    }
    stderr: SplitParser {
      splitMarker: "\n"
      onRead: line => root._pushOpLine(line)
    }
    onExited: (exitCode, exitStatus) => {
      if (!root.packageOpBusy)
        return
      root.packageOpBusy = false
      if (exitCode === 0) {
        root.packageOpStatus = "Done."
        root.refreshAppImages()
        root.packageOpFinished(true, "Done.")
      } else {
        root.packageOpStatus = "Failed (exit " + exitCode + ")"
        root.packageOpFinished(false, root.packageOpStatus)
      }
    }
  }

  Process {
    id: pkgResolveProc
    command: ["true"]
    stdout: StdioCollector {
      onStreamFinished: {
        const bin = text.trim()
        if (!bin.length) {
          const a = root.pkgPendingAction
          const p = root.pkgPendingPkg
          const ps = root.pkgPendingPkgs.slice()
          root.packageOpBusy = false
          root.packageOpStatus = "proteus-pkg missing — opened terminal"
          root.pkgPendingAction = ""
          root.pkgPendingPkg = ""
          root.pkgPendingPkgs = []
          if (a === "sync")
            root.openPacmanTerminal(["sudo", "pacman", "-Sy"])
          else if (a === "upgrade")
            root.openPacmanTerminal(["sudo", "pacman", "-Syu"])
          else if (a === "upgrade-packages" && ps.length)
            root.openPacmanTerminal(["sudo", "pacman", "-S", "--needed", "--"].concat(ps))
          else if (a === "install" && (p.length || ps.length))
            root.openPacmanTerminal(["sudo", "pacman", "-S", "--needed", "--"].concat(p.length ? [p] : ps))
          else if (a === "remove" && (p.length || ps.length))
            root.openPacmanTerminal(["sudo", "pacman", "-Rns", "--"].concat(p.length ? [p] : ps))
          else if (a === "orphans")
            root.openPacmanTerminal(["sudo", "bash", "-lc", "pkgs=$(pacman -Qdtq); [ -n \"$pkgs\" ] && sudo pacman -Rns -- $pkgs || echo 'No orphans'"])
          root.packageOpFinished(false, "proteus-pkg not installed; used terminal fallback")
          return
        }
        root._startPkgMutator(bin)
      }
    }
  }

  Process {
    id: pkgMutatorProc
    command: ["true"]

    stdout: SplitParser {
      splitMarker: "\n"
      onRead: line => root._pushOpLine(line)
    }
    stderr: SplitParser {
      splitMarker: "\n"
      onRead: line => root._pushOpLine(line)
    }
    onExited: (exitCode, exitStatus) => {
      if (!root.packageOpBusy)
        return
      if (exitCode === 0) {
        root._finishPkgMutator(true, "Done.")
        return
      }
      if (exitCode === 126 || exitCode === 127) {
        root._finishPkgMutator(false, "Authentication cancelled or helper missing.")
        return
      }
      root._finishPkgMutator(false, "Failed (exit " + exitCode + ")")
    }
  }

  Component.onCompleted: refreshHelpers()
}
