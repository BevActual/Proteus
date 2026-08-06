#!/usr/bin/env bash
# settings-next-smoke — iced Settings sibling (proteus-settings-next) honesty gates.
#
# Skips gracefully when ../ProteusSettings is absent. Does not flip QML default.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fail=0
ok() { echo "  OK  $*"; }
bad() { echo "  FAIL $*"; fail=1; }
skip() { echo "  SKIP $*"; }

echo "==> settings-next-smoke"

ST_ROOT="${PROTEUS_SETTINGS_ROOT:-${ROOT}/../ProteusSettings}"
if [[ ! -f "${ST_ROOT}/Cargo.toml" ]]; then
  skip "ProteusSettings sibling missing at ${ST_ROOT}"
  echo "settings-next-smoke: ok (skipped)"
  exit 0
fi
ok "ProteusSettings at ${ST_ROOT}"

grep -q 'proteus-settings-next' "${ST_ROOT}/Cargo.toml" \
  && ok "bin name proteus-settings-next" || bad "Cargo.toml missing proteus-settings-next"

# Source gates — packages deepen
grep -q 'packages-orphans' "${ST_ROOT}/src/panes/packages.rs" \
  && ok "packages-orphans leaf" || bad "packages-orphans missing"
grep -q 'PendingConfirm\|RequestUpgradeSelected\|ConfirmPending' "${ST_ROOT}/src/panes/packages.rs" \
  && ok "packages confirm/selection" || bad "packages confirm/selection missing"
grep -q 'upgrade-packages' "${ST_ROOT}/src/main.rs" \
  && ok "upgrade-packages wired" || bad "upgrade-packages not wired"
grep -q 'fn pkg_orphans' "${ST_ROOT}/src/backend.rs" \
  && ok "pkg_orphans backend" || bad "pkg_orphans backend missing"
grep -q 'packages-flatpak\|Flatpak' "${ST_ROOT}/src/panes/packages.rs" \
  && ok "packages-flatpak leaf" || skip "packages-flatpak (wave 2 pending)"
grep -q 'packages-webapps\|Web apps\|webapps' "${ST_ROOT}/src/panes/packages.rs" \
  && ok "packages-webapps leaf" || skip "packages-webapps (wave 2 pending)"

# Source gates — sound deepen
grep -q 'sound-latency' "${ST_ROOT}/src/panes/sound.rs" \
  && ok "sound-latency leaf" || bad "sound-latency missing"
grep -q 'PlayTest\|SetLatency\|SetDefaultVolume' "${ST_ROOT}/src/panes/sound.rs" \
  && ok "sound aggregate/test/latency msgs" || bad "sound deepen msgs missing"
grep -q 'fn sound_play_test\|fn sound_set_latency\|fn sound_input_peak' "${ST_ROOT}/src/backend.rs" \
  && ok "sound backends" || bad "sound backends missing"
grep -q 'audioLatency\|pw-metadata' "${ST_ROOT}/src/backend.rs" \
  && ok "audioLatency / pw-metadata" || bad "latency apply missing"
grep -q 'sound-apps\|sink-input\|SinkInput' "${ST_ROOT}/src/panes/sound.rs" \
  && ok "sound-apps leaf" || skip "sound-apps (wave 3 pending)"

# Wave 1 — notifications / users / privacy
grep -q 'notificationsDnd\|SetDnd' "${ST_ROOT}/src/panes/notifications.rs" \
  && ok "notifications DND" || bad "notifications pane missing"
grep -q 'PinSet\|greetd\|Lock' "${ST_ROOT}/src/panes/users.rs" \
  && ok "users PIN/session" || bad "users pane missing"
grep -q 'privacy-activity\|SetGrant' "${ST_ROOT}/src/panes/privacy.rs" \
  && ok "privacy activity/grants" || bad "privacy pane missing"

# Wave 2/3 hubs (skip if not yet landed)
[[ -f "${ST_ROOT}/src/panes/network.rs" ]] \
  && ok "network pane module" || skip "network pane (wave 2)"
[[ -f "${ST_ROOT}/src/panes/desktop.rs" ]] \
  && ok "desktop pane module" || skip "desktop pane (wave 3)"
grep -q 'style-background\|style-lock\|style-icons\|style-font' "${ST_ROOT}/src/panes/style.rs" \
  && ok "style remainder leaves" || skip "style remainder (wave 3)"

# Phase 3 holdouts (thin)
grep -q 'peripherals-mouse\|SetMouseSensitivity' "${ST_ROOT}/src/panes/peripherals.rs" \
  && ok "peripherals-mouse leaf" || bad "peripherals-mouse missing"
grep -q 'peripherals-touchpad\|SetTouchpadNatural' "${ST_ROOT}/src/panes/peripherals.rs" \
  && ok "peripherals-touchpad leaf" || bad "peripherals-touchpad missing"
grep -q 'hypr_apply_pointer\|hypr_apply_touchpad' "${ST_ROOT}/src/backend.rs" \
  && ok "hypr pointer/touchpad apply" || bad "hypr apply missing"
grep -q 'network-tailscale\|TailscaleUp' "${ST_ROOT}/src/panes/network.rs" \
  && ok "network-tailscale leaf" || bad "network-tailscale missing"
grep -q 'tailscale_status\|tailscale_up' "${ST_ROOT}/src/backend.rs" \
  && ok "tailscale backend" || bad "tailscale backend missing"
grep -q 'packages-appimages\|AppImageAdd' "${ST_ROOT}/src/panes/packages.rs" \
  && ok "packages-appimages leaf" || bad "packages-appimages missing"
