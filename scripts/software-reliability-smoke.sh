#!/usr/bin/env bash
# Host static checks for Software reliability (Install|Installed mode + op narrative).
# Complements scripts/software-guest-smoke.sh (guest CLI dogfood).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
ok() { echo "OK  $*"; }
bad() { echo "FAIL $*"; fail=1; }

need() {
  local file="$1" pat="$2" label="$3"
  if rg -q -- "$pat" "$file"; then
    ok "$label"
  else
    bad "$label ($file missing /$pat/)"
  fi
}

for pane in PackagesSearchPane PackagesAurPane PackagesFlatpakPane; do
  f="$ROOT/apps/proteus-settings/panes/${pane}.qml"
  need "$f" 'searchGen' "${pane} searchGen"
  need "$f" 'requestGen = -1' "${pane} abort invalidate"
  need "$f" 'installQuery' "${pane} installQuery"
  need "$f" 'installedQuery' "${pane} installedQuery"
  need "$f" 'mode !== "install"' "${pane} install-mode guard"
done

need "$ROOT/shell/shared/Packages.qml" 'packageOpCommand' "Packages.packageOpCommand"
need "$ROOT/shell/shared/Packages.qml" 'packageOpLastError' "Packages.packageOpLastError"
need "$ROOT/shell/shared/Packages.qml" 'function formatOpCommand' "Packages.formatOpCommand"
need "$ROOT/apps/proteus-settings/kit/PackagesOpProgress.qml" 'packageOpCommand' "OpProgress shows command"
need "$ROOT/apps/proteus-settings/kit/PackagesOpProgress.qml" 'packageOpLastError' "OpProgress shows last error"
need "$ROOT/apps/proteus-settings/kit/PackagesOpProgress.qml" 'showIdleStatus: true' "OpProgress keeps idle result"

[[ "$fail" -eq 0 ]] || { echo "software-reliability-smoke: FAILED" >&2; exit 1; }
echo "software-reliability-smoke: OK"
