#!/usr/bin/env bash
# Host-side sanity check for the overlay tree (no guest, no pacman).
# Usage: ./vm/install/check.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALL="${ROOT}/vm/install"
fail=0

ok() { echo "  OK  $*"; }
bad() { echo "  FAIL $*"; fail=1; }

echo "==> proteus install tree check (${ROOT})"

[[ -x "${INSTALL}/bootstrap.sh" ]] || chmod +x "${INSTALL}/bootstrap.sh" 2>/dev/null || true
[[ -f "${INSTALL}/helpers.sh" ]] && ok helpers.sh || bad helpers.sh
[[ -f "${INSTALL}/proteus-base.packages" ]] && ok proteus-base.packages || bad proteus-base.packages
[[ -f "${INSTALL}/proteus-desktop.packages" ]] && ok proteus-desktop.packages || bad proteus-desktop.packages
[[ -f "${INSTALL}/proteus-console.packages" ]] && ok proteus-console.packages || bad proteus-console.packages

for stage in preflight packaging config hardware login apps desktop console post-install; do
  if [[ -f "${INSTALL}/${stage}.sh" ]]; then
    if bash -n "${INSTALL}/${stage}.sh" 2>/dev/null; then
      ok "stage ${stage}.sh"
    else
      bad "stage ${stage}.sh (bash -n)"
    fi
  else
    bad "missing ${stage}.sh"
  fi
done

for hw in virt nvidia amd intel; do
  [[ -f "${INSTALL}/hardware/${hw}.sh" ]] && ok "hardware/${hw}.sh" || bad "hardware/${hw}.sh"
done

base_n="$(grep -cEv '^\s*(#|$)' "${INSTALL}/proteus-base.packages" || true)"
desk_n="$(grep -cEv '^\s*(#|$)' "${INSTALL}/proteus-desktop.packages" || true)"
cons_n="$(grep -cEv '^\s*(#|$)' "${INSTALL}/proteus-console.packages" 2>/dev/null || true)"
ok "base packages: ${base_n}"
ok "desktop packages: ${desk_n}"
ok "console packages: ${cons_n}"
[[ "${base_n}" -ge 5 ]] || bad "base package list looks too thin"
[[ "${cons_n:-0}" -ge 5 ]] || bad "console package list looks too thin"

# Roster split: console seats live in proteus-console.packages (multilib),
# never in the desktop list where steam silently fails.
for pkg in steam retroarch gamescope game-devices-udev; do
  grep -qE "^${pkg}\$" "${INSTALL}/proteus-console.packages" 2>/dev/null \
    && ok "console list has ${pkg}" || bad "console list missing ${pkg}"
done
for pkg in steam retroarch gamescope; do
  grep -qE "^${pkg}\$" "${INSTALL}/proteus-desktop.packages" \
    && bad "desktop list still carries ${pkg} (belongs in proteus-console.packages)" \
    || ok "desktop list free of ${pkg}"
done

# Repair preset + update pass + console stage wired into bootstrap
grep -q 'PROTEUS_INSTALL_REPAIR' "${INSTALL}/bootstrap.sh" \
  && ok "bootstrap repair preset" || bad "bootstrap missing PROTEUS_INSTALL_REPAIR"
grep -q 'PROTEUS_INSTALL_UPDATE' "${INSTALL}/bootstrap.sh" \
  && ok "bootstrap update pass" || bad "bootstrap missing PROTEUS_INSTALL_UPDATE"
grep -qE 'STAGES=\(.*console.*\)' "${INSTALL}/bootstrap.sh" \
  && ok "bootstrap stage list has console" || bad "bootstrap stage list missing console"

# Shared helper linker (live-tree symlinks; stale /usr/local/bin bug class)
grep -q 'proteus_install_helper' "${INSTALL}/helpers.sh" \
  && ok "helpers.sh proteus_install_helper" || bad "helpers.sh missing proteus_install_helper"
grep -q 'proteus_install_helper' "${INSTALL}/apps.sh" \
  && ok "apps.sh uses proteus_install_helper" || bad "apps.sh must use proteus_install_helper"
grep -q 'proteus_install_helper' "${ROOT}/vm/guest/apply-console-kit.sh" \
  && ok "apply-console-kit uses shared helper" || bad "apply-console-kit must use proteus_install_helper"

# Console stage contents: multilib + kit + posture/profile drift fix
grep -q 'multilib' "${INSTALL}/console.sh" \
  && ok "console.sh multilib" || bad "console.sh missing multilib enable"
