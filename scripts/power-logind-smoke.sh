#!/usr/bin/env bash
# power-logind-smoke — host static checks for proteus-logind + Settings Power wiring
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
ok() { echo "power-logind-smoke: OK $*"; }
die() { echo "power-logind-smoke: FAIL $*" >&2; fail=1; }

PKG="${ROOT}/services/proteus-logind"
[[ -f "${PKG}/Cargo.toml" ]] || die "missing Cargo.toml"
[[ -f "${PKG}/src/main.rs" ]] || die "missing src/main.rs"
[[ -f "${PKG}/org.bevington.proteus.logind.policy" ]] || die "missing polkit policy"
grep -q 'org.bevington.proteus.logind' "${PKG}/org.bevington.proteus.logind.policy" \
  || die "policy action id"
[[ -x "${ROOT}/vm/guest/install-proteus-logind.sh" ]] || die "install-proteus-logind.sh"
grep -q 'install-proteus-logind' "${ROOT}/vm/guest/install-settings-app.sh" \
  || die "settings-app install hook"

grep -q 'setLogindPolicy' "${ROOT}/shell/shared/Power.qml" || die "Power.qml setLogindPolicy"
grep -q 'logind.conf.d' "${ROOT}/shell/shared/Power.qml" || die "Power.qml drop-in merge"
grep -q 'openInstallHelper' "${ROOT}/shell/shared/Power.qml" || die "Power.qml openInstallHelper"
grep -q '/usr/local/libexec/proteus-logind' "${ROOT}/shell/shared/Power.qml" \
  || die "Power.qml resolves libexec wrapper"
grep -q 'setProfile' "${ROOT}/shell/shared/Power.qml" || die "Power.qml setProfile"
grep -q 'powerprofilesctl' "${ROOT}/shell/shared/Power.qml" || die "Power.qml powerprofilesctl"
grep -q 'power-saver' "${ROOT}/shell/shared/Power.qml" || die "Power.qml eco→power-saver map"
grep -q 'proteus-logind' "${ROOT}/apps/proteus-settings/panes/PowerPane.qml" \
  || die "PowerPane cites helper"
grep -q 'SettingsSegmented' "${ROOT}/apps/proteus-settings/panes/PowerPane.qml" \
  || die "PowerPane profile segmented"
grep -q 'Power.setProfile' "${ROOT}/shell/surfaces/desktop/QuickSettingsGrid.qml" \
  || die "CC Power tile setProfile"

BIN=""
if [[ -x "${PKG}/bin/proteus-logind" ]]; then
  BIN="${PKG}/bin/proteus-logind"
elif [[ -x "${PKG}/target/release/proteus-logind" ]]; then
  BIN="${PKG}/target/release/proteus-logind"
fi
if [[ -n "${BIN}" ]]; then
  "${BIN}" show >/dev/null || die "show"
  if out="$("${BIN}" set IdleAction=bogus 2>&1)"; then
    die "invalid IdleAction should fail"
  else
    echo "$out" | grep -q 'invalid IdleAction' || die "invalid IdleAction message"
    ok "rejects invalid IdleAction"
  fi
  if "${BIN}" set IdleAction=suspend 2>/dev/null; then
    die "set without root should fail"
  else
    ok "set refuses non-root"
  fi
  ok "CLI ${BIN}"
else
  echo "power-logind-smoke: note — no release binary (build with cargo build --release)"
fi

ok "sources + wiring"
[[ "${fail}" -eq 0 ]] || { echo "power-logind-smoke: FAILED" >&2; exit 1; }
echo "power-logind-smoke: OK"
