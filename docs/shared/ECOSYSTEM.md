---
doc: ecosystem
role: context
audience: contributors, coding agents
last_updated: "2026-07-26"
doc_status: active
scope: Bevington product frame including Proteus as host OS
related:
  - ../proteus/POSITIONING.md
  - ../proteus/ARCHITECTURE.md
---

# Ecosystem — Bevington products

Active set around this company orbit:

| Product | Repo | Role |
|---------|------|------|
| **Rowena** | `~/Projects/Rowena` | Local-first writing IDE |
| **Meridian** | `~/Projects/Meridian` | Models / providers / hub |
| **Mobius** | `~/Projects/Mobius` | Agent harness + **company loop SoT** |
| **Proteus** | `~/Projects/Proteus` | Adaptive **host OS** (postures) |

```
                    ┌─────────────┐
                    │  Meridian   │  models / credentials
                    └──────┬──────┘
                           │
        ┌──────────────────┼──────────────────┐
        ▼                  ▼                  ▼
   ┌─────────┐       ┌─────────┐        ┌─────────┐
   │ Rowena  │       │ Mobius  │        │  …apps  │
   └────┬────┘       └────┬────┘        └────┬────┘
        │                 │                  │
        └────────────┬────┴──────────────────┘
                     ▼
              ┌─────────────┐
              │   Proteus   │  environment / postures
              └─────────────┘
```

- **Proteus** does not own the company Track/queue (Mobius) or model hub (Meridian).
- **Rowena / Mobius** remain thin clients of Meridian for models.
- Insights flow both ways: Proteus Settings/chrome patterns can improve Rowena;
  Rowena tokens/IA and Meridian smoke/gates inform Proteus.

Company loop kickoffs (`loop`, `standing`, …): **Mobius** `AGENTS.md` /
`docs/ISSUES.md`. Override sibling roots with `MOBIUS_ROOT` / `ROWENA_ROOT` /
`MERIDIAN_ROOT` if needed.
