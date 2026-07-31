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

# --- Repos / AUR / Flathub: mode-safe loads + abort ---
for pane in PackagesSearchPane PackagesAurPane PackagesFlatpakPane; do
  f="$ROOT/apps/proteus-settings/panes/${pane}.qml"
  need "$f" 'searchGen' "${pane} searchGen"
  need "$f" 'requestGen = -1' "${pane} abort invalidate"
  need "$f" 'installQuery' "${pane} installQuery"
  need "$f" 'installedQuery' "${pane} installedQuery"
  need "$f" 'mode !== "install"' "${pane} install-mode guard"
  need "$f" 'Packages.saveLeafUi' "${pane} saveLeafUi"
  need "$f" 'Packages.loadLeafUi' "${pane} loadLeafUi"
done

# --- Shared Packages singleton: op narrative + leaf UI memory + helpers ---
need "$ROOT/shell/shared/Packages.qml" 'packageOpCommand' "Packages.packageOpCommand"
need "$ROOT/shell/shared/Packages.qml" 'packageOpLastError' "Packages.packageOpLastError"
need "$ROOT/shell/shared/Packages.qml" 'function formatOpCommand' "Packages.formatOpCommand"
need "$ROOT/shell/shared/Packages.qml" 'function saveLeafUi' "Packages.saveLeafUi"
need "$ROOT/shell/shared/Packages.qml" 'function loadLeafUi' "Packages.loadLeafUi"
need "$ROOT/shell/shared/Packages.qml" 'function refreshHelpers' "Packages.refreshHelpers"
need "$ROOT/apps/proteus-settings/kit/PackagesOpProgress.qml" 'packageOpCommand' "OpProgress shows command"
need "$ROOT/apps/proteus-settings/kit/PackagesOpProgress.qml" 'packageOpLastError' "OpProgress shows last error"
need "$ROOT/apps/proteus-settings/kit/PackagesOpProgress.qml" 'showIdleStatus: true' "OpProgress keeps idle result"

# --- Hub: helper honesty ---
need "$ROOT/apps/proteus-settings/panes/PackagesPane.qml" 'Packages.refreshHelpers' "Hub refreshHelpers"
need "$ROOT/apps/proteus-settings/panes/PackagesPane.qml" 'Needs yay/paru' "Hub AUR helper honesty"
need "$ROOT/apps/proteus-settings/panes/PackagesPane.qml" 'Needs flatpak' "Hub Flatpak helper honesty"
need "$ROOT/apps/proteus-settings/panes/PackagesPane.qml" 'User library' "Hub AppImages honesty"
need "$ROOT/apps/proteus-settings/panes/PackagesPane.qml" 'Unused dependencies' "Hub Orphans honesty"

# --- Updates: list + Apply narrative ---
UPD="$ROOT/apps/proteus-settings/panes/PackagesUpdatesPane.qml"
need "$UPD" 'PackagesOpProgress' "Updates OpProgress"
need "$UPD" 'onCancelled' "Updates Cancel"
need "$UPD" 'pacman -Qu' "Updates -Qu fact"
need "$UPD" 'packageOpBusy' "Updates applying bind"
need "$UPD" 'onExited' "Updates -Qu exit honesty"
need "$UPD" 'System is up to date' "Updates empty honesty"

# --- Orphans: empty honesty + remove narrative ---
ORPH="$ROOT/apps/proteus-settings/panes/PackagesOrphansPane.qml"
need "$ORPH" 'PackagesOpProgress' "Orphans OpProgress"
need "$ORPH" 'No orphan packages' "Orphans empty honesty"
need "$ORPH" 'onCancelled' "Orphans Cancel"
need "$ORPH" '"-Qdt"' "Orphans -Qdt probe"
need "$ORPH" 'command + Cancel' "Orphans Cancel fact"

# --- AppImages: user library + no polkit ---
APP="$ROOT/apps/proteus-settings/panes/PackagesAppImagesPane.qml"
need "$APP" 'PackagesOpProgress' "AppImages OpProgress"
need "$APP" 'proteus/appimages' "AppImages library path"
need "$APP" 'No authentication' "AppImages user-only honesty"
need "$APP" 'onCancelled' "AppImages Cancel"

[[ "$fail" -eq 0 ]] || { echo "software-reliability-smoke: FAILED" >&2; exit 1; }
echo "software-reliability-smoke: OK"
