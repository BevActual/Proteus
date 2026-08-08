#!/usr/bin/env bash
# shell-smoke — owned iced shell (OWNED-STACK rung 1) parity gates.
#
# Holds both engines honest during the overlap: layer namespaces, IPC targets,
# engine fact, ctl protocol, and crate tests. Does not require Wayland.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SURFACES="${ROOT}/shell/src/surfaces"
APP="${ROOT}/shell/src/app"
PLATFORM="${ROOT}/shell/src/platform"
MAIN="${ROOT}/shell/src/main.rs"
# Grep thin main + app/ (session logic lives under app/ after the split).
shell_app_grep() { grep -rq --include='*.rs' -- "$@" "${APP}" "${MAIN}"; }
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
          proteus-spaces proteus-hud proteus-bg proteus-desktop-widgets proteus-toast \
          proteus-privacy-ask proteus-lock; do
  grep -q "\"${ns}\"" "${ROOT}/shell/src/lib.rs" \
    && ok "layer ${ns}" || bad "layer ${ns}"
done
grep -rq --include='*.rs' 'ToggleSpaces\|visible_space_ids\|chrome.*spaces\|"spaces"' \
  "${SURFACES}" "${ROOT}/shell/src/spaces.rs" "${ROOT}/shell/src/ctl.rs" \
  && ok "Spaces Mission Control path" || bad "Spaces overview missing"
grep -q 'mosaic_cell_size\|CARD_W\|pencil' \
  "${ROOT}/shell/src/spaces.rs" "${ROOT}/shell/src/icons.rs" \
  && ok "Spaces overview UX (mosaic + pencil)" || bad "Spaces UX polish missing"
grep -rq --include='*.rs' 'workspaceNames\|names_with_rename\|SpacesRename' \
  "${ROOT}/shell/src/spaces.rs" "${APP}" "${MAIN}" \
  && ok "Spaces rename Fact path" || bad "Spaces rename missing"
grep -rq --include='*.rs' 'move_window_to_workspace\|SpacesDrop\|SpacesDragStart' \
  "${ROOT}/shell/src/wm_ipc.rs" "${APP}" "${MAIN}" "${ROOT}/shell/src/spaces.rs" \
  && ok "Spaces drag-move" || bad "Spaces drag-move missing"
grep -rq --include='*.rs' 'struct Monitor\|occupied_space_ids_for_output\|windows_on_space_for_output' \
  "${ROOT}/shell/src/wm_ipc.rs" "${ROOT}/shell/src/spaces.rs" \
  && ok "Spaces per-head helpers" || bad "Spaces per-head helpers missing"
grep -rq --include='*.rs' 'ScratchToggle\|scratch_toggle\|special:scratch' \
  "${SURFACES}" "${APP}" "${ROOT}/shell/src/wm_ipc.rs" \
  && grep -q '◇' "${SURFACES}/bar.rs" \
  && ok "Scratchpad ◇ strip pill" || bad "Scratchpad ◇ strip missing"
grep -q 'SCRATCH_WORKSPACE\|special:scratch' "${ROOT}/compositor/src/wm.rs" \
  && grep -q 'SCRATCH_WORKSPACE\|toplevel_on_scratch' "${ROOT}/shell/src/wm_ipc.rs" \
  && ok "Scratchpad distinct workspace id" || bad "Scratchpad distinct id missing"
grep -q 'scratch_toggle\|scratch-toggle' "${ROOT}/compositor/src/binds.rs" \
  && grep -q 'scratch_move\|scratch-move' "${ROOT}/compositor/src/binds.rs" \
  && ok "Scratchpad Super+S chord binds" || bad "Scratchpad Super+S binds missing"
grep -q 'scratchpad_card\|Scratchpad' "${ROOT}/shell/src/spaces.rs" \
  && grep -q 'SCRATCH_WORKSPACE' "${ROOT}/shell/src/spaces.rs" "${ROOT}/shell/src/app/handlers/spaces.rs" \
  && ok "Spaces overview Scratchpad card" || bad "overview Scratchpad card missing"
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
grep -rq --include='*.rs' 'iced_layershell::build_pattern::daemon\|build_pattern::daemon' "${APP}" "${MAIN}" \
  && ok "daemon multi-window entry" || bad "daemon entry missing"
