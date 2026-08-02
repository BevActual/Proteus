#!/usr/bin/env bash
# app-manifest-smoke — env/apps catalog + schema + EnvGate postures/prefers/device_classes/adapts
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APPS="${ROOT}/env/apps"
EG="${ROOT}/shell/shared/EnvGate.qml"
BEACON="${ROOT}/shell/surfaces/desktop/Beacon.qml"
DOCK="${ROOT}/shell/shared/DockApps.qml"
fail=0

die() { echo "app-manifest-smoke: FAIL $*" >&2; fail=1; }
ok() { echo "app-manifest-smoke: OK $*"; }

[[ -f "${APPS}/schema.json" ]] || die "missing schema.json"
[[ -f "${APPS}/catalog.json" ]] || die "missing catalog.json"
[[ -f "${APPS}/README.md" ]] || die "missing README.md"
[[ -f "${EG}" ]] || die "missing EnvGate.qml"
ok "files present"

python3 - "${APPS}/schema.json" "${APPS}/catalog.json" <<'PY' || die "python validate"
import json, sys
schema_path, catalog_path = sys.argv[1], sys.argv[2]
with open(schema_path, encoding="utf-8") as f:
    schema = json.load(f)
with open(catalog_path, encoding="utf-8") as f:
    catalog = json.load(f)
assert schema.get("type") == "object", "schema.type"
assert "id" in schema.get("required", []), "schema.required id"
mans = catalog.get("manifests")
assert isinstance(mans, list) and len(mans) >= 2, "catalog.manifests (>=2)"
props = schema.get("properties", {})
allowed = set(props.keys())
has_postures = False
has_prefers = False
has_device_classes = False
has_adapts = False
has_adapts_panes = False
for i, m in enumerate(mans):
    assert isinstance(m, dict), f"manifest[{i}] object"
    assert m.get("id"), f"manifest[{i}].id"
    unknown = set(m.keys()) - allowed
    assert not unknown, f"manifest[{i}] unknown keys: {unknown}"
    for key in ("requires", "requiresAny", "desktopIds", "prefers", "postures", "device_classes", "permissions"):
        if key in m:
            assert isinstance(m[key], list), f"manifest[{i}].{key} list"
    if "adapts" in m:
        assert isinstance(m["adapts"], dict), f"manifest[{i}].adapts object"
        has_adapts = True
        if isinstance(m["adapts"].get("panes"), list) and m["adapts"]["panes"]:
            has_adapts_panes = True
    if m.get("postures"):
        has_postures = True
    if m.get("prefers"):
        has_prefers = True
    if m.get("device_classes"):
        has_device_classes = True
assert has_postures, "catalog needs ≥1 postures example"
assert has_prefers, "catalog needs ≥1 prefers example"
assert has_device_classes, "catalog needs ≥1 device_classes example"
assert has_adapts, "catalog needs ≥1 adapts example"
assert has_adapts_panes, "catalog needs ≥1 adapts.panes example"
assert "adapts" in props, "schema missing adapts"
adapts_props = (props.get("adapts") or {}).get("properties") or {}
assert "input" in adapts_props and "nav" in adapts_props and "panes" in adapts_props, \
    "schema adapts must define input/nav/panes"
adapts_desc = (props.get("adapts") or {}).get("description", "")
assert "never block" in adapts_desc.lower() or "never blocks" in adapts_desc.lower(), \
    "schema adapts must say never blocks"
# schema honesty: postures/prefers/device_classes must not say unused
pref_desc = (props.get("prefers") or {}).get("description", "")
post_desc = (props.get("postures") or {}).get("description", "")
dc_desc = (props.get("device_classes") or {}).get("description", "")
assert "unused" not in pref_desc.lower(), "schema prefers still says unused"
assert "unused" not in post_desc.lower(), "schema postures still says unused"
assert "unused" not in dc_desc.lower(), "schema device_classes still says unused"
assert "hardware.deviceclass" in dc_desc.lower() or "device class" in dc_desc.lower(), \
    "schema device_classes must mention Hardware.deviceClass / device class"
print("validate ok", len(mans), "manifests")
PY
ok "catalog validates (postures + prefers + device_classes + adapts examples)"

