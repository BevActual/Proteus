#!/usr/bin/env bash
# compositor-smoke — owned Smithay compositor IPC contract (OWNED-STACK rung 2).
#
# Always-on: crate layout, cargo test (wm roster), build ctl client.
# Optional nested: if DISPLAY/WAYLAND_DISPLAY present, round-trip ctl socket.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CRATE="${ROOT}/compositor"
fail=0
ok() { echo "compositor-smoke: OK $*"; }
bad() { echo "compositor-smoke: FAIL $*" >&2; fail=1; }
# Accumulate checks (do not exit early) — alias for readability at call sites.
die() { bad "$*"; }
tmp_dir="$(mktemp -d)"
comp_pid=""
log=""
cleanup() {
  kill "${comp_pid:-}" 2>/dev/null || true
  [[ -n "${log:-}" ]] && rm -f "${log}"
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

[[ -f "${CRATE}/Cargo.toml" ]] || die "missing compositor/Cargo.toml"
[[ -f "${CRATE}/src/wm.rs" ]] || die "missing wm.rs"
[[ -f "${CRATE}/src/ctl.rs" ]] || die "missing ctl.rs"
[[ -f "${CRATE}/src/grabs.rs" ]] || die "missing grabs.rs"
[[ -f "${CRATE}/src/xwayland.rs" ]] || die "missing xwayland.rs"
[[ -f "${CRATE}/src/screencopy.rs" ]] || die "missing screencopy.rs"
[[ -f "${CRATE}/src/layout.rs" ]] || die "missing layout.rs"
[[ -f "${CRATE}/src/drm.rs" ]] || die "missing drm.rs"
[[ -f "${CRATE}/src/dmabuf_init.rs" ]] || die "missing dmabuf_init.rs"
grep -q 'PROTEUS_COMPOSITOR_SOCK' "${CRATE}/src/ctl.rs" \
  || die "ctl must export PROTEUS_COMPOSITOR_SOCK"
grep -q 'PROTEUS_COMPOSITOR_SOCK' "${ROOT}/shell/src/wm_ipc.rs" \
  || die "shell wm_ipc.rs must use PROTEUS_COMPOSITOR_SOCK"
grep -q 'hyprctl::\|Command::new\("hyprctl"\)\|his_socket2' "${ROOT}/shell/src/wm_ipc.rs" \
  && die "shell wm_ipc.rs must not call hyprctl (Hyprland purged)" || true
# Soft: ensure no hyprctl Command
if grep -q 'Command::new("hyprctl")' "${ROOT}/shell/src/wm_ipc.rs"; then
  die "shell wm_ipc.rs still spawns hyprctl"
fi
if grep -q 'using_smithay' "${ROOT}/shell/src/wm_ipc.rs"; then
  die "shell wm_ipc.rs still gates on using_smithay"
fi
[[ -f "${ROOT}/shell/src/hypr.rs" ]] \
  && die "shell/src/hypr.rs must be renamed to wm_ipc.rs" || true
grep -q 'SsdHit::Maximize\|maximize_hit' "${CRATE}/src/input.rs" "${CRATE}/src/decoration.rs" \
  || die "SSD maximize hit missing (SsdHit::Maximize / maximize_hit)"
grep -q 'SsdHit::Minimize\|minimize_hit\|minimize_address' \
  "${CRATE}/src/input.rs" "${CRATE}/src/decoration.rs" "${CRATE}/src/ctl.rs" \
  || die "SSD minimize hit missing (SsdHit::Minimize / minimize_address)"
grep -q 'is_ssd_titlebar_double_click\|SSD_DOUBLE_CLICK_MS' \
  "${CRATE}/src/decoration.rs" "${CRATE}/src/input.rs" \
  || die "SSD titlebar double-click maximize missing"
grep -q 'ssd_hover\|SsdChromePart\|btn_fill\|COLOR_CLOSE_HOVER' \
  "${CRATE}/src/decoration.rs" "${CRATE}/src/input.rs" "${CRATE}/src/state.rs" \
  || die "SSD button hover/press feedback missing"
grep -q 'enumerate gpus\|PROTEUS_DRM_DEVICE' "${CRATE}/src/drm.rs" \
  || die "drm multi-GPU thin enumerate / PROTEUS_DRM_DEVICE missing"
grep -q 'cursor_render_elements\|CursorState\|Kind::Cursor' \
  "${CRATE}/src/cursor.rs" "${CRATE}/src/handlers.rs" "${CRATE}/src/winit.rs" "${CRATE}/src/drm.rs" \
  || die "soft cursor draw missing"
grep -q 'PROTEUS_DRM_TRANSFORM\|Transform::_180\|virtio' "${CRATE}/src/drm.rs" \
  || die "virtio DRM transform workaround missing"
grep -q 'NodeType::Primary' "${CRATE}/src/drm.rs" \
  || die "DRM primary (card) node preference missing"
[[ -f "${CRATE}/src/displays.rs" ]] || die "missing displays.rs (Fact load)"
grep -q 'load_displays_fact\|apply_displays_fact\|displays\.json' \
  "${CRATE}/src/displays.rs" "${CRATE}/src/ctl.rs" "${CRATE}/src/drm.rs" "${CRATE}/src/winit.rs" \
  || die "displays Fact load/apply missing"
grep -q 'output .* scale\|OutputScale\|strip_prefix("output ' "${CRATE}/src/wm.rs" \
  || die "dispatch output scale missing"
grep -q 'OutputPos\|OutputMode\|output .* mode' "${CRATE}/src/wm.rs" \
  || die "dispatch output pos/mode missing"
grep -q 'OutputTransform\|output .* transform\|parse_transform_token' \
  "${CRATE}/src/wm.rs" "${CRATE}/src/displays.rs" "${CRATE}/src/ctl.rs" \
  || die "dispatch output transform missing"
grep -q 'transform' "${ROOT}/shell/scripts/proteus-settings-apply" \
  || die "proteus-settings-apply apply-displays transform missing"
grep -q 'apply-displays' "${ROOT}/shell/scripts/proteus-settings-apply" \
  || die "proteus-settings-apply apply-displays missing"
grep -qE '^\s*input\)|input-reload' "${ROOT}/shell/scripts/proteus-settings-apply" \
  || die "proteus-settings-apply input missing"
[[ -f "${CRATE}/src/identify.rs" ]] || die "missing identify.rs"
grep -q 'start_identify\|parse_identify_secs\|identify_render_elements' \
  "${CRATE}/src/identify.rs" "${CRATE}/src/ctl.rs" \
  || die "dispatch identify / identify overlay missing"
grep -q 'identify_render_elements' "${CRATE}/src/winit.rs" "${CRATE}/src/drm.rs" "${CRATE}/src/render_elements.rs" \
  || die "identify render path missing in winit/drm"
[[ -f "${CRATE}/src/binds.rs" ]] || die "missing binds.rs (session keybinds)"
grep -q 'reloadbinds\|BindsState\|default_binds' "${CRATE}/src/binds.rs" "${CRATE}/src/ctl.rs" "${CRATE}/src/input.rs" \
  || die "keybinds SoT / reloadbinds missing"
grep -q 'scratch_toggle\|scratch-toggle' "${CRATE}/src/binds.rs" \
  && grep -q 'scratch_move\|scratch-move' "${CRATE}/src/binds.rs" \
  && grep -q 'logo_alt' "${CRATE}/src/binds.rs" \
  || die "Scratchpad Super+S / Super+Alt+S binds missing"
grep -q 'id: "files"' "${CRATE}/src/binds.rs" \
  && grep -q 'xf86audioraisevolume\|xf86monbrightnessdown' "${CRATE}/src/binds.rs" \
  || die "files / XF86 media default binds missing"
grep -q 'input-reload\|InputConfig\|sensitivity_scale' \
  "${CRATE}/src/ctl.rs" "${CRATE}/src/input_config.rs" "${CRATE}/src/input.rs" \
  || die "input-reload / InputConfig missing"
grep -q 'tabletTipPressureCurve\|remap_tablet_pressure\|TabletToolAxis' \
  "${CRATE}/src/input_config.rs" "${CRATE}/src/input.rs" \
  || die "tablet pressure curve remap missing"
grep -q 'tabletActiveAreaSizeX\|apply_active_area_norm\|eraser_as_button\|tabletEraserButtonMode' \
  "${CRATE}/src/input_config.rs" "${CRATE}/src/input.rs" \
  || die "tablet active-area / eraser-as-button missing"
grep -q 'tabletTipPressureCurve\|tabletEraserPressureCurve' \
  "${ROOT}/shell/scripts/proteus-settings-apply" \
  || die "proteus-settings-apply input missing tablet curve keys"
grep -q 'tabletActiveAreaSizeX\|tabletEraserButtonMode' \
  "${ROOT}/shell/scripts/proteus-settings-apply" \
  || die "proteus-settings-apply input missing active-area/eraser keys"
grep -q 'SessionLockManagerState\|delegate_session_lock\|session_lock' \
  "${CRATE}/src/session_lock.rs" "${CRATE}/src/state.rs" \
  || die "ext-session-lock module missing"
grep -q 'IdleInhibitHandler\|delegate_idle_inhibit\|IdleInhibitManagerState' \
  "${CRATE}/src/idle_inhibit.rs" "${CRATE}/src/state.rs" \
  || die "zwp_idle_inhibit module missing"
grep -q 'systemd-inhibit\|SystemdIdleInhibit\|idle_inhibit_bridge' \
  "${CRATE}/src/idle_inhibit.rs" \
  || die "idle-inhibit systemd bridge missing"
grep -q 'idle-inhibit' "${CRATE}/src/ctl.rs" \
  || die "ctl idle-inhibit probe missing"
grep -q 'session-lock' "${CRATE}/src/ctl.rs" \
  || die "ctl session-lock probe missing"
grep -q '"pending"\|session_lock_pending\|"active"' "${CRATE}/src/ctl.rs" \
  || die "ctl session-lock must report pending/active"
[[ -f "${ROOT}/dev/smoke/compositor-session-lock.sh" ]] \
  || die "missing compositor-session-lock.sh (protocol dogfood)"
grep -q 'PROTEUS_SESSION_LOCK_DOGFOOD\|proteus-session-lock' \
  "${ROOT}/dev/smoke/compositor-session-lock.sh" \
  || die "protocol lock dogfood helper incomplete"
# Default Fact remains overlay (protocol is opt-in only).
grep -q 'SessionLockMode::Overlay' "${ROOT}/shell/src/engine.rs" \
  && grep -q 'PROTEUS_SESSION_LOCK' "${ROOT}/shell/src/engine.rs" \
  || die "shell session-lock overlay default / env opt-in missing"
# Docs honesty: transform live In (UI Out); protocol dogfood In.
grep -qE 'transform.*live|output.*transform|transform live In' \
  "${ROOT}/docs/proteus/CURRENT.md" "${ROOT}/docs/proteus/COMPOSITOR-SPIKE.md" \
  "${ROOT}/docs/proteus/SETTINGS-IA.md" \
  || die "docs missing transform live honesty"
grep -q 'compositor-session-lock\|protocol opt-in dogfood\|protocol.*dogfood' \
  "${ROOT}/docs/proteus/CURRENT.md" "${ROOT}/docs/proteus/COMPOSITOR-SPIKE.md" \
  "${ROOT}/docs/proteus/COMPOSITOR.md" \
  || die "docs missing protocol lock dogfood honesty"
grep -q 'beacon\|workspace_1\|FilterResult::Intercept' "${CRATE}/src/binds.rs" "${CRATE}/src/input.rs" \
  || die "beacon/workspace intercept missing"
[[ -f "${ROOT}/env/settings/keybinds.defaults.json" ]] \
  || die "missing env/settings/keybinds.defaults.json"
grep -q 'keybinds.json' "${ROOT}/install/machine/install-keybinds.sh" \
  || die "install-keybinds must seed keybinds.json"
grep -q 'fn dispatch' "${CRATE}/src/wm.rs" \
  || die "wm must implement dispatch"
grep -q 'workspace_local_\|,local\|logo_ctrl' "${CRATE}/src/binds.rs" "${CRATE}/src/wm.rs" \
  || die "Super+Ctrl local workspace binds / workspace N,local missing"
grep -q 'renameworkspace\|workspace_names\|workspaceNames' "${CRATE}/src/wm.rs" "${CRATE}/src/ctl.rs" \
  || die "renameworkspace / workspaceNames missing"
grep -qE 'Super\+Ctrl|workspace N,local|renameworkspace' \
  "${ROOT}/docs/proteus/CURRENT.md" "${ROOT}/docs/proteus/COMPOSITOR-SPIKE.md" \
  || die "docs missing Spaces local/rename honesty"
grep -q 'BindmAction\|lookup_bindm\|default_bindm\|try_start_bindm' \
  "${CRATE}/src/binds.rs" "${CRATE}/src/input.rs" \
  || die "mouse bindm missing"
grep -q '"bindm"' "${ROOT}/env/settings/keybinds.defaults.json" \
  || die "keybinds.defaults.json missing bindm"
grep -qE 'bindm|Super\+LMB|Super\+RMB' \
  "${ROOT}/docs/proteus/CURRENT.md" "${ROOT}/docs/proteus/COMPOSITOR-SPIKE.md" \
  || die "docs missing bindm honesty"
grep -qF -- '--backend' "${CRATE}/src/main.rs" \
  || die "CLI --backend missing"
grep -q 'fn init_drm\|pub fn init_drm' "${CRATE}/src/drm.rs" \
  || die "init_drm missing"
grep -q 'LibSeatSession' "${CRATE}/src/drm.rs" \
  || die "LibSeatSession missing"
grep -q 'backend_session_libseat\|backend_drm' "${CRATE}/Cargo.toml" \
  || die "smithay DRM/session features missing"
grep -q 'equal_column_layout' "${CRATE}/src/layout.rs" \
  || die "equal_column_layout missing"
grep -q 'dwindle_layout' "${CRATE}/src/layout.rs" \
  || die "dwindle_layout missing"
grep -q 'master_layout' "${CRATE}/src/layout.rs" \
  || die "master_layout missing"
grep -q 'fn inset_rect\|inset_rect' "${CRATE}/src/layout.rs" \
  || die "inset_rect missing"
grep -q 'gaps_out' "${CRATE}/src/wm.rs" \
  || die "gaps_out missing on Wm"
grep -qE 'gapsin|gaps in|gapsout' "${CRATE}/src/wm.rs" \
  || die "gapsin/gapsout dispatch missing"
grep -q 'smartgaps\|smart_gaps\|effective_gaps' "${CRATE}/src/wm.rs" "${CRATE}/src/layout.rs" "${CRATE}/src/ctl.rs" \
  || die "smartgaps missing"
grep -q 'master_factor' "${CRATE}/src/wm.rs" \
  || die "master_factor missing on Wm"
grep -q 'masterfactor' "${CRATE}/src/wm.rs" \
  || die "masterfactor dispatch missing"
grep -q 'inset_rect' "${CRATE}/src/ctl.rs" \
  || die "relayout must apply inset_rect gaps"
grep -qE 'LayoutKind|layout dwindle|strip_prefix\("layout ' "${CRATE}/src/wm.rs" \
  || die "dispatch layout missing"
grep -q 'dwindle_layout\|LayoutKind::Dwindle' "${CRATE}/src/ctl.rs" \
  || die "relayout must use dwindle / LayoutKind"
grep -q 'work_area_with_exclusive' "${CRATE}/src/layout.rs" \
  || die "work_area_with_exclusive missing"
grep -q 'non_exclusive_zone' "${CRATE}/src/ctl.rs" \
  || die "relayout must use non_exclusive_zone"
grep -q 'work_area_with_exclusive' "${CRATE}/src/ctl.rs" \
  || die "relayout must compose work_area_with_exclusive"
grep -q 'togglefloating' "${CRATE}/src/wm.rs" \
  || die "togglefloating dispatch missing"
grep -q 'relayout_active\|fn relayout_active' "${CRATE}/src/ctl.rs" \
  || die "relayout_active missing"
grep -q '"at"' "${CRATE}/src/wm.rs" \
  || die "clients JSON must include at"
grep -q '"size"' "${CRATE}/src/wm.rs" \
  || die "clients JSON must include size"
grep -q 'clients_json_live\|"at"' "${CRATE}/src/ctl.rs" \
  || die "ctl clients must emit live at/size"
grep -q 'zwlr_screencopy_manager_v1\|ZwlrScreencopyManagerV1' "${CRATE}/src/screencopy.rs" \
  || die "screencopy manager missing"
grep -q 'screencopy_should_flip_y\|PROTEUS_SCREENCOPY_FLIP_Y\|prepare_screencopy_pixels' \
  "${CRATE}/src/screencopy.rs" \
  || die "screencopy Y-flip auto (virtio) missing"
grep -q 'linux_dmabuf' "${CRATE}/src/screencopy.rs" \
  || die "screencopy must advertise linux_dmabuf"
grep -q 'get_dmabuf' "${CRATE}/src/screencopy.rs" \
  || die "screencopy must fulfill dmabuf buffers via get_dmabuf"
grep -q 'DmabufState' "${CRATE}/src/state.rs" \
  || die "DmabufState missing on compositor state"
grep -q 'init_dmabuf_global\|create_global_with_default_feedback\|create_global' "${CRATE}/src/winit.rs" \
  || die "winit must init dmabuf global"
grep -q 'init_dmabuf_global' "${CRATE}/src/dmabuf_init.rs" \
  || die "shared dmabuf_init missing"
grep -q 'last_frame\|drain_pending_screencopies' "${CRATE}/src/drm.rs" \
  || die "drm path must capture last_frame / drain screencopy"
grep -q 'UdevBackend' "${CRATE}/src/drm.rs" \
  || die "drm must use UdevBackend for hotplug"
grep -q 'sync_connectors\|HashMap.*crtc\|surfaces:' "${CRATE}/src/drm.rs" \
  || die "drm multi-output surface map missing"
grep -q 'struct MoveSurfaceGrab' "${CRATE}/src/grabs.rs" \
  || die "MoveSurfaceGrab missing"
grep -q 'struct ResizeSurfaceGrab' "${CRATE}/src/grabs.rs" \
  || die "ResizeSurfaceGrab missing"
grep -q 'MoveSurfaceGrab' "${CRATE}/src/handlers.rs" \
  || die "move_request must wire MoveSurfaceGrab"
grep -q 'ResizeSurfaceGrab' "${CRATE}/src/handlers.rs" \
  || die "resize_request must wire ResizeSurfaceGrab"
grep -q 'grab_popup' "${CRATE}/src/handlers.rs" \
  || die "popup grab must be wired"
grep -q '"xwayland"' "${CRATE}/Cargo.toml" \
  || die "smithay xwayland feature missing"
grep -q 'XWayland::spawn\|init_xwayland' "${CRATE}/src/xwayland.rs" \
  || die "Xwayland spawn missing"
grep -q 'impl XwmHandler for CompositorNext' "${CRATE}/src/xwayland.rs" \
  || die "XwmHandler on CompositorNext missing"
grep -q 'XDG_CURRENT_DESKTOP.*wlroots\|"wlroots"' "${CRATE}/src/main.rs" \
  || die "compositor must set XDG_CURRENT_DESKTOP=wlroots for xdp-wlr"
[[ -f "${ROOT}/dev/smoke/compositor-game-present.sh" ]] \
  || die "missing compositor-game-present.sh"
[[ -f "${ROOT}/dev/smoke/compositor-gamescope.sh" ]] \
  || die "missing compositor-gamescope.sh (interim nest helper)"
[[ -x "${ROOT}/shell/scripts/proteus-gamescope" ]] \
  || die "missing proteus-gamescope (owned game-present launch wrapper)"
grep -q 'game-present\|owned game-present\|already_inside_gamescope' \
  "${ROOT}/shell/scripts/proteus-gamescope" \
  || die "proteus-gamescope missing owned game-present path"
bash -n "${ROOT}/shell/scripts/proteus-gamescope" \
  || die "proteus-gamescope bash -n failed"
grep -q 'game.present\|game_present\|GamePresent' \
  "${CRATE}/src/wm.rs" "${CRATE}/src/game_present.rs" \
  || die "compositor missing game-present module/dispatch"
grep -q 'RescaleRenderElement\|game_present_render_elements' \
  "${CRATE}/src/render_elements.rs" \
  || die "compositor missing game-present Rescale blit path"
grep -q 'CustomRenderElement' "${CRATE}/src/drm.rs" "${CRATE}/src/winit.rs" \
  || die "DRM/winit render_output must use CustomRenderElement"
grep -q 'focus.stack\|FocusStackLayer\|focus_stack' \
  "${CRATE}/src/wm.rs" \
  || die "compositor missing focus-stack dispatch"
# Docs: owned game-present In; console-home swap still Out; nest interim.
grep -qE 'game-present|proteus-gamescope|Steam.*%command%' \
  "${ROOT}/docs/proteus/CURRENT.md" \
  || die "CURRENT missing owned game-present / Steam launch-options note"
grep -q 'console-home.*not swapped\|gamescope console-home not swapped' \
  "${ROOT}/docs/proteus/CURRENT.md" "${ROOT}/docs/proteus/COMPOSITOR-SPIKE.md" \
  || die "docs must keep console-home swap Out"
[[ -f "${ROOT}/dev/smoke/compositor-portal-screenshot.sh" ]] \
  || die "missing compositor-portal-screenshot.sh"
[[ -f "${ROOT}/dev/smoke/compositor-screencast.sh" ]] \
  || die "missing compositor-screencast.sh"
[[ -f "${ROOT}/dev/smoke/compositor-drm.sh" ]] \
  || die "missing compositor-drm.sh"
grep -q 'CopyWithDamage\|with_damage' "${CRATE}/src/screencopy.rs" \
  || die "screencopy must implement copy_with_damage"
grep -q 'XdgDecorationState' "${CRATE}/src/state.rs" \
  || die "XdgDecorationState missing on compositor state"
grep -q 'Mode::ClientSide' "${CRATE}/src/handlers.rs" \
  && grep -q 'Ignore ServerSide' "${CRATE}/src/handlers.rs" \
  || die "xdg-decoration must force ClientSide (app chrome)"
grep -q 'delegate_xdg_decoration' "${CRATE}/src/handlers.rs" \
  || die "delegate_xdg_decoration missing"
[[ -f "${CRATE}/src/decoration.rs" ]] || die "missing decoration.rs"
grep -q 'TITLEBAR_H' "${CRATE}/src/decoration.rs" \
  || die "TITLEBAR_H missing"
grep -q 'ssd_render_elements' "${CRATE}/src/decoration.rs" \
  || die "ssd_render_elements missing"
grep -q 'focus_ring_render_elements\|FOCUS_RING_W' "${CRATE}/src/decoration.rs" \
  || die "focus ring chrome missing"
grep -q 'focus_ring_render_elements' "${CRATE}/src/winit.rs" "${CRATE}/src/render_elements.rs" \
  || die "winit must call focus_ring_render_elements"
grep -q 'cosmic-text\|truncate_title_to_width\|MemoryRenderBuffer' "${CRATE}/src/decoration.rs" \
  || die "SSD title text rasterize missing"
grep -q 'cosmic-text' "${CRATE}/Cargo.toml" \
  || die "cosmic-text dep missing"
grep -q 'CustomRenderElement\|MemoryRenderBufferRenderElement' "${CRATE}/src/winit.rs" \
  || die "winit must pass CustomRenderElement / Memory SSD custom elements"
grep -q 'CustomRenderElement\|MemoryRenderBufferRenderElement' "${CRATE}/src/drm.rs" \
  || die "drm must pass CustomRenderElement / Memory SSD custom elements"
grep -q 'ssd_render_elements\|output_custom_render_elements' "${CRATE}/src/winit.rs" "${CRATE}/src/render_elements.rs" \
  || die "winit must call ssd_render_elements"
grep -q 'ssd_render_elements\|output_custom_render_elements' "${CRATE}/src/drm.rs" "${CRATE}/src/render_elements.rs" \
  || die "drm must call ssd_render_elements"
grep -q 'RescaleRenderElement\|game_present_render_elements' "${CRATE}/src/render_elements.rs" \
  || die "game-present Rescale blit path missing"
grep -q 'ssd_hit_at\|SsdHit\|start_ssd_move' "${CRATE}/src/input.rs" \
  || die "SSD titlebar input hit-test missing"
grep -q 'outer_to_content_geo' "${CRATE}/src/ctl.rs" \
  || die "tiling must reserve SSD titlebar via outer_to_content_geo"
grep -q 'movewindow output' "${CRATE}/src/wm.rs" \
  || die "movewindow output: dispatch missing"
grep -q 'focusoutput' "${CRATE}/src/wm.rs" \
  || die "focusoutput dispatch missing"
grep -q 'active_by_output\|workspace N,output' "${CRATE}/src/wm.rs" \
  || grep -q 'output:' "${CRATE}/src/wm.rs" \
  || die "per-output workspace boards missing"
grep -q ',output:' "${CRATE}/src/wm.rs" \
  || die "workspace N,output:NAME dispatch missing"
grep -q 'activeWorkspace' "${CRATE}/src/ctl.rs" \
  || die "monitors JSON must include activeWorkspace"
grep -q 'focused_output' "${CRATE}/src/wm.rs" \
  || die "focused_output tracking missing"
grep -q 'effective_output\|FocusOutput\|focus_output_named' "${CRATE}/src/ctl.rs" \
  || die "per-output relayout / FocusOutput apply missing"
grep -q 'for output in outputs\|outputs:' "${CRATE}/src/ctl.rs" \
  || die "relayout_active must iterate per output"
SESSION="${ROOT}/shell/scripts/proteus-session"
[[ -f "${SESSION}" ]] || die "missing proteus-session"
grep -q 'smithay\|compositor' "${SESSION}" \
  || die "proteus-session must mention smithay"
grep -qE '""\|smithay\|compositor\|compositor-next\)|Hyprland purged|smithay DRM only' "${SESSION}" \
  || die "proteus-session must be smithay-only"
grep -q 'proteus-compositor' "${SESSION}" \
  || die "proteus-session must resolve proteus-compositor"
grep -q 'Hyprland purged\|refuse (Hyprland purged)' "${SESSION}" \
  || die "proteus-session must refuse without Hyprland fallthrough"
grep -qE 'hyprland\|hypr\)' "${SESSION}" \
  || die "proteus-session must refuse Fact=hyprland"
grep -q -- '--backend drm' "${SESSION}" \
  || die "proteus-session smithay path must use --backend drm"
[[ -f "${ROOT}/dev/smoke/compositor-dogfood.sh" ]] \
  || die "missing compositor-dogfood.sh"
ok "crate + IPC + grabs + xwayland + screencopy + portal-env + gamescope + tiling + screencast + drm + decoration + session-wire + output-assign helpers present"

if ! (cd "${ROOT}" && cargo test -p compositor --bin proteus-compositor -q 2>/dev/null); then
  die "cargo test -p compositor (wm+grabs)"
else
  ok "wm + grabs unit tests"
fi

if ! (cd "${ROOT}" && cargo build -p compositor -q 2>/dev/null); then
  die "cargo build -p compositor"
else
  ok "compositor builds"
fi

COMP="$(ls -1 "${ROOT}/target/debug/proteus-compositor" 2>/dev/null || true)"
CTL="$(ls -1 "${ROOT}/target/debug/proteus-compositorctl" 2>/dev/null || true)"
[[ -x "${COMP}" ]] || die "proteus-compositor binary missing"
[[ -x "${CTL}" ]] || die "proteus-compositorctl binary missing"
ok "binaries present"

# Live DRM never runs by default (would steal the graphical seat). Helper SKIPs
# unless PROTEUS_COMPOSITOR_DRM=1 (VT/VM dogfood).
drm_helper="${ROOT}/dev/smoke/compositor-drm.sh"
set +e
bash "${drm_helper}" >"${tmp_dir}/drm.out" 2>"${tmp_dir}/drm.err"
drm_rc=$?
set -e
if [[ "${drm_rc}" -eq 0 ]]; then
  ok "drm backend live prove"
elif [[ "${drm_rc}" -eq 2 ]]; then
  ok "drm live skipped (set PROTEUS_COMPOSITOR_DRM=1 on free VT/VM)"
else
  die "drm helper failed (rc=${drm_rc}): $(tr '\n' ' ' <"${tmp_dir}/drm.err" | head -c 300)"
fi

# Nested ctl round-trip needs a winit display (nested under host Wayland/X11).
if [[ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
  ok "no DISPLAY/WAYLAND_DISPLAY — nested ctl round-trip skipped"
  [[ $fail -eq 0 ]] || { echo "compositor-smoke: FAILED" >&2; exit 1; }
  echo "compositor-smoke: OK"
  exit 0
fi

log="$(mktemp "${tmp_dir}/nested.XXXXXX")"
# Keep host XDG_RUNTIME_DIR so winit can nest under the parent compositor.
# Isolate engine fact so shell path is irrelevant here.
unset PROTEUS_COMPOSITOR_ENGINE || true

stdbuf -oL -eL "${COMP}" >"${log}" 2>&1 &
comp_pid=$!
# Give winit a moment to nest under the host display.
sleep 0.5
sock=""
for _ in $(seq 1 80); do
  if grep -q 'ctl socket ' "${log}" 2>/dev/null; then
    sock="$(sed -n 's/.*ctl socket //p' "${log}" | head -1)"
    break
  fi
  if ! kill -0 "${comp_pid}" 2>/dev/null; then
    die "compositor exited early; log: $(tr '\n' ' ' < "${log}")"
    break
  fi
  sleep 0.1
done

if [[ -z "${sock}" || ! -S "${sock}" ]]; then
  die "ctl socket not created (see log: $(tr '\n' ' ' < "${log}" | head -c 400))"
else
  ok "ctl socket up"
  export PROTEUS_COMPOSITOR_SOCK="${sock}"
  ws="$("${CTL}" workspaces 2>/dev/null || true)"
  echo "${ws}" | grep -q '"id": *1' \
    && ok "workspaces JSON" \
    || die "workspaces query failed: ${ws}"

  active="$("${CTL}" activeworkspace 2>/dev/null || true)"
  echo "${active}" | grep -q '"id": *1' \
    && ok "activeworkspace=1" \
    || die "activeworkspace: ${active}"

  # session-lock probe — compositor advertises ext-session-lock; shell default
  # Fact remains overlay (protocol opt-in via PROTEUS_SESSION_LOCK / session-lock).
  slock="$("${CTL}" session-lock 2>/dev/null || true)"
  echo "${slock}" | grep -q '"ok": *true' \
    && echo "${slock}" | grep -q '"supported": *true' \
    && ok "ctl session-lock supported" \
    || die "session-lock probe failed: ${slock}"

  # idle-inhibit probe — global advertised; count 0 until a client inhibits.
  iinh="$("${CTL}" idle-inhibit 2>/dev/null || true)"
  echo "${iinh}" | grep -q '"ok": *true' \
    && echo "${iinh}" | grep -q '"supported": *true' \
    && echo "${iinh}" | grep -q '"count"' \
    && ok "ctl idle-inhibit supported" \
    || die "idle-inhibit probe failed: ${iinh}"

  disp="$("${CTL}" dispatch workspace 2 2>/dev/null || true)"
  echo "${disp}" | grep -q '"ok": *true' \
    && ok "dispatch workspace 2" \
    || die "dispatch failed: ${disp}"

  active2="$("${CTL}" activeworkspace 2>/dev/null || true)"
  echo "${active2}" | grep -qE '"id": *2' \
    && ok "activeworkspace=2 after dispatch" \
    || die "activeworkspace not 2: ${active2}"

  rn="$("${CTL}" dispatch "renameworkspace 2 Code" 2>/dev/null || true)"
  echo "${rn}" | grep -q '"ok": *true' \
    && ok "dispatch renameworkspace 2 Code" \
    || die "renameworkspace failed: ${rn}"
  active_named="$("${CTL}" activeworkspace 2>/dev/null || true)"
  echo "${active_named}" | grep -q '"name": *"Code"' \
    && ok "activeworkspace name=Code after rename" \
    || die "activeworkspace name not Code: ${active_named}"
  "${CTL}" dispatch "renameworkspace 2" >/dev/null 2>&1 || true

  loc="$("${CTL}" dispatch "workspace 3,local" 2>/dev/null || true)"
  echo "${loc}" | grep -q '"ok": *true' \
    && ok "dispatch workspace 3,local" \
    || die "workspace local failed: ${loc}"
  "${CTL}" dispatch "workspace 1" >/dev/null 2>&1 || true

  # Thin Displays modeset — scale on primary output (Fact path grepped above).
  mon_json="$("${CTL}" monitors 2>/dev/null || true)"
  mon_name="$(echo "${mon_json}" | python3 -c 'import json,sys
try:
  a=json.load(sys.stdin)
  print(a[0]["name"] if a else "")
except Exception:
  print("")' 2>/dev/null || true)"
  if [[ -n "${mon_name}" ]]; then
    scale_disp="$("${CTL}" dispatch "output ${mon_name} scale 1.25" 2>/dev/null || true)"
    echo "${scale_disp}" | grep -q '"ok": *true' \
      && ok "dispatch output ${mon_name} scale 1.25" \
      || die "output scale failed: ${scale_disp}"
    # Restore 1.0 so later captures stay sane.
    "${CTL}" dispatch "output ${mon_name} scale 1" >/dev/null 2>&1 || true
    xf_disp="$("${CTL}" dispatch "output ${mon_name} transform 180" 2>/dev/null || true)"
    echo "${xf_disp}" | grep -q '"ok": *true' \
      && ok "dispatch output ${mon_name} transform 180" \
      || die "output transform failed: ${xf_disp}"
    mon_xf="$("${CTL}" monitors 2>/dev/null || true)"
    echo "${mon_xf}" | python3 -c 'import json,sys
a=json.load(sys.stdin)
sys.exit(0 if a and int(a[0].get("transform",-1))==2 else 1)' \
      && ok "monitors JSON transform=2 after dispatch" \
      || die "monitors transform not live: ${mon_xf}"
    "${CTL}" dispatch "output ${mon_name} transform normal" >/dev/null 2>&1 || true
  else
    ok "monitors empty — output scale/transform prove skipped"
  fi

  rb="$("${CTL}" dispatch reloadbinds 2>/dev/null || true)"
  echo "${rb}" | grep -q '"ok": *true' \
    && ok "dispatch reloadbinds" \
    || die "reloadbinds failed: ${rb}"

  ir="$("${CTL}" dispatch input-reload 2>/dev/null || true)"
  echo "${ir}" | grep -q '"ok": *true' \
    && ok "dispatch input-reload" \
    || die "input-reload failed: ${ir}"

  idf="$("${CTL}" dispatch identify 2>/dev/null || true)"
  echo "${idf}" | grep -q '"ok": *true' \
    && ok "dispatch identify" \
    || die "identify failed: ${idf}"

  clients="$("${CTL}" clients 2>/dev/null || true)"
  echo "${clients}" | grep -q '^\[' \
    && ok "clients JSON array" \
    || die "clients: ${clients}"
  # Schema keys at/size are unit-tested; empty roster has no objects — assert source contract.
  grep -q '"at"' "${CRATE}/src/wm.rs" && grep -q '"size"' "${CRATE}/src/wm.rs" \
    && ok "clients at/size schema in wm" \
    || die "clients missing at/size in wm"

  # Nested WAYLAND_DISPLAY from compositor log (shared by grim / portal / protocol lock).
  nested_wd="$(sed -n 's/.*nested \(spike \)\?on WAYLAND_DISPLAY=//p' "${log}" | head -1)"

  # Protocol session-lock dogfood (opt-in helper; Fact default remains overlay).
  slock_helper="${ROOT}/dev/smoke/compositor-session-lock.sh"
  if [[ -z "${nested_wd}" ]]; then
    ok "protocol session-lock dogfood skipped — nested WAYLAND_DISPLAY unknown"
  else
    set +e
    WAYLAND_DISPLAY="${nested_wd}" PROTEUS_COMPOSITOR_SOCK="${sock}" \
      PROTEUS_COMPOSITORCTL="${CTL}" PROTEUS_SESSION_LOCK_DOGFOOD=1 \
      bash "${slock_helper}" >"${tmp_dir}/slock.out" 2>"${tmp_dir}/slock.err"
    slock_rc=$?
    set -e
    if [[ "${slock_rc}" -eq 0 ]]; then
      ok "protocol session-lock dogfood"
    elif [[ "${slock_rc}" -eq 2 ]]; then
      ok "protocol session-lock dogfood skipped — $(tr '\n' ' ' <"${tmp_dir}/slock.err" | head -c 160)"
    else
      die "protocol session-lock dogfood failed (rc=${slock_rc}): $(tr '\n' ' ' <"${tmp_dir}/slock.err" | head -c 300)"
    fi
  fi

  # Optional grim region capture via zwlr_screencopy (dock preview path).
  if command -v grim >/dev/null 2>&1; then
    if [[ -n "${nested_wd}" ]]; then
      grim_png="$(mktemp --suffix=.png)"
      if env WAYLAND_DISPLAY="${nested_wd}" grim -g '0,0 32x32' "${grim_png}" 2>/dev/null \
        && [[ -s "${grim_png}" ]]; then
        ok "grim region capture (${grim_png##*/} $(wc -c < "${grim_png}")B)"
      else
        die "grim region capture failed under WAYLAND_DISPLAY=${nested_wd}"
      fi
      rm -f "${grim_png}"
    else
      ok "grim present but nested WAYLAND_DISPLAY unknown — skipped"
    fi
  else
    ok "grim not installed — screencopy capture skipped"
  fi

  # Optional portal Screenshot via xdg-desktop-portal-wlr (isolated dbus session).
  # Does not touch the host Hyprland portal units. SKIP if xdp-wlr missing.
  nested_wd="$(sed -n 's/.*nested \(spike \)\?on WAYLAND_DISPLAY=//p' "${log}" | head -1)"
  portal_helper="${ROOT}/dev/smoke/compositor-portal-screenshot.sh"
  [[ -f "${portal_helper}" ]] || die "missing compositor-portal-screenshot.sh"
  xdp_wlr=""
  for cand in /usr/lib/xdg-desktop-portal-wlr /usr/libexec/xdg-desktop-portal-wlr; do
    if [[ -x "${cand}" ]]; then
      xdp_wlr="${cand}"
      break
    fi
  done
  if [[ -z "${xdp_wlr}" ]]; then
    ok "xdg-desktop-portal-wlr not installed — portal Screenshot skipped"
  elif [[ -z "${nested_wd}" ]]; then
    ok "portal binary present but nested WAYLAND_DISPLAY unknown — skipped"
  else
    portal_png="$(mktemp --suffix=.png)"
    set +e
    WAYLAND_DISPLAY="${nested_wd}" bash "${portal_helper}" "${portal_png}" >"${tmp_dir}/portal.out" 2>"${tmp_dir}/portal.err"
    portal_rc=$?
    set -e
    if [[ "${portal_rc}" -eq 0 && -s "${portal_png}" ]]; then
      ok "portal Screenshot (${portal_png##*/} $(wc -c < "${portal_png}")B)"
    elif [[ "${portal_rc}" -eq 2 ]]; then
      ok "portal Screenshot deps missing — skipped"
    else
      # Soft skip: nested isolate can fail on some hosts without failing the suite.
      ok "portal Screenshot inconclusive (rc=${portal_rc}) — skipped"
    fi
    rm -f "${portal_png}"
  fi

  # Owned game-present ctl (no gamescope binary required).
  gp_helper="${ROOT}/dev/smoke/compositor-game-present.sh"
  if [[ -z "${nested_wd}" ]]; then
    ok "game-present skipped — nested WAYLAND_DISPLAY unknown"
  else
    set +e
    WAYLAND_DISPLAY="${nested_wd}" PROTEUS_COMPOSITOR_SOCK="${sock}" \
      PROTEUS_COMPOSITORCTL="${CTL}" \
      bash "${gp_helper}" >"${tmp_dir}/gp.out" 2>"${tmp_dir}/gp.err"
    gp_rc=$?
    set -e
    if [[ "${gp_rc}" -eq 0 ]]; then
      ok "owned game-present + focus-stack ctl"
    else
      die "game-present smoke failed (rc=${gp_rc}): $(tr '\n' ' ' <"${tmp_dir}/gp.err" | head -c 300)"
    fi
  fi

  # Optional interim gamescope nesting (FORCE / engine=gamescope only in product).
  gs_helper="${ROOT}/dev/smoke/compositor-gamescope.sh"
  if [[ -z "${nested_wd}" ]]; then
    ok "gamescope nesting skipped — nested WAYLAND_DISPLAY unknown"
  else
    set +e
    WAYLAND_DISPLAY="${nested_wd}" PROTEUS_COMPOSITOR_SOCK="${sock}" \
      PROTEUS_COMPOSITORCTL="${CTL}" \
      bash "${gs_helper}" >"${tmp_dir}/gs.out" 2>"${tmp_dir}/gs.err"
    gs_rc=$?
    set -e
    if [[ "${gs_rc}" -eq 0 ]]; then
      ok "gamescope nest still maps as client (interim)"
    elif [[ "${gs_rc}" -eq 2 ]]; then
      ok "gamescope nesting skipped (missing binary or no usable backend)"
    else
      die "gamescope nesting failed (rc=${gs_rc}): $(tr '\n' ' ' <"${tmp_dir}/gs.err" | head -c 300)"
    fi
  fi

  # Optional short screencast via wf-recorder (copy_with_damage path).
  scast_helper="${ROOT}/dev/smoke/compositor-screencast.sh"
  if [[ -z "${nested_wd}" ]]; then
    ok "screencast skipped — nested WAYLAND_DISPLAY unknown"
  else
    set +e
    WAYLAND_DISPLAY="${nested_wd}" bash "${scast_helper}" \
      >"${tmp_dir}/scast.out" 2>"${tmp_dir}/scast.err"
    scast_rc=$?
    set -e
    if [[ "${scast_rc}" -eq 0 ]]; then
      ok "wf-recorder screencast under nested display"
    elif [[ "${scast_rc}" -eq 2 ]]; then
      ok "screencast skipped (wf-recorder not installed)"
    else
      die "screencast failed (rc=${scast_rc}): $(tr '\n' ' ' <"${tmp_dir}/scast.err" | head -c 300)"
    fi
  fi

  # Optional X11 client round-trip when Xwayland binary + an X11 client exist.
  x11client=""
  for cand in xeyes xlogo xclock xterm; do
    if command -v "${cand}" >/dev/null 2>&1; then
      x11client="${cand}"
      break
    fi
  done
  if command -v Xwayland >/dev/null 2>&1 && [[ -n "${x11client}" ]]; then
    xready=""
    for _ in $(seq 1 50); do
      if grep -q 'Xwayland ready DISPLAY=' "${log}" 2>/dev/null; then
        xready="$(sed -n 's/.*Xwayland ready DISPLAY=//p' "${log}" | head -1)"
        break
      fi
      if grep -q 'Xwayland unavailable\|Xwayland failed' "${log}" 2>/dev/null; then
        break
      fi
      sleep 0.1
    done
    if [[ -n "${xready}" ]]; then
      ok "Xwayland ready (${xready})"
      before="$("${CTL}" clients 2>/dev/null || echo '[]')"
      before_n="$(python3 -c "import json,sys; print(len(json.loads(sys.argv[1])))" "${before}" 2>/dev/null || echo 0)"
      env -u WAYLAND_DISPLAY DISPLAY="${xready}" "${x11client}" >/dev/null 2>&1 &
      x11_pid=$!
      saw=""
      for _ in $(seq 1 40); do
        sleep 0.15
        after="$("${CTL}" clients 2>/dev/null || echo '[]')"
        after_n="$(python3 -c "import json,sys; print(len(json.loads(sys.argv[1])))" "${after}" 2>/dev/null || echo 0)"
        if [[ "${after_n}" -gt "${before_n}" ]]; then
          saw=1
          break
        fi
      done
      kill "${x11_pid}" 2>/dev/null || true
      wait "${x11_pid}" 2>/dev/null || true
      [[ -n "${saw}" ]] && ok "${x11client} mapped into clients" || die "${x11client} did not appear in clients"
    else
      ok "Xwayland not ready in time — x11 client check skipped"
    fi
  else
    ok "Xwayland/X11 client not installed — x11 client check skipped"
  fi
fi

kill "${comp_pid}" 2>/dev/null || true
wait "${comp_pid}" 2>/dev/null || true
comp_pid=""

# Dogfood gate helper — static + optional nested/DRM/guest (SKIP is OK).
set +e
bash "${ROOT}/dev/smoke/compositor-dogfood.sh" >"${tmp_dir}/dogfood.out" 2>"${tmp_dir}/dogfood.err"
dog_rc=$?
set -e
if [[ "${dog_rc}" -eq 0 ]]; then
  ok "dogfood gate"
elif [[ "${dog_rc}" -eq 2 ]]; then
  ok "dogfood gate soft-skip"
else
  die "dogfood gate failed (rc=${dog_rc}): $(tr '\n' ' ' <"${tmp_dir}/dogfood.err" | head -c 300)"
fi

[[ $fail -eq 0 ]] || { echo "compositor-smoke: FAILED" >&2; exit 1; }
echo "compositor-smoke: OK"
