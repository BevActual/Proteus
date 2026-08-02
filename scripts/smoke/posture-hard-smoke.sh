#!/usr/bin/env bash
# posture-hard-smoke — hard posture helper + console profile rename (no live compositor flip)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

die() { echo "posture-hard-smoke: FAIL $*" >&2; exit 1; }
ok() { echo "posture-hard-smoke: OK $*"; }

POSTURE="${ROOT}/vm/guest/proteus-posture"
GUIDE="${ROOT}/vm/guest/proteus-guide"
PROFILE="${ROOT}/vm/guest/set-hypr-profile.sh"
CONSOLE_CONF="${ROOT}/env/hypr/profiles/console.conf"

[[ -x "${POSTURE}" ]] || die "proteus-posture not executable"
[[ -x "${GUIDE}" ]] || die "proteus-guide not executable"
[[ -x "${PROFILE}" ]] || die "set-hypr-profile.sh not executable"
[[ -f "${CONSOLE_CONF}" ]] || die "missing env/hypr/profiles/console.conf"
[[ ! -f "${ROOT}/env/hypr/profiles/media.conf" ]] || die "legacy media.conf still present — should be console.conf"
grep -q 'PROTEUS_SKIP_SESSION_LOCK=1' "${POSTURE}" \
  || die "proteus-posture must skip cold-boot lock on chrome restart"
ok "helpers + console.conf"

# usage exits 2
set +e
"${POSTURE}" >/dev/null 2>&1
ec=$?
set -e
[[ "${ec}" -eq 2 ]] || die "proteus-posture usage should exit 2 (got ${ec})"
ok "proteus-posture usage"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

# Isolate completely from the dogfood session
export HOME="${TMP}"
unset XDG_CONFIG_HOME XDG_RUNTIME_DIR || true
export XDG_RUNTIME_DIR="${TMP}/run"
mkdir -p "${HOME}/.config/proteus" "${HOME}/.config/hypr/profiles" "${XDG_RUNTIME_DIR}"

# Stub hyprctl so we never reload the live compositor
mkdir -p "${TMP}/bin"
cat >"${TMP}/bin/hyprctl" <<'EOF'
#!/usr/bin/env bash
echo "hyprctl stub: $*" >>"${HOME}/hyprctl-stub.log"
exit 1
EOF
chmod +x "${TMP}/bin/hyprctl"

FAKE_ROOT="${TMP}/proteus"
mkdir -p "${FAKE_ROOT}/shell/scripts" "${FAKE_ROOT}/vm/guest" "${FAKE_ROOT}/env/hypr/profiles"
cp "${POSTURE}" "${FAKE_ROOT}/vm/guest/proteus-posture"
cp "${PROFILE}" "${FAKE_ROOT}/vm/guest/set-hypr-profile.sh"
cp "${GUIDE}" "${FAKE_ROOT}/vm/guest/proteus-guide"
cp "${CONSOLE_CONF}" "${FAKE_ROOT}/env/hypr/profiles/console.conf"
printf '# stub\n' >"${FAKE_ROOT}/env/hypr/profiles/desktop.conf"
cat >"${FAKE_ROOT}/shell/scripts/proteus-qs" <<'EOF'
#!/usr/bin/env bash
echo "stub proteus-qs $*" >>"${HOME}/qs-stub.log"
exit 0
EOF
chmod +x "${FAKE_ROOT}/vm/guest/"* "${FAKE_ROOT}/shell/scripts/proteus-qs" 2>/dev/null || true
chmod +x "${FAKE_ROOT}/vm/guest/proteus-posture" "${FAKE_ROOT}/vm/guest/set-hypr-profile.sh" \
  "${FAKE_ROOT}/vm/guest/proteus-guide" "${FAKE_ROOT}/shell/scripts/proteus-qs"

export PROTEUS_ROOT="${FAKE_ROOT}"
export PATH="${TMP}/bin:${FAKE_ROOT}/shell/scripts:${PATH}"

bash "${FAKE_ROOT}/vm/guest/proteus-posture" console || true
[[ -f "${HOME}/.config/proteus/posture" ]] || die "posture Fact not written"
got="$(tr -d '[:space:]' <"${HOME}/.config/proteus/posture")"
[[ "${got}" == "console" ]] || die "expected Fact console, got '${got}'"
ok "Fact write console"

