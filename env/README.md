# env/ — host / nested session seeds

Templates for **nested** Proteus (`scripts/run-nested.sh`) and copy-sources
for guest overlay install.

| Path | Role |
|------|------|
| `hypr/` | Hyprland nested template + proteus-*.conf fragments |
| `ghostty/` | Minimal Ghostty seed (no opacity/blur) |
| `fastfetch/` | P monogram + modules on shell start |
| `shell/proteus-bashrc.sh` | Run fastfetch when Ghostty opens |

**vs `vm/guest/`:** guest scripts *install* session pieces onto the dogfood VM.
`env/` seeds the same *kinds* of facts for nested / first boot.

Live truth still under `~/.config/hypr/` and `~/.config/proteus/`
([FACTS.md](../docs/proteus/FACTS.md)). Terminal details: [README-terminal.md](./README-terminal.md).
