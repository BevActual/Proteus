#!/usr/bin/env bash
# smoke-all — desktop spine only until desktop is rock solid.
#
# Console / host / Software-guest / QML-era leaf stubs are deferred: run those
# scripts directly when that posture work resumes. Guest desktop dogfood stays
# (owned-guest; skips unless SSH :2222 or PROTEUS_GUEST=1).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

run() {
  echo "── $1 ──"
  "${ROOT}/dev/smoke/$1"
}

run shellcheck-smoke.sh
run doc-links-smoke.sh
run layout-smoke.sh
run ipc-contract-smoke.sh
run config-schema-smoke.sh
run chrome-tokens-smoke.sh
run shell-core-smoke.sh
run shell-smoke.sh
run compositor-smoke.sh
run shell-owned-dogfood-smoke.sh
run settings-next-smoke.sh
run settings-backing-smoke.sh
run install-smoke.sh
run install-idempotency-smoke.sh
run session-smoke.sh

# Guest desktop dogfood (skips if SSH down unless PROTEUS_GUEST=1)
run owned-guest-smoke.sh

echo "smoke-all: OK (desktop spine)"
echo "smoke-all: deferred — console/host/software guest + QML-era leaf stubs (run individually)"
