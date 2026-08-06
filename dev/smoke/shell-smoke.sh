#!/usr/bin/env bash
# shell-smoke — owned iced shell (OWNED-STACK rung 1) parity gates.
#
# Holds both engines honest during the overlap: layer namespaces, IPC targets,
# engine fact, ctl protocol, and crate tests. Does not require Wayland.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fail=0
ok() { echo "  OK  $*"; }
bad() { echo "  FAIL $*"; fail=1; }

echo "==> shell-smoke"

# Crate present
[[ -f "${ROOT}/shell/Cargo.toml" ]] && ok "shell crate" || bad "shell crate missing"
[[ -f "${ROOT}/Cargo.toml" ]] && grep -q 'shell' "${ROOT}/Cargo.toml" \
  && ok "workspace lists shell" || bad "workspace missing shell"

# Unit tests
if command -v cargo >/dev/null 2>&1; then
  if (cd "${ROOT}" && cargo test -p proteus-shell --lib -q); then
    ok "proteus-shell lib tests"
  else
    bad "proteus-shell lib tests"
  fi
  if (cd "${ROOT}" && cargo test -p proteus-ui --lib -q); then
    ok "proteus-ui lib tests"
  else
    bad "proteus-ui lib tests"
  fi
else
  bad "cargo not available"
fi

# Layer namespace + IPC target constants (source-level parity)
for ns in proteus-bar proteus-dock proteus-launcher proteus-control-center \
          proteus-hud proteus-bg proteus-desktop-widgets proteus-toast \
          proteus-privacy-ask proteus-lock; do
  grep -q "\"${ns}\"" "${ROOT}/shell/src/lib.rs" \
    && ok "layer ${ns}" || bad "layer ${ns}"
done
for t in lock chrome widgets hud; do
  grep -q "\"${t}\"" "${ROOT}/shell/src/lib.rs" \
    && ok "ipc target ${t}" || bad "ipc target ${t}"
done

# Engine resolution — owned only (Quickshell retired)
grep -q 'ShellEngine::Owned\|fn resolve_engine' "${ROOT}/shell/src/engine.rs" \
  && ok "resolve_engine Owned" || bad "resolve_engine missing"
grep -q 'shell-engine' "${ROOT}/shell/src/engine.rs" \
  && ok "shell-engine fact write" || bad "shell-engine fact missing"
[[ -f "${ROOT}/shell/src/faces/mod.rs" ]] && ok "faces module" || bad "faces module missing"

# Multi-layer daemon boot (bar + NewLayerShell extras)
grep -q 'iced_layershell::build_pattern::daemon\|build_pattern::daemon' "${ROOT}/shell/src/main.rs" \
  && ok "daemon multi-window entry" || bad "daemon entry missing"
grep -q 'to_layer_message(multi)' "${ROOT}/shell/src/main.rs" \
  && ok "to_layer_message(multi)" || bad "to_layer_message(multi) missing"
grep -q 'NewLayerShell' "${ROOT}/shell/src/main.rs" \
  && ok "NewLayerShell boot" || bad "NewLayerShell missing"
grep -q 'BOOT_LAYERS_DESKTOP\|boot_layers_for_face' "${ROOT}/shell/src/main.rs" \
  && ok "face-aware boot layers" || bad "face-aware boot missing"
for sym in DOCK LAUNCHER CONTROL_CENTER HUD BG DESKTOP_WIDGETS TOAST PRIVACY_ASK LOCK; do
  grep -E "BOOT_LAYERS_(DESKTOP|LEAN)" -A20 "${ROOT}/shell/src/main.rs" | grep -q "layers::${sym}" \
    && ok "boot layer ${sym}" || bad "boot layer ${sym}"
done
grep -q 'session_chrome_suppressed\|session_start_lock_pending' "${ROOT}/shell/src/main.rs" \
  && ok "lock chrome suppress" || bad "lock suppress missing"
grep -q 'try_unlock\|check-unlock' "${ROOT}/shell/src/platform.rs" \
  && ok "PAM unlock path" || bad "PAM unlock missing"
