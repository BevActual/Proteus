# proteus-greetd

Privileged greetd config helper for Proteus Settings → Users.

```bash
proteus-greetd show
pkexec proteus-greetd set-autologin <user> [command]
pkexec proteus-greetd clear-autologin
proteus-greetd smoke
```

- **show** — JSON status (unit + `[initial_session]`); no root
- **set-autologin** — write `/etc/greetd/config.toml` `[initial_session]` (root / pkexec)
- **clear-autologin** — remove `[initial_session]` (root / pkexec)

Does **not** restart greetd (apply on next boot / logout → greeter). Default
command: `/usr/local/bin/proteus-session`.

```bash
cargo build --release
sudo ../../install/machine/install-proteus-greetd.sh
./scripts/smoke/users-smoke.sh
```