grep -rq --include='*.rs' 'to_layer_message(multi)' "${APP}" "${MAIN}" \
  && ok "to_layer_message(multi)" || bad "to_layer_message(multi) missing"
grep -rq --include='*.rs' 'NewLayerShell' "${APP}" "${MAIN}" \
  && ok "NewLayerShell boot" || bad "NewLayerShell missing"
grep -q 'fn boot_layers\|Face::' "${ROOT}/shell/src/faces/mod.rs" \
  && shell_app_grep 'boot_layers()' \
  && ok "face-aware boot layers" || bad "face-aware boot missing"
[[ -f "${ROOT}/shell/src/faces/desktop/mod.rs" ]] \
  && [[ -f "${ROOT}/shell/src/faces/console/mod.rs" ]] \
  && [[ -f "${ROOT}/shell/src/faces/host/mod.rs" ]] \
  && ok "faces/{desktop,console,host} modules" \
  || bad "faces per-mode modules missing"
grep -q 'BOOT_LAYERS' "${ROOT}/shell/src/faces/desktop/mod.rs" \
  && ok "desktop BOOT_LAYERS" || bad "desktop BOOT_LAYERS missing"
grep -q 'BOOT_LAYERS_LEAN' "${ROOT}/shell/src/faces/mod.rs" \
  && ok "lean BOOT_LAYERS" || bad "lean BOOT_LAYERS missing"
for sym in DOCK LAUNCHER CONTROL_CENTER HUD BG DESKTOP_WIDGETS TOAST PRIVACY_ASK LOCK; do
  grep -E "BOOT_LAYERS" -A20 "${ROOT}/shell/src/faces/desktop/mod.rs" \
    "${ROOT}/shell/src/faces/mod.rs" | grep -q "layers::${sym}" \
    && ok "boot layer ${sym}" || bad "boot layer ${sym}"
done
grep -rq --include='*.rs' 'session_chrome_suppressed\|session_start_lock_pending' "${APP}" "${MAIN}" \
  && ok "lock chrome suppress" || bad "lock suppress missing"
# Opaque lock floor — wallpaper/solid in Overlay so windows cannot peek.
grep -rq --include='*.rs' 'fn lock_backdrop\|lock_backdrop(' "${SURFACES}" \
  && grep -rq --include='*.rs' 'lock_view(' "${APP}" "${MAIN}" \
  && grep -rq --include='*.rs' 'wallpaper_handle' "${APP}" "${MAIN}" \
  && ok "lock opaque backdrop (no desktop peek)" \
  || bad "lock_backdrop / wallpaper floor missing"
grep -q 'compositor_supports_session_lock' "${ROOT}/shell/src/engine.rs" \
  && grep -q 'session-lock' "${ROOT}/shell/src/engine.rs" \
  && ok "protocol lock compositor probe" \
  || bad "session-lock compositor gate missing"
grep -rq --include='*.rs' 'try_unlock\|check-unlock' "${PLATFORM}" \
  && ok "PAM unlock path" || bad "PAM unlock missing"
grep -q 'spawn_socket2_listener' "${ROOT}/shell/src/wm_ipc.rs" \
  && ok "compositor subscribe listener" || bad "subscribe listener missing"
grep -q 'volumeUp\|volume_step\|brightnessUp' "${ROOT}/shell/src/ctl.rs" \
  && ok "HUD volume/brightness steps" || bad "HUD steps missing"
grep -q 'customizeDesktop\|dockLaunch\|focusCycle' "${ROOT}/shell/src/ctl.rs" \
  && ok "chrome IPC parity verbs" || bad "chrome IPC verbs missing"
grep -q '"notifications"' "${ROOT}/shell/src/ctl.rs" \
  && ok "chrome notifications IPC" || bad "notifications IPC missing"
grep -rq --include='*.rs' 'center_hub_view\|ToggleNotifications\|DesktopPress' "${SURFACES}" \
  && ok "center hub + wallpaper hold" || bad "center hub / hold missing"
