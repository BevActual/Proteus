#!/usr/bin/env bash
# workloads-app-smoke — Proteus Workloads app + start/stop/kill/create/destroy + HostHome wire
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fail=0
ok() { echo "workloads-app-smoke: OK $*"; }
die() { echo "workloads-app-smoke: FAIL $*" >&2; fail=1; }

APP="${ROOT}/apps/proteus-workloads"
CATALOG="${ROOT}/env/apps/catalog.json"
WL="${ROOT}/shell/shared/Workloads.qml"
WL_PY="${ROOT}/shell/scripts/proteus-workloads.py"
SS="${ROOT}/shell/shared/ShellState.qml"
INSTALL="${ROOT}/install/machine/install-workloads-app.sh"
HOST_HOME="${ROOT}/shell/surfaces/host/HostHome.qml"

[[ -d "${APP}" ]] || die "missing apps/proteus-workloads"
[[ -x "${APP}/proteus-workloads" ]] || die "launcher not executable"
[[ -f "${APP}/shell.qml" ]] || die "missing shell.qml"
[[ -f "${APP}/WorkloadsApp.qml" ]] || die "missing WorkloadsApp.qml"
[[ -f "${APP}/proteus-workloads.desktop" ]] || die "missing .desktop"
ok "app tree"

grep -q 'Proteus Workloads' "${APP}/shell.qml" || die "shell.qml title"
grep -q 'FloatingWindow' "${APP}/shell.qml" || die "shell.qml FloatingWindow"
grep -q 'Workloads\.' "${APP}/WorkloadsApp.qml" || die "WorkloadsApp must use Workloads"
grep -q 'requestAction\|runConfirm' "${APP}/WorkloadsApp.qml" \
  || die "WorkloadsApp must confirm mutations"
grep -q 'Workloads.start\|Workloads.stop' "${APP}/WorkloadsApp.qml" \
  || die "WorkloadsApp must call Workloads.start/stop"
grep -q 'Workloads.kill' "${APP}/WorkloadsApp.qml" \
  || die "WorkloadsApp must call Workloads.kill"
grep -q 'Force stop' "${APP}/WorkloadsApp.qml" \
  || die "WorkloadsApp missing Force stop UI"
grep -q 'Workloads.create\|Workloads.destroy' "${APP}/WorkloadsApp.qml" \
  || die "WorkloadsApp must call Workloads.create/destroy"
grep -q 'requestCreate\|Create…' "${APP}/WorkloadsApp.qml" \
  || die "WorkloadsApp missing Create strip"
grep -q 'start/stop/kill/create/destroy + one-click deploy + usershare add/remove In' "${APP}/WorkloadsApp.qml" \
  || die "WorkloadsApp must state kill/deploy/share In honesty"
grep -q 'Workloads\|headless\|Virtualization Settings hub' "${APP}/WorkloadsApp.qml" \
  || die "WorkloadsApp must state Settings virt jump / headless honesty"
grep -q 'quitApp\|Qt.quit' "${APP}/WorkloadsApp.qml" \
  || die "WorkloadsApp must expose quit"
grep -q 'Key_Escape\|escapeAction' "${APP}/WorkloadsApp.qml" \
  || die "WorkloadsApp must Escape to dismiss/quit"
grep -q '✕' "${APP}/WorkloadsApp.qml" || die "WorkloadsApp missing ✕ close"
grep -q 'Shortcut\|Escape' "${APP}/shell.qml" \
  || die "shell.qml must wire Escape Shortcut"
grep -q 'close_host_product_apps' "${ROOT}/shell/scripts/proteus-posture" \
  || die "proteus-posture must close host product apps when leaving host"
grep -q 'Proteus Workloads' "${ROOT}/shell/scripts/proteus-posture" \
  || die "proteus-posture must target Proteus Workloads title"
ok "app tree"

