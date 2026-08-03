#!/usr/bin/env bash
# qs-version-smoke — record Quickshell version (host or note); no IgnorePkg pin
#
# Upgrade path (honest):
#   1. On guest: pacman -Syu quickshell   # or full -Syu
#   2. PROTEUS_GUEST=1 ./dev/smoke-all.sh   # or ./dev/smoke/qs-guest-smoke.sh
#   3. Confirm "quickshell version:" line + SHELL_OK / SETTINGS_OK
# Do NOT add quickshell to pacman IgnorePkg on rolling Arch (COMPOSITOR Out).
# ISO pin is Later.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

echo "qs-version-smoke: pin policy = record + smoke (not IgnorePkg); ISO pin Later"

if command -v quickshell >/dev/null 2>&1; then
  ver="$(quickshell --version 2>/dev/null || quickshell -v 2>/dev/null || echo unknown)"
  echo "qs-version-smoke: host quickshell: ${ver}"
else
  echo "qs-version-smoke: host quickshell not on PATH (OK — guest records via qs-guest-smoke)"
fi

# Contract: guest smoke must keep recording version
GUEST_SMOKE="${ROOT}/dev/smoke/qs-guest-smoke.sh"
[[ -f "${GUEST_SMOKE}" ]] || { echo "qs-version-smoke: FAIL missing qs-guest-smoke.sh" >&2; exit 1; }
grep -qE 'quickshell --version|quickshell -v' "${GUEST_SMOKE}" \
  || { echo "qs-version-smoke: FAIL qs-guest-smoke must record quickshell version" >&2; exit 1; }
grep -q 'not pacman IgnorePkg' "${GUEST_SMOKE}" \
  || { echo "qs-version-smoke: FAIL qs-guest-smoke must document record-not-IgnorePkg policy" >&2; exit 1; }
if grep -qiE 'IgnorePkg[[:space:]]*=' "${GUEST_SMOKE}"; then
  echo "qs-version-smoke: FAIL qs-guest-smoke must not IgnorePkg-pin" >&2
  exit 1
fi

echo "qs-version-smoke: OK (upgrade → qs-guest-smoke / smoke-all)"
