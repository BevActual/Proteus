# proteus-battery-threshold

Privileged (pkexec) helper for Settings → Power **Charge limits**.

Reads/writes sysfs `charge_control_start_threshold` /
`charge_control_end_threshold` when the kernel exposes them. Fail-closed when
absent. **TLP stays Out** — this never edits `/etc/tlp.conf`.

```bash
cargo build --release
sudo bash vm/guest/install-proteus-battery-threshold.sh
proteus-battery-threshold show
pkexec proteus-battery-threshold set --start 40 --end 80
```

Fixture: `PROTEUS_BATTERY_THRESHOLD_FIXTURE=1`.