grep -q 'apply-console-kit.sh' "${INSTALL}/console.sh" \
  && ok "console.sh applies console kit" || bad "console.sh missing apply-console-kit"
grep -q 'set-hypr-profile.sh' "${INSTALL}/console.sh" \
  && ok "console.sh drift fix" || bad "console.sh missing posture/profile drift fix"
grep -q 'console.sh' "${ROOT}/vm/guest/install-console-software.sh" \
  && ok "install-console-software → console stage" || bad "install-console-software must wrap console stage"

# Host provision: read-only status mode; qemu-img must not choke on a running VM
grep -q '^  status) status ;;' "${ROOT}/vm/provision.sh" \
  && ok "provision.sh status mode" || bad "provision.sh missing status mode"
grep -q 'qemu-img info -U' "${ROOT}/vm/provision.sh" \
  && ok "provision.sh qemu-img -U (running-VM safe)" || bad "provision.sh qemu-img needs -U"

# Install path SoT doc
[[ -f "${ROOT}/docs/proteus/INSTALL.md" ]] && ok docs/proteus/INSTALL.md || bad "missing docs/proteus/INSTALL.md"
grep -q 'guest-install.sh' "${ROOT}/docs/proteus/INSTALL.md" 2>/dev/null \
  && grep -q 'bootstrap.sh repair' "${ROOT}/docs/proteus/INSTALL.md" 2>/dev/null \
  && ok "INSTALL.md covers layers + repair" || bad "INSTALL.md must cover three layers + repair"

[[ -f "${ROOT}/env/hypr/hyprland.conf" ]] && ok env/hypr/hyprland.conf || bad env/hypr/hyprland.conf
[[ -f "${ROOT}/env/hypr/proteus-profile.conf" ]] && ok env/hypr/proteus-profile.conf || bad env/hypr/proteus-profile.conf
[[ -f "${ROOT}/env/hypr/profiles/desktop.conf" ]] && ok env/hypr/profiles/desktop.conf || bad env/hypr/profiles/desktop.conf
[[ -f "${ROOT}/env/hypr/profiles/console.conf" ]] && ok env/hypr/profiles/console.conf || bad env/hypr/profiles/console.conf
[[ -x "${ROOT}/vm/guest/proteus-posture" ]] && ok vm/guest/proteus-posture || bad vm/guest/proteus-posture
[[ -x "${ROOT}/vm/guest/proteus-guide" ]] && ok vm/guest/proteus-guide || bad vm/guest/proteus-guide
[[ -x "${ROOT}/vm/guest/apply-console-kit.sh" ]] && ok vm/guest/apply-console-kit.sh || bad vm/guest/apply-console-kit.sh
[[ -x "${ROOT}/shell/scripts/proteus-console-launch" ]] && ok shell/scripts/proteus-console-launch || bad shell/scripts/proteus-console-launch
[[ -x "${ROOT}/shell/scripts/proteus-console-seat" ]] && ok shell/scripts/proteus-console-seat || bad shell/scripts/proteus-console-seat
[[ -x "${ROOT}/shell/scripts/proteus-workspace" ]] && ok shell/scripts/proteus-workspace || bad shell/scripts/proteus-workspace
[[ -x "${ROOT}/shell/scripts/proteus-console-capabilities" ]] && ok shell/scripts/proteus-console-capabilities || bad shell/scripts/proteus-console-capabilities
[[ -x "${ROOT}/shell/scripts/proteus-console-session" ]] && ok shell/scripts/proteus-console-session || bad shell/scripts/proteus-console-session
[[ -x "${ROOT}/vm/guest/dogfood-console.sh" ]] && ok vm/guest/dogfood-console.sh || bad vm/guest/dogfood-console.sh
grep -q 'proteus-console-seat' "${ROOT}/vm/install/apps.sh" && ok "apps.sh installs proteus-console-seat" || bad "apps.sh missing proteus-console-seat"
grep -q 'proteus-console-capabilities' "${ROOT}/vm/install/apps.sh" && ok "apps.sh installs proteus-console-capabilities" || bad "apps.sh missing proteus-console-capabilities"
grep -q 'proteus-console-launch' "${ROOT}/vm/install/apps.sh" && ok "apps.sh installs proteus-console-launch" || bad "apps.sh missing proteus-console-launch"
grep -q 'proteus-console-session' "${ROOT}/vm/install/apps.sh" && ok "apps.sh installs proteus-console-session" || bad "apps.sh missing proteus-console-session"
grep -q 'install-console-software' "${ROOT}/vm/guest/apply-console-kit.sh" \
  && ok "apply-console-kit cites install-console-software" || bad "apply-console-kit must cite full console install"
