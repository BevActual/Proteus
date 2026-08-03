# proteus-hw-probe

Wave **A** hardware probe: classify `desktop` / `laptop` and emit modules +
capabilities JSON. Thin Wave **B** wedge: `input.remote` / `remote` from CEC,
IR (`/sys/class/rc`), lirc, or `PROTEUS_HW_PROBE_FORCE_REMOTE=1`.

```bash
./proteus-hw-probe
./proteus-hw-probe --compact
PROTEUS_HW_PROBE_FORCE_REMOTE=1 ./proteus-hw-probe --compact
../../dev/smoke/hw-probe-smoke.sh
```

Spec: [../../docs/proteus/HARDWARE.md](../../docs/proteus/HARDWARE.md).
QML stub without hardware: `PROTEUS_REMOTE_PROBE=1`.
