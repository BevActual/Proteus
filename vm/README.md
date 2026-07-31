# Proteus QEMU/KVM test VM

Vanilla **Arch Linux** guest for building and testing the Proteus distro in isolation from your host Omarchy session.

## Host packages

You need a fuller QEMU install than the minimal `qemu-system-x86` package:

```bash
sudo pacman -S qemu-desktop qemu-img edk2-ovmf
```

(`qemu-desktop` pulls GTK display + virtio bits. `edk2-ovmf` provides UEFI firmware.)

## Layout (modular)

| In repo (`vm/`) | Outside repo (cache) |
|-----------------|----------------------|
| `run.sh`, `download-iso.sh`, `create-disk.sh`, `lib.sh` | ISO, qcow2, OVMF vars, boot extract, socks/logs |
| `guest/` installers | — |
| `README.md` | — |

Default cache: **`~/.cache/proteus-vm`** (`$XDG_CACHE_HOME/proteus-vm`). Override with `PROTEUS_VM_CACHE`. First run of any harness script migrates legacy `vm/iso|disks|boot|vars` into the cache (no overwrite).

## Quick start

```bash
# From the Proteus repo root
./vm/download-iso.sh      # Arch ISO -> $PROTEUS_VM_CACHE/iso/
./vm/create-disk.sh       # 40G qcow2 -> $PROTEUS_VM_CACHE/disks/proteus.qcow2
./vm/run.sh install       # boot ISO + disk (install Arch)
# after install + reboot from disk:
./vm/run.sh               # daily boot
```

### Recommended: base + light overlay

```bash
./vm/provision.sh prepare     # ISO + disk in PROTEUS_VM_CACHE
./vm/run.sh install           # if disk empty — Arch live + guest-install.sh
./vm/run.sh                   # boot installed disk
./vm/provision.sh             # SSH → overlay (Hyprland/QS/desktop kit)
./vm/run.sh snapshot hyprland-base
PROTEUS_GUEST=1 ./scripts/smoke-all.sh
```

Overlay stages: [`vm/install/`](install/). Knobs: `PROTEUS_INSTALL_DESKTOP=0`,
`PROTEUS_INSTALL_SKIP=…`, `PROTEUS_INSTALL_RESUME=1`.
`./vm/bootstrap.sh` requires **SSH public-key** auth (no password polling).
Empty qcow → `./vm/provision.sh` exits before overlay (`PROTEUS_PROVISION_FORCE=1` to override).
Existing [`vm/guest/`](guest/) scripts remain the mutators the stages call.

## Guest: first Arch install

Inside the live ISO (UEFI):

