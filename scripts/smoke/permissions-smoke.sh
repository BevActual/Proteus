#!/usr/bin/env bash
# permissions-smoke — permissions.json store + helpers + Privacy wiring
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fail=0
ok() { echo "permissions-smoke: OK $*"; }
die() { echo "permissions-smoke: FAIL $*" >&2; fail=1; }

HELPER="${ROOT}/shell/scripts/proteus-permissions.py"
PROBE="${ROOT}/shell/scripts/privacy-indicators.py"
PERM_QML="${ROOT}/shell/shared/Permissions.qml"
PRIV_PANE="${ROOT}/apps/proteus-settings/panes/PrivacyPane.qml"
CAT_LEAF="${ROOT}/apps/proteus-settings/panes/PrivacyCategoryLeaf.qml"
ACT_LEAF="${ROOT}/apps/proteus-settings/panes/PrivacyActivityLeaf.qml"
FP_LEAF="${ROOT}/apps/proteus-settings/panes/PrivacyFlatpakLeaf.qml"
SCHEMA="${ROOT}/docs/proteus/CONFIG-SCHEMA.md"

[[ -x "${HELPER}" ]] || die "proteus-permissions.py not executable"
[[ -x "${PROBE}" ]] || die "privacy-indicators.py not executable"
[[ -f "${PERM_QML}" ]] || die "missing Permissions.qml"
[[ -f "${PRIV_PANE}" ]] || die "missing PrivacyPane.qml"
[[ -f "${CAT_LEAF}" ]] || die "missing PrivacyCategoryLeaf.qml"
[[ -f "${ACT_LEAF}" ]] || die "missing PrivacyActivityLeaf.qml"
[[ -f "${FP_LEAF}" ]] || die "missing PrivacyFlatpakLeaf.qml"
ok "files present"

grep -q 'permissions.json' "${PERM_QML}" || die "Permissions.qml must cite permissions.json"
grep -q 'privacy-microphone\|PrivacyCategoryLeaf' "${PRIV_PANE}" || die "PrivacyPane must hub into category leaves"
grep -q 'SettingsCombo\|SettingsSegmented' "${CAT_LEAF}" || die "category leaf must use Settings kit pickers"

# Store must not live in settings.json schema keys
if grep -qiE 'permissionGrants|privacyMicEnabled|permissions\.json' "${SCHEMA}" 2>/dev/null; then
  # Allow a documentation mention of the separate file, but not as a settings.json key row
  if grep -qiE '^\|[^|]*permission' "${SCHEMA}" 2>/dev/null; then
    die "CONFIG-SCHEMA must not put permission grants in settings.json key table"
  fi
fi
ok "schema keeps grants out of settings.json keys"

TMPHOME="$(mktemp -d)"
trap 'rm -rf "${TMPHOME}"' EXIT
export HOME="${TMPHOME}"

st="$(python3 "${HELPER}" store-get)"
echo "${st}" | grep -q '"ok": true' || die "store-get ok"
echo "${st}" | grep -q '"microphone": "allow"' || die "default microphone allow"
ok "store-get defaults"

python3 "${HELPER}" store-set-category microphone deny >/dev/null
python3 "${HELPER}" store-set-app org.gnome.Snapshot camera deny >/dev/null
python3 "${HELPER}" store-set-app firefox microphone ask >/dev/null

# Reload via store-get must reflect mutators (not stale defaults).
reload="$(python3 "${HELPER}" store-get)"
echo "${reload}" | python3 -c 'import json,sys
d=json.load(sys.stdin)
assert d.get("ok") is True
assert d.get("categories",{}).get("microphone")=="deny"
apps=d.get("apps") or {}
assert (apps.get("org.gnome.Snapshot") or {}).get("camera")=="deny"
assert (apps.get("firefox") or {}).get("microphone")=="ask"
' || die "store-get reload after store-set-*"
ok "store-get reload"

g1="$(python3 "${HELPER}" granted org.gnome.Snapshot camera)"
echo "${g1}" | grep -q '"granted": false' || die "snapshot camera deny → not granted"
g2="$(python3 "${HELPER}" granted firefox microphone)"
echo "${g2}" | grep -q '"granted": false' || die "ask → not granted for adaptive"
g3="$(python3 "${HELPER}" granted otherapp camera)"
echo "${g3}" | grep -q '"granted": true' || die "fallback category allow → granted"
ok "granted semantics"

[[ -f "${HOME}/.config/proteus/permissions.json" ]] || die "permissions.json written"
mode="$(stat -c '%a' "${HOME}/.config/proteus/permissions.json" 2>/dev/null || stat -f '%Lp' "${HOME}/.config/proteus/permissions.json")"
[[ "${mode}" == "600" ]] || die "permissions.json mode ${mode} (want 600)"
ok "store mode 600"

