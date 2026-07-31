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

for stage in preflight packaging config hardware login apps desktop post-install; do
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
ok "base packages: ${base_n}"
ok "desktop packages: ${desk_n}"
[[ "${base_n}" -ge 5 ]] || bad "base package list looks too thin"

[[ -f "${ROOT}/env/hypr/hyprland.conf" ]] && ok env/hypr/hyprland.conf || bad env/hypr/hyprland.conf
[[ -f "${ROOT}/env/hypr/proteus-profile.conf" ]] && ok env/hypr/proteus-profile.conf || bad env/hypr/proteus-profile.conf
[[ -f "${ROOT}/env/hypr/profiles/desktop.conf" ]] && ok env/hypr/profiles/desktop.conf || bad env/hypr/profiles/desktop.conf
[[ -f "${ROOT}/env/hypr/profiles/media.conf" ]] && ok env/hypr/profiles/media.conf || bad env/hypr/profiles/media.conf
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
    && grep -q 'hide-system-apps.sh' "${ROOT}/vm/install/apps.sh" \
    && ok "apps.sh invokes hide-system-apps" || bad "apps.sh must invoke hide-system-apps"
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
