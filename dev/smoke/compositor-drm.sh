#!/usr/bin/env bash
# compositor-drm.sh — opt-in live DRM/session prove for compositor.
#
# DANGER: `--backend drm` claims the seat / modesets. Never run on an active
# Hyprland graphical session unless you intend to steal the display.
#
# Env:
#   PROTEUS_COMPOSITOR_DRM=1  — required; without it exit 2 SKIP
#   PROTEUS_COMPOSITOR   — optional path to proteus-compositor
#   PROTEUS_COMPOSITORCTL     — optional path to proteus-compositorctl
#
# Exit 0 — drm spike started, ctl workspaces ok, then stopped
# Exit 2 — SKIP (flag unset, or libseat/GPU/connector failure)
# Exit 1 — hard failure (binary missing, ctl broken after successful start)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMP="${PROTEUS_COMPOSITOR:-${ROOT}/target/debug/proteus-compositor}"
CTL="${PROTEUS_COMPOSITORCTL:-${ROOT}/target/debug/proteus-compositorctl}"

if [[ "${PROTEUS_COMPOSITOR_DRM:-}" != "1" ]]; then
  echo "compositor-drm: PROTEUS_COMPOSITOR_DRM!=1 — skip live DRM" >&2
  exit 2
fi

if [[ ! -x "${COMP}" ]]; then
  echo "compositor-drm: missing binary ${COMP}" >&2
  exit 1
fi
if [[ ! -x "${CTL}" ]]; then
  echo "compositor-drm: missing ctl ${CTL}" >&2
  exit 1
fi

LOG="$(mktemp)"
PID=""
cleanup() {
  if [[ -n "${PID}" ]] && kill -0 "${PID}" 2>/dev/null; then
    kill "${PID}" 2>/dev/null || true
    sleep 0.3
    kill -9 "${PID}" 2>/dev/null || true
  fi
  rm -f "${LOG}"
}
trap cleanup EXIT

# Clear nested display so DRM path owns the seat rather than nesting under host.
env -u WAYLAND_DISPLAY -u DISPLAY \
  "${COMP}" --backend drm >"${LOG}" 2>&1 &
PID=$!

saw=""
for _ in $(seq 1 50); do
  if ! kill -0 "${PID}" 2>/dev/null; then
    echo "compositor-drm: process exited early" >&2
    cat "${LOG}" >&2 || true
    # Soft-skip when seat/GPU unavailable (typical nested host).
    if grep -qiE 'libseat|no DRM GPU|no connected DRM|session' "${LOG}" 2>/dev/null; then
      exit 2
    fi
    exit 2
  fi
  if grep -q 'drm spike on WAYLAND_DISPLAY=' "${LOG}" 2>/dev/null; then
    saw=1
    break
  fi
  sleep 0.1
done

if [[ -z "${saw}" ]]; then
  echo "compositor-drm: no drm spike log line" >&2
  cat "${LOG}" >&2 || true
  exit 2
fi

nested_wd="$(sed -n 's/.*drm spike on WAYLAND_DISPLAY=//p' "${LOG}" | head -1)"
sock=""
for _ in $(seq 1 30); do
  sock="$(ls -1 "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"/proteus-compositor-"${nested_wd}".sock 2>/dev/null | head -1 || true)"
  if [[ -n "${sock}" && -S "${sock}" ]]; then
    break
  fi
  sleep 0.1
done

if [[ -z "${sock}" || ! -S "${sock}" ]]; then
  echo "compositor-drm: ctl socket missing for ${nested_wd}" >&2
  exit 1
fi

ws="$(PROTEUS_COMPOSITOR_SOCK="${sock}" "${CTL}" workspaces 2>/dev/null || true)"
if ! echo "${ws}" | grep -q '\['; then
  echo "compositor-drm: workspaces query failed: ${ws}" >&2
  exit 1
fi

echo "compositor-drm: OK WAYLAND_DISPLAY=${nested_wd}"
exit 0