act="$(python3 "${PROBE}")"
echo "${act}" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert "mic" in d and "apps" in d and isinstance(d["apps"], list)' \
  || die "privacy-indicators apps array"
ok "activity probe shape"

fp="$(python3 "${HELPER}" flatpak-list)"
echo "${fp}" | grep -q '"ok": true' || die "flatpak-list ok"
ok "flatpak-list"

# flatpak-set always persists store; Flatpak override applied only when flatpak exists.
# Use a synthetic ref so we never touch a real install; SKIP override assert if no flatpak.
fp_set="$(python3 "${HELPER}" flatpak-set org.proteus.SmokeProbe camera deny 2>/dev/null || true)"
if echo "${fp_set}" | grep -q '"ok": true'; then
  fp_reload="$(python3 "${HELPER}" store-get)"
  echo "${fp_reload}" | python3 -c 'import json,sys
d=json.load(sys.stdin)
apps=d.get("apps") or {}
assert (apps.get("org.proteus.SmokeProbe") or {}).get("camera")=="deny"
' || die "flatpak-set store persist"
  ok "flatpak-set store round-trip"
elif ! command -v flatpak >/dev/null 2>&1; then
  # Helper returns ok:false when flatpak missing — still require store-only path documented.
  python3 "${HELPER}" store-set-app org.proteus.SmokeProbe camera deny >/dev/null
  echo "$(python3 "${HELPER}" store-get)" | grep -q 'org.proteus.SmokeProbe' \
    || die "store-set-app fallback when flatpak absent"
  ok "flatpak-set SKIP (no flatpak; store-set-app covered)"
else
  die "flatpak-set failed unexpectedly: ${fp_set}"
fi

# Manifest permissions field accepted
"${ROOT}/scripts/smoke/app-manifest-smoke.sh" >/dev/null || die "app-manifest-smoke"
ok "app-manifest with permissions"

grep -q 'permissionDeniedReason\|Permissions.granted' "${ROOT}/shell/shared/EnvGate.qml" \
  || die "EnvGate must honor Permissions.granted"
grep -q 'isAsk\|appPrivacyAskCategory' "${ROOT}/shell/shared/EnvGate.qml" \
  || die "EnvGate must distinguish Ask vs Deny"
grep -q 'function isAsk\|grantSession' "${ROOT}/shell/shared/Permissions.qml" \
  || die "Permissions must expose isAsk + session once-grant"
grep -q 'Fail-closed until ready\|fail-closed until ready' "${ROOT}/shell/shared/Permissions.qml" \
  || die "Permissions.granted must fail-closed until ready"
grep -q 'Permissions loading\|Fail-closed until Permissions' "${ROOT}/shell/shared/EnvGate.qml" \
  || die "EnvGate must block privacy-gated apps while Permissions not ready"
grep -q 'diagnosticsAllowed: root.ready\|ready && categoryState("diagnostics")' \
  "${ROOT}/shell/shared/Permissions.qml" \
  || die "diagnosticsAllowed must fail-closed until ready"
grep -q 'fail-closed until Permissions\|return false' "${ROOT}/shell/shared/NetworkDiagnostics.qml" \
  || die "NetworkDiagnostics must fail-closed when Permissions missing/not ready"
grep -q 'fail-closed until Permissions.ready' "${PRIV_PANE}" \
  || die "PrivacyPane honesty must say fail-closed"
ok "EnvGate grant gate + fail-closed"

DOCK="${ROOT}/shell/shared/DockApps.qml"
ASK="${ROOT}/shell/shared/PrivacyAsk.qml"
ASK_PANEL="${ROOT}/shell/surfaces/desktop/PrivacyAskPanel.qml"
BEACON="${ROOT}/shell/surfaces/desktop/Beacon.qml"
[[ -f "${ASK}" ]] || die "missing PrivacyAsk.qml"
[[ -f "${ASK_PANEL}" ]] || die "missing PrivacyAskPanel.qml"
grep -q 'appPrivacyAskCategory\|PrivacyAsk.promptLaunch' "${DOCK}" \
  || die "DockApps must prompt on Ask"
grep -q 'appPrivacyBlockPane' "${DOCK}" \
  || die "DockApps must open Privacy leaf via appPrivacyBlockPane on Deny"
grep -q 'PrivacyAsk.promptLaunch\|appPrivacyAskCategory' "${BEACON}" \
  || die "Beacon must prompt on Ask"
