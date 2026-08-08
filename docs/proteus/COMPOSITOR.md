---
doc: compositor
role: architecture
audience: architects, contributors, coding agents
last_updated: "2026-08-08"
doc_status: active
scope: Owned Smithay compositor + iced shell; posture engines; profiles; limits
related:
  - ARCHITECTURE.md
  - POSTURES.md
  - STACK.md
  - OWNED-STACK.md
  - COMPOSITOR-SPIKE.md
  - CURRENT.md
status_legend:
  shipped: In code today
  partial: Present; gaps remain
  planned: Designed; not in code
---

# Compositor & shell runtime — owned stack

Proteus **owns** the shipping Wayland session: Smithay compositor
(`proteus-compositor` in `compositor/`) + iced chrome (`proteus-shell` via
`proteus-chrome`). Hyprland and Quickshell are **retired** as session engines
(2026-08-06). Focus postures: **desktop · console · host**
([POSTURES.md](./POSTURES.md)). Detail checklist:
[COMPOSITOR-SPIKE.md](./COMPOSITOR-SPIKE.md).

## Document map

| Section | Contents |
|---------|----------|
| [1. Roles](#1-roles) | Who does what |
| [2. Owned compositor](#2-owned-compositor) | Smithay session |
| [3. Owned chrome](#3-owned-chrome) | iced layer-shell shell |
| [4. Profiles on disk](#4-profiles-on-disk) | Facts + apply |
| [5. Capabilities](#5-capabilities) | Facts that drive posture + features |
| [6. HARD RULES](#6-hard-rules) | Locks |
| [7. Status](#7-status) | What’s real today |

---

## 1. Roles

| Piece | Role |
|-------|------|
| **Proteus** | Identity, postures, Settings IA, capability model |
| **`proteus-compositor`** | Wayland session — tiling, outputs, keybinds, layer-shell, IPC |
| **`proteus-shell`** | Presence chrome (bar, dock, Beacon, lock, overlays) |
| **`proteus-settings-next`** | System control center (sibling iced app) |
| **Gamescope** *(interim FORCE-only)* | Shipping: owned **game-present** + **focus-stack** on smithay. Nest/session only via `PROTEUS_FORCE_GAMESCOPE=1` / Fact `engine=gamescope`. Steam: `proteus-gamescope %command%` → owned path by default |

```
capabilities + role  →  hard-switch posture  →  proteus-session engine + chrome + Settings
```

| Focus posture | Typical engines |
|---------------|-----------------|
| **desktop** | `proteus-compositor` DRM + full iced desktop face |
| **console** | **End state (`partial`):** always smithay + thin console face; titles via game-present; Guide focus-stack via `proteus-console-focus`. gs-session FORCE-only |
| **host** | No DE by default; lean seat + host face when attached |

---

## 2. Owned compositor

Crate: [`compositor/`](../../compositor/) · binary: `proteus-compositor` · ctl:
`proteus-compositorctl`.

### Do

- Session via `proteus-session` → `--backend drm -c proteus-chrome`
- Nested dogfood via `./dev/run-nested.sh` (winit)
- Facts on disk: `displays.json`, `keybinds.json`, gaps/chrome via
  `proteus-settings-apply` / compositorctl
- Screencopy for grim / dock thumbs — virtio skips CPU Y-flip by default
  (`PROTEUS_SCREENCOPY_FLIP_Y`)

### Don’t

- Reintroduce Hyprland as a session fallback
- Fork Smithay / carry long-lived patches — replace behind contracts
  ([OWNED-STACK.md](./OWNED-STACK.md))
- Infer seat orientation from grim alone (`PROTEUS_DRM_TRANSFORM` only when the
  **panel** is wrong)

Fact `compositor-engine`: `smithay` / `compositor` (alias `compositor-next`
still accepted). `hyprland` / `hypr` → refused.

---

## 3. Owned chrome

`shell/scripts/proteus-chrome` → `proteus-shell` only (QML / `proteus-qs`
deleted).

| Surface | Notes |
|---------|--------|
| Menu bar / dock / Beacon / CC / Spaces / lock / widgets | iced multi-window layer-shell in one process |
| Faces | `shell/src/faces/` — desktop shipping; console/host thin stubs |
| IPC | `proteus-shellctl` + compositor sock (`wm_ipc.rs`) |

Settings is **not** chrome — sibling [`../ProteusSettings`](../../../ProteusSettings/AGENTS.md).

---

## 4. Profiles on disk

Hypr fragment tree (`env/hypr/`) **deleted**. Soft `set-hypr-profile.sh` is a
retired stub.

```
~/.config/proteus/displays.json     # outputs / scale / pos / mode / transform
~/.config/proteus/keybinds.json     # session chords
~/.config/proteus/settings.json     # chrome + desktop Facts
~/.config/proteus/compositor-engine # smithay
~/.config/proteus/posture           # hard switch
```

**Hard console/host flip:** `proteus-posture` → Fact + greeter restart;
`proteus-session` picks the engine at next login. Nested/dev: in-place chrome
flip. See [POSTURES.md](./POSTURES.md) § Hard switches.

---

## 5. Capabilities

| Capability | Influences |
|------------|------------|
| `display` / `headless` | Whether compositor + chrome start |
| `tiling` / `multi_monitor` | Layout + Displays pane |
| `touch` / `pointer` / `remote` / `gamepad` | Chrome targets, keybind set |
| `mic` / `speaker` | Voice surfaces; meeting mode |
| `game_scope` | Hardware Vulkan for owned present quality (*partial*; does not start Gamescope) |
| `battery` | Power panes |

Rule: **missing `display` does not invent a new posture** — it disables
compositor chrome for that unit.

---

## 6. HARD RULES

1. **Smithay is the only shipping session compositor** — Hyprland purged.  
2. **iced owns chrome** — Settings is a sibling iced app, not shell.  
3. **SoT on disk / CLI** — shell restart must not lose config.  
4. **Replace, never fork** borrowed engines ([OWNED-STACK.md](./OWNED-STACK.md)).  
5. **Not every posture needs a full desktop seat** — host defaults lean.  
6. **Soft profile reload ≠ posture flip** for console/host.  
7. **DRM transform / screencopy flip** — seat is ground truth; grim is not.

---

## 7. Status

| Item | Status |
|------|--------|
| Guest smithay + iced shell | `shipped` |
| Settings → keybinds / gaps / displays | `shipped` (thin) — Facts + `proteus-settings-apply` / compositorctl |
| Hyprland session / QS chrome | `retired` |
| Console hard switch | `partial` — owned smithay + console face stub; game-present/focus-stack; gs-session FORCE-only |
| Game-present | `partial` — Fact `game-present` + ctl; Rescale/NN blit thin (`RescaleRenderElement`); integer/stretch + filter; FSR / fill-crop / fps_limit Out |
| Host hard switch | `partial` — headless default + seat attach |
| Owned compositor depth | `shipped` (thin) — per-output Spaces boards + see [COMPOSITOR-SPIKE.md](./COMPOSITOR-SPIKE.md) |
| Capability resolver | `planned` |
| Lock | `partial` — iced **overlay** lock + PAM is the shipping default (`session-lock` Fact / `PROTEUS_SESSION_LOCK`; unset → overlay); `ext-session-lock-v1` thin on compositor + opt-in `proteus-session-lock` helper; ctl `session-lock` (`supported`/`pending`/`locked`/`active`); nested dogfood `dev/smoke/compositor-session-lock.sh`; greetd/tuigreet still login |
