# Proteus

**Bevington Systems** — an adaptive environment that reshapes itself to **where
you are** and **what this machine’s job is** (posture = hardware + use).

| Posture | Intent |
|---------|--------|
| Desktop | Create / windowed work (first target) |
| Media | Lean-back consume + play (TV, games) |
| Wearable | Micro / glance |
| XR | Spatial / headset |
| Vehicle | Eyes-up, locked task set |
| Home | House controller (scenes, devices) |
| Host | Operate the box — headless by default, **UI when you want it** |

Session modes (focus, present, meeting, …) sit *on* postures. Hardware kits
(vitals-only wearable, voice-only home hub, headless host, …) vary by
**capabilities** inside a posture — see
[docs/proteus/POSTURES.md](docs/proteus/POSTURES.md).

**Thesis:** Linux under the hood, Mac in the hand. Settings bridges elegant UI
to inspectable system facts. See **[docs/](docs/README.md)**.

| Doc | Start here |
|-----|------------|
| [POSITIONING](docs/proteus/POSITIONING.md) | Field, white space, proof order |
| [ARCHITECTURE](docs/proteus/ARCHITECTURE.md) | Layers + HARD RULES |
| [POSTURES](docs/proteus/POSTURES.md) | Jobs, kits, device class |
| [APPLICATIONS](docs/proteus/APPLICATIONS.md) | Adaptive apps |
| [HARDWARE](docs/proteus/HARDWARE.md) | Device classes, sensors, modules |
| [COMPOSITOR](docs/proteus/COMPOSITOR.md) | Hyprland + Quickshell |
| [STACK](docs/proteus/STACK.md) | QML / Tauri / Rust |
| [CURRENT](docs/proteus/CURRENT.md) | What’s built today |
| [AGENTS.md](AGENTS.md) | Agent entry |

Built on Arch Linux + [Quickshell](https://quickshell.org/) (Qt/QML) + Hyprland.

## Status

Early scaffold. Desktop spine in progress; other postures are stubs/planned.
Honest inventory: [docs/proteus/CURRENT.md](docs/proteus/CURRENT.md).

## Test in a VM (recommended)

```bash
sudo pacman -S qemu-desktop qemu-img edk2-ovmf   # once, if needed
./vm/download-iso.sh
./vm/create-disk.sh
./vm/run.sh install   # first time
./vm/run.sh           # thereafter
```

Guest install, 9p share, SSH, snapshots: **[vm/README.md](vm/README.md)**.

```bash
# On guest after boot:
bash /mnt/proteus/vm/guest/install-settings-app.sh
```

SSH: `ssh -p 2222 andrew@127.0.0.1`

## Nested Hyprland (host quick-test)

Shell-only experiments (does not replace the VM for distro work):

```bash
./scripts/run-nested.sh
```

- Exit: `Super+Shift+E` · Terminal: `Super+Return` · Settings: `Super+,`
- Surface override: `PROTEUS_SURFACE=phone ./scripts/run-nested.sh`

## Layout

```
docs/            # POSITIONING, ARCHITECTURE, POSTURES, CURRENT, …
vm/              # QEMU/KVM Arch guest harness
env/             # Seeds: hypr/ · ghostty/ · fastfetch/
scripts/         # run-nested.sh, run-desktop.sh
shell/           # Quickshell (chrome)
  shared/        # Theme, Config, Keybinds, ShellState, …
  surfaces/      # Desktop + posture stubs
apps/
  proteus-settings/   # Control center (Style, Desktop, Keyboard, …)
services/
  proteus-hw-probe/   # Wave A: desktop/laptop → capabilities JSON
```

### Desktop shell (today)

- Top bar: glass menu bar; launcher, workspaces, app title, clock, status → Control Center
- App launcher (`Super+Space` / `Super+D`) — Apps / Files / Clipboard modes; fuzzy + tags
- Dock — floating glass shelf + Mag; pins, running dots
- Terminal: `Super+Return` → `proteus-terminal` (Ghostty + VM GL workaround)
- Session: `proteus-session` → `start-hyprland`/Hyprland; no terminal `exec-once`; stray system apps hidden (`hide-system-apps.sh`)
- **Settings** (`Super+,`) — Appearance (incl. Icons), Desktop (incl. Beacon), Displays, Sound, Network, Software (pacman / AUR / Flatpak / AppImages / Orphans), …; cold-start via sticky pane loaders
- Keybinds file: `~/.config/hypr/proteus-keybinds.conf`

Full honest inventory: [docs/proteus/CURRENT.md](docs/proteus/CURRENT.md).

Edits under `shell/` and `apps/` live-reload via the 9p share when Quickshell
is running in the VM.
