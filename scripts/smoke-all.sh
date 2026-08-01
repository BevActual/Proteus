#!/usr/bin/env bash
# smoke-all — host smoke suite; guest QS load when SSH up or PROTEUS_GUEST=1
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

run() {
  echo "── $1 ──"
  "${ROOT}/scripts/smoke/$1"
}

run layout-smoke.sh
run widget-layout-resolve-smoke.sh
run ipc-contract-smoke.sh
run config-schema-smoke.sh
run config-roundtrip-smoke.sh
run app-manifest-smoke.sh
run chrome-tokens-smoke.sh
run software-reliability-smoke.sh
run power-logind-smoke.sh
run accounts-smoke.sh
run audio-mix-serve-smoke.sh
run hw-probe-smoke.sh
run install-smoke.sh
run session-smoke.sh
run qs-version-smoke.sh

# Guest: always attempt (skips if SSH down unless PROTEUS_GUEST=1)
run qs-guest-smoke.sh
run software-guest-smoke.sh

echo "smoke-all: OK"