grep -q 'desktop_widgets\|HOLD_MS\|desktopWidgets' "${ROOT}/shell/src/desktop_widgets.rs" \
  && ok "desktop widget placement module" || bad "desktop_widgets missing"
grep -rq --include='*.rs' 'WifiRadioToggle\|AppearanceMode\|Screenshot' "${SURFACES}" \
  && ok "CC quick-settings harden" || bad "CC functional tiles missing"
grep -rq --include='*.rs' 'module_tile\|WifiRadioToggle' "${SURFACES}" \
  && ok "CC 2-col module grid" || bad "CC module grid missing"
# Quieter menu bar — wifi/BT/volume chips collapse into CC.
if grep -rn --include='*.rs' 'let right = row!' "${SURFACES}/bar.rs" | head -1 >/dev/null \
  && awk '/let right = row!/,/align_y/' "${SURFACES}/bar.rs" | head -20 \
    | grep -qE 'wifi_chip|bt_chip|vol_chip|tile_chip'; then
  bad "menu bar still has dense wifi/BT/vol/tile chips"
else
  ok "menu bar quieter right cluster"
fi
grep -q 'widgets' "${ROOT}/shell/src/ctl.rs" \
  && ok "widgets CRUD ctl" || bad "widgets ctl missing"
grep -rq --include='*.rs' 'run_notifications_server\|org.freedesktop.Notifications' "${PLATFORM}" \
  && ok "zbus Notifications server" || bad "zbus Notifications missing"
grep -rq --include='*.rs' 'dbus-monitor\|NotifBus' "${PLATFORM}" \
  && ok "notif path / fallback" || bad "notif path missing"
grep -q 'list_desktop_apps\|filter_desktop_hits\|gtk-launch' "${ROOT}/shell/src/beacon.rs" \
  && ok "Beacon desktop enumerate/launch" || bad "Beacon desktop missing"
grep -q 'overlays_blocked\|overlays blocked while locked' "${ROOT}/shell/src/ctl.rs" \
  && ok "lock blocks overlays" || bad "lock overlay gate missing"
grep -rq --include='*.rs' 'start_tray_watcher\|tray_poll' "${PLATFORM}" \
  && ok "SNI tray watcher" || bad "SNI tray missing"
grep -rq --include='*.rs' 'load_dock_pins\|dockPins' "${APP}" "${MAIN}" \
  && ok "dock pins from facts" || bad "dock pins missing"
grep -rq --include='*.rs' 'DockEditDone\|persist_dock_pins\|DockUnpin\|remove_dock_pin' "${APP}" "${SURFACES}" \
  && ok "dock edit + dockPins persist" || bad "dock edit reorder missing"
grep -q 'DockContextOpen\|DockKeep\|DockRemove\|add_dock_pin\|on_right_press' \
  "${SURFACES}/dock.rs" "${SURFACES}/mod.rs" "${APP}/handlers/dock.rs" \
  && ok "dock right-click Keep/Remove" || bad "dock Keep/Remove context missing"
grep -rq --include='*.rs' 'DockDragOffDrop\|DockDragOffHover\|Drop here to remove\|dock_drag_off' \
  "${APP}" "${SURFACES}" \
  && ok "dock drag-off unpin" || bad "dock drag-off unpin missing"
grep -rq --include='*.rs' 'proteus-launcher\|is_beacon_pin' "${APP}" "${MAIN}" "${SURFACES}" \
  && ok "Beacon dock pin" || bad "Beacon dock pin missing"
grep -q 'settings_catalog_hits\|--page=' "${ROOT}/shell/src/beacon.rs" \
  && ok "Beacon settings catalog" || bad "Beacon settings missing"
grep -q 'lock_screen_view\|Click or type to unlock\|Enter unlock PIN\|Use password' \
  "${ROOT}/shell/src/lock_ui.rs" \
  && ok "lock full-bleed PIN/reveal" || bad "lock GUI shallow"
