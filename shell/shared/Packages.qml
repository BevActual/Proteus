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

  // AUR / Flatpak detection (refreshed on demand)
  property string aurHelper: "" // yay | paru | ""
  property bool flatpakAvailable: false
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

  function _trimOpLines(maxKeep) {
    const n = maxKeep || 4
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
    _trimOpLines(4)
  }

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

  function openPacmanRemove(pkg) {
    if (!pkg || !String(pkg).length)
      return
    const name = String(pkg).replace(/[^a-zA-Z0-9@.+_-]/g, "")
    if (!name.length)
      return
    runPacmanMutator("remove", name)
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

  function aurRemove(pkg) {
    const name = String(pkg || "").replace(/[^a-zA-Z0-9@.+_-]/g, "")
    if (!name.length || !aurHelper.length)
      return
    runUserPkgOp([aurHelper, "-Rns", "--noconfirm", "--", name], "Removing " + name + "…")
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
    runUserPkgOp(["flatpak", "install", "-y", "--user", "--", id], "Installing " + id + "…")
  }

  function flatpakRemove(ref) {
    const id = String(ref || "").trim()
    if (!id.length || !flatpakAvailable)
      return
    runUserPkgOp(["flatpak", "uninstall", "-y", "--user", "--", id], "Removing " + id + "…")
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
        && action !== "remove" && action !== "orphans")
      return
    if ((action === "install" || action === "remove") && (!pkg || !String(pkg).length))
      return

    packageOpBusy = true
    packageOpLines = ["Looking up proteus-pkg…"]
    packageOpStatus = packageOpLines[0]
    pkgPendingAction = action
    pkgPendingPkg = pkg ? String(pkg) : ""

    let script = "BIN=\"\"; "
        + "if [ -x /usr/local/libexec/proteus-pkg ]; then BIN=/usr/local/libexec/proteus-pkg; "
        + "elif command -v proteus-pkg >/dev/null 2>&1; then BIN=$(command -v proteus-pkg); fi; "
    const bases = repoPkgCandidates
    for (let i = 0; i < bases.length; i++) {
      const b = Config.shellQuote(bases[i])
      script += "if [ -z \"$BIN\" ]; then "
          + "for t in target/release/proteus-pkg target/debug/proteus-pkg proteus-pkg; do "
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
    if (pkgPendingAction === "install" || pkgPendingAction === "remove")
      args.push(pkgPendingPkg)
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
    if (ok && (action === "upgrade" || action === "sync" || action === "install"
            || action === "remove" || action === "orphans" || action === "user"))
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
          + "printf '%s %s' \"$H\" \"$F\""
    ]
    stdout: StdioCollector {
      onStreamFinished: {
        const parts = text.trim().split(/\s+/)
        root.aurHelper = parts[0] || ""
        root.flatpakAvailable = parts[1] === "1"
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
          root.packageOpBusy = false
          root.packageOpStatus = "proteus-pkg missing — opened terminal"
          root.pkgPendingAction = ""
          root.pkgPendingPkg = ""
          if (a === "sync")
            root.openPacmanTerminal(["sudo", "pacman", "-Sy"])
          else if (a === "upgrade")
            root.openPacmanTerminal(["sudo", "pacman", "-Syu"])
          else if (a === "install" && p.length)
            root.openPacmanTerminal(["sudo", "pacman", "-S", "--needed", p])
          else if (a === "remove" && p.length)
            root.openPacmanTerminal(["sudo", "pacman", "-Rns", p])
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
