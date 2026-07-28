#!/usr/bin/env bash
# Host-side sanity check for the overlay tree (no guest, no pacman).
# Usage: ./vm/install/check.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALL="${ROOT}/vm/install"
fail=0

ok() { echo "  OK  $*"; }
bad() { echo "  FAIL $*"; fail=1; }

echo "==> proteus install tree check (${ROOT})"

[[ -x "${INSTALL}/bootstrap.sh" ]] || chmod +x "${INSTALL}/bootstrap.sh" 2>/dev/null || true
[[ -f "${INSTALL}/helpers.sh" ]] && ok helpers.sh || bad helpers.sh
[[ -f "${INSTALL}/proteus-base.packages" ]] && ok proteus-base.packages || bad proteus-base.packages
[[ -f "${INSTALL}/proteus-desktop.packages" ]] && ok proteus-desktop.packages || bad proteus-desktop.packages

for stage in preflight packaging config hardware login apps desktop post-install; do
  if [[ -f "${INSTALL}/${stage}.sh" ]]; then
    if bash -n "${INSTALL}/${stage}.sh" 2>/dev/null; then
      ok "stage ${stage}.sh"
    else
      bad "stage ${stage}.sh (bash -n)"
    fi
  else
    bad "missing ${stage}.sh"
  fi
done

for hw in virt nvidia amd intel; do
  [[ -f "${INSTALL}/hardware/${hw}.sh" ]] && ok "hardware/${hw}.sh" || bad "hardware/${hw}.sh"
done

base_n="$(grep -cEv '^\s*(#|$)' "${INSTALL}/proteus-base.packages" || true)"
desk_n="$(grep -cEv '^\s*(#|$)' "${INSTALL}/proteus-desktop.packages" || true)"
ok "base packages: ${base_n}"
ok "desktop packages: ${desk_n}"
[[ "${base_n}" -ge 5 ]] || bad "base package list looks too thin"

[[ -f "${ROOT}/env/hypr/hyprland.conf" ]] && ok env/hypr/hyprland.conf || bad env/hypr/hyprland.conf
[[ -d "${ROOT}/vm/guest" ]] && ok vm/guest/ || bad vm/guest/
[[ -x "${ROOT}/vm/bootstrap.sh" || -f "${ROOT}/vm/bootstrap.sh" ]] && ok vm/bootstrap.sh || bad vm/bootstrap.sh
[[ -f "${ROOT}/vm/provision.sh" ]] && ok vm/provision.sh || bad vm/provision.sh

# shellcheck source=helpers.sh
source "${INSTALL}/helpers.sh"
export PROTEUS_ROOT="${ROOT}"
PROTEUS_INSTALL_STATUS_DIR="${TMPDIR:-/tmp}/proteus-install-check-$$"
export PROTEUS_INSTALL_STATUS_DIR
mkdir -p "${PROTEUS_INSTALL_STATUS_DIR}"
proteus_status_ensure
proteus_stage_done_mark check-selftest
[[ -f "${PROTEUS_INSTALL_STATUS_DIR}/check-selftest.done" ]] && ok "status markers" || bad "status markers"
rm -rf "${PROTEUS_INSTALL_STATUS_DIR}"

echo
if [[ "${fail}" -eq 0 ]]; then
  echo "==> check OK"
  exit 0
fi
echo "==> check FAILED"
exit 1
