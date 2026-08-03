#!/usr/bin/env bash
# Host-side sanity check for the overlay tree (no guest, no pacman).
# Usage: ./install/check.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL="${ROOT}/install"
fail=0

ok() { echo "  OK  $*"; }
bad() { echo "  FAIL $*"; fail=1; }

echo "==> proteus install tree check (${ROOT})"

[[ -x "${INSTALL}/bootstrap.sh" ]] || chmod +x "${INSTALL}/bootstrap.sh" 2>/dev/null || true
[[ -f "${INSTALL}/helpers.sh" ]] && ok helpers.sh || bad helpers.sh
[[ -f "${INSTALL}/proteus-base.packages" ]] && ok proteus-base.packages || bad proteus-base.packages
[[ -f "${INSTALL}/proteus-desktop.packages" ]] && ok proteus-desktop.packages || bad proteus-desktop.packages
[[ -f "${INSTALL}/proteus-console.packages" ]] && ok proteus-console.packages || bad proteus-console.packages

for stage in preflight snapshots packaging config hardware login apps desktop console host post-install; do
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

for hw in virt cpu nvidia amd intel; do
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
grep -qE 'STAGES=\(.*snapshots.*\)' "${INSTALL}/bootstrap.sh" \
  && ok "bootstrap stage list has snapshots" || bad "bootstrap stage list missing snapshots"

# Shared helper linker (live-tree symlinks; stale /usr/local/bin bug class)
grep -q 'proteus_install_helper' "${INSTALL}/helpers.sh" \
  && ok "helpers.sh proteus_install_helper" || bad "helpers.sh missing proteus_install_helper"

# --- bare metal: install root must not be hardcoded to the VM 9p share --------
# The symlink-vs-copy decision keyed off a literal /mnt/proteus, so every helper
# was silently copied (and went stale) on a bare-metal tree.
grep -q 'src}" == "${live_root}"' "${INSTALL}/helpers.sh" \
  && ok "helper linker keys off PROTEUS_ROOT (not literal /mnt/proteus)" \
  || bad "helper linker still hardcodes /mnt/proteus for the symlink test"
grep -q 'proteus_write_root_fact' "${INSTALL}/helpers.sh" \
  && ok "helpers.sh proteus_write_root_fact" || bad "helpers.sh missing proteus_write_root_fact"
grep -q 'proteus_write_root_fact' "${INSTALL}/config.sh" \
  && ok "config stage writes the root Fact" || bad "config stage does not write ~/.config/proteus/root"
grep -qE 'env = PROTEUS_ROOT,' "${INSTALL}/config.sh" \
  && ok "config stage seeds hypr env = PROTEUS_ROOT" || bad "config stage missing hypr PROTEUS_ROOT env"

SESSION_BIN="${ROOT}/shell/scripts/proteus-session"
if [[ -f "${SESSION_BIN}" ]]; then
  grep -q 'proteus/root' "${SESSION_BIN}" \
    && ok "proteus-session reads the root Fact" \
    || bad "proteus-session cannot resolve the root Fact (greetd starts it with a clean env)"
  grep -q '_proteus_root_valid' "${SESSION_BIN}" \
    && ok "proteus-session validates each root candidate" \
    || bad "proteus-session missing root validation (a stale Fact would strand the session)"
else
  bad "missing shell/scripts/proteus-session"
fi

# Self-locating helpers must resolve symlinks — /usr/local/bin entries are
# symlinks into the tree, so dirname without readlink yields /usr/local/bin.
if grep -rl 'dirname "${BASH_SOURCE\[0\]}"' "${ROOT}/install/machine" "${ROOT}/shell/scripts" 2>/dev/null | grep -q .; then
  bad "self-locating helpers still use dirname without readlink -f"
else
  ok "self-locating helpers resolve symlinks (readlink -f)"
fi

