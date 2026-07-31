#!/usr/bin/env bash
# app-manifest-smoke — env/apps catalog + schema gate
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APPS="${ROOT}/env/apps"
fail=0

die() { echo "app-manifest-smoke: FAIL $*" >&2; fail=1; }
ok() { echo "app-manifest-smoke: OK $*"; }

[[ -f "${APPS}/schema.json" ]] || die "missing schema.json"
[[ -f "${APPS}/catalog.json" ]] || die "missing catalog.json"
[[ -f "${APPS}/README.md" ]] || die "missing README.md"
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
for i, m in enumerate(mans):
    assert isinstance(m, dict), f"manifest[{i}] object"
    assert m.get("id"), f"manifest[{i}].id"
    unknown = set(m.keys()) - allowed
    assert not unknown, f"manifest[{i}] unknown keys: {unknown}"
    for key in ("requires", "requiresAny", "desktopIds", "prefers", "postures", "device_classes"):
        if key in m:
            assert isinstance(m[key], list), f"manifest[{i}].{key} list"
print("validate ok", len(mans), "manifests")
PY
ok "catalog validates"
[[ $fail -eq 0 ]] || { echo "app-manifest-smoke: FAILED" >&2; exit 1; }
echo "app-manifest-smoke: OK (schema + catalog)"
