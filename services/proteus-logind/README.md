# proteus-logind

Privileged logind policy writer for Proteus Settings → Power. Settings proposes
idle/lid values, then runs:

```bash
pkexec /usr/local/libexec/proteus-logind set IdleAction=suspend IdleActionSec=30min …
pkexec /usr/local/libexec/proteus-logind unset IdleActionSec
pkexec /usr/local/libexec/proteus-logind clear
pkexec /usr/local/libexec/proteus-logind show
```

## Commands

| Action | Effect |
|--------|--------|
| `set Key=value…` | Write `/etc/systemd/logind.conf.d/99-proteus.conf` (merge), **reload** `systemd-logind` (not restart — restart drops the Wayland seat) |
| `unset Key…` | Remove key(s) from the Proteus drop-in (delete file if empty), reload logind |
| `clear` | Remove the Proteus drop-in, reload logind |
| `show` | Print effective keys as JSON (main conf + drop-ins; no root required) |

Allowlisted keys: `IdleAction`, `IdleActionSec`, `HandleLidSwitch`,
`HandleLidSwitchExternalPower`. Action values: `ignore`, `lock`, `suspend`,
`hibernate`, `hybrid-sleep`, `suspend-then-hibernate`, `poweroff`.
`IdleActionSec` must be a systemd timespan (`5min`, `1h`, bare seconds, …).

Must run as root via `pkexec` for `set` / `clear`.

## Build / install

```bash
cd services/proteus-logind && cargo build --release
# guest / host install:
sudo ../../install/machine/install-proteus-logind.sh
# or via settings install when a release binary exists:
sudo ../../install/machine/install-settings-app.sh
```

Polkit policy: `org.bevington.proteus.logind.policy` → `/usr/share/polkit-1/actions/`.

## STACK

Privileged mutators are Rust CLIs (+ polkit), not Python. See `docs/proteus/STACK.md`.
