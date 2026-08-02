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

# Manifest permissions field accepted
"${ROOT}/scripts/smoke/app-manifest-smoke.sh" >/dev/null || die "app-manifest-smoke"
ok "app-manifest with permissions"

grep -q 'permissionDeniedReason\|Permissions.granted' "${ROOT}/shell/shared/EnvGate.qml" \
  || die "EnvGate must honor Permissions.granted"
ok "EnvGate grant gate"

[[ $fail -eq 0 ]] || { echo "permissions-smoke: FAILED" >&2; exit 1; }
echo "permissions-smoke: OK"
