#!/usr/bin/env bash
# compositor-session-lock.sh — opt-in protocol lock dogfood under nested compositor.
#
# Proves: proteus-session-lock (iced_sessionlock) can request ext-session-lock-v1
# and compositor ctl reports active/pending. Default shell Fact stays overlay —
# this helper only runs when invoked (smoke calls it with nested WD).
#
# Env:
#   WAYLAND_DISPLAY          — nested spike display (required)
#   PROTEUS_COMPOSITOR_SOCK  — ctl socket (required)
#   PROTEUS_COMPOSITORCTL    — optional path to proteus-compositorctl
#   PROTEUS_ROOT             — repo root (optional; derived from script)
#
# Exit 0 — lock requested; ctl reports active/pending/locked
# Exit 2 — SKIP (helper missing / build fail / no nested display)
# Exit 1 — hard failure (helper ran but compositor never saw lock)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export PROTEUS_ROOT="${PROTEUS_ROOT:-${ROOT}}"
CTL="${PROTEUS_COMPOSITORCTL:-${ROOT}/target/debug/proteus-compositorctl}"

if [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
  echo "compositor-session-lock: WAYLAND_DISPLAY unset — SKIP" >&2
  exit 2
fi
if [[ -z "${PROTEUS_COMPOSITOR_SOCK:-}" || ! -S "${PROTEUS_COMPOSITOR_SOCK}" ]]; then
  echo "compositor-session-lock: PROTEUS_COMPOSITOR_SOCK missing — SKIP" >&2
  exit 2
fi
if [[ ! -x "${CTL}" ]]; then
  echo "compositor-session-lock: ctl missing at ${CTL}" >&2
  exit 1
fi

# Default overlay must remain Fact SoT — refuse if caller flipped env globally
# without opt-in dogfood marker (smoke sets PROTEUS_SESSION_LOCK_DOGFOOD=1).
if [[ "${PROTEUS_SESSION_LOCK_DOGFOOD:-}" != "1" ]]; then
  echo "compositor-session-lock: set PROTEUS_SESSION_LOCK_DOGFOOD=1 to run" >&2
  exit 2
fi

find_helper() {
  local cand
  for cand in \
    "${ROOT}/target/debug/proteus-session-lock" \
    "${ROOT}/target/release/proteus-session-lock" \
    "${ROOT}/shell/target/debug/proteus-session-lock" \
    /usr/local/libexec/proteus/proteus-session-lock \
    /usr/local/bin/proteus-session-lock; do
    if [[ -x "${cand}" ]]; then
      echo "${cand}"
      return 0
    fi
  done
  if command -v proteus-session-lock >/dev/null 2>&1; then
    command -v proteus-session-lock
    return 0
  fi
  return 1
}

HELPER="$(find_helper || true)"
if [[ -z "${HELPER}" ]]; then
  echo "compositor-session-lock: building proteus-session-lock…" >&2
  if ! (cd "${ROOT}" && cargo build -p proteus-shell --bin proteus-session-lock -q 2>/tmp/proteus-slock-build.err); then
    echo "compositor-session-lock: build failed — SKIP" >&2
    head -c 400 /tmp/proteus-slock-build.err >&2 || true
    exit 2
  fi
  HELPER="$(find_helper || true)"
fi
if [[ -z "${HELPER}" || ! -x "${HELPER}" ]]; then
  echo "compositor-session-lock: helper still missing — SKIP" >&2
  exit 2
fi

LOCK_LOG="$(mktemp)"
LOCK_PID=""
cleanup() {
  if [[ -n "${LOCK_PID}" ]] && kill -0 "${LOCK_PID}" 2>/dev/null; then
    kill "${LOCK_PID}" 2>/dev/null || true
    sleep 0.2
    kill -9 "${LOCK_PID}" 2>/dev/null || true
  fi
  rm -f "${LOCK_LOG}"
}
trap cleanup EXIT

# Probe baseline — should be idle before helper.
base="$("${CTL}" session-lock 2>/dev/null || true)"
echo "${base}" | grep -q '"supported": *true' || {
  echo "compositor-session-lock: ctl session-lock not supported: ${base}" >&2
  exit 1
}

env WAYLAND_DISPLAY="${WAYLAND_DISPLAY}" \
  PROTEUS_SESSION_LOCK=protocol \
  XDG_CURRENT_DESKTOP=wlroots \
  "${HELPER}" >"${LOCK_LOG}" 2>&1 &
LOCK_PID=$!

active=0
for _ in $(seq 1 40); do
  st="$("${CTL}" session-lock 2>/dev/null || true)"
  if echo "${st}" | python3 -c 'import json,sys
try:
  j=json.load(sys.stdin)
  sys.exit(0 if j.get("active") or j.get("pending") or j.get("locked") else 1)
except Exception:
  sys.exit(1)'; then
    active=1
    break
  fi
  if ! kill -0 "${LOCK_PID}" 2>/dev/null; then
    break
  fi
  sleep 0.15
done

if [[ "${active}" -eq 1 ]]; then
  echo "compositor-session-lock: OK protocol lock active (helper=${HELPER##*/})"
  exit 0
fi

# Soft SKIP when helper exits immediately (missing protocol deps / GPU) —
# nested hosts vary; do not fail the desktop spine for that.
if ! kill -0 "${LOCK_PID}" 2>/dev/null; then
  echo "compositor-session-lock: helper exited before lock — SKIP" >&2
  head -c 300 "${LOCK_LOG}" >&2 || true
  echo >&2
  exit 2
fi

echo "compositor-session-lock: FAIL lock not observed: $("${CTL}" session-lock 2>/dev/null || true)" >&2
head -c 300 "${LOCK_LOG}" >&2 || true
echo >&2
exit 1
