# env/ — the default environment Proteus ships

Config templates, app manifests and design tokens that define what Proteus looks
like out of the box. **Not install-only.** Three different consumers read this
tree, which is why it is not folded into `install/`:

| Consumer | Reads | When |
|----------|-------|------|
| **Runtime** | `apps/catalog.json` via `EnvGate.qml`; `hypr/profiles/*` via `shell/scripts/set-hypr-profile.sh` | while Proteus is running — including during a posture flip |
| **Installer** | `hypr/` · `ghostty/` · `fastfetch/` · `shell/` · `systemd/` | `install/config.sh` seeds them into `$HOME` on first install |
| **Dev harness** | `hypr/` · `ghostty/` · `fastfetch/` · `shell/` | `dev/run-nested.sh` seeds a nested session; smoke gates assert template content |

| Path | Role |
|------|------|
| `hypr/` | Hyprland template + `proteus-*.conf` fragments + posture `profiles/` |
| `apps/` | App capability manifests (`catalog.json` · `schema.json`) for EnvGate |
| `chrome/` | Sibling chrome token export (JSON + CSS vars) |
| `ghostty/` | Minimal Ghostty seed (no opacity/blur) |
| `fastfetch/` | P monogram + modules on shell start |
| `shell/proteus-bashrc.sh` | Run fastfetch when Ghostty opens |
| `systemd/user/` | Optional `proteus-qs.service` (opt-in vs hypr exec-once) |

## Two things that must not move

- **`apps/` is resolved at runtime** as `Quickshell.shellRoot + "/../env/apps/…"`
  ([EnvGate.qml](../shell/shared/EnvGate.qml)). `env/` has to stay adjacent to
  `shell/`; relocating it breaks the shell, not just the installer.
- **`chrome/` is a published cross-repo contract** — sibling products consume the
  token export ([CHROME.md](../docs/proteus/CHROME.md)). Its path is an external
  interface, not an internal detail.

## vs `install/`

`install/` *acts* on a machine: it copies these files into `$HOME` and `/etc`,
installs packages, writes Facts. `env/` is inert data with no opinion about where
it is going — the same `hypr/profiles/console.conf` is copied by the installer,
seeded by the nested dev runner, and installed live by a posture flip.

Live truth still lives under `~/.config/hypr/` and `~/.config/proteus/`
([FACTS.md](../docs/proteus/FACTS.md)). Terminal details:
[README-terminal.md](./README-terminal.md).
