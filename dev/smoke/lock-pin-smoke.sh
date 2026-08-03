#!/usr/bin/env bash
# lock-pin-smoke — hashed unlock PIN store/verify + helper wiring (no PAM)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fail=0
ok() { echo "lock-pin-smoke: OK $*"; }
die() { echo "lock-pin-smoke: FAIL $*" >&2; fail=1; }

AUTH="${ROOT}/shell/scripts/proteus_auth.py"
UNLOCK="${ROOT}/shell/scripts/check-unlock.py"
PINCLI="${ROOT}/shell/scripts/proteus-pin.py"
LOCK="${ROOT}/shell/surfaces/desktop/LockSurface.qml"
USERS="${ROOT}/apps/proteus-settings/panes/UsersPane.qml"

[[ -f "${AUTH}" ]] || die "missing proteus_auth.py"
[[ -x "${UNLOCK}" ]] || die "check-unlock.py not executable"
[[ -x "${PINCLI}" ]] || die "proteus-pin.py not executable"
[[ -f "${LOCK}" ]] || die "missing LockSurface.qml"
[[ -f "${USERS}" ]] || die "missing UsersPane.qml"

grep -q 'check-unlock.py' "${LOCK}" || die "LockSurface must use check-unlock.py"
grep -q 'pinAppend\|Enter PIN\|Use password' "${LOCK}" || die "LockSurface PIN UI"
grep -q 'proteus-pin.py' "${USERS}" || die "UsersPane cites proteus-pin.py"
grep -q 'Lock screen PIN' "${USERS}" || die "UsersPane PIN group"
grep -q 'settings.json' "${USERS}" || die "UsersPane honesty about settings.json"

[[ -f "${ROOT}/shell/pam/proteus-lock" ]] || die "missing shell/pam/proteus-lock"
[[ -x "${ROOT}/install/machine/install-lock-pam.sh" ]] || die "install-lock-pam.sh not executable"
grep -q 'proteus-pin.py' "${ROOT}/install/apps.sh" \
  || die "apps.sh must install proteus-pin.py"
grep -q 'check-unlock.py' "${ROOT}/install/apps.sh" \
  || die "apps.sh must install check-unlock.py"
grep -q 'install-lock-pam' "${ROOT}/install/apps.sh" \
  || die "apps.sh must cite install-lock-pam"
python3 -m py_compile "${AUTH}" || die "proteus_auth.py py_compile"
ok "install + PAM source wiring"

# Fail closed: PIN must not be claimed as a Config / settings.json key
if grep -qiE '^\|[^|]*\bpin\b|lockPin|unlockPin' \
  "${ROOT}/docs/proteus/CONFIG-SCHEMA.md" 2>/dev/null; then
  die "CONFIG-SCHEMA must not put unlock PIN in settings.json keys"
fi
ok "schema does not store PIN in settings.json"

TMPHOME="$(mktemp -d)"
trap 'rm -rf "${TMPHOME}"' EXIT
export HOME="${TMPHOME}"

st="$(python3 "${UNLOCK}" --status)"
echo "${st}" | grep -q '"configured":false' || die "status empty home configured:false"
ok "status unconfigured"

python3 -c "
import sys
sys.path.insert(0, '${ROOT}/shell/scripts')
import proteus_auth, os
proteus_auth.write_pin('2468')
assert proteus_auth.verify_pin('2468')
assert not proteus_auth.verify_pin('0000')
assert not proteus_auth.verify_pin('24680')
mode = os.stat(proteus_auth.pin_path()).st_mode & 0o777
assert mode == 0o600, oct(mode)
"

st="$(python3 "${UNLOCK}" --status)"
echo "${st}" | grep -q '"configured":true' || die "status configured after write"
echo "${st}" | grep -q '"length":4' || die "status length 4"

if printf '2468\n' | python3 "${UNLOCK}" smokeuser pin; then
  ok "check-unlock pin accept"
else
  die "check-unlock pin accept"
fi
if printf '0000\n' | python3 "${UNLOCK}" smokeuser pin; then
  die "check-unlock pin should reject wrong PIN"
else
  ok "check-unlock pin reject"
fi

cli_st="$(python3 "${PINCLI}" status)"
echo "${cli_st}" | grep -q '"configured":true' || die "proteus-pin status"

python3 -c "
import sys
sys.path.insert(0, '${ROOT}/shell/scripts')
import proteus_auth
proteus_auth.clear_pin()
assert not proteus_auth.pin_status()['configured']
"
ok "hash write/verify/clear"

if [[ "${fail}" -ne 0 ]]; then
  exit 1
fi
echo "lock-pin-smoke: OK"
