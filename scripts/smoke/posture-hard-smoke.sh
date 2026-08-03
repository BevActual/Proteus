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

# Uniform hard flip contract: managed sessions (PROTEUS_SESSION=1) end the
# graphical session — greeter shows, proteus-session picks the next engine.
grep -q 'end_session' "${POSTURE}" \
  || die "proteus-posture missing end_session (uniform flip)"
grep -q 'loginctl terminate-session' "${POSTURE}" \
  || die "proteus-posture must terminate-session for managed flips"
grep -q 'PROTEUS_SESSION' "${POSTURE}" \
  || die "proteus-posture must gate session exit on PROTEUS_SESSION"
ok "uniform flip contract (static)"

# usage exits 2
set +e
"${POSTURE}" >/dev/null 2>&1
ec=$?
set -e
[[ "${ec}" -eq 2 ]] || die "proteus-posture usage should exit 2 (got ${ec})"
ok "proteus-posture usage"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

# Isolate completely from the dogfood session — force the dev fallback path
# so a managed guest session never gets terminated by this smoke.
export HOME="${TMP}"
unset XDG_CONFIG_HOME XDG_RUNTIME_DIR PROTEUS_SESSION || true
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

# host Fact (host.conf stub must exist for set-hypr-profile)
printf '# stub\n' >"${FAKE_ROOT}/env/hypr/profiles/host.conf"
bash "${FAKE_ROOT}/vm/guest/proteus-posture" host || true
got="$(tr -d '[:space:]' <"${HOME}/.config/proteus/posture")"
[[ "${got}" == "host" ]] || die "expected Fact host, got '${got}'"
ok "Fact write host"

# Managed flip: PROTEUS_SESSION=1 must end the session via loginctl instead
# of the in-place chrome restart.
cat >"${TMP}/bin/loginctl" <<'EOF'
#!/usr/bin/env bash
echo "loginctl stub: $*" >>"${HOME}/loginctl-stub.log"
exit 0
EOF
chmod +x "${TMP}/bin/loginctl"
PROTEUS_SESSION=1 XDG_SESSION_ID=42 \
  bash "${FAKE_ROOT}/vm/guest/proteus-posture" console || true
sleep 1
grep -q 'terminate-session 42' "${HOME}/loginctl-stub.log" 2>/dev/null \
  || die "managed flip must loginctl terminate-session"
got="$(tr -d '[:space:]' <"${HOME}/.config/proteus/posture")"
[[ "${got}" == "console" ]] || die "managed flip must still write Fact (got '${got}')"
rm -f "${TMP}/bin/loginctl" "${HOME}/loginctl-stub.log"
ok "managed flip → session exit (loginctl stub)"

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
      desktop|console|couch|host|phone|vr|watch) ;;
      *) PROTEUS_SURFACE=desktop ;;
    esac
    [[ "${PROTEUS_SURFACE}" == "couch" ]] && PROTEUS_SURFACE=console
    printf "%s" "${PROTEUS_SURFACE}"
  '
)"
[[ "${RESOLVED}" == "console" ]] || die "boot persistence resolved '${RESOLVED}' not console"
ok "boot persistence from Fact"

printf 'host\n' >"${HOME}/.config/proteus/posture"
RESOLVED_HOST="$(
  bash -c '
    unset PROTEUS_SURFACE || true
    _posture_file="${HOME}/.config/proteus/posture"
    if [[ -z "${PROTEUS_SURFACE:-}" && -f "${_posture_file}" ]]; then
      PROTEUS_SURFACE="$(tr -d "[:space:]" <"${_posture_file}" || true)"
    fi
    case "${PROTEUS_SURFACE:-}" in
      desktop|console|couch|host|phone|vr|watch) ;;
      *) PROTEUS_SURFACE=desktop ;;
    esac
    printf "%s" "${PROTEUS_SURFACE}"
  '
)"
[[ "${RESOLVED_HOST}" == "host" ]] || die "boot persistence resolved '${RESOLVED_HOST}' not host"
ok "boot persistence host Fact"

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
grep -q 'HostShell' "${ROOT}/shell/shell.qml" || die "shell.qml missing HostShell"
[[ -f "${ROOT}/shell/surfaces/HostShell.qml" ]] || die "HostShell.qml missing"
grep -q 'case "host"' "${ROOT}/shell/shell.qml" || die "shell.qml missing host case"
ok "console + host surface loader"

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
grep -q 'close_host_product_apps' "${ROOT}/vm/guest/proteus-posture" \
  || die "proteus-posture missing close_host_product_apps"
grep -q 'Proteus Workloads' "${ROOT}/vm/guest/proteus-posture" \
  || die "proteus-posture must close Proteus Workloads on leave-host"