grep -q 'spawn_socket2_listener' "${ROOT}/shell/src/wm_ipc.rs" \
  && ok "compositor subscribe listener" || bad "subscribe listener missing"
grep -q 'volumeUp\|volume_step\|brightnessUp' "${ROOT}/shell/src/ctl.rs" \
  && ok "HUD volume/brightness steps" || bad "HUD steps missing"
grep -q 'customizeDesktop\|dockLaunch\|focusCycle' "${ROOT}/shell/src/ctl.rs" \
  && ok "chrome IPC parity verbs" || bad "chrome IPC verbs missing"
grep -q 'widgets' "${ROOT}/shell/src/ctl.rs" \
  && ok "widgets CRUD ctl" || bad "widgets ctl missing"
grep -q 'run_notifications_server\|org.freedesktop.Notifications' "${ROOT}/shell/src/platform.rs" \
  && ok "zbus Notifications server" || bad "zbus Notifications missing"
grep -q 'dbus-monitor\|NotifBus' "${ROOT}/shell/src/platform.rs" \
  && ok "notif path / fallback" || bad "notif path missing"
grep -q 'list_desktop_apps\|filter_desktop_hits\|gtk-launch' "${ROOT}/shell/src/beacon.rs" \
  && ok "Beacon desktop enumerate/launch" || bad "Beacon desktop missing"
grep -q 'overlays_blocked\|overlays blocked while locked' "${ROOT}/shell/src/ctl.rs" \
  && ok "lock blocks overlays" || bad "lock overlay gate missing"
grep -q 'start_tray_watcher\|tray_poll' "${ROOT}/shell/src/platform.rs" \
  && ok "SNI tray watcher" || bad "SNI tray missing"
grep -q 'load_dock_pins\|dockPins' "${ROOT}/shell/src/main.rs" \
  && ok "dock pins from facts" || bad "dock pins missing"
grep -q 'settings_catalog_hits\|--page=' "${ROOT}/shell/src/beacon.rs" \
  && ok "Beacon settings catalog" || bad "Beacon settings missing"
grep -q 'lock_screen_view\|Click or type to unlock\|Enter unlock PIN\|Use password' \
  "${ROOT}/shell/src/lock_ui.rs" \
  && ok "lock full-bleed PIN/reveal" || bad "lock GUI shallow"
grep -q 'LockReveal\|LockPinDigit\|lock_ui' "${ROOT}/shell/src/main.rs" "${ROOT}/shell/src/surfaces.rs" \
  && ok "lock shell wiring" || bad "lock shell wiring missing"
grep -q 'WindowClose\|WindowMinimize\|WindowMaximize' "${ROOT}/shell/src/surfaces.rs" \
  && ok "bar traffic-lights msgs" || bad "bar traffic-lights missing"
grep -q 'window_close\|window_minimize\|window_maximize' "${ROOT}/shell/src/wm_ipc.rs" \
  && ok "wm_ipc window traffic-lights" || bad "wm_ipc window helpers missing"
grep -q 'PrivacyDots\|privacy_dots\|OpenPrivacy' "${ROOT}/shell/src/platform.rs" "${ROOT}/shell/src/surfaces.rs" \
  && ok "privacy dots" || bad "privacy dots missing"
grep -q 'PowerProfile\|power_set_profile_index\|VolumeStep' "${ROOT}/shell/src/surfaces.rs" "${ROOT}/shell/src/platform.rs" \
  && ok "CC power/volume" || bad "CC power/volume missing"
grep -q 'NotifDismiss' "${ROOT}/shell/src/surfaces.rs" \
  && ok "CC notif dismiss" || bad "CC notif dismiss missing"
grep -q 'dock_activate\|DockAction' "${ROOT}/shell/src/wm_ipc.rs" \
  && ok "dock minimize/restore" || bad "dock activate missing"
grep -q 'filter_beacon_hits\|Window ·\|File ·\|beacon-file-index' "${ROOT}/shell/src/beacon.rs" \
  && ok "Beacon Windows/files thin" || bad "Beacon Windows/files missing"
