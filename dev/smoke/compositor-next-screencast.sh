#!/usr/bin/env bash
# compositor-next-screencast.sh — short wf-recorder capture under nested spike.
#
# Env: WAYLAND_DISPLAY (required)
# Exit 0 — non-empty recording; exit 2 — SKIP (wf-recorder missing);
# Exit 1 — recorder ran but produced empty/missing file.
set -euo pipefail

if [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
  echo "compositor-next-screencast: WAYLAND_DISPLAY unset" >&2
  exit 1
fi

if ! command -v wf-recorder >/dev/null 2>&1; then
  echo "compositor-next-screencast: wf-recorder not found" >&2
  exit 2
fi

OUT="$(mktemp --suffix=.mp4)"
LOG="$(mktemp)"
REC_PID=""
cleanup() {
  if [[ -n "${REC_PID}" ]] && kill -0 "${REC_PID}" 2>/dev/null; then
    # SIGINT lets wf-recorder finalize the container when possible.
    kill -INT "${REC_PID}" 2>/dev/null || true
    sleep 0.4
    kill -9 "${REC_PID}" 2>/dev/null || true
    wait "${REC_PID}" 2>/dev/null || true
  fi
  rm -f "${LOG}"
}
trap cleanup EXIT

# Geometry region; -f output file. Runs until we interrupt.
env WAYLAND_DISPLAY="${WAYLAND_DISPLAY}" XDG_CURRENT_DESKTOP=wlroots \
  wf-recorder -g "0,0 64x64" -f "${OUT}" >"${LOG}" 2>&1 &
REC_PID=$!
sleep 2
if ! kill -0 "${REC_PID}" 2>/dev/null; then
  echo "compositor-next-screencast: wf-recorder exited early" >&2
  cat "${LOG}" >&2 || true
  rm -f "${OUT}"
  exit 1
fi
kill -INT "${REC_PID}" 2>/dev/null || true
sleep 0.6
if kill -0 "${REC_PID}" 2>/dev/null; then
  kill -9 "${REC_PID}" 2>/dev/null || true
fi
wait "${REC_PID}" 2>/dev/null || true
REC_PID=""

if [[ ! -s "${OUT}" ]]; then
  echo "compositor-next-screencast: empty recording" >&2
  cat "${LOG}" >&2 || true
  rm -f "${OUT}"
  exit 1
fi

echo "compositor-next-screencast: OK ($(wc -c < "${OUT}")B)"
rm -f "${OUT}"
exit 0