bash "${FAKE_ROOT}/vm/guest/proteus-posture" desktop || true
got="$(tr -d '[:space:]' <"${HOME}/.config/proteus/posture")"
[[ "${got}" == "desktop" ]] || die "expected Fact desktop, got '${got}'"
ok "Fact write desktop"

# Pointer migration media → console
printf 'source = ~/.config/hypr/profiles/media.conf\n' >"${HOME}/.config/hypr/proteus-profile.conf"
printf '# legacy\n' >"${HOME}/.config/hypr/profiles/media.conf"
bash "${FAKE_ROOT}/vm/guest/set-hypr-profile.sh" console
grep -q 'profiles/console.conf' "${HOME}/.config/hypr/proteus-profile.conf" \
  || die "pointer not migrated to console.conf"
[[ -f "${HOME}/.config/hypr/profiles/console.conf" ]] || die "console.conf not seeded"
ok "media → console pointer migration"

# Boot persistence: resolve Fact when PROTEUS_SURFACE unset
printf 'console\n' >"${HOME}/.config/proteus/posture"
RESOLVED="$(
  bash -c '
    unset PROTEUS_SURFACE || true
    _posture_file="${HOME}/.config/proteus/posture"
    if [[ -z "${PROTEUS_SURFACE:-}" && -f "${_posture_file}" ]]; then
      PROTEUS_SURFACE="$(tr -d "[:space:]" <"${_posture_file}" || true)"
    fi
    case "${PROTEUS_SURFACE:-}" in
      desktop|console|couch|phone|vr|watch) ;;
      *) PROTEUS_SURFACE=desktop ;;
    esac
    [[ "${PROTEUS_SURFACE}" == "couch" ]] && PROTEUS_SURFACE=console
    printf "%s" "${PROTEUS_SURFACE}"
  '
)"
[[ "${RESOLVED}" == "console" ]] || die "boot persistence resolved '${RESOLVED}' not console"
ok "boot persistence from Fact"

if command -v gamescope >/dev/null 2>&1; then
  ok "gamescope present"
else
  ok "gamescope absent (warn path — home still works)"
fi

grep -q 'gamepadsGuideSingle' "${ROOT}/shell/shared/Config.qml" || die "Config missing gamepadsGuideSingle"
grep -q 'gamepadsGuideDouble' "${ROOT}/shell/shared/Config.qml" || die "Config missing gamepadsGuideDouble"
ok "Config gamepads keys"

grep -q 'ConsoleShell' "${ROOT}/shell/shell.qml" || die "shell.qml missing ConsoleShell"
[[ -f "${ROOT}/shell/surfaces/ConsoleShell.qml" ]] || die "ConsoleShell.qml missing"
[[ ! -f "${ROOT}/shell/surfaces/CouchShell.qml" ]] || die "CouchShell.qml should be removed"
ok "console surface loader"

LAUNCH="${ROOT}/shell/scripts/proteus-console-launch"
SEAT="${ROOT}/shell/scripts/proteus-console-seat"
CAPS="${ROOT}/shell/scripts/proteus-console-capabilities"
APPLY="${ROOT}/vm/guest/apply-console-kit.sh"
[[ -x "${LAUNCH}" ]] || die "proteus-console-launch not executable"
[[ -x "${SEAT}" ]] || die "proteus-console-seat not executable"
[[ -x "${CAPS}" ]] || die "proteus-console-capabilities not executable"
[[ -x "${APPLY}" ]] || die "apply-console-kit.sh not executable"
bash -n "${LAUNCH}" || die "proteus-console-launch bash -n"
bash -n "${SEAT}" || die "proteus-console-seat bash -n"
bash -n "${CAPS}" || die "proteus-console-capabilities bash -n"
bash -n "${APPLY}" || die "apply-console-kit.sh bash -n"
set +e
"${LAUNCH}" >/dev/null 2>&1
lec=$?
set -e
[[ "${lec}" -eq 2 ]] || die "proteus-console-launch usage should exit 2 (got ${lec})"
set +e
"${SEAT}" >/dev/null 2>&1
sec=$?
set -e
[[ "${sec}" -eq 2 ]] || die "proteus-console-seat usage should exit 2 (got ${sec})"
CAPS_JSON="$("${CAPS}" 2>/dev/null || true)"
echo "${CAPS_JSON}" | grep -q 'gamescopeUsable' || die "capabilities missing gamescopeUsable"
# Console kit lives in its own list (multilib; console stage) — not desktop
grep -qE '^gamescope$' "${ROOT}/vm/install/proteus-console.packages" || die "gamescope not in console packages"
grep -qE '^python-evdev$' "${ROOT}/vm/install/proteus-console.packages" || die "python-evdev not in console packages"
grep -qE '^(gamescope|python-evdev)$' "${ROOT}/vm/install/proteus-desktop.packages" \
  && die "console kit must not live in desktop packages" || true
