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
grep -qiE 'ACL|preauth|server install Out' "${LEAF}" \
  || die "leaf must keep ACL/preauth/server install Out honesty"
grep -qiE 'Headscale admin → Network → Headscale|Cert wizard Out' "${VPN}" \
  || die "VPN leaf must point Headscale admin to Network → Headscale"
ok "wiring"

grep -q 'def cmd_nodes\|def cmd_expire\|/api/v1/node\|set-key' "${SCRIPT}" \
  || die "script missing API surface"
grep -q 'PROTEUS_HEADSCALE_FIXTURE' "${SCRIPT}" || die "script missing fixture mode"
grep -q 'proteus-headscale.py' "${ROOT}/vm/install/apps.sh" \
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
ok "fixtures"

[[ $fail -eq 0 ]] || { echo "headscale-admin-smoke: FAILED" >&2; exit 1; }
echo "headscale-admin-smoke: OK"
