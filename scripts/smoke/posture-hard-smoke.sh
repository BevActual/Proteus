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
APPLY="${ROOT}/vm/guest/apply-console-kit.sh"
[[ -x "${LAUNCH}" ]] || die "proteus-console-launch not executable"
[[ -x "${APPLY}" ]] || die "apply-console-kit.sh not executable"
bash -n "${LAUNCH}" || die "proteus-console-launch bash -n"
bash -n "${APPLY}" || die "apply-console-kit.sh bash -n"
set +e
"${LAUNCH}" >/dev/null 2>&1
lec=$?
set -e
[[ "${lec}" -eq 2 ]] || die "proteus-console-launch usage should exit 2 (got ${lec})"
grep -q 'gamescope' "${ROOT}/vm/install/proteus-desktop.packages" || die "gamescope not in desktop packages"
grep -q 'python-evdev' "${ROOT}/vm/install/proteus-desktop.packages" || die "python-evdev not in desktop packages"
grep -q 'proteus-console-launch' "${ROOT}/shell/surfaces/console/ConsoleLibrary.qml" \
  || grep -q 'launchBin' "${ROOT}/shell/surfaces/console/ConsoleLibrary.qml" \
  || die "ConsoleLibrary missing launch helper wiring"
[[ -f "${ROOT}/shell/surfaces/console/ConsoleAppsModel.qml" ]] || die "ConsoleAppsModel.qml missing"
ok "console launch kit + Library model"

grep -q 'function pad' "${ROOT}/shell/surfaces/DesktopShell.qml" || die "DesktopShell missing chrome pad IPC"
grep -q 'function pad' "${ROOT}/shell/surfaces/ConsoleShell.qml" || die "ConsoleShell missing chrome pad IPC"
grep -q 'handlePad' "${ROOT}/shell/shared/ShellState.qml" || die "ShellState missing handlePad"
grep -q 'padWanted' "${ROOT}/vm/guest/proteus-guide" || die "proteus-guide missing padWanted poll"
ok "chrome pad IPC contract"

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
grep -q 'steam' "${ROOT}/vm/install/proteus-desktop.packages" || die "steam not in desktop packages"
grep -q 'retroarch' "${ROOT}/vm/install/proteus-desktop.packages" || die "retroarch not in desktop packages"
grep -q 'consoleRecents' "${ROOT}/shell/shared/Config.qml" || die "Config missing consoleRecents"
ok "webapp + Steam/Retro + consoleRecents"

echo "posture-hard-smoke: OK"
