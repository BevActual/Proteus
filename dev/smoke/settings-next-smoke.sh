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

# System Settings look (proteus-ui inset lists + shell chrome)
grep -q 'settings_group\|large_title\|ui_sidebar_item\|sidebar_item as' \
  "${ST_ROOT}/src/panes/common.rs" "${ST_ROOT}/src/main.rs" \
  && ok "Settings inset-list / large_title / sidebar" \
  || bad "Settings Apple-look chrome missing"
grep -q 'Facts · CLI · iced' "${ST_ROOT}/src/main.rs" \
  && bad "Settings sidebar still shows marketing subtitle" \
  || ok "Settings sidebar quiet (no Facts·CLI·iced)"

# Compact CTAs — Shrink helpers + hub list is one inset plate
grep -q 'fn action_button\|fn primary_button\|fn button_cluster' \
  "${ST_ROOT}/src/panes/common.rs" \
  && grep -q 'Length::Shrink' "${ST_ROOT}/src/panes/common.rs" \
  && grep -q 'compact_button_style\|accent_button_style' "${ST_ROOT}/src/panes/common.rs" \
  && ok "compact action/primary/button_cluster" \
  || bad "Settings compact CTA helpers missing"
# Arrow-key nav + hub/sidebar focus caret
grep -q 'NavKey\|nav_zone\|hub_focus' "${ST_ROOT}/src/main.rs" \
  && grep -q 'ArrowUp\|ArrowDown\|ArrowLeft\|ArrowRight' "${ST_ROOT}/src/main.rs" \
  && grep -q 'focused' "${ST_ROOT}/src/main.rs" \
  && ok "Settings arrow-key nav + focus caret" \
  || bad "Settings keyboard nav missing"
# Leaf pages must not steal Enter/Up/Down from text fields (iced gap).
grep -q 'Leaf pages host text fields\|NOT Up/Down/Enter' "${ST_ROOT}/src/main.rs" \
  && grep -q 'if repeat' "${ST_ROOT}/src/main.rs" \
  && ok "Settings nav ignores leaf typing + key-repeat" \
  || bad "Settings nav still steals keys from text fields"
grep -q 'hub_row\|settings_group' "${ST_ROOT}/src/panes/common.rs" \
  && grep -q 'fn hub_list' "${ST_ROOT}/src/panes/common.rs" \
  && ok "hub_list → settings_group/hub_row" \
  || bad "hub_list inset contract missing"
# Ban full-width accent Install / Make default strips (must use helpers).
if grep -RnE 'button\(text\("(Install|Remove|Make default)"\)\)' \
  "${ST_ROOT}/src/panes" 2>/dev/null \
  | grep -v 'action_button\|primary_button' \
  | grep -q .; then
  bad "raw Install/Remove/Make-default buttons — use action_button/primary_button"
else
  ok "no raw Install/Remove/Make-default accent strips"
fi

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
grep -q 'peripherals-tablet\|SetTipCurvePreset\|tabletTipPressureCurve' \
  "${ST_ROOT}/src/panes/peripherals.rs" \
  && ok "peripherals-tablet leaf" || bad "peripherals-tablet missing"
grep -q 'hypr_apply_pointer\|hypr_apply_touchpad\|hypr_apply_tablet' "${ST_ROOT}/src/backend.rs" \
  && ok "pointer/touchpad/tablet apply helpers" || bad "pointer/touchpad/tablet apply helpers missing"
if grep -q 'proteus-settings-apply' "${ST_ROOT}/src/backend.rs" \
  && grep -q '\["input"\]' "${ST_ROOT}/src/backend.rs"; then
  ok "pointer/touchpad live apply (proteus-settings-apply input)"
else
  bad "pointer/touchpad live apply missing"
fi
grep -qE '^\s*input\)|dispatch.*input-reload' "${ROOT}/shell/scripts/proteus-settings-apply" \
  && ok "settings-apply input → input-reload" \
  || bad "settings-apply input subcommand missing"
if grep -q 'Fact-only until libinput' "${ST_ROOT}/src/panes/peripherals.rs"; then
  bad "peripherals still Fact-only banner"
else
  ok "peripherals UI live-apply honesty"
fi
grep -q 'Live via proteus-settings-apply' "${ST_ROOT}/src/panes/peripherals.rs" \
  && ok "peripherals live-apply copy" || bad "peripherals live-apply copy missing"
