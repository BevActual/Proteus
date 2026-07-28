#!/usr/bin/env bash
# Proteus dogfood overlay installer (Omarchy-shaped, light packages).
#
# Run on the Arch guest after base install (guest-install.sh or manual Arch):
#   sudo bash /mnt/proteus/vm/install/bootstrap.sh
#
# Env:
#   PROTEUS_INSTALL_DESKTOP=0     skip desktop kit
#   PROTEUS_INSTALL_SKIP=a,b      skip named stages (e.g. hardware,desktop)
#   PROTEUS_INSTALL_RESUME=1      skip stages that already have a .done marker
#   PROTEUS_INSTALL_ONLY=stage    run a single stage then exit
#   PROTEUS_INSTALL_LOG=path      append log (default /var/log/proteus-install.log as root)
#
# Stages: preflight → packaging → config → hardware → login → apps → desktop → post-install
set -euo pipefail

INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
source "${INSTALL_DIR}/helpers.sh"

if [[ -z "${PROTEUS_ROOT:-}" ]]; then
  if [[ -d /mnt/proteus/vm/install ]]; then
    export PROTEUS_ROOT=/mnt/proteus
  else
    export PROTEUS_ROOT="$(cd "${INSTALL_DIR}/../.." && pwd)"
  fi
fi

export PROTEUS_INSTALL="${PROTEUS_ROOT}/vm/install"
export PATH="${PROTEUS_ROOT}/vm/guest:${PATH:-}"

if [[ -z "${PROTEUS_INSTALL_LOG:-}" ]]; then
  if [[ "${EUID}" -eq 0 ]]; then
    export PROTEUS_INSTALL_LOG=/var/log/proteus-install.log
  else
    export PROTEUS_INSTALL_LOG="${XDG_CACHE_HOME:-${HOME}/.cache}/proteus-install.log"
    mkdir -p "$(dirname "${PROTEUS_INSTALL_LOG}")"
  fi
fi
touch "${PROTEUS_INSTALL_LOG}" 2>/dev/null || true

STAGES=(preflight packaging config hardware login apps desktop post-install)
# Parallel arrays for summary (bash 4+)
declare -a STAGE_RESULTS=()
declare -a STAGE_SECS=()
BOOT_T0="$(date +%s)"

proteus_log "Proteus overlay bootstrap"
proteus_log "PROTEUS_ROOT=${PROTEUS_ROOT}"
proteus_log "log=${PROTEUS_INSTALL_LOG}"
[[ -n "${PROTEUS_INSTALL_SKIP:-}" ]] && proteus_log "SKIP=${PROTEUS_INSTALL_SKIP}"
[[ "${PROTEUS_INSTALL_RESUME:-0}" == "1" ]] && proteus_log "RESUME=1 (honoring .done markers)"
[[ -n "${PROTEUS_INSTALL_ONLY:-}" ]] && proteus_log "ONLY=${PROTEUS_INSTALL_ONLY}"

run_stage() {
  local stage="$1"
  local t0 t1 elapsed result

  if [[ -n "${PROTEUS_INSTALL_ONLY:-}" && "${PROTEUS_INSTALL_ONLY}" != "${stage}" ]]; then
    STAGE_RESULTS+=("omit")
    STAGE_SECS+=("0")
    return 0
  fi
  if proteus_stage_skipped "${stage}"; then
    proteus_log "── ${stage} ── SKIP (PROTEUS_INSTALL_SKIP)"
    STAGE_RESULTS+=("skip")
    STAGE_SECS+=("0")
    return 0
  fi
  if proteus_stage_already_done "${stage}"; then
    proteus_log "── ${stage} ── SKIP (already done; unset PROTEUS_INSTALL_RESUME to redo)"
    STAGE_RESULTS+=("done")
    STAGE_SECS+=("0")
    return 0
  fi

  proteus_log "── ${stage} ──"
  t0="$(date +%s)"
  # shellcheck disable=SC1090
  if ! bash "${PROTEUS_INSTALL}/${stage}.sh"; then
    proteus_log "FAIL stage=${stage} (see ${PROTEUS_INSTALL_LOG})"
    STAGE_RESULTS+=("FAIL")
    STAGE_SECS+=("$(( $(date +%s) - t0 ))")
    return 1
  fi
  t1="$(date +%s)"
  elapsed=$((t1 - t0))
  proteus_stage_done_mark "${stage}" || true
  proteus_log "── ${stage} ── OK (${elapsed}s)"
  STAGE_RESULTS+=("ok")
  STAGE_SECS+=("${elapsed}")
}

for stage in "${STAGES[@]}"; do
  run_stage "${stage}"
done

BOOT_ELAPSED=$(( $(date +%s) - BOOT_T0 ))
proteus_log "bootstrap OK (${BOOT_ELAPSED}s)"
proteus_log "status=$(proteus_status_dir)"

echo
echo "Stage summary (${BOOT_ELAPSED}s total):"
printf '  %-14s  %-6s  %s\n' "STAGE" "RESULT" "SEC"
i=0
for stage in "${STAGES[@]}"; do
  printf '  %-14s  %-6s  %ss\n' "${stage}" "${STAGE_RESULTS[$i]}" "${STAGE_SECS[$i]}"
  i=$((i + 1))
done
echo
echo "Install log: ${PROTEUS_INSTALL_LOG}"
echo "Status dir:  $(proteus_status_dir)"