1. Install with `archinstall` or the [Installation guide](https://wiki.archlinux.org/title/Installation_guide).
2. Create a user, install `openssh`, enable it:
   ```bash
   sudo pacman -S openssh
   sudo systemctl enable --now sshd
   ```
3. Shut down the VM, then boot without the ISO: `./vm/run.sh`
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
- **Session:** `seatd` (enabled), `polkit`, PipeWire (`pipewire`, `pipewire-pulse`, `wireplumber`)
- **Qt:** `qt6-base`, `qt6-declarative`, `qt6-wayland`, `qt6-svg`

Guest config lives under `~/.config/hypr/hyprland.conf` (andrew). A convenience symlink is at `~/.config/quickshell/proteus` → `/mnt/proteus/shell`.

### Login (greetd) + lock screen

Cold boot uses **greetd autologin** (`andrew` → `proteus-session`), then Quickshell
shows the **Proteus lock screen** (`lockOnSessionStart`, default on). Unlock with
your user password. `Super+L` locks again anytime.

- Config: [`vm/guest/greetd-config.toml`](guest/greetd-config.toml) (`initial_session`)
- Re-apply: `sudo bash /mnt/proteus/vm/guest/apply-greeter.sh && sudo systemctl restart greetd`
- After logout, **tuigreet** still appears for account selection

Disable auto-lock on session start by setting `"lockOnSessionStart": false` in
`~/.config/proteus/settings.json` (Settings UI later).

### Quickshell chrome supervisor

Default: Hyprland `exec-once` → `proteus-qs` (flock / backoff / `--restart`).
Optional: `bash /mnt/proteus/vm/guest/install-proteus-qs-user-unit.sh` then
`systemctl --user enable --now proteus-qs.service` (comment out the hypr
`exec-once` line). After upgrading Quickshell: `PROTEUS_GUEST=1 ./scripts/smoke-all.sh`
(records version; do not IgnorePkg-pin on rolling Arch).

### Start a graphical session (manual / debug)

If greetd is not running, log in on a TTY and run:

```bash
~/start-proteus.sh
```

   Or simply `Hyprland` if `/mnt/proteus` is already mounted.

Optional auto-start on tty1: `touch ~/.proteus-autostart-hyprland` (see `~/.bash_profile`). SSH logins are unaffected.

Useful binds: `Super+Return` → `proteus-terminal` (Ghostty + VM GL workaround), `Super+Space` launcher, `Super+,` Settings, `Super+Shift+E` exit Hyprland. Rebind in **Settings → Keyboard** (writes `~/.config/hypr/proteus-keybinds.conf`). Desktop/Displays write `proteus-general.conf` / `proteus-monitors.conf`. First-time guest wiring:

```bash
bash /mnt/proteus/vm/guest/install-keybinds.sh
bash /mnt/proteus/vm/guest/install-desktop-conf.sh
# or all of the above via:
# Build mutators / helpers on the host first if needed:
#   (cd services/proteus-pkg && cargo build --release)
#   (cd services/proteus-logind && cargo build --release)
#   (cd services/proteus-audio-mix && cargo build --release && mkdir -p bin && cp target/release/proteus-audio-mix bin/)
bash /mnt/proteus/vm/guest/install-settings-app.sh
# (also runs hide-system-apps.sh — Settings-covered tools + Quickshell hidden; Calculator stays)
# Overlay apps + post-install re-run hide-system-apps idempotently.
# or just the helpers:
#   sudo bash /mnt/proteus/vm/guest/install-proteus-pkg.sh
#   sudo bash /mnt/proteus/vm/guest/install-proteus-logind.sh
#   sudo bash /mnt/proteus/vm/guest/install-proteus-audio-mix.sh
```

### Notes / blockers

- Full Hyprland + Quickshell needs the **QEMU display window**, not SSH alone (no Wayland over plain SSH).
- **Lag / GPU:** default tries `virtio-vga-gl` + `gtk,gl=on` (VirGL). That helps most on **AMD/Intel Mesa**. On **NVIDIA proprietary** drivers (especially Wayland hosts), VirGL often fails or stutters — use `PROTEUS_VM_GL=0 ./vm/run.sh` (software `virtio-vga`; expect jank) or dogfood with `./scripts/run-nested.sh` on the host instead. Guest packages: `mesa` + `vulkan-virtio`.
- **Audio quality (honest):** crackle under a VirGL guest desktop is mostly a **guest emulated-HDA soft limit**, not a broken host codec.
  - **What works:** host headphones + non-VM audio are fine. Default path is `ich9-intel-hda` → host **Pulse** (`PROTEUS_VM_AUDIO=pa`) at **48 kHz** with a **~200 ms** audiodev buffer. Guest Settings → Sound latency **High** (PipeWire quantum ~1024) is required. Host `pw-top` typically shows **ERR=0** for `qemu` / EVO4 while the guest ALSA HDA node racks up **ERR** under load — so host underrun chasing does not fix this.
  - **Strong signal:** with `PROTEUS_VM_GL=0`, guest HDA `ERR` drops near zero (audio becomes much cleaner) while QEMU CPU stays high — points at VirGL/scheduling vs ich9-HDA, not sample-rate mismatch. Tradeoff: software `virtio-vga` makes Hyprland feel laggy.
  - **What does not reliably fix crackle:** larger `PROTEUS_VM_AUDIO_BUFFER` (400–500 ms), swapping `pa` ↔ native `pipewire` ↔ `sdl`. Those help host-side underruns; they do not stop guest HDA xruns under VirGL.
  - **Accept for VM dogfood:** mild crackle with VirGL on is expected. Prefer `./scripts/run-nested.sh` on the host when audio quality matters. Keep `PROTEUS_VM_AUDIO=pa` + High latency as the best available default.
  - **Escapes:** `PROTEUS_VM_AUDIO_BUFFER` / `PROTEUS_VM_AUDIO_TIMER`; `PROTEUS_VM_AUDIO=pipewire|sdl|0`; `PROTEUS_VM_GL=0` for an audio A/B; experimental `PROTEUS_VM_SOUND=virtio` (`virtio-sound-pci` — QEMU supports it; guest `virtio_snd` loads, but WirePlumber often stays on `auto_null` unless the session can open the card — not dogfood-ready yet).
- Host already runs a Wayland session; one VM is enough — extra `qemu-system` processes steal CPU.
- Shell loads from **9p** (`/mnt/proteus`); heavy Settings/hyprctl spam can feel sticky even with GL.

## Snapshots

```bash
./vm/run.sh snapshot clean-base     # after a good install
./vm/run.sh snapshot hyprland-base  # after Hyprland + Quickshell guest setup
./vm/run.sh snapshots
./vm/run.sh restore clean-base      # roll back the qcow2
./vm/run.sh restore hyprland-base
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

Repo `vm/` stays harness + `guest/` only. Scripts and docs are what you push; disks/ISOs stay on the machine.