grep -q 'function promptCapture\|promptCapture' "${ASK}" \
  || die "PrivacyAsk must expose promptCapture for mid-session"
grep -q 'mode === "capture"\|isCapture\|mid-session' "${ASK}" \
  || die "PrivacyAsk must distinguish capture mode"
grep -q 'promptCapture\|maybePromptCapture' "${ROOT}/shell/shared/PrivacyIndicators.qml" \
  || die "PrivacyIndicators must trigger mid-session Ask"
grep -q 'kind !== "camera" && kind !== "screen"\|kind !== "screen"' \
  "${ROOT}/shell/shared/PrivacyIndicators.qml" \
  || die "PrivacyIndicators mid-session Ask must include screen"
grep -q 'cat !== "camera" && cat !== "screen"\|cat !== "screen"' "${ASK}" \
  || die "PrivacyAsk.promptCapture must accept screen"
grep -q 'mic/camera/screen' "${ASK}" \
  || die "PrivacyAsk honesty must mention mic/camera/screen mid-session"
grep -q 'PrivacyAsk.visible' "${ROOT}/shell/shared/PrivacyIndicators.qml" \
  || die "PrivacyIndicators must pause enforce while Ask open"
grep -q 'syncSessionFile\|permissions-session.json' "${ROOT}/shell/shared/Permissions.qml" \
  || die "Permissions must sync session file for enforce"
grep -q 'load_session_allows\|session_path\|permissions-session' "${HELPER}" \
  || die "proteus-permissions must honor session Allow-once file"
grep -q 'Allow once\|Always Allow' "${ASK_PANEL}" \
  || die "PrivacyAskPanel missing Allow once / Always Allow"
grep -q 'isCapture\|is using' "${ASK_PANEL}" \
  || die "PrivacyAskPanel must adapt copy for mid-session"
grep -q 'PrivacyAsk' "${ROOT}/shell/surfaces/DesktopShell.qml" \
  || die "DesktopShell must host PrivacyAskPanel"
ok "Ask prompt + Dock/Beacon + mid-session intercept"

ND="${ROOT}/shell/shared/NetworkDiagnostics.qml"
ND_LEAF="${ROOT}/apps/proteus-settings/panes/NetworkDiagnosticsLeaf.qml"
grep -q 'diagnosticsAllowed\|Permissions.diagnosticsAllowed\|\.allowed' "${ND}" \
  || die "NetworkDiagnostics must honor Permissions.diagnosticsAllowed"
grep -q 'denyHint\|Diagnostics blocked' "${ND_LEAF}" \
  || die "NetworkDiagnosticsLeaf must show Privacy deny honesty"
ok "Diagnostics category gate"

grep -q 'proteus-permissions.py' "${ROOT}/vm/install/apps.sh" \
  || die "apps.sh must install proteus-permissions.py"
grep -q 'privacy-indicators.py' "${ROOT}/vm/install/apps.sh" \
  || die "apps.sh must install privacy-indicators.py"
ok "apps.sh privacy helpers"

# EnvGate catalog must not mark CURRENT-shipped categories as partial
# (Privacy + Online accounts may stay partial).
python3 - <<'PY' "${ROOT}/shell/shared/EnvGate.qml" || die "EnvGate settingsCatalog vs CURRENT shipped"
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
# crude extract of id/status pairs in settingsCatalog block
block = text.split("settingsCatalog:", 1)[1].split("settingsSearchIndex:", 1)[0]
ids = re.findall(r'id:\s*"([^"]+)"', block)
statuses = re.findall(r'status:\s*"([^"]+)"', block)
assert len(ids) == len(statuses), (ids, statuses)
m = dict(zip(ids, statuses))
shipped = {
    "style", "desktop", "displays", "sound", "network", "peripherals",
    "power", "users", "datetime", "notifications", "packages",
    "virtualization", "system",
}
partial_ok = {"privacy", "accounts"}
for i in shipped:
    assert m.get(i) == "shipped", f"{i} want shipped got {m.get(i)}"
for i in partial_ok:
    assert m.get(i) == "partial", f"{i} want partial got {m.get(i)}"
print("catalog ok")
PY
ok "EnvGate catalog vs CURRENT"

# Native enforcement v1 — portal sync + capture enforce commands
python3 "${HELPER}" portal-sync >/dev/null \
  || die "portal-sync must exit 0 (graceful when portal absent)"
psync="$(python3 "${HELPER}" portal-sync microphone)"
echo "${psync}" | python3 -c 'import json,sys
d=json.load(sys.stdin)
assert d.get("ok") is True
assert "portalAvailable" in d
' || die "portal-sync JSON shape"
ok "portal-sync"

