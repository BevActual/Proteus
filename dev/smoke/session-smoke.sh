#!/usr/bin/env bash
# session-smoke — host gate for proteus-session contract (#1167 · Hyprland purge)
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
  'mount /mnt/proteus' \
  'proteus-compositor-next' \
  '--backend drm' \
  'Hyprland purged'
do
  grep -qF -- "${needle}" "${SESSION}" || fail "proteus-session missing: ${needle}"
done

grep -qE -- '""\|smithay\|compositor-next\)|smithay DRM only' "${SESSION}" \
  || fail "proteus-session missing smithay-only engine"

# Must not start Hyprland / start-hyprland (case-sensitive — Fact name hyprland is OK).
if grep -Eq '^[[:space:]]*exec[[:space:]]+(start-hyprland|Hyprland)\b' "${SESSION}"; then
  fail "proteus-session must not exec Hyprland (purged)"
fi
if grep -Eq '^[[:space:]]*(start-hyprland|Hyprland)\b' "${SESSION}"; then
  fail "proteus-session must not invoke Hyprland binary (purged)"
fi
grep -q 'resolve_start_hyprland' "${SESSION}" \
  && fail "proteus-session still has resolve_start_hyprland"

# Phase 3 engine switch: console posture + usable game_scope → Gamescope
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

# Owned idle (replaces hypridle) + compositorctl seat path
IDLE="${ROOT}/shell/scripts/proteus-idle"
[[ -f "${IDLE}" ]] || fail "missing proteus-idle"
bash -n "${IDLE}" || fail "bash -n proteus-idle"
[[ -f "${ROOT}/install/machine/assets/proteus-idle.service" ]] \
  || fail "missing proteus-idle.service asset"
if grep -qE '^hypridle$' "${ROOT}/install/proteus-base.packages" 2>/dev/null; then
  fail "base packages still list hypridle"
fi
SEAT="${ROOT}/shell/scripts/proteus-console-seat"
[[ -f "${SEAT}" ]] || fail "missing proteus-console-seat"
grep -qE 'hyprctl\b' "${SEAT}" && fail "proteus-console-seat still references hyprctl"
grep -q 'compositorctl' "${SEAT}" || fail "proteus-console-seat missing compositorctl"

KB="${ROOT}/install/machine/install-keybinds.sh"
[[ -f "${KB}" ]] || fail "missing install-keybinds.sh"
bash -n "${KB}" || fail "bash -n install-keybinds"
grep -q 'keybinds.json' "${KB}" || fail "install-keybinds must seed keybinds.json"
[[ -f "${ROOT}/env/settings/keybinds.defaults.json" ]] \
  || fail "missing keybinds.defaults.json"
[[ -f "${ROOT}/compositor-next/src/binds.rs" ]] || fail "missing compositor binds.rs"

echo "session-smoke: OK proteus-session contract + proteus.desktop + idle + console-seat + keybinds"
