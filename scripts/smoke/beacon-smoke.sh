#!/usr/bin/env bash
# beacon-smoke — Beacon Files index + UniversalSearch wiring (host static)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fail=0
ok() { echo "beacon-smoke: OK $*"; }
die() { echo "beacon-smoke: FAIL $*" >&2; fail=1; }

INDEX="${ROOT}/shell/scripts/beacon-file-index.py"
BEACON="${ROOT}/shell/surfaces/desktop/Beacon.qml"
US="${ROOT}/shell/shared/UniversalSearch.qml"

[[ -x "${INDEX}" ]] || die "beacon-file-index.py not executable"
[[ -f "${BEACON}" ]] || die "missing Beacon.qml"
[[ -f "${US}" ]] || die "missing UniversalSearch.qml"
ok "files present"

grep -q 'UniversalSearch' "${BEACON}" || die "Beacon must consume UniversalSearch"
grep -q 'beacon-file-index.py' "${BEACON}" || die "Beacon must invoke beacon-file-index.py"
grep -q 'defaultAppSubtitle' "${BEACON}" || die "Beacon must subtitle files with defaultAppSubtitle"
grep -q 'wtypeProbe\|wtype' "${BEACON}" || die "Beacon must probe wtype for clipboard paste"
grep -q 'actionCatalog' "${US}" || die "UniversalSearch must expose actionCatalog"
ok "Beacon + UniversalSearch wiring"

grep -q 'beacon-file-index.py' "${ROOT}/vm/install/apps.sh" \
  || die "apps.sh must install beacon-file-index.py"
ok "apps.sh install"

TMPHOME="$(mktemp -d)"
trap 'rm -rf "${TMPHOME}"' EXIT
export HOME="${TMPHOME}"
export XDG_CACHE_HOME="${TMPHOME}/.cache"
mkdir -p "${TMPHOME}/Documents"
echo "beacon-smoke-marker" >"${TMPHOME}/Documents/beacon-smoke-marker.txt"

rebuild_out="$(python3 "${INDEX}" rebuild)"
echo "${rebuild_out}" | python3 -c 'import json,sys
d=json.load(sys.stdin)
assert d.get("ok") is True
assert int(d.get("count") or 0) >= 1
' || die "rebuild JSON"
ok "index rebuild"

search_out="$(python3 "${INDEX}" search beacon-smoke-marker)"
echo "${search_out}" | python3 -c 'import json,sys
d=json.load(sys.stdin)
assert d.get("ok") is True
hits=d.get("hits") or []
assert any("beacon-smoke-marker" in str(h.get("name","")) for h in hits)
' || die "search JSON hits"
ok "index search"

status_out="$(python3 "${INDEX}" status)"
echo "${status_out}" | python3 -c 'import json,sys
d=json.load(sys.stdin)
assert d.get("ok") is True
assert d.get("present") is True
assert "beacon-files.json" in str(d.get("path",""))
' || die "status JSON"
ok "index status"

[[ $fail -eq 0 ]] || { echo "beacon-smoke: FAILED" >&2; exit 1; }
echo "beacon-smoke: OK"
