# COMPOSITOR-SPIKE — Smithay rung 2 (honest status)

> Spike record for the owned-compositor rung ([OWNED-STACK.md](./OWNED-STACK.md)).
> **Hyprland stays the shipping compositor.** This spike is nested-only and
> opt-in; nothing in the install path references it.

## What exists (2026-08-05)

`compositor-next/` — minimal Smithay 0.7 compositor, ~1k lines, smallvil-derived:

| Piece | Status |
|-------|--------|
| winit backend (nested window as output) | `works` |
| xdg-shell toplevels (map, popups; no move/resize grabs) | `works` |
| wlr-layer-shell (map/arrange/anchor, exclusive zones via `layer_map`) | `works` |
| wp_viewporter + wp_fractional_scale | `works` — iced_layershell clients hard-require viewporter |
| Input routing (pointer/keyboard, layers above windows) | `thin` |
| Session takeover / DRM / libinput backend | **out** — spike is nested winit only |

## Prove (2026-08-05, host nested run)

```
./target/debug/proteus-compositor-next -c ./target/debug/proteus-shell --face desktop
proteus-compositor-next: nested spike on WAYLAND_DISPLAY=wayland-2
proteus-compositor-next: layer mapped: proteus-bar
proteus-compositor-next: layer mapped: proteus-dock
proteus-compositor-next: layer mapped: proteus-launcher
proteus-compositor-next: layer mapped: proteus-control-center
proteus-compositor-next: layer mapped: proteus-hud
proteus-compositor-next: layer mapped: proteus-bg
proteus-compositor-next: layer mapped: proteus-desktop-widgets
proteus-compositor-next: layer mapped: proteus-toast
proteus-compositor-next: layer mapped: proteus-privacy-ask
proteus-compositor-next: layer mapped: proteus-lock
```

All ten `proteus-shell` chrome layers map and render inside the spike with no
client panic (first run without viewporter panicked iced_layershell — fixed by
adding `ViewporterState` / `FractionalScaleManagerState`).

## Opt-in

- Build: `cargo build -p compositor-next` (not in `default-members`).
- Engine fact: `resolve_compositor_engine()` accepts `smithay` from
  `PROTEUS_COMPOSITOR_ENGINE` / `~/.config/proteus/compositor-engine`;
  default stays `hyprland`; unknown values fall through with an honest eprintln.
- Run nested: `./target/debug/proteus-compositor-next -c proteus-shell --face desktop`.

## Doctrine

Replace behind contracts, never carry patches (no Hyprland fork). Rung-1 gates
closed 2026-08-05, which permits this rung-2 spike. Next rung step — hyprctl/IPC
contract shims so `proteus-shell` workspace/toplevel state works without
Hyprland — does not start before this spike's gates are honest in this file.

## Out

DRM/session takeover, libinput, xdg-decoration, screencopy, multi-output,
move/resize grabs, popup grabs.
