#!/usr/bin/env bash
# dogfood-host — guest host flip + headless/seat verify (+ restore desktop).
# Usage (guest):
#   bash /mnt/proteus/scripts/dogfood/dogfood-host.sh
#   bash /mnt/proteus/scripts/dogfood/dogfood-host.sh --attach   # after headless, attach seat
#   bash /mnt/proteus/scripts/dogfood/dogfood-host.sh --restore  # flip back to desktop
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
if [[ -n "${PROTEUS_ROOT:-}" && -d "${PROTEUS_ROOT}/shell" ]]; then
  ROOT="${PROTEUS_ROOT}"
elif [[ -d "${HERE}/../../shell" ]]; then
  ROOT="$(cd "${HERE}/../.." && pwd)"
elif [[ -d /mnt/proteus/shell ]]; then
  ROOT=/mnt/proteus
else
  ROOT="${PROTEUS_ROOT:-/mnt/proteus}"
fi
export PROTEUS_ROOT="${ROOT}"

ATTACH=0
RESTORE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --attach) ATTACH=1; shift ;;
    --restore) RESTORE=1; shift ;;
    -h|--help)
      sed -n '2,8p' "$0" | sed 's/^# //;s/^#//'
      exit 0
      ;;
    *)
      echo "dogfood-host: unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

die() { echo "dogfood-host: FAIL $*" >&2; exit 1; }
log() { echo "dogfood-host: $*"; }

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
if [[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" && -d "${XDG_RUNTIME_DIR}/hypr" ]]; then
  HYPRLAND_INSTANCE_SIGNATURE="$(ls "${XDG_RUNTIME_DIR}/hypr" 2>/dev/null | head -1 || true)"
  export HYPRLAND_INSTANCE_SIGNATURE
fi
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
export PATH="/usr/local/bin:${ROOT}/shell/scripts:${ROOT}/install/machine:${PATH}"
export PROTEUS_SKIP_SESSION_LOCK=1

POSTURE_BIN=""
for c in proteus-posture "${ROOT}/shell/scripts/proteus-posture" /usr/local/bin/proteus-posture; do
  if [[ -x "${c}" ]]; then POSTURE_BIN="${c}"; break; fi
done
[[ -n "${POSTURE_BIN}" ]] || die "proteus-posture not found"

SEAT_BIN=""
for c in proteus-host-seat "${ROOT}/shell/scripts/proteus-host-seat" /usr/local/bin/proteus-host-seat; do
  if [[ -x "${c}" ]]; then SEAT_BIN="${c}"; break; fi
done
[[ -n "${SEAT_BIN}" ]] || die "proteus-host-seat not found"

SHELL_DIR="${ROOT}/shell"
QS_IPC=(qs -p "${SHELL_DIR}")
command -v qs >/dev/null 2>&1 || QS_IPC=(quickshell -p "${SHELL_DIR}")

chrome_state() {
  "${QS_IPC[@]}" ipc call chrome state 2>/dev/null || true
}

wait_surface() {
  local want="$1"
  local i surface
  for i in $(seq 1 40); do
    surface="$(chrome_state | python3 -c 'import json,sys
try:
  d=json.load(sys.stdin)
  print(d.get("surface") or "")
except Exception:
  print("")
' 2>/dev/null || true)"
    if [[ "${surface}" == "${want}" ]]; then
      echo "${surface}"
      return 0
    fi
    sleep 0.35
  done
  echo "${surface:-}"
  return 1
}

wait_qs_absent() {
  local i
  for i in $(seq 1 30); do
    if ! pgrep -f "quickshell -p ${SHELL_DIR}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.25
  done
  return 1
}

fact_posture() {
  tr -d '[:space:]' <"${HOME}/.config/proteus/posture" 2>/dev/null || true
}

fact_chrome() {
  local f="${HOME}/.config/proteus/host-chrome"
  if [[ -f "${f}" ]]; then
    tr -d '[:space:]' <"${f}"
  else
    echo full
  fi
}

if [[ "${RESTORE}" -eq 1 ]]; then
  log "restoring desktop"
  "${POSTURE_BIN}" desktop
  got="$(fact_posture)"
  [[ "${got}" == "desktop" ]] || die "posture Fact=${got} want=desktop"
  if ! wait_surface desktop >/dev/null; then
    die "chrome surface not desktop after restore"
  fi
  log "done (desktop)"
  exit 0
fi

if [[ "${ATTACH}" -eq 1 ]]; then
  log "attaching host seat"
  "${SEAT_BIN}" attach
  [[ "$(fact_posture)" == "host" ]] || die "posture must stay host"
  [[ "$(fact_chrome)" == "full" ]] || die "host-chrome want=full got=$(fact_chrome)"
  if ! wait_surface host >/dev/null; then
    die "chrome surface not host after attach"
  fi
  log "OK seat attached chrome.surface=host"
  log "done (host chrome) — restore: $0 --restore"
  exit 0
fi

log "entering host (default headless)"
"${POSTURE_BIN}" host
[[ "$(fact_posture)" == "host" ]] || die "posture Fact want=host"
[[ "$(fact_chrome)" == "none" ]] || die "host-chrome want=none (default headless) got=$(fact_chrome)"
if ! wait_qs_absent; then
  die "Quickshell still running after host headless"
fi
log "OK Fact=host host-chrome=none QS absent"

log "attaching ops seat"
"${SEAT_BIN}" attach
[[ "$(fact_chrome)" == "full" ]] || die "host-chrome want=full after attach"
if ! wait_surface host >/dev/null; then
  die "chrome surface not host after attach"
fi
log "OK chrome.surface=host"

log "detaching seat"
"${SEAT_BIN}" detach
[[ "$(fact_posture)" == "host" ]] || die "posture must stay host after detach"
[[ "$(fact_chrome)" == "none" ]] || die "host-chrome want=none after detach"
if ! wait_qs_absent; then
  die "Quickshell still running after detach"
fi
log "OK headless again"

log "done (host) — restore: $0 --restore"
exit 0