grep -q 'proteus-console-seat' "${ROOT}/shell/surfaces/console/ConsoleLibrary.qml" \
  || die "ConsoleLibrary missing proteus-console-seat wiring"
grep -q 'runSeat' "${ROOT}/shell/surfaces/console/ConsoleLibrary.qml" \
  || die "ConsoleLibrary missing runSeat"
grep -q 'gamescope_usable' "${LAUNCH}" || die "proteus-console-launch missing gamescope_usable (VM bare path)"
grep -q 'shell/scripts:\$HOME/.local/bin:/usr/local/bin' "${ROOT}/shell/surfaces/console/ConsoleLibrary.qml" \
  || grep -q 'shell/scripts:$HOME/.local/bin:/usr/local/bin' "${ROOT}/shell/surfaces/console/ConsoleLibrary.qml" \
  || die "ConsoleLibrary should prefer live shell/scripts on PATH"
grep -q 'fullscreenAssist' "${ROOT}/shell/surfaces/console/ConsoleLibrary.qml" \
  && die "ConsoleLibrary should use seat fullscreen, not fullscreenAssist" || true
grep -q 'kind === "posture"' "${ROOT}/shell/surfaces/console/ConsoleLibrary.qml" \
  || die "ConsoleLibrary posture flip must key on kind===posture only"
grep -q 'fullscreen_state 2 2' "${ROOT}/env/hypr/profiles/console.conf" \
  || die "console.conf missing fullscreen_state rule"
grep -qE 'org\.quickshell|\[Qq\]uickshell' "${ROOT}/env/hypr/profiles/console.conf" \
  || die "console.conf must exempt org.quickshell from fullscreen"
grep -q 'special:proteus-chrome' "${ROOT}/env/hypr/profiles/console.conf" \
  || die "console.conf must park Quickshell on special:proteus-chrome"
grep -q 'console_workspace_hygiene' "${ROOT}/vm/guest/proteus-posture" \
  || die "proteus-posture missing console workspace hygiene"
grep -q 'proteus-console-seat' "${ROOT}/vm/guest/apply-console-kit.sh" \
  || die "apply-console-kit missing proteus-console-seat"
[[ -f "${ROOT}/shell/surfaces/console/ConsoleAppsModel.qml" ]] || die "ConsoleAppsModel.qml missing"
ok "console launch kit + Library model"

grep -q 'function pad' "${ROOT}/shell/surfaces/DesktopShell.qml" || die "DesktopShell missing chrome pad IPC"
grep -q 'function pad' "${ROOT}/shell/surfaces/ConsoleShell.qml" || die "ConsoleShell missing chrome pad IPC"
grep -q 'handlePad' "${ROOT}/shell/shared/ShellState.qml" || die "ShellState missing handlePad"
grep -q 'padWanted' "${ROOT}/vm/guest/proteus-guide" || die "proteus-guide missing padWanted poll"
ok "chrome pad IPC contract"