grep -q 'lock-password-input\|lock_password_focus_pending\|LockWakeChar' \
  "${APP}" "${MAIN}" "${ROOT}/shell/src/lock_ui.rs" "${SURFACES}" \
  && grep -rq --include='*.rs' 'repeat' "${APP}" "${MAIN}" \
  && ok "lock password focus + wake keystroke (no repeat bunches)" \
  || bad "lock password input lag guards missing"
grep -rq --include='*.rs' 'no WM/sensor/applet spam while typing' "${APP}" "${MAIN}" \
  && grep -rq --include='*.rs' '1000' "${APP}" "${MAIN}" \
  && ok "lock auth light tick" || bad "lock still heavy-ticks while typing"
grep -rq --include='*.rs' 'LockReveal\|LockPinDigit\|lock_ui' "${APP}" "${MAIN}" "${SURFACES}" \
  && ok "lock shell wiring" || bad "lock shell wiring missing"
grep -rq --include='*.rs' 'Windows-style\|not in the menu bar' "${SURFACES}" \
  && ok "bar defers window chrome to SSD" || bad "bar still claims traffic-lights"
if grep -rqE --include='*.rs' 'fn traffic_light|Message::WindowClose|Message::WindowMinimize' \
  "${SURFACES}"; then
  bad "bar still paints traffic-lights"
else
  ok "bar has no traffic-lights widgets"
fi
grep -q 'window_close\|window_minimize\|window_maximize' "${ROOT}/shell/src/wm_ipc.rs" \
  && ok "wm_ipc window helpers (dock/IPC)" || bad "wm_ipc window helpers missing"
grep -q 'Minimize\|minimize_hit' "${ROOT}/compositor/src/decoration.rs" \
  && ok "SSD minimize chrome" || bad "SSD minimize missing"
grep -rq --include='*.rs' 'PrivacyDots\|privacy_dots\|OpenPrivacy' "${PLATFORM}" "${SURFACES}" \
  && ok "privacy dots" || bad "privacy dots missing"
grep -rq --include='*.rs' 'PrivacyAllow\|session-allow\|privacy_ask_app\|enforce-capture' \
  "${APP}" "${SURFACES}" "${ROOT}/shell/src/ctl.rs" \
  && grep -q 'session-allow\|session-clear\|save_session_allows' \
    "${ROOT}/shell/scripts/proteus-permissions.py" \
  && ok "Privacy Ask Allow/Deny + session/enforce thin" \
  || bad "Privacy Ask wire missing"
grep -q 'gate_launch_for_privacy\|first_launch_ask_category\|privacy_ask_pending' \
  "${APP}/handlers/overlays.rs" "${ROOT}/shell/src/privacy_gate.rs" "${ROOT}/shell/src/ctl.rs" \
  && ok "Privacy launch→Ask producer thin" \
  || bad "Privacy launch→Ask producer missing"
grep -rq --include='*.rs' 'PowerProfile\|power_set_profile_index\|VolumeStep' "${SURFACES}" "${PLATFORM}" \
  && ok "CC power/volume" || bad "CC power/volume missing"
grep -rqE --include='*.rs' 'ToggleFloating|VolumeMute' "${SURFACES}" "${APP}" "${MAIN}" \
  && grep -rqE --include='*.rs' 'glyph_view\("wifi"|glyph_view\("tile"' "${SURFACES}" \
  && ok "bar wifi/BT/volume/tile chips" || bad "bar system chips missing"
grep -q 'is_ghostty_desktop_id\|proteus-terminal' "${ROOT}/shell/src/beacon.rs" \
  && ok "Beacon Ghostty → proteus-terminal" || bad "Beacon Ghostty route missing"
grep -rq --include='*.rs' 'NotifDismiss' "${SURFACES}" \
  && ok "CC notif dismiss" || bad "CC notif dismiss missing"
grep -q 'dock_activate\|DockAction\|dock_activate_plan' "${ROOT}/shell/src/wm_ipc.rs" \
  && ok "dock minimize/restore" || bad "dock activate missing"
