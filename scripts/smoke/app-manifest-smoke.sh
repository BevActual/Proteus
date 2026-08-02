#!/usr/bin/env bash
# app-manifest-smoke — env/apps catalog + schema + EnvGate posture/prefers gate
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APPS="${ROOT}/env/apps"
EG="${ROOT}/shell/shared/EnvGate.qml"
BEACON="${ROOT}/shell/surfaces/desktop/Beacon.qml"
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
for i, m in enumerate(mans):
    assert isinstance(m, dict), f"manifest[{i}] object"
    assert m.get("id"), f"manifest[{i}].id"
    unknown = set(m.keys()) - allowed
    assert not unknown, f"manifest[{i}] unknown keys: {unknown}"
    for key in ("requires", "requiresAny", "desktopIds", "prefers", "postures", "device_classes", "permissions"):
        if key in m:
            assert isinstance(m[key], list), f"manifest[{i}].{key} list"
    if m.get("postures"):
        has_postures = True
    if m.get("prefers"):
        has_prefers = True
assert has_postures, "catalog needs ≥1 postures example"
assert has_prefers, "catalog needs ≥1 prefers example"
# schema honesty: postures/prefers descriptions must not say unused
pref_desc = (props.get("prefers") or {}).get("description", "")
post_desc = (props.get("postures") or {}).get("description", "")
assert "unused" not in pref_desc.lower(), "schema prefers still says unused"
assert "unused" not in post_desc.lower(), "schema postures still says unused"
print("validate ok", len(mans), "manifests")
PY
ok "catalog validates (postures + prefers examples)"

grep -q 'postureAllowed\|postures' "${EG}" || die "EnvGate missing postures hard gate"
grep -q 'prefersHint\|prefersSatisfied\|appPrefersBoost' "${EG}" || die "EnvGate missing prefers soft path"
grep -q 'SessionPosture' "${EG}" || die "EnvGate must read SessionPosture"
grep -q 'appPrefersBoost\|appResultSubtitle\|appPrefersHint' "${BEACON}" \
  || die "Beacon must use prefers boost/hint"
ok "EnvGate + Beacon posture/prefers wiring"

[[ $fail -eq 0 ]] || { echo "app-manifest-smoke: FAILED" >&2; exit 1; }
echo "app-manifest-smoke: OK (schema + catalog + EnvGate)"
