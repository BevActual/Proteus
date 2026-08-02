# INSTALL — Proteus dogfood install path (SoT)

Single map of how a machine (today: the QEMU VM) becomes a Proteus dogfood
session. **This is not a product ISO** — no Calamares-class installer exists
or is planned yet ([CURRENT.md](CURRENT.md) §8). Dogfood = vanilla Arch base +
the `vm/install/` overlay.

## The three layers (people keep conflating these)

| Layer | Entry | Runs where | Role |
|-------|--------|-----------|------|
| Base Arch | [`vm/guest-install.sh`](../../vm/guest-install.sh) | Live ISO (guest, root) | Unattended disk: partition, pacstrap, user, sshd |
| Overlay | [`vm/install/bootstrap.sh`](../../vm/install/bootstrap.sh) | Installed guest (sudo) | Hyprland / Quickshell / Settings / desktop + console kit |
| Host drive | [`vm/provision.sh`](../../vm/provision.sh) → [`vm/bootstrap.sh`](../../vm/bootstrap.sh) | Host | Cache ISO/disk, wait for SSH, run the overlay remotely |

Overlay stages (detail: [vm/install/README.md](../../vm/install/README.md)):
`preflight → packaging → config → hardware → login → apps → desktop → console → post-install`.

## Happy path (empty cache → console dogfood)

```bash
./vm/provision.sh prepare        # 1. Arch ISO + 40G qcow2 into PROTEUS_VM_CACHE
./vm/run.sh install              # 2. boot live ISO + disk
# in the live ISO:
#   mount -t 9p -o trans=virtio,version=9p2000.L proteus /mnt/proteus  (usually automatic)
#   bash /mnt/proteus/vm/guest-install.sh
./vm/run.sh                      # 3. reboot into the installed disk
ssh-copy-id -p 2222 andrew@127.0.0.1   # 4. once — host bootstrap is publickey-only
./vm/provision.sh                # 5. SSH → overlay (all stages incl. console)
./vm/run.sh snapshot hyprland-base
PROTEUS_GUEST=1 ./scripts/smoke-all.sh
```

Or run the overlay directly on the guest: `sudo bash /mnt/proteus/vm/install/bootstrap.sh`.

## Overlay knobs (`PROTEUS_INSTALL_*`)

| Env / arg | Effect |
|-----------|--------|
| `bootstrap.sh repair` / `PROTEUS_INSTALL_REPAIR=1` | Fast preset: only `config → apps → console` (re-seed configs, re-link live helpers, fix posture/profile drift; no pacman stages) |
| `PROTEUS_INSTALL_UPDATE=1` | With repair or full run: `pacman -Syu` + re-apply all package lists (`--needed`) so preinstalled apps come current |
| `PROTEUS_INSTALL_DESKTOP=0` | Skip Chromium/Nautilus desktop kit |
| `PROTEUS_INSTALL_SKIP=hardware,console` | Skip named stages |
| `PROTEUS_INSTALL_ONLY=console` | Run one stage |
| `PROTEUS_INSTALL_RESUME=1` | Honor `.done` markers (default: plain re-run re-executes everything — that *is* the full repair) |
| `PROTEUS_INSTALL_LOG=` / `PROTEUS_INSTALL_STATUS_DIR=` | Log / status-marker paths |

Package sets: [`proteus-base.packages`](../../vm/install/proteus-base.packages)
(session stack) · [`proteus-desktop.packages`](../../vm/install/proteus-desktop.packages)
(browser, files, viewers, capture) · [`proteus-console.packages`](../../vm/install/proteus-console.packages)
(Gamescope, Steam + lib32, RetroArch + cores, pad udev rules — needs multilib,
which the `console` stage enables).

## Console dogfood after the overlay

The `console` stage (and the earlier `apps` stage) put the seat kit on PATH —
`proteus-console-seat`, `proteus-console-capabilities`, `proteus-console-launch`
(symlinked to the live tree when `PROTEUS_ROOT=/mnt/proteus`) — and seeds
`console.conf`. Then:

```bash
proteus-posture console          # hard flip (fact + hypr profile + chrome restart)
proteus-console-seat --expect-class steam -- steam -gamepadui
# seat map/fullscreen trail:
#   tail -f /run/user/$UID/proteus-console-seat.log
```

Phase 1 = supervised seats + capabilities probe (Gamescope only when
`gamescopeUsable`; QEMU/VirGL typically bare kiosk). **Phase 2** Gamescope
*session* is Out. Pad passthrough (`PROTEUS_VM_PAD=auto`), Steam/RetroArch
specifics, and VM audio/GL caveats live in [vm/README.md](../../vm/README.md).

## Honesty / expectations

- **Not a product ISO.** `guest-install.sh` is a VM-shaped unattended Arch
  install; real-hardware installs are manual Arch + overlay.
- **Host bootstrap needs SSH key auth** (`BatchMode` — password prompts are
  never polled; `ssh-copy-id` first).
- **Re-running the overlay is safe** — stages are idempotent, pacman uses
  `--needed`; `bootstrap.sh repair` is the fast path when only configs/helpers
  drifted.
- **Stale `/usr/local/bin` helpers** were a real bug class; when the tree is
  live at `/mnt/proteus`, helpers are symlinks and cannot go stale.
- **Lock unlock PIN** — `apps` stage puts `proteus-pin.py` + `check-unlock.py`
  on PATH (module `proteus_auth.py` stays beside them in `shell/scripts/`).
  Hash lives under `~/.local/share/proteus/auth/pin` (0600), never
  `settings.json`. Optional PAM service `proteus-lock` is installed from
  `shell/pam/proteus-lock` via `vm/guest/install-lock-pam.sh`; if that step
  skips (no `system-auth`), the lock falls back to the `login` PAM stack.
- **Beacon Files index** — `apps` stage puts `beacon-file-index.py` on PATH.
  Cache: `~/.cache/proteus/beacon-files.json` (fd preferred, `os.walk`
  fallback; depth ≤5). `fd` / `wtype` are optional — without `wtype`,
  clipboard paste is copy-only.

## Failure table

| Symptom | Cause → fix |
|---------|-------------|
| `provision.sh` refuses: "disk looks empty" | Base Arch never installed → `./vm/run.sh install` + `guest-install.sh` first (`./vm/provision.sh status` to inspect) |
| `vm/bootstrap: FAIL SSH unreachable` | Guest down, sshd off, or no key auth → boot guest, `ssh-copy-id -p 2222 andrew@127.0.0.1` |
| Apps launch in desktop chrome while posture says console | Fact ≠ hypr profile drift → `bootstrap.sh repair` or `proteus-posture console` (seat also self-heals) |
| Steam missing after overlay | multilib not enabled / `console` stage skipped → re-run overlay or `PROTEUS_INSTALL_ONLY=console` |
| Gamescope exits instantly in the VM | No Vulkan under QEMU/VirGL → expected; seats run bare (`proteus-console-capabilities` reports `gamescope_usable:false`) |
| Helpers on PATH behave stale | Copied (not linked) bins from an old run → `bootstrap.sh repair` re-links from the live tree |
