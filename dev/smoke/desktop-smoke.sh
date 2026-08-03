#!/usr/bin/env bash
# desktop-smoke — Desktop Settings leaves + defaults/Beacon helpers (host static)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fail=0
ok() { echo "desktop-smoke: OK $*"; }
die() { echo "desktop-smoke: FAIL $*" >&2; fail=1; }

DEFAULTS="${ROOT}/shell/scripts/proteus-defaults.py"
INDEX="${ROOT}/shell/scripts/beacon-file-index.py"
SHARED="${ROOT}/shell/shared"
PANES="${ROOT}/apps/proteus-settings/panes"

for f in \
  "${DEFAULTS}" "${INDEX}" \
  "${SHARED}/DefaultApps.qml" "${SHARED}/FocusMode.qml" "${SHARED}/ControlCenterLayout.qml" \
  "${PANES}/DesktopDefaultsLeaf.qml" "${PANES}/DesktopFocusLeaf.qml" \
  "${PANES}/DesktopControlCenterLeaf.qml" "${PANES}/DesktopSpacesLeaf.qml" \
  "${PANES}/DesktopLauncherLeaf.qml" "${PANES}/DesktopPane.qml"; do
  [[ -f "${f}" ]] || die "missing ${f#${ROOT}/}"
done
[[ -x "${DEFAULTS}" ]] || die "proteus-defaults.py not executable"
[[ -x "${INDEX}" ]] || die "beacon-file-index.py not executable"
ok "files present"

grep -q 'proteus-defaults.py' "${SHARED}/DefaultApps.qml" \
  || die "DefaultApps.qml must cite proteus-defaults.py"
grep -q 'FocusMode\|focusProfiles' "${PANES}/DesktopFocusLeaf.qml" \
  || die "DesktopFocusLeaf must wire FocusMode"
grep -q 'ControlCenterLayout' "${PANES}/DesktopControlCenterLeaf.qml" \
  || die "DesktopControlCenterLeaf must wire ControlCenterLayout"
grep -q 'workspaceMode' "${PANES}/DesktopSpacesLeaf.qml" \
  || die "DesktopSpacesLeaf must cite workspaceMode"
grep -q 'desktop-control-center' "${ROOT}/shell/surfaces/desktop/ControlCenter.qml" \
  || die "ControlCenter Edit tiles must openSettings desktop-control-center"
grep -q 'desktop-focus' "${PANES}/NotificationsPane.qml" \
  || die "NotificationsPane must jump to desktop-focus"
ok "leaf wiring"

# Beacon Settings blurb mentions Files / Privacy / Windows (copy honesty)
grep -qiE 'Files|file index|beacon-file-index' "${PANES}/DesktopLauncherLeaf.qml" \
  || die "DesktopLauncherLeaf blurb must mention Files index"
grep -qiE 'Privacy|Windows|wtype|Clipboard' "${PANES}/DesktopLauncherLeaf.qml" \
  || die "DesktopLauncherLeaf blurb must mention Privacy/Windows/clipboard"
ok "Beacon Settings blurb"

list_out="$(python3 "${DEFAULTS}" list 2>/dev/null || true)"
echo "${list_out}" | python3 -c 'import json,sys
d=json.load(sys.stdin)
assert isinstance(d, dict)
assert "categories" in d or d.get("ok") is True or isinstance(d.get("categories"), list) or True
# build_list returns categories key
cats = d.get("categories")
assert isinstance(cats, list) and len(cats) >= 1
' || die "proteus-defaults.py list JSON"
ok "proteus-defaults list"

python3 -m py_compile "${INDEX}" || die "beacon-file-index.py py_compile"
ok "beacon-file-index py_compile"

grep -q 'proteus-defaults.py' "${ROOT}/install/apps.sh" \
  || die "apps.sh must install proteus-defaults.py"
grep -q 'beacon-file-index.py' "${ROOT}/install/apps.sh" \
  || die "apps.sh must install beacon-file-index.py"
ok "apps.sh desktop helpers"

[[ $fail -eq 0 ]] || { echo "desktop-smoke: FAILED" >&2; exit 1; }
echo "desktop-smoke: OK"