grep -q 'proteus-console-seat' "${ROOT}/vm/guest/apply-console-kit.sh" \
  || die "apply-console-kit missing proteus-console-seat"
[[ -f "${ROOT}/shell/surfaces/console/ConsoleAppsModel.qml" ]] || die "ConsoleAppsModel.qml missing"
ok "console launch kit + Library model"

grep -q 'function pad' "${ROOT}/shell/surfaces/DesktopShell.qml" || die "DesktopShell missing chrome pad IPC"
grep -q 'function pad' "${ROOT}/shell/surfaces/ConsoleShell.qml" || die "ConsoleShell missing chrome pad IPC"
grep -q 'handlePad' "${ROOT}/shell/shared/ShellState.qml" || die "ShellState missing handlePad"
grep -q 'settingsFaceHubs\|availableSettingsPanesForFace\|settingsFaceConsoleHubs' \
  "${ROOT}/shell/shared/EnvGate.qml" \
  || die "EnvGate missing Settings face hub API"
grep -q 'Different Settings faces\|settingsFaceHubs' \
  "${ROOT}/docs/proteus/POSTURES.md" "${ROOT}/docs/proteus/SETTINGS-IA.md" \
  || die "docs missing Settings faces lock"
grep -q 'availableSettingsPanesForFace' \
  "${ROOT}/shell/surfaces/console/ConsoleAppsModel.qml" \
  || die "ConsoleAppsModel must use face catalog"
grep -q 'BTN_TL\|"lb"' "${ROOT}/vm/guest/proteus-guide" \
  || die "proteus-guide missing bumper map (LB/RB)"
grep -q 'cycleDestination\|"lb"' "${ROOT}/shell/surfaces/console/ConsoleHome.qml" \
  || die "ConsoleHome missing LB/RB tab cycle"
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
# Shelf-era chrome (Hero / Shelf / Row / Card) is retired — list IA only.
for gone in ConsoleHero.qml ConsoleShelf.qml ConsoleRow.qml ConsoleCard.qml; do
  [[ -e "${ROOT}/shell/surfaces/console/${gone}" ]] \
    && die "shelf-era ${gone} must stay deleted (list IA is the console chrome)"
done
# ConsoleFooter returned as status + pad-legend strip (statusHint visible).
grep -q 'ConsoleFooter' "${ROOT}/shell/surfaces/console/ConsoleHome.qml" \
  || die "ConsoleHome missing ConsoleFooter status strip"
grep -q 'statusHint' "${ROOT}/shell/surfaces/console/ConsoleHome.qml" \
  || die "ConsoleHome must surface library.statusHint"
ok "console desktop UX parity wires"

CHOME="${ROOT}/shell/surfaces/console/ConsoleHome.qml"
CAPPS="${ROOT}/shell/surfaces/console/ConsoleAppsModel.qml"
CLIB="${ROOT}/shell/surfaces/console/ConsoleLibrary.qml"
CBAR="${ROOT}/shell/surfaces/console/ConsoleBar.qml"
[[ -f "${ROOT}/shell/surfaces/console/ConsoleLeanSheet.qml" ]] || die "missing ConsoleLeanSheet.qml"
[[ -f "${ROOT}/shell/surfaces/console/ConsoleSettingsPane.qml" ]] || die "missing ConsoleSettingsPane.qml"
grep -q 'ConsoleSettingsPane\|focusConsoleSettings\|openConsoleSettings' "${CHOME}" \
  "${ROOT}/shell/shared/ShellState.qml" \
  || die "Console in-chrome Settings wiring missing"
grep -q 'kind === "settings"' "${CLIB}" || die "ConsoleLibrary settings activate missing"
grep -q 'openConsoleSettings' "${CLIB}" || die "ConsoleLibrary must use openConsoleSettings"
grep -q 'ShellState.openSettings(page)' "${CLIB}" \
  && die "ConsoleLibrary must not openSettings for settings kind"
grep -q 'ConsoleSideList\|ConsoleDetailPane' "${CHOME}" \
  || die "ConsoleHome must wire SideList + DetailPane"
grep -q 'gamesList\|mediaList\|settingsList\|isStreamingApp\|isLocalPlayer' "${CAPPS}" \
  || die "ConsoleAppsModel missing list IA / streaming classifier"
grep -q 'kind: "section"\|isSection\|settingsCatalog' "${CAPPS}" \
  || die "ConsoleAppsModel Settings list must group by hub (section headers)"
grep -q 'mpv' "${CAPPS}" || die "ConsoleAppsModel must denylist mpv from Media"
grep -q 'appSeats' "${CHOME}" && die "Home still binds curated appSeats — use DesktopEntry cards"
grep -q 'searchShortcuts\|Shortcuts' "${CAPPS}" "${CHOME}" || die "Search idle shortcuts missing"
grep -q 'focusZone === "list"\|searchField\|filterField' "${CHOME}" \
  || die "ConsoleHome missing list IA focus zones"
