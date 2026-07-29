#!/usr/bin/env bash
# qs-guest-smoke — guest Quickshell cold start (SHELL_OK / SETTINGS_OK)
# Skip if SSH unreachable unless PROTEUS_GUEST=1 (then fail closed).
set -euo pipefail

HOST="${PROTEUS_GUEST_HOST:-127.0.0.1}"
PORT="${PROTEUS_GUEST_PORT:-2222}"
USER="${PROTEUS_GUEST_USER:-andrew}"
REQUIRE="${PROTEUS_GUEST:-0}"

ssh_opts=(
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o BatchMode=yes
  -o ConnectTimeout=3
  -p "${PORT}"
)

if ! ssh "${ssh_opts[@]}" "${USER}@${HOST}" 'echo SSH_OK' >/dev/null 2>&1; then
  if [[ "${REQUIRE}" == "1" ]]; then
    echo "qs-guest-smoke: FAIL SSH ${USER}@${HOST}:${PORT} unreachable (PROTEUS_GUEST=1)" >&2
    exit 1
  fi
  echo "qs-guest-smoke: SKIP guest SSH unreachable (set PROTEUS_GUEST=1 to require)"
  exit 0
fi

echo "qs-guest-smoke: guest SSH OK — cold-start shell + Settings"

# Record Quickshell version (pin policy: record + smoke, not pacman IgnorePkg)
qs_ver="$(ssh "${ssh_opts[@]}" "${USER}@${HOST}" 'quickshell --version 2>/dev/null || quickshell -v 2>/dev/null || echo unknown' | head -1 || true)"
echo "qs-guest-smoke: quickshell version: ${qs_ver:-unknown}"

out="$(ssh "${ssh_opts[@]}" "${USER}@${HOST}" 'bash -s' <<'EOF'
set -uo pipefail
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
if [[ -d "${XDG_RUNTIME_DIR}/hypr" ]]; then
  export HYPRLAND_INSTANCE_SIGNATURE="$(ls "${XDG_RUNTIME_DIR}/hypr" | head -1)"
fi
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
# This restarts the session shell, and a cold start re-arms the auto-lock.
# Without this the suite leaves the guest at a password prompt every run,
# which makes it unusable unattended. Only the automatic lock is suppressed.
export PROTEUS_SKIP_SESSION_LOCK=1

echo "QS_VERSION=$(quickshell --version 2>/dev/null || quickshell -v 2>/dev/null || echo unknown)"

pkill -f "proteus-qs /mnt/proteus/shell" 2>/dev/null || true
pkill -f "quickshell -p /mnt/proteus/shell$" 2>/dev/null || true
pkill -f "quickshell -p /mnt/proteus/apps/proteus-settings" 2>/dev/null || true
sleep 0.5
: > /tmp/proteus-shell.log
: > /tmp/proteus-settings.log
# Smoke uses direct quickshell (not the respawn loop) so the suite can wait on PIDs.
nohup quickshell -p /mnt/proteus/shell >/tmp/proteus-shell.log 2>&1 &
SP=$!
sleep 3.2
nohup quickshell -p /mnt/proteus/apps/proteus-settings >/tmp/proteus-settings.log 2>&1 &
TP=$!
sleep 2.2

if kill -0 "$SP" 2>/dev/null; then echo SHELL_OK; else echo SHELL_DEAD; fi
if kill -0 "$TP" 2>/dev/null; then echo SETTINGS_OK; else echo SETTINGS_DEAD; fi

# Fatal patterns from prior load-order / alias bugs
if rg -q 'Invalid alias reference|TypeError|Unable to find id' /tmp/proteus-shell.log /tmp/proteus-settings.log 2>/dev/null; then
  echo LOG_ERRORS
  echo "=== shell ==="
  tail -40 /tmp/proteus-shell.log || true
  echo "=== settings ==="
  tail -40 /tmp/proteus-settings.log || true
else
  echo LOG_CLEAN
fi
EOF
)"

echo "${out}"

echo "${out}" | grep -q SHELL_OK || { echo "qs-guest-smoke: FAIL shell did not stay up" >&2; exit 1; }
echo "${out}" | grep -q SETTINGS_OK || { echo "qs-guest-smoke: FAIL Settings did not stay up" >&2; exit 1; }
if echo "${out}" | grep -q LOG_ERRORS; then
  echo "qs-guest-smoke: FAIL TypeError / Invalid alias in logs" >&2
  exit 1
fi

echo "qs-guest-smoke: OK"