# Control Center Console tile — bash `A && B & || C` is a syntax error (tile no-op).
CC="${ROOT}/shell/surfaces/desktop/ControlCenter.qml"
QSGRID="${ROOT}/shell/surfaces/desktop/QuickSettingsGrid.qml"
[[ -f "${CC}" ]] || die "missing ControlCenter.qml"
[[ -f "${QSGRID}" ]] || die "missing QuickSettingsGrid.qml"
if grep -qE 'proteus-posture[^
]*&&[^
]*&[[:space:]]*\|\|' "${CC}" "${QSGRID}" 2>/dev/null; then
  die "CC console launch uses invalid bash A && B & || C"
fi
grep -q 'vm/guest/proteus-posture' "${CC}" || die "ControlCenter missing live-tree posture launch"
grep -q 'vm/guest/proteus-posture' "${QSGRID}" || die "QuickSettingsGrid missing live-tree posture launch"
grep -q 'PROTEUS_SKIP_SESSION_LOCK=1' "${ROOT}/vm/guest/proteus-posture" \
  || die "live proteus-posture missing SKIP_SESSION_LOCK on restart"
grep -q 'id: "console"' "${QSGRID}" || die "QuickSettingsGrid missing Console tile"
grep -q 'id: "desktop"' "${QSGRID}" || die "QuickSettingsGrid missing Desktop tile (console posture)"
grep -q 'consoleSurfaceActive' "${CC}" || die "ControlCenter missing consoleSurfaceActive posture gate"
grep -q 'consoleChrome\|consoleSurfaceActive' "${CC}" || die "ControlCenter missing console panel geometry"
ok "CC Console tile launch syntax"

CSHELL="${ROOT}/shell/surfaces/ConsoleShell.qml"
grep -q 'StatusHud' "${CSHELL}" || die "ConsoleShell missing StatusHud"
grep -q 'NotificationToast' "${CSHELL}" || die "ConsoleShell missing NotificationToast"
grep -q 'volume-up' "${CSHELL}" || die "ConsoleShell missing volume shortcuts"
grep -q 'navFade' "${CSHELL}" || die "ConsoleShell missing navFade motion"
ok "console HUD/toast/motion"

[[ -f "${ROOT}/shell/shared/UniversalSearch.qml" ]] || die "missing UniversalSearch.qml"
grep -q 'UniversalSearch' "${ROOT}/shell/surfaces/console/ConsoleAppsModel.qml" \
  || die "ConsoleAppsModel missing UniversalSearch"
grep -q 'consoleExtras\|UniversalSearch' "${ROOT}/shell/surfaces/console/ConsoleAppsModel.qml" \
  || die "ConsoleAppsModel missing consoleExtras path"
grep -q 'UniversalSearch.actionCatalog\|UniversalSearch.runAction' \
  "${ROOT}/shell/surfaces/desktop/Beacon.qml" \
  || die "Beacon must consume UniversalSearch allowlist"
grep -q 'kind === "action"' "${ROOT}/shell/surfaces/console/ConsoleLibrary.qml" \
  || die "ConsoleLibrary missing action activate"
grep -q 'chromeStyle' "${ROOT}/shell/surfaces/console/ConsoleCard.qml" \
  || die "ConsoleCard missing chromeStyle"
grep -q 'contextLine\|padHintLine' "${ROOT}/shell/surfaces/console/ConsoleFooter.qml" \
  "${ROOT}/shell/surfaces/console/ConsoleHome.qml" \
  || die "console pad hint context line missing"
ok "console desktop UX parity wires"

CHOME="${ROOT}/shell/surfaces/console/ConsoleHome.qml"
CAPPS="${ROOT}/shell/surfaces/console/ConsoleAppsModel.qml"
CLIB="${ROOT}/shell/surfaces/console/ConsoleLibrary.qml"
[[ -f "${ROOT}/shell/surfaces/console/ConsoleLeanSheet.qml" ]] || die "missing ConsoleLeanSheet.qml"
[[ -f "${ROOT}/shell/surfaces/console/ConsoleShelf.qml" ]] || die "missing ConsoleShelf.qml"
grep -q 'sectionLabels\|sectionedApps\|gamesShelf\|appsShelf' "${CAPPS}" \
  || die "ConsoleAppsModel missing library/apps/games shelves"
