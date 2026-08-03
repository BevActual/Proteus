#!/usr/bin/env bash
# host-smoke — Host hard-switch Phase 1 gate (no live compositor flip)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fail=0
ok() { echo "host-smoke: OK $*"; }
die() { echo "host-smoke: FAIL $*" >&2; fail=1; }

POSTURE="${ROOT}/shell/scripts/proteus-posture"
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
[[ -x "${ROOT}/dev/dogfood/dogfood-host.sh" ]] || die "dogfood-host.sh missing/not executable"
[[ -x "${ROOT}/dev/smoke/host-guest-smoke.sh" ]] || die "host-guest-smoke.sh missing"
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
grep -q 'runPosture("host --chrome")' "${US}" || die "UniversalSearch must enter host with --chrome (seated)"
SEAT="${ROOT}/shell/scripts/proteus-host-seat"
[[ -x "${SEAT}" ]] || die "proteus-host-seat not executable"
grep -qE 'attach\|detach\|status' "${SEAT}" || die "proteus-host-seat missing attach|detach|status"
grep -q 'write_host_chrome none' "${POSTURE}" || die "proteus-posture must default host-chrome none"
grep -q 'stop_wallpaper' "${POSTURE}" || die "proteus-posture missing stop_wallpaper on headless"
grep -q 'id: "host"' "${CCL}" || die "ControlCenterLayout missing host tile"
grep -q 'id: "host"' "${QSGRID}" || die "QuickSettingsGrid missing host tile"
grep -q 'hostSurfaceActive' "${QSGRID}" || die "QuickSettingsGrid missing hostSurfaceActive gate"
# Prefer live-tree launch (not A && B & || C)
if grep -qE 'proteus-posture[^
]*&&[^
]*&[[:space:]]*\|\|' "${QSGRID}" 2>/dev/null; then
  die "QS grid host launch uses invalid bash A && B & || C"
fi
grep -q 'shell/scripts/proteus-posture' "${QSGRID}" || die "QuickSettingsGrid missing live-tree posture launch"
ok "enter/exit wires"

HOST_HOME="${ROOT}/shell/surfaces/host/HostHome.qml"
[[ -f "${HOST_HOME}" ]] || die "missing HostHome.qml"
grep -q 'HostHome' "${HSHELL}" || die "HostShell missing HostHome"
grep -q 'SystemLoad\|SystemInfo' "${HOST_HOME}" || die "HostHome missing load/info glance"
grep -q 'openSettings\|MissionCenter\|openTerminal' "${HOST_HOME}" \
  || die "HostHome missing ops quick actions"
grep -q 'StatusHud' "${HSHELL}" || die "HostShell missing StatusHud"
grep -q 'NotificationToast' "${HSHELL}" || die "HostShell missing NotificationToast"
# Home glance is a Top layer — it must yield to real app windows
# (Settings / Workloads toplevels) and the bar must reserve its strip.
grep -q 'appWindowOpen' "${HSHELL}" \
  || die "HostShell must hide Home while an app window is open (appWindowOpen)"
grep -q '&& !appWindowOpen' "${HSHELL}" \
  || die "HostShell homeWanted must gate on appWindowOpen"
grep -q 'ExclusionMode.Auto' "${HSHELL}" \
  || die "HostShell bar must reserve its strip (ExclusionMode.Auto)"
grep -q 'hostnameLabel\|SystemLoad.summaryLabel' "${HSHELL}" \
  || die "HostShell bar missing hostname/load"
grep -q 'Workloads' "${HOST_HOME}" || die "HostHome missing Workloads glance"
grep -q 'openWorkloadsApp\|openWorkloads(' "${HOST_HOME}" \
  || die "HostHome missing Workloads app handoff"
grep -q 'headless\|host-chrome\|Workloads' "${HOST_HOME}" \
  || die "HostHome must state headless / Workloads honesty"
grep -q '"Headless"' "${HOST_HOME}" || die "HostHome missing Headless quick action"
grep -q 'runHostSeat("detach")' "${HOST_HOME}" \
  || die "HostHome must use proteus-host-seat for detach"
