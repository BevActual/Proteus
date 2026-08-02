#!/usr/bin/env bash
# host-smoke — Host hard-switch Phase 1 gate (no live compositor flip)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fail=0
ok() { echo "host-smoke: OK $*"; }
die() { echo "host-smoke: FAIL $*" >&2; fail=1; }

POSTURE="${ROOT}/vm/guest/proteus-posture"
QS="${ROOT}/shell/scripts/proteus-qs"
HOST_CONF="${ROOT}/env/hypr/profiles/host.conf"
HSHELL="${ROOT}/shell/surfaces/HostShell.qml"
SHELLQML="${ROOT}/shell/shell.qml"
US="${ROOT}/shell/shared/UniversalSearch.qml"
CCL="${ROOT}/shell/shared/ControlCenterLayout.qml"
QSGRID="${ROOT}/shell/surfaces/desktop/QuickSettingsGrid.qml"
SS="${ROOT}/shell/shared/ShellState.qml"

[[ -x "${POSTURE}" ]] || die "proteus-posture not executable"
[[ -x "${QS}" ]] || die "proteus-qs not executable"
[[ -f "${HOST_CONF}" ]] || die "missing env/hypr/profiles/host.conf"
[[ -f "${HSHELL}" ]] || die "missing HostShell.qml"
ok "helpers + HostShell + host.conf"

grep -q 'desktop|console|host' "${POSTURE}" \
  || grep -qE 'host' "${POSTURE}" \
  || die "proteus-posture must accept host"
grep -q 'host)' "${POSTURE}" || die "proteus-posture missing host) case"
grep -q 'HostShell' "${SHELLQML}" || die "shell.qml missing HostShell"
grep -q 'case "host"' "${SHELLQML}" || die "shell.qml missing host surface case"
grep -q 'host|phone' "${QS}" || grep -q '|host|' "${QS}" \
  || die "proteus-qs must allowlist host surface"
grep -q 'hostSurfaceActive' "${SS}" || die "ShellState missing hostSurfaceActive"
ok "loader + Fact surface allowlist"

grep -q 'enter-host' "${US}" || die "UniversalSearch missing enter-host"
grep -q 'runPosture("host")' "${US}" || die "UniversalSearch missing runPosture host"
grep -q 'id: "host"' "${CCL}" || die "ControlCenterLayout missing host tile"
grep -q 'id: "host"' "${QSGRID}" || die "QuickSettingsGrid missing host tile"
grep -q 'hostSurfaceActive' "${QSGRID}" || die "QuickSettingsGrid missing hostSurfaceActive gate"
# Prefer live-tree launch (not A && B & || C)
if grep -qE 'proteus-posture[^
]*&&[^
]*&[[:space:]]*\|\|' "${QSGRID}" 2>/dev/null; then
  die "QS grid host launch uses invalid bash A && B & || C"
fi
grep -q 'vm/guest/proteus-posture' "${QSGRID}" || die "QuickSettingsGrid missing live-tree posture launch"
ok "enter/exit wires"

HOST_HOME="${ROOT}/shell/surfaces/host/HostHome.qml"
[[ -f "${HOST_HOME}" ]] || die "missing HostHome.qml"
grep -q 'HostHome' "${HSHELL}" || die "HostShell missing HostHome"
grep -q 'SystemLoad\|SystemInfo' "${HOST_HOME}" || die "HostHome missing load/info glance"
grep -q 'openSettings\|MissionCenter\|openTerminal' "${HOST_HOME}" \
  || die "HostHome missing ops quick actions"
grep -q 'StatusHud' "${HSHELL}" || die "HostShell missing StatusHud"
grep -q 'NotificationToast' "${HSHELL}" || die "HostShell missing NotificationToast"
grep -q 'hostnameLabel\|SystemLoad.summaryLabel' "${HSHELL}" \
  || die "HostShell bar missing hostname/load"
grep -q 'Workloads' "${HOST_HOME}" || die "HostHome missing Workloads glance"
grep -q 'headless-no-QS\|full Host workloads' "${HOST_HOME}" \
  || die "HostHome must state full workloads/headless Out honesty"
ok "Phase 2 HostHome + HUD/toast"

WL="${ROOT}/shell/shared/Workloads.qml"
WL_PY="${ROOT}/shell/scripts/proteus-workloads.py"
[[ -f "${WL}" ]] || die "missing Workloads.qml"
[[ -x "${WL_PY}" ]] || die "proteus-workloads.py not executable"
grep -q 'proteus-workloads.py' "${WL}" || die "Workloads.qml missing script path"
wl_out="$(PROTEUS_WORKLOADS_FIXTURE=1 python3 "${WL_PY}")"
echo "${wl_out}" | grep -q '"ok":true' || die "workloads fixture not ok: ${wl_out}"
echo "${wl_out}" | grep -q 'proteus-guest' || die "workloads fixture missing sample VM"
echo "${wl_out}" | grep -q '"fixture":true' || die "workloads fixture flag missing"
ok "Workloads singleton + fixture probe"

# Isolated Fact write host (stub qs + hyprctl)
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
export HOME="${TMP}"
unset XDG_CONFIG_HOME || true
export XDG_RUNTIME_DIR="${TMP}/run"
mkdir -p "${HOME}/.config/proteus" "${HOME}/.config/hypr/profiles" "${XDG_RUNTIME_DIR}" "${TMP}/bin"

cat >"${TMP}/bin/hyprctl" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "${TMP}/bin/hyprctl"

FAKE_ROOT="${TMP}/proteus"
mkdir -p "${FAKE_ROOT}/shell/scripts" "${FAKE_ROOT}/vm/guest" "${FAKE_ROOT}/env/hypr/profiles"
cp "${POSTURE}" "${FAKE_ROOT}/vm/guest/proteus-posture"
cp "${ROOT}/vm/guest/set-hypr-profile.sh" "${FAKE_ROOT}/vm/guest/set-hypr-profile.sh"
cp "${ROOT}/vm/guest/proteus-guide" "${FAKE_ROOT}/vm/guest/proteus-guide"
cp "${HOST_CONF}" "${FAKE_ROOT}/env/hypr/profiles/host.conf"
printf '# stub\n' >"${FAKE_ROOT}/env/hypr/profiles/desktop.conf"
printf '# stub\n' >"${FAKE_ROOT}/env/hypr/profiles/console.conf"
cat >"${FAKE_ROOT}/shell/scripts/proteus-qs" <<'EOF'
#!/usr/bin/env bash
echo "stub proteus-qs $*" >>"${HOME}/qs-stub.log"
exit 0
EOF
chmod +x "${FAKE_ROOT}/vm/guest/"* "${FAKE_ROOT}/shell/scripts/proteus-qs" 2>/dev/null || true

export PROTEUS_ROOT="${FAKE_ROOT}"
export PATH="${TMP}/bin:${FAKE_ROOT}/shell/scripts:${PATH}"

bash "${FAKE_ROOT}/vm/guest/proteus-posture" host || true
[[ -f "${HOME}/.config/proteus/posture" ]] || die "posture Fact not written"
got="$(tr -d '[:space:]' <"${HOME}/.config/proteus/posture")"
[[ "${got}" == "host" ]] || die "expected Fact host, got '${got}'"
grep -q 'profiles/host.conf' "${HOME}/.config/hypr/proteus-profile.conf" \
  || die "hypr pointer not set to host.conf"
ok "Fact write + profile pointer host"

[[ $fail -eq 0 ]] || { echo "host-smoke: FAILED" >&2; exit 1; }
echo "host-smoke: OK"
