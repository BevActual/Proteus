#!/usr/bin/env bash
# focus-smoke — Focus profile entity CRUD wiring (host static)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fail=0
ok() { echo "focus-smoke: OK $*"; }
die() { echo "focus-smoke: FAIL $*" >&2; fail=1; }

FM="${ROOT}/shell/shared/FocusMode.qml"
LEAF="${ROOT}/apps/proteus-settings/panes/DesktopFocusLeaf.qml"

[[ -f "${FM}" ]] || die "missing FocusMode.qml"
[[ -f "${LEAF}" ]] || die "missing DesktopFocusLeaf.qml"
ok "files present"

grep -q 'function addProfile' "${FM}" || die "FocusMode missing addProfile"
grep -q 'function renameProfile' "${FM}" || die "FocusMode missing renameProfile"
grep -q 'function deleteProfile' "${FM}" || die "FocusMode missing deleteProfile"
grep -q 'uniqueProfileId\|slugifyProfileId' "${FM}" || die "FocusMode missing id helpers"
grep -q 'paneDensity' "${FM}" || die "FocusMode missing paneDensity signal"
grep -q 'minimal\|full' "${FM}" || die "FocusMode paneDensity must use full|minimal"
grep -q 'Hard-hides\|paneAvailable' "${FM}" \
  || die "FocusMode must document Settings hard pane hide"
ok "FocusMode CRUD API + paneDensity"

grep -q 'FocusMode.addProfile' "${LEAF}" || die "DesktopFocusLeaf must call addProfile"
grep -q 'FocusMode.renameProfile' "${LEAF}" || die "DesktopFocusLeaf must call renameProfile"
grep -q 'FocusMode.deleteProfile' "${LEAF}" || die "DesktopFocusLeaf must call deleteProfile"
grep -q 'confirmDelete' "${LEAF}" || die "DesktopFocusLeaf must confirm delete"
grep -q 'SettingsCombo' "${LEAF}" || die "DesktopFocusLeaf must use SettingsCombo when many profiles"
grep -q 'profileOptions.length > 3' "${LEAF}" || die "DesktopFocusLeaf must switch picker at >3 profiles"
ok "DesktopFocusLeaf CRUD UI"

# Roundtrip fixture must use runtime field name "name" (not "label")
if grep -q '"label": "Smoke"' "${ROOT}/scripts/smoke/config-roundtrip-smoke.sh"; then
  die "config-roundtrip focusProfiles stub still uses label (want name)"
fi
grep -q '"name": "Smoke"' "${ROOT}/scripts/smoke/config-roundtrip-smoke.sh" \
  || die "config-roundtrip focusProfiles stub must use name"
ok "config-roundtrip name field"

[[ $fail -eq 0 ]] || { echo "focus-smoke: FAILED" >&2; exit 1; }
echo "focus-smoke: OK"