# --- layout split: install/ vs dev/vm/ vs shell/scripts ---------------------------
# dev/vm/ is one kind of machine, not the install path. Runtime helpers live with
# every other PATH helper; install/machine/ holds install-time mutators only.
[[ -d "${ROOT}/dev/vm/guest" ]] && bad "dev/vm/guest still exists (moved to install/machine + shell/scripts)" \
  || ok "dev/vm/guest gone"
[[ -d "${ROOT}/dev/vm/install" ]] && bad "dev/vm/install still exists (moved to install/)" \
  || ok "dev/vm/install gone"
[[ -d "${ROOT}/install/machine" ]] && ok "install/machine present" || bad "install/machine missing"
[[ -d "${ROOT}/dev/dogfood" ]] && ok "dev/dogfood present" || bad "dev/dogfood missing"

# --- product vs maintainer boundary -------------------------------------------
# Everything under dev/ is maintainer tooling and must never be installed onto a
# machine. The root holds product directories only, so "what ships" is legible
# from `ls` rather than from tribal knowledge.
for d in vm smoke dogfood spike fixtures; do
  [[ -d "${ROOT}/dev/${d}" ]] && ok "dev/${d} present" || bad "dev/${d} missing"
done
[[ -f "${ROOT}/dev/smoke-all.sh" ]] && ok "dev/smoke-all.sh entry point" || bad "dev/smoke-all.sh missing"
for stale in "${ROOT}/scripts" "${ROOT}/tests" "${ROOT}/vm"; do
  [[ -e "${stale}" ]] && bad "$(basename "${stale}")/ still at repo root (moved under dev/)" || true
done
ok "repo root is product-only (dev/ holds maintainer tooling)"

# The installer must never EXECUTE anything from dev/ — that would make a real
# machine depend on maintainer tooling. Mentioning a dev/ path in an echo or log
# line is fine (those are operator hints), so this matches invocation only.
#
# Deliberately narrow: an earlier version of this check matched `2>/dev/null`
# (the device, not the directory) and, under `pipefail`, `grep -q`'s early exit
# made the pipeline return non-zero — so it reported OK while real references
# existed. A gate that cannot fail is worse than no gate.
# Lines that only *print* a dev/ path (echo/printf/log hints telling the operator
# what to run next) are fine — filter those before judging.
dev_exec="$(grep -rnE '(bash|source|exec|\.)[[:space:]]+[^[:space:]]*(^|/)dev/' \
  "${INSTALL}" --include='*.sh' 2>/dev/null \
  | grep -vE ':[[:space:]]*#' \
  | grep -vE ':[[:space:]]*(echo|printf|proteus_log|log)[[:space:]]' || true)"
if [[ -n "${dev_exec}" ]]; then
  bad "install/ executes something from dev/ (maintainer tooling must not be installed)"
  printf '%s\n' "${dev_exec}" | head -3
else
  ok "install/ never executes anything from dev/"
fi

for h in proteus-session proteus-posture proteus-host-seat proteus-guide proteus-bg set-hypr-profile.sh; do
  if [[ -f "${ROOT}/shell/scripts/${h}" ]]; then
    ok "runtime helper shell/scripts/${h}"
  else
    bad "runtime helper ${h} not in shell/scripts"
  fi
  [[ -e "${ROOT}/install/machine/${h}" ]] \
    && bad "install/machine still carries runtime helper ${h}" || true
done

