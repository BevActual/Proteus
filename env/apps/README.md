# env/apps — app capability manifests

Declarative **requires** / **requiresAny** / **postures** / **prefers** /
**device_classes** / **adapts** / **permissions** contracts for launcher gating.
Spec: [APPLICATIONS.md](../../docs/proteus/APPLICATIONS.md).

| File | Role |
|------|------|
| `schema.json` | JSON Schema for one manifest object |
| `catalog.json` | Seed catalog (`manifests[]`) shell-core loads at session start |

**shell-core** (`services/proteus-shell-core`) prefers a catalog match (desktop id /
optional `match` regex) over category heuristics. Fail-open until hardware
probe is ready. Unmatched DesktopEntries keep Wave A heuristics.

| Field | Enforcement |
|-------|-------------|
| `requires` / `requiresAny` | Hard (probe caps) |
| `postures` | Hard allow-list vs session posture (empty = any) |
| `device_classes` | Hard allow-list vs probe `device_class` (empty = any) |
| `prefers` | Soft — Beacon subtitle + search boost; never blocks |
| `adapts` | Soft shaping — `appAdaptProfile` / Beacon hint / `PROTEUS_ADAPT_*` launch env; never blocks |
| `permissions` | Hard via permissions store (Ask ≠ Deny; fail-closed until ready) |

`adapts.panes` resolves via Focus pane density (Focus on → minimal). Soft
hint + launch env for apps; **Settings** hard-hides non-allowlisted hubs/leaves
when Focus is on (Desktop→Focus · Privacy · Users · Notifications · About stay).
`proteus-settings` catalog entry is the first-party consumer. `input: remote`
resolves via probe remote capability — CEC/IR/lirc / Bluetooth HID remote-like
names or soft `PROTEUS_REMOTE_PROBE=1` stub.
