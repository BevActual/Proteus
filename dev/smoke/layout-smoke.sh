#!/usr/bin/env bash
# layout-smoke — owned shell tree structure gate (QML chrome retired).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fail=0

die() { echo "layout-smoke: FAIL $*" >&2; fail=1; }
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

# Owned shell crate + face scaffold
[[ -f "${ROOT}/shell/Cargo.toml" ]] && ok "shell/Cargo.toml" || die "shell/Cargo.toml"
[[ -f "${ROOT}/shell/src/main.rs" ]] && ok "shell/src/main.rs" || die "shell/src/main.rs"
[[ -f "${ROOT}/shell/src/faces/mod.rs" ]] && ok "faces/mod.rs" || die "faces/mod.rs"
[[ -f "${ROOT}/shell/src/faces/desktop.rs" ]] && ok "faces/desktop.rs" || die "faces/desktop.rs"
[[ -f "${ROOT}/shell/src/faces/console.rs" ]] && ok "faces/console.rs" || die "faces/console.rs"
[[ -f "${ROOT}/shell/src/faces/host.rs" ]] && ok "faces/host.rs" || die "faces/host.rs"

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