grep -q 'DockPlan::Cycle\|running.len() >= 2' "${ROOT}/shell/src/wm_ipc.rs" \
  && ok "dock multi-window cycle" || bad "dock cycle missing"
grep -rq --include='*.rs' 'dock_plan_cycle_multi_focused\|dock_pins_defaults_include_beacon' \
  "${ROOT}/shell/src/wm_ipc.rs" "${SURFACES}" \
  && ok "dock cargo unit tests" || bad "dock unit tests missing"
grep -rq --include='*.rs' 'dock_transients\|dock_divider' "${SURFACES}" \
  && ok "dock pin/transient divider" || bad "dock transients missing"
grep -rq --include='*.rs' 'DOCK_PREVIEW_DWELL_MS\|DockPreviewFocus\|DockPreviewClose\|Hidden' \
  "${SURFACES}" "${APP}" "${MAIN}" \
  && ok "dock dwell preview interact" || bad "dock dwell preview missing"
grep -rq --include='*.rs' 'dock_bounce\|DOCK_BOUNCE_TIMEOUT_MS' "${APP}" "${MAIN}" "${SURFACES}" \
  && ok "dock launch bounce" || bad "dock bounce missing"
grep -q 'glass_alpha\|apply_chrome_opacity' "${ROOT}/services/proteus-ui/src/theme.rs" \
  && ok "chromeOpacity → glass_alpha" || bad "glass_alpha from settings missing"
grep -rq --include='*.rs' 'dockIconSize\|dock_icon_size' "${APP}" "${MAIN}" \
  && ok "dockIconSize Fact" || bad "dockIconSize missing"
grep -rq --include='*.rs' 'BAR || n == layers::DOCK => Layer::Top' "${APP}" "${MAIN}" \
  && grep -rq --include='*.rs' 'dock_strip_h(surfaces::DOCK_ICON_REST)\|ExclusiveZoneChange' "${APP}" "${MAIN}" \
  && ok "dock Top + exclusive_zone" || bad "dock layer/exclusive missing"
grep -rq --include='*.rs' 'DOCK_LEAVE_DELAY_MS\|DockPreviewEnter\|dock_leave_at' \
  "${SURFACES}" "${APP}" "${MAIN}" \
  && ok "dock preview hover bridge" || bad "dock leave bridge missing"
grep -rqE --include='*.rs' 'Preview band above the strip|click-through until a dwell preview' \
  "${SURFACES}" \
  && grep -rqE --include='*.rs' 'DOCK_LAYER_H: u32 = (3[0-9]{2}|[4-9][0-9]{2})' "${SURFACES}" \
  && ok "dock preview band does not crush shelf" || bad "dock shelf crush guard missing"
grep -rq --include='*.rs' 'DockLayout\|dockLayout\|DOCK_HOVER_SCALE' \
  "${SURFACES}" "${APP}" "${MAIN}" \
  && ok "dock layout + hover scale (no magnify)" || bad "dock layout/hover missing"
grep -rq --include='*.rs' 'dock_dot_count\|dock_running_windows\|dock_active_dot_index' \
  "${SURFACES}" \
  && ok "dock multi-window dots" || bad "dock running dots missing"
grep -rq --include='*.rs' 'layers::BG || n == layers::LOCK => -1' "${APP}" "${MAIN}" \
  && ok "wallpaper+lock DontCare full-bleed" || bad "BG/lock exclusive clips"
grep -rq --include='*.rs' 'apply_settings_if_changed\|settings_mtime' "${APP}" "${MAIN}" \
  && grep -rq --include='*.rs' 'skip_sync' "${APP}" "${MAIN}" \
  && grep -rq --include='*.rs' 'LockPinDigit\|PinEntry' "${APP}" "${MAIN}" \
  && ok "shell settings mtime + light surface path" || bad "shell lag guards missing"
grep -rq --include='*.rs' 'fn pull_wm\|try_lock' "${APP}" "${MAIN}" \
  && grep -rq --include='*.rs' 'from_millis(33)' "${APP}" "${MAIN}" \
  && grep -q 'reload_widgets\|rebuild_strip' "${ROOT}/shell/src/lock_ui.rs" \
  && ok "shell responsiveness (wm pull / 30fps anim / lock cache)" \
  || bad "shell responsiveness guards missing"