[[ -x "${INSTALL}" ]] || die "install-workloads-app.sh not executable"
grep -q 'install-workloads-app.sh' "${ROOT}/install/apps.sh" \
  || die "apps.sh must install workloads app"
grep -q 'proteus-workloads' "${CATALOG}" || die "catalog missing proteus-workloads"
grep -q '"id": "proteus-workloads"' "${CATALOG}" || die "catalog id proteus-workloads"
grep -q '"postures"' "${CATALOG}" && grep -A20 '"id": "proteus-workloads"' "${CATALOG}" \
  | grep -q 'host' \
  || die "catalog proteus-workloads needs postures host"
ok "manifest + install"

grep -q 'openWorkloadsApp' "${SS}" || die "ShellState missing openWorkloadsApp"
grep -q -- '--tab' "${SS}" || die "ShellState openWorkloadsApp missing tab deep link"
grep -q 'openWorkloadsApp' "${HOST_HOME}" || die "HostHome missing openWorkloadsApp"
grep -q 'title: "Workloads"' "${HOST_HOME}" || die "HostHome missing Workloads card"
grep -q 'Workloads\|headless\|host-chrome' "${HOST_HOME}" \
  || die "HostHome must state Workloads / headless honesty"
if grep -qE 'Workloads\.(start|stop|kill|create|destroy|deployApp|shareAdd|shareRemove)\(' "${HOST_HOME}"; then
  die "HostHome glance must stay read-only (no mutations)"
fi
ok "HostHome + ShellState wire"

# Tabs: Workloads · Apps · Shares (single mutation surface, HexOS-style)
grep -q 'currentTab' "${APP}/WorkloadsApp.qml" || die "WorkloadsApp missing currentTab"
grep -q 'function openTab' "${APP}/WorkloadsApp.qml" || die "WorkloadsApp missing openTab"
grep -q '"workloads", "apps", "shares"' "${APP}/WorkloadsApp.qml" \
  || die "WorkloadsApp missing tab set"
grep -q 'openTab' "${APP}/shell.qml" || die "shell.qml IPC missing openTab"
grep -q -- '--tab' "${APP}/proteus-workloads" || die "launcher missing --tab deep link"
grep -q 'PROTEUS_WORKLOADS_TAB' "${APP}/proteus-workloads" \
  || die "launcher missing PROTEUS_WORKLOADS_TAB for fresh launch"
grep -q 'Workloads.deployApp' "${APP}/WorkloadsApp.qml" || die "Apps tab must deploy via singleton"
grep -q 'Workloads.shareAdd' "${APP}/WorkloadsApp.qml" || die "Shares tab must shareAdd via singleton"
grep -q 'Workloads.shareRemove' "${APP}/WorkloadsApp.qml" || die "Shares tab must shareRemove via singleton"
grep -q 'Install samba' "${APP}/WorkloadsApp.qml" \
  || die "Shares tab must gate honestly when samba missing"
grep -q 'podman / docker not available' "${APP}/WorkloadsApp.qml" \
  || die "Apps tab must gate honestly when engine missing"
ok "tabs (Workloads · Apps · Shares) + honest gates"

# One-click catalog schema
HOST_APPS="${ROOT}/env/apps/host-apps.json"
[[ -f "${HOST_APPS}" ]] || die "missing env/apps/host-apps.json"
python3 - "${HOST_APPS}" <<'PY' || die "host-apps catalog schema"
import json, re, sys
data = json.load(open(sys.argv[1]))
apps = data.get("apps")
assert isinstance(apps, list) and len(apps) >= 4, "need a curated catalog"
for a in apps:
    assert re.match(r"^[a-z0-9][a-z0-9-]*$", a["id"]), a
    assert a["name"] and a["blurb"] and a["image"], a
    assert isinstance(a["ports"], list) and all(
        re.match(r"^\d{1,5}:\d{1,5}$", p) for p in a["ports"]), a
    assert isinstance(a["volumes"], list) and all(
        v["name"] and str(v["path"]).startswith("/") for v in a["volumes"]), a
    assert isinstance(a.get("webPort"), int), a
