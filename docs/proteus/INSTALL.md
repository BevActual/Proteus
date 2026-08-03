# INSTALL — Proteus dogfood install path (SoT)

Single map of how a machine (QEMU VM **or bare metal**) becomes a Proteus
dogfood session. **This is not a product ISO** — no Calamares-class installer
exists or is planned yet ([CURRENT.md](CURRENT.md) §8). Dogfood = vanilla Arch
base + the `vm/install/` overlay.

> **Naming:** the overlay lives under `vm/` for historical reasons and now
> installs bare-metal machines too. Rename is queued, not done.

## The three layers (people keep conflating these)

| Layer | Entry | Runs where | Role |
|-------|--------|-----------|------|
| Base Arch | [`vm/guest-install.sh`](../../vm/guest-install.sh) (VM) · manual Arch (bare metal) | Live ISO, root | Unattended disk: partition, pacstrap, user, sshd |
| Overlay | [`vm/install/bootstrap.sh`](../../vm/install/bootstrap.sh) | Installed machine (sudo) | Hyprland / Quickshell / Settings / desktop + console kit |
| Host drive | [`vm/provision.sh`](../../vm/provision.sh) → [`vm/bootstrap.sh`](../../vm/bootstrap.sh) | Host | Cache ISO/disk, wait for SSH, run the overlay remotely (VM only) |

Overlay stages (detail: [vm/install/README.md](../../vm/install/README.md)):
`preflight → snapshots → packaging → config → hardware → login → apps → desktop → console → host → post-install`.

## Bare metal

The overlay is path-agnostic: it installs from wherever the tree is checked
out. There is no 9p share and no `/mnt/proteus`.

```bash
# 1. Install vanilla Arch by hand (archinstall or the ArchWiki guide).
#    btrfs root with an @ subvolume layout is recommended — it is what the
#    `snapshots` stage needs to give you a rollback net.
# 2. Clone the tree, then run the overlay against it:
git clone <proteus-remote> ~/Projects/Proteus
cd ~/Projects/Proteus
PROTEUS_ROOT="$PWD" sudo -E bash vm/install/bootstrap.sh
```

`sudo -E` matters — the overlay reads `PROTEUS_ROOT` from the environment.

### How the install root is found at login

greetd starts `proteus-session` with a **clean environment**, so `PROTEUS_ROOT`
is not inherited. The root is therefore a Fact on disk, like `posture` and
`host-chrome`:

| Order | Source | Written by |
|-------|--------|------------|
| 1 | `PROTEUS_ROOT` in the environment | dev shells, nested, SSH automation |
| 2 | `~/.config/proteus/root` | `vm/install/config.sh` |
| 3 | self-locate — `/usr/local/bin` helpers are symlinks into the live tree | `proteus_install_helper` |
| 4 | `/mnt/proteus` | VM 9p share |

Every candidate is validated (`<root>/shell` must exist) before it is accepted,
so a stale Fact after moving the tree degrades to the next source instead of
stranding the session. `config.sh` also seeds `env = PROTEUS_ROOT,…` into
`hyprland.conf` for processes the compositor spawns.

**Moved the checkout?** Re-run `bootstrap.sh repair` — it rewrites the Fact, the
hypr env line, and every `/usr/local/bin` symlink.

### Helpers: symlink vs copy

`proteus_install_helper` symlinks `/usr/local/bin/*` into the live tree so edits
take effect without reinstalling (copies going stale was a real bug class). On
bare metal that points root-invoked helpers at a user-writable checkout — fine
for a single-operator dogfood box, **not** appropriate on a shared machine. Set
`PROTEUS_INSTALL_COPY_HELPERS=1` to force copies and accept the staleness.

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
| `PROTEUS_INSTALL_SNAPSHOTS=0` | Skip the `snapshots` stage (no btrfs rollback net) |
| `PROTEUS_SNAPSHOT_BOOT=1` | Also install `grub-btrfs` (GRUB systems only) |
| `PROTEUS_INSTALL_COPY_HELPERS=1` | Copy helpers into `/usr/local/bin` instead of symlinking the live tree |

## Snapshots (bare-metal rollback net)

The VM has `./vm/run.sh snapshot|restore`. Bare metal gets the equivalent from
the `snapshots` stage, which runs **immediately after preflight** so its
baseline is genuinely "before Proteus touched this machine."

| Piece | Role |
|-------|------|
| `snapper` + `root` config | Timeline snapshots, dogfood-shaped retention (6 hourly / 7 daily / 4 weekly) |
| `snap-pac` | Pre/post snapshot around **every** pacman transaction — the highest-value piece on rolling Arch |
| `proteus:baseline` snapshot | Tagged pre-overlay restore point |
| `proteus-snapshot` | Thin Proteus vocabulary over snapper — `status` · `list` · `create` · `pre-flip` · `rollback` |
| `grub-btrfs` (opt-in) | Boot directly into a snapshot from the GRUB menu |