[[ -x "${ROOT}/shell/scripts/proteus-permissions.py" ]] && ok shell/scripts/proteus-permissions.py || bad shell/scripts/proteus-permissions.py
[[ -x "${ROOT}/shell/scripts/privacy-indicators.py" ]] && ok shell/scripts/privacy-indicators.py || bad shell/scripts/privacy-indicators.py
[[ -x "${ROOT}/shell/scripts/proteus-defaults.py" ]] && ok shell/scripts/proteus-defaults.py || bad shell/scripts/proteus-defaults.py
[[ -x "${ROOT}/shell/scripts/beacon-file-index.py" ]] && ok shell/scripts/beacon-file-index.py || bad shell/scripts/beacon-file-index.py
grep -q 'beacon-file-index.py' "${ROOT}/vm/install/apps.sh" && ok "apps.sh installs beacon-file-index.py" || bad "apps.sh missing beacon-file-index.py"
[[ -x "${ROOT}/shell/scripts/proteus-pin.py" ]] && ok shell/scripts/proteus-pin.py || bad shell/scripts/proteus-pin.py
[[ -x "${ROOT}/shell/scripts/check-unlock.py" ]] && ok shell/scripts/check-unlock.py || bad shell/scripts/check-unlock.py
[[ -f "${ROOT}/shell/scripts/proteus_auth.py" ]] && ok shell/scripts/proteus_auth.py || bad shell/scripts/proteus_auth.py
[[ -f "${ROOT}/shell/pam/proteus-lock" ]] && ok shell/pam/proteus-lock || bad shell/pam/proteus-lock
[[ -x "${ROOT}/vm/guest/install-lock-pam.sh" ]] && ok vm/guest/install-lock-pam.sh || bad vm/guest/install-lock-pam.sh
grep -q 'proteus-pin.py' "${ROOT}/vm/install/apps.sh" && ok "apps.sh installs proteus-pin.py" || bad "apps.sh missing proteus-pin.py"
grep -q 'check-unlock.py' "${ROOT}/vm/install/apps.sh" && ok "apps.sh installs check-unlock.py" || bad "apps.sh missing check-unlock.py"
grep -q 'install-lock-pam' "${ROOT}/vm/install/apps.sh" && ok "apps.sh cites install-lock-pam" || bad "apps.sh missing install-lock-pam"
if bash -n "${ROOT}/vm/guest/apply-console-kit.sh" 2>/dev/null; then
  ok "apply-console-kit.sh bash -n"
else
  bad "apply-console-kit.sh (bash -n)"
fi
if bash -n "${ROOT}/shell/scripts/proteus-console-launch" 2>/dev/null; then
  ok "proteus-console-launch bash -n"
else
  bad "proteus-console-launch (bash -n)"
fi
if bash -n "${ROOT}/shell/scripts/proteus-console-seat" 2>/dev/null; then
  ok "proteus-console-seat bash -n"
else
  bad "proteus-console-seat (bash -n)"
fi
if bash -n "${ROOT}/shell/scripts/proteus-workspace" 2>/dev/null; then
  ok "proteus-workspace bash -n"
else
  bad "proteus-workspace (bash -n)"
fi
if bash -n "${ROOT}/shell/scripts/proteus-console-capabilities" 2>/dev/null; then
  ok "proteus-console-capabilities bash -n"
else
  bad "proteus-console-capabilities (bash -n)"
fi
if python3 -m py_compile "${ROOT}/shell/scripts/proteus-permissions.py" 2>/dev/null; then
  ok "proteus-permissions.py py_compile"
else
  bad "proteus-permissions.py (py_compile)"
fi
if python3 -m py_compile "${ROOT}/shell/scripts/privacy-indicators.py" 2>/dev/null; then
  ok "privacy-indicators.py py_compile"
else
  bad "privacy-indicators.py (py_compile)"
fi
if python3 "${ROOT}/shell/scripts/proteus-permissions.py" --help >/dev/null 2>&1; then
  ok "proteus-permissions.py --help"
else
  bad "proteus-permissions.py (--help)"
fi
if python3 -m py_compile "${ROOT}/shell/scripts/proteus-defaults.py" 2>/dev/null; then
  ok "proteus-defaults.py py_compile"
else
  bad "proteus-defaults.py (py_compile)"
fi
if python3 -m py_compile "${ROOT}/shell/scripts/beacon-file-index.py" 2>/dev/null; then
  ok "beacon-file-index.py py_compile"