grep -q 'isConsoleHomeApp' "${CAPPS}" || die "ConsoleAppsModel missing isConsoleHomeApp curated Home filter"
grep -q 'appsModel.appsShelf\|appsShelf' "${CHOME}" || die "Home Apps shelf must use individual apps (not appSeats)"
grep -q 'appSeats' "${CHOME}" && die "Home still binds curated appSeats — use DesktopEntry cards"
grep -q 'featuredMetaLine\|shelfItemsAt(shelfIndex)' "${CHOME}" \
  || die "Hero must track focused card on any shelf"
grep -q 'peekScale\|shelfActive' "${ROOT}/shell/surfaces/console/ConsoleShelf.qml" \
  || die "ConsoleShelf missing active/peek sizing"
# Console cards/hero: no category tag chips (shelf titles carry that job).
if grep -qE 'displayTag|quietTags' "${ROOT}/shell/surfaces/console/ConsoleCard.qml"; then
  die "ConsoleCard still has category tag UI"
fi
if grep -qE 'tagLbl|readonly property string tag' "${ROOT}/shell/surfaces/console/ConsoleHero.qml"; then
  die "ConsoleHero still has category tag UI"
fi
grep -q 'metaLine' "${ROOT}/shell/surfaces/console/ConsoleHero.qml" \
  || die "ConsoleHero missing metaLine for cinematic featured"
grep -q 'searchShortcuts\|Shortcuts' "${CAPPS}" "${CHOME}" || die "Search idle shortcuts missing"
grep -q 'libSection\|LIBRARY' "${CHOME}" || die "ConsoleHome missing library section chips"
grep -q 'homeShelves\|focusZone === "shelf"\|shelfIndex' "${CHOME}" || die "ConsoleHome missing shelf Home model"
grep -q 'bandHeight\|bandFocused' "${ROOT}/shell/surfaces/console/ConsoleHero.qml" \
  || die "ConsoleHero missing full-bleed band"
grep -q 'focusScale' "${ROOT}/shell/surfaces/console/ConsoleCard.qml" \
  "${ROOT}/shell/surfaces/console/ConsoleRow.qml" \
  || die "Console cards missing focus scale"
grep -q 'Library\|Search' "${ROOT}/shell/surfaces/console/ConsoleBar.qml" \
  || die "ConsoleBar missing Library/Search destinations"
grep -q 'openMediaSheet\|pickMediaFile\|launchMediaPath' "${CHOME}" "${CLIB}" \
  || die "Media seat submenu wiring missing"
grep -q 'openDetailsSheet\|ConsoleLeanSheet' "${CHOME}" || die "Hero Details sheet missing"
grep -q 'webItems\|Web Apps\|webApps' "${CHOME}" "${CAPPS}" || die "Home Web apps shelf missing"
grep -q 'removeRecent\|allowRemove' "${CHOME}" "${CLIB}" || die "Jump Back In remove missing"
[[ -x "${ROOT}/shell/scripts/proteus-pick-media" ]] || die "proteus-pick-media not executable"
ok "console shelf Home + submenus"

WEBAPP="${ROOT}/shell/scripts/proteus-webapp"
[[ -x "${WEBAPP}" ]] || die "proteus-webapp not executable"
bash -n "${WEBAPP}" || die "proteus-webapp bash -n"
set +e
"${WEBAPP}" >/dev/null 2>&1
wec=$?
set -e
[[ "${wec}" -eq 2 ]] || die "proteus-webapp usage should exit 2 (got ${wec})"
grep -q 'packages-webapps' "${ROOT}/apps/proteus-settings/panes/PackagesPane.qml" \
  || die "Software hub missing Web apps leaf"
[[ -f "${ROOT}/apps/proteus-settings/panes/PackagesWebAppsPane.qml" ]] || die "PackagesWebAppsPane.qml missing"
grep -qE '^steam$' "${ROOT}/vm/install/proteus-console.packages" || die "steam not in console packages"
grep -qE '^retroarch$' "${ROOT}/vm/install/proteus-console.packages" || die "retroarch not in console packages"
grep -q 'consoleRecents' "${ROOT}/shell/shared/Config.qml" || die "Config missing consoleRecents"
ok "webapp + Steam/Retro + consoleRecents"

echo "posture-hard-smoke: OK"