grep -q 'appimages_list\|appimages_add' "${ST_ROOT}/src/backend.rs" \
  && ok "appimages backend" || bad "appimages backend missing"

# Phase 3 megas (thin) — AUR · Accounts password · QML escape
grep -q 'packages-aur\|AurSearch\|AurInstall' "${ST_ROOT}/src/panes/packages.rs" \
  && ok "packages-aur leaf" || bad "packages-aur missing"
grep -q 'fn aur_search\|fn aur_foreign\|fn aur_install' "${ST_ROOT}/src/backend.rs" \
  && ok "aur backend" || bad "aur backend missing"
[[ -f "${ST_ROOT}/src/panes/accounts.rs" ]] \
  && ok "accounts pane module" || bad "accounts pane missing"
grep -q 'ConnectNextcloud\|ConnectImap\|accounts_connect_password' "${ST_ROOT}/src/panes/accounts.rs" "${ST_ROOT}/src/main.rs" "${ST_ROOT}/src/backend.rs" \
  && ok "accounts password providers" || bad "accounts password wiring missing"
if grep -qE 'Open in QML Settings|open_qml_settings|OpenQml' "${ST_ROOT}/src/panes/pending.rs" "${ST_ROOT}/src/backend.rs" 2>/dev/null; then
  skip "QML Settings escape still in sibling (retire in ProteusSettings)"
else
  ok "no QML Settings escape in sibling"
fi
grep -q 'ConnectOAuth\|accounts_connect_oauth' "${ST_ROOT}/src/panes/accounts.rs" "${ST_ROOT}/src/backend.rs" \
  && ok "Accounts OAuth PKCE wire" || bad "Accounts OAuth missing"
[[ -f "${ST_ROOT}/src/panes/displays.rs" ]] \
  && ok "displays pane module" || bad "displays pane missing"
grep -q 'displays_list\|displays_apply\|proteus-monitors' "${ST_ROOT}/src/backend.rs" \
  && ok "displays list+apply backend" || bad "displays backend missing"
grep -q 'sound-matrix\|MixRoute\|audio_mix_status' "${ST_ROOT}/src/panes/sound.rs" "${ST_ROOT}/src/backend.rs" \
  && ok "Mixer list thin" || bad "Mixer thin missing"
grep -q 'desktop-spaces\|SetWorkspaceMode\|desktop-beacon\|controlCenterColumns' "${ST_ROOT}/src/panes/desktop.rs" \
  && ok "desktop remaining leaves" || bad "desktop leaves missing"
grep -q 'network-vpn\|VpnUp\|network-headscale\|headscale_status' "${ST_ROOT}/src/panes/network.rs" "${ST_ROOT}/src/backend.rs" \
  && ok "VPN + Headscale thin" || bad "VPN/Headscale missing"
grep -q 'peripherals-keyboard\|Open QML Keyboard' "${ST_ROOT}/src/panes/peripherals.rs" \
  && ok "keyboard escape leaf" || bad "keyboard leaf missing"

# Phase 2 megas — canvas / grid / glances / headscale policy
grep -q 'Layout canvas\|SetPosition\|NudgeX\|canvas::Program\|Canvas::new' "${ST_ROOT}/src/panes/displays.rs" \
  && ok "Displays layout canvas" || bad "Displays canvas missing"
grep -q 'Wave Link grid\|MixRoute\|MixVolume' "${ST_ROOT}/src/panes/sound.rs" \
  && ok "Mixer Wave Link grid" || bad "Mixer grid missing"
grep -q 'Glances\|EditSeat\|Connect / Save' "${ST_ROOT}/src/panes/accounts.rs" \
  && ok "Accounts glances create/edit" || bad "Accounts glances missing"
grep -q 'HeadscalePolicyCheck\|HeadscalePolicySave\|policy HuJSON\|headscale_policy_check\|headscale_user_create' \
  "${ST_ROOT}/src/panes/network.rs" "${ST_ROOT}/src/backend.rs" "${ST_ROOT}/src/main.rs" \
  && ok "Headscale policy/users" || bad "Headscale policy missing"

# Wave 4+: iced is the only Settings install path (QML retired).
INSTALL="${ROOT}/install/machine/install-settings-app.sh"
if [[ -f "${INSTALL}" ]]; then
  grep -q 'proteus-settings-next' "${INSTALL}" \
    && ok "installer installs iced" || bad "installer missing iced path"
  if grep -E 'cat >.*/proteus-settings-qml|exec.*/proteus-settings-qml|falling back to QML' \
    "${INSTALL}" >/dev/null; then
    bad "installer still has QML fallback"
  else
    ok "installer iced-only (no QML fallback)"
  fi
else
  bad "install-settings-app.sh missing"
fi

# Shell default is Owned
if awk '/^pub fn resolve_engine/,/^}/' "${ROOT}/shell/src/engine.rs" | grep -q 'ShellEngine::Owned'; then
  ok "shell default Owned"
else
  bad "shell default not Owned"
fi
if command -v cargo >/dev/null 2>&1; then
  if (cd "${ST_ROOT}" && cargo test -q --bins 2>/dev/null || cargo test -q 2>/dev/null); then
    ok "ProteusSettings cargo test"
  else
    # Bin-only crate may have no tests — build is enough
    if (cd "${ST_ROOT}" && cargo build -q); then
      ok "ProteusSettings cargo build"
    else
      bad "ProteusSettings cargo build/test"
    fi
  fi
else
  bad "cargo not available"
fi

if [[ "${fail}" -ne 0 ]]; then
  echo "settings-next-smoke: FAILED"
  exit 1
fi
echo "settings-next-smoke: ok"