# install/machine holds executable mutators; data files live in machine/assets.
for f in "${ROOT}"/install/machine/*; do
  base="$(basename "${f}")"
  [[ "${base}" == "assets" ]] && continue
  case "${base}" in
    install-*.sh|apply-*.sh|hide-system-apps.sh|ensure-flathub.sh|repair-*.sh) ;;
    *) bad "install/machine/${base} is not a mutator script (data files belong in machine/assets/)" ;;
  esac
done
[[ -d "${ROOT}/install/machine/assets" ]] && ok "install/machine/assets present" \
  || bad "install/machine/assets missing"
ok "install/machine holds mutator scripts only"

# The layout split moved runtime helpers out of install/machine, but scripts
# there resolve siblings relative to their own directory — apply-greeter.sh went
# on installing ${ROOT}/proteus-session from a path that no longer had it.
for h in proteus-session proteus-posture proteus-host-seat proteus-guide proteus-bg set-hypr-profile.sh; do
  if grep -rlE '\$\{(ROOT|HERE)\}/'"${h}"'\b' "${ROOT}/install/machine" 2>/dev/null | grep -q .; then
    bad "install/machine script resolves ${h} from its own dir (it lives in shell/scripts)"
  fi
done
ok "install/machine resolves runtime helpers from shell/scripts"

# Stale-symlink migration guard for installs made before the split.
grep -q 'prune_dangling_helpers' "${INSTALL}/apps.sh" \
  && ok "apps stage prunes dangling helper symlinks" \
  || bad "apps stage missing dangling-symlink prune (pre-split installs break)"

# No source file may reference the retired paths. `:!` excludes this checker,
# whose own failure message necessarily contains the strings it looks for.
if git -C "${ROOT}" grep -qE 'dev/vm/(guest/|install/)' -- . ':!install/check.sh' 2>/dev/null; then
  bad "tree still references the retired overlay paths (see: git grep -nE 'dev/vm/(guest/|install/)')"
else
  ok "no references to the retired overlay paths"
fi

# --- unattended VM install wiring ---------------------------------------------
# auto-install.py sat orphaned for weeks. It is wired now but UNPROVEN, so gate
# the contract between its three moving parts rather than the behaviour: the
# path it drives, the socket run.sh must expose, and the dispatch that calls it.
AUTOINST="${ROOT}/dev/vm/auto-install.py"
if [[ -f "${AUTOINST}" ]]; then
  python3 -m py_compile "${AUTOINST}" 2>/dev/null \
    && ok "auto-install.py compiles" || bad "auto-install.py py_compile"
  grep -q 'dev/vm/guest-install.sh' "${AUTOINST}" \
    && ok "auto-install drives the real guest-install path" \
    || bad "auto-install.py points at a stale guest-install path"
  grep -q 'PROTEUS_VM_SERIAL' "${ROOT}/dev/vm/run.sh" \
    && ok "run.sh exposes the serial socket auto-install needs" \
    || bad "run.sh no longer exposes PROTEUS_VM_SERIAL"
  grep -q 'fresh) fresh ;;' "${ROOT}/dev/vm/provision.sh" \
    && ok "provision.sh dispatches fresh" || bad "provision.sh fresh mode not wired"
  grep -q 'UNPROVEN' "${ROOT}/dev/vm/provision.sh" \
    && ok "fresh mode is labelled unproven" \
    || bad "fresh mode lost its unproven caveat (it has not been run end-to-end)"
else
  bad "dev/vm/auto-install.py missing"
fi

# --- snapshots (bare-metal rollback net) --------------------------------------
SNAP_HELPER="${ROOT}/shell/scripts/proteus-snapshot"
[[ -x "${SNAP_HELPER}" ]] && ok "proteus-snapshot helper executable" \
  || bad "proteus-snapshot missing or not executable"
grep -q 'proteus-snapshot' "${INSTALL}/apps.sh" \
  && ok "apps stage installs proteus-snapshot" || bad "apps stage does not install proteus-snapshot"
grep -q 'findmnt -no FSTYPE /' "${INSTALL}/snapshots.sh" \
  && ok "snapshots stage gates on btrfs" || bad "snapshots stage missing btrfs honesty gate"
grep -q 'snap-pac' "${INSTALL}/snapshots.sh" \
  && ok "snapshots stage installs snap-pac" || bad "snapshots stage missing snap-pac"

# --- licensing is stated once and consistently --------------------------------
# The repo previously had no LICENSE at all (so: all rights reserved by default)
# while six Cargo.toml files advertised MIT. Metadata that contradicts the actual
# licence is worse than silence, so both halves are gated.
[[ -f "${ROOT}/LICENSE" ]] && ok "LICENSE present" || bad "LICENSE missing (repo would be all-rights-reserved)"
grep -q 'SPDX-License-Identifier: GPL-3.0-only' "${ROOT}/LICENSE" 2>/dev/null \
  && ok "LICENSE declares GPL-3.0-only" || bad "LICENSE missing its SPDX identifier"
grep -q 'GNU GENERAL PUBLIC LICENSE' "${ROOT}/LICENSE" 2>/dev/null \
  && ok "LICENSE carries the full GPL text" || bad "LICENSE has no GPL body"
grep -qi 'TRADEMARKS AND BRAND' "${ROOT}/LICENSE" 2>/dev/null \
  && ok "LICENSE carves out the brand" || bad "LICENSE lost the trademark carve-out"

lic_bad=0
for c in "${ROOT}"/services/*/Cargo.toml; do
  want='license = "GPL-3.0-only"'
  grep -qF "${want}" "${c}" || {
    bad "$(basename "$(dirname "${c}")")/Cargo.toml does not declare GPL-3.0-only"
    lic_bad=1
  }