print("catalog ok")
PY
ok "host-apps.json catalog schema"

grep -q 'function start\|function stop\|_mutate' "${WL}" \
  || die "Workloads.qml missing start/stop API"
grep -q 'function kill' "${WL}" || die "Workloads.qml missing kill API"
grep -q 'function create\|function destroy' "${WL}" \
  || die "Workloads.qml missing create/destroy API"
grep -q 'mutating' "${WL}" || die "Workloads.qml missing mutating flag"
ok "Workloads singleton mutate API"

[[ -x "${WL_PY}" ]] || die "proteus-workloads.py not executable"
bash -n "${WL_PY}" 2>/dev/null || python3 -m py_compile "${WL_PY}" || die "WL_PY syntax"

dry="$(PROTEUS_WORKLOADS_FIXTURE=1 python3 "${WL_PY}" start --kind vm --name proteus-guest --dry-run)"
echo "${dry}" | grep -q '"ok":true' || die "fixture start dry-run not ok: ${dry}"
echo "${dry}" | grep -qE '"dryRun":true|"fixture":true' \
  || die "fixture start missing dryRun/fixture"
stop_out="$(PROTEUS_WORKLOADS_FIXTURE=1 python3 "${WL_PY}" stop --kind container --name registry --dry-run)"
echo "${stop_out}" | grep -q '"ok":true' || die "fixture stop dry-run not ok"
kill_vm="$(PROTEUS_WORKLOADS_FIXTURE=1 python3 "${WL_PY}" kill --kind vm --name proteus-guest --dry-run)"
echo "${kill_vm}" | grep -q '"ok":true' || die "fixture kill vm not ok: ${kill_vm}"
echo "${kill_vm}" | grep -q '"action":"kill"' || die "fixture kill missing action"
kill_ct="$(PROTEUS_WORKLOADS_FIXTURE=1 python3 "${WL_PY}" kill --kind container --name registry --dry-run)"
echo "${kill_ct}" | grep -q '"ok":true' || die "fixture kill container not ok"
create_vm="$(PROTEUS_WORKLOADS_FIXTURE=1 python3 "${WL_PY}" create --kind vm --name new-box --disk /tmp/x.qcow2 --dry-run)"
echo "${create_vm}" | grep -q '"ok":true' || die "fixture create vm not ok: ${create_vm}"
create_ct="$(PROTEUS_WORKLOADS_FIXTURE=1 python3 "${WL_PY}" create --kind container --name c1 --image alpine:latest --dry-run)"
echo "${create_ct}" | grep -q '"ok":true' || die "fixture create container not ok"
destroy_out="$(PROTEUS_WORKLOADS_FIXTURE=1 python3 "${WL_PY}" destroy --kind vm --name idle-box --dry-run)"
echo "${destroy_out}" | grep -q '"ok":true' || die "fixture destroy not ok"

# Kill In (virsh destroy / engine kill); ban rm -f / kill -9 / timed hard-stop.
python3 - "${WL_PY}" <<'PY' || die "kill argv scan"
import pathlib, re, sys
src = pathlib.Path(sys.argv[1]).read_text()
code = "\n".join(ln for ln in src.splitlines() if not ln.lstrip().startswith("#"))
if "action == \"kill\"" not in code and "action == 'kill'" not in code:
    raise SystemExit("missing kill action branch")
if 'sub = "destroy"' not in code and "sub = 'destroy'" not in code:
    if not re.search(r'virsh_cmd\([^)]*["\']destroy["\']', code):
        raise SystemExit("missing virsh destroy for kill")
if 'eng_action = "kill"' not in code and "eng_action = 'kill'" not in code:
    raise SystemExit("missing engine kill")
