#!/usr/bin/env bash
# layout-smoke — owned shell tree structure gate (QML chrome retired).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fail=0

bad() { echo "layout-smoke: FAIL $*" >&2; fail=1; }
die() { bad "$*"; } # accumulate (do not exit)
ok() { echo "layout-smoke: OK $*"; }

# Retired QML trees must stay gone
for d in shared surfaces wallpaper console-home; do
  if [[ -e "${ROOT}/shell/${d}" ]]; then
    die "retired QML path must not exist: shell/${d}"
  else
    ok "no shell/${d}"
  fi
done
if [[ -e "${ROOT}/shell/shell.qml" ]]; then
  die "shell/shell.qml must be retired"
else
  ok "no shell.qml"
fi
if [[ -d "${ROOT}/apps/proteus-settings" ]]; then
  die "apps/proteus-settings QML must be retired"
else
  ok "no apps/proteus-settings"
fi
if [[ -d "${ROOT}/shell-next" ]]; then
  die "shell-next must be renamed to shell/"
else
  ok "no shell-next"
fi
if [[ -d "${ROOT}/compositor-next" ]]; then
  die "compositor-next must be renamed to compositor/"
else
  ok "no compositor-next"
fi
[[ -f "${ROOT}/compositor/Cargo.toml" ]] && ok "compositor/Cargo.toml" || die "compositor/Cargo.toml"

# Owned shell crate + face scaffold
[[ -f "${ROOT}/shell/Cargo.toml" ]] && ok "shell/Cargo.toml" || die "shell/Cargo.toml"
[[ -f "${ROOT}/shell/src/main.rs" ]] && ok "shell/src/main.rs" || die "shell/src/main.rs"
[[ -f "${ROOT}/shell/src/app/mod.rs" ]] && ok "app/mod.rs" || die "app/mod.rs"
[[ -f "${ROOT}/shell/src/platform/mod.rs" ]] && ok "platform/mod.rs" || die "platform/mod.rs"
[[ -f "${ROOT}/shell/src/app/state.rs" ]] && ok "app/state.rs" || die "app/state.rs"
[[ -f "${ROOT}/shell/src/app/update.rs" ]] && ok "app/update.rs" || die "app/update.rs"
[[ -f "${ROOT}/shell/src/app/view.rs" ]] && ok "app/view.rs" || die "app/view.rs"
[[ -f "${ROOT}/shell/src/app/layers.rs" ]] && ok "app/layers.rs" || die "app/layers.rs"
[[ -f "${ROOT}/shell/src/app/handlers/mod.rs" ]] && ok "handlers/mod.rs" || die "handlers/mod.rs"
for h in overlays spaces dock lock widgets system; do
  [[ -f "${ROOT}/shell/src/app/handlers/${h}.rs" ]] \
    && ok "handlers/${h}.rs" || die "handlers/${h}.rs"
done
[[ -f "${ROOT}/shell/src/app/runtime.rs" ]] && ok "app/runtime.rs" || die "app/runtime.rs"
[[ -f "${ROOT}/shell/src/app/subscription.rs" ]] && ok "app/subscription.rs" || die "app/subscription.rs"
[[ -f "${ROOT}/shell/src/faces/mod.rs" ]] && ok "faces/mod.rs" || die "faces/mod.rs"
[[ -f "${ROOT}/shell/src/faces/desktop/mod.rs" ]] && ok "faces/desktop/mod.rs" || die "faces/desktop/mod.rs"
[[ -f "${ROOT}/shell/src/faces/console/mod.rs" ]] && ok "faces/console/mod.rs" || die "faces/console/mod.rs"
[[ -f "${ROOT}/shell/src/faces/host/mod.rs" ]] && ok "faces/host/mod.rs" || die "faces/host/mod.rs"
[[ -f "${ROOT}/shell/src/surfaces/mod.rs" ]] && ok "surfaces/mod.rs" || die "surfaces/mod.rs"
for surf in bar dock beacon control_center hub hud toast privacy lock wallpaper widgets; do
  [[ -f "${ROOT}/shell/src/surfaces/${surf}.rs" ]] \
    && ok "surfaces/${surf}.rs" || die "surfaces/${surf}.rs"
done

# Non-QML runtime assets kept under shell/
[[ -d "${ROOT}/shell/scripts" ]] && ok "shell/scripts" || die "shell/scripts"
[[ -d "${ROOT}/shell/pam" ]] && ok "shell/pam" || die "shell/pam"
[[ -d "${ROOT}/shell/assets" ]] && ok "shell/assets" || die "shell/assets"
[[ -x "${ROOT}/shell/scripts/proteus-chrome" ]] && ok "proteus-chrome" || die "proteus-chrome"
if [[ -e "${ROOT}/shell/scripts/proteus-qs" ]]; then
  die "proteus-qs must be retired"
else
  ok "no proteus-qs"
fi

# Workspace member
grep -q '"shell"' "${ROOT}/Cargo.toml" && ok "workspace member shell" || die "workspace missing shell"

if [[ "${fail}" -ne 0 ]]; then
  echo "layout-smoke: FAILED"
  exit 1
fi
echo "layout-smoke: OK"