else
  bad "beacon-file-index.py (py_compile)"
fi
if python3 -m py_compile "${ROOT}/shell/scripts/proteus_auth.py" 2>/dev/null; then
  ok "proteus_auth.py py_compile"
else
  bad "proteus_auth.py (py_compile)"
fi
if python3 -m py_compile "${ROOT}/shell/scripts/proteus-pin.py" 2>/dev/null; then
  ok "proteus-pin.py py_compile"
else
  bad "proteus-pin.py (py_compile)"
fi
if python3 -m py_compile "${ROOT}/shell/scripts/check-unlock.py" 2>/dev/null; then
  ok "check-unlock.py py_compile"
else
  bad "check-unlock.py (py_compile)"
fi
[[ -f "${ROOT}/env/hypr/profiles/host.conf" ]] && ok env/hypr/profiles/host.conf || bad env/hypr/profiles/host.conf
[[ -f "${ROOT}/env/hypr/profiles/home.conf" ]] && ok env/hypr/profiles/home.conf || bad env/hypr/profiles/home.conf
if [[ -f "${ROOT}/shell/scripts/proteus-qs" ]]; then
  if bash -n "${ROOT}/shell/scripts/proteus-qs" 2>/dev/null; then
    ok shell/scripts/proteus-qs
  else
    bad "shell/scripts/proteus-qs (bash -n)"
  fi
  grep -q 'flock' "${ROOT}/shell/scripts/proteus-qs" && ok "proteus-qs flock" || bad "proteus-qs missing flock"
  grep -q -- '--restart' "${ROOT}/shell/scripts/proteus-qs" && ok "proteus-qs --restart" || bad "proteus-qs missing --restart"
  grep -q 'reap_chrome' "${ROOT}/shell/scripts/proteus-qs" && ok "proteus-qs orphan reap" || bad "proteus-qs missing reap_chrome"
else
  bad shell/scripts/proteus-qs
fi
if [[ -f "${ROOT}/vm/guest/set-hypr-profile.sh" ]]; then
  if bash -n "${ROOT}/vm/guest/set-hypr-profile.sh" 2>/dev/null; then
    ok vm/guest/set-hypr-profile.sh
  else
    bad "vm/guest/set-hypr-profile.sh (bash -n)"
  fi
else
  bad vm/guest/set-hypr-profile.sh
fi
[[ -d "${ROOT}/vm/guest" ]] && ok vm/guest/ || bad vm/guest/
[[ -x "${ROOT}/vm/bootstrap.sh" || -f "${ROOT}/vm/bootstrap.sh" ]] && ok vm/bootstrap.sh || bad vm/bootstrap.sh
[[ -f "${ROOT}/vm/provision.sh" ]] && ok vm/provision.sh || bad vm/provision.sh
[[ -f "${ROOT}/vm/guest/install-icons.sh" ]] && ok vm/guest/install-icons.sh || bad vm/guest/install-icons.sh
[[ -f "${ROOT}/brand/proteus-mark.svg" ]] && ok brand/proteus-mark.svg || bad brand/proteus-mark.svg
grep -q '^Icon=proteus-settings' "${ROOT}/apps/proteus-settings/proteus-settings.desktop" && ok "settings.desktop Icon" || bad "settings.desktop Icon"
grep -q '^Icon=proteus' "${ROOT}/vm/guest/proteus.desktop" && ok "session.desktop Icon" || bad "session.desktop Icon"

# #1168 — seed hyprland.conf: qs/bg/cliphist present; no terminal exec-once
HYPR_SEED="${ROOT}/env/hypr/hyprland.conf"
if [[ -f "${HYPR_SEED}" ]]; then
  grep -qE '^[[:space:]]*exec-once[[:space:]].*proteus-qs' "${HYPR_SEED}" \
    && ok "hypr seed proteus-qs exec-once" || bad "hypr seed missing proteus-qs exec-once"
  grep -qE '^[[:space:]]*exec-once[[:space:]].*proteus-bg' "${HYPR_SEED}" \
    && ok "hypr seed proteus-bg exec-once" || bad "hypr seed missing proteus-bg exec-once"
  grep -q 'cliphist store' "${HYPR_SEED}" \
    && ok "hypr seed cliphist exec-once" || bad "hypr seed missing cliphist"
  grep -q 'hyprpolkitagent' "${HYPR_SEED}" \
    && ok "hypr seed polkit agent exec-once" || bad "hypr seed missing hyprpolkitagent"
  # Settings is a normal app window now — the old float+center popup rule
  # must NOT come back (it made Settings a centered sheet).
  grep -q 'Proteus Settings' "${HYPR_SEED}" \
    && bad "hypr seed still has legacy Settings float rule" \
    || ok "hypr seed has no Settings float rule (normal window)"
  if grep -qiE '^[[:space:]]*exec-once[[:space:]]*=.*(ghostty|kitty|alacritty|foot|proteus-terminal|wezterm)' "${HYPR_SEED}"; then
    bad "hypr seed must not exec-once a terminal"
  else
    ok "hypr seed no terminal exec-once"
  fi
  grep -qi 'do not exec-once' "${HYPR_SEED}" \
    && ok "hypr seed terminal comment lock" || bad "hypr seed missing terminal comment lock"
