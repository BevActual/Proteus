#!/usr/bin/env bash
# dogfood-console — one-command guest console flip + verify (+ optional seat).
# Usage (guest):
#   bash /mnt/proteus/vm/guest/dogfood-console.sh
#   bash /mnt/proteus/vm/guest/dogfood-console.sh --launch browser
#   bash /mnt/proteus/vm/guest/dogfood-console.sh --launch retroarch
#   bash /mnt/proteus/vm/guest/dogfood-console.sh --restore   # flip back to desktop
# Host: ssh … 'bash /mnt/proteus/vm/guest/dogfood-console.sh'
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

LAUNCH=""
RESTORE=0
SKIP_REPAIR="${PROTEUS_DOGFOOD_SKIP_REPAIR:-0}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --launch)
      LAUNCH="${2:-}"
      shift 2 || { echo "dogfood-console: --launch needs browser|retroarch" >&2; exit 2; }
      ;;
    --restore) RESTORE=1; shift ;;
    -h|--help)
      sed -n '2,10p' "$0" | sed 's/^# //;s/^#//'
      exit 0
      ;;
    *)
      echo "dogfood-console: unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

die() { echo "dogfood-console: FAIL $*" >&2; exit 1; }
log() { echo "dogfood-console: $*"; }

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
if [[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" && -d "${XDG_RUNTIME_DIR}/hypr" ]]; then
  HYPRLAND_INSTANCE_SIGNATURE="$(ls "${XDG_RUNTIME_DIR}/hypr" 2>/dev/null | head -1 || true)"
  export HYPRLAND_INSTANCE_SIGNATURE
fi
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
export PATH="/usr/local/bin:${ROOT}/shell/scripts:${ROOT}/vm/guest:${PATH}"

POSTURE_BIN=""
for c in proteus-posture "${ROOT}/vm/guest/proteus-posture" /usr/local/bin/proteus-posture; do
  if [[ -x "${c}" ]]; then POSTURE_BIN="${c}"; break; fi
done
[[ -n "${POSTURE_BIN}" ]] || die "proteus-posture not found (run apply-console-kit / overlay console)"

CAPS_BIN=""
for c in proteus-console-capabilities "${ROOT}/shell/scripts/proteus-console-capabilities"; do
  if [[ -x "${c}" ]]; then CAPS_BIN="${c}"; break; fi
done
SESSION_BIN=""
for c in proteus-console-session "${ROOT}/shell/scripts/proteus-console-session"; do
  if [[ -x "${c}" ]]; then SESSION_BIN="${c}"; break; fi
done
SEAT_BIN=""
for c in proteus-console-seat "${ROOT}/shell/scripts/proteus-console-seat"; do
  if [[ -x "${c}" ]]; then SEAT_BIN="${c}"; break; fi
done
SHELL_DIR="${ROOT}/shell"
QS_IPC=(qs -p "${SHELL_DIR}")
command -v qs >/dev/null 2>&1 || QS_IPC=(quickshell -p "${SHELL_DIR}")

repair_helpers() {
  [[ "${SKIP_REPAIR}" == "1" ]] && return 0
  local apply="${ROOT}/vm/guest/apply-console-kit.sh"
  [[ -x "${apply}" ]] || return 0
  # Helpers-only: packages owned by overlay console stage / install-console-software.
  if [[ ! -x /usr/local/bin/proteus-console-session && ! -x "${ROOT}/shell/scripts/proteus-console-session" ]]; then
    log "repairing helpers (session missing on PATH)"
  elif ! command -v proteus-console-session >/dev/null 2>&1; then
    log "repairing helpers (proteus-console-session not on PATH)"
  else
    return 0
  fi
  if [[ "${EUID}" -eq 0 ]]; then
    PROTEUS_SKIP_CONSOLE_PACKAGES=1 bash "${apply}" >/tmp/proteus-dogfood-repair.log 2>&1 \
      || log "warn: apply-console-kit repair failed (see /tmp/proteus-dogfood-repair.log)"
  elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    sudo env PROTEUS_SKIP_CONSOLE_PACKAGES=1 bash "${apply}" >/tmp/proteus-dogfood-repair.log 2>&1 \
      || log "warn: apply-console-kit repair failed (see /tmp/proteus-dogfood-repair.log)"
  else
    log "warn: cannot sudo repair helpers — run: sudo PROTEUS_SKIP_CONSOLE_PACKAGES=1 bash ${apply}"
  fi
  hash -r 2>/dev/null || true
  export PATH="/usr/local/bin:${ROOT}/shell/scripts:${ROOT}/vm/guest:${PATH}"
  SESSION_BIN=""
  for c in proteus-console-session "${ROOT}/shell/scripts/proteus-console-session"; do
    if [[ -x "${c}" ]]; then SESSION_BIN="${c}"; break; fi
  done
}

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

verify_target() {
  local want="$1"
  local fact="${XDG_CONFIG_HOME:-${HOME}/.config}/proteus/posture"
  [[ -f "${fact}" ]] || die "posture Fact missing (${fact})"
  local got
  got="$(tr -d '[:space:]' <"${fact}")"
  [[ "${got}" == "${want}" ]] || die "posture Fact=${got} want=${want}"

  local pointer="${HOME}/.config/hypr/proteus-profile.conf"
  [[ -f "${pointer}" ]] || die "hypr profile pointer missing"
  grep -q "profiles/${want}\\.conf" "${pointer}" \
    || die "proteus-profile.conf does not point at profiles/${want}.conf"

  local surface
  if ! surface="$(wait_surface "${want}")"; then
    die "chrome surface=${surface:-?} want=${want} (is Hyprland+QS live?)"
  fi
  log "OK Fact=${got} profile=${want} chrome.surface=${surface}"
}

print_caps_honesty() {
  [[ -n "${CAPS_BIN}" ]] || return 0
  local json
  json="$("${CAPS_BIN}" 2>/dev/null || echo '{}')"
  echo "${json}" | python3 -c 'import json,sys
d=json.load(sys.stdin)
print("dogfood-console: caps gamescopeUsable=%s vulkanHw=%s pad=%s isVm=%s steam=%s retroarch=%s sessionEffective=%s replacesHyprland=%s"
      % (d.get("gamescopeUsable"), d.get("vulkanHw"), d.get("pad"), d.get("isVm"),
         d.get("steam"), d.get("retroarch"), d.get("sessionEffective"), d.get("replacesHyprland")))
mode = "session (Gamescope owns the console session)" if d.get("sessionEffective") == "session" \
    else "interim (Hyprland kiosk + supervised seats)"
print("dogfood-console: console mode = " + mode)
if d.get("pad") is False:
  print("dogfood-console: hint pad — host: PROTEUS_VM_PAD=auto ./vm/run.sh (keyboard stand-ins OK without pad)")
if d.get("isVm") and not d.get("gamescopeUsable"):
  print("dogfood-console: hint Gamescope — VirGL has no hardware Vulkan; interim kiosk (expected). GPU passthrough: vm/README.md §VFIO")
' 2>/dev/null || true
  # Opt-in assert for bare metal / GPU-passthrough dogfood:
  #   PROTEUS_EXPECT_GS_SESSION=1 → capabilities must claim the session path.
  if [[ "${PROTEUS_EXPECT_GS_SESSION:-0}" == "1" ]]; then
    echo "${json}" | python3 -c 'import json,sys
d=json.load(sys.stdin)
assert d.get("gamescopeUsable") is True, "gamescopeUsable false — no hardware Vulkan (VFIO bound? vulkan-tools installed?)"
assert d.get("sessionEffective") == "session", "sessionEffective=%r — run: proteus-console-session set-mode session" % d.get("sessionEffective")
assert d.get("replacesHyprland") is True, "replacesHyprland false"
print("dogfood-console: OK gs-session capabilities (replacesHyprland)")
' || die "PROTEUS_EXPECT_GS_SESSION=1 but capabilities do not claim the Gamescope session"
  fi
  if [[ -z "${SESSION_BIN}" ]]; then
    log "warn: proteus-console-session missing — full packages: sudo bash ${ROOT}/vm/guest/install-console-software.sh"
  fi
  if ! command -v steam >/dev/null 2>&1 || ! command -v retroarch >/dev/null 2>&1; then
    log "hint packages — helpers-only kit is not the full console stage; use install-console-software.sh / PROTEUS_INSTALL_ONLY=console"
  fi
}

optional_launch() {
  local kind="$1"
  [[ -n "${SEAT_BIN}" ]] || die "proteus-console-seat missing"
  local logf="${XDG_RUNTIME_DIR}/proteus-console-seat.log"
  : >"${logf}" 2>/dev/null || true
  case "${kind}" in
    browser)
      local browser=""
      for b in firefox chromium google-chrome-stable brave; do
        if command -v "${b}" >/dev/null 2>&1; then browser="${b}"; break; fi
      done
      [[ -n "${browser}" ]] || die "no browser on PATH for --launch browser"
      log "launching seat browser (${browser})"
      "${SEAT_BIN}" --expect-class "${browser}|firefox|Chromium|brave-browser" -- \
        "${browser}" "https://proteus.local/" >/dev/null 2>&1 &
      ;;
    retroarch)
      command -v retroarch >/dev/null 2>&1 || die "retroarch missing (install-console-software / console stage)"
      log "launching seat retroarch"
      "${SEAT_BIN}" --expect-class 'com.libretro.RetroArch|retroarch' -- retroarch >/dev/null 2>&1 &
      ;;
    *)
      die "--launch expects browser|retroarch (got ${kind})"
      ;;
  esac
  local i
  for i in $(seq 1 30); do
    if [[ -f "${logf}" ]] && grep -qE 'mapped|fullscreen|seat' "${logf}" 2>/dev/null; then
      log "OK seat log activity → ${logf}"
      return 0
    fi
    sleep 0.4
  done
  log "warn: seat log quiet after launch — check ${logf}"
}

repair_helpers

if [[ "${RESTORE}" -eq 1 ]]; then
  log "restoring desktop"
  "${POSTURE_BIN}" desktop
  verify_target desktop
  print_caps_honesty
  log "done (desktop)"
  exit 0
fi

log "entering console"
"${POSTURE_BIN}" console
verify_target console
print_caps_honesty

if [[ -n "${LAUNCH}" ]]; then
  optional_launch "${LAUNCH}"
fi

log "done (console) — restore: $0 --restore"
exit 0