enf="$(python3 "${HELPER}" enforce-capture)"
echo "${enf}" | python3 -c 'import json,sys
d=json.load(sys.stdin)
assert d.get("ok") is True
assert "microphone" in d and "camera" in d and "screen" in d
assert "portalScreen" in d and isinstance(d.get("portalScreen"), list)
' || die "enforce-capture JSON shape"
ok "enforce-capture"

PROTEUS_PORTAL_SESSION_FIXTURE=1 python3 "${HELPER}" enforce-capture | python3 -c 'import json,sys
d=json.load(sys.stdin)
assert d.get("ok") is True
ps=d.get("portalScreen") or []
assert len(ps) >= 1 and ps[0].get("closed") is True and ps[0].get("fixture") is True
assert int(d.get("portalClosed") or 0) >= 1
' || die "portal Session.Close fixture"
ok "portal Session.Close fixture"

grep -q 'portal-sync\|SetPermission\|PermissionStore' "${HELPER}" \
  || die "helper missing portal PermissionStore bridge"
grep -q 'Session.Close\|portal_close_screencast_sessions\|PORTAL_SESSION_IFACE' "${HELPER}" \
  || die "helper missing portal Session.Close"
grep -q 'Session.Close\|portal Session.Close' "${CAT_LEAF}" "${PRIV_PANE}" \
  || die "Privacy UI missing portal Session.Close honesty"
grep -q 'Session.Close\|portal screencast sessions' "${ROOT}/shell/shared/PrivacyAsk.qml" \
  || die "PrivacyAsk missing portal Session.Close honesty"
grep -q 'enforce-capture\|set-source-output-mute' "${HELPER}" \
  || die "helper missing capture enforce"
grep -q 'def enforce_screen\|_is_screencast_node' "${HELPER}" \
  || die "helper missing enforce_screen for screencast kill"
grep -q 'def capture_should_block\|in ("deny", "ask")' "${HELPER}" \
  || die "enforce-capture must block Deny + Ask"
grep -q 'Deny or Ask\|deny", "ask"' "${HELPER}" \
  || die "enforce-capture help/docs must note Ask enforce"
grep -q 'Ask skipped' "${HELPER}" \
  && die "enforce-capture must not still say Ask skipped"
grep -q 'enforce-capture' "${ROOT}/shell/shared/PrivacyIndicators.qml" \
  || die "PrivacyIndicators must periodic enforce-capture"
grep -q 'PermissionStore\|capture enforce\|Deny/Ask\|Deny + Ask' "${CAT_LEAF}" "${PRIV_PANE}" \
  || die "Privacy UI missing native enforcement honesty"
# Offline: Ask grant must count as capture block; Allow must not.
TMPASK="$(mktemp -d)"
(
  export HOME="${TMPASK}"
  python3 "${HELPER}" store-set-app org.proteus.AskProbe microphone ask >/dev/null
  python3 "${HELPER}" store-set-app org.proteus.AllowProbe camera allow >/dev/null
  python3 "${HELPER}" store-set-app org.proteus.ScreenAsk screen ask >/dev/null
  python3 "${HELPER}" store-set-app org.proteus.ScreenAllow screen allow >/dev/null
  python3 - "${HELPER}" <<'PY' || exit 1
import importlib.util, sys
from pathlib import Path
p = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("pp", p)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
data = m.load_store()
assert m.capture_should_block(data, "org.proteus.AskProbe", "microphone") is True
assert m.capture_should_block(data, "org.proteus.AllowProbe", "camera") is False
assert m.capture_should_block(data, "org.proteus.AskProbe", "camera") is False
assert m.capture_should_block(data, "org.proteus.ScreenAsk", "screen") is True
assert m.capture_should_block(data, "org.proteus.ScreenAllow", "screen") is False
# Session Allow-once bypasses Ask block (mid-session dialog path).
sess = {"org.proteus.AskProbe\tmicrophone", "org.proteus.ScreenAsk\tscreen"}
assert m.capture_should_block(data, "org.proteus.AskProbe", "microphone", sess) is False
assert m.capture_should_block(data, "org.proteus.AskProbe", "microphone", set()) is True
assert m.capture_should_block(data, "org.proteus.ScreenAsk", "screen", sess) is False
assert m.capture_should_block(data, "org.proteus.ScreenAsk", "screen", set()) is True
print("capture_should_block ok")
PY
) || die "capture_should_block Ask/Allow offline"
rm -rf "${TMPASK}"
ok "native enforcement wiring + Ask capture block"

[[ $fail -eq 0 ]] || { echo "permissions-smoke: FAILED" >&2; exit 1; }
echo "permissions-smoke: OK"
