---
doc: chrome
role: reference
audience: UI, contributors, coding agents
last_updated: "2026-07-28"
doc_status: active
scope: Proteus chrome language — principles, tokens, Settings patterns (company reference)
related:
  - SETTINGS-IA.md
  - CURRENT.md
  - ARCHITECTURE.md
  - ../shared/ECOSYSTEM.md
  - ../../shell/shared/Theme.qml
status_legend:
  shipped: Live in Theme.qml / Settings panes today
  planned: Named for sibling binding; export under env/chrome/ is shipped
---

# Proteus chrome — design lock

**Company chrome reference.** Host shell + Settings define the visual language
sibling apps should match for *frames* (lists, sheets, bars, chrome). Product
*canvases* (e.g. Rowena writing modes) stay free — **chrome ≠ canvas**.

**Live binding:** [`shell/shared/Theme.qml`](../../shell/shared/Theme.qml)  
**IA / UX locks:** [SETTINGS-IA.md](./SETTINGS-IA.md) §8  
**Out this door:** Theme value churn, Rowena CSS retarget, new Settings panes.
Token export lives under `env/chrome/` (this serial door 5/5).

## Document map

| Section | Contents |
|---------|----------|
| [1. Principles](#1-principles) | Calm chrome; accent = action; legibility |
| [2. Surfaces](#2-surfaces) | Light / dark fills |
| [3. Text](#3-text) | Roles |
| [4. Accent & danger](#4-accent--danger) | Selection / action only |
| [5. Chrome fills](#5-chrome-fills) | Transparency / blur plates |
| [6. Space](#6-space) | 4px grid |
| [7. Radius](#7-radius) | Control corners |
| [8. Type](#8-type) | Family + sizes from Config |
| [9. Patterns](#9-patterns) | Settings composition kit |
| [10. Sibling map](#10-sibling-map) | How Rowena / others consume |

---

## 1. Principles

1. **One chrome language.** Bar, dock, Control Center, Settings, lock Customize,
   toasts — same space / radius / text roles / accent rules. Per-control inventing
   is a defect.
2. **Chrome ≠ canvas.** Theme tokens paint OS chrome and Settings. First-party
   apps may theme their *content* surface (manuscript, media stage) without
   rewriting the frame.
3. **Accent = selection / action only.** Never decoration wash, glow filler, or
   gradient chrome. Use accent for selection, primary actions, focus, running
   dots — not backgrounds or dividers.
4. **Calm chrome.** Discoverability without permanent label clutter. Grouped
   lists, soft selection, large titles (System Settings posture).
5. **Legibility floor.** Prefs (opacity, accent, font) must not produce
   unreadable UI. Transparency may clear the plate; text contrast stays.
6. **Host posture reuses Settings.** Do not invent a second control center for
   host / hypervisor chrome.

---

## 2. Surfaces

From `Theme.qml` (`Config.chromeMode` → `light`).

| Token | Light | Dark | Use |
|-------|-------|------|-----|
| `bg` | `#f2f2f7` | `#000000` | Grouped-background canvas |
| `bgPanel` | `#e8e8ed` | `#1c1c1e` | Panel / chrome plate |
| `bgElevated` | `#ffffff` | `#1c1c1e` | Inset list cards / elevated sheets |
| `bgHover` | `#e5e5ea` | `#2c2c2e` | Row / control hover |
| `border` | `#d1d1d6` | `#2c2c2e` | Hairline borders |
| `separator` | black @ 29% | white @ 10% | List separators |

---

## 3. Text

| Token | Light | Dark | Use |
|-------|-------|------|-----|
| `text` | `#1c1c1e` | `#f5f5f7` | Primary labels |
| `textDim` | `#636366` | `#98989d` | Secondary / values |
| `textMute` | `#8e8e93` | `#636366` | Hints / fact lines |

---

## 4. Accent & danger

| Token | Source | Use |
|-------|--------|-----|
| `accent` | `Config.accentColor` | Selection, primary action, focus |
| `accentSoft` | accent @ 14% light / 22% dark | Soft selection wash |
| `danger` | `#ff453a` | Destructive / critical only |

---

## 5. Chrome fills

Alpha tracks `Config.chromeOpacity` (`chromeAlpha` / `glassAlpha`). Blur flag:
`Config.chromeBlur`.

| Token | Recipe | Use |
|-------|--------|-----|
| `panelFill` | `bgPanel` × alpha | Top bar / dock plate |
| `elevatedFill` | `bgElevated` × alpha | Floating panels |
| `chromeHover` | `bgHover` × alpha | Hover on chrome |
| `chromeBorder` | `border` × alpha | Chrome edges |
| `chromeAccentFill` | `accent` × alpha | Accent on chrome |
| `chromeAccentSoft` | accent × alpha × (0.22 light / 0.28 dark) | Soft accent on chrome |
| `scrimFill` | `bg` × (0.28 light / 0.45 dark) × max(alpha, 0.4) | Dim overlays |
| `glassAlpha` | linear opacity; soft floor only when blur on | Bar / dock frost amount |
| `menuBarFill` / `dockPlateFill` | frosted plate × `glassAlpha` | Menu bar · Dock shelf |
| `chromeHairline` | black/white @ ~8–12% (hidden when clear) | Hairlines on glass chrome |
| `chromeClear` | `chromeAlpha < 0.01` | Fully clear plate |

Opacity is live in QML; blur layerrules debounce and reload only on toggle (not every slider tick).

---

## 6. Space

**Base unit = 4px.**

| Token | px | Typical use |
|-------|---:|-------------|
| `spaceXs` | 4 | Hair gaps |
| `spaceSm` | 8 | Compact padding |
| `spaceMd` | 12 | Default form rhythm |
| `spaceLg` | 16 | Section gaps |
| `spaceXl` | 24 | Pane margins |

---

## 7. Radius

| Token | px | Typical use |
|-------|---:|-------------|
| `radiusSm` | 6 | Compact controls |
| `radius` | 8 | Default |
| `radiusMd` | 10 | Cards / groups |
| `radiusLg` | 12 | Larger sheets |
| `radiusXl` | 16 | Soft panels |
| `radiusPill` | 22 | Segmented / true pills sparingly |

---

## 8. Type

| Token | Source | Notes |
|-------|--------|-------|
| `fontFamily` | `Config.fontFamily` | System / user pick |
| `fontSize` | `Config.fontSize` | Body |
| `fontSizeSm` | `Config.fontSizeSm` | Hints / fact lines |

Chrome type stays neutral; expressive faces belong on product canvases, not
Settings lists.

---

## 9. Patterns

Composition kit under `apps/proteus-settings/kit/` (panes import `../kit`;
shell surfaces that rhyme):

| Pattern | Role |
|---------|------|
| **Settings hub › leaf** | Category list → one control leaf; Esc / ‹ back |
| **SettingsGroup** | Titled grouped list |
| **SettingsFormRow** | Label + hint + trailing control |
| **SettingsHubList** | › rows into sub-settings |
| **SettingsSegmented** | Exclusive segment pick |
| **Fact line** | Mute one-liner naming the on-disk / CLI fact |

Shell chrome (TopBar, Dock, Control Center, lock Customize) should reuse the
same space/radius/text/accent rules even when not importing those QML types.

---

## 10. Sibling map

| Consumer | Expected binding | Status |
|----------|------------------|--------|
| Proteus QML | `Theme.*` | `shipped` |
| Shared export | `env/chrome/chrome-tokens.json` + `chrome-tokens.css` | `shipped` (static mirror of tables) |
| Rowena shell chrome | Map `--proteus-*` / `--shell-*` toward this table; keep mode canvas separate | `partial` — CSS vars available; app retarget later |

When in doubt: open Settings on Proteus, then match the *frame*, not the
wallpaper.
