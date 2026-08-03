#!/usr/bin/env bash
# session-smoke — host gate for proteus-session contract (#1167)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SESSION="${ROOT}/shell/scripts/proteus-session"
DESKTOP="${ROOT}/install/machine/assets/proteus.desktop"

fail() { echo "session-smoke: FAIL $*" >&2; exit 1; }

[[ -f "${SESSION}" ]] || fail "missing ${SESSION}"
[[ -x "${SESSION}" ]] || fail "not executable: ${SESSION}"
bash -n "${SESSION}" || fail "bash -n proteus-session"

for needle in \
  'PROTEUS_SURFACE' \
  'PROTEUS_ROOT' \
  'QS_ICON_THEME' \
  'start-hyprland' \
  'Hyprland' \
  'mount /mnt/proteus'
do
  grep -qF "${needle}" "${SESSION}" || fail "proteus-session missing: ${needle}"
done

# Phase 3 engine switch: console posture + usable game_scope → Gamescope
# session, with fast-fail degrade back to the seat/Hyprland path.
for needle in \
  'PROTEUS_SESSION=1' \
  'console_session_wanted' \
  'proteus-console-gs-session' \
  'degrade_session_fact'
do
  grep -qF "${needle}" "${SESSION}" || fail "proteus-session missing engine switch: ${needle}"
done

# Must not launch a terminal from the session wrapper (ignore comments).
if grep -Eiq '^[[:space:]]*exec[[:space:]]+.*(ghostty|proteus-terminal)' "${SESSION}"; then
  fail "proteus-session must not exec a terminal"
fi
if grep -Eiq '^[[:space:]]*exec-once' "${SESSION}"; then
  fail "proteus-session must not use exec-once"
fi

[[ -f "${DESKTOP}" ]] || fail "missing ${DESKTOP}"
grep -qF 'Exec=/usr/local/bin/proteus-session' "${DESKTOP}" \
  || fail "proteus.desktop must Exec proteus-session"

echo "session-smoke: OK proteus-session contract + proteus.desktop"