grep -qiE 'Host Settings face|Virtualization|Settings → Virtualization|mutations in Workloads|desktop face escape' "${HOST_HOME}" \
  || die "HostHome must state Host Settings face / Virtualization honesty"
grep -q 'openSettingsSmart\|fullsettings' "${HOST_HOME}" \
  || die "HostHome must use openSettingsSmart + Full Settings escape"

# HexOS-style Command-Deck dashboard: read-only resource cards + deep links.
grep -q 'HostMetrics' "${HOST_HOME}" || die "HostHome missing HostMetrics glance"
for card in '"Processor"' '"Memory"' '"Storage"' '"Network"' '"Health"' '"Workloads"' '"Apps"' '"Shares"'; do
  grep -q "title: ${card}" "${HOST_HOME}" || die "HostHome missing ${card} card"
done
grep -q 'openWorkloads("workloads")' "${HOST_HOME}" || die "Workloads card must deep-link workloads tab"
grep -q 'openWorkloads("apps")' "${HOST_HOME}" || die "Apps card must deep-link apps tab"
grep -q 'openWorkloads("shares")' "${HOST_HOME}" || die "Shares card must deep-link shares tab"
grep -q 'component Spark' "${HOST_HOME}" || die "HostHome missing sparkline component"
# Dashboard stays mutation-free — all mutations live in the Workloads app.
if grep -qE 'Workloads\.(start|stop|kill|create|destroy|deployApp|shareAdd|shareRemove)\(' "${HOST_HOME}"; then
  die "HostHome must not mutate workloads (dashboard is read-only)"
fi
HM="${ROOT}/shell/shared/HostMetrics.qml"
HM_PY="${ROOT}/shell/scripts/proteus-host-metrics.py"
[[ -f "${HM}" ]] || die "missing HostMetrics.qml"
[[ -x "${HM_PY}" ]] || die "proteus-host-metrics.py not executable"
grep -q 'proteus-host-metrics.py' "${HM}" || die "HostMetrics.qml missing script path"
grep -q 'retain\|release' "${HM}" || die "HostMetrics.qml missing retain/release pattern"
ok "Command-Deck dashboard (cards · deep links · read-only)"
grep -q 'hostSurfaceActive' "${ROOT}/shell/shared/ShellState.qml" || die "ShellState missing hostSurfaceActive"
grep -q 'settingsFaceHostHubs\|openSettingsSmart' \
  "${ROOT}/shell/shared/EnvGate.qml" "${ROOT}/shell/shared/ShellState.qml" \
  || die "Host Settings face wiring missing"
ok "Phase 2 HostHome + HUD/toast + headless"

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
mkdir -p "${FAKE_ROOT}/shell/scripts" "${FAKE_ROOT}/install/machine" "${FAKE_ROOT}/env/hypr/profiles"
cp "${POSTURE}" "${FAKE_ROOT}/shell/scripts/proteus-posture"
cp "${ROOT}/shell/scripts/set-hypr-profile.sh" "${FAKE_ROOT}/shell/scripts/set-hypr-profile.sh"
cp "${ROOT}/shell/scripts/proteus-guide" "${FAKE_ROOT}/shell/scripts/proteus-guide"
cp "${HOST_CONF}" "${FAKE_ROOT}/env/hypr/profiles/host.conf"
printf '# stub\n' >"${FAKE_ROOT}/env/hypr/profiles/desktop.conf"
printf '# stub\n' >"${FAKE_ROOT}/env/hypr/profiles/console.conf"
cat >"${FAKE_ROOT}/shell/scripts/proteus-qs" <<'EOF'
#!/usr/bin/env bash
echo "stub proteus-qs $*" >>"${HOME}/qs-stub.log"
exit 0
EOF
chmod +x "${FAKE_ROOT}/install/machine/"* "${FAKE_ROOT}/shell/scripts/proteus-qs" 2>/dev/null || true

export PROTEUS_ROOT="${FAKE_ROOT}"
export PATH="${TMP}/bin:${FAKE_ROOT}/shell/scripts:${PATH}"