grep -q 'Games\|Media\|Search\|Settings' "${CBAR}" \
  || die "ConsoleBar missing Games/Media/Search/Settings destinations"
grep -q 'Apps\|id: "apps"' "${CBAR}" || die "ConsoleBar missing Apps destination"
grep -q 'appsList\|isConsoleAppsDest' "${CAPPS}" \
  || die "ConsoleAppsModel missing Apps list"
grep -q 'openMediaSheet\|pickMediaFile\|launchMediaPath' "${CHOME}" "${CLIB}" \
  || die "Media seat submenu wiring missing"
grep -q 'openDetailsSheet\|ConsoleLeanSheet' "${CHOME}" || die "Details sheet missing"
grep -q 'availableSettingsPanes\|settingsList\|tab === "settings"' "${CHOME}" "${CAPPS}" \
  || die "Settings destination missing"
grep -q 'removeRecent' "${CLIB}" || die "consoleRecents remove helper missing"
[[ -x "${ROOT}/shell/scripts/proteus-pick-media" ]] || die "proteus-pick-media not executable"
ok "console list IA + submenus"

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

# Settings About hard-switch picker (soft HyprProfile stays soft)
SP="${ROOT}/shell/shared/SessionPosture.qml"
SYS="${ROOT}/apps/proteus-settings/panes/SystemPane.qml"
[[ -f "${SP}" ]] || die "missing SessionPosture.qml"
grep -q 'proteus-posture' "${SP}" || die "SessionPosture must invoke proteus-posture"
grep -q 'confirmSwitch\|requestSwitch' "${SP}" || die "SessionPosture missing confirm path"
grep -q 'hardHonesty' "${SP}" || die "SessionPosture missing hardHonesty"
grep -q 'Session posture' "${SYS}" || die "SystemPane missing Session posture group"
grep -q 'SessionPosture.requestSwitch\|SessionPosture.confirmSwitch' "${SYS}" \
  || die "SystemPane missing SessionPosture wiring"
grep -q 'Advanced · window rules\|advancedHyprOpen' "${SYS}" \
  || die "SystemPane must bury HyprProfile under Advanced · window rules"
grep -q 'HyprProfile.set' "${SYS}" || die "SystemPane soft picker must still call HyprProfile.set"
grep -q 'SessionPosture' "${ROOT}/shell/shared/SystemInfo.qml" \
  || die "SystemInfo should include hard Session posture in copy"
ok "Settings hard-switch posture picker"

EG="${ROOT}/shell/shared/EnvGate.qml"
grep -q 'postures: \["desktop"\]' "${EG}" || die "EnvGate desktop hub missing postures desktop-only"
grep -q 'postures: \["host", "desktop"\]' "${EG}" || die "EnvGate virtualization missing host+desktop postures"
grep -q 'function defaultSettingsPage' "${EG}" || die "EnvGate missing defaultSettingsPage"
grep -q 'postureAllowed(spec)' "${EG}" || die "EnvGate paneAvailable must call postureAllowed"
ok "EnvGate Settings posture gates"

KB="${ROOT}/shell/shared/Keybinds.qml"
grep -q 'entryAllowedOnPosture' "${KB}" || die "Keybinds missing entryAllowedOnPosture"
grep -q 'postures: \["desktop"\]' "${KB}" || die "Keybinds missing enter-console/host postures tags"
grep -q 'postures: \["console"\]' "${KB}" || die "Keybinds missing console-nav postures"
grep -q 'Filtered for posture' "${KB}" || die "Keybinds.confText must note posture filter"
grep -q 'Keybinds.persistAndApply' "${ROOT}/shell/surfaces/DesktopShell.qml" \
  || die "DesktopShell must re-apply keybinds on start"
grep -q 'Keybinds.persistAndApply' "${ROOT}/shell/surfaces/ConsoleShell.qml" \
  || die "ConsoleShell must re-apply keybinds on start"
grep -q 'Keybinds.persistAndApply' "${ROOT}/shell/surfaces/HostShell.qml" \
  || die "HostShell must re-apply keybinds on start"
grep -q 'proteus-posture console' "${ROOT}/env/hypr/proteus-keybinds.conf" \
  || die "seed keybinds missing enter-console"
grep -q 'proteus-posture host --chrome' "${ROOT}/env/hypr/proteus-keybinds.conf" \
  || die "seed keybinds missing enter-host --chrome"
ok "Keybinds posture filter + seed"

grep -q 'Hard switch · restarts chrome' "${ROOT}/shell/surfaces/desktop/QuickSettingsGrid.qml" \
  || die "CC tiles must say Hard switch · restarts chrome"
ok "CC hard-switch honesty"

echo "posture-hard-smoke: OK"