grep -q 'postureAllowed\|postures' "${EG}" || die "EnvGate missing postures hard gate"
grep -q 'deviceClassAllowed\|deviceClasses\|device_classes' "${EG}" \
  || die "EnvGate missing device_classes hard gate"
grep -q 'deviceClassBlockReason' "${EG}" || die "EnvGate missing deviceClassBlockReason"
grep -q 'prefersHint\|prefersSatisfied\|appPrefersBoost' "${EG}" || die "EnvGate missing prefers soft path"
grep -q 'appAdaptProfile\|appAdaptHint' "${EG}" || die "EnvGate missing adapts resolver"
grep -q 'appAdaptLaunchEnv\|PROTEUS_ADAPT_INPUT\|PROTEUS_ADAPT_NAV\|PROTEUS_ADAPT_PANES' "${EG}" \
  || die "EnvGate missing appAdaptLaunchEnv / PROTEUS_ADAPT_*"
grep -q 'FocusMode.paneDensity\|paneDensity' "${EG}" \
  || die "EnvGate must resolve panes via FocusMode.paneDensity"
grep -q 'out.panes\|panes = pick' "${EG}" || die "EnvGate must set out.panes"
grep -q 'minimalPaneAllow\|paneAllowedWhenMinimal\|Hidden while Focus' "${EG}" \
  || die "EnvGate missing Focus hard pane hide wedge"
grep -q 'paneAvailable(p.id)' "${ROOT}/shell/shared/UniversalSearch.qml" \
  || die "UniversalSearch must gate Settings hits by pane id"
grep -q 'EnvGate.paneAvailable\|FocusMode.paneDensity' \
  "${ROOT}/apps/proteus-settings/panes/DesktopPane.qml" \
  || die "DesktopPane must filter leaves via EnvGate when Focus minimal"
grep -q 'Focus pane density\|Hidden while Focus\|FocusMode.active' \
  "${ROOT}/apps/proteus-settings/panes/SystemPane.qml" \
  || die "SystemPane must surface Focus pane density honesty"
grep -q 'adapts:' "${EG}" || die "EnvGate ruleFromManifest missing adapts"
grep -q 'SessionPosture' "${EG}" || die "EnvGate must read SessionPosture"
grep -q 'Hardware.deviceClass\|activeDeviceClass' "${EG}" \
  || die "EnvGate must read Hardware.deviceClass"
grep -q 'appPrefersBoost\|appResultSubtitle\|appPrefersHint' "${BEACON}" \
  || die "Beacon must use prefers boost/hint"
grep -q 'appAdaptHint' "${BEACON}" || die "Beacon must use appAdaptHint"
grep -q 'DockApps.launchEntry' "${BEACON}" || die "Beacon must launch via DockApps.launchEntry"
grep -q 'appAvailable\|appBlockReason\|appAvailabilitySubtitle' "${BEACON}" \
  || die "Beacon must surface availability / block reason"
grep -q 'EnvGate.appAvailable' "${DOCK}" || die "DockApps must use EnvGate.appAvailable"
grep -q 'appAdaptLaunchEnv\|PROTEUS_ADAPT_\|environment: adaptEnv' "${DOCK}" \
  || die "DockApps must inject PROTEUS_ADAPT_* launch env"
# Regression: adapt-env path once required desk.command before execute() —
# dock pins then never launched when DesktopEntry.command was empty.
# focusOrLaunch uses root.launchEntry — Singleton must declare id: root.
awk 'BEGIN{ok=0} /^Singleton \{/{s=1} s&&/id: root/{ok=1; exit} END{exit !ok}' "${DOCK}" \
  || die "DockApps Singleton must declare id: root (focusOrLaunch uses root.launchEntry)"
grep -q 'deskOrSelf.execute\|launchDesktopIdFallback' "${DOCK}" \
  || die "DockApps.launchEntry must call DesktopEntry.execute or gtk-launch fallback"
if grep -q 'deskOrSelf && deskOrSelf.command && deskOrSelf.command.length' "${DOCK}"; then
  die "DockApps.launchEntry must not gate execute() on command.length"
fi
grep -q 'gtk-launch' "${DOCK}" \
  || die "DockApps must gtk-launch fallback when DesktopEntries miss"
grep -q 'PrivacyAsk.promptLaunch' "${DOCK}" \
  || die "DockApps.focusOrLaunch must use PrivacyAsk.promptLaunch"