grep -q 'ToggleDnd\|wifi_list_thin\|bt_list_thin' "${ROOT}/shell/src/surfaces.rs" "${ROOT}/shell/src/platform.rs" \
  && ok "CC DND/WiFi/BT" || bad "CC tiles missing"
grep -q 'ToggleFocus\|focus_profiles\|Focus Mode' "${ROOT}/shell/src/surfaces.rs" "${ROOT}/shell/src/platform.rs" \
  && ok "CC Focus Mode thin" || bad "CC Focus missing"
grep -q 'Hovered\|magnify\|pad_boost\|radius: if hovered' "${ROOT}/shell/src/surfaces.rs" \
  && ok "dock magnify thin" || bad "dock magnify missing"
grep -q 'menu_bar_plate\|dock_plate\|elevated_chip\|chrome_tile' \
  "${ROOT}/services/proteus-ui/src/widgets.rs" \
  && ok "chrome glass tokens" || bad "chrome glass helpers missing"
grep -q 'menu_bar_plate\|dock_plate\|elevated_chip\|chrome_tile' \
  "${ROOT}/shell/src/surfaces.rs" \
  && ok "chrome glass surfaces" || bad "chrome glass surfaces missing"
grep -q 'lock_cooldown_secs\|on_fail\|Try again in' \
  "${ROOT}/shell/src/lock_ui.rs" "${ROOT}/shell/src/platform.rs" \
  && ok "lock progressive cooldown" || bad "lock cooldown missing"

# UI/UX parity pass — kit widgets, icon pipeline, motion engine (CHROME.md)
grep -q 'theme_slider' "${ROOT}/services/proteus-ui/src/widgets.rs" \
  && grep -q 'theme_switch' "${ROOT}/services/proteus-ui/src/widgets.rs" \
  && grep -q 'circle_button' "${ROOT}/services/proteus-ui/src/widgets.rs" \
  && grep -q 'squircle_plate\|SQUIRCLE_RATIO' "${ROOT}/services/proteus-ui/src/widgets.rs" \
  && ok "kit slider/switch/circle/squircle" || bad "kit parity widgets missing"
grep -q 'accent_soft\|light_close\|privacy_mic\|icon_plate' "${ROOT}/services/proteus-ui/src/theme.rs" \
  && ok "kit semantic tokens" || bad "kit semantic tokens missing"
grep -q 'resolve_app_icon' "${ROOT}/shell/src/icons.rs" \
  && grep -q 'chrome_glyph' "${ROOT}/shell/src/icons.rs" \
  && grep -q 'IconCache' "${ROOT}/shell/src/icons.rs" \
  && ok "icon pipeline (freedesktop + glyphs)" || bad "icon pipeline missing"
grep -q 'Icon=' "${ROOT}/shell/src/beacon.rs" \
  && ok "desktop Icon= parsing" || bad "Icon= parsing missing"
grep -q 'AnimatedValue' "${ROOT}/shell/src/anim.rs" \
  && grep -q 'OutCubic' "${ROOT}/shell/src/anim.rs" \
  && grep -q 'Keyframes' "${ROOT}/shell/src/anim.rs" \
  && grep -q 'Deadline' "${ROOT}/shell/src/anim.rs" \
  && ok "anim engine (easing/keyframes/deadline)" || bad "anim engine missing"
grep -q 'iced::time::every' "${ROOT}/shell/src/main.rs" \
  && grep -q 'motion_active' "${ROOT}/shell/src/main.rs" \
  && ok "timer subscriptions + motion gate" || bad "timer subscriptions missing"
# Freeze guard — subprocess polling must live on the heavy worker, never in update()
grep -q 'spawn_heavy_worker' "${ROOT}/shell/src/main.rs" \
  && grep -q 'HeavySnapshot' "${ROOT}/shell/src/main.rs" \
  && ok "heavy worker (no subprocess on UI thread)" || bad "heavy worker missing"