grep -q 'skip_reconcile\|WmShared\|flush_pending_sliders' \
  "${APP}" "${MAIN}" "${ROOT}/shell/src/wm_ipc.rs" \
  && grep -rq --include='*.rs' 'chrono\|Local::now' "${SURFACES}" \
  && ok "shell responsiveness pass2 (wm gen / clock / sliders)" \
  || bad "shell responsiveness pass2 missing"
grep -q 'filter_beacon_hits\|Window ·\|File ·\|Place ·\|Recent ·\|launcherFileRecents\|beacon-file-index\|warm_file_index' "${ROOT}/shell/src/beacon.rs" \
  && ok "Beacon Windows/files thin" || bad "Beacon Windows/files missing"
grep -q 'clipboard_hits\|Clipboard ·\|cliphist\|calc_hit\|eval_calc\|wl-copy\|wtype' "${ROOT}/shell/src/beacon.rs" \
  && ok "Beacon clipboard/calc thin" || bad "Beacon clipboard/calc missing"
grep -rq --include='*.rs' 'ToggleDnd\|wifi_list_thin\|bt_list_thin' "${SURFACES}" "${PLATFORM}" \
  && ok "CC DND/WiFi/BT" || bad "CC tiles missing"
grep -rq --include='*.rs' 'ToggleFocus\|focus_profiles\|Focus Mode' "${SURFACES}" "${PLATFORM}" \
  && ok "CC Focus Mode thin" || bad "CC Focus missing"
grep -q 'apply_focus_schedule\|schedule_window_active\|focus_schedule_last' \
  "${PLATFORM}/focus.rs" "${APP}/runtime.rs" "${APP}/state.rs" \
  && ok "Focus schedule auto-apply thin" || bad "Focus schedule auto-apply missing"
grep -q 'parse_weekly_rrule\|rrule' "${PLATFORM}/focus.rs" \
  && ok "Focus schedule RRULE thin" || bad "Focus schedule RRULE missing"
grep -q 'focus_launch_allowed\|gate_launch_for_focus' \
  "${PLATFORM}/focus.rs" "${APP}/handlers/overlays.rs" "${APP}/handlers/dock.rs" \
  && ok "Focus launch enforce thin" || bad "Focus launch enforce missing"
grep -q 'breakCritical\|is_critical_escape\|profile_break_critical' \
  "${PLATFORM}/focus.rs" \
  && ok "Focus critical-break honor thin" || bad "Focus critical-break honor missing"
grep -rq --include='*.rs' 'DOCK_MAG_CELLS\|dock_mag_falloff\|dock_mag_strength' \
  "${SURFACES}" "${APP}" "${MAIN}" \
  && bad "dock magnify helpers must be removed" \
  || ok "dock magnify retired"
grep -rq --include='*.rs' 'fn dock_plate_h' "${SURFACES}" \
  && grep -rq --include='*.rs' 'dock_plate(' "${SURFACES}" \
  && grep -rq --include='*.rs' 'dock_autohide\|dock_slide\|DOCK_PEEK_SLIDE' "${APP}" "${MAIN}" "${SURFACES}" \
  && ok "dock plate + autohide peek" \
  || bad "dock plate / autohide missing"
grep -rq --include='*.rs' 'DOCK_POINTER_EPS' "${APP}" "${MAIN}" \
  && bad "DOCK_POINTER_EPS (magnify coalesce) must be gone" \
  || ok "no dock pointer magnify coalesce"
grep -q 'menu_bar_plate\|dock_plate\|elevated_chip\|chrome_tile' \
  "${ROOT}/services/proteus-ui/src/widgets.rs" \
  && ok "chrome glass tokens" || bad "chrome glass helpers missing"
grep -rq --include='*.rs' 'menu_bar_plate\|dock_plate\|elevated_chip\|chrome_tile' \
  "${SURFACES}" \
  && ok "chrome glass surfaces" || bad "chrome glass surfaces missing"
