---
doc: architecture
role: agent-map
audience: coding agents, contributors
last_updated: "2026-08-08"
doc_status: active
scope: Layers, ownership, repo layout, HARD RULES
related:
  - POSITIONING.md
  - POSTURES.md
  - SETTINGS-IA.md
  - STACK.md
  - COMPOSITOR.md
  - OWNED-STACK.md
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
| [3. Shared spine](#3-shared-spine) | Tokens, facts, gating, open |
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
│  proteus-settings-next · proteus-workloads (iced siblings) │
│  future first-party apps (Tauri or owned iced)          │
├─────────────────────────────────────────────────────────┤
│  Shell chrome (iced — proteus-shell via proteus-chrome) │
│  bar · dock · Beacon · lock · overlays — launches, doesn’t own │
├─────────────────────────────────────────────────────────┤
│  Shared spine (Rust)                                    │
│  proteus-shell-core · proteus-ui · posture / capabilities │
├─────────────────────────────────────────────────────────┤
│  System facts (files + small helpers)                   │
│  ~/.config/proteus/* · pipewire · nm · pacman…          │
├─────────────────────────────────────────────────────────┤
│  Platform                                               │
│  Arch · proteus-compositor (Smithay) · greetd · polkit · dev/vm/ │
└─────────────────────────────────────────────────────────┘
```

**Pattern (Keyboard is the prototype):**  
elegant Settings UI → real file on disk → compositor/daemon reload.

**Stack:** OS chrome → iced; product apps → iced sibling or Tauri; helpers → Rust —
[STACK.md](./STACK.md). **Engines:** [COMPOSITOR.md](./COMPOSITOR.md).
**Ladder:** [OWNED-STACK.md](./OWNED-STACK.md).

---

## 2. Ownership

| Layer | Owns | Must not own |
|--------|------|----------------|
| **Shell (`proteus-shell`)** | Presence chrome; shortcuts that open apps/overlays | Product apps; sole copy of system truth |
| **Settings** | Preference + maintenance IA (sibling iced app) | Drawing bar/dock |
| **`proteus-compositor`** | Windowing / session Wayland seat | Product identity; every posture |
| **Shared spine** | Tokens, schema, gating, `proteus-open` | Per-posture layout |
| **System facts** | Truth on disk / daemons | UI widgets |
| **Postures** | Chrome arrangement, primary panes, input grammar | Separate settings stores |

Privileged actions: **propose → confirm / polkit → apply** (same muscle as
Mobius gates; implementation later).

---

## 3. Shared spine

| Module | Role |
|--------|------|
| `services/proteus-shell-core` | Typed facts, `settings.json` R/W, chrome tokens (`env/chrome/`), app/pane gating, `proteus-open`, NDJSON `serve` |
| `services/proteus-ui` | Shared iced theme + widgets (shell + Settings + Workloads) |
| `shell/src/wm_ipc.rs` | Compositor sock IPC (workspaces, clients, dispatch) |
| `shell/src/faces/` | Posture faces — desktop shipping; console/host thin stubs |
| `shell/scripts/*` | Session PATH helpers — `proteus-session` · `proteus-chrome` · `proteus-posture` · apply / idle / seats |
| Posture Fact + `proteus-posture` | Hard session posture (About confirm picker) |
| Capabilities (via hw-probe + shell-core) | Device-environment flags → gating |
| Online accounts / calendar / mail helpers | Vault + glance backends (`proteus-accounts`, mutate/send scripts) |

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
    proteus/          # this product (incl. FACTS · CONFIG-SCHEMA · CHROME · COMPOSITOR*)
    shared/           # ecosystem seat among Bevington apps
  compositor/         # proteus-compositor (Smithay) + proteus-compositorctl
  shell/              # proteus-shell iced chrome only
    src/faces/        # desktop · console · host
    scripts/          # ALL runtime PATH helpers — proteus-session · proteus-chrome ·
                      #   proteus-posture · proteus-host-seat · proteus-idle · …
  env/                # seeds: chrome/ · ghostty/ · fastfetch/ (see env/README.md)
  install/            # machine-agnostic overlay — VM and bare metal (SoT: INSTALL.md)
    bootstrap.sh      # stage runner; check.sh = host tree gate
    *.packages        # base · desktop · console · host rosters
    hardware/         # GPU + CPU microcode detection
    machine/          # install-time mutators only: install-*.sh · apply-*.sh
  services/           # proteus-hw-probe · proteus-shell-core · proteus-ui · proteus-pkg ·
                      #   proteus-logind · proteus-audio-mix · proteus-accounts · …
  dev/                # MAINTAINER TOOLING ONLY — never installed onto a machine
    vm/               # QEMU harness: run · provision · guest-install; ISO/qcow in PROTEUS_VM_CACHE
    smoke/            # all *-smoke.sh gates (host + guest)
    smoke-all.sh      # desktop spine suite (console/host deferred)
    dogfood/          # dogfood-console.sh · dogfood-host.sh
    spike/            # throwaway experiments
    fixtures/         # schema/layout smoke fixtures
    run-nested.sh · run-desktop.sh · generate-wallpapers.py

Siblings (path deps, not submodules):
  ../ProteusSettings   # proteus-settings-next (sole Settings app)
  ../ProteusWorkloads  # proteus-workloads iced app
```

On-disk facts: [FACTS.md](./FACTS.md) · key groups: [CONFIG-SCHEMA.md](./CONFIG-SCHEMA.md).

`services/proteus-shell-core` — owned shell spine ([OWNED-STACK.md](./OWNED-STACK.md)
rung 0): typed facts, chrome-token generation, app/pane gating, `proteus-open`,
minimal NDJSON `serve`. Unit-tested (`cargo test`); gates via `shell-core-smoke`.
`services/proteus-pkg` — privileged pacman mutator (pkexec + polkit) for Settings Software.
`services/proteus-logind` — privileged logind drop-in writer for Settings Power.
`services/proteus-battery-threshold` — privileged sysfs charge_control_* writer.
`services/proteus-audio-mix` — session-scoped resident dump+peaks for Sound Mixer.
`services/proteus-accounts` — online-accounts vault + Google PKCE.

Optional later: more Rust CLIs (`proteus-net`, etc.). Future first-party apps under
`apps/` as Tauri or owned iced ([STACK.md](./STACK.md)).

**Wave A hardware probe:** `services/proteus-hw-probe/` →
`./services/proteus-hw-probe/proteus-hw-probe` ([HARDWARE.md](./HARDWARE.md)).

---

## 5. HARD RULES

`locked` for this track:

1. **Shell launches Settings; Settings owns system control.**
2. **Every Settings control has a file or CLI you can inspect.** Enforced: each
   settings hub declares `backsFacts` / `backsCli` in the catalog, and
   `dev/smoke/settings-backing-smoke.sh` resolves every name against repo
   helpers, built services, a declared external-tool list, and the Facts table
   in [CURRENT.md](./CURRENT.md) §5.
3. **One Config schema for all postures.**
4. **Accent = action/selection**, not decoration wash.
5. **VM + scripts are the verify path** (`./dev/run-nested.sh` = shell-only shortcut).
6. **No second settings store per posture** (capability kits share the schema; panes enable/disable).
7. **Host is a posture, not a second distro / hypervisor appliance.**
8. **Focus postures are hard switches** — prove **desktop · console · host**
   until each is undeniable; park the rest ([POSTURES.md](./POSTURES.md)).
9. **Smithay is the only shipping session compositor** — Hyprland purged; never
   fork borrowed engines; SoT on disk; console uses owned smithay (Gamescope FORCE-only)
   compositor when capable ([COMPOSITOR.md](./COMPOSITOR.md) ·
   [OWNED-STACK.md](./OWNED-STACK.md)).
10. **Stack split** — chrome in iced (`shell/` + `proteus-ui`); Settings/Workloads
    in iced siblings; product apps in Tauri or owned iced; helpers in Rust
    ([STACK.md](./STACK.md)).
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
| Shell / Settings / compositor (desktop) | Dogfood in VM (`./dev/vm/run.sh`) or nested (`./dev/run-nested.sh`); `./dev/smoke-all.sh` (desktop spine only) |
| Layout / Config keys | Covered by desktop `smoke-all`; fixtures in `dev/fixtures/` |
| Console / host smokes | Deferred — individual `dev/smoke/*` scripts + dogfood; not in `smoke-all` until desktop is rock solid |
| Guest installers | `install/machine/*.sh` on running guest |
| Keybinds | Settings → Peripherals → Keyboard + `~/.config/proteus/keybinds.json` + compositor `reloadbinds` |
| Desktop / Displays | Settings → `displays.json` + `proteus-settings-apply` / compositorctl |
| Hardware probe | `./dev/smoke/hw-probe-smoke.sh` |
| Docs-only | Keep CURRENT cites honest |

SSH (default): `ssh -p 2222 andrew@127.0.0.1`

---

## 8. See also

| Doc | Role |
|-----|------|
| [COMPOSITOR.md](./COMPOSITOR.md) | Owned Smithay + iced shell roles, profiles, limits |
| [COMPOSITOR-SPIKE.md](./COMPOSITOR-SPIKE.md) | Compositor depth checklist |
| [OWNED-STACK.md](./OWNED-STACK.md) | Owned-stack ladder — tiers, sequencing, `proteus-shell-core` |
| [POSTURES.md](./POSTURES.md) | Posture + device class + capabilities + host vs hypervisor |
| [APPLICATIONS.md](./APPLICATIONS.md) | Adaptive apps / environment contract |
| [HARDWARE.md](./HARDWARE.md) | Device classes + sensors/modules targets |
| [STACK.md](./STACK.md) | Languages by layer |
