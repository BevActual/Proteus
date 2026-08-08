---
doc: applications
role: architecture
audience: architects, contributors, app authors
last_updated: "2026-08-08"
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
and is **not enabled everywhere by default**. Settings **faces** follow the same
rule: one Facts/files SoT, disconnected chrome per posture
([SETTINGS-IA.md](./SETTINGS-IA.md) § Posture faces) — not three settings trees.

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

`partial` — Wave A manifests ship under `env/apps/`; shell-core gating enforces
`requires` / `requiresAny` / **`postures`** (hard vs session posture) /
**`device_classes`** (hard vs probe `device_class`) when a desktop entry
matches; **`prefers`** is soft (Beacon hint + search boost); **`adapts`** is
soft shaping (`appAdaptProfile` / Beacon hint / **`PROTEUS_ADAPT_*` launch env** —
never blocks apps). Gating resolves `input` + `nav` + **`panes`** (via Focus
pane density) and Dock/Beacon inject `PROTEUS_ADAPT_INPUT` /
`PROTEUS_ADAPT_NAV` / `PROTEUS_ADAPT_PANES` when launching. When panes resolve
to **minimal** (Focus on), Settings **hard-hides** non-allowlisted hubs/leaves
(Desktop→Focus · Privacy · Users · Notifications · About stay). `input: remote`
resolves via probe remote capability — CEC/IR/lirc / Bluetooth HID remote-like
names or soft stub `PROTEUS_REMOTE_PROBE=1`. Settings About may surface adapt
launch env (soft display — first-party consumer wedge).

Each app declares a contract (manifest / metadata):

| Field | Meaning |
|-------|---------|
| **requires** | Capabilities that must be present or the app doesn’t offer itself |
| **requiresAny** | At least one of these capabilities must be present |
| **prefers** | Soft capability hints — Beacon subtitle + ranking boost (never blocks) |
| **postures** | Hard allow-list vs session posture (`desktop` · `console` · `host`; empty = any) |
| **device_classes** | Hard allow-list vs Wave A class (`desktop` · `laptop` · `tablet` · `phone` · `server`; empty = any) |
| **adapts** | Soft UI-shaping for apps; shell-core resolves `input` + `nav` + `panes` (Focus on → minimal); launch injects `PROTEUS_ADAPT_*`; Settings hard-hides panes when minimal |

On disk: `env/apps/schema.json` + `env/apps/catalog.json`. Shell-core loads the
catalog at session start (`env/apps/…` beside the tree / install root).

Example sketches:

- **Rowena** — requires `display`; prefers `pointer` or large `display`; primary
  postures `desktop` (+ maybe compact on `phone` device class later).  
- **Host workloads app** — requires `libvirt` or `containers`; posture `host`;
  separate from Settings (VM/container *setup* is not a Settings category);
  works headless via CLI/API; GUI facet only when seat attached
  (`host-chrome=full` / `proteus-host-seat attach`).
  **Today:** HostHome **Command-Deck dashboard** (read-only cards via
  `proteus-host-metrics.py`) + Tauri app (sibling `../ProteusWorkloads`) with
  tabs — **Workloads** (start/stop/kill/create/destroy) · **Apps** (one-click
  container catalog `env/apps/host-apps.json`, deploy → `proteus-app-<id>`) ·
  **Shares** (Samba usershare add/remove); dashboard cards deep-link tabs
  (`proteus-workloads --tab …`); Settings → Virtualization thin hub.
- **Vitals glance** — requires `vitals`; `device_classes: ["watch","phone"]`
  (catalog example; blocks on desktop/laptop VM).  
- **Console titles** (games, Plex, streaming/web apps) — posture `console`
  (and often `desktop`); launch from Console shelves, not store Big Picture.
  Adapts to `remote` / `gamepad`. **Store apps** (Steam, Heroic, …) may list
  on `console` + `desktop` but are **backends** (install/update) — not Console
  Games/Media list primary rows ([POSTURES.md](./POSTURES.md) § Console launcher).

---

## 4. Availability

**Default: not universal.**

The launcher / hub only surfaces apps whose **requires** match the current
environment (and posture allow-list). Users can still search “unavailable here”
with a clear reason (“needs libvirt”, “needs display”).

### Implementation (Wave A)

| Surface | Gate |
|---------|------|
| Settings sidebar | shell-core pane gate — Sound needs audio caps; Network needs wifi/ethernet/bt; … |
| Beacon | Hide gated apps unless searching; search shows them dimmed with reason (`gate_app`) |
| Dock | Visible pins honor optional `requires` / `requiresAny` |
| App manifests | `env/apps/catalog.json` preferred over `appRules` / category heuristics |

Code: `services/proteus-shell-core` (`gate.rs` + catalogs). Fail-open until
hardware probe is ready. Missing catalog → heuristics only.

**User grants:** manifests may list `permissions` (`microphone` · `camera` ·
`location` · `notifications` · `screen` · `diagnostics`). Gating requires
Allow (Ask/Deny block). Store: `~/.config/proteus/permissions.json` via
`proteus-permissions.py` + shell/Settings. Fail-open until the store is ready.
Native OS sandbox for pacman apps stays Out — Flatpak overrides are separate
(Settings → Privacy → Flatpak apps).

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
- OS Settings facets → **iced** (`proteus-settings-next`)  
- Headless / privileged → **Rust** CLI/API the GUI calls  

Do not ship `rowena-phone` and `rowena-desktop` as separate products if one
adaptive app can honor the contract.

---

## 7. Status

| Item | Status |
|------|--------|
| Environment tuple (docs) | `planned` / locked in prose |
| App capability manifest | `partial` — `env/apps/` schema + catalog; shell-core load + postures/prefers/device_classes/adapts + launch env |
| Beacon filtering by contract | `partial` — manifest match + heuristic fallback + prefers boost + adapts hint + Dock/Beacon/`openSettings` `PROTEUS_ADAPT_*` + Settings About adapt env |
| DesktopEntries launcher | `shipped` (desktop) |
| Console lean seats | `partial` — Browser / Media / Terminal / Steam / RetroArch / Desktop via `proteus-console-launch`; Games · Media · Apps · Search · Settings list IA; Apps = curated lean-back; Media = streaming; **Console Settings face**; Search = DesktopEntries + extras |

---

## Non-goals

- One APK/IPA per posture  
- “Runs everywhere” as the default promise  
- Treating **phone** as a locked OS posture instead of a device class  
- Forcing compositor apps onto headless kits  
