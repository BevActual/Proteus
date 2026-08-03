#!/usr/bin/env bash
# Host static checks for Software reliability (Install|Installed mode + op narrative).
# Complements dev/smoke/software-guest-smoke.sh (guest CLI dogfood).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
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
  need "$f" 'applySearchSeed' "${pane} applySearchSeed"
  need "$f" 'ingestSeed' "${pane} ingestSeed"
  need "$f" 'activateLeaf' "${pane} activateLeaf"
done

# --- Shared Packages singleton: op narrative + leaf UI memory + helpers ---
need "$ROOT/shell/shared/Packages.qml" 'packageOpCommand' "Packages.packageOpCommand"
need "$ROOT/shell/shared/Packages.qml" 'packageOpLastError' "Packages.packageOpLastError"
need "$ROOT/shell/shared/Packages.qml" 'function formatOpCommand' "Packages.formatOpCommand"
need "$ROOT/shell/shared/Packages.qml" 'function saveLeafUi' "Packages.saveLeafUi"
need "$ROOT/shell/shared/Packages.qml" 'function loadLeafUi' "Packages.loadLeafUi"
need "$ROOT/shell/shared/Packages.qml" 'function refreshHelpers' "Packages.refreshHelpers"
need "$ROOT/shell/shared/Packages.qml" 'function seedPackageSearch' "Packages.seedPackageSearch"
need "$ROOT/shell/shared/Packages.qml" 'function hasSearchSeedFor' "Packages.hasSearchSeedFor"
need "$ROOT/shell/shared/Packages.qml" 'searchSeedEpoch' "Packages.searchSeedEpoch"
need "$ROOT/apps/proteus-settings/SettingsNav.qml" 'goInstallSearch' "SettingsNav.goInstallSearch"
need "$ROOT/apps/proteus-settings/SettingsNav.qml" 'pendingInstallQuery' "SettingsNav.pendingInstallQuery"
need "$ROOT/apps/proteus-settings/SettingsNav.qml" 'takePendingInstall' "SettingsNav.takePendingInstall"
need "$ROOT/apps/proteus-settings/kit/SettingsFormRow.qml" 'onClicked: root.activated' "FormRow click → activated"
need "$ROOT/apps/proteus-settings/kit/PackagesOpProgress.qml" 'packageOpCommand' "OpProgress shows command"
need "$ROOT/apps/proteus-settings/kit/PackagesOpProgress.qml" 'packageOpLastError' "OpProgress shows last error"
need "$ROOT/apps/proteus-settings/kit/PackagesOpProgress.qml" 'showIdleStatus: true' "OpProgress keeps idle result"

# --- Hub: helper honesty + seed push ---
need "$ROOT/apps/proteus-settings/panes/PackagesPane.qml" 'Packages.refreshHelpers' "Hub refreshHelpers"
need "$ROOT/apps/proteus-settings/panes/PackagesPane.qml" 'Needs yay' "Hub AUR helper honesty"
need "$ROOT/apps/proteus-settings/panes/PackagesPane.qml" 'Needs flatpak' "Hub Flatpak helper honesty"
need "$ROOT/apps/proteus-settings/panes/PackagesPane.qml" 'User library' "Hub AppImages honesty"
need "$ROOT/apps/proteus-settings/panes/PackagesPane.qml" 'Unused dependencies' "Hub Orphans honesty"
need "$ROOT/apps/proteus-settings/panes/PackagesPane.qml" 'pushPendingSeed' "Hub pushPendingSeed"

# --- Escape Install… routes into Software ---
need "$ROOT/apps/proteus-settings/panes/SoundMatrixLeaf.qml" 'goInstallSearch' "Mixer Install… → Software"
need "$ROOT/apps/proteus-settings/panes/NetworkDiagnosticsLeaf.qml" 'goInstallSearch' "Wireshark Install… → Software"
need "$ROOT/apps/proteus-settings/panes/SystemPane.qml" 'goInstallSearch' "Mission Center Install… → Software"
need "$ROOT/apps/proteus-settings/panes/NetworkLocalSendLeaf.qml" 'goInstallSearch' "LocalSend Install… → Software"
need "$ROOT/apps/proteus-settings/panes/NetworkTailscaleLeaf.qml" 'goInstallSearch' "Tailscale Install… → Software"
need "$ROOT/apps/proteus-settings/panes/NetworkBluetoothLeaf.qml" 'goInstallSearch' "Bluetooth Install… → Software"

# --- SettingsNav is a root-module singleton: any pane referencing it MUST import ".." ---
for f in "$ROOT"/apps/proteus-settings/panes/*.qml; do
  if grep -qE '(^|[^.[:alnum:]_])SettingsNav\.' "$f"; then
    if grep -q 'import "\.\."' "$f"; then
      ok "$(basename "$f") imports root for SettingsNav"
    else
      bad "$(basename "$f") uses SettingsNav without import \"..\""
    fi
  fi
done

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
need "$ORPH" 'command \+ Cancel' "Orphans Cancel fact"

# --- AppImages: user library + no polkit ---
APP="$ROOT/apps/proteus-settings/panes/PackagesAppImagesPane.qml"
need "$APP" 'PackagesOpProgress' "AppImages OpProgress"
need "$APP" 'proteus/appimages' "AppImages library path"
need "$APP" 'No authentication' "AppImages user-only honesty"
need "$APP" 'onCancelled' "AppImages Cancel"

# --- Web apps: URL → desktop entry via proteus-webapp ---
WEB="$ROOT/apps/proteus-settings/panes/PackagesWebAppsPane.qml"
need "$WEB" 'proteus-webapp' "Web apps helper"
need "$WEB" 'No authentication' "Web apps user-only honesty"
need "$WEB" 'onCancelled' "Web apps Cancel"
need "$ROOT/shell/scripts/proteus-webapp" 'proteus-web-' "Web apps desktop prefix"

[[ "$fail" -eq 0 ]] || { echo "software-reliability-smoke: FAILED" >&2; exit 1; }
echo "software-reliability-smoke: OK"
