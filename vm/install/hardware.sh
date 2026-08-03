#!/usr/bin/env bash
# hardware — detect-and-install GPU bits (no-op when hardware absent)
# Keeps proteus-base.packages thin; Omarchy-shaped optional overlays.
set -euo pipefail
# shellcheck source=helpers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

PROTEUS_ROOT="$(proteus_install_root)"
HW="${PROTEUS_ROOT}/vm/install/hardware"

run_hw() {
  local name="$1"
  proteus_log "hardware/${name}"
  bash "${HW}/${name}.sh"
}

run_hw virt
run_hw cpu
run_hw nvidia
run_hw amd
run_hw intel

proteus_log "hardware OK"
