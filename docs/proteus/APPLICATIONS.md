---
doc: applications
role: architecture
audience: architects, contributors, app authors
last_updated: "2026-07-30"
doc_status: active
scope: Adaptive apps — one identity, environment-shaped; not every app on every kit
related:
  - POSTURES.md
  - HARDWARE.md
  - STACK.md
  - ARCHITECTURE.md
  - CURRENT.md
status_legend:
  planned: Designed; not in code
  shipped: In code today
---

# Applications — one app, shaped by environment

Proteus apps are **not** forked per posture or per device SKU. An application is
**one product identity** that **adapts** to the environment it is running in —
and is **not enabled everywhere by default**.

This is the opposite of “ship five APKs.” It is closer to adaptive layouts, with
an explicit **capability contract**.

## Document map

| Section | Contents |
|---------|----------|
| [1. Environment tuple](#1-environment-tuple) | What an app sees |
| [2. Device class vs posture](#2-device-class-vs-posture) | Phone isn’t a job |
| [3. App contract](#3-app-contract) | Require / prefer / adapt |
| [4. Availability](#4-availability) | Not every app on every kit |
| [5. Shaping](#5-shaping) | Same app, different chrome |
| [6. Stack](#6-stack) | How we build them |
| [7. Status](#7-status) | Today |

---

## 1. Environment tuple

An app session resolves against:

```
device class  ×  capabilities  ×  posture  ×  session mode
        └──────────── environment ────────────┘
```

| Piece | Meaning | Example |
|-------|---------|---------|
| **Device class** | Physical product category | `phone`, `laptop`, `tv`, `watch`, `hub`, `server` |
| **Capabilities** | What *this unit* can do | `touch`, `display`, `vitals`, `libvirt` |
| **Posture** | What job the OS is in | `desktop`, `console`, `host` |
| **Session mode** | Optional soft overlay (not a posture flip) | `focus`, `present`, … |

OS chrome and apps both read this tuple. Details:
[POSTURES.md](./POSTURES.md) · module/sensor inventory: [HARDWARE.md](./HARDWARE.md).

---

## 2. Device class vs posture

**Phone was easy to mis-file as a posture.** A phone is primarily a **device
class** (pocket computer with touch, cellular, battery), not a unique *job*
like `host` or `console`.

| | Device class | Posture |
|--|--------------|---------|
| Asks | What kind of machine is this? | What is this machine *doing*? |
| Changes slowly | Hardware SKU / form | Role / user intent (hard switch) |
| Examples | phone, tablet, laptop, TV, watch, XR headset, vehicle HU, home hub, server | **Focus:** desktop, console, host · **Parked:** home, wearable, xr, vehicle |

A **phone** often runs personal compute with dense touch chrome — that may look
like a “mobile” shell, but the shell is still Proteus expressing **device class
+ capabilities**, possibly under a personal/desktop-adjacent job, not a locked
posture named “phone.”

Likewise: a **TV** is a device class that often runs **console** posture; a
**rack NUC** is a device class that often runs **host** (UI on demand).

---

## 3. App contract

`partial` — Wave A manifests ship under `env/apps/`; EnvGate enforces
`requires` / `requiresAny` / **`postures`** (hard vs SessionPosture) when a
desktop entry matches; **`prefers`** is soft (Beacon hint + search boost).
`device_classes` / `adapts` remain docs-forward (schema allows; gating ignores).

Each app declares a contract (manifest / metadata):

| Field | Meaning |
|-------|---------|
| **requires** | Capabilities that must be present or the app doesn’t offer itself |
| **requiresAny** | At least one of these capabilities must be present |
| **prefers** | Soft capability hints — Beacon subtitle + ranking boost (never blocks) |
| **postures** | Hard allow-list vs session posture (`desktop` · `console` · `host`; empty = any) |
| **device_classes** | Optional allow/deny (e.g. vitals UI on `watch` / `phone` only) |
| **adapts** | Which UI facets change (nav density, input, panes) |

On disk: `env/apps/schema.json` + `env/apps/catalog.json`. EnvGate loads the
catalog at session start (`catalogPath` via `shellRoot/../env/apps/…`).

Example sketches:

- **Rowena** — requires `display`; prefers `pointer` or large `display`; primary
  postures `desktop` (+ maybe compact on `phone` device class later).  
- **Host workloads app** — requires `libvirt` or `containers`; posture `host`;
  separate from Settings (VM/container *setup* is not a Settings category);
  works headless via CLI/API; GUI facet only when UI session exists.
  **Today:** HostHome ships a **thin read-only glance** (`Workloads` /
  `proteus-workloads.py`); create/destroy UI and the full app stay Out.  
- **Vitals glance** — requires `vitals`; device classes `watch` / band; no
  Hyprland needed.  
- **Media / console player** — posture `console` or `desktop`; adapts to `remote` /
  `gamepad` / `touch`.

---

## 4. Availability

**Default: not universal.**

The launcher / hub only surfaces apps whose **requires** match the current
environment (and posture allow-list). Users can still search “unavailable here”
with a clear reason (“needs libvirt”, “needs display”).

### Implementation (Wave A)

| Surface | Gate |
|---------|------|
| Settings sidebar | `EnvGate.availableSettingsPanes()` — Sound needs audio caps; Network needs wifi/ethernet/bt; … |
| Beacon | Hide gated apps unless searching; search shows them dimmed with reason (`Beacon.qml` → `EnvGate.appAvailable`) |
| Dock | `DockApps.visiblePinned` via optional `requires` / `requiresAny` on pins |
| App manifests | `env/apps/catalog.json` preferred over `appRules` / category heuristics |

Code: `shell/shared/EnvGate.qml`. Fail-open until `Hardware.ready`. Missing
catalog → heuristics only (`manifestsReady` false).

**User grants:** manifests may list `permissions` (`microphone` · `camera` ·
`location` · `notifications` · `screen` · `diagnostics`). EnvGate requires
`Permissions.granted` (Allow only; Ask/Deny block). Store:
`~/.config/proteus/permissions.json` via `Permissions.qml`. Fail-open until the
store is ready. Native OS sandbox for pacman apps stays Out — Flatpak overrides
are separate (Settings → Privacy → Flatpak apps).

This avoids pretending every creative app belongs on a vitals band or that every
ops tool belongs on the console.

---

## 5. Shaping

When an app *does* run, it **shapes** — one binary/identity:

| Environment signal | App may change |
|--------------------|----------------|
| `touch` vs `pointer` | Hit targets, chrome |
| Display size / `headless` | Layout density; headless → CLI/API only |
| Posture `console` | Lean-back typography, remote / gamepad nav |
| Posture `host` | Ops IA; no “creative desktop” assumptions |
| Session `focus` | Hide secondary panels |
| `mic`/`speaker` without `display` | Voice-first flows |

Same idea as Rowena **surface profiles** (one spine, center column changes) —
applied across the OS environment tuple, not only writing modes.

---

## 6. Stack

Build adaptive apps per [STACK.md](./STACK.md):

- Product windows → **Tauri + TS** (shared UI that branches on environment)  
- OS Settings facets → **Quickshell** today  
- Headless / privileged → **Rust** CLI/API the GUI calls  

Do not ship `rowena-phone` and `rowena-desktop` as separate products if one
adaptive app can honor the contract.

---

## 7. Status

| Item | Status |
|------|--------|
| Environment tuple (docs) | `planned` / locked in prose |
| App capability manifest | `partial` — `env/apps/` schema + catalog; EnvGate load + postures/prefers |
| Beacon filtering by contract | `partial` — manifest match + heuristic fallback + prefers boost |
| DesktopEntries launcher | `shipped` (desktop) |
| Console lean seats | `partial` — Browser / Media / Terminal / Steam / RetroArch / Desktop via `proteus-console-launch`; Jump Back In = `consoleRecents`; Library/Search = DesktopEntries (+ Games tag); Web apps from Software leaf |

---

## Non-goals

- One APK/IPA per posture  
- “Runs everywhere” as the default promise  
- Treating **phone** as a locked OS posture instead of a device class  
- Forcing compositor apps onto headless kits  
