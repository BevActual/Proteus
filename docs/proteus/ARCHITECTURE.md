---
doc: architecture
role: agent-map
audience: coding agents, contributors
last_updated: "2026-07-30"
doc_status: active
scope: Layers, ownership, repo layout, HARD RULES
related:
  - POSITIONING.md
  - POSTURES.md
  - SETTINGS-IA.md
  - STACK.md
  - COMPOSITOR.md
  - CURRENT.md
---

# Proteus — architecture

Cold-start map for `~/Projects/Proteus`. Where this disagrees with code,
**the repo wins** — update [CURRENT.md](./CURRENT.md).

## Document map

| Section | Contents |
|---------|----------|
| [1. Layer cake](#1-layer-cake) | Postures → apps → shell → spine → facts → platform |
| [2. Ownership](#2-ownership) | Who owns what |
| [3. Shared spine](#3-shared-spine) | Theme, Config, Keybinds, posture |
| [4. Repo layout](#4-repo-layout) | Paths |
| [5. HARD RULES](#5-hard-rules) | Locks |
| [6. Ecosystem](#6-ecosystem) | Sibling products |
| [7. Verify](#7-verify) | VM + smoke |
| [8. See also](#8-see-also) | Stack · compositor |

---

## 1. Layer cake

```
┌─────────────────────────────────────────────────────────┐
│  Postures (hard-switch jobs — focus)                     │
│  desktop · console · host   (parked: home · wearable · …) │
├─────────────────────────────────────────────────────────┤
│  Apps                                                   │
│  proteus-settings (QS today) · future Tauri apps        │
├─────────────────────────────────────────────────────────┤
│  Shell chrome (Quickshell)                              │
│  bar · dock · launcher · toasts — launches, doesn’t own │
├─────────────────────────────────────────────────────────┤
│  Shared spine                                           │
│  Theme · Config · Keybinds · Posture/capabilities       │
├─────────────────────────────────────────────────────────┤
│  System facts (files + small helpers)                   │
│  ~/.config/proteus/* · hypr · pipewire · nm · pacman…   │
├─────────────────────────────────────────────────────────┤
│  Platform                                               │
│  Arch · Hyprland (backend) · greetd · polkit · vm/      │
└─────────────────────────────────────────────────────────┘
```

**Pattern (Keyboard is the prototype):**  
elegant Settings UI → real file on disk → compositor/daemon reload.

**Stack:** OS chrome → Quickshell; product apps → Tauri; helpers → Rust —
[STACK.md](./STACK.md). **Engines:** [COMPOSITOR.md](./COMPOSITOR.md).

---

## 2. Ownership

| Layer | Owns | Must not own |
|--------|------|----------------|
| **Shell (Quickshell)** | Presence chrome; shortcuts that open apps/overlays | Product apps; sole copy of system truth |
| **Settings** | Preference + maintenance IA | Drawing bar/dock |
| **Hyprland** | Windowing backend for compositor postures | Product identity; every posture |
| **Shared spine** | Tokens, schema, apply helpers | Per-posture layout |
| **System facts** | Truth on disk / daemons | QML widgets |
| **Postures** | Chrome arrangement, primary panes, input grammar | Separate settings stores |

Privileged actions: **propose → confirm / polkit → apply** (same muscle as
Mobius gates; implementation later).

---

## 3. Shared spine

| Module (today / intended) | Role |
|---------------------------|------|
| `Theme.qml` | Chrome tokens (space/radius + accent/font from Config) |
| `Config.qml` | Sole `settings.json` FileView + adapter keys (no aliases to Background) |
| `ConfigHypr.qml` | Hypr general.conf + chrome apply helpers (child of Config) |
| `Background.qml` | Wallpaper + lock backdrop façade; reads/writes `Config.*` fields |
| `BackgroundCatalog/Daily/Apply.qml` | Catalog tables · daily fetch · apply backends |
| `Widgets.qml` | Lock/desktop applet catalog + CRUD (+ `WidgetsLock` / `WidgetsDesktop`) |
| `Displays.qml` | Monitors list / apply → `proteus-monitors.conf` |
| `Audio.qml` · `Power.qml` · `DateTime.qml` · `Weather.qml` | Behavior singletons (prefs in Config where persisted) |
| `Hardware.qml` | Wave A: cache-first; shell live-probes (+ deferred refresh); Settings QS cache-only (`isSettingsApp`) → caps / device class |
| `Keybinds.qml` | Catalog + overrides → `proteus-keybinds.conf` |
| `ShellState.qml` | Beacon / open Settings / hardware mirrors |
| `Posture` *(intended)* | Resolver: capabilities + role → posture template |
| `Capabilities` *(intended)* | Device-environment flags — **probe feeds this today via Hardware** |

One **Config schema** for all postures. Postures change job template; **device
environments** (capability kits) change which chrome/engines/panes exist —
[POSTURES.md](./POSTURES.md) § Device environments. Not a second JSON tree per
SKU.

---

## 4. Repo layout

```
Proteus/
  AGENTS.md · README.md
  docs/
    README.md
    proteus/          # this product (incl. FACTS.md · CONFIG-SCHEMA.md · CHROME.md)
    shared/           # ecosystem seat among Bevington apps
  shell/              # Quickshell only
    shell.qml         # picks posture/surface loader
    shared/           # flat pragma-Singleton package + named helpers (see FACTS.md)
    surfaces/         # DesktopShell, PhoneShell, … (host later)
  apps/
    proteus-settings/ # Settings.qml + kit/ + panes/*; shared/ → ../../shell/shared
  env/                # seeds: hypr/ · ghostty/ · fastfetch/ (see env/README.md)
  vm/                 # QEMU harness + guest/ mutators + install/ overlay; ISO/qcow in PROTEUS_VM_CACHE
  services/           # proteus-hw-probe (read) · proteus-pkg · proteus-logind · proteus-audio-mix
  scripts/            # runners + tools: run-nested, run-desktop, smoke-all (entry)
    smoke/            # all *-smoke.sh gates (host + guest); run via ./scripts/smoke-all.sh
  tests/              # fixtures for schema/layout smokes (not a QML unit runner)
```

Public QML import path: `import "../../shared"` / Settings `shared` symlink.
**Keep singletons + their helpers in one directory** (Quickshell load-order);
do not put façades in domain subdirs behind `qmldir` without a proven cold start.
On-disk facts: [FACTS.md](./FACTS.md) · key groups: [CONFIG-SCHEMA.md](./CONFIG-SCHEMA.md).

`services/proteus-pkg` — privileged pacman mutator (pkexec + polkit) for Settings Software.
`services/proteus-logind` — privileged logind drop-in writer (pkexec + polkit) for Settings Power.
`services/proteus-audio-mix` — session-scoped resident dump+peaks for Sound Mixer (no polkit; mutations still `audio-mix.py`).
Optional later: more Rust CLIs (`proteus-net`, etc.) so QML stays thin
(Meridian-style: apps as clients of helpers). Future first-party apps under
`apps/` as Tauri projects ([STACK.md](./STACK.md)).

**Wave A hardware probe:** `services/proteus-hw-probe/` →
`./services/proteus-hw-probe/proteus-hw-probe` ([HARDWARE.md](./HARDWARE.md)).

---

## 5. HARD RULES

`locked` for this track:

1. **Shell launches Settings; Settings owns system control.**
2. **Every Settings control has a file or CLI you can inspect.**
3. **One Config schema for all postures.**
4. **Accent = action/selection**, not decoration wash.
5. **VM + scripts are the verify path** (nested Hyprland is shell-only shortcut).
6. **No second settings store per posture** (capability kits share the schema; panes enable/disable).
7. **Host is a posture, not a second distro / hypervisor appliance.**
8. **Focus postures are hard switches** — prove **desktop · console · host**
   until each is undeniable; park the rest ([POSTURES.md](./POSTURES.md)).
9. **Hyprland / Quickshell are backends** — profile and wrap; don’t fork early; SoT on disk; plan shell respawn; console may use a game-scoped compositor ([COMPOSITOR.md](./COMPOSITOR.md)).
10. **Stack split** — chrome/Settings in QML; product apps in Tauri; helpers in Rust ([STACK.md](./STACK.md)).
11. **Apps adapt to environment** — one app identity; capability contract; not enabled on every device class/posture by default ([APPLICATIONS.md](./APPLICATIONS.md)).
12. **Phone is a device class**, not a locked posture.

---

## 6. Ecosystem

Proteus is the **host environment** for Bevington apps — not a fourth peer in
the writing/AI loop. See [../shared/ECOSYSTEM.md](../shared/ECOSYSTEM.md).

| Product | Role |
|---------|------|
| **Rowena** | Writing IDE (client) |
| **Meridian** | Models / hub (client of nothing OS-wise; apps use it) |
| **Mobius** | Agent work harness / company loop SoT |
| **Proteus** | Adaptive OS those apps run on |

Do not reimplement Meridian providers or Mobius queue inside Proteus.

---

## 7. Verify

| Change | Gate |
|--------|------|
| Shell / Settings QML | Dogfood in VM (`./vm/run.sh`) or nested (`./scripts/run-nested.sh`); `./scripts/smoke/qs-guest-smoke.sh` when guest up |
| Layout / Config keys | `./scripts/smoke/layout-smoke.sh` · `./scripts/smoke/config-schema-smoke.sh` · fixtures in `tests/` |
| Host smoke suite | `./scripts/smoke-all.sh` |
| Guest installers | `vm/guest/*.sh` on running guest |
| Keybinds | Settings → Keyboard round-trip + `~/.config/hypr/proteus-keybinds.conf` |
| Desktop / Displays | Settings → `proteus-general.conf` / `proteus-monitors.conf` |
| Hardware probe | `./scripts/smoke/hw-probe-smoke.sh` |
| Docs-only | Keep CURRENT cites honest |

SSH (default): `ssh -p 2222 andrew@127.0.0.1`

---

## 8. See also

| Doc | Role |
|-----|------|
| [COMPOSITOR.md](./COMPOSITOR.md) | Hyprland + Quickshell roles, limits, profiles |
| [POSTURES.md](./POSTURES.md) | Posture + device class + capabilities + host vs hypervisor |
| [APPLICATIONS.md](./APPLICATIONS.md) | Adaptive apps / environment contract |
| [HARDWARE.md](./HARDWARE.md) | Device classes + sensors/modules targets |
| [STACK.md](./STACK.md) | Languages by layer |
