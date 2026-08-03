# shell/shared/ — shared spine (flat)

Quickshell **directory import** package. Settings reaches it via
`apps/proteus-settings/shared` → here.

## Hard rule

Keep **pragma Singleton** façades and their helpers in **this directory**.
Do not put them in domain subdirs (`chrome/`, `config/`, …) or behind
`qmldir` — that hits load-order cycles (`Invalid alias reference`).

## Naming

| Prefix | Role |
|--------|------|
| `Theme` | Chrome tokens |
| `ChromeMenuPlate` | Glass context-menu plate (dock kit seed) |
| `Config` / `ConfigHypr` | `settings.json` FileView + Hypr apply |
| `Background*` | Wallpaper / lock backdrop (Catalog · Daily · Apply) |
| `Widgets*` | Lock / desktop applets (Lock · Desktop) |
| `UniversalSearch` | Shared Apps-mode allowlist + scoring (Beacon + console Search) |
| Others | System / session façades (`Hardware`, `EnvGate`, `Keybinds`, …) |

**Ownership:** Config owns FileView only — no `property alias` to Background.
Background reads/writes `Config.*` fields. Details: [FACTS.md](../../docs/proteus/FACTS.md).

Gate: `./dev/smoke/layout-smoke.sh` · full suite: `./dev/smoke-all.sh`
