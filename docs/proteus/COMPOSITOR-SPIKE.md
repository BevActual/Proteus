# COMPOSITOR-SPIKE — Smithay depth checklist (honest status)

> Depth record for the owned-compositor rung ([OWNED-STACK.md](./OWNED-STACK.md)).
> **Smithay is the only shipping session engine** (Hyprland purged 2026-08-06).
> Nested dogfood = compositor winit via `./dev/run-nested.sh`. Live DRM
> stays opt-in for CI (`PROTEUS_COMPOSITOR_DRM=1`). Filename keeps “SPIKE” for
> link stability; the crate is `compositor/` / `proteus-compositor`.

## What exists (2026-08-08)

`compositor/` — Smithay 0.7 session compositor (shipping thin):

| Piece | Status |
|-------|--------|
| winit backend (nested window as output) | `works` |
| xdg-shell toplevels (map, popups) | `works` |
| Interactive move / resize pointer grabs | `works` — marks window `floating`; loc synced into wm roster; **bindm** Super+LMB move · Super+RMB resize (`keybinds.json` `bindm` Fact) |
| Equal / dwindle / master tiling | `partial` — default **dwindle**; `dispatch layout equal\|dwindle\|master`; gaps out/in (default **10/6**); **smart-gaps** (default on; zero gaps when one tiled window); `masterfactor`; per-output + exclusive zone; `togglefloating` |
| Focus ring (CSD) | `works` (thin) — 2px accent MemoryRenderBuffer around focused **CSD** window; Cosmic `IndicatorShader` is pattern-only (never forked) |
| xdg-decoration (`zxdg_decoration_manager_v1`) | `works` (thin) — **CSD-first** (GTK ServerSide asks ignored); SSD titlebar (28px) only when `t.ssd`; cosmic-text + close/max/min hits; double-click titlebar maximize; button hover/press |
| xdg popup pointer/keyboard grabs | `works` |
| Nested Xwayland + X11Wm | `works` — soft-fail if `Xwayland` missing; X11 clients join wm/IPC roster |
| wlr-layer-shell (map/arrange/anchor, exclusive zones via `layer_map`) | `works` |
| wp_viewporter + wp_fractional_scale | `works` — iced_layershell clients hard-require viewporter |
| `zwlr_screencopy_manager_v1` (SHM + linux-dmabuf) | `works` — grim + `copy_with_damage`; nested + DRM GLES upload into client dmabufs; offscreen readback for CPU `last_frame`; **Y-flip auto** skips CPU flip on virtio-gpu (`PROTEUS_SCREENCOPY_FLIP_Y=0\|1` override) so grim matches the seat |
| Portal Screenshot (`xdg-desktop-portal-wlr`) | `partial` — sets `XDG_CURRENT_DESKTOP=wlroots`; smoke runs isolated dbus Screenshot when portal-wlr is installed (SKIP otherwise). **Shipping prefers portal-wlr** (Hyprland portal retired with Hyprland). |
| Gamescope nesting (client under compositor) | `partial` — smoke nests `gamescope` under compositor `WAYLAND_DISPLAY`, asserts ctl `clients` growth; SKIP if binary missing or backends exit (no Vulkan / VirGL). **Desktop nest helper** `proteus-gamescope` (Steam `%command%` / CLI; flags Fact `gamescope-flags`). Console-home **not** swapped. |
| PipeWire Screencast | `partial` — compositor `copy_with_damage` ready for xdp-wlr/wf-recorder; smoke via `wf-recorder` when installed (SKIP otherwise). PipeWire stays never-own. |
| Input routing (pointer/keyboard, layers above windows) | `thin` |
| Workspace roster `1..=10` + `special:minimized` parking | `works` — **per-output boards** (synced `workspace N` · local `workspace N,output:NAME`); monitors JSON `activeWorkspace` + focused |
| Control socket (`PROTEUS_COMPOSITOR_SOCK`) query + dispatch + subscribe | `works` |
| Shell engine-aware IPC (`shell/src/wm_ipc.rs`) | `works` |
| Clients JSON hypr-shaped `at` / `size` | `works` — live Space/Window geometry |
| Session / DRM / libinput backend | `works` (thin) — `--backend drm`; **only** shipping path via `proteus-session` (Fact=hyprland refused; nested/missing/DRM fail → exit 1); install Fact + portal-wlr; Hyprland purged |
| SSD maximize hit | `works` (thin) — `SsdHit::Maximize` / `maximize_hit`; titlebar double-click toggle |
| Multi-GPU enumerate | `thin` — DRM lists GPUs; prefers **card** (Primary) node; `PROTEUS_DRM_DEVICE` override |
| Soft cursor | `works` (thin) — default arrow MemoryRenderBuffer; `cursor_image` tracked; client surface → default |
| VirGL / virtio transform | `thin` — prefers **card** node; `PROTEUS_DRM_TRANSFORM` (`normal`/`180`/`flipped`/…) for host-GL orientation quirks (no auto flip — VirGL hosts differ) |
| Displays Fact + modeset | `works` (thin) — load `displays.json`; `dispatch output` scale/pos/mode/**transform**; monitors JSON live transform; **Identify** flash; Settings **10s Revert**; Settings orientation UI **In** (flipped Out) |
| Session keybinds | `works` (thin) — Super chords in compositor (`binds.rs`); Super+Ctrl+1–0 local Spaces; Fact `keybinds.json`; `reloadbinds` (+ reload `workspaceNames`) |
| `ext-session-lock-v1` | `partial` (thin) — `session_lock.rs` tracked; global advertised; blank xdg windows while locked; LockSurfaces drawn; ctl `session-lock` (`supported`/`pending`/`locked`/`active`); **Overlay remains default** shell Fact; protocol opt-in dogfood via `compositor-session-lock.sh` + `proteus-session-lock` |

### Supported ctl dispatches

`workspace N` (synced all heads) · `workspace N,output:NAME` · `workspace N,local` ·
`renameworkspace N <name>` ·
`focuswindow address:…` · `killactive` · `cyclenext` ·
`movetoworkspacesilent N|special:minimized` · `fullscreen 1` · `togglefloating` ·
`layout equal|dwindle|master` · `gapsout N` · `gapsin N` · `smartgaps on|off|toggle` · `masterfactor F` ·
`output <name> scale <f>` · `output <name> pos <x> <y>` · `output <name> mode <WxH[@Hz]>` ·
`output <name> transform <0-7|normal|90|180|…>` ·
`identify [secs]` · `reloadbinds` · `input-reload` ·
`movewindow output:<name>` · `focusoutput <name>`

Queries (hypr-shaped JSON fields): `workspaces` · `activeworkspace` ·
`clients` (incl. `at`/`size`/`output`) · `activewindow` · `monitors`
(incl. `focused` · `activeWorkspace` · `transform`) · `session-lock`
(`supported`/`pending`/`locked`/`active`). Workspace `name` honors `workspaceNames`.
Helper: `proteus-compositorctl`.

## Prove (2026-08-06)

### Layers (2026-08-05, host nested run)

```
./target/debug/proteus-compositor -c ./target/debug/proteus-shell --face desktop
proteus-compositor: nested on WAYLAND_DISPLAY=wayland-2
proteus-compositor: layer mapped: proteus-bar
… (all ten proteus-shell chrome layers)
```

### IPC (2026-08-06)

- `cargo test -p compositor` — wm roster unit tests (incl. `at`/`size`).
- `./dev/smoke/compositor-smoke.sh` — build + (when DISPLAY set) ctl
  round-trip: workspaces → dispatch workspace 2 → activeworkspace.

### Grabs (2026-08-06)

- `cargo test` includes `resize_edges_geometry` unit tests.
- Smoke greps for `MoveSurfaceGrab` / `ResizeSurfaceGrab` / wired `move_request` /
  popup `grab_popup`.
- Manual dogfood: nested compositor + foot/kitty (or Settings) — drag CSD/SSD
  titlebar, resize from edges, open a menu/popup if the client supports it.

### Xwayland (2026-08-06)

- Smithay feature `xwayland`; `init_xwayland` soft-fails without the binary.
- On Ready: sets `DISPLAY=:{n}` and attaches `X11Wm`; X11 map/unmap/focus/close/
  fullscreen/move/resize feed the same wm roster as xdg.
- Smoke: when `Xwayland` + `xeyes` exist, assert `clients` grows after spawn.

### Screencopy (2026-08-06)

- `zwlr_screencopy_manager_v1` v3 (SHM `buffer` + `linux_dmabuf` + `buffer_done`);
  region + full output. Pixels from offscreen GLES readback after each redraw.
- `wp_linux_dmabuf` global from winit GLES formats; dmabuf `copy` binds client
  buffer and uploads cropped `last_frame` via `MemoryRenderBuffer`.
- Smoke: when `grim` exists and nested display is up, `grim -g '0,0 32x32'` must
  write a non-empty PNG (SKIP if no grim). DRM-path screencopy still unset.

### Portals Screenshot (2026-08-06)

- Compositor process + `-c` children set `XDG_CURRENT_DESKTOP=wlroots` for
  `xdg-desktop-portal-wlr` `UseIn`.
- Helper: [`dev/smoke/compositor-portal-screenshot.sh`](../../dev/smoke/compositor-portal-screenshot.sh)
  — `dbus-run-session` + preferred `wlr` + non-interactive Screenshot.
- Smoke: SKIP if `xdg-desktop-portal-wlr` missing; otherwise attempt Screenshot
  under nested `WAYLAND_DISPLAY` (inconclusive host setups soft-skip).
- Shipping: `xdg-desktop-portal-wlr` in base packages + `env/portal/portals.conf`
  (`Preferred=wlr;gtk`). Hyprland portal retired with Hyprland.
- PipeWire Screencast still **out**.

### Gamescope nesting (2026-08-06)

- Helper: [`dev/smoke/compositor-gamescope.sh`](../../dev/smoke/compositor-gamescope.sh)
  — nest `gamescope -W 1280 -H 720 -- sleep …` under compositor display; retry
  `--backend sdl` on early exit; poll ctl `clients` for growth / `gamescope`.
- Desktop launch: [`shell/scripts/proteus-gamescope`](../../shell/scripts/proteus-gamescope)
  — nest under ambient Wayland; Fact `~/.config/proteus/gamescope-flags`; Steam
  launch options `proteus-gamescope %command%`; bare-run when Vulkan/VM unusable;
  no double-nest inside gamescope session.
- Smoke: SKIP (rc 2) if gamescope missing or both backends die; FAIL if up but
  absent from clients.
- Console-home gamescope session still **not** swapped (owned face honesty).

### Tiling (2026-08-06)

- [`layout.rs`](../../compositor/src/layout.rs) — `equal_column_layout`,
  `dwindle_layout` (default), `master_layout(factor)`, `inset_rect`,
  `work_area_with_exclusive`.
- `dispatch layout equal|dwindle|master`; `gapsout` / `gapsin` (defaults 8 / 4);
  `smartgaps on|off|toggle` (default on — effective gaps 0/0 when one tiled window);
  `masterfactor` (`0.1..=0.9`, default 0.5); move/resize grabs set `floating`;
  `dispatch togglefloating`.
- `relayout_active` picks effective gaps via `effective_gaps`, insets work area by
  `gaps_out`, lays out, insets each tile by `gaps_in`, then applies SSD reserve —
  **per output** against `non_exclusive_zone`.

### Screencast / copy_with_damage (2026-08-06)

- `CopyWithDamage` always queues until the next redraw; fulfill sends full-buffer
  `damage` then `flags`/`ready` ([`screencopy.rs`](../../compositor/src/screencopy.rs)).
- Helper: [`dev/smoke/compositor-screencast.sh`](../../dev/smoke/compositor-screencast.sh)
  — short `wf-recorder` under nested display (SKIP if missing).
- Full portal Screencast UI dogfood still **out**.

### DRM / session (2026-08-06)

- [`drm.rs`](../../compositor/src/drm.rs) — `LibSeatSession`, primary GPU
  (`PROTEUS_DRM_DEVICE` override), **all** connected desktop connectors (side-by-side),
  GBM scanout, libinput, session pause/activate, `UdevBackend` hotplug resync.
- Screencopy: offscreen readback per crtc → `last_frame` +
  `drain_pending_screencopies_for`; shared [`dmabuf_init.rs`](../../compositor/src/dmabuf_init.rs).
- CLI: `--backend winit|drm` (env `PROTEUS_COMPOSITOR_BACKEND`); DRM failures
  exit non-zero (no silent winit fallback).
- Equal-column / dwindle / master tiling is **per output** (windows tagged with
  `Output::name()`; empty tag → primary). `dispatch movewindow output:<name>` +
  `dispatch focusoutput <name>` (pointer warp to output center).
- Helper: [`dev/smoke/compositor-drm.sh`](../../dev/smoke/compositor-drm.sh)
  — live prove only when `PROTEUS_COMPOSITOR_DRM=1` (free VT/VM); otherwise SKIP.
- Multi-GPU still **out**.

### xdg-decoration (2026-08-06)

- `XdgDecorationState` + `XdgDecorationHandler`: prefer `Mode::ClientSide` on
  new / unset (app chrome); SSD only for explicit `ServerSide`; sync
  `ToplevelRecord.ssd`.
- Thin SSD draw ([`decoration.rs`](../../compositor/src/decoration.rs)):
  `TITLEBAR_H=28` solid bar (+ minimize/maximize/close) + **cosmic-text title** via
  `MemoryRenderBuffer` (truncate/ellipsis); hits + drag-move; **double-click**
  titlebar maximize/restore; button **hover/press** colors.

### Displays Fact / modeset (2026-08-06)

- Fact: `~/.config/proteus/displays.json` (Settings write).
- Load at DRM/winit start ([`displays.rs`](../../compositor/src/displays.rs)):
  scale + position + transform; DRM mode match via connector modes + `use_mode`.
- Live: `dispatch output <name> scale|pos|mode|transform`; helper
  `proteus-settings-apply apply-displays`.
- Identify: `dispatch identify [secs]` (default 3) — centered connector-name
  badge per output ([`identify.rs`](../../compositor/src/identify.rs)).
- Settings: 10s snapshot Revert after Apply (Settings-owned; restore Fact + live).
- Settings orientation UI **In** (Normal/90/180/270); flipped transforms still Out.

### Session-wire (2026-08-06)

- [`shell/scripts/proteus-session`](../../shell/scripts/proteus-session): **smithay
  only**. Fact=`hyprland` refused (exit 1). Nested display / missing binary /
  fast DRM fail → exit 1 (greeter). Bare seat → `--backend drm -c proteus-chrome`.
- Install writes `compositor-engine=smithay`; does **not** seed `hyprland.conf`.
  Hyprland packages dropped from base.

### Dogfood gate (2026-08-06)

- Helper: [`dev/smoke/compositor-dogfood.sh`](../../dev/smoke/compositor-dogfood.sh)
  — static asserts + nested ctl prove; DRM via `PROTEUS_COMPOSITOR_DRM=1`; guest
  via `PROTEUS_GUEST=1` (Fact `smithay` + binary hard; `COMP_LIVE` soft-SKIP).
- Nested host path: [`dev/run-nested.sh`](../../dev/run-nested.sh) →
  compositor **winit** `-c proteus-chrome` (never Hyprland).

## Opt-in / rollback

- Build: `cargo build -p compositor` (not in `default-members`).
- Engine: empty / `smithay` → smithay; `hyprland` → **refused** by session.
- Nested: `./dev/run-nested.sh`.
- Run DRM (VT/VM): `./target/debug/proteus-compositor --backend drm`
  (optionally `-c …`); smoke: `PROTEUS_COMPOSITOR_DRM=1 ./dev/smoke/compositor-drm.sh`.

## Doctrine

Replace behind contracts, never carry patches. **Hyprland purged** as session
engine 2026-08-06. `env/hypr/` **deleted**. Settings apply via
`proteus-settings-apply` / compositorctl; idle is owned (`proteus-idle`); SSD
maximize hit + thin multi-GPU enumerate; Displays Fact load + live `output`
modeset + Identify flash; Settings 10s Revert; session Super keybinds
(`binds.rs` / `keybinds.json`) landed.

## Cosmic pattern peer (behavior only — never fork)

Skim of `cosmic-comp` (IndicatorShader / tiling chrome). **Borrow:** focused
window gets a thin accent outline (we use MemoryRenderBuffer, not their GLES
pixel shader); clearer default gaps so tiles read as separate seats. **Ignore:**
libcosmic / iced shell crates, corner-radius protocol, stack tabs, overview
backdrop shaders, pop-launcher. Proteus chrome stays in `proteus-shell`.

## Out

Flipped transform UI, deeper multi-GPU policy,
console-home gamescope swap, Settings keybind rebind editor,
blur/anim polish, flip shell lock default to protocol.