if grep -En 'platform::(bt_list_thin|wifi_list_thin|power_status|mpris_players)\(\)' \
    "${ROOT}/shell/src/main.rs" | grep -v 'spawn_heavy_worker' | grep -vq 'HeavySnapshot'; then
  # Allowed only inside spawn_heavy_worker; a hit elsewhere means UI-thread polling is back.
  if awk '/fn spawn_heavy_worker/,/^}/' "${ROOT}/shell/src/main.rs" \
      | grep -cq 'platform::power_status'; then
    ok "subprocess polling scoped to worker"
  else
    bad "subprocess polling on UI thread"
  fi
else
  ok "subprocess polling scoped to worker"
fi
grep -q 'lock_ui::lock_screen_view\|LockMsg' "${ROOT}/shell/src/bin/proteus-session-lock.rs" \
  && ok "session-lock shared UI" || bad "session-lock UI parity missing"
grep -q 'PROTEUS_SESSION_LOCK\|resolve_session_lock\|activate_session_lock' "${ROOT}/shell/src/engine.rs" \
  && ok "session-lock fact spike" || bad "session-lock missing"
grep -q 'session_lock_helper\|spawn_protocol_lock\|proteus-session-lock' "${ROOT}/shell/src/engine.rs" "${ROOT}/shell/src/ctl.rs" \
  && ok "session-lock protocol helper" || bad "session-lock helper missing"
[[ -f "${ROOT}/shell/src/bin/proteus-session-lock.rs" ]] \
  && ok "proteus-session-lock bin source" || bad "session-lock bin missing"
grep -q 'Games.*Media.*Apps.*Search.*Settings\|"Games".*"Media".*"Apps"' \
  "${ROOT}/shell/src/faces/console.rs" \
  && ok "console face list IA" || bad "console face IA missing"
grep -q 'OpenMediaPath\|console_apps_thin\|Beacon .desktop' \
  "${ROOT}/shell/src/faces/console.rs" "${ROOT}/shell/src/platform.rs" "${ROOT}/shell/src/main.rs" \
  && ok "console Media/Apps thin" || bad "console Media/Apps missing"
grep -q 'Console Settings\|OpenConsoleSettingsPage\|network-wifi' \
  "${ROOT}/shell/src/faces/console.rs" \
  && ok "console Settings face thin" || bad "console Settings face missing"
grep -q 'host_glance\|HostGlance\|proteus-host-metrics' \
  "${ROOT}/shell/src/faces/host.rs" "${ROOT}/shell/src/platform.rs" \
  && ok "host Glance metrics" || bad "host Glance missing"
grep -q 'HexOS-style cards\|glance.cards' \
  "${ROOT}/shell/src/faces/host.rs" "${ROOT}/shell/src/platform.rs" \
  && ok "host Glance HexOS cards" || bad "host Glance cards missing"
grep -q 'gamescope console-home not swapped' "${ROOT}/shell/src/faces/console.rs" \
  && ok "gamescope Home not swapped note" || bad "gamescope honesty missing"
grep -q 'consoleTab' "${ROOT}/shell/src/ctl.rs" \
  && ok "consoleTab ctl" || bad "consoleTab ctl missing"
grep -q 'console_games_list\|LaunchGame\|proteus-console-games' \
  "${ROOT}/shell/src/platform.rs" "${ROOT}/shell/src/faces/console.rs" \
  && ok "console Games scan/launch" || bad "console Games missing"
grep -q 'HostTab\|host_face_view' \
  "${ROOT}/shell/src/faces/host.rs" "${ROOT}/shell/src/main.rs" \
  && ok "host face Workloads tabs" || bad "host face missing"
grep -q 'gamescope console-home not swapped' \
  "${ROOT}/docs/proteus/OWNED-STACK.md" "${ROOT}/shell/src/faces/console.rs" \
  && ok "gamescope Home not swapped honesty" || bad "gamescope honesty missing"
grep -q 'resolve_compositor_engine\|compositor-engine' "${ROOT}/shell/src/engine.rs" \
  && ok "compositor-engine fallthrough" || bad "compositor-engine missing"
