#!/usr/bin/env bash
# smoke-all — host smoke suite; guest QS load when SSH up or PROTEUS_GUEST=1
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
run widget-layout-resolve-smoke.sh
run ipc-contract-smoke.sh
run config-schema-smoke.sh
run config-roundtrip-smoke.sh
run app-manifest-smoke.sh
run chrome-tokens-smoke.sh
run software-reliability-smoke.sh
run power-logind-smoke.sh
run power-threshold-smoke.sh
run accounts-smoke.sh
run users-smoke.sh
run lock-pin-smoke.sh
run permissions-smoke.sh
run desktop-smoke.sh
run spaces-smoke.sh
run focus-smoke.sh
run control-center-smoke.sh
run beacon-smoke.sh
run audio-mix-serve-smoke.sh
run hw-probe-smoke.sh
run install-smoke.sh
run session-smoke.sh
run posture-hard-smoke.sh
run console-smoke.sh
run host-smoke.sh
run workloads-app-smoke.sh
run host-metrics-smoke.sh
run peripherals-smoke.sh
run network-vpn-smoke.sh
run headscale-admin-smoke.sh
run qs-version-smoke.sh

# Guest: always attempt (skips if SSH down unless PROTEUS_GUEST=1)
run qs-guest-smoke.sh
run software-guest-smoke.sh
run console-guest-smoke.sh
run host-guest-smoke.sh

echo "smoke-all: OK"
