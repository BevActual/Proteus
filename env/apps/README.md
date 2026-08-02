# env/apps — app capability manifests

Declarative **requires** / **requiresAny** / **postures** / **prefers** /
**device_classes** / **adapts** / **permissions** contracts for launcher gating.
Spec: [APPLICATIONS.md](../../docs/proteus/APPLICATIONS.md).

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
| `device_classes` | Hard allow-list vs `Hardware.deviceClass` (empty = any) |
| `prefers` | Soft — Beacon subtitle + search boost; never blocks |
| `adapts` | Soft shaping — `appAdaptProfile` / Beacon hint / `PROTEUS_ADAPT_*` launch env; never blocks |
| `permissions` | Hard via `Permissions` (Ask ≠ Deny; fail-closed until ready) |

`adapts.panes` resolves via `FocusMode.paneDensity` (Focus on → minimal). Soft
hint + launch env for apps; **Settings** hard-hides non-allowlisted hubs/leaves
when Focus is on (Desktop→Focus · Privacy · Users · Notifications · About stay).
`proteus-settings` catalog entry is the first-party consumer (`AdaptEnv` · About).
`input: remote` resolves via `Hardware.has("remote")` — probe CEC/IR/lirc /
Bluetooth HID remote-like names or soft `PROTEUS_REMOTE_PROBE=1` stub.