if re.search(r'\[\s*tool\s*,\s*["\']rm["\']\s*,\s*["\']-f["\']', code):
    raise SystemExit("rm -f argv")
for tok in ("kill -9", "--time 0", "stop -t 0"):
    if tok in code:
        raise SystemExit(tok)
if "undefine" not in code:
    raise SystemExit("missing undefine")
if '[tool, "rm", name]' not in code:
    raise SystemExit("missing engine rm")
if "shutdown" not in code:
    raise SystemExit("missing shutdown")
if '"kill", "create", "destroy"' not in code and '"kill"' not in code:
    raise SystemExit("missing kill choices")
print("kill argv ok")
PY
ok "start/stop/kill/create/destroy fixture + kill argv"

# Deploy + shares fixtures
dep="$(PROTEUS_WORKLOADS_FIXTURE=1 python3 "${WL_PY}" deploy --app jellyfin --dry-run)"
echo "${dep}" | grep -q '"ok":true' || die "fixture deploy not ok: ${dep}"
echo "${dep}" | grep -q '"action":"deploy"' || die "fixture deploy missing action"
bad_dep="$(PROTEUS_WORKLOADS_FIXTURE=1 python3 "${WL_PY}" deploy --app 'no;such' --dry-run || true)"
echo "${bad_dep}" | grep -q '"ok":false' || die "deploy must reject bad app id"
apps_out="$(PROTEUS_WORKLOADS_FIXTURE=1 python3 "${WL_PY}" apps)"
echo "${apps_out}" | grep -q '"ok":true' || die "apps fixture not ok"
echo "${apps_out}" | grep -q 'proteus-app-' || die "apps fixture missing container names"
sh_add="$(PROTEUS_WORKLOADS_FIXTURE=1 python3 "${WL_PY}" share-add --name media --path /tmp --dry-run)"
echo "${sh_add}" | grep -q '"ok":true' || die "fixture share-add not ok"
sh_rm="$(PROTEUS_WORKLOADS_FIXTURE=1 python3 "${WL_PY}" share-remove --name media --dry-run)"
echo "${sh_rm}" | grep -q '"ok":true' || die "fixture share-remove not ok"
sh_ls="$(PROTEUS_WORKLOADS_FIXTURE=1 python3 "${WL_PY}" shares)"
echo "${sh_ls}" | grep -q '"available":true' || die "shares fixture not ok"
bad_share="$(PROTEUS_WORKLOADS_FIXTURE=1 python3 "${WL_PY}" share-add --name 'x;y' --path /tmp || true)"
echo "${bad_share}" | grep -q '"ok":false' || die "share-add must reject bad name"

# Deploy argv scan: no privileged / host-net / rm -f deploys; volumes stay
# under the per-app data root; usershares via net usershare only.
python3 - "${WL_PY}" <<'PY' || die "deploy/shares argv scan"
import pathlib, sys
src = pathlib.Path(sys.argv[1]).read_text()
code = "\n".join(ln for ln in src.splitlines() if not ln.lstrip().startswith("#"))
for banned in ("--privileged", "--network=host", '"--net", "host"', "cap-add"):
    if banned in code:
        raise SystemExit(f"banned deploy flag: {banned}")
assert '"--restart", "unless-stopped"' in code, "deploy must restart unless-stopped"
assert '_APP_PREFIX = "proteus-app-"' in code, "deploy must namespace containers"
assert '".local" / "share" / "proteus" / "apps"' in code, "volumes must live under proteus data root"
assert '"usershare", "add"' in code, "share-add must use net usershare add"
assert '"usershare", "delete"' in code, "share-remove must use net usershare delete"
assert "guest_ok=y" in code, "usershare add must be guest-readable"
print("deploy/shares argv ok")
PY
ok "deploy + shares fixtures + argv bans"

[[ $fail -eq 0 ]] || { echo "workloads-app-smoke: FAILED" >&2; exit 1; }
echo "workloads-app-smoke: OK"