fi

HIDE="${ROOT}/vm/guest/hide-system-apps.sh"
if [[ -f "${HIDE}" ]]; then
  if bash -n "${HIDE}" 2>/dev/null; then
    ok "hide-system-apps.sh bash -n"
  else
    bad "hide-system-apps.sh (bash -n)"
  fi
  for app in pavucontrol nm-connection-editor blueman-manager quickshell; do
    grep -q "hide ${app} " "${HIDE}" || grep -qE "hide ${app}\"" "${HIDE}" \
      || grep -q "hide ${app} " "${HIDE}" \
      || true
    if grep -qE "hide ${app}( |$)" "${HIDE}" || grep -q "hide ${app} " "${HIDE}"; then
      ok "hide-system-apps targets ${app}"
    elif grep -q "hide ${app}" "${HIDE}"; then
      ok "hide-system-apps targets ${app}"
    else
      bad "hide-system-apps missing hide ${app}"
    fi
  done
  grep -q 'NoDisplay=true' "${HIDE}" && ok "hide-system-apps NoDisplay" || bad "hide-system-apps NoDisplay"
  grep -q 'install-settings-app.sh' "${ROOT}/vm/install/apps.sh" \
    && grep -q 'install-workloads-app.sh' "${ROOT}/vm/install/apps.sh" \
    && grep -q 'hide-system-apps.sh' "${ROOT}/vm/install/apps.sh" \
    && ok "apps.sh invokes hide-system-apps + workloads" || bad "apps.sh must invoke hide-system-apps + workloads"
  grep -q 'hide-system-apps.sh' "${ROOT}/vm/install/post-install.sh" \
    && ok "post-install refreshes hide-system-apps" || bad "post-install missing hide-system-apps"
else
  bad "missing hide-system-apps.sh"
fi


UNIT="${ROOT}/env/systemd/user/proteus-qs.service"
if [[ -f "${UNIT}" ]]; then
  grep -q 'proteus-qs' "${UNIT}" && ok "proteus-qs.service template" || bad "proteus-qs.service ExecStart"
  grep -q 'WantedBy=graphical-session.target' "${UNIT}" && ok "proteus-qs.service WantedBy" || bad "proteus-qs.service WantedBy"
  grep -qiE '^IgnorePkg|pacman.*IgnorePkg' "${UNIT}" && bad "unit must not IgnorePkg-pin" || ok "proteus-qs.service no IgnorePkg pin"
else
  bad "missing env/systemd/user/proteus-qs.service"
fi
INST="${ROOT}/vm/guest/install-proteus-qs-user-unit.sh"
if [[ -f "${INST}" ]]; then
  bash -n "${INST}" 2>/dev/null && ok "install-proteus-qs-user-unit.sh bash -n" || bad "install-proteus-qs-user-unit.sh bash -n"
  grep -q 'proteus-qs.service' "${INST}" && ok "install-proteus-qs-user-unit installs unit" || bad "install script missing unit"
else
  bad "missing install-proteus-qs-user-unit.sh"
fi

# shellcheck source=helpers.sh
source "${INSTALL}/helpers.sh"
export PROTEUS_ROOT="${ROOT}"
PROTEUS_INSTALL_STATUS_DIR="${TMPDIR:-/tmp}/proteus-install-check-$$"
export PROTEUS_INSTALL_STATUS_DIR
mkdir -p "${PROTEUS_INSTALL_STATUS_DIR}"
proteus_status_ensure
proteus_stage_done_mark check-selftest
[[ -f "${PROTEUS_INSTALL_STATUS_DIR}/check-selftest.done" ]] && ok "status markers" || bad "status markers"
rm -rf "${PROTEUS_INSTALL_STATUS_DIR}"

echo
if [[ "${fail}" -eq 0 ]]; then
  echo "==> check OK"
  exit 0
fi
echo "==> check FAILED"
exit 1