grep -q 'XDG_DATA_DIRS' "${ROOT}/shell/scripts/proteus-qs" \
  || die "proteus-qs must export XDG_DATA_DIRS for DesktopEntries"
grep -q 'proteus-dock-activate' "${DOCK}" \
  || die "DockApps must use proteus-dock-activate for pin clicks"
SS="${ROOT}/shell/shared/ShellState.qml"
AE="${ROOT}/shell/shared/AdaptEnv.qml"
SP="${ROOT}/apps/proteus-settings/panes/SystemPane.qml"
[[ -f "${AE}" ]] || die "missing AdaptEnv.qml"
grep -q 'PROTEUS_ADAPT_INPUT\|PROTEUS_ADAPT_NAV\|PROTEUS_ADAPT_PANES' "${AE}" \
  || die "AdaptEnv must read PROTEUS_ADAPT_*"
grep -q 'AdaptEnv' "${SP}" || die "SystemPane must surface AdaptEnv"
grep -q 'PROTEUS_REMOTE_PROBE\|remoteProbeStub\|remoteFromProbe\|Remote input' "${SP}" \
  || die "SystemPane must surface remote probe / stub status"
grep -q 'appAdaptLaunchEnv\|PROTEUS_ADAPT_' "${SS}" \
  || die "ShellState.openSettings must inject PROTEUS_ADAPT_*"
grep -q '"id": "proteus-settings"' "${APPS}/catalog.json" \
  || die "catalog missing proteus-settings adapts consumer"
python3 - "${APPS}/catalog.json" <<'PY' || die "proteus-settings catalog adapts"
import json, sys
c = json.load(open(sys.argv[1], encoding="utf-8"))
m = next(x for x in c["manifests"] if x.get("id") == "proteus-settings")
assert isinstance(m.get("adapts"), dict) and m["adapts"].get("panes")
print("ok")
PY
ok "EnvGate + Beacon/Dock posture/prefers/device_classes/adapts wiring + consumer"

HW="${ROOT}/shell/shared/Hardware.qml"
grep -q 'PROTEUS_REMOTE_PROBE\|remoteProbeStub\|remoteFromProbe' "${HW}" \
  || die "Hardware missing remote probe stub / remoteFromProbe"
grep -q 'c === "remote"\|cap === "remote"' "${HW}" \
  || die "Hardware.has must handle remote stub"
# EnvGate must resolve remote via Hardware.has — not hard-skip the token.
if grep -qE 'cap === "remote"[[:space:]]*$|cap === "remote"\)' "${EG}"; then
  die "EnvGate must not hard-skip adapts.input remote"
fi
if awk '/const inputs = adapts.input/,/const navs = adapts.nav/' "${EG}" \
  | grep -q 'cap === "remote"'; then
  die "EnvGate input loop still skips remote"
fi
grep -q 'Hardware.has(cap)' "${EG}" || die "EnvGate must call Hardware.has for input caps"
in_desc="$(python3 - "${APPS}/schema.json" <<'PY'
import json, sys
s = json.load(open(sys.argv[1], encoding="utf-8"))
print((s["properties"]["adapts"]["properties"]["input"].get("description") or ""))
PY
)"
echo "${in_desc}" | grep -qi 'PROTEUS_REMOTE_PROBE\|remote stub\|Hardware.has' \
  || die "schema adapts.input must mention remote stub / Hardware.has"
echo "${in_desc}" | grep -qiE 'skipped until probed' \
  && die "schema still says remote skipped until probed"
python3 - "${APPS}/catalog.json" <<'PY' || die "catalog needs adapts.input remote example"
import json, sys
c = json.load(open(sys.argv[1], encoding="utf-8"))
found = False
for m in c.get("manifests") or []:
    inp = ((m.get("adapts") or {}).get("input")) or []
    if "remote" in [str(x).lower() for x in inp]:
        found = True
        break
assert found, "no adapts.input remote in catalog"
print("ok")
PY
ok "remote probe stub (Hardware + EnvGate + schema/catalog)"

[[ $fail -eq 0 ]] || { echo "app-manifest-smoke: FAILED" >&2; exit 1; }
echo "app-manifest-smoke: OK (schema + catalog + EnvGate)"
