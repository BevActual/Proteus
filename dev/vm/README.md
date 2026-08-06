# Proteus QEMU/KVM test VM

Vanilla **Arch Linux** guest for building and testing the Proteus distro in isolation from your host Omarchy session.

## Host packages

You need a fuller QEMU install than the minimal `qemu-system-x86` package:

```bash
sudo pacman -S qemu-desktop qemu-img edk2-ovmf
```

(`qemu-desktop` pulls GTK display + virtio bits. `edk2-ovmf` provides UEFI firmware.)

## Layout (modular)

| In repo (`dev/vm/`) | Outside repo (cache) |
|-----------------|----------------------|
| `run.sh`, `download-iso.sh`, `create-disk.sh`, `lib.sh` | ISO, qcow2, OVMF vars, boot extract, socks/logs |
| `guest/` installers | — |
| `README.md` | — |

Default cache: **`~/.cache/proteus-vm`** (`$XDG_CACHE_HOME/proteus-vm`). Override with `PROTEUS_VM_CACHE`. First run of any harness script migrates legacy `dev/vm/iso|disks|boot|vars` into the cache (no overwrite).

## Quick start

```bash
# From the Proteus repo root
./dev/vm/download-iso.sh      # Arch ISO -> $PROTEUS_VM_CACHE/iso/
./dev/vm/create-disk.sh       # 40G qcow2 -> $PROTEUS_VM_CACHE/disks/proteus.qcow2
./dev/vm/run.sh install       # boot ISO + disk (install Arch)
# after install + reboot from disk:
./dev/vm/run.sh               # daily boot
```

### Gamepad / pad (console dogfood)

**Preferred:** pass the host joystick evdev into the guest (works when you are in
the `input` group; no root USB claim):

```bash
# Stop the running guest first (close the QEMU window or kill qemu-system-x86_64)
PROTEUS_VM_PAD=auto ./dev/vm/run.sh
# or pin a node:
PROTEUS_VM_PAD=/dev/input/event20 ./dev/vm/run.sh
```

**Alternate:** full USB passthrough (`usb-host`) — needs **write** on
`/dev/bus/usb/BBB/DDD` (often root-only). Add a udev rule `MODE="0660",
GROUP="input"` for the pad, or use `PROTEUS_VM_PAD` instead:

```bash
PROTEUS_VM_USB=auto ./dev/vm/run.sh          # first Xbox/Sony/Razer/… from lsusb
PROTEUS_VM_USB=1532:0a45 ./dev/vm/run.sh     # e.g. Razer Wolverine V3 TE
```

In the guest: `python-evdev` + `proteus-guide` (via `apply-console-kit.sh`);
`tail -f /run/user/\$UID/proteus-guide.log` should show `watching 1 gamepad(s)`.
Guide button → nav; face buttons / D-pad while console nav is up.

### Steam / RetroArch (console seats)

**Phase 1:** Hyprland kiosk + supervised `proteus-console-seat` (wait for map →
fullscreen by address → reaper). Gamescope only when Vulkan is usable.
**Phase 2 (shipped):** nested Gamescope *session mode* under Hyprland via
`proteus-console-session` Fact + ConsoleBar toggle when `gamescopeUsable` —
does **not** replace Hyprland as sole compositor.

Console software lives in `install/proteus-console.packages` — the overlay
`console` stage installs it (multilib included). Re-apply by hand:

```bash
sudo bash /mnt/proteus/install/machine/install-console-software.sh   # → console stage
# helpers/seed only (not a full package substitute):
sudo bash /mnt/proteus/install/machine/apply-console-kit.sh
# one-command flip + verify (optional --launch browser|retroarch):
bash /mnt/proteus/dev/dogfood/dogfood-console.sh
```

Without sudo, user-local RetroArch cores work under `~/.config/retroarch/cores`
(buildbot zip or Online Updater). Launch from console Games / Library, or:

```bash
proteus-console-seat --expect-class steam -- steam -gamepadui
proteus-console-seat --expect-class 'com.libretro.RetroArch|retroarch' -- retroarch
```

Dogfood checks after launch:

```bash
qs -p /mnt/proteus/shell ipc call chrome state   # surface must stay "console"
tail -f /run/user/$UID/proteus-console-seat.log  # mapped address + fullscreen
hyprctl activewindow -j | head                  # ~fullscreen size
```

`proteus-console-launch` skips Gamescope inside QEMU (no Vulkan); override with
`PROTEUS_FORCE_GAMESCOPE=1` on real hardware. Steam still needs an interactive
login the first time.

### Recommended: base + light overlay

Install path SoT (three layers, knobs, repair, failure table):
[docs/proteus/INSTALL.md](../../docs/proteus/INSTALL.md). VM-specific pad / Steam /
audio detail stays in this file.

```bash
./dev/vm/provision.sh prepare     # ISO + disk in PROTEUS_VM_CACHE
./dev/vm/run.sh install           # if disk empty — Arch live + guest-install.sh
./dev/vm/run.sh                   # boot installed disk
./dev/vm/provision.sh             # SSH → overlay (Hyprland/QS/desktop kit)
./dev/vm/run.sh snapshot hyprland-base
PROTEUS_GUEST=1 ./dev/smoke-all.sh
```

Overlay stages: [`install/`](../../install/). Knobs: `PROTEUS_INSTALL_DESKTOP=0`,
`PROTEUS_INSTALL_SKIP=…`, `PROTEUS_INSTALL_RESUME=1`; fast re-apply:
`sudo bash /mnt/proteus/install/bootstrap.sh repair` (+`PROTEUS_INSTALL_UPDATE=1`).
`./dev/vm/bootstrap.sh` requires **SSH public-key** auth (no password polling).
Empty qcow → `./dev/vm/provision.sh` exits before overlay (`PROTEUS_PROVISION_FORCE=1` to override).
Existing [`install/machine/`](../../install/machine/) scripts remain the mutators the stages call.

## Guest: first Arch install

Inside the live ISO (UEFI):

