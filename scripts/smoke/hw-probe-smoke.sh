#!/usr/bin/env bash
# Smoke: wave A probe emits valid JSON with required keys + thin remote sensor.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROBE="${ROOT}/services/proteus-hw-probe/proteus-hw-probe"
PY="${ROOT}/services/proteus-hw-probe/proteus_hw_probe.py"
HW="${ROOT}/shell/shared/Hardware.qml"
SP="${ROOT}/apps/proteus-settings/panes/SystemPane.qml"
fail=0
ok() { echo "hw-probe-smoke: OK $*"; }
die() { echo "hw-probe-smoke: FAIL $*" >&2; fail=1; }

[[ -x "${PROBE}" || -f "${PROBE}" ]] || die "missing proteus-hw-probe"
grep -q 'def has_remote_input\|input.remote' "${PY}" || die "probe missing has_remote_input / input.remote"
grep -q 'def has_bluetooth_hid_remote' "${PY}" || die "probe missing has_bluetooth_hid_remote"
grep -q 'remoteFromProbe\|remoteProbeStub' "${HW}" || die "Hardware.qml missing remoteFromProbe"
grep -q 'Remote input\|remoteFromProbe\|CEC\|Bluetooth' "${SP}" || die "SystemPane missing remote probe honesty"

out="$("${PROBE}" --compact)"
python3 -c "
import json, sys
d = json.loads(sys.argv[1])
assert d.get('schema') == 'proteus.hw.probe/v0', d
assert d.get('wave') == 'A', d
assert 'device_class' in d and d['device_class'], d
assert 'capabilities' in d and isinstance(d['capabilities'], dict), d
assert 'modules' in d and isinstance(d['modules'], dict), d
print('proteus-hw-probe smoke OK')
print('  class:', d['device_class'])
print('  caps:', ', '.join(sorted(d['capabilities'])) or '(none)')
" "${out}" || die "base probe JSON"

forced="$(PROTEUS_HW_PROBE_FORCE_REMOTE=1 "${PROBE}" --compact)"
echo "${forced}" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d.get("capabilities",{}).get("remote") is True, d.get("capabilities")
assert d.get("modules",{}).get("input.remote") is True, d.get("modules")
print("force-remote OK")
' || die "PROTEUS_HW_PROBE_FORCE_REMOTE must emit remote + input.remote"
ok "force-remote"

forced_bt="$(PROTEUS_HW_PROBE_FORCE_REMOTE_BT=1 "${PROBE}" --compact)"
echo "${forced_bt}" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d.get("capabilities",{}).get("remote") is True, d.get("capabilities")
assert d.get("modules",{}).get("input.remote") is True, d.get("modules")
print("force-remote-bt OK")
' || die "PROTEUS_HW_PROBE_FORCE_REMOTE_BT must emit remote + input.remote"
ok "force-remote-bt"

# Offline Bluetooth HID name heuristic (fixture — no real BT needed)
tmp="$(mktemp)"
trap 'rm -f "${tmp}"' EXIT
cat >"${tmp}" <<'EOF'
I: Bus=0005 Vendor=1234 Product=5678 Version=0111
N: Name="Acme Media Remote"
P: Phys=aa:bb:cc:dd:ee:ff
S: Sysfs=/devices/virtual/input/input99
H: Handlers=kbd event99
B: EV=100003

I: Bus=0005 Vendor=9999 Product=1111 Version=0111
N: Name="Generic Consumer Control"
P: Phys=11:22:33:44:55:66
S: Sysfs=/devices/virtual/input/input98
H: Handlers=kbd event98
B: EV=100003
EOF
ROOT="${ROOT}" PROTEUS_HW_PROBE_INPUT_DEVICES="${tmp}" python3 - <<'PY' || die "BT HID fixture heuristic"
import importlib.util
import os
from pathlib import Path

root = Path(os.environ["ROOT"])
spec = importlib.util.spec_from_file_location(
    "proteus_hw_probe", root / "services/proteus-hw-probe/proteus_hw_probe.py"
)
mod = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(mod)
assert mod.has_bluetooth_hid_remote() is True, "Acme Media Remote should match"
# Consumer Control alone must not match — rewrite fixture
path = Path(os.environ["PROTEUS_HW_PROBE_INPUT_DEVICES"])
path.write_text(
    'I: Bus=0005 Vendor=9999 Product=1111 Version=0111\n'
    'N: Name="Generic Consumer Control"\n'
    'P: Phys=11:22:33:44:55:66\n\n',
    encoding="utf-8",
)
assert mod.has_bluetooth_hid_remote() is False, "Consumer Control alone must not match"
print("bt-hid-fixture OK")
PY
ok "bt-hid-fixture"

[[ "${fail}" -eq 0 ]] || exit 1
ok "all"