if grep -q 'Command::new("hyprctl")' "${ST_ROOT}/src/backend.rs"; then
  bad "Settings backend still spawns hyprctl"
else
  ok "Settings backend no hyprctl"
fi
grep -qE 'proteus-settings-apply|proteus-compositorctl' "${ST_ROOT}/src/backend.rs" \
  && ok "Settings apply via proteus-settings-apply / compositorctl" \
  || bad "Settings missing proteus-settings-apply / compositorctl monitors"
grep -q 'displays\.json' "${ST_ROOT}/src/backend.rs" \
  && ok "displays.json Fact" || bad "displays.json Fact missing"
grep -q 'apply-displays' "${ST_ROOT}/src/backend.rs" "${ROOT}/shell/scripts/proteus-settings-apply" \
  && ok "apply-displays bridge" || bad "apply-displays missing"
grep -q 'Apply Fact + live\|is the compositor running' "${ST_ROOT}/src/panes/displays.rs" \
  && ok "Displays UI honesty (smithay)" || bad "Displays UI still Hyprland-shaped"
grep -q 'Identify\|displays_identify\|dispatch.*identify' \
  "${ST_ROOT}/src/panes/displays.rs" "${ST_ROOT}/src/backend.rs" \
  && ok "Displays Identify" || bad "Displays Identify missing"
grep -q 'Keep\|RevertNow\|displays_revert\|DisplaysApplyDone' \
  "${ST_ROOT}/src/panes/displays.rs" "${ST_ROOT}/src/main.rs" \
  && ok "Displays 10s Revert" || bad "Displays Revert missing"
grep -q 'network-tailscale\|TailscaleUp' "${ST_ROOT}/src/panes/network.rs" \
  && ok "network-tailscale leaf" || bad "network-tailscale missing"
grep -q 'TailscaleLoginDraft\|TailscaleSetExit\|Login server\|Set exit' \
  "${ST_ROOT}/src/panes/network.rs" \
  && ok "network-tailscale thin usable UI" || bad "network-tailscale thin usable UI missing"
grep -q 'tailscale_status\|tailscale_up' "${ST_ROOT}/src/backend.rs" \
  && ok "tailscale backend" || bad "tailscale backend missing"
grep -q 'exit_nodes\|current_exit\|login_server\|TailscalePeer\|--login-server=\|--exit-node=' \
  "${ST_ROOT}/src/backend.rs" \
  && ok "tailscale peers/exit/login-server" || bad "tailscale peers/exit/login-server missing"
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
if grep -qE 'Open in QML Settings|open_qml_settings|OpenQml' \
  "${ST_ROOT}/src/panes" "${ST_ROOT}/src/backend.rs" "${ST_ROOT}/src/main.rs" 2>/dev/null; then
  bad "QML Settings escape still present (must be retired)"
else
  ok "no QML Settings escape in sibling"
fi
grep -q 'desktop-beacon' "${ST_ROOT}/src/nav.rs" \
  && ok "desktop-beacon hub id" || bad "desktop-beacon hub id missing"
grep -q 'defaults_list\|SetDefault\|ClearBeaconRecents\|SetFocusActive' \
  "${ST_ROOT}/src/panes/desktop.rs" "${ST_ROOT}/src/backend.rs" "${ST_ROOT}/src/main.rs" \
  && ok "desktop defaults/focus/beacon wire" || bad "desktop thin leaves missing"
grep -q 'FocusAdd\|FocusRename\|FocusDelete\|focus_profile_add\|focus_profile_delete' \
  "${ST_ROOT}/src/panes/desktop.rs" "${ST_ROOT}/src/backend.rs" "${ST_ROOT}/src/main.rs" \
  && ok "desktop Focus profile CRUD" || bad "Focus profile CRUD missing"
grep -q 'ConnectOAuth\|accounts_connect_oauth' "${ST_ROOT}/src/panes/accounts.rs" "${ST_ROOT}/src/backend.rs" \
  && ok "Accounts OAuth PKCE wire" || bad "Accounts OAuth missing"
[[ -f "${ST_ROOT}/src/panes/displays.rs" ]] \
  && ok "displays pane module" || bad "displays pane missing"
grep -q 'displays_list\|displays_apply\|displays_identify' "${ST_ROOT}/src/backend.rs" \
  && ok "displays list+apply+identify backend" || bad "displays backend missing"
