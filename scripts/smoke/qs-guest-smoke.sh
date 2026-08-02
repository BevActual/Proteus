#!/usr/bin/env bash
# qs-guest-smoke — guest Quickshell cold start (SHELL_OK / SETTINGS_OK)
# Skip if SSH unreachable unless PROTEUS_GUEST=1 (then fail closed).
#
# Version / upgrade path (#1174):
#   After upgrading Quickshell on the guest (`pacman -Syu`), re-run this script
#   (or PROTEUS_GUEST=1 ./scripts/smoke-all.sh). It prints
#   "qs-guest-smoke: quickshell version: …" then asserts SHELL_OK / SETTINGS_OK.
#   Pin policy: record + smoke — not pacman IgnorePkg (COMPOSITOR Out). ISO pin Later.
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

# Polkit auth agent — pkexec (proteus-pkg / proteus-logind) needs a GUI prompt.
# Without it Install/Power apply dies with "/dev/tty: No such device or address".
if pgrep -x hyprpolkitagent >/dev/null 2>&1; then
  echo POLKIT_AGENT_OK
else
  echo POLKIT_AGENT_MISSING
fi

# Install… deep link — drive nav via the Settings IPC probe (shell.qml "nav"):
# seed a Software search, then assert the page landed on the target leaf.
if kill -0 "$TP" 2>/dev/null; then
  qs -p /mnt/proteus/apps/proteus-settings ipc call nav installSearch qpwgraph packages-search >/dev/null 2>&1
  sleep 1.2
  nav_state="$(qs -p /mnt/proteus/apps/proteus-settings ipc call nav state 2>/dev/null || echo '')"
  echo "NAV_STATE=${nav_state}"
  if [[ "${nav_state}" == *'"page":"packages-search"'* ]]; then
    echo NAV_OK
  else
    echo NAV_FAIL
  fi
  # Desktop catch-up — Control Center Edit tiles › leaf
  qs -p /mnt/proteus/apps/proteus-settings ipc call nav go desktop-control-center >/dev/null 2>&1
  sleep 1.0
  desk_nav="$(qs -p /mnt/proteus/apps/proteus-settings ipc call nav state 2>/dev/null || echo '')"
  echo "DESKTOP_NAV_STATE=${desk_nav}"
  if [[ "${desk_nav}" == *'"page":"desktop-control-center"'* ]]; then
    echo DESKTOP_NAV_OK
  else
    echo DESKTOP_NAV_FAIL
  fi
  # Spaces leaf (multi-display workspaceMode)
  qs -p /mnt/proteus/apps/proteus-settings ipc call nav go desktop-spaces >/dev/null 2>&1
  sleep 1.0
  spaces_nav="$(qs -p /mnt/proteus/apps/proteus-settings ipc call nav state 2>/dev/null || echo '')"
  echo "DESKTOP_SPACES_NAV_STATE=${spaces_nav}"
  if [[ "${spaces_nav}" == *'"page":"desktop-spaces"'* ]]; then
    echo DESKTOP_SPACES_NAV_OK
  else
    echo DESKTOP_SPACES_NAV_FAIL
  fi
fi

# Beacon universal search — unlock first (fresh installs lock on session
# start), seed "reboot", assert the Apps surface answers with an action row.
if kill -0 "$SP" 2>/dev/null; then
  qs -p /mnt/proteus/shell ipc call lock unlock >/dev/null 2>&1
  qs -p /mnt/proteus/shell ipc call chrome beacon reboot >/dev/null 2>&1
  sleep 1.0
  beacon_state="$(qs -p /mnt/proteus/shell ipc call chrome beaconState 2>/dev/null || echo '')"
  echo "BEACON_STATE=${beacon_state}"
  if [[ "${beacon_state}" == *'"action"'* ]]; then
    echo BEACON_OK
  else
    echo BEACON_FAIL
  fi
  qs -p /mnt/proteus/shell ipc call chrome beacon focus >/dev/null 2>&1
  sleep 0.5
  focus_state="$(qs -p /mnt/proteus/shell ipc call chrome beaconState 2>/dev/null || echo '')"
  echo "FOCUS_STATE=${focus_state}"
  if [[ "${focus_state}" == *'focus'* ]] || [[ "${focus_state}" == *'"action"'* ]]; then
    echo FOCUS_OK
  else
    echo FOCUS_FAIL
  fi
  qs -p /mnt/proteus/shell ipc call chrome focusCycle >/dev/null 2>&1 || true
fi

