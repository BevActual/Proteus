#!/usr/bin/env bash
# headscale-admin-smoke — Headscale remote admin leaf + script wiring (host static)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fail=0
ok() { echo "headscale-admin-smoke: OK $*"; }
die() { echo "headscale-admin-smoke: FAIL $*" >&2; fail=1; }

LEAF="${ROOT}/apps/proteus-settings/panes/NetworkHeadscaleLeaf.qml"
PANE="${ROOT}/apps/proteus-settings/panes/NetworkPane.qml"
SCRIPT="${ROOT}/shell/scripts/proteus-headscale.py"
CFG="${ROOT}/shell/shared/Config.qml"
SETTINGS="${ROOT}/apps/proteus-settings/Settings.qml"
ENVGATE="${ROOT}/shell/shared/EnvGate.qml"
VPN="${ROOT}/apps/proteus-settings/panes/NetworkVpnLeaf.qml"

for f in "${LEAF}" "${PANE}" "${SCRIPT}" "${CFG}" "${SETTINGS}" "${ENVGATE}"; do
  [[ -f "${f}" ]] || die "missing ${f#${ROOT}/}"
done
[[ -x "${SCRIPT}" ]] || die "proteus-headscale.py not executable"
ok "files present"

grep -q 'network-headscale' "${PANE}" || die "NetworkPane missing headscale section"
grep -q 'NetworkHeadscaleLeaf' "${PANE}" || die "NetworkPane missing Headscale loader"
grep -q 'network-headscale' "${SETTINGS}" || die "Settings.qml missing network-headscale child"
grep -q 'network-headscale' "${ENVGATE}" || die "EnvGate missing network-headscale"
grep -q 'headscaleAdminUrl' "${CFG}" || die "Config missing headscaleAdminUrl"
grep -q 'openHeadscaleAdmin' "${CFG}" || die "Config missing openHeadscaleAdmin"
grep -q 'proteus-headscale.py' "${LEAF}" || die "leaf missing script path"
grep -q 'expireNode\|enableNode\|Save API key\|vault' "${LEAF}" \
  || die "leaf missing admin actions"
grep -q 'createUser\|Users\|user-create' "${LEAF}" \
  || die "leaf missing Users group"
grep -q 'checkPolicy\|savePolicy\|Policy\|policy-set' "${LEAF}" \
  || die "leaf missing Policy group"
grep -qiE 'preauth|structured ACL|server install Out' "${LEAF}" \
  || die "leaf must keep preauth/structured ACL/server install Out honesty"
grep -qiE 'Headscale admin → Network → Headscale|Cert wizard Out' "${VPN}" \
  || die "VPN leaf must point Headscale admin to Network → Headscale"
ok "wiring"

grep -q 'def cmd_nodes\|def cmd_expire\|/api/v1/node\|set-key' "${SCRIPT}" \
  || die "script missing API surface"
grep -q 'def cmd_users\|def cmd_user_create\|def cmd_policy\|policy-check\|policy-set' "${SCRIPT}" \
  || die "script missing users/policy API surface"
grep -q 'PROTEUS_HEADSCALE_FIXTURE' "${SCRIPT}" || die "script missing fixture mode"
grep -q 'proteus-headscale.py' "${ROOT}/install/apps.sh" \
  || die "apps.sh must install proteus-headscale.py"
ok "script + install"

PROTEUS_HEADSCALE_FIXTURE=1 python3 "${SCRIPT}" status | python3 -c 'import json,sys
d=json.load(sys.stdin)
assert d.get("ok") is True and d.get("hasKey") is True
assert int(d.get("nodeCount") or 0) >= 1
' || die "status fixture"
PROTEUS_HEADSCALE_FIXTURE=1 python3 "${SCRIPT}" nodes | python3 -c 'import json,sys
d=json.load(sys.stdin)
assert d.get("ok") is True and len(d.get("nodes") or []) >= 1
' || die "nodes fixture"
PROTEUS_HEADSCALE_FIXTURE=1 python3 "${SCRIPT}" expire 1 | python3 -c 'import json,sys
d=json.load(sys.stdin)
assert d.get("ok") is True and d.get("action")=="expire"
' || die "expire fixture"
PROTEUS_HEADSCALE_FIXTURE=1 python3 "${SCRIPT}" enable 1 | python3 -c 'import json,sys
d=json.load(sys.stdin)
assert d.get("ok") is True and d.get("action")=="enable"
' || die "enable fixture"
PROTEUS_HEADSCALE_FIXTURE=1 python3 "${SCRIPT}" users | python3 -c 'import json,sys
d=json.load(sys.stdin)
assert d.get("ok") is True and len(d.get("users") or []) >= 1
assert d["users"][0].get("name")
' || die "users fixture"
PROTEUS_HEADSCALE_FIXTURE=1 python3 "${SCRIPT}" user-create smokeuser | python3 -c 'import json,sys
d=json.load(sys.stdin)
assert d.get("ok") is True and d.get("action")=="user-create"
assert (d.get("user") or {}).get("name")=="smokeuser"
' || die "user-create fixture"
PROTEUS_HEADSCALE_FIXTURE=1 python3 "${SCRIPT}" policy | python3 -c 'import json,sys
d=json.load(sys.stdin)
assert d.get("ok") is True and "acls" in (d.get("policy") or "")
assert d.get("writable") is True
' || die "policy fixture"
printf '%s' '{"acls":[]}' | PROTEUS_HEADSCALE_FIXTURE=1 python3 "${SCRIPT}" policy-check | python3 -c 'import json,sys
d=json.load(sys.stdin)
assert d.get("ok") is True and d.get("action")=="policy-check"
' || die "policy-check fixture"
printf '%s' '{"acls":[]}' | PROTEUS_HEADSCALE_FIXTURE=1 python3 "${SCRIPT}" policy-set | python3 -c 'import json,sys
d=json.load(sys.stdin)
assert d.get("ok") is True and d.get("action")=="policy-set"
' || die "policy-set fixture"
ok "fixtures"

[[ $fail -eq 0 ]] || { echo "headscale-admin-smoke: FAILED" >&2; exit 1; }
echo "headscale-admin-smoke: OK"
