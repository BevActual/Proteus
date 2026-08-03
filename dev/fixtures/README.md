# dev/fixtures — fixtures for smoke gates

Not a QML unit-test runner. Live truth still lives under `~/.config/proteus/`
([FACTS.md](../../docs/proteus/FACTS.md)). These files seed and pin shapes for
host smokes under [`dev/smoke/`](../smoke/).

| Path | Role |
|------|------|
| `fixtures/settings.minimal.json` | Minimal valid `settings.json` (⊆ Config FileView keys); also used by `config-roundtrip-smoke` |
| `fixtures/hw-probe.sample.json` | Wave A probe shape reference (live gate: `hw-probe-smoke.sh`) |

Schema inventory: [CONFIG-SCHEMA.md](../../docs/proteus/CONFIG-SCHEMA.md).  
Run: `./dev/smoke-all.sh` (all `dev/smoke/*-smoke.sh`; guest smokes skip unless SSH / `PROTEUS_GUEST=1`).