# Calendar popover — toggle open via IPC, assert chrome state reflects it,
# then toggle it back closed.
if kill -0 "$SP" 2>/dev/null; then
  qs -p /mnt/proteus/shell ipc call chrome calendar >/dev/null 2>&1
  sleep 0.5
  cal_state="$(qs -p /mnt/proteus/shell ipc call chrome state 2>/dev/null || echo '')"
  qs -p /mnt/proteus/shell ipc call chrome calendar >/dev/null 2>&1
  if [[ "${cal_state}" == *'"calendar":true'* ]]; then
    echo CALENDAR_OK
  else
    echo "CALENDAR_FAIL state=${cal_state}"
  fi
fi

# Customize + widgets probe — add/move/snap/remove without gallery UI.
# Prefer worldclock (multi-instance) so we always create a fresh id and can
# remove it without touching the user's unique widgets. Trap cleans up.
if kill -0 "$SP" 2>/dev/null; then
  SMOKE_WID=""
  cleanup_smoke_widget() {
    if [[ -n "${SMOKE_WID}" ]]; then
      qs -p /mnt/proteus/shell ipc call widgets remove "${SMOKE_WID}" >/dev/null 2>&1 || true
    fi
    # Leave Customize off for the rest of the session / later smokes.
    cust="$(qs -p /mnt/proteus/shell ipc call chrome state 2>/dev/null || echo '')"
    if [[ "${cust}" == *'"customize":true'* ]]; then
      qs -p /mnt/proteus/shell ipc call chrome customizeDesktop >/dev/null 2>&1 || true
    fi
    qs -p /mnt/proteus/shell ipc call widgets setSnap 0 >/dev/null 2>&1 || true
  }
  trap cleanup_smoke_widget EXIT

  before_state="$(qs -p /mnt/proteus/shell ipc call widgets state 2>/dev/null || echo '')"
  echo "WIDGETS_BEFORE=${before_state}"
  before_count="$(python3 -c 'import json,sys; d=json.loads(sys.argv[1] or "{}"); print(int(d.get("count",0)))' "${before_state}" 2>/dev/null || echo 0)"

  qs -p /mnt/proteus/shell ipc call chrome customizeDesktop >/dev/null 2>&1
  sleep 0.4
  cust_state="$(qs -p /mnt/proteus/shell ipc call chrome state 2>/dev/null || echo '')"
  if [[ "${cust_state}" == *'"customize":true'* ]]; then
    echo CUSTOMIZE_OK
  else
    echo "CUSTOMIZE_FAIL state=${cust_state}"
  fi

  SMOKE_WID="$(qs -p /mnt/proteus/shell ipc call widgets add worldclock 2>/dev/null | tr -d '\r' || true)"
  echo "WIDGETS_ADD_ID=${SMOKE_WID}"
  sleep 0.3
  after_add="$(qs -p /mnt/proteus/shell ipc call widgets state 2>/dev/null || echo '')"
  echo "WIDGETS_AFTER_ADD=${after_add}"
  after_count="$(python3 -c 'import json,sys; d=json.loads(sys.argv[1] or "{}"); print(int(d.get("count",0)))' "${after_add}" 2>/dev/null || echo 0)"
  if [[ -n "${SMOKE_WID}" && "${after_count}" -gt "${before_count}" ]]; then
    echo WIDGETS_ADD_OK
  else
    echo "WIDGETS_ADD_FAIL id=${SMOKE_WID} before=${before_count} after=${after_count}"
  fi

  if [[ -n "${SMOKE_WID}" ]]; then
    qs -p /mnt/proteus/shell ipc call widgets move "${SMOKE_WID}" 0.2 0.2 >/dev/null 2>&1
    sleep 0.15
    qs -p /mnt/proteus/shell ipc call widgets move "${SMOKE_WID}" 0.5 0.5 >/dev/null 2>&1
    sleep 0.15
    if kill -0 "$SP" 2>/dev/null; then
      echo WIDGETS_MOVE_OK
    else
      echo WIDGETS_MOVE_DEAD
    fi
  else
    echo WIDGETS_MOVE_SKIP
  fi

  qs -p /mnt/proteus/shell ipc call widgets setSnap 1 >/dev/null 2>&1
  sleep 0.2
  snap_on="$(qs -p /mnt/proteus/shell ipc call widgets state 2>/dev/null || echo '')"
  qs -p /mnt/proteus/shell ipc call widgets setSnap 0 >/dev/null 2>&1
  sleep 0.2
  snap_off="$(qs -p /mnt/proteus/shell ipc call widgets state 2>/dev/null || echo '')"
  if [[ "${snap_on}" == *'"snap":true'* && "${snap_off}" == *'"snap":false'* ]]; then
    echo WIDGETS_SNAP_OK
  else
    echo "WIDGETS_SNAP_FAIL on=${snap_on} off=${snap_off}"
  fi

  if [[ -n "${SMOKE_WID}" ]]; then
    qs -p /mnt/proteus/shell ipc call widgets remove "${SMOKE_WID}" >/dev/null 2>&1
    sleep 0.2
    after_rm="$(qs -p /mnt/proteus/shell ipc call widgets state 2>/dev/null || echo '')"
    echo "WIDGETS_AFTER_RM=${after_rm}"
    if [[ "${after_rm}" != *"${SMOKE_WID}"* ]]; then
      echo WIDGETS_REMOVE_OK
      SMOKE_WID=""
    else
      echo WIDGETS_REMOVE_FAIL
    fi
  fi

  qs -p /mnt/proteus/shell ipc call chrome customizeDesktop >/dev/null 2>&1
  sleep 0.3
  cust_end="$(qs -p /mnt/proteus/shell ipc call chrome state 2>/dev/null || echo '')"
  if [[ "${cust_end}" == *'"customize":false'* ]]; then
    echo CUSTOMIZE_EXIT_OK
  else
    echo "CUSTOMIZE_EXIT_FAIL state=${cust_end}"
  fi

  if kill -0 "$SP" 2>/dev/null; then
    echo WIDGETS_SHELL_ALIVE
  else
    echo WIDGETS_SHELL_DEAD
  fi

  trap - EXIT
  cleanup_smoke_widget