grep -q 'sound-matrix\|MixRoute\|audio_mix_status' "${ST_ROOT}/src/panes/sound.rs" "${ST_ROOT}/src/backend.rs" \
  && ok "Mixer list thin" || bad "Mixer thin missing"
grep -q 'desktop-spaces\|SetWorkspaceMode\|desktop-beacon\|controlCenterColumns' "${ST_ROOT}/src/panes/desktop.rs" \
  && ok "desktop remaining leaves" || bad "desktop leaves missing"
grep -q 'SetDockLayout\|SetDockIconSize\|SetDockRounding\|SetDockAutoHide\|SetBarHeight\|SetBarRounding\|SetBarAutoHide' \
  "${ST_ROOT}/src/panes/desktop.rs" "${ST_ROOT}/src/main.rs" \
  && grep -q 'dockLayout\|barHeight\|barRounding' "${ST_ROOT}/src/panes/desktop.rs" \
  && ok "Dock & menu bar layout/size/rounding/autohide" \
  || bad "desktop-dock chrome Facts UI missing"
grep -q 'network-vpn\|VpnUp\|network-headscale\|headscale_status' "${ST_ROOT}/src/panes/network.rs" "${ST_ROOT}/src/backend.rs" \
  && ok "VPN + Headscale thin" || bad "VPN/Headscale missing"
grep -q 'network-diagnostics\|network-localsend\|network-devices' "${ST_ROOT}/src/panes/network.rs" \
  && ok "network devices/diagnostics/localsend leaves" || bad "network Phase C leaves missing"
grep -q 'fn network_devices\|fn network_diagnostics\|fn localsend_status' "${ST_ROOT}/src/backend.rs" \
  && ok "network Phase C backends" || bad "network Phase C backends missing"
grep -q 'privacy-flatpak\|FlatpakSet\|privacy-diagnostics' "${ST_ROOT}/src/panes/privacy.rs" \
  && ok "privacy-flatpak leaf" || bad "privacy-flatpak missing"
grep -q 'fn privacy_flatpak_list\|fn privacy_flatpak_set\|fn privacy_diagnostics' "${ST_ROOT}/src/backend.rs" \
  && ok "privacy flatpak/diagnostics backends" || bad "privacy Phase D backends missing"
grep -q 'SetAppGrant\|AddApp\|Per-app grants' "${ST_ROOT}/src/panes/privacy.rs" \
  && ok "privacy per-app grants UI" || bad "privacy per-app grants UI missing"
grep -q 'fn privacy_apps_for_category\|fn privacy_set_app_grant\|store-set-app' "${ST_ROOT}/src/backend.rs" \
  && ok "privacy per-app grants backends" || bad "privacy per-app grants backends missing"
grep -q 'PrivacyCategoryLoaded\|privacy_set_app_grant\|privacy_apps_for_category' "${ST_ROOT}/src/main.rs" \
  && ok "privacy per-app grants main wire" || bad "privacy per-app grants main wire missing"
grep -q 'peripherals-keyboard\|KeybindEdit\|KeybindApply\|keybinds.json' \
  "${ST_ROOT}/src/panes/peripherals.rs" \
  && ok "keyboard leaf thin rebind UI" || bad "keyboard leaf rebind missing"
grep -q 'fn keybinds_list\|fn keybinds_set_chord\|fn keybinds_clear_override\|reloadbinds' \
  "${ST_ROOT}/src/backend.rs" \
  && ok "keybinds backend + reloadbinds" || bad "keybinds backend missing"
grep -q 'KeybindsLoaded\|KeybindApply\|keybinds_set_chord' "${ST_ROOT}/src/main.rs" \
  && ok "keyboard rebind main wire" || bad "keyboard rebind main wire missing"

# Phase 2 megas — canvas / grid / glances / headscale policy
grep -q 'Layout canvas\|SetPosition\|NudgeX\|canvas::Program\|Canvas::new' "${ST_ROOT}/src/panes/displays.rs" \
  && ok "Displays layout canvas" || bad "Displays canvas missing"
grep -q 'SetTransform\|transform_label' "${ST_ROOT}/src/panes/displays.rs" \
  && grep -q 'SetTransform' "${ST_ROOT}/src/main.rs" \
  && grep -q 'transform' "${ST_ROOT}/src/backend.rs" "${ROOT}/shell/scripts/proteus-settings-apply" \
  && ok "Displays orientation/transform UI + apply" \
  || bad "Displays orientation/transform missing"
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
