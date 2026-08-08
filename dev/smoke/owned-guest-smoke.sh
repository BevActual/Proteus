#!/usr/bin/env bash
# owned-guest-smoke — guest owned iced chrome (Wave 4 shipping path).
# Asserts shell-engine=owned, proteus-shell live, proteus-shellctl, Settings iced.
# Skip if SSH unreachable unless PROTEUS_GUEST=1 (then fail closed).
set -euo pipefail

# shellcheck source=dev/smoke/_guest_ssh.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_guest_ssh.sh"
proteus_guest_ssh_require_or_skip "owned-guest-smoke"

echo "owned-guest-smoke: guest SSH OK — assert owned chrome live"

out="$(proteus_guest_ssh 'bash -s' <<'EOF'
set -uo pipefail
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
export PATH="/usr/local/bin:$PATH"

engine="$(tr -d '[:space:]' <"${XDG_CONFIG_HOME:-$HOME/.config}/proteus/shell-engine" 2>/dev/null || true)"
if [[ -z "${engine}" && -f /etc/proteus/shell-engine ]]; then
  engine="$(tr -d '[:space:]' </etc/proteus/shell-engine || true)"
fi
echo "ENGINE=${engine:-unset}"

if [[ "${engine:-owned}" != "owned" && "${engine}" != "iced" && "${engine}" != "proteus-shell" ]]; then
  echo "ENGINE_NOT_OWNED"
fi

if command -v proteus-shell >/dev/null 2>&1 || [[ -x /usr/local/bin/proteus-shell ]]; then
  echo "BIN_OK"
else
  echo "BIN_MISSING"
fi

if pgrep -f '/usr/local/libexec/proteus/proteus-shell|/proteus-shell --face' >/dev/null 2>&1; then
  echo "SHELL_LIVE"
else
  echo "SHELL_DEAD"
fi

# Primary QS chrome / proteus-qs watchdog must not own the session
if pgrep -f 'shell/scripts/proteus-qs' >/dev/null 2>&1; then
  echo "QS_WATCHDOG_RUNNING"
elif pgrep -f 'quickshell -p /mnt/proteus/shell$' >/dev/null 2>&1 \
  || pgrep -f 'quickshell -p /mnt/proteus/shell ' >/dev/null 2>&1; then
  echo "QS_CHROME_STILL_RUNNING"
else
  echo "QS_CHROME_CLEAR"
fi

state="$(proteus-shellctl chrome state 2>/dev/null || echo '')"
echo "CTL_STATE=${state}"
if [[ "${state}" == *'"engine":"owned"'* ]] || [[ "${state}" == *'"ok":true'* ]]; then
  echo "CTL_OK"
else
  echo "CTL_FAIL"
fi

# Unlock session-start lock so surfaces are usable
proteus-shellctl lock unlock >/dev/null 2>&1 || true

# Settings iced (Wave 4) — binary present
if command -v proteus-settings >/dev/null 2>&1 \
  || command -v proteus-settings-next >/dev/null 2>&1 \
  || [[ -x /usr/local/bin/proteus-settings ]]; then
  echo "SETTINGS_BIN_OK"
else
  echo "SETTINGS_BIN_MISSING"
fi

# smithay session (only shipping path — Hyprland purged)
comp_eng="$(tr -d '[:space:]' <"${XDG_CONFIG_HOME:-$HOME/.config}/proteus/compositor-engine" 2>/dev/null || true)"
comp_eng="$(printf '%s' "${comp_eng}" | tr '[:upper:]' '[:lower:]')"
echo "COMPOSITOR_ENGINE=${comp_eng:-empty}"
if [[ "${comp_eng}" == "smithay" || "${comp_eng}" == "compositor" || "${comp_eng}" == "compositor-next" || -z "${comp_eng}" ]]; then
  # empty Fact is treated as smithay by proteus-session
  echo "COMPOSITOR_ENGINE_SMITHAY"
fi
if command -v proteus-compositor >/dev/null 2>&1 \
  || [[ -x /usr/local/bin/proteus-compositor ]] \
  || [[ -x /usr/local/libexec/proteus/proteus-compositor ]]; then
  echo "COMPOSITOR_BIN_OK"
else
  echo "COMPOSITOR_BIN_MISSING"
fi
if pgrep -x proteus-compositor >/dev/null 2>&1; then
  echo "COMPOSITOR_LIVE"
fi
# Chrome path: smithay Fact (or empty) + compositor binary (session -c proteus-chrome)
if command -v proteus-compositor >/dev/null 2>&1 \
  || [[ -x /usr/local/bin/proteus-compositor ]] \
  || [[ -x /usr/local/libexec/proteus/proteus-compositor ]]; then
  if [[ "${comp_eng}" == "smithay" || "${comp_eng}" == "compositor" \
     || "${comp_eng}" == "compositor-next" || -z "${comp_eng}" ]]; then
    echo "CHROME_PATH_OK"
  fi
fi
# Refuse lingering Hyprland session engine
if [[ "${comp_eng}" == "hyprland" ]]; then
  echo "COMPOSITOR_ENGINE_HYPRLAND"
fi
if pgrep -x Hyprland >/dev/null 2>&1; then
  echo "HYPRLAND_STILL_RUNNING"
fi

