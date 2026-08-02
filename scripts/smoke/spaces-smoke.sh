#!/usr/bin/env bash
# spaces-smoke — Spaces multi-display wiring + band math (host static)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fail=0
ok() { echo "spaces-smoke: OK $*"; }
die() { echo "spaces-smoke: FAIL $*" >&2; fail=1; }

WS="${ROOT}/shell/scripts/proteus-workspace"
STRIP="${ROOT}/shell/surfaces/desktop/Workspaces.qml"
LEAF="${ROOT}/apps/proteus-settings/panes/DesktopSpacesLeaf.qml"
BINDS="${ROOT}/env/hypr/proteus-keybinds.conf"
KB="${ROOT}/shell/shared/Keybinds.qml"

[[ -x "${WS}" ]] || die "proteus-workspace not executable"
[[ -f "${STRIP}" ]] || die "missing Workspaces.qml"
[[ -f "${LEAF}" ]] || die "missing DesktopSpacesLeaf.qml"
[[ -f "${BINDS}" ]] || die "missing proteus-keybinds.conf"
ok "files present"

bash -n "${WS}" || die "proteus-workspace bash -n"
"${WS}" selftest || die "proteus-workspace selftest"
ok "band math selftest"

grep -q 'proteus-workspace' "${STRIP}" || die "Workspaces.qml must invoke proteus-workspace"
grep -q 'workspaceMode' "${STRIP}" || die "Workspaces.qml must read workspaceMode"
grep -q 'perDisplay\|--local' "${STRIP}" || die "Workspaces.qml must support per-display / --local"
grep -q 'workspaceMode' "${LEAF}" || die "DesktopSpacesLeaf must bind workspaceMode"
grep -q 'proteus-workspace' "${BINDS}" || die "hypr keybinds must call proteus-workspace"
grep -q 'proteus-workspace goto 1' "${BINDS}" || die "hypr missing Super+1"
grep -q 'proteus-workspace goto 6' "${BINDS}" || die "hypr missing Super+6"
grep -q 'goto 1 --local' "${BINDS}" || die "hypr missing Super+Ctrl+1"
grep -q 'proteus-workspace' "${KB}" || die "Keybinds.qml must cite proteus-workspace"
grep -q 'proteus-workspace' "${ROOT}/vm/install/apps.sh" \
  || die "apps.sh must install proteus-workspace"
ok "shell + Settings + keybind wiring"

# Honesty: keyboard binds stop at 6; strip supports logical 1–10
if grep -qE 'proteus-workspace goto 7' "${BINDS}"; then
  die "hypr unexpectedly binds Super+7 (v1 documents keyboard 1–6 only)"
fi
grep -qiE '1–6|1-6' "${LEAF}" || die "DesktopSpacesLeaf must mention Super+Ctrl+1–6 keyboard range"
ok "1–6 keyboard honesty"

[[ $fail -eq 0 ]] || { echo "spaces-smoke: FAILED" >&2; exit 1; }
echo "spaces-smoke: OK"
