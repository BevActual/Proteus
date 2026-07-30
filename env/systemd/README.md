# env/systemd — optional user units

| Unit | Role |
|------|------|
| `user/proteus-qs.service` | Optional supervisor for desktop chrome via `proteus-qs` |

**Default dogfood** still starts chrome from Hyprland `exec-once` (see
`env/hypr/hyprland.conf`). The user unit is an opt-in alternative:

```bash
bash /mnt/proteus/vm/guest/install-proteus-qs-user-unit.sh
systemctl --user enable --now proteus-qs.service
# Comment out the proteus-qs exec-once line in ~/.config/hypr/hyprland.conf
```

Do **not** IgnorePkg-pin Quickshell on rolling Arch ([COMPOSITOR.md](../../docs/proteus/COMPOSITOR.md)).