done
[[ "${lic_bad}" -eq 0 ]] && ok "every crate declares GPL-3.0-only (matches LICENSE)"

[[ -f "${ROOT}/THIRD-PARTY.md" ]] && ok "THIRD-PARTY.md present" \
  || bad "THIRD-PARTY.md missing (what Proteus is built on)"

# --- env/ must stay adjacent to shell/ ----------------------------------------
# EnvGate resolves manifests as shellRoot + "/../env/apps/…", so env/ is a
# runtime dependency of the shell, not an install-only seed directory. Folding
# it into install/ would break the running shell, not just the installer.
[[ -f "${ROOT}/env/apps/catalog.json" ]] && ok "env/apps/catalog.json present" \
  || bad "env/apps/catalog.json missing (EnvGate resolves it at runtime)"
grep -q 'env/apps/catalog.json' "${ROOT}/shell/shared/EnvGate.qml" \
  && ok "EnvGate reads env/apps relative to shellRoot" \
  || bad "EnvGate no longer reads env/apps (runtime contract changed)"
grep -q 'env/hypr/profiles' "${ROOT}/shell/scripts/set-hypr-profile.sh" \
  && ok "posture flip installs profiles from env/hypr (runtime consumer)" \
  || bad "set-hypr-profile.sh no longer sources env/hypr/profiles"

# env/ ships data, never tooling. Keyed on the executable bit, not the file
# extension: proteus-bashrc.sh is a .sh but is *sourced* into the user's shell,
# so it is data; a generator that rewrites env/ content belongs in dev/.
env_exec="$(find "${ROOT}/env" -type f -perm -u+x 2>/dev/null || true)"
if [[ -n "${env_exec}" ]]; then
  bad "env/ contains executable tooling (generators belong in dev/)"
  printf '%s\n' "${env_exec}" | head -3
else
  ok "env/ is data only (no executables)"
fi
[[ -f "${ROOT}/dev/gen-helix-logo.py" ]] && ok "helix generator lives in dev/" \
  || bad "dev/gen-helix-logo.py missing (it regenerates env/fastfetch/proteus-helix.txt)"

# --- no hardcoded usernames in the install path -------------------------------
# A guessed username writes an entire install into the wrong home, silently,
# because every path still exists. The shared resolver refuses to guess; nothing
# under install/ may reintroduce a literal fallback. (dev/ is exempt: the VM
# harness legitimately creates a known account.)
# --exclude=check.sh: this file necessarily contains the pattern it searches for.
user_hard="$(grep -rniE '(:-|\|\||=)[[:space:]]*"?andrew"?[[:space:]]*(\}|\)|$)|/home/andrew\b' \
  "${INSTALL}" --include='*.sh' --exclude=check.sh 2>/dev/null \
  | grep -vE ':[[:space:]]*#' || true)"
