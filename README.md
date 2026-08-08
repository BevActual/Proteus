# Proteus

**Bevington Systems** — an adaptive environment that reshapes itself to **where
you are** and **what this machine’s job is** (posture = hardware + use).

**Focus set (prove these):**

| Posture | Intent |
|---------|--------|
| Desktop | Create / windowed work (primary spine) |
| Console | Lean-back consume + play (TV, games) — `proteus-posture` + console face |
| Host | Operate the box — headless by default, **UI when you want it** |

**Parked (thesis only):** wearable · xr · vehicle · home — see
[docs/proteus/POSTURES.md](docs/proteus/POSTURES.md).

Session modes (focus, present, meeting, …) sit *on* postures. Hardware kits
(vitals-only wearable, voice-only home hub, headless host, …) vary by
**capabilities** inside a posture.

**Thesis:** Linux under the hood, Mac in the hand. Settings bridges elegant UI
to inspectable system facts. See **[docs/](docs/README.md)**.

| Doc | Start here |
|-----|------------|
| [POSITIONING](docs/proteus/POSITIONING.md) | Field, white space, proof order |
| [ARCHITECTURE](docs/proteus/ARCHITECTURE.md) | Layers + HARD RULES |
| [POSTURES](docs/proteus/POSTURES.md) | Jobs, kits, device class |
| [APPLICATIONS](docs/proteus/APPLICATIONS.md) | Adaptive apps |
| [HARDWARE](docs/proteus/HARDWARE.md) | Device classes, sensors, modules |
| [COMPOSITOR](docs/proteus/COMPOSITOR.md) | Owned Smithay compositor + iced shell |
| [STACK](docs/proteus/STACK.md) | iced / Tauri / Rust |
| [CURRENT](docs/proteus/CURRENT.md) | What’s built today |
| [AGENTS.md](AGENTS.md) | Agent entry |

Built on Arch Linux + owned iced shell (`proteus-shell`) + Smithay compositor
(`proteus-compositor`).

## Status

Desktop spine is dogfoodable in the VM (shell + Settings largely shipped).
Console and host hard switches are `partial` (`proteus-posture`; host defaults
headless / seat attach); parked postures are thesis only. Honest inventory:
[docs/proteus/CURRENT.md](docs/proteus/CURRENT.md).

## Test in a VM (recommended)

```bash
sudo pacman -S qemu-desktop qemu-img edk2-ovmf   # once, if needed
./dev/vm/download-iso.sh
./dev/vm/create-disk.sh
./dev/vm/run.sh install   # first time
./dev/vm/run.sh           # thereafter
```

Guest install, 9p share, SSH, snapshots: **[dev/vm/README.md](dev/vm/README.md)**.

```bash
# On guest after boot:
bash /mnt/proteus/install/machine/install-settings-app.sh
```

SSH: `ssh -p 2222 andrew@127.0.0.1`

## Nested compositor (host quick-test)

Shell-only experiments (does not replace the VM for distro work):

```bash
./dev/run-nested.sh
```

- Exit: `Super+Shift+E` · Terminal: `Super+Return` · Settings: `Super+,`
- Surface override: `PROTEUS_SURFACE=phone ./dev/run-nested.sh`

## Layout

```
docs/            # POSITIONING, ARCHITECTURE, POSTURES, CURRENT, …
compositor/      # proteus-compositor (Smithay) + proteus-compositorctl
install/         # Overlay installer — VM and bare metal alike
  hardware/      # GPU + CPU microcode detection
  machine/       # install-time mutators (install-*.sh, apply-*.sh)
env/             # Seeds: chrome/ · ghostty/ · fastfetch/
shell/           # proteus-shell iced chrome
  src/faces/     # desktop · console · host
  scripts/       # Runtime PATH helpers (session, posture, seats, …)
services/
  proteus-shell-core/  # facts · tokens · gating · proteus-open
  proteus-ui/          # shared iced kit
  proteus-hw-probe/    # Wave A capabilities JSON
  proteus-pkg/ · proteus-logind/ · proteus-audio-mix/ · proteus-accounts/ · …
dev/             # Maintainer tooling — never installed onto a machine
  vm/            # QEMU/KVM Arch guest harness
  smoke/  smoke-all.sh   # desktop spine gates (+ owned-guest)
  dogfood/  spike/  fixtures/

Siblings (path deps):
  ../ProteusSettings   # proteus-settings-next
  ../ProteusWorkloads  # proteus-workloads
```

### Desktop shell (today)

- Top bar: glass menu bar; app title, workspaces, clock+weather, status → Control Center (Beacon is off the bar)
- **Beacon** (`Super+Space` / `Super+D`; dock pin) — Apps / Files / Clipboard / Actions; fuzzy + tags
- Dock — floating glass shelf; pins, running dots; layout/size/rounding/autohide Facts
- Terminal: `Super+Return` → `proteus-terminal` (Ghostty + VM GL workaround)
- Session: `proteus-session` → `proteus-compositor --backend drm -c proteus-chrome`
- **Settings** (`Super+,`) — iced sibling `proteus-settings-next`; Appearance, Desktop (Dock & menu bar, Beacon, …), Displays, Sound, Network, Peripherals, Software, …
- Keybinds: `~/.config/proteus/keybinds.json` · Displays: `~/.config/proteus/displays.json`

Full honest inventory: [docs/proteus/CURRENT.md](docs/proteus/CURRENT.md).

Guest 9p share mounts the tree at `/mnt/proteus`; rebuild/install helpers to pick
up binary changes (`install-proteus-compositor.sh`, `install-shell.sh`, …).

## Licence

**GPL-3.0-only** — see [LICENSE](LICENSE).

The names *Proteus* and *Bevington Systems* and the marks under `brand/` are
excluded from that grant; fork freely, but rebrand. What Proteus is built on,
and why none of it encumbers this source, is recorded in
[THIRD-PARTY.md](THIRD-PARTY.md).