fi

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
echo "${out}" | grep -q POLKIT_AGENT_OK || { echo "qs-guest-smoke: FAIL hyprpolkitagent not running (pkexec auth prompts will fail)" >&2; exit 1; }
echo "${out}" | grep -q NAV_OK || { echo "qs-guest-smoke: FAIL Install… deep link (nav installSearch) did not land on packages-search" >&2; exit 1; }
echo "${out}" | grep -q DESKTOP_NAV_OK || { echo "qs-guest-smoke: FAIL Desktop nav go desktop-control-center did not land" >&2; exit 1; }
echo "${out}" | grep -q DESKTOP_SPACES_NAV_OK || { echo "qs-guest-smoke: FAIL Desktop nav go desktop-spaces did not land" >&2; exit 1; }
echo "${out}" | grep -q BEACON_OK || { echo "qs-guest-smoke: FAIL Beacon universal search (chrome beacon reboot) returned no action row" >&2; exit 1; }
echo "${out}" | grep -q FOCUS_OK || { echo "qs-guest-smoke: FAIL Beacon Focus action (chrome beacon focus) not found" >&2; exit 1; }
echo "${out}" | grep -q CALENDAR_OK || { echo "qs-guest-smoke: FAIL calendar popover (chrome calendar) did not open" >&2; exit 1; }
echo "${out}" | grep -q CUSTOMIZE_OK || { echo "qs-guest-smoke: FAIL Customize mode (chrome customizeDesktop) did not open" >&2; exit 1; }
echo "${out}" | grep -q WIDGETS_ADD_OK || { echo "qs-guest-smoke: FAIL widgets add (worldclock probe)" >&2; exit 1; }
echo "${out}" | grep -q WIDGETS_MOVE_OK || { echo "qs-guest-smoke: FAIL widgets move left shell dead or skipped" >&2; exit 1; }
echo "${out}" | grep -q WIDGETS_SNAP_OK || { echo "qs-guest-smoke: FAIL widgets setSnap did not round-trip" >&2; exit 1; }
echo "${out}" | grep -q WIDGETS_REMOVE_OK || { echo "qs-guest-smoke: FAIL widgets remove left probe id" >&2; exit 1; }
echo "${out}" | grep -q CUSTOMIZE_EXIT_OK || { echo "qs-guest-smoke: FAIL Customize did not exit" >&2; exit 1; }
echo "${out}" | grep -q WIDGETS_SHELL_ALIVE || { echo "qs-guest-smoke: FAIL shell died during widgets probe" >&2; exit 1; }
if echo "${out}" | grep -q LOG_ERRORS; then
  echo "qs-guest-smoke: FAIL TypeError / Invalid alias in logs" >&2
  exit 1
fi

echo "qs-guest-smoke: OK"