if [[ -n "${user_hard}" ]]; then
  bad "install/ hardcodes a username fallback (use proteus_session_user)"
  printf '%s\n' "${user_hard}" | head -3
else
  ok "install/ has no hardcoded username fallback"
fi
grep -q 'cannot determine the session user' "${INSTALL}/helpers.sh" \
  && ok "proteus_session_user refuses to guess" \
  || bad "proteus_session_user still has a guess of last resort"
grep -q 'proteus_session_user' "${INSTALL}/preflight.sh" \
  && ok "preflight resolves the session user up front" \
  || bad "preflight does not resolve the session user (failure would land mid-install)"

# --- package names must still exist upstream ----------------------------------
# `p7zip` sat in the desktop roster long after Arch replaced it with `7zip`.
# Nothing caught it: desktop.sh silently reclassifies an unknown name as AUR and
# moves on, so a rotted package name degrades into a skipped install.
#
# Pinned to core/extra/multilib on purpose — validating against the running
# machine's repo set gives different answers per box (an [omarchy] or
# [chaotic-aur] repo resolves names a vanilla bare-metal Arch cannot).
# AUR_OK lists names we know are AUR-only and handle through the helper path.
AUR_OK=" game-devices-udev localsend-bin localsend "
if command -v pacman >/dev/null 2>&1; then
  REPO_LIST="$(pacman -Sl core extra multilib 2>/dev/null | awk '{print $2}' | sort -u || true)"
  if [[ -z "${REPO_LIST}" ]]; then
    ok "package name check SKIP (no synced core/extra/multilib db)"
  else
    pkg_bad=0
    for list in "${INSTALL}"/proteus-*.packages; do
      while read -r pkg; do
        [[ -n "${pkg}" ]] || continue
        grep -qxF "${pkg}" <<<"${REPO_LIST}" && continue
        pacman -Sg "${pkg}" >/dev/null 2>&1 && continue          # group (base-devel)
        [[ "${AUR_OK}" == *" ${pkg} "* ]] && continue            # known AUR seat
        bad "package '${pkg}' ($(basename "${list}")) is not in core/extra/multilib and is not a declared AUR seat"
        pkg_bad=1
      done < <(grep -vE '^\s*(#|$)' "${list}")
    done
    [[ "${pkg_bad}" -eq 0 ]] && ok "all package names resolve in core/extra/multilib (or are declared AUR)"
  fi
else
  ok "package name check SKIP (pacman not on this host)"
fi

# --- packages the shell actually shells out to --------------------------------
# flatpak was referenced across Software/ensure-flathub but never installed.
for pkg in flatpak upower pciutils sof-firmware; do
  grep -qxF "${pkg}" "${INSTALL}/proteus-base.packages" \
    && ok "base list has ${pkg}" || bad "base list missing ${pkg}"
done
for pkg in git base-devel; do
  grep -qxF "${pkg}" "${INSTALL}/proteus-desktop.packages" \
    && ok "desktop list has ${pkg} (AUR build chain)" || bad "desktop list missing ${pkg}"
done
grep -q 'proteus_bootstrap_aur_helper' "${INSTALL}/desktop.sh" \
  && ok "desktop stage bootstraps an AUR helper" || bad "desktop stage cannot bootstrap an AUR helper"
grep -q 'proteus_install_helper' "${INSTALL}/apps.sh" \
  && ok "apps.sh uses proteus_install_helper" || bad "apps.sh must use proteus_install_helper"
grep -q 'proteus_install_helper' "${ROOT}/install/machine/apply-console-kit.sh" \
  && ok "apply-console-kit uses shared helper" || bad "apply-console-kit must use proteus_install_helper"

# Console stage contents: multilib + kit + posture/profile drift fix
grep -q 'multilib' "${INSTALL}/console.sh" \
  && ok "console.sh multilib" || bad "console.sh missing multilib enable"
grep -q 'apply-console-kit.sh' "${INSTALL}/console.sh" \
  && ok "console.sh applies console kit" || bad "console.sh missing apply-console-kit"
