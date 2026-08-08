---
doc: owned-stack
role: decision-record
audience: coding agents, contributors
last_updated: "2026-08-08"
doc_status: active
scope: Owned-stack endgame — what Proteus will own, what stays borrowed, sequencing
related:
  - ARCHITECTURE.md
  - STACK.md
  - COMPOSITOR.md
  - POSTURES.md
  - CURRENT.md
---

# Proteus — owned stack (decision record)

**Decision (2026-08-05):** the long-term direction is an **owned stack** —
Proteus-built spin-offs of each layer, in Rust where practical — for tight
integration, inspectability, and real tests at every layer. Borrowed engines (Tauri/WebKit, Gamescope) remain **interim behind contracts**
where still used. Hyprland and Quickshell chrome are **retired** (2026-08-06) —
shipping session is owned `proteus-compositor` + iced `proteus-shell`.

This refines — does not repeal — ARCHITECTURE HARD RULES 9/10: we still
**never fork** an upstream. Borrowed layers are *replaced* by owned
implementations when the owned one passes the same gates; they are never
carried as patched copies.

## Document map

| Section | Contents |
|---------|----------|
| [1. Tiers](#1-tiers) | Own / borrow-interim / never own |
| [2. Sequencing](#2-sequencing) | Replacement ladder, in dependency order |
| [3. Survivability rules](#3-survivability-rules) | What keeps this from stalling the product |
| [4. proteus-shell-core](#4-proteus-shell-core) | The owned spine — surface sketch |
| [5. Status](#5-status) | Honest ladder position |

---

## 1. Tiers

| Tier | Layers | Notes |
|------|--------|-------|
| **Owned endgame** | Facts/state core (`proteus-shell-core`) · shell chrome (iced layer-shell widgets) · compositor (Smithay-based, posture-native) · XR face (own clients on Monado/Stardust model) · app chrome toolkit (post-Tauri) | Each replaces its borrowed layer only after passing the same gates |
| **Borrowed interim** (behind contracts) | Tauri/WebKit (app runtime) · gamescope (console session · desktop nest via `proteus-gamescope`) | Hyprland + Quickshell **retired**; owned `proteus-compositor` + `proteus-shell` ship |
| **Never own** | Kernel · Mesa · PipeWire · Wayland protocol · Monado (OpenXR runtime) · greetd/polkit | Extend and configure only |

## 2. Sequencing

Dependency order — each rung makes the next one cheaper and is independently
useful even if the ladder stops there:

| Rung | What | Why first |
|------|------|-----------|
| **0. `proteus-shell-core`** | Facts, gating, posture, theme derivation as a tested Rust crate + subscribe stream (§4) | Prerequisite for every renderer (iced, XR); typed + `cargo test` |
| **1. Owned chrome** | iced layer-shell shell (`shell/`) over the core — **shipped** (QML retired) | Compositor-agnostic chrome; faces under `shell/src/faces/` |
| **2. Compositor** | Smithay `compositor/` — **Hyprland purged**; DRM session + Displays Fact (incl. live transform) + keybinds + nested winit; shell IPC `wm_ipc.rs`; `proteus-settings-apply`; owned idle; protocol lock opt-in dogfood | Deeper multi-GPU / flipped transform UI / blur still out — [COMPOSITOR-SPIKE.md](./COMPOSITOR-SPIKE.md) |
| **3. Faces on the owned stack** | Console + XR faces land natively (input, surfaces, state — one vocabulary) | Where the integration payoff compounds |
| **4. App chrome toolkit** | First-party apps move from Tauri/WebKit to the owned iced toolkit | WebKit is the largest remaining black box; Settings/Workloads already iced siblings |

## 3. Survivability rules

1. **Replace, never fork.** No patched vendored copies of Hyprland/Quickshell/
   Tauri — a layer is borrowed stock or owned outright.
2. **One layer at a time.** A rung starts only when the rung below passes its
   gates; no parallel platform rewrites while postures are `partial`.
3. **Contracts first, swap second.** Every replacement lands behind an existing
   contract (deep links, tokens, Facts schema, CLI JSON) with smokes holding
   both sides honest during the overlap — the Tauri app split is the template.
4. **The product keeps shipping.** At every point there is a working system;
   owned layers install alongside (cf. `proteus-settings-next`) and become the
   default only by passing the same VM dogfood + smoke gates.
5. **Honest ledger.** Ladder position lives in §5 + [CURRENT.md](./CURRENT.md);
   no layer is called owned until it is the shipping default.

## 4. proteus-shell-core

The owned spine — the layer no framework provides and every renderer needs.
A Rust crate (library first; `serve` NDJSON stream for live subscribers per the
`proteus-audio-mix` precedent — **not** a new always-on daemon).

**Owns** (typed + unit-tested):

| Concern | What |
|---------|------|
| Config / facts | `settings.json` schema, read/write, key adapters ([CONFIG-SCHEMA.md](./CONFIG-SCHEMA.md)) |
| Theme tokens | Accent/mode/font → chrome tokens; `env/chrome/` build artifact |
| Gating | App/pane rules — postures, device classes, capability requirements |
| Posture / hardware | Posture fact + capabilities resolution (probe JSON in, typed caps out) |
| Launch | `proteus-open` — sibling roots, quoting, fallbacks |

**Stays in the renderer** (iced shell / Settings): layout, animation,
per-surface view state, input handling — views over the core's stream.

**Consumers:** iced shell · iced Settings/Workloads · future Tauri apps · rung-3 faces.

## 5. Status

| Rung | Status |
|------|--------|
| 0 shell-core | `partial` — crate shipped; see slice ledger below (Config write + Permissions now landed) |
| 1 iced chrome | `shipped` (tree) — **QML chrome retired 2026-08-06**: `shell-next` → `shell/` sole chrome tree; `proteus-chrome` owned-only; Quickshell/`proteus-qs` deleted; face modules under `shell/src/faces/` (desktop shipping; console/host thin stubs). Prior: Wave 4 dogfood, UI/UX parity, boot reliability, wallpaper/previews/Lock Customize |
| 2 compositor | `shipped` (thin) — Displays Fact + `dispatch output`; session Super keybinds (`binds.rs` + `keybinds.json`); owned idle; maximize; multi-GPU enumerate; nested winit; `wm_ipc.rs` — see [COMPOSITOR-SPIKE.md](./COMPOSITOR-SPIKE.md) |
| 3 owned faces | `partial` — scaffold in `shell/src/faces/{desktop,console,host}/`; console/host thin (rebuild later); gamescope console-home not swapped |
| 4 app toolkit | `partial` — Settings **iced only** (QML Settings deleted 2026-08-06); OAuth Connect · Displays list+apply · Mixer list thin; canvas/grid polish + Headscale deep still holdout |

**Sequencing exception (2026-08-05):** rung 1 is a **big push** (parallel owned session covering bar/dock/Beacon/CC/lock/widgets/faces) rather than bar-first piecemeal, and the apps track (rung 4) runs in parallel inside sibling repos. Rules 3–5 still bind: contracts first, parallel install, honest ledger. Rule 2 (“one layer at a time”) is amended for this campaign only.

### Rung 0 slice ledger (honest)

| Slice | Status |
|-------|--------|
| Tokens | `shipped` — `tokens --json/--css/--write` generates `env/chrome/` byte-for-byte; golden cargo tests + drift gate in `chrome-tokens-smoke` |
| Facts + schema | `shipped` — typed posture / hw-probe / permissions; schema-keys SoT in shell-core (`shell-core-smoke`; Config.qml retired) |
| Gating | `shipped` — app + pane gating; Permissions Ask/Deny when store present |
| proteus-open | `shipped` — owned shell + Settings launch via `proteus-open` / wrappers |
| serve | `shipped` (library-first) — `FactsWatch` + NDJSON CLI adapter; iced shell consumes the library |
| Config **write** path | `shipped` — `settings-write` / `posture-write` CLI + `facts::write_settings`; iced Settings is the shipping writer |

### Rung 1 slice ledger (honest)

| Slice | Status |
|-------|--------|
| Workspace + proteus-ui | `shipped` — root `Cargo.toml`; shared iced kit |
| shell skeleton | `shipped` — crate at `shell/` (was `shell-next`); face modules; compositor IPC (`wm_ipc.rs`); `proteus-shellctl` |
| Platform stubs | `partial` — zbus Notifications (+ dbus-monitor fallback) + DND; **SNI tray list-only**; brightness/volume HUD; UPower/MPRIS CLI |
| Frame surfaces | `shipped` — bar/dock/wallpaper/previews (see prior parity pass) |
| Overlays + lock | `shipped` — Beacon/CC/HUD/toast/lock Customize thin |
| Boot reliability | `shipped` — protocol gates + respawn watchdog |
| Widgets + faces | `partial` — `shell/src/faces/`; console/host thin; **gamescope console-home not swapped** |
| Engine switch | `shipped` — **owned-only** (`proteus-chrome`); Quickshell path deleted 2026-08-06; `shell-engine` fact may still read `owned` |
| Swap gate | `shipped` — QML chrome + Settings QML deleted; iced sole path |
