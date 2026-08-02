#!/usr/bin/env bash
# peripherals-smoke — Touchpad/Tablet + per-device device {} (host static)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fail=0
ok() { echo "peripherals-smoke: OK $*"; }
die() { echo "peripherals-smoke: FAIL $*" >&2; fail=1; }

CFG="${ROOT}/shell/shared/Config.qml"
HYPR="${ROOT}/shell/shared/ConfigHypr.qml"
TOUCH="${ROOT}/apps/proteus-settings/panes/TouchpadPane.qml"
TAB="${ROOT}/apps/proteus-settings/panes/TabletPane.qml"
MOUSE="${ROOT}/apps/proteus-settings/panes/MousePane.qml"
HUB="${ROOT}/apps/proteus-settings/panes/PeripheralsPane.qml"
SET="${ROOT}/apps/proteus-settings/Settings.qml"
FIX="${ROOT}/tests/fixtures/settings.minimal.json"
GEN="${ROOT}/env/hypr/proteus-general.conf"

for f in "${CFG}" "${HYPR}" "${TOUCH}" "${TAB}" "${MOUSE}" "${HUB}" "${SET}" "${FIX}" "${GEN}"; do
  [[ -f "${f}" ]] || die "missing ${f#${ROOT}/}"
done
ok "files present"

grep -q 'touchpadNaturalScroll' "${CFG}" || die "Config missing touchpadNaturalScroll"
grep -q 'tabletOutput' "${CFG}" || die "Config missing tabletOutput"
grep -q 'tabletActiveAreaSizeX\|tabletActiveAreaPosX' "${CFG}" \
  || die "Config missing tablet active-area Facts"
grep -q 'tabletPressureMin\|tabletPressureMax' "${CFG}" \
  || die "Config missing tablet pressure Facts"
grep -q 'tabletEraserButtonMode\|tabletEraserButtonOverride' "${CFG}" \
  || die "Config missing tablet eraser-button Facts"
grep -q 'tabletRegionSizeX\|tabletRegionPosX\|tabletRegionAbsolute' "${CFG}" \
  || die "Config missing tablet monitor-region Facts"
grep -q 'inputDeviceOverrides' "${CFG}" || die "Config missing inputDeviceOverrides"
grep -q 'upsertInputDeviceOverride\|inputDeviceOverridesList' "${CFG}" \
  || die "Config missing per-device override API"
grep -q 'onTouchpadNaturalScrollChanged' "${CFG}" || die "Config missing touchpad apply hook"
grep -q 'onTabletOutputChanged' "${CFG}" || die "Config missing tablet apply hook"
grep -q 'onTabletActiveAreaSizeXChanged\|onTabletPressureMinChanged' "${CFG}" \
  || die "Config missing tablet area/pressure apply hooks"
grep -q 'onTabletEraserButtonModeChanged\|onTabletEraserButtonOverrideChanged' "${CFG}" \
  || die "Config missing tablet eraser apply hooks"
grep -q 'onTabletRegionSizeXChanged\|onTabletRegionAbsoluteChanged' "${CFG}" \
  || die "Config missing tablet region apply hooks"
grep -q 'onInputDeviceOverridesChanged' "${CFG}" || die "Config missing device-override apply hook"
ok "Config Facts"

grep -q 'input:touchpad:natural_scroll' "${HYPR}" || die "ConfigHypr missing touchpad keyword"
grep -q 'input:touchpad:tap-to-click' "${HYPR}" || die "ConfigHypr missing tap-to-click"
grep -q 'input:tablet:relative_input' "${HYPR}" || die "ConfigHypr missing tablet keyword"
grep -q 'input:tablet:active_area_size' "${HYPR}" || die "ConfigHypr missing active_area_size"
grep -q 'input:tablet:region_size' "${HYPR}" || die "ConfigHypr missing region_size"
grep -q 'input:tablet:absolute_region_position' "${HYPR}" \
  || die "ConfigHypr missing absolute_region_position"
grep -q 'input:tablettool:pressure_range_min' "${HYPR}" || die "ConfigHypr missing pressure_range_min"
grep -q 'input:tablettool:eraser_button_mode' "${HYPR}" || die "ConfigHypr missing eraser_button_mode"
grep -q 'input:tablettool:eraser_button_override' "${HYPR}" \
  || die "ConfigHypr missing eraser_button_override"
grep -q 'touchpad {' "${HYPR}" || die "ConfigHypr missing touchpad conf block"
grep -q 'tablet {' "${HYPR}" || die "ConfigHypr missing tablet conf block"
grep -q 'tablettool {' "${HYPR}" || die "ConfigHypr missing tablettool conf block"
grep -q 'eraser_button_mode' "${HYPR}" || die "ConfigHypr missing eraser_button_mode emit"
grep -q 'active_area_size' "${HYPR}" || die "ConfigHypr missing active_area_size emit"
grep -q 'device {' "${HYPR}" || die "ConfigHypr missing device {} emit"
grep -q 'device\[' "${HYPR}" || die "ConfigHypr missing device[name] hyprctl keyword"
ok "ConfigHypr wire"

grep -q 'touchpad {' "${GEN}" || die "proteus-general.conf missing touchpad"
grep -q 'tablet {' "${GEN}" || die "proteus-general.conf missing tablet"
grep -q 'active_area_size' "${GEN}" || die "proteus-general.conf missing active_area_size"
grep -q 'region_size' "${GEN}" || die "proteus-general.conf missing region_size"
grep -q 'absolute_region_position' "${GEN}" \
  || die "proteus-general.conf missing absolute_region_position"
