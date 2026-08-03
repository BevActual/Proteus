#!/usr/bin/env bash
# host-metrics-smoke — proteus-host-metrics.py JSON contract + HostMetrics wire
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fail=0
ok() { echo "host-metrics-smoke: OK $*"; }
die() { echo "host-metrics-smoke: FAIL $*" >&2; fail=1; }

HM_PY="${ROOT}/shell/scripts/proteus-host-metrics.py"
HM="${ROOT}/shell/shared/HostMetrics.qml"

[[ -x "${HM_PY}" ]] || die "proteus-host-metrics.py not executable"
[[ -f "${HM}" ]] || die "missing HostMetrics.qml"
python3 -m py_compile "${HM_PY}" || die "py_compile"
ok "tree + py_compile"

# Fixture JSON contract — everything the dashboard cards bind to.
PROTEUS_HOST_METRICS_FIXTURE=1 python3 "${HM_PY}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["ok"] is True and d["fixture"] is True
st = d["storage"]
assert st["drives"] and all("name" in x and "smart" in x for x in st["drives"])
assert st["mounts"] and all(
    {"target", "usedGiB", "totalGiB", "usedPct"} <= set(m) for m in st["mounts"])
assert st["pools"] and all({"name", "health", "kind"} <= set(p) for p in st["pools"])
assert isinstance(st["smartAvailable"], bool)
net = d["network"]
assert net["primary"] and net["interfaces"]
assert all({"name", "up", "rxBps", "txBps"} <= set(i) for i in net["interfaces"])
sh = d["shares"]
assert isinstance(sh["available"], bool) and isinstance(sh["smbActive"], bool)
assert all({"name", "path", "guestOk"} <= set(s) for s in sh["items"])
h = d["health"]
assert all({"severity", "message"} <= set(a) for a in h["alerts"])
assert isinstance(h["failedUnits"], int)
assert d["summary"] and isinstance(d["errors"], list)
print("fixture contract ok")
' || die "fixture contract"
ok "fixture JSON contract"

# Live run must emit valid JSON too (degrades honestly, never crashes).
PROTEUS_HOST_METRICS_SAMPLE=0.1 python3 "${HM_PY}" \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["ok"]' \
  || die "live run must emit ok JSON"
ok "live run JSON"

# Read-only: no mutation binaries in the metrics CLI.
if grep -nE 'usershare["'\'' ]*,[ ]*["'\'']add|usershare["'\'' ]*,[ ]*["'\'']delete|"rm"|"run"|virsh' "${HM_PY}" >/dev/null; then
  die "metrics CLI must stay read-only (glance data only)"
fi
ok "read-only glance"

# Singleton wire (retain/poll pattern like Workloads.qml)
grep -q 'pragma Singleton' "${HM}" || die "HostMetrics must be a singleton"
grep -q 'proteus-host-metrics.py' "${HM}" || die "HostMetrics missing script path"
grep -q 'function retain' "${HM}" || die "HostMetrics missing retain"
grep -q 'function release' "${HM}" || die "HostMetrics missing release"
grep -q 'Timer' "${HM}" || die "HostMetrics missing poll timer"
for prop in drives mounts pools netInterfaces alerts shares; do
  grep -q "property var ${prop}" "${HM}" || die "HostMetrics missing ${prop}"
done
ok "HostMetrics singleton wire"

# Install wiring
grep -q 'proteus-host-metrics.py' "${ROOT}/vm/install/apps.sh" \
  || die "apps.sh must install proteus-host-metrics.py"
grep -q 'proteus-host-metrics.py' "${ROOT}/vm/install/check.sh" \
  || die "check.sh must verify proteus-host-metrics.py"
ok "install wiring"

[[ $fail -eq 0 ]] || { echo "host-metrics-smoke: FAILED" >&2; exit 1; }
echo "host-metrics-smoke: OK"
