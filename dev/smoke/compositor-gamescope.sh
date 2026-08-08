#!/usr/bin/env bash
# compositor-gamescope.sh — nest gamescope under compositor.
#
# Env:
#   WAYLAND_DISPLAY          — nested spike display (required)
#   PROTEUS_COMPOSITOR_SOCK  — ctl socket (required for clients poll)
#   PROTEUS_COMPOSITORCTL    — optional path to proteus-compositorctl
#
# Exit 0 — gamescope stayed up and appeared in clients
# Exit 2 — SKIP (gamescope missing or no usable backend)
# Exit 1 — gamescope up but not in clients / hard failure
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CTL="${PROTEUS_COMPOSITORCTL:-${ROOT}/target/debug/proteus-compositorctl}"

if [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
  echo "compositor-gamescope: WAYLAND_DISPLAY unset" >&2
  exit 1
fi
if [[ -z "${PROTEUS_COMPOSITOR_SOCK:-}" || ! -S "${PROTEUS_COMPOSITOR_SOCK}" ]]; then
  echo "compositor-gamescope: PROTEUS_COMPOSITOR_SOCK missing/not a socket" >&2
  exit 1
fi

GS_BIN="$(command -v gamescope || true)"
if [[ -z "${GS_BIN}" ]]; then
  echo "compositor-gamescope: gamescope not found" >&2
  exit 2
fi
if [[ ! -x "${CTL}" ]]; then
  echo "compositor-gamescope: proteus-compositorctl missing at ${CTL}" >&2
  exit 1
fi

GS_LOG="$(mktemp)"
GS_PID=""
cleanup() {
  if [[ -n "${GS_PID}" ]] && kill -0 "${GS_PID}" 2>/dev/null; then
    kill "${GS_PID}" 2>/dev/null || true
    sleep 0.3
    kill -9 "${GS_PID}" 2>/dev/null || true
  fi
  rm -f "${GS_LOG}"
}
trap cleanup EXIT

baseline="$("${CTL}" clients 2>/dev/null || echo '[]')"
baseline_n="$(python3 -c "import json,sys; print(len(json.loads(sys.argv[1])))" "${baseline}" 2>/dev/null || echo 0)"

start_gs() {
  local backend="${1:-}"
  local args=(-W 1280 -H 720)
  if [[ -n "${backend}" ]]; then
    args+=(--backend "${backend}")
  fi
  # Short-lived child keeps gamescope mapped long enough to poll clients.
  env WAYLAND_DISPLAY="${WAYLAND_DISPLAY}" XDG_CURRENT_DESKTOP=wlroots \
    "${GS_BIN}" "${args[@]}" -- sleep 12 >"${GS_LOG}" 2>&1 &
  GS_PID=$!
}

alive() {
  [[ -n "${GS_PID}" ]] && kill -0 "${GS_PID}" 2>/dev/null
}

start_gs ""
sleep 2
if ! alive; then
  echo "compositor-gamescope: default backend exited — retrying --backend sdl" >&2
  GS_PID=""
  start_gs "sdl"
  sleep 2
fi
if ! alive; then
  echo "compositor-gamescope: no usable backend (see log)" >&2
  cat "${GS_LOG}" >&2 || true
  exit 2
fi

saw=""
for _ in $(seq 1 40); do
  if ! alive; then
    echo "compositor-gamescope: gamescope died during poll" >&2
    cat "${GS_LOG}" >&2 || true
    exit 1
  fi
  after="$("${CTL}" clients 2>/dev/null || echo '[]')"
  after_n="$(python3 -c "import json,sys; print(len(json.loads(sys.argv[1])))" "${after}" 2>/dev/null || echo 0)"
  if echo "${after}" | grep -qi 'gamescope'; then
    saw=1
    break
  fi
  if [[ "${after_n}" -gt "${baseline_n}" ]]; then
    saw=1
    break
  fi
  sleep 0.15
done

if [[ -z "${saw}" ]]; then
  echo "compositor-gamescope: gamescope up but not in clients" >&2
  echo "baseline=${baseline_n} clients=${after:-}" >&2
  cat "${GS_LOG}" >&2 || true
  exit 1
fi

echo "compositor-gamescope: OK (clients grew or matched gamescope)"
exit 0