grep -q 'tablettool {' "${GEN}" || die "proteus-general.conf missing tablettool"
grep -q 'pressure_range_min' "${GEN}" || die "proteus-general.conf missing pressure_range_min"
grep -q 'eraser_button_mode' "${GEN}" || die "proteus-general.conf missing eraser_button_mode"
grep -q 'eraser_button_override' "${GEN}" || die "proteus-general.conf missing eraser_button_override"
ok "general.conf template"

grep -q 'peripherals-touchpad' "${HUB}" || die "hub missing Touchpad"
grep -q 'peripherals-tablet' "${HUB}" || die "hub missing Tablet"
grep -q 'peripherals-touchpad' "${SET}" || die "Settings missing touchpad child"
grep -q 'TouchpadPane.qml' "${SET}" || die "Settings missing TouchpadPane loader"
grep -q 'TabletPane.qml' "${SET}" || die "Settings missing TabletPane loader"
grep -q 'Config.touchpadNaturalScroll' "${TOUCH}" || die "TouchpadPane unbound"
grep -q 'Config.tabletOutput' "${TAB}" || die "TabletPane unbound"
grep -q 'Config.tabletActiveAreaSizeX\|Config.tabletActiveAreaPosX' "${TAB}" \
  || die "TabletPane missing active-area bindings"
grep -q 'Config.tabletPressureMin\|Config.tabletPressureMax' "${TAB}" \
  || die "TabletPane missing pressure bindings"
grep -q 'Config.tabletEraserButtonMode\|Config.tabletEraserButtonOverride' "${TAB}" \
  || die "TabletPane missing eraser-button bindings"
grep -q 'Pressure range\|linear remap' "${TAB}" \
  || die "TabletPane must label pressure as linear range"
grep -q 'Config.tabletRegionSizeX\|Config.tabletRegionAbsolute' "${TAB}" \
  || die "TabletPane missing monitor-region bindings"
grep -qiE 'per-tool|gestures stay Out|gesture maps stay Out|gestures Out' "${TAB}" \
  || die "TabletPane must keep curves/gestures Out honesty"
grep -q 'upsertInputDeviceOverride\|inputDeviceOverridesList' "${MOUSE}" \
  || die "MousePane missing per-device overrides UI"
grep -qiE 'device \{\}|Per-device|pressure' "${MOUSE}" \
  || die "MousePane must mention device {} / per-device honesty"
ok "Settings UI wiring"

python3 - <<PY || die "fixture keys"
import json
from pathlib import Path
d=json.loads(Path("${FIX}").read_text())
for k in ("touchpadNaturalScroll","touchpadTapToClick","touchpadDisableWhileTyping",
          "touchpadClickfinger","touchpadScrollFactor","tabletRelativeInput",
          "tabletLeftHanded","tabletOutput","tabletTransform",
          "tabletActiveAreaPosX","tabletActiveAreaPosY",
          "tabletActiveAreaSizeX","tabletActiveAreaSizeY",
          "tabletPressureMin","tabletPressureMax",
          "tabletEraserButtonMode","tabletEraserButtonOverride",
          "tabletRegionPosX","tabletRegionPosY",
          "tabletRegionSizeX","tabletRegionSizeY","tabletRegionAbsolute",
          "inputDeviceOverrides"):
  assert k in d, k
assert isinstance(d["inputDeviceOverrides"], list)
assert float(d["tabletPressureMin"]) == -1
assert float(d["tabletPressureMax"]) == -1
assert int(d["tabletEraserButtonMode"]) == 0
assert int(d["tabletEraserButtonOverride"]) == 0
assert d["tabletRegionAbsolute"] is False
PY
ok "fixture"

python3 - <<'PY' || die "inputDeviceOverrides normalize fixture"
# Mirror Config.inputDeviceOverridesList rules
def normalize(raw):
    out, seen = [], set()
    for row in raw or []:
        if not isinstance(row, dict):
            continue
        name = str(row.get("name") or "").strip()
        if not name or "\n" in name or "}" in name or name in seen:
            continue
        seen.add(name[:128])
        name = name[:128]
        try:
            sens = float(row.get("sensitivity", 0))
        except Exception:
            sens = 0.0
        sens = max(-1.0, min(1.0, round(sens * 10) / 10))
        out.append({"name": name, "sensitivity": sens, "accelFlat": bool(row.get("accelFlat"))})
        if len(out) >= 16:
            break
    return out

rows = normalize([
    {"name": "epic-mouse-v1", "sensitivity": 0.55, "accelFlat": True},
    {"name": "epic-mouse-v1", "sensitivity": 0},
    {"name": "bad\nname", "sensitivity": 1},
    {"name": "trackball", "sensitivity": 2, "accelFlat": False},
])
assert rows[0]["name"] == "epic-mouse-v1" and rows[0]["sensitivity"] == 0.6
assert rows[0]["accelFlat"] is True
assert rows[1]["name"] == "trackball" and rows[1]["sensitivity"] == 1.0
assert len(rows) == 2
print("ok")
PY
ok "inputDeviceOverrides normalize"

[[ $fail -eq 0 ]] || { echo "peripherals-smoke: FAILED" >&2; exit 1; }
echo "peripherals-smoke: OK"