grep -q 'set-hypr-profile.sh' "${INSTALL}/console.sh" \
  && ok "console.sh drift fix" || bad "console.sh missing posture/profile drift fix"

# host stage — samba usershares + smartmontools (HexOS-style dashboard backends)
[[ -f "${INSTALL}/host.sh" ]] && ok install/host.sh || bad install/host.sh
bash -n "${INSTALL}/host.sh" 2>/dev/null && ok "host.sh bash -n" || bad "host.sh (bash -n)"
[[ -f "${INSTALL}/proteus-host.packages" ]] && ok install/proteus-host.packages || bad install/proteus-host.packages
grep -q '^samba$' "${INSTALL}/proteus-host.packages" && ok "host packages: samba" || bad "host packages missing samba"
grep -q '^smartmontools$' "${INSTALL}/proteus-host.packages" && ok "host packages: smartmontools" || bad "host packages missing smartmontools"
grep -q 'console host post-install' "${INSTALL}/bootstrap.sh" && ok "bootstrap.sh runs host stage" || bad "bootstrap.sh missing host stage"
grep -q 'usershare' "${INSTALL}/host.sh" && ok "host.sh configures usershares" || bad "host.sh missing usershares"
grep -q 'sambashare' "${INSTALL}/host.sh" && ok "host.sh sambashare group" || bad "host.sh missing sambashare group"
[[ -f "${ROOT}/env/apps/host-apps.json" ]] && ok env/apps/host-apps.json || bad env/apps/host-apps.json
python3 -c "import json;json.load(open('${ROOT}/env/apps/host-apps.json'))" 2>/dev/null \
  && ok "host-apps.json parses" || bad "host-apps.json (json parse)"
grep -q 'console.sh' "${ROOT}/install/machine/install-console-software.sh" \
  && ok "install-console-software → console stage" || bad "install-console-software must wrap console stage"

# Host provision: read-only status mode; qemu-img must not choke on a running VM
grep -q '^  status) status ;;' "${ROOT}/dev/vm/provision.sh" \
  && ok "provision.sh status mode" || bad "provision.sh missing status mode"