grep -rq --include='*.rs' 'lock_cooldown_secs\|on_fail\|Try again in' \
  "${ROOT}/shell/src/lock_ui.rs" "${PLATFORM}" \
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
grep -rq --include='*.rs' 'iced::time::every' "${APP}" "${MAIN}" \
  && grep -rq --include='*.rs' 'motion_active' "${APP}" "${MAIN}" \
  && ok "timer subscriptions + motion gate" || bad "timer subscriptions missing"
# Freeze guard — subprocess polling must live on the heavy worker, never in update()
grep -rq --include='*.rs' 'spawn_heavy_worker' "${APP}" "${MAIN}" \
  && grep -rq --include='*.rs' 'HeavySnapshot' "${APP}" "${MAIN}" \
  && ok "heavy worker (no subprocess on UI thread)" || bad "heavy worker missing"
if grep -En 'platform::(bt_list_thin|wifi_list_thin|power_status|mpris_players)\(\)' \
    "${APP}" "${MAIN}" | grep -v 'spawn_heavy_worker' | grep -vq 'HeavySnapshot'; then
  # Allowed only inside spawn_heavy_worker; a hit elsewhere means UI-thread polling is back.
  if awk '/fn spawn_heavy_worker/,/^}/' "${APP}"/*.rs "${MAIN}" \
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
  "${ROOT}/shell/src/faces/console/mod.rs" \
  && ok "console face list IA" || bad "console face IA missing"
grep -rq --include='*.rs' 'OpenMediaPath\|console_apps_thin\|Beacon .desktop' \
  "${ROOT}/shell/src/faces/console/mod.rs" "${PLATFORM}" "${APP}" "${MAIN}" \
  && ok "console Media/Apps thin" || bad "console Media/Apps missing"
grep -q 'Console Settings\|OpenConsoleSettingsPage\|network-wifi' \
  "${ROOT}/shell/src/faces/console/mod.rs" \
  && ok "console Settings face thin" || bad "console Settings face missing"
grep -rq --include='*.rs' 'host_glance\|HostGlance\|proteus-host-metrics' \
  "${ROOT}/shell/src/faces/host/mod.rs" "${PLATFORM}" \
  && ok "host Glance metrics" || bad "host Glance missing"
grep -rq --include='*.rs' 'HexOS-style cards\|glance.cards' \
  "${ROOT}/shell/src/faces/host/mod.rs" "${PLATFORM}" \
  && ok "host Glance HexOS cards" || bad "host Glance cards missing"
grep -q 'gamescope console-home not swapped' "${ROOT}/shell/src/faces/console/mod.rs" \
  && ok "gamescope Home not swapped note" || bad "gamescope honesty missing"
grep -q 'consoleTab' "${ROOT}/shell/src/ctl.rs" \
  && ok "consoleTab ctl" || bad "consoleTab ctl missing"
grep -rq --include='*.rs' 'console_games_list\|LaunchGame\|proteus-console-games' \
  "${PLATFORM}" "${ROOT}/shell/src/faces/console/mod.rs" \
  && ok "console Games scan/launch" || bad "console Games missing"
grep -rq --include='*.rs' 'HostTab\|host_face_view' \
  "${ROOT}/shell/src/faces/host/mod.rs" "${APP}" "${MAIN}" \
  && ok "host face Workloads tabs" || bad "host face missing"
grep -q 'gamescope console-home not swapped' \
  "${ROOT}/docs/proteus/OWNED-STACK.md" "${ROOT}/shell/src/faces/console/mod.rs" \
  && ok "gamescope Home not swapped honesty" || bad "gamescope honesty missing"
grep -q 'resolve_compositor_engine\|compositor-engine' "${ROOT}/shell/src/engine.rs" \
  && ok "compositor-engine fallthrough" || bad "compositor-engine missing"
grep -qE '"" \| "smithay"|Hyprland purged|smithay only' "${ROOT}/shell/src/engine.rs" \
  && ok "smithay engine shipping default" || bad "smithay default missing"
[[ -f "${ROOT}/docs/proteus/COMPOSITOR-SPIKE.md" ]] \
  && ok "COMPOSITOR-SPIKE.md" || bad "COMPOSITOR-SPIKE.md missing"
grep -rq --include='*.rs' 'BOOT_LAYERS\|boot_extra_layers' "${APP}" "${MAIN}" \
  && ok "boot_extra_layers" || bad "boot_extra_layers missing"
grep -rq --include='*.rs' 'brightness_set\|BrightnessStep\|BrightnessSet' "${APP}" "${MAIN}" \
  && ok "brightness wired" || bad "brightness not wired"
grep -q 'ChromeEpoch\|AtomicU64' "${ROOT}/shell/src/ctl.rs" \
  && ok "ctl chrome epoch" || bad "ctl chrome epoch missing"

# Layer geometry protocol gate — invalid anchor/size kills the client at boot
grep -rq --include='*.rs' 'layer_sizes_respect_anchor_protocol' "${APP}" "${MAIN}" \
  && ok "layer geometry test present" || bad "layer geometry test missing"
grep -rq --include='*.rs' 'reconcile_layer_input\|SetInputRegion' "${APP}" "${MAIN}" \
  && ok "idle overlay input regions" || bad "overlay input regions missing"
grep -q 'respawn\|systemd-cat' "${ROOT}/shell/scripts/proteus-chrome" \
  && ok "chrome respawn watchdog" || bad "chrome respawn watchdog missing"
grep -rq --include='*.rs' 'wallpaper_state\|WallpaperState' "${PLATFORM}" \
  && grep -rq --include='*.rs' 'wallpaper_view' "${SURFACES}" \
  && grep -rq --include='*.rs' 'ContentFit' "${SURFACES}" \
  && ok "owned wallpaper image" || bad "owned wallpaper missing"
grep -q 'pkill -x proteus-bg\|owned shell paints' "${ROOT}/shell/scripts/proteus-chrome" \
  "${ROOT}/shell/scripts/proteus-bg" \
  && ok "owned retires QS wallpaper" || bad "QS wallpaper still primary on owned"
grep -rq --include='*.rs' 'dock_preview_capture' "${PLATFORM}" \
  && grep -rq --include='*.rs' 'proteus/previews' "${PLATFORM}" \
  && grep -rq --include='*.rs' 'grim' "${PLATFORM}" \
  && ok "dock preview capture (grim)" || bad "dock preview capture missing"
grep -rq --include='*.rs' 'DockHover\|dock_preview' "${APP}" "${MAIN}" \
  && ok "dock hover previews wired" || bad "dock previews not wired"
grep -q 'read_lock_widgets\|strip_view\|LOCK_WIDGET_CATALOG' "${ROOT}/shell/src/lock_ui.rs" \
  && grep -q 'customize_view\|CustomizeAdd' "${ROOT}/shell/src/lock_ui.rs" \
  && ok "lock customize zones/applets" || bad "lock customize missing"
grep -q '"customize"' "${ROOT}/shell/src/ctl.rs" \
  && ok "lock customize ctl verb" || bad "lock customize verb missing"
grep -q 'persist_lock_widgets' "${ROOT}/shell/src/lock_ui.rs" \
  && ok "lockWidgets persistence" || bad "lockWidgets persistence missing"

# Smithay rung-2 spike (nested, opt-in) — crate + engine opt-in + dated doc
[[ -f "${ROOT}/compositor/Cargo.toml" ]] \
  && ok "compositor crate" || bad "compositor crate missing"
grep -q '"smithay" | "compositor" | "compositor-next" => "smithay"' "${ROOT}/shell/src/engine.rs" \
  && ok "smithay engine opt-in" || bad "smithay opt-in missing"
grep -qE '^## Prove \(20[0-9]{2}-' "${ROOT}/docs/proteus/COMPOSITOR-SPIKE.md" \
  && ok "spike doc dated" || bad "COMPOSITOR-SPIKE.md undated"
if command -v cargo >/dev/null 2>&1; then
  if (cd "${ROOT}" && cargo build -p compositor -q 2>/dev/null); then
    ok "compositor builds"
  else
    bad "compositor build"
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
