#!/usr/bin/env bash
# peripherals-smoke — Touchpad/Tablet Settings depth (host static)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fail=0
ok() { echo "peripherals-smoke: OK $*"; }
die() { echo "peripherals-smoke: FAIL $*" >&2; fail=1; }

CFG="${ROOT}/shell/shared/Config.qml"
HYPR="${ROOT}/shell/shared/ConfigHypr.qml"
TOUCH="${ROOT}/apps/proteus-settings/panes/TouchpadPane.qml"
TAB="${ROOT}/apps/proteus-settings/panes/TabletPane.qml"
HUB="${ROOT}/apps/proteus-settings/panes/PeripheralsPane.qml"
SET="${ROOT}/apps/proteus-settings/Settings.qml"
FIX="${ROOT}/tests/fixtures/settings.minimal.json"
GEN="${ROOT}/env/hypr/proteus-general.conf"

for f in "${CFG}" "${HYPR}" "${TOUCH}" "${TAB}" "${HUB}" "${SET}" "${FIX}" "${GEN}"; do
  [[ -f "${f}" ]] || die "missing ${f#${ROOT}/}"
done
ok "files present"

grep -q 'touchpadNaturalScroll' "${CFG}" || die "Config missing touchpadNaturalScroll"
grep -q 'tabletOutput' "${CFG}" || die "Config missing tabletOutput"
grep -q 'onTouchpadNaturalScrollChanged' "${CFG}" || die "Config missing touchpad apply hook"
grep -q 'onTabletOutputChanged' "${CFG}" || die "Config missing tablet apply hook"
ok "Config Facts"

grep -q 'input:touchpad:natural_scroll' "${HYPR}" || die "ConfigHypr missing touchpad keyword"
grep -q 'input:touchpad:tap-to-click' "${HYPR}" || die "ConfigHypr missing tap-to-click"
grep -q 'input:tablet:relative_input' "${HYPR}" || die "ConfigHypr missing tablet keyword"
grep -q 'touchpad {' "${HYPR}" || die "ConfigHypr missing touchpad conf block"
grep -q 'tablet {' "${HYPR}" || die "ConfigHypr missing tablet conf block"
ok "ConfigHypr wire"

grep -q 'touchpad {' "${GEN}" || die "proteus-general.conf missing touchpad"
grep -q 'tablet {' "${GEN}" || die "proteus-general.conf missing tablet"
ok "general.conf template"

grep -q 'peripherals-touchpad' "${HUB}" || die "hub missing Touchpad"
grep -q 'peripherals-tablet' "${HUB}" || die "hub missing Tablet"
grep -q 'peripherals-touchpad' "${SET}" || die "Settings missing touchpad child"
grep -q 'TouchpadPane.qml' "${SET}" || die "Settings missing TouchpadPane loader"
grep -q 'TabletPane.qml' "${SET}" || die "Settings missing TabletPane loader"
grep -q 'Config.touchpadNaturalScroll' "${TOUCH}" || die "TouchpadPane unbound"
grep -q 'Config.tabletOutput' "${TAB}" || die "TabletPane unbound"
ok "Settings UI wiring"

python3 - <<PY || die "fixture keys"
import json
from pathlib import Path
d=json.loads(Path("${FIX}").read_text())
for k in ("touchpadNaturalScroll","touchpadTapToClick","touchpadDisableWhileTyping",
          "touchpadClickfinger","touchpadScrollFactor","tabletRelativeInput",
          "tabletLeftHanded","tabletOutput","tabletTransform"):
  assert k in d, k
PY
ok "fixture"

[[ $fail -eq 0 ]] || { echo "peripherals-smoke: FAILED" >&2; exit 1; }
echo "peripherals-smoke: OK"
