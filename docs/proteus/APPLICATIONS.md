---
doc: applications
role: architecture
audience: architects, contributors, app authors
last_updated: "2026-07-28"
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
| **Posture** | What job the OS is in | `desktop`, `media`, `host`, … |
| **Session mode** | Optional activity overlay | `focus`, `present`, … |

OS chrome and apps both read this tuple. Details:
[POSTURES.md](./POSTURES.md) · module/sensor inventory: [HARDWARE.md](./HARDWARE.md).

---

## 2. Device class vs posture

**Phone was easy to mis-file as a posture.** A phone is primarily a **device
class** (pocket computer with touch, cellular, battery), not a unique *job*
like `host` or `media`.

| | Device class | Posture |
|--|--------------|---------|
| Asks | What kind of machine is this? | What is this machine *doing*? |
| Changes slowly | Hardware SKU / form | Role / user intent / sticky mode |
| Examples | phone, tablet, laptop, TV, watch, XR headset, vehicle HU, home hub, server | desktop, media, wearable, xr, vehicle, home, host |

A **phone** often runs personal compute with dense touch chrome — that may look
like a “mobile” shell, but the shell is still Proteus expressing **device class
+ capabilities**, possibly under a personal/desktop-adjacent job, not a eighth
locked posture named “phone.”

Likewise: a **TV** is a device class that often runs **media** posture; a
**rack NUC** is a device class that often runs **host** (UI on demand).

---

## 3. App contract

`partial` — Wave A manifests ship under `env/apps/`; EnvGate enforces
`requires` / `requiresAny` when a desktop entry matches. `prefers` /
`postures` / `device_classes` / `adapts` remain docs-forward (schema allows;
gating ignores).

Each app declares a contract (manifest / metadata):

| Field | Meaning |
|-------|---------|
| **requires** | Capabilities that must be present or the app doesn’t offer itself |
| **requiresAny** | At least one of these capabilities must be present |
| **prefers** | Soft hints (larger display, pointer, …) for layout defaults |
| **postures** | Where it is allowed or primary (`host`, `media`, `desktop`, …) |
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
- **Vitals glance** — requires `vitals`; device classes `watch` / band; no
  Hyprland needed.  
- **Media player** — posture `media` or `desktop`; adapts to `remote` /
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
| Launcher | Hide gated apps unless searching; search shows them dimmed with reason (`Launcher.qml` → `EnvGate.appAvailable`) |
| Dock | `DockApps.visiblePinned` via optional `requires` / `requiresAny` on pins |
| App manifests | `env/apps/catalog.json` preferred over `appRules` / category heuristics |

Code: `shell/shared/EnvGate.qml`. Fail-open until `Hardware.ready`. Missing
catalog → heuristics only (`manifestsReady` false).

This avoids pretending every creative app belongs on a vitals band or that every
ops tool belongs on the couch.

---

## 5. Shaping

When an app *does* run, it **shapes** — one binary/identity:

| Environment signal | App may change |
|--------------------|----------------|
| `touch` vs `pointer` | Hit targets, chrome |
| Display size / `headless` | Layout density; headless → CLI/API only |
| Posture `media` | Lean-back typography, remote nav |
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
| App capability manifest | `partial` — `env/apps/` schema + catalog; EnvGate load |
| Launcher filtering by contract | `partial` — manifest match + heuristic fallback |
| DesktopEntries launcher | `shipped` (desktop) |

---

## Non-goals

- One APK/IPA per posture  
- “Runs everywhere” as the default promise  
- Treating **phone** as a locked OS posture instead of a device class  
- Forcing compositor apps onto headless kits  
