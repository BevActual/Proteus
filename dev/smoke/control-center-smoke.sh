#!/usr/bin/env bash
# control-center-smoke — CC columns UI + layout wiring (host static)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fail=0
ok() { echo "control-center-smoke: OK $*"; }
die() { echo "control-center-smoke: FAIL $*" >&2; fail=1; }

CCL="${ROOT}/shell/shared/ControlCenterLayout.qml"
LEAF="${ROOT}/apps/proteus-settings/panes/DesktopControlCenterLeaf.qml"
GRID="${ROOT}/shell/surfaces/desktop/QuickSettingsGrid.qml"

[[ -f "${CCL}" ]] || die "missing ControlCenterLayout.qml"
[[ -f "${LEAF}" ]] || die "missing DesktopControlCenterLeaf.qml"
[[ -f "${GRID}" ]] || die "missing QuickSettingsGrid.qml"
ok "files present"

grep -q 'function setColumns' "${CCL}" || die "ControlCenterLayout missing setColumns"
grep -q 'columns !== 2 && columns !== 3' "${CCL}" \
  || grep -q 'columns === 3' "${CCL}" \
  || die "ControlCenterLayout must clamp columns to 2|3"
ok "setColumns API"

grep -q 'ControlCenterLayout.setColumns' "${LEAF}" \
  || die "DesktopControlCenterLeaf must call setColumns"
grep -q 'SettingsSegmented' "${LEAF}" || die "DesktopControlCenterLeaf must offer segmented columns"
grep -qi 'Columns' "${LEAF}" || die "DesktopControlCenterLeaf must label Columns"
ok "Settings columns UI"

grep -q 'resolvedLayout().columns' "${GRID}" \
  || die "QuickSettingsGrid must bind resolvedLayout().columns"
ok "runtime grid columns"

# Roundtrip stub should carry columns
grep -q '"columns"' "${ROOT}/dev/smoke/config-roundtrip-smoke.sh" \
  || die "config-roundtrip must mutate controlCenterLayout.columns"
ok "config-roundtrip columns"

[[ $fail -eq 0 ]] || { echo "control-center-smoke: FAILED" >&2; exit 1; }
echo "control-center-smoke: OK"
