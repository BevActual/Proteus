---
doc: ecosystem
role: context
audience: contributors, coding agents
last_updated: "2026-07-28"
doc_status: active
scope: Bevington product frame including Proteus as host OS
related:
  - ../proteus/POSITIONING.md
  - ../proteus/ARCHITECTURE.md
  - ../proteus/CHROME.md
  - ../ISSUES.md
  - ../../../Mobius/docs/shared/ECOSYSTEM.md
---

# Ecosystem — Bevington products

**This file is Proteus’s seat map** for the company orbit. Company queue /
Track SoT remains Mobius ([ISSUES.md](../ISSUES.md) → Mobius). Sibling `docs/shared/ECOSYSTEM.md` copies (Mobius / Meridian / Rowena /
Proteus) share the **apps + host OS** frame — treat **Proteus as the host
environment under apps**, not a fourth peer writing/AI product.

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
  Rowena tokens/IA and Meridian smoke/gates inform Proteus. Chrome language SoT:
  [proteus/CHROME.md](../proteus/CHROME.md) (`Theme.qml` binding).
- Company licensing sketches (if needed): Mobius / Rowena
  `docs/shared/company-policies.md` — not duplicated here.

Company loop kickoffs (`loop`, `standing`, …): **Mobius** `AGENTS.md` /
`docs/ISSUES.md`. Override sibling roots with `MOBIUS_ROOT` / `ROWENA_ROOT` /
`MERIDIAN_ROOT` / `PROTEUS_ROOT` if needed.
