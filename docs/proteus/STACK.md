---
doc: stack
role: reference
audience: contributors, coding agents
last_updated: "2026-08-06"
doc_status: active
scope: Languages and runtimes by layer — what to build in what
related:
  - ARCHITECTURE.md
  - OWNED-STACK.md
  - COMPOSITOR.md
  - SETTINGS-IA.md
  - APPLICATIONS.md
  - CURRENT.md
  - ../shared/ECOSYSTEM.md
---

# Proteus — language / stack

Do **not** pick one language for the whole OS. Split by layer.
Adaptive app behavior (one identity, environment-shaped): [APPLICATIONS.md](./APPLICATIONS.md).
**Endgame:** owned Rust stack replacing borrowed layers rung by rung —
[OWNED-STACK.md](./OWNED-STACK.md). Quickshell chrome and Settings QML are
**retired** (2026-08-06).

## Document map

| Section | Contents |
|---------|----------|
| [1. Rule](#1-rule) | One-liner |
| [2. By layer](#2-by-layer) | Default stack table |
| [3. Why not all-X](#3-why-not-all-x) | Rejected monocultures |
| [4. New work defaults](#4-new-work-defaults) | Practical choice guide |
| [5. Sibling alignment](#5-sibling-alignment) | Rowena / Meridian |
| [6. Exceptions log](#6-exceptions-log) | Blessed deviations |

---

## 1. Rule

> **If it’s the OS looking at you → iced (`shell/`, `proteus-ui`).**  
> **If it’s a product window the user runs → iced sibling or Tauri (TypeScript + Rust).**  
> **If it’s a daemon/CLI that mutates the system → Rust.**  
> **Hardware / environment probes may be Python** until promoted to Rust
> (explicit exception — see §2).

---

## 2. By layer

| What you’re building | Stack | Why |
|----------------------|-------|-----|
| Shell chrome (bar, dock, Beacon, overlays) | **iced / `shell/`** (`proteus-shell` via `proteus-chrome`) | Wayland layer-shell; faces under `shell/src/faces/` |
| Shell spine (facts, tokens, gating, launch) | **Rust** — `services/proteus-shell-core` | Typed + `cargo test`; generates `env/chrome/`; `proteus-open` |
| Shared iced kit | **Rust** — `services/proteus-ui` | Theme from shell-core tokens; widgets for shell + sibling apps |
| System control center (`proteus-settings`) | **iced** (sibling [`../ProteusSettings`](../../../ProteusSettings/AGENTS.md)) | Sole Settings app; QML deleted |
| Host Workloads app (`proteus-workloads`) | **iced** (sibling [`../ProteusWorkloads`](../../../ProteusWorkloads/AGENTS.md)) | Same backend + `--tab` contract |
| **Hardware / env probes** | **Python** *(blessed)* | `proteus-hw-probe` Wave A; Rust rewrite candidate later |
| System helpers that **mutate** state | **Rust** small CLIs (+ bash when tiny) | Thin, smokeable |
| Hot-path session helpers | **Rust** resident CLI (`serve`) | NDJSON while Settings leaf open |
| First-party Proteus apps (Files, …) | **TypeScript + Tauri (Rust)** | Matches **Rowena**; not shell chrome |
| Host / ops backends | **Rust** services or Linux tools behind thin API | Trust + long-running |

Truth stays on **disk / CLI** regardless of UI stack ([ARCHITECTURE.md](./ARCHITECTURE.md) HARD RULES).

---

## 3. Why not all-X

| Monoculture | Problem |
|-------------|---------|
| All QML | Retired for chrome/Settings; poor match to Rowena for rich apps |
| All Electron | Heavy; fights “elegant Linux” |
| All Rust GUI overnight | Wrong while postures are `partial`; iced chrome is the owned path per [OWNED-STACK.md](./OWNED-STACK.md) |
| Fork Quickshell | Never — replace, don’t fork |

---

## 4. New work defaults

1. New **Settings pane** → iced sibling (`../ProteusSettings`) + optional Rust mutator / serve
2. New **Proteus app** → Tauri + TS or iced, theme aligned with Proteus tokens
3. New **mutating system capability** → Rust CLI that Settings/apps call
4. New **read-only discovery** → Python probe OK (log in §6 if long-lived)
5. New **shell chrome surface** → `shell/src/` (or `shell/src/faces/` for posture faces)
6. New **hot-path poll** → Rust resident helper while the leaf is open

---

## 5. Sibling alignment

| Product | Stack reminder |
|---------|----------------|
| **Rowena** | Tauri + TypeScript (+ Rust) |
| **Meridian** | Rust crates / hub listen |
| **Mobius** | Docs + TS/JS packages / scripts |
| **Proteus** | iced chrome + iced Settings/Workloads + Rust mutators + Python probes |

---

## 6. Exceptions log

| Exception | Status | Notes |
|-----------|--------|-------|
| `services/proteus-hw-probe` in Python | `blessed` | Read-only Wave A probe; Rust rewrite when schema/packaging demands it |
| Trivial one-liner bash (`hyprctl`, `pactl`) | `blessed` | Not “helpers” — direct apply |
| Settings / chrome QML | `retired` | Deleted 2026-08-06; iced only |