grep -q 'qemu-img info -U' "${ROOT}/dev/vm/provision.sh" \
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
[[ -x "${ROOT}/shell/scripts/proteus-posture" ]] && ok shell/scripts/proteus-posture || bad shell/scripts/proteus-posture
[[ -x "${ROOT}/shell/scripts/proteus-host-seat" ]] && ok shell/scripts/proteus-host-seat || bad shell/scripts/proteus-host-seat
[[ -x "${ROOT}/shell/scripts/proteus-guide" ]] && ok shell/scripts/proteus-guide || bad shell/scripts/proteus-guide
[[ -x "${ROOT}/dev/dogfood/dogfood-host.sh" ]] && ok dev/dogfood/dogfood-host.sh || bad dev/dogfood/dogfood-host.sh
[[ -x "${ROOT}/install/machine/apply-console-kit.sh" ]] && ok install/machine/apply-console-kit.sh || bad install/machine/apply-console-kit.sh
[[ -x "${ROOT}/shell/scripts/proteus-console-launch" ]] && ok shell/scripts/proteus-console-launch || bad shell/scripts/proteus-console-launch
[[ -x "${ROOT}/shell/scripts/proteus-console-seat" ]] && ok shell/scripts/proteus-console-seat || bad shell/scripts/proteus-console-seat
[[ -x "${ROOT}/shell/scripts/proteus-workspace" ]] && ok shell/scripts/proteus-workspace || bad shell/scripts/proteus-workspace
[[ -x "${ROOT}/shell/scripts/proteus-console-capabilities" ]] && ok shell/scripts/proteus-console-capabilities || bad shell/scripts/proteus-console-capabilities
[[ -x "${ROOT}/shell/scripts/proteus-console-session" ]] && ok shell/scripts/proteus-console-session || bad shell/scripts/proteus-console-session
[[ -x "${ROOT}/shell/scripts/proteus-console-gs-session" ]] && ok shell/scripts/proteus-console-gs-session || bad shell/scripts/proteus-console-gs-session
[[ -x "${ROOT}/shell/scripts/proteus-console-focus" ]] && ok shell/scripts/proteus-console-focus || bad shell/scripts/proteus-console-focus
[[ -f "${ROOT}/shell/console-home/shell.qml" ]] && ok shell/console-home/shell.qml || bad shell/console-home/shell.qml
[[ -x "${ROOT}/dev/dogfood/dogfood-console.sh" ]] && ok dev/dogfood/dogfood-console.sh || bad dev/dogfood/dogfood-console.sh
grep -q 'proteus-console-seat' "${ROOT}/install/apps.sh" && ok "apps.sh installs proteus-console-seat" || bad "apps.sh missing proteus-console-seat"
grep -q 'proteus-console-capabilities' "${ROOT}/install/apps.sh" && ok "apps.sh installs proteus-console-capabilities" || bad "apps.sh missing proteus-console-capabilities"
grep -q 'proteus-console-launch' "${ROOT}/install/apps.sh" && ok "apps.sh installs proteus-console-launch" || bad "apps.sh missing proteus-console-launch"
grep -q 'proteus-console-session' "${ROOT}/install/apps.sh" && ok "apps.sh installs proteus-console-session" || bad "apps.sh missing proteus-console-session"
grep -q 'proteus-console-gs-session' "${ROOT}/install/apps.sh" && ok "apps.sh installs proteus-console-gs-session" || bad "apps.sh missing proteus-console-gs-session"
grep -q 'proteus-console-focus' "${ROOT}/install/apps.sh" && ok "apps.sh installs proteus-console-focus" || bad "apps.sh missing proteus-console-focus"
grep -q 'install-console-software' "${ROOT}/install/machine/apply-console-kit.sh" \
  && ok "apply-console-kit cites install-console-software" || bad "apply-console-kit must cite full console install"
[[ -x "${ROOT}/shell/scripts/proteus-permissions.py" ]] && ok shell/scripts/proteus-permissions.py || bad shell/scripts/proteus-permissions.py
[[ -x "${ROOT}/shell/scripts/privacy-indicators.py" ]] && ok shell/scripts/privacy-indicators.py || bad shell/scripts/privacy-indicators.py
[[ -x "${ROOT}/shell/scripts/proteus-defaults.py" ]] && ok shell/scripts/proteus-defaults.py || bad shell/scripts/proteus-defaults.py
[[ -x "${ROOT}/shell/scripts/beacon-file-index.py" ]] && ok shell/scripts/beacon-file-index.py || bad shell/scripts/beacon-file-index.py
grep -q 'beacon-file-index.py' "${ROOT}/install/apps.sh" && ok "apps.sh installs beacon-file-index.py" || bad "apps.sh missing beacon-file-index.py"
[[ -x "${ROOT}/shell/scripts/proteus-pin.py" ]] && ok shell/scripts/proteus-pin.py || bad shell/scripts/proteus-pin.py
[[ -x "${ROOT}/shell/scripts/check-unlock.py" ]] && ok shell/scripts/check-unlock.py || bad shell/scripts/check-unlock.py
[[ -x "${ROOT}/shell/scripts/proteus-host-metrics.py" ]] && ok shell/scripts/proteus-host-metrics.py || bad shell/scripts/proteus-host-metrics.py
grep -q 'proteus-host-metrics.py' "${ROOT}/install/apps.sh" && ok "apps.sh installs proteus-host-metrics.py" || bad "apps.sh missing proteus-host-metrics.py"
[[ -x "${ROOT}/shell/scripts/proteus-console-games.py" ]] && ok shell/scripts/proteus-console-games.py || bad shell/scripts/proteus-console-games.py
grep -q 'proteus-console-games.py' "${ROOT}/install/apps.sh" && ok "apps.sh installs proteus-console-games.py" || bad "apps.sh missing proteus-console-games.py"
[[ -f "${ROOT}/shell/scripts/proteus_auth.py" ]] && ok shell/scripts/proteus_auth.py || bad shell/scripts/proteus_auth.py
[[ -f "${ROOT}/shell/pam/proteus-lock" ]] && ok shell/pam/proteus-lock || bad shell/pam/proteus-lock
[[ -x "${ROOT}/install/machine/install-lock-pam.sh" ]] && ok install/machine/install-lock-pam.sh || bad install/machine/install-lock-pam.sh
grep -q 'proteus-pin.py' "${ROOT}/install/apps.sh" && ok "apps.sh installs proteus-pin.py" || bad "apps.sh missing proteus-pin.py"
grep -q 'check-unlock.py' "${ROOT}/install/apps.sh" && ok "apps.sh installs check-unlock.py" || bad "apps.sh missing check-unlock.py"
grep -q 'install-lock-pam' "${ROOT}/install/apps.sh" && ok "apps.sh cites install-lock-pam" || bad "apps.sh missing install-lock-pam"
if bash -n "${ROOT}/install/machine/apply-console-kit.sh" 2>/dev/null; then
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
if python3 -m py_compile "${ROOT}/shell/scripts/proteus-host-metrics.py" 2>/dev/null; then
  ok "proteus-host-metrics.py py_compile"