bash "${FAKE_ROOT}/shell/scripts/proteus-posture" host || true
[[ -f "${HOME}/.config/proteus/posture" ]] || die "posture Fact not written"
got="$(tr -d '[:space:]' <"${HOME}/.config/proteus/posture")"
[[ "${got}" == "host" ]] || die "expected Fact host, got '${got}'"
grep -q 'profiles/host.conf' "${HOME}/.config/hypr/proteus-profile.conf" \
  || die "hypr pointer not set to host.conf"
[[ -f "${HOME}/.config/proteus/host-chrome" ]] || die "host-chrome Fact not written on default host"
hc0="$(tr -d '[:space:]' <"${HOME}/.config/proteus/host-chrome")"
[[ "${hc0}" == "none" ]] || die "default host must be headless (host-chrome=none), got '${hc0}'"
ok "Fact write + profile pointer host + default headless"

# headless-no-QS Fact + --stop path
grep -qE -- '--stop' "${QS}" || die "proteus-qs missing --stop"
grep -q 'host-chrome\|host_chrome_mode' "${QS}" || die "proteus-qs missing host-chrome gate"
grep -qE -- '--headless' "${POSTURE}" || die "proteus-posture missing --headless"
cp "${SEAT}" "${FAKE_ROOT}/shell/scripts/proteus-host-seat"
chmod +x "${FAKE_ROOT}/shell/scripts/proteus-host-seat"
bash "${FAKE_ROOT}/shell/scripts/proteus-host-seat" status | grep -q 'host-chrome=none' \
  || die "proteus-host-seat status missing host-chrome=none"
bash "${FAKE_ROOT}/shell/scripts/proteus-posture" host --chrome || true
hc2="$(tr -d '[:space:]' <"${HOME}/.config/proteus/host-chrome")"
[[ "${hc2}" == "full" ]] || die "expected host-chrome full after --chrome, got '${hc2}'"
bash "${FAKE_ROOT}/shell/scripts/proteus-posture" host --headless || true
hc="$(tr -d '[:space:]' <"${HOME}/.config/proteus/host-chrome")"
[[ "${hc}" == "none" ]] || die "expected host-chrome none, got '${hc}'"
ok "host-chrome Fact + seat helper + --headless/--chrome"

SP="${ROOT}/apps/proteus-settings/panes/SystemPane.qml"
VP="${ROOT}/apps/proteus-settings/panes/VirtualizationPane.qml"
SET="${ROOT}/apps/proteus-settings/Settings.qml"
EG="${ROOT}/shell/shared/EnvGate.qml"
[[ -f "${VP}" ]] || die "missing VirtualizationPane.qml"
grep -q 'id: "virtualization"' "${EG}" || die "EnvGate catalog missing virtualization"
grep -q 'VirtualizationPane.qml\|page === "virtualization"' "${SET}" \
  || die "Settings must load VirtualizationPane"
grep -q 'Virtualization' "${SP}" || die "SystemPane missing Virtualization jump"
grep -q 'virtualization' "${SP}" || die "SystemPane must jump to Virtualization hub"
grep -q 'openWorkloadsApp' "${VP}" || die "VirtualizationPane must open Workloads"
grep -q 'openWorkloadsApp("apps")' "${VP}" || die "VirtualizationPane must deep-link Apps tab"
grep -q 'openWorkloadsApp("shares")' "${VP}" || die "VirtualizationPane must deep-link Shares tab"
# Bar: Workloads entry + host Settings face (not the desktop face)
grep -q 'openWorkloadsApp' "${HSHELL}" || die "HostShell bar missing Workloads link"
grep -q 'openSettingsSmart' "${HSHELL}" || die "HostShell bar Settings must open host face"
grep -q 'runHostSeat\|proteus-host-seat' "${VP}" \
  || die "VirtualizationPane missing proteus-host-seat actions"
grep -qiE 'auto-resolver|Portainer|mutations' "${VP}" \
  || die "VirtualizationPane must state mutations/auto-resolver Out"
ok "Settings Virtualization hub (thin)"

[[ $fail -eq 0 ]] || { echo "host-smoke: FAILED" >&2; exit 1; }
echo "host-smoke: OK"