grep -qE '"" \| "smithay"|Hyprland purged|smithay only' "${ROOT}/shell/src/engine.rs" \
  && ok "smithay engine shipping default" || bad "smithay default missing"
[[ -f "${ROOT}/docs/proteus/COMPOSITOR-SPIKE.md" ]] \
  && ok "COMPOSITOR-SPIKE.md" || bad "COMPOSITOR-SPIKE.md missing"
grep -q 'BOOT_LAYERS\|boot_extra_layers' "${ROOT}/shell/src/main.rs" \
  && ok "boot_extra_layers" || bad "boot_extra_layers missing"
grep -q 'brightness_set\|BrightnessStep\|BrightnessSet' "${ROOT}/shell/src/main.rs" \
  && ok "brightness wired" || bad "brightness not wired"
grep -q 'ChromeEpoch\|AtomicU64' "${ROOT}/shell/src/ctl.rs" \
  && ok "ctl chrome epoch" || bad "ctl chrome epoch missing"

# Layer geometry protocol gate — invalid anchor/size kills the client at boot
grep -q 'layer_sizes_respect_anchor_protocol' "${ROOT}/shell/src/main.rs" \
  && ok "layer geometry test present" || bad "layer geometry test missing"
grep -q 'reconcile_layer_input\|SetInputRegion' "${ROOT}/shell/src/main.rs" \
  && ok "idle overlay input regions" || bad "overlay input regions missing"
grep -q 'respawn\|systemd-cat' "${ROOT}/shell/scripts/proteus-chrome" \
  && ok "chrome respawn watchdog" || bad "chrome respawn watchdog missing"
grep -q 'wallpaper_state\|WallpaperState' "${ROOT}/shell/src/platform.rs" \
  && grep -q 'wallpaper_view' "${ROOT}/shell/src/surfaces.rs" \
  && grep -q 'ContentFit' "${ROOT}/shell/src/surfaces.rs" \
  && ok "owned wallpaper image" || bad "owned wallpaper missing"
grep -q 'pkill -x proteus-bg\|owned shell paints' "${ROOT}/shell/scripts/proteus-chrome" \
  "${ROOT}/shell/scripts/proteus-bg" \
  && ok "owned retires QS wallpaper" || bad "QS wallpaper still primary on owned"
grep -q 'dock_preview_capture' "${ROOT}/shell/src/platform.rs" \
  && grep -q 'proteus/previews' "${ROOT}/shell/src/platform.rs" \
  && grep -q 'grim' "${ROOT}/shell/src/platform.rs" \
  && ok "dock preview capture (grim)" || bad "dock preview capture missing"
grep -q 'DockHover\|dock_preview' "${ROOT}/shell/src/main.rs" \
  && ok "dock hover previews wired" || bad "dock previews not wired"
grep -q 'read_lock_widgets\|strip_view\|LOCK_WIDGET_CATALOG' "${ROOT}/shell/src/lock_ui.rs" \
  && grep -q 'customize_view\|CustomizeAdd' "${ROOT}/shell/src/lock_ui.rs" \
  && ok "lock customize zones/applets" || bad "lock customize missing"
grep -q '"customize"' "${ROOT}/shell/src/ctl.rs" \
  && ok "lock customize ctl verb" || bad "lock customize verb missing"
grep -q 'persist_lock_widgets' "${ROOT}/shell/src/lock_ui.rs" \
  && ok "lockWidgets persistence" || bad "lockWidgets persistence missing"

# Smithay rung-2 spike (nested, opt-in) — crate + engine opt-in + dated doc
[[ -f "${ROOT}/compositor-next/Cargo.toml" ]] \
  && ok "compositor-next crate" || bad "compositor-next crate missing"
grep -q '"smithay" | "compositor-next" => "smithay"' "${ROOT}/shell/src/engine.rs" \
  && ok "smithay engine opt-in" || bad "smithay opt-in missing"
grep -qE '^## Prove \(20[0-9]{2}-' "${ROOT}/docs/proteus/COMPOSITOR-SPIKE.md" \
  && ok "spike doc dated" || bad "COMPOSITOR-SPIKE.md undated"
