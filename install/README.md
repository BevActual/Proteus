# install/ — Proteus dogfood overlay (Omarchy-shaped, light)

Not a product ISO. After bare Arch (`guest-install.sh` or manual), this
pipeline turns the guest into a Hyprland + Quickshell dogfood session.
Full install path (all three layers): [docs/proteus/INSTALL.md](../docs/proteus/INSTALL.md).

```
# Host (after guest has Arch + SSH + 9p):
./dev/vm/provision.sh                 # prepare ISO/disk hints + overlay over SSH
./dev/vm/bootstrap.sh                 # overlay only

# On guest:
sudo bash /mnt/proteus/install/bootstrap.sh
```

## Stages

| Stage | Role |
|-------|------|
| `preflight.sh` | 9p mount unit, paths |
| `packaging.sh` | [`proteus-base.packages`](./proteus-base.packages) — session stack |
| `config.sh` | seatd, QS symlink, hypr/ghostty/fastfetch seeds, hypridle |
| `hardware.sh` | Detect GPU → optional drivers (`hardware/*`) |
| `login.sh` | greetd / `proteus-session` |
| `apps.sh` | Settings (iced), keybinds, desktop conf, PAM, `hide-system-apps`, helper bins (symlinked to the live tree under `/mnt/proteus`) |
| `desktop.sh` | [`proteus-desktop.packages`](./proteus-desktop.packages) (default on) |
| `console.sh` | multilib + [`proteus-console.packages`](./proteus-console.packages) (Steam/RetroArch/cores/pads), `apply-console-kit` seed, posture↔profile drift fix |
| `host.sh` | [`proteus-host.packages`](./proteus-host.packages) (samba + smartmontools + nvme-cli + podman), usershares dir + `sambashare` group + smb enable, read-only `smartctl -jH` sudoers drop |
| `post-install.sh` | status file + next steps; refresh `hide-system-apps` |

## Knobs

| Env / arg | Effect |
|-----------|--------|
| `bootstrap.sh repair` / `PROTEUS_INSTALL_REPAIR=1` | Fast preset: only `config → apps → console` (configs/helpers/drift; no pacman stages) |
| `PROTEUS_INSTALL_UPDATE=1` | After stages: `pacman -Syu` + re-apply package lists (`--needed`) |
| `PROTEUS_INSTALL_DESKTOP=0` | Skip Chromium/Nautilus kit |
| `PROTEUS_INSTALL_SKIP=hardware,console` | Skip named stages |
| `PROTEUS_INSTALL_ONLY=desktop` | Run one stage |
| `PROTEUS_INSTALL_RESUME=1` | Skip stages with `/var/lib/proteus/install/*.done` |
| `PROTEUS_INSTALL_LOG=` | Override log path (default `/var/log/proteus-install.log`) |
| `PROTEUS_INSTALL_STATUS_DIR=` | Override resume/status dir (default `/var/lib/proteus/install`) |

Pacman uses `--needed` and skips the transaction when every package is already
installed. Markers under the status dir.

Host tree check (no guest):

```bash
./install/check.sh
```

## Package sets

| File | Contents |
|------|----------|
| `proteus-base.packages` | Hyprland, QS, Ghostty, portals, PipeWire, NM, BT, capture tools, xdg-user-dirs, fastfetch, … |
| `proteus-desktop.packages` | **Chromium**, Nautilus (interim Files), gnome-calculator/calendar/weather/clocks, loupe, amberol, snapshot, gnome-disk-utility, imv, **celluloid** (desktop video; mpv + yt-dlp stay for console/CLI), **wtype** + **fd** (Beacon clipboard paste + Files search), evince, mousepad, wf-recorder, p7zip, noto-fonts-cjk, **localsend-bin** (AUR prebuilt via yay/paru), mission-center, … (pavucontrol/blueman/nm-editor hidden — Settings) |
| `proteus-console.packages` | Gamescope, **Steam** (+ ttf-liberation, lib32-mesa), RetroArch + lean cores, game-devices-udev — needs multilib (console stage enables) |
| `proteus-host.packages` | **samba** (usershares — Workloads app Shares tab) + **smartmontools** / **nvme-cli** (host dashboard drive health) + **podman** (Workloads containers / one-click apps) |

## Hardware (detect-and-install)

| Script | When |
|--------|------|
| `hardware/virt.sh` | QEMU — mesa/vulkan-virtio; skip discrete |
| `hardware/nvidia.sh` | Bare metal NVIDIA → open-dkms |
| `hardware/amd.sh` / `intel.sh` | Bare metal AMD / Intel |

Existing helpers under [`../guest/`](./machine/) stay the mutators.
Dock: Chromium / Nautilus / mousepad / Ghostty / Settings.
Capture interim: `Super+Shift+S` · `Print` · `Super+Shift+V` · `Super+Shift+C`.
