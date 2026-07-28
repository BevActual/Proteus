---
doc: facts
role: reference
audience: coding agents, contributors
last_updated: "2026-07-28"
doc_status: active
scope: On-disk truth paths; QML façade vs services mutators
related:
  - CONFIG-SCHEMA.md
  - ARCHITECTURE.md
  - STACK.md
  - CURRENT.md
---

# Proteus — system facts

Truth lives on **disk / CLI**. QML singletons are façades. Prefer this map
before inventing a second store.

## Paths

| Path | Owner (write) | Readers |
|------|---------------|---------|
| `~/.config/proteus/settings.json` | `Config.qml` FileView | Background, Widgets, Theme, Audio prefs, … |
| `~/.config/proteus/keybinds.json` | `Keybinds.qml` | Hyprland bind generator |
| `~/.config/proteus/hw-probe.json` | `proteus-hw-probe` / `Hardware.qml` cache | EnvGate, Settings About |
| `~/.config/hypr/proteus-general.conf` | `Config` / `ConfigHypr` | Hyprland `source =` |
| `~/.config/hypr/proteus-keybinds.conf` | `Keybinds.qml` | Hyprland |
| `~/.config/hypr/proteus-monitors.conf` | `Displays.qml` | Hyprland |
| `~/.local/share/proteus/backgrounds/` | Background daily/album flows | `proteus-bg` / wallpaper runner |

Seed templates for nested/host sessions: [`env/`](../../env/) — see
[`env/README.md`](../../env/README.md). Guest installers that **place** those
facts: [`vm/guest/`](../../vm/guest/).

## QML façade vs services

| Kind | Stack | Rule |
|------|-------|------|
| Preference / chrome state | QML (`shell/shared/…`) | One Config schema; domain façades mutate via FileView or thin helpers |
| Read-only discovery | Python OK (`services/proteus-hw-probe`) | JSON out; no privileged write |
| Privileged mutation | Rust CLI (`services/proteus-pkg`, …) + polkit | Settings proposes → confirm → helper |

**Do not** add silent Python helpers for privileged mutation. **Do not** grow a
second `settings-*.json` per posture.

## Shared package layout

Public API stays `import "../../shared"` (Settings: `shared` symlink).

```
shell/shared/qmldir          # registers singletons
  chrome/Theme.qml
  config/Config.qml + ConfigHypr.qml
  background/Background.qml + Catalog/Daily/Apply
  widgets/Widgets.qml + Lock/Desktop
  system/…  session/…
```

Schema key groups: [CONFIG-SCHEMA.md](./CONFIG-SCHEMA.md).
