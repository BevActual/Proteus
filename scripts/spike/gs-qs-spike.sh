#!/usr/bin/env bash
# gs-qs-spike — prove Quickshell runs as a plain xdg client under gamescope.
# Gate for the Gamescope-as-session console Home (COMPOSITOR.md Phase 3).
#
# Checks:
#   1. gamescope starts (nested under the current session, or on a TTY)
#   2. quickshell FloatingWindow maps inside it
#   3. Quickshell.Io Process works (uname round-trip)
#   4. `qs ipc` reachable from a sibling shell
#
# Usage:
#   ./scripts/spike/gs-qs-spike.sh                 # system gamescope/quickshell
#   PROTEUS_GS_SPIKE_ROOT=~/.cache/proteus-gs-spike/root ./scripts/spike/gs-qs-spike.sh
#     (extracted-package root when gamescope/quickshell are not installed;
#      populate with `tar --zstd -xf <pkg>` of gamescope, quickshell,
#      qt6-wayland, qt6-svg, cpptrace into $ROOT)
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE="${HERE}/gs-qs-spike"
TIMEOUT="${PROTEUS_GS_SPIKE_TIMEOUT:-25}"

log() { echo "gs-qs-spike: $*"; }
fail() { echo "gs-qs-spike: FAIL $*" >&2; cleanup; exit 1; }

SPIKE_ROOT="${PROTEUS_GS_SPIKE_ROOT:-}"
GS_BIN="$(command -v gamescope || true)"
QS_BIN="$(command -v qs || command -v quickshell || true)"
if [[ -n "${SPIKE_ROOT}" ]]; then
  [[ -x "${SPIKE_ROOT}/usr/bin/gamescope" ]] && GS_BIN="${SPIKE_ROOT}/usr/bin/gamescope"
  [[ -x "${SPIKE_ROOT}/usr/bin/quickshell" ]] && QS_BIN="${SPIKE_ROOT}/usr/bin/quickshell"
  # gamescope execs gamescopereaper from PATH for its primary child
  export PATH="${SPIKE_ROOT}/usr/bin:${PATH}"
  export LD_LIBRARY_PATH="${SPIKE_ROOT}/usr/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
  export QT_PLUGIN_PATH="${SPIKE_ROOT}/usr/lib/qt6/plugins:/usr/lib/qt6/plugins${QT_PLUGIN_PATH:+:${QT_PLUGIN_PATH}}"
  export QML2_IMPORT_PATH="${SPIKE_ROOT}/usr/lib/qt6/qml:/usr/lib/qt6/qml${QML2_IMPORT_PATH:+:${QML2_IMPORT_PATH}}"
fi
[[ -n "${GS_BIN}" ]] || fail "gamescope not found (install or set PROTEUS_GS_SPIKE_ROOT)"
[[ -n "${QS_BIN}" ]] || fail "quickshell not found (install or set PROTEUS_GS_SPIKE_ROOT)"
log "gamescope: ${GS_BIN}"
log "quickshell: ${QS_BIN}"

RUNDIR="${XDG_RUNTIME_DIR:-/tmp}"
GS_LOG="${RUNDIR}/gs-qs-spike.gamescope.log"
GS_PID=""

cleanup() {
  if [[ -n "${GS_PID}" ]] && kill -0 "${GS_PID}" 2>/dev/null; then
    kill "${GS_PID}" 2>/dev/null
    sleep 0.5
    kill -9 "${GS_PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

start_gamescope() {
  local backend="$1"
  local args=(-W 1280 -H 720)
  [[ -n "${backend}" ]] && args+=(--backend "${backend}")
  log "starting gamescope ${args[*]} -- quickshell -p ${PROFILE}"
  # Prefer wayland-native for the client (gamescope only exports DISPLAY by
  # default); QS falls back to Xwayland if the wayland QPA cannot load.
  "${GS_BIN}" "${args[@]}" -- env "QT_QPA_PLATFORM=wayland;xcb" \
    WAYLAND_DISPLAY=gamescope-0 "${QS_BIN}" -p "${PROFILE}" >"${GS_LOG}" 2>&1 &
  GS_PID=$!
}

# Nested first (running desktop session); SDL fallback for odd stacks.
start_gamescope ""
sleep 3
if ! kill -0 "${GS_PID}" 2>/dev/null; then
  log "default backend exited early — retrying with --backend sdl (log: ${GS_LOG})"
  start_gamescope "sdl"
  sleep 3
  kill -0 "${GS_PID}" 2>/dev/null || fail "gamescope did not stay up (see ${GS_LOG})"
fi
log "gamescope up (pid ${GS_PID})"

# Poll spike IPC from this (sibling) shell — proves qs ipc works across
# process boundaries while QS lives inside the gamescope session.
#
# LEARNING (feeds proteus-console-gs-session): Quickshell IPC discovery is
# display-scoped — even `qs ipc -i <id>` refuses instances on another display.
# The caller must share the instance's DISPLAY/WAYLAND_DISPLAY, so the real
# session script must export gamescope's displays to proteus-guide + helpers.
find_pid() {
  # NB: python reads JSON from the pipe; program must be -c (a heredoc on
  # `python3 -` would clobber stdin and json.load would see EOF).
  "${QS_BIN}" list -a -j 2>/dev/null | python3 -c '
import json, sys
profile = sys.argv[1].rstrip("/")
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
instances = data if isinstance(data, list) else data.get("instances", [])
for inst in instances:
    conf = str(inst.get("config_path") or inst.get("configPath") or "")
    if conf.startswith(profile):
        print(inst.get("pid") or "")
        break
' "${PROFILE}"
}

env_of() { tr '\0' '\n' <"/proc/$1/environ" 2>/dev/null | rg "^$2=" | head -1 | cut -d= -f2-; }

STATUS=""
for _ in $(seq 1 "${TIMEOUT}"); do
  QS_CHILD_PID="$(find_pid || true)"
  if [[ -n "${QS_CHILD_PID}" ]]; then
    CH_DISPLAY="$(env_of "${QS_CHILD_PID}" DISPLAY || true)"
    CH_WAYLAND="$(env_of "${QS_CHILD_PID}" WAYLAND_DISPLAY || true)"
    STATUS="$(DISPLAY="${CH_DISPLAY}" WAYLAND_DISPLAY="${CH_WAYLAND}" \
      "${QS_BIN}" -p "${PROFILE}" ipc call spike status 2>/dev/null || true)"
    [[ -n "${STATUS}" ]] && break
  fi
  sleep 1
done
[[ -n "${STATUS}" ]] || fail "no IPC response from spike shell within ${TIMEOUT}s (see ${GS_LOG})"
log "ipc status: ${STATUS}"

python3 - "${STATUS}" <<'PY' || fail "spike status incomplete"
import json, sys
d = json.loads(sys.argv[1])
assert d.get("mapped") is True, f"window did not map: {d}"
assert d.get("processOk") is True, f"Process fact failed: {d}"
wl = d.get("waylandDisplay", "")
x11 = d.get("x11Display", "")
on_gs = wl.startswith("gamescope") or bool(x11)
assert on_gs, f"not on a gamescope display: {d}"
mode = "wayland-native " + wl if wl.startswith("gamescope") else "xwayland " + x11
print("gs-qs-spike: window mapped | Process OK | client mode: " + mode)
PY

log "PASS — Quickshell FloatingWindow works as a gamescope client"
