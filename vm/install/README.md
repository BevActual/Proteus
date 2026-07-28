# vm/install/ — Proteus dogfood overlay (Omarchy-shaped, light)

Not a product ISO. After bare Arch (`guest-install.sh` or manual), this
pipeline turns the guest into a Hyprland + Quickshell dogfood session.

```
# Host (after guest has Arch + SSH + 9p):
./vm/provision.sh                 # prepare ISO/disk hints + overlay over SSH
./vm/bootstrap.sh                 # overlay only

# On guest:
sudo bash /mnt/proteus/vm/install/bootstrap.sh
```

## Stages

| Stage | Role |
|-------|------|
| `preflight.sh` | 9p mount unit, paths |
| `packaging.sh` | [`proteus-base.packages`](./proteus-base.packages) — session stack |
| `config.sh` | seatd, QS symlink, hypr/ghostty/fastfetch seeds, hypridle |
| `hardware.sh` | Detect GPU → optional drivers (`hardware/*`) |
| `login.sh` | greetd / `proteus-session` |
| `apps.sh` | Settings, keybinds, desktop conf, PAM, interim capture bins |
| `desktop.sh` | [`proteus-desktop.packages`](./proteus-desktop.packages) (default on) |
| `post-install.sh` | status file + next steps |

## Knobs

| Env | Effect |
|-----|--------|
| `PROTEUS_INSTALL_DESKTOP=0` | Skip Chromium/Nautilus kit |
| `PROTEUS_INSTALL_SKIP=hardware,desktop` | Skip named stages |
| `PROTEUS_INSTALL_ONLY=desktop` | Run one stage |
| `PROTEUS_INSTALL_RESUME=1` | Skip stages with `/var/lib/proteus/install/*.done` |
| `PROTEUS_INSTALL_LOG=` | Override log path (default `/var/log/proteus-install.log`) |
| `PROTEUS_INSTALL_STATUS_DIR=` | Override resume/status dir (default `/var/lib/proteus/install`) |

Pacman uses `--needed` and skips the transaction when every package is already
installed. Markers under the status dir.

Host tree check (no guest):

```bash
./vm/install/check.sh
```

## Package sets

| File | Contents |
|------|----------|
| `proteus-base.packages` | Hyprland, QS, Ghostty, portals, PipeWire, NM, BT, capture tools, fastfetch, … |
| `proteus-desktop.packages` | **Chromium**, Nautilus (interim Files), imv, mpv, evince, mousepad, … |

## Hardware (detect-and-install)

| Script | When |
|--------|------|
| `hardware/virt.sh` | QEMU — mesa/vulkan-virtio; skip discrete |
| `hardware/nvidia.sh` | Bare metal NVIDIA → open-dkms |
| `hardware/amd.sh` / `intel.sh` | Bare metal AMD / Intel |

Existing helpers under [`../guest/`](../guest/) stay the mutators.
Dock: Chromium / Nautilus / mousepad / Ghostty / Settings.
Capture interim: `Super+Shift+S` · `Print` · `Super+Shift+V` · `Super+Shift+C`.