# HUD / lock ctl verbs
if proteus-shellctl hud volume 40 2>/dev/null | grep -q '"ok"'; then
  echo "HUD_OK"
else
  echo "HUD_FAIL"
fi
if proteus-shellctl lock lock 2>/dev/null | grep -q '"ok"'; then
  echo "LOCK_OK"
  proteus-shellctl lock unlock >/dev/null 2>&1 || true
else
  echo "LOCK_FAIL"
fi

# Beacon / CC still respond under glass chrome
if proteus-shellctl chrome launcher 2>/dev/null | grep -q '"ok"'; then
  echo "BEACON_OK"
  proteus-shellctl chrome launcher 2>/dev/null >/dev/null || true
else
  echo "BEACON_FAIL"
fi
if proteus-shellctl chrome controlCenter 2>/dev/null | grep -q '"ok"'; then
  echo "CC_OK"
  proteus-shellctl chrome controlCenter 2>/dev/null >/dev/null || true
else
  echo "CC_FAIL"
fi

# Lock GUI markers in installed bin (full-bleed / PIN path)
SHELL_BIN=/usr/local/libexec/proteus/proteus-shell
LOCK_BIN=/usr/local/libexec/proteus/proteus-session-lock
if [[ -x "${SHELL_BIN}" ]] && grep -aFq 'Click or type to unlock' "${SHELL_BIN}"; then
  echo "LOCK_GUI_OK"
elif [[ -x "${LOCK_BIN}" ]] && grep -aFq 'Click or type to unlock' "${LOCK_BIN}"; then
  echo "LOCK_GUI_OK"
else
  echo "LOCK_GUI_FAIL"
fi

# Owned engine renders the wallpaper — QS wallpaper loop must not be running
if pgrep -f "quickshell -p .*shell/wallpaper" >/dev/null 2>&1; then
  echo "WALLPAPER_QS_STILL_RUNNING"
else
  echo "WALLPAPER_OWNED_OK"
fi
EOF
)"

echo "${out}"

fail=0
echo "${out}" | grep -q '^ENGINE=owned$\|^ENGINE=iced$\|^ENGINE=proteus-shell$' || {
  # default owned when unset is OK only if shell live — require explicit owned fact
  if echo "${out}" | grep -q '^ENGINE=unset$'; then
    echo "owned-guest-smoke: FAIL shell-engine unset (expected owned)" >&2
    fail=1
  elif echo "${out}" | grep -q '^ENGINE_NOT_OWNED$'; then
    echo "owned-guest-smoke: FAIL shell-engine not owned" >&2
    fail=1
  fi
}
echo "${out}" | grep -q '^BIN_OK$' || { echo "owned-guest-smoke: FAIL proteus-shell bin missing" >&2; fail=1; }
echo "${out}" | grep -q '^SHELL_LIVE$' || { echo "owned-guest-smoke: FAIL proteus-shell not running" >&2; fail=1; }
echo "${out}" | grep -q '^QS_CHROME_CLEAR$' || { echo "owned-guest-smoke: FAIL Quickshell/proteus-qs still primary chrome" >&2; fail=1; }
echo "${out}" | grep -q '^CTL_OK$' || { echo "owned-guest-smoke: FAIL proteus-shellctl" >&2; fail=1; }
echo "${out}" | grep -q '^SETTINGS_BIN_OK$' || { echo "owned-guest-smoke: FAIL proteus-settings bin missing" >&2; fail=1; }
echo "${out}" | grep -q '^CHROME_PATH_OK$' \
  || { echo "owned-guest-smoke: FAIL chrome path (need smithay Fact + proteus-compositor)" >&2; fail=1; }
echo "${out}" | grep -q '^COMPOSITOR_BIN_OK$' \
  || { echo "owned-guest-smoke: FAIL proteus-compositor missing" >&2; fail=1; }
echo "${out}" | grep -q '^COMPOSITOR_ENGINE_HYPRLAND$' \
  && { echo "owned-guest-smoke: FAIL compositor-engine=hyprland (purged)" >&2; fail=1; }
echo "${out}" | grep -q '^HYPRLAND_STILL_RUNNING$' \
  && { echo "owned-guest-smoke: FAIL Hyprland still running" >&2; fail=1; }
echo "${out}" | grep -q '^HUD_OK$' || { echo "owned-guest-smoke: FAIL hud ctl" >&2; fail=1; }
echo "${out}" | grep -q '^LOCK_OK$' || { echo "owned-guest-smoke: FAIL lock ctl" >&2; fail=1; }
echo "${out}" | grep -q '^BEACON_OK$' || { echo "owned-guest-smoke: FAIL beacon ctl" >&2; fail=1; }
echo "${out}" | grep -q '^CC_OK$' || { echo "owned-guest-smoke: FAIL control center ctl" >&2; fail=1; }
echo "${out}" | grep -q '^LOCK_GUI_OK$' || { echo "owned-guest-smoke: FAIL lock GUI markers in bin" >&2; fail=1; }
echo "${out}" | grep -q '^WALLPAPER_OWNED_OK$' || { echo "owned-guest-smoke: FAIL QS wallpaper loop still running under owned" >&2; fail=1; }

if [[ "${fail}" -ne 0 ]]; then
  echo "owned-guest-smoke: FAILED" >&2
  exit 1
fi
echo "owned-guest-smoke: OK"
