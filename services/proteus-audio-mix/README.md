# proteus-audio-mix

Resident (session-scoped) mixer helper for Proteus Settings → Sound → Mixer /
Apps. Owns **cached dump** + **row peaks** while the leaf is open; mutations
stay on `shell/scripts/audio-mix.py` for now.

```bash
proteus-audio-mix dump
proteus-audio-mix serve --dump-ms 4500 [--peaks sink…]
```

## Protocol (`serve`)

Stdout NDJSON (one object per line):

| Line | Shape |
|------|--------|
| dump | `{"t":"dump","ok":true,"channels":[…],…}` — same fields as `audio-mix.py dump` |
| peaks | `{"t":"peaks","v":{"proteus_mix_system":12,…}}` |

Stdin / control FIFO lines:

| Cmd | Effect |
|-----|--------|
| `dump` | Emit a dump immediately |
| `peaks sink…` | Replace peak sink list (empty → stop peaks) |
| `pause` / `resume` | Pause / resume periodic dumps (drag reorder) |
| `quit` | Exit |

Optional `--ctl PATH`: also read the same line protocol from a FIFO (clients
write via `echo dump > "$XDG_RUNTIME_DIR/proteus-audio-mix.ctl"`).

## Build / install

```bash
cd services/proteus-audio-mix && cargo build --release
sudo ../../install/machine/install-proteus-audio-mix.sh
```

No polkit — session `pactl` / `parec` only.
