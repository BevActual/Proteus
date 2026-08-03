#!/usr/bin/env bash
# power-threshold-smoke — host static checks for charge limits + helper
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fail=0
ok() { echo "power-threshold-smoke: OK $*"; }
die() { echo "power-threshold-smoke: FAIL $*" >&2; fail=1; }

PKG="${ROOT}/services/proteus-battery-threshold"
[[ -f "${PKG}/Cargo.toml" ]] || die "missing Cargo.toml"
[[ -f "${PKG}/src/main.rs" ]] || die "missing src/main.rs"
[[ -f "${PKG}/org.bevington.proteus.battery-threshold.policy" ]] || die "missing polkit policy"
grep -q 'org.bevington.proteus.battery-threshold' \
  "${PKG}/org.bevington.proteus.battery-threshold.policy" || die "policy action id"
[[ -x "${ROOT}/install/machine/install-proteus-battery-threshold.sh" ]] \
  || die "install-proteus-battery-threshold.sh"
grep -q 'install-proteus-battery-threshold' "${ROOT}/install/machine/install-settings-app.sh" \
  || die "settings-app install hook"
ok "package + install"

grep -q 'chargeThresholdsAvailable\|refreshChargeThresholds\|proteus-battery-threshold' \
  "${ROOT}/shell/shared/Power.qml" || die "Power.qml missing charge threshold API"
grep -q 'setChargeThresholds\|charge_control' "${ROOT}/shell/shared/Power.qml" \
  || die "Power.qml missing setChargeThresholds"
grep -q 'Charge limits\|chargeThresholdsAvailable\|ThemeSlider' \
  "${ROOT}/apps/proteus-settings/panes/PowerPane.qml" \
  || die "PowerPane missing Charge limits UI"
grep -qiE 'TLP Out|charge_control' \
  "${ROOT}/apps/proteus-settings/panes/PowerPane.qml" \
  || die "PowerPane must keep TLP Out honesty"
ok "wiring"

BIN=""
if [[ -x "${PKG}/bin/proteus-battery-threshold" ]]; then
  BIN="${PKG}/bin/proteus-battery-threshold"
elif [[ -x "${PKG}/target/release/proteus-battery-threshold" ]]; then
  BIN="${PKG}/target/release/proteus-battery-threshold"
fi
if [[ -n "${BIN}" ]]; then
  PROTEUS_BATTERY_THRESHOLD_FIXTURE=1 "${BIN}" show | python3 -c 'import json,sys
d=json.load(sys.stdin)
assert d.get("ok") is True and d.get("supported") is True
assert int(d.get("start") or 0) == 40 and int(d.get("end") or 0) == 80
' || die "show fixture"
  PROTEUS_BATTERY_THRESHOLD_FIXTURE=1 "${BIN}" set --start 40 --end 80 \
    | python3 -c 'import json,sys
d=json.load(sys.stdin)
assert d.get("ok") is True and d.get("action")=="set"
' || die "set fixture"
  if "${BIN}" set --start 40 --end 80 2>/dev/null; then
    die "set without root should fail (non-fixture)"
  else
    ok "set refuses non-root"
  fi
  if out="$("${BIN}" set --start 90 --end 80 2>&1)"; then
    die "start>=end should fail"
  else
    echo "$out" | grep -qiE 'less than|start' || die "start>=end message"
    ok "rejects start>=end"
  fi
  ok "CLI ${BIN}"
else
  echo "power-threshold-smoke: note — no release binary (cargo build --release)"
fi

[[ "${fail}" -eq 0 ]] || { echo "power-threshold-smoke: FAILED" >&2; exit 1; }
echo "power-threshold-smoke: OK"
