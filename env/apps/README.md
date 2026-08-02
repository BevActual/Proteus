# env/apps/ — app capability manifests

Declarative **requires** / **requiresAny** / **postures** / **prefers**
contracts for launcher gating. Spec: [APPLICATIONS.md](../../docs/proteus/APPLICATIONS.md).

| File | Role |
|------|------|
| `schema.json` | JSON Schema for one manifest object |
| `catalog.json` | Seed catalog (`manifests[]`) EnvGate loads at session start |

**EnvGate** (`shell/shared/EnvGate.qml`) prefers a catalog match (desktop id /
optional `match` regex) over category heuristics. Fail-open until
`Hardware.ready`. Unmatched DesktopEntries keep Wave A heuristics.

| Field | Enforcement |
|-------|-------------|
| `requires` / `requiresAny` | Hard (Hardware caps) |
| `postures` | Hard allow-list vs `SessionPosture` (empty = any) |
| `prefers` | Soft — Beacon subtitle + search boost; never blocks |
| `device_classes` / `adapts` | Schema only (still Out) |