`proteus-posture` takes a `pre-flip` snapshot before every hard switch
(`PROTEUS_POSTURE_SNAPSHOT=0` to disable). It is best-effort and never blocks a
flip.

**Honesty gates:** root not btrfs → stage logs and skips, no fake net. `snapper`
missing or unconfigured → skip. `proteus-snapshot status` always states what is
*not* covered — notably that without `grub-btrfs` an unbootable system needs a
live USB, and that `rollback` does not restore `/home`, `/boot`, or anything
written after the snapshot.

`rollback` is a **dry run by default**: it prints the plan and the exclusions,
and only executes with `--yes`.

Package sets: [`proteus-base.packages`](../../vm/install/proteus-base.packages)
(session stack) · [`proteus-desktop.packages`](../../vm/install/proteus-desktop.packages)
(browser, files, viewers, capture) · [`proteus-console.packages`](../../vm/install/proteus-console.packages)
(Gamescope, Steam + lib32, RetroArch + cores, pad udev rules, focus-router X
tools + vulkan-tools — needs multilib, which the `console` stage enables) ·
[`proteus-host.packages`](../../vm/install/proteus-host.packages)
(samba + smartmontools — the `host` stage also seeds the usershares dir,
`sambashare` group, smb service and a read-only `smartctl -jH` sudoers drop
for the host dashboard).

## Console dogfood after the overlay

The `console` stage (and the earlier `apps` stage) put the seat kit on PATH —
`proteus-console-seat`, `proteus-console-capabilities`, `proteus-console-launch`,
`proteus-console-session`, `proteus-console-gs-session`, `proteus-console-focus`
(symlinked to the live tree when `PROTEUS_ROOT=/mnt/proteus`) — and seeds
`console.conf`. With hardware Vulkan (bare metal / VFIO passthrough — see
[vm/README.md](../../vm/README.md) §VFIO) and
`proteus-console-session set-mode session`, the next console login boots the
**Gamescope session** (Proteus Home + Guide focus-flip) instead of the
Hyprland kiosk.

### Flip to console and launch a title

```bash
# Preferred one-command (Fact + profile + chrome.surface === console)
bash /mnt/proteus/vm/guest/dogfood-console.sh
bash /mnt/proteus/vm/guest/dogfood-console.sh --launch retroarch   # optional seat
bash /mnt/proteus/vm/guest/dogfood-console.sh --restore            # back to desktop

# Manual equivalent
proteus-posture console
proteus-console-seat --expect-class steam -- steam -gamepadui
# trail: tail -f /run/user/$UID/proteus-console-seat.log
# chrome: qs -p /mnt/proteus/shell ipc call chrome state
```

**Repair vs full packages:** `apply-console-kit.sh` = helpers/seed (+ best-effort
pkgs). Full Steam/RetroArch/cores/udev = overlay `console` stage or
`sudo bash /mnt/proteus/vm/guest/install-console-software.sh`.

Phase 1 = supervised seats + capabilities probe (Gamescope only when
`gamescopeUsable`; QEMU/VirGL typically bare kiosk). **Phase 2** = nested
session Fact via `proteus-console-session` (`seat`\|`gamescope`) + launch
adaptive flags + ConsoleBar toggle — still nested under Hyprland (sole
Gamescope compositor Out). Pad passthrough (`PROTEUS_VM_PAD=auto`),
Steam/RetroArch specifics, and VM audio/GL caveats live in
[vm/README.md](../../vm/README.md). Guest gate:
`./scripts/smoke/console-guest-smoke.sh` (SKIP unless SSH / `PROTEUS_GUEST=1`).

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
| Bare metal: login lands in a bare compositor, no chrome | `proteus-session` could not resolve the root → check `cat ~/.config/proteus/root`, then `bootstrap.sh repair` |
| Bare metal: moved the checkout, session broke | Stale root Fact → re-run `PROTEUS_ROOT="$PWD" sudo -E bash vm/install/bootstrap.sh repair` |
| `proteus-snapshot status` says unavailable | Root is not btrfs, or no snapper `root` config → run the `snapshots` stage, or accept no rollback net |
| Console reports `gamescope_usable:false` on real hardware | Missing 32-bit Vulkan driver → enable multilib (the `console` stage does) then re-run `PROTEUS_INSTALL_ONLY=hardware` |
| Settings → Software → AUR / Flathub panes stay empty | No AUR helper / no `flatpak` → run the `desktop` stage (bootstraps `yay-bin`); `flatpak` now ships in the base list |