1. Install with `archinstall` or the [Installation guide](https://wiki.archlinux.org/title/Installation_guide).
2. Create a user, install `openssh`, enable it:
   ```bash
   sudo pacman -S openssh
   sudo systemctl enable --now sshd
   ```
3. Shut down the VM, then boot without the ISO: `./dev/vm/run.sh`
4. From the **host**, SSH in (user created at install; temp password set at install):
   ```bash
   ssh -p 2222 andrew@127.0.0.1
   ```

### Mount the Proteus tree (9p)

The host repo is shared as mount tag `proteus`:

```bash
sudo mkdir -p /mnt/proteus
sudo mount -t 9p -o trans=virtio,version=9p2000.L proteus /mnt/proteus
ls /mnt/proteus
```

Persist in `/etc/fstab` (already set on the `hyprland-base` snapshot disk):

```
proteus  /mnt/proteus  9p  trans=virtio,version=9p2000.L,rw,_netdev  0  0
```

## Guest desktop (Hyprland + Quickshell)

On the `hyprland-base` snapshot (and current disk after setup), the guest has a minimal Wayland stack from official Arch repos:

- **Compositor:** `hyprland`, `xdg-desktop-portal-hyprland`
- **Shell:** `quickshell` (autostarts `quickshell -p /mnt/proteus/shell`)
- **Terminal:** `ghostty`
- **GPU:** `mesa`, `vulkan-virtio` (virtio-vga)
- **Session:** `seatd` (enabled), `polkit` + `hyprpolkitagent` (GUI auth for `pkexec` helpers), PipeWire (`pipewire`, `pipewire-pulse`, `wireplumber`)
- **Qt:** `qt6-base`, `qt6-declarative`, `qt6-wayland`, `qt6-svg`

Guest config lives under `~/.config/hypr/hyprland.conf` (andrew). A convenience symlink is at `~/.config/quickshell/proteus` → `/mnt/proteus/shell`.

### Login (greetd) + lock screen

Cold boot uses **greetd autologin** (`andrew` → `proteus-session`), then Quickshell
shows the **Proteus lock screen** (`lockOnSessionStart`, default on). Unlock with
your user password, or an optional **unlock PIN** (Settings → Users → Lock screen
PIN — numpad on the lock for desktop and console). `Super+L` locks again anytime.

- Config: [`install/machine/assets/greetd-config.toml`](../../install/machine/assets/greetd-config.toml) (`initial_session`)
- Re-apply: `sudo bash /mnt/proteus/install/machine/apply-greeter.sh && sudo systemctl restart greetd`
- After logout, **tuigreet** still appears for account selection

Disable auto-lock on session start in **Settings → Appearance → Lock screen**,
or set `"lockOnSessionStart": false` in `~/.config/proteus/settings.json`.

### Session chrome (Wave 4)

**Compositor (2026-08-06):** `proteus-session` is **smithay only**
(`proteus-compositor-next -c proteus-chrome`). Hyprland is **purged** (no
fail-closed, no Fact rollback). Nested: `./dev/run-nested.sh` (winit).

Dogfood checklist (guest VT or free seat):

1. Confirm Fact + binary: `cat ~/.config/proteus/compositor-engine` → `smithay`;
   `command -v proteus-compositor-next`.
2. Log in via greetd → smithay session (Fact=hyprland refuses).
3. Host/guest smoke: `./dev/smoke/compositor-next-dogfood.sh`.
4. Nested on host: `./dev/run-nested.sh` (never Hyprland).

Default chrome: compositor `-c` → `proteus-chrome` (owned iced
`proteus-shell`).

### Console posture (dogfood)

```bash
sudo bash /mnt/proteus/install/machine/apply-console-kit.sh   # once
/mnt/proteus/shell/scripts/proteus-posture console         # prefer live tree
```

Hard flip writes `~/.config/proteus/posture` and — inside a managed session
(started via `proteus-session`) — **ends the session**: the greeter shows and
the next login picks the engine from the Facts (Hyprland kiosk, or the
Gamescope session when capabilities allow). Outside a managed session (SSH /
nested dev) the legacy in-place chrome flip is used so automation keeps
working. Return via console Desktop seat / CC Desktop tile /
`proteus-posture desktop`. See
[docs/proteus/POSTURES.md](../../docs/proteus/POSTURES.md) ·
[CURRENT.md](../../docs/proteus/CURRENT.md).

### GPU passthrough (VFIO) — Gamescope session prove path

VirGL has no hardware Vulkan, so the VM console stays interim (Hyprland kiosk
+ bare seats). To dogfood the **Gamescope-owned console session** in the same
disk/SSH loop, pass a host GPU through:

1. **IOMMU on** — kernel cmdline `intel_iommu=on` / `amd_iommu=on`
   (+ `iommu=pt`); verify groups: `find /sys/kernel/iommu_groups -type l`.
2. **Bind the GPU to vfio-pci** (host) — e.g. for `0000:01:00.0` (+ its audio
   function `.1`): `modprobe vfio-pci` then either kernel cmdline
   `vfio-pci.ids=VVVV:DDDD,VVVV:DDDD` (from `lspci -nn`) or a driverctl
   override. The GPU must not be driving the host desktop.
3. **Boot with the device:**

```bash
PROTEUS_VM_VFIO=0000:01:00.0,0000:01:00.1 ./dev/vm/run.sh
# GPU as the only display (attach a monitor to it, or use Looking Glass):
PROTEUS_VM_VFIO=… PROTEUS_VM_VFIO_PRIMARY=1 ./dev/vm/run.sh
```

4. **Verify in the guest** — `proteus-console-capabilities` must report
   `"vulkanHw": true` and `"gamescopeUsable": true`; then
   `proteus-console-session set-mode session` and
   `PROTEUS_EXPECT_GS_SESSION=1 bash /mnt/proteus/dev/dogfood/dogfood-console.sh`
   asserts `replacesHyprland`. The next console login lands in the Gamescope
   session (Proteus Home + Guide focus-flip).

Pad still rides `PROTEUS_VM_PAD=auto`. This harness is the bridge toward
hosting game instances under host posture later; that product UI is out of
scope here.

### Start a graphical session (manual / debug)

If greetd is not running, log in on a TTY and run:

```bash
~/start-proteus.sh
```

   Or simply `Hyprland` if `/mnt/proteus` is already mounted.

Optional auto-start on tty1: `touch ~/.proteus-autostart-hyprland` (see `~/.bash_profile`). SSH logins are unaffected.

Useful binds: `Super+Return` → `proteus-terminal` (Ghostty + VM GL workaround), `Super+Space` Beacon (system search), `Super+,` Settings, `Super+Shift+E` exit Hyprland. Rebind in **Settings → Peripherals → Keyboard** (writes `~/.config/hypr/proteus-keybinds.conf`). Desktop/Displays write `proteus-general.conf` / `proteus-monitors.conf`. First-time guest wiring:

```bash
bash /mnt/proteus/install/machine/install-keybinds.sh
bash /mnt/proteus/install/machine/install-desktop-conf.sh
# or all of the above via:
# Build mutators / helpers on the host first if needed:
#   (cd services/proteus-pkg && cargo build --release)
#   (cd services/proteus-logind && cargo build --release)
#   (cd services/proteus-audio-mix && cargo build --release && mkdir -p bin && cp target/release/proteus-audio-mix bin/)
bash /mnt/proteus/install/machine/install-settings-app.sh
# (also runs hide-system-apps.sh — Settings-covered tools + Quickshell hidden; Calculator stays)
# Overlay apps + post-install re-run hide-system-apps idempotently.
# or just the helpers:
#   sudo bash /mnt/proteus/install/machine/install-proteus-pkg.sh
#   sudo bash /mnt/proteus/install/machine/install-proteus-logind.sh
#   sudo bash /mnt/proteus/install/machine/install-proteus-audio-mix.sh
# LocalSend (AUR localsend-bin) — keep the terminal open until Done:
#   bash /mnt/proteus/install/machine/install-localsend-native.sh
#   bash /mnt/proteus/install/machine/repair-localsend-native.sh   # empty .so / interrupted yay
```

### Notes / blockers

- Full Hyprland + Quickshell needs the **QEMU display window**, not SSH alone (no Wayland over plain SSH).
- **Lag / GPU:** default tries `virtio-vga-gl` + `gtk,gl=on` (VirGL). That helps most on **AMD/Intel Mesa**. On **NVIDIA proprietary** drivers (especially Wayland hosts), VirGL often fails or stutters — use `PROTEUS_VM_GL=0 ./dev/vm/run.sh` (software `virtio-vga`; expect jank) or dogfood with `./dev/run-nested.sh` on the host instead. Guest packages: `mesa` + `vulkan-virtio`.
- **Audio quality (honest):** crackle under a VirGL guest desktop is mostly a **guest emulated-HDA soft limit**, not a broken host codec.
  - **What works:** host headphones + non-VM audio are fine. Default path is `ich9-intel-hda` → host **Pulse** (`PROTEUS_VM_AUDIO=pa`) at **48 kHz** with a **~200 ms** audiodev buffer. Guest Settings → Sound latency **High** (PipeWire quantum ~1024) is required. Host `pw-top` typically shows **ERR=0** for `qemu` / EVO4 while the guest ALSA HDA node racks up **ERR** under load — so host underrun chasing does not fix this.
  - **Strong signal:** with `PROTEUS_VM_GL=0`, guest HDA `ERR` drops near zero (audio becomes much cleaner) while QEMU CPU stays high — points at VirGL/scheduling vs ich9-HDA, not sample-rate mismatch. Tradeoff: software `virtio-vga` makes Hyprland feel laggy.
  - **What does not reliably fix crackle:** larger `PROTEUS_VM_AUDIO_BUFFER` (400–500 ms), swapping `pa` ↔ native `pipewire` ↔ `sdl`. Those help host-side underruns; they do not stop guest HDA xruns under VirGL.
  - **Accept for VM dogfood:** mild crackle with VirGL on is expected. Prefer `./dev/run-nested.sh` on the host when audio quality matters. Keep `PROTEUS_VM_AUDIO=pa` + High latency as the best available default.
  - **Escapes:** `PROTEUS_VM_AUDIO_BUFFER` / `PROTEUS_VM_AUDIO_TIMER`; `PROTEUS_VM_AUDIO=pipewire|sdl|0`; `PROTEUS_VM_GL=0` for an audio A/B; experimental `PROTEUS_VM_SOUND=virtio` (`virtio-sound-pci` — QEMU supports it; guest `virtio_snd` loads, but WirePlumber often stays on `auto_null` unless the session can open the card — not dogfood-ready yet).
- Host already runs a Wayland session; one VM is enough — extra `qemu-system` processes steal CPU.
- Shell loads from **9p** (`/mnt/proteus`); heavy Settings/hyprctl spam can feel sticky even with GL.

## Snapshots

```bash
./dev/vm/run.sh snapshot clean-base     # after a good install
./dev/vm/run.sh snapshot hyprland-base  # after Hyprland + Quickshell guest setup
./dev/vm/run.sh snapshots
./dev/vm/run.sh restore clean-base      # roll back the qcow2
./dev/vm/run.sh restore hyprland-base
```

Shut the guest down cleanly before snapshot/restore when possible.

## Tunables (env)

| Variable | Default | Meaning |
|----------|---------|---------|
| `PROTEUS_VM_CACHE` | `~/.cache/proteus-vm` | ISO, disks, vars, boot, runtime socks/logs |
| `PROTEUS_VM_CPUS` | `6` | vCPU count |
| `PROTEUS_VM_MEM` | `8G` | RAM |
| `PROTEUS_VM_SSH_PORT` | `2222` | Host port → guest `:22` |
| `PROTEUS_VM_GL` | `1` | `1` = `virtio-vga-gl` + VirGL display; `0` = plain `virtio-vga` |
| `PROTEUS_VM_AUDIO` | `pa` | Host audiodev: `pa` (default), `pipewire`, `sdl`, or `0` to disable |
| `PROTEUS_VM_AUDIO_BUFFER` | `200000` | Audiodev `out`/`in` buffer-length (μs); host-side only — limited help vs VirGL HDA crackle |
| `PROTEUS_VM_AUDIO_TIMER` | `20000` | Audiodev `timer-period` (μs) |
| `PROTEUS_VM_SOUND` | `hda` | Guest device: `hda` (`ich9-intel-hda`, default) or experimental `virtio` |
| `PROTEUS_VM_DISPLAY` | (auto) | Override QEMU `-display` (default `gtk,gl=on,zoom-to-fit=on` when GL on) |
| `ARCH_MIRROR` | geo mirror | ISO download base |
| `OVMF_CODE` / `OVMF_VARS_TEMPLATE` | `/usr/share/edk2/x64/…` | UEFI firmware paths |

## Cache layout (`PROTEUS_VM_CACHE`)

| Path | Role |
|------|------|
| `iso/` | Arch ISO + checksums |
| `disks/` | qcow2 images |
| `vars/` | per-VM UEFI NVRAM |
| `boot/` | extracted kernel/initrd (direct-kernel install) |
| `runtime/` | qmp/serial socks, qemu logs |

Repo `dev/vm/` stays harness + `guest/` only. Scripts and docs are what you push; disks/ISOs stay on the machine.