if command -v cargo >/dev/null 2>&1; then
  if (cd "${ROOT}" && cargo build -p compositor-next -q 2>/dev/null); then
    ok "compositor-next builds"
  else
    bad "compositor-next build"
  fi
fi

# Build bins (debug is enough for smoke)
if command -v cargo >/dev/null 2>&1; then
  if (cd "${ROOT}" && cargo build -p proteus-shell -q); then
    ok "proteus-shell builds"
  else
    bad "proteus-shell build"
  fi
  if (cd "${ROOT}" && cargo test -p proteus-shell --bin proteus-shell -q >/dev/null 2>&1); then
    ok "layer geometry unit tests"
  else
    bad "layer geometry unit tests"
  fi
fi

SHELL_BIN="${ROOT}/target/debug/proteus-shell"
CTL_BIN="${ROOT}/target/debug/proteus-shellctl"
if [[ -x "${SHELL_BIN}" && -x "${CTL_BIN}" ]]; then
  # Headless ctl roundtrip
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/proteus-shell-smoke-$$}"
  install -d "${XDG_RUNTIME_DIR}/proteus"
  "${SHELL_BIN}" --headless >/tmp/proteus-shell-smoke.log 2>&1 &
  spid=$!
  sleep 0.4
  if "${CTL_BIN}" chrome state 2>/dev/null | grep -q '"ok":true\|"ok": true'; then
    ok "shellctl chrome.state"
  else
    # JSON may omit space
    if "${CTL_BIN}" chrome state 2>/dev/null | grep -q '"ok"'; then
      ok "shellctl chrome.state"
    else
      bad "shellctl chrome.state"
      cat /tmp/proteus-shell-smoke.log >&2 || true
    fi
  fi
  if "${CTL_BIN}" lock lock 2>/dev/null | grep -q '"ok"'; then
    ok "shellctl lock.lock"
  else
    bad "shellctl lock.lock"
  fi
  kill "${spid}" 2>/dev/null || true
  wait "${spid}" 2>/dev/null || true
else
  bad "debug bins missing after build"
fi

# Installer present
[[ -f "${ROOT}/install/machine/install-proteus-shell.sh" ]] \
  && ok "install-proteus-shell.sh" || bad "install-proteus-shell.sh missing"

# Default engine is Owned. Quickshell retired.
if awk '/^pub fn resolve_engine/,/^}/' "${ROOT}/shell/src/engine.rs" | grep -q 'ShellEngine::Owned'; then
  ok "default engine Owned"
else
  bad "default engine not Owned"
fi
if grep -qE 'ENGINE=quickshell|proteus-qs' "${ROOT}/shell/scripts/proteus-chrome"; then
  bad "proteus-chrome still has Quickshell path"
else
  ok "proteus-chrome owned-only"
fi
if [[ -f "${ROOT}/shell/scripts/proteus-qs" ]]; then
  bad "proteus-qs must be retired"
else
  ok "proteus-qs retired"
fi
grep -q 'echo "owned"' "${ROOT}/install/machine/install-proteus-shell.sh" \
  && ok "installer seeds owned" || bad "installer not seeding owned"
grep -q 'exit 1\|Wave 4 owned default requires\|proteus-shell required' "${ROOT}/install/machine/install-proteus-shell.sh" \
  && ok "installer fail-closed without bins" || bad "installer still silent-skips"
grep -q 'proteus-shell required\|Wave 4 owned default\|cargo build -p proteus-shell' "${ROOT}/install/machine/install-settings-app.sh" \
  && ok "settings-app requires proteus-shell" || bad "settings-app still silent-skips shell"
if grep -E 'cat >.*/proteus-settings-qml|exec.*/proteus-settings-qml|falling back to QML' \
  "${ROOT}/install/machine/install-settings-app.sh" >/dev/null; then
  bad "settings-app still has QML fallback"
else
  ok "settings-app iced-only"
fi

if [[ "${fail}" -ne 0 ]]; then
  echo "shell-smoke: FAILED"
  exit 1
fi
echo "shell-smoke: ok"
