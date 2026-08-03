#!/usr/bin/env bash
# layout-smoke — flat shared spine + Settings kit structure gate
# Fail closed if domain packages / qmldir return or required files go missing.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SHARED="${ROOT}/shell/shared"
SETTINGS="${ROOT}/apps/proteus-settings"
fail=0

die() { echo "layout-smoke: FAIL $*" >&2; fail=1; }
ok() { echo "layout-smoke: OK $*"; }

# Forbidden domain package dirs (Quickshell load-order cycles)
for d in chrome config background widgets system session; do
  if [[ -d "${SHARED}/${d}" ]]; then
    die "domain dir must not exist: shell/shared/${d}/"
  fi
done

if [[ -e "${SHARED}/qmldir" ]]; then
  die "shell/shared/qmldir must not exist (flat directory import only)"
fi

REQUIRED=(
  Theme.qml
  Config.qml
  ConfigHypr.qml
  Background.qml
  BackgroundCatalog.qml
  BackgroundDaily.qml
  BackgroundApply.qml
  Widgets.qml
  WidgetsLock.qml
  WidgetsDesktop.qml
  Audio.qml
  Power.qml
  DateTime.qml
  Weather.qml
  Displays.qml
  Hardware.qml
  EnvGate.qml
  Keybinds.qml
  ShellState.qml
  LockLayoutZones.qml
  Notifications.qml
  KeepAwake.qml
  FocusMode.qml
  ControlCenterLayout.qml
  LocalSend.qml
  HyprProfile.qml
  SessionPosture.qml
  SystemInfo.qml
  SystemLoad.qml
  MissionCenter.qml
  NetworkDiagnostics.qml
  Accounts.qml
  CalendarEvents.qml
  MailGlance.qml
  ContactsGlance.qml
  AdaptEnv.qml
  Workloads.qml
  SpacesDisplays.qml
  SpacesNames.qml
  PrivacyAsk.qml
  Hud.qml
  Brightness.qml
  Packages.qml
  DockApps.qml
  Time.qml
  ActiveWindow.qml
  UniversalSearch.qml
  Permissions.qml
  PrivacyIndicators.qml
  DefaultApps.qml
  SystemServices.qml
)

for f in "${REQUIRED[@]}"; do
  if [[ ! -f "${SHARED}/${f}" ]]; then
    die "missing shell/shared/${f}"
  fi
done
ok "required singletons/helpers present ($(printf '%s\n' "${REQUIRED[@]}" | wc -l) files)"

KIT_REQUIRED=(
  PackagesActionBar.qml
  PackagesConfirm.qml
  PackagesOpProgress.qml
  PackagesPickerRow.qml
  SettingsCombo.qml
  SettingsFormRow.qml
  SettingsGroup.qml
  SettingsHubList.qml
  SettingsSegmented.qml
)
# kit lives in the shared spine so every posture face can reach it — the console
# face is a separate renderer under shell/surfaces/console and cannot import
# across into apps/. Settings keeps a symlink so `import "../kit"` in ~40 panes
# is unchanged.
for f in "${KIT_REQUIRED[@]}"; do
  if [[ ! -f "${SHARED}/kit/${f}" ]]; then
    die "missing shell/shared/kit/${f}"
  fi
done
ok "shared kit present"

if [[ ! -L "${SETTINGS}/kit" ]]; then
  die "apps/proteus-settings/kit must be a symlink to shell/shared/kit"
else
  kit_target="$(readlink -f "${SETTINGS}/kit")"
  kit_expect="$(readlink -f "${SHARED}/kit")"
  if [[ "${kit_target}" != "${kit_expect}" ]]; then
    die "kit symlink → ${kit_target}, expected ${kit_expect}"
  fi
  ok "Settings kit → shell/shared/kit"
fi

# kit sits one level below the flat singleton package, so it reaches it as ".."
# — not "../shared", which only resolved from the old apps/ location.
if grep -rq 'import "\.\./shared"' "${SHARED}/kit"/*.qml 2>/dev/null; then
  die "shell/shared/kit still imports \"../shared\" (resolves to shell/shared/shared)"
fi
ok "kit imports the shared package as \"..\""

# Nothing in the shared spine may depend on a product app.
if grep -rqE 'apps/proteus-' "${SHARED}/kit"/*.qml 2>/dev/null; then
  die "shell/shared/kit references apps/ (shared spine must not depend on a product app)"
fi
ok "kit is app-independent"

if [[ ! -e "${SETTINGS}/shared" ]]; then
  die "apps/proteus-settings/shared missing"
elif [[ ! -L "${SETTINGS}/shared" ]]; then
  die "apps/proteus-settings/shared must be a symlink"
else
  target="$(readlink -f "${SETTINGS}/shared")"
  expect="$(readlink -f "${ROOT}/shell/shared")"
  if [[ "${target}" != "${expect}" ]]; then
    die "shared symlink → ${target}, expected ${expect}"
  fi
  ok "Settings shared → shell/shared"
fi

if [[ ! -f "${ROOT}/shell/shell.qml" ]]; then
  die "missing shell/shell.qml"
fi
if [[ ! -f "${SETTINGS}/shell.qml" ]]; then
  die "missing apps/proteus-settings/shell.qml"
fi

if [[ "${fail}" -ne 0 ]]; then
  echo "layout-smoke: FAILED" >&2
  exit 1
fi
echo "layout-smoke: OK (flat shared + kit)"
