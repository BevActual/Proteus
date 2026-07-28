pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Proteus package operations — pacman queries stay in the Settings panes;
// this owns the privileged mutator path (services/proteus-pkg via pkexec) and
// the terminal + sudo fallback for dogfooding without an install.
//
// Extracted from Config.qml. All state here is session-scoped, so unlike audio
// or wallpaper this needed nothing from settings.json.
Singleton {
  id: root

  // Packages hub badge (−1 = not checked yet)
  property int packageUpgradeCount: -1

  property bool packageOpBusy: false
  property string packageOpStatus: ""
  property string packageBinPath: ""

  property string pkgPendingAction: ""
  property string pkgPendingPkg: ""

  signal packageOpFinished(bool ok, string message)

  function notePackageUpgrades(count) {
    packageUpgradeCount = count
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
        "exec foot -e bash -lc " + JSON.stringify(cmd + '; echo; read -r -p \"Press Enter to close…\" _')
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

  function runPacmanMutator(action, pkg) {
    if (packageOpBusy)
      return
    if (action !== "sync" && action !== "upgrade" && action !== "install")
      return
    if (action === "install" && (!pkg || !String(pkg).length))
      return

    packageOpBusy = true
    packageOpStatus = "Looking up proteus-pkg…"
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
    packageOpStatus = "Authenticate to apply…"
    const args = ["pkexec", bin, pkgPendingAction]
    if (pkgPendingAction === "install")
      args.push(pkgPendingPkg)
    pkgMutatorProc.command = args
    pkgMutatorProc.running = false
    pkgMutatorProc.running = true
  }

  function _finishPkgMutator(ok, message) {
    const action = pkgPendingAction
    packageOpBusy = false
    packageOpStatus = message
    pkgPendingAction = ""
    pkgPendingPkg = ""
    if (ok && (action === "upgrade" || action === "sync" || action === "install"))
      notePackageUpgrades(-1)
    packageOpFinished(ok, message)
  }

  Process {
    id: pkgResolveProc
    command: ["true"]
    stdout: StdioCollector {
      onStreamFinished: {
        const bin = text.trim()
        if (!bin.length) {
          // Dogfood without install: fall back to terminal + sudo
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
            root.openPacmanTerminal(["sudo", "pacman", "-S", p])
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

    stdout: StdioCollector {
      id: pkgOut
    }
    stderr: StdioCollector {
      id: pkgErr
    }
    onExited: (exitCode, exitStatus) => {
      const out = pkgOut.text.trim()
      const err = pkgErr.text.trim()
      if (exitCode === 0) {
        const last = out.split("\n").filter(l => l.length).pop() || "Done."
        root._finishPkgMutator(true, last)
        return
      }
      if (exitCode === 126 || exitCode === 127) {
        root._finishPkgMutator(false, err || "Authentication cancelled or helper missing.")
        return
      }
      const msg = (err || out).split("\n").filter(l => l.length).pop() || ("Failed (exit " + exitCode + ")")
      root._finishPkgMutator(false, msg)
    }
  }
}