else
  bad "proteus-host-metrics.py (py_compile)"
fi
if python3 -m py_compile "${ROOT}/shell/scripts/proteus-console-games.py" 2>/dev/null; then
  ok "proteus-console-games.py py_compile"
else
  bad "proteus-console-games.py (py_compile)"
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
if [[ -f "${ROOT}/shell/scripts/set-hypr-profile.sh" ]]; then
  if bash -n "${ROOT}/shell/scripts/set-hypr-profile.sh" 2>/dev/null; then
    ok shell/scripts/set-hypr-profile.sh
  else
    bad "shell/scripts/set-hypr-profile.sh (bash -n)"
  fi
else
  bad shell/scripts/set-hypr-profile.sh
fi
[[ -d "${ROOT}/install/machine" ]] && ok install/machine/ || bad install/machine/
[[ -x "${ROOT}/dev/vm/bootstrap.sh" || -f "${ROOT}/dev/vm/bootstrap.sh" ]] && ok dev/vm/bootstrap.sh || bad dev/vm/bootstrap.sh
[[ -f "${ROOT}/dev/vm/provision.sh" ]] && ok dev/vm/provision.sh || bad dev/vm/provision.sh
[[ -f "${ROOT}/install/machine/install-icons.sh" ]] && ok install/machine/install-icons.sh || bad install/machine/install-icons.sh
[[ -f "${ROOT}/brand/proteus-mark.svg" ]] && ok brand/proteus-mark.svg || bad brand/proteus-mark.svg
grep -q '^Icon=proteus-settings' "${ROOT}/apps/proteus-settings/proteus-settings.desktop" && ok "settings.desktop Icon" || bad "settings.desktop Icon"
grep -q '^Icon=proteus' "${ROOT}/install/machine/assets/proteus.desktop" && ok "session.desktop Icon" || bad "session.desktop Icon"

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

HIDE="${ROOT}/install/machine/hide-system-apps.sh"
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
  grep -q 'install-settings-app.sh' "${ROOT}/install/apps.sh" \
    && grep -q 'install-workloads-app.sh' "${ROOT}/install/apps.sh" \
    && grep -q 'hide-system-apps.sh' "${ROOT}/install/apps.sh" \
    && ok "apps.sh invokes hide-system-apps + workloads" || bad "apps.sh must invoke hide-system-apps + workloads"
  grep -q 'hide-system-apps.sh' "${ROOT}/install/post-install.sh" \
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
INST="${ROOT}/install/machine/install-proteus-qs-user-unit.sh"
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
