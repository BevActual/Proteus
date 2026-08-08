#!/usr/bin/env bash
# session-smoke — host gate for proteus-session contract (smithay only)
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
  'PROTEUS_ICON_THEME' \
  'mount /mnt/proteus' \
  'proteus-compositor' \
  '--backend drm' \
  'Hyprland purged'
do
  grep -qF -- "${needle}" "${SESSION}" || fail "proteus-session missing: ${needle}"
done

grep -qE -- '""\|smithay\|compositor\|compositor-next\)|smithay DRM only' "${SESSION}" \
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
grep -qE 'DesktopNames=.*wlroots' "${DESKTOP}" \
  || fail "proteus.desktop must DesktopNames=wlroots (not Hyprland)"
grep -qiE 'DesktopNames=.*Hyprland' "${DESKTOP}" \
  && fail "proteus.desktop still DesktopNames=Hyprland"

WS="${ROOT}/shell/scripts/proteus-workspace"
[[ -f "${WS}" ]] || fail "missing proteus-workspace"
bash -n "${WS}" || fail "bash -n proteus-workspace"
grep -qE 'hyprctl\b' "${WS}" && fail "proteus-workspace still references hyprctl"
grep -q 'proteus-compositorctl\|need_ctl' "${WS}" \
  || fail "proteus-workspace missing compositorctl path"
"${WS}" selftest >/dev/null || fail "proteus-workspace selftest"

grep -q 'hw.env' "${SESSION}" || fail "proteus-session must source hw.env"
# shellcheck source=../../install/hardware/_lib.sh
source "${ROOT}/install/hardware/_lib.sh"
proteus_hw_env_selftest >/dev/null || fail "proteus_hw_env_selftest"
grep -q 'proteus_hw_session_envs' "${ROOT}/install/hardware/nvidia.sh" \
  || fail "nvidia.sh must write hw.env via proteus_hw_session_envs"
grep -qE '~/.config/hypr/proteus-hw\.conf|hyprland\.conf' \
  "${ROOT}/install/hardware/_lib.sh" \
  && fail "hardware/_lib.sh still writes Hypr conf"
if grep -qE '^quickshell$' "${ROOT}/install/proteus-base.packages" 2>/dev/null; then
  fail "base packages still list quickshell"
fi
if grep -qE '^hyprpicker$' "${ROOT}/install/proteus-base.packages" 2>/dev/null; then
  fail "base packages still list hyprpicker (use grim+slurp colorpick)"
fi
CP="${ROOT}/shell/scripts/proteus-colorpick"
[[ -f "${CP}" ]] || fail "missing proteus-colorpick"
bash -n "${CP}" || fail "bash -n proteus-colorpick"
grep -qE '(^|[[:space:]])hyprpicker([[:space:]]|$)' "${CP}" \
  && fail "proteus-colorpick still calls hyprpicker"
grep -q 'grim' "${CP}" || fail "proteus-colorpick must use grim"
# PPM one-pixel round-trip (no Wayland needed)
rgb="$(printf 'P6\n1 1\n255\n\xff\x80\x00' | python3 -c '
import sys
data = sys.stdin.buffer.read()
assert data.startswith(b"P6")
i = 2
while data[i] in b" \t\r\n":
    i += 1
parts = []
while len(parts) < 3:
    while data[i] in b" \t\r\n":
        i += 1
    start = i
    while data[i] not in b" \t\r\n":
        i += 1
    parts.append(data[start:i])
if data[i] in b" \t\r\n":
    i += 1
r, g, b = data[i], data[i+1], data[i+2]
print(f"#{r:02X}{g:02X}{b:02X}")
')"
[[ "${rgb}" == "#FF8000" ]] || fail "colorpick PPM parse expected #FF8000 got ${rgb}"

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
[[ -f "${ROOT}/compositor/src/binds.rs" ]] || fail "missing compositor binds.rs"

echo "session-smoke: OK proteus-session contract + proteus.desktop + idle + console-seat + keybinds"
