//! Control socket — JSON query / dispatch for proteus-shell (smithay backend).
//!
//! Line protocol on `$XDG_RUNTIME_DIR/proteus-compositor-$WAYLAND_DISPLAY.sock`
//! (also exported as `PROTEUS_COMPOSITOR_SOCK`):
//! - `workspaces` | `activeworkspace` | `clients` | `activewindow` | `monitors` → one JSON line
//! - `dispatch <verb>` → `{"ok":true}` or `{"ok":false,"error":"..."}`
//! - `subscribe` → keep connection; NDJSON events (`workspace>>…`, etc.)

use std::{
    io::{BufRead, BufReader, Write},
    os::unix::net::{UnixListener, UnixStream},
    path::PathBuf,
    sync::{Arc, Mutex},
};

use smithay::desktop::layer_map_for_output;
use smithay::reexports::calloop::{channel, EventLoop};
use smithay::reexports::wayland_protocols::xdg::shell::server::xdg_toplevel;
use smithay::utils::{Logical, Rectangle, SERIAL_COUNTER};

use crate::layout::{
    dwindle_layout, effective_gaps, equal_column_layout, inset_rect, master_layout,
    work_area_with_exclusive,
};
use crate::decoration::outer_to_content_geo;
use crate::{wm::{LayoutKind, WmOp}, CalloopData, CompositorNext};

pub struct CtlClient {
    pub line: String,
    pub stream: UnixStream,
}

pub type CtlSubscribers = Arc<Mutex<Vec<UnixStream>>>;

pub fn ctl_socket_path(wayland_display: &str) -> PathBuf {
    let runtime = std::env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| "/tmp".into());
    let safe = wayland_display.replace('/', "_");
    PathBuf::from(runtime).join(format!("proteus-compositor-{safe}.sock"))
}

pub fn init_ctl(
    event_loop: &mut EventLoop<'static, CalloopData>,
    state: &mut CompositorNext,
) -> Result<PathBuf, Box<dyn std::error::Error>> {
    let wayland = state.socket_name.to_string_lossy().to_string();
    let path = ctl_socket_path(&wayland);
    if path.exists() {
        let _ = std::fs::remove_file(&path);
    }

    let listener = UnixListener::bind(&path)?;
    let (tx, rx) = channel::channel::<CtlClient>();
    std::thread::Builder::new()
        .name("proteus-compositor-ctl".into())
        .spawn(move || ctl_accept_loop(listener, tx))?;

    event_loop
        .handle()
        .insert_source(rx, |event, _, data| {
            if let channel::Event::Msg(client) = event {
                data.state.handle_ctl_client(client);
            }
        })
        .map_err(|e| format!("ctl channel: {e}"))?;

    state.ctl_path = Some(path.clone());
    std::env::set_var("PROTEUS_COMPOSITOR_SOCK", &path);
    eprintln!(
        "proteus-compositor: ctl socket {}",
        path.display()
    );
    Ok(path)
}

fn ctl_accept_loop(listener: UnixListener, tx: channel::Sender<CtlClient>) {
    for stream in listener.incoming() {
        let Ok(stream) = stream else {
            continue;
        };
        let Ok(cloned) = stream.try_clone() else {
            continue;
        };
        let tx = tx.clone();
        std::thread::spawn(move || {
            let mut reader = BufReader::new(cloned);
            let mut line = String::new();
            match reader.read_line(&mut line) {
                Ok(0) => {}
                Ok(_) => {
                    let line = line.trim().to_string();
                    if !line.is_empty() {
                        let _ = tx.send(CtlClient { line, stream });
                    }
                }
                Err(_) => {}
            }
        });
    }
}

impl CompositorNext {
    pub fn handle_ctl_client(&mut self, mut client: CtlClient) {
        if client.line == "subscribe" {
            if let Ok(mut guard) = self.ctl_subscribers.lock() {
                guard.push(client.stream);
            }
            return;
        }

        let response = self.handle_ctl_line(&client.line);
        let _ = writeln!(client.stream, "{response}");
        let _ = client.stream.flush();
    }

    pub fn handle_ctl_line(&mut self, line: &str) -> String {
        let line = line.trim();
        if let Some(rest) = line.strip_prefix("dispatch ") {
            let rest = rest.trim();
            if rest == "reloadbinds" || rest == "reload keybinds" {
                self.binds.reload();
                return serde_json::json!({"ok": true}).to_string();
            }
            if rest == "input-reload" || rest == "reload input" {
                self.input_config.reload();
                eprintln!(
                    "proteus-compositor: input-reload sensitivity={} scale={:.3} natural={} tap={} scroll={}",
                    self.input_config.sensitivity,
                    self.input_config.sensitivity_scale(),
                    self.input_config.natural_scroll,
                    self.input_config.tap_to_click,
                    self.input_config.scroll_factor
                );
                return serde_json::json!({"ok": true}).to_string();
            }
            if rest == "identify" || rest.starts_with("identify ") {
                let arg = rest.strip_prefix("identify").unwrap_or("").trim();
                match crate::identify::parse_identify_secs(arg) {
                    Ok(secs) => {
                        self.start_identify(secs);
                        self.broadcast_event("dispatch>>identify");
                        return serde_json::json!({"ok": true}).to_string();
                    }
                    Err(e) => {
                        return serde_json::json!({"ok": false, "error": e}).to_string();
                    }
                }
            }
            match self.wm.dispatch(rest) {
                Ok(ops) => {
                    self.apply_wm_ops(ops);
                    self.broadcast_event(&format!("dispatch>>{rest}"));
                    if rest.starts_with("workspace ") {
                        let out = self
                            .wm
                            .focused_output
                            .clone()
                            .unwrap_or_else(|| self.primary_output_name());
                        self.broadcast_event(&format!(
                            "workspace>>{}>>{}",
                            self.wm.active_workspace, out
                        ));
                        // Compat: shell may still parse bare id form.
                        self.broadcast_event(&format!("workspace>>{}", self.wm.active_workspace));
                    }
                    serde_json::json!({"ok": true}).to_string()
                }
                Err(e) => serde_json::json!({"ok": false, "error": e}).to_string(),
            }
        } else if line == "session-lock" {
            serde_json::json!({"ok": true, "supported": true}).to_string()
        } else if line == "clients" {
            // Prefer live Space / Window geometry for hypr-shaped at/size.
            self.clients_json_live().to_string()
        } else if line == "monitors" {
            // Registers outputs into per-monitor board state.
            self.monitors_json_live().to_string()
        } else {
            match self.wm.query(line) {
                Ok(v) => v.to_string(),
                Err(e) => serde_json::json!({"ok": false, "error": e}).to_string(),
            }
        }
    }

    /// Hypr-shaped monitors list from Space outputs.
    pub fn monitors_json_live(&mut self) -> serde_json::Value {
        use serde_json::{json, Value};
        let names: Vec<String> = self.space.outputs().map(|o| o.name()).collect();
        for name in &names {
            self.wm.ensure_output(name);
        }
        let focused_name = self
            .wm
            .focused_output
            .clone()
            .or_else(|| names.first().cloned());
        let arr: Vec<Value> = self
            .space
            .outputs()
            .map(|output| {
                let geo = self.space.output_geometry(output).unwrap_or_else(|| {
                    smithay::utils::Rectangle::new((0, 0).into(), (0, 0).into())
                });
                let mode = output.current_mode();
                let (w, h, refresh) = mode
                    .map(|m| {
                        (
                            m.size.w.max(0) as u64,
                            m.size.h.max(0) as u64,
                            (m.refresh as f64) / 1000.0,
                        )
                    })
                    .unwrap_or((geo.size.w.max(0) as u64, geo.size.h.max(0) as u64, 60.0));
                let scale = output.current_scale().fractional_scale();
                let transform = crate::displays::transform_to_wl(output.current_transform());
                let name = output.name();
                let aw = self.wm.active_for_output(&name);
                json!({
                    "name": name,
                    "width": w,
                    "height": h,
                    "refreshRate": refresh,
                    "x": geo.loc.x,
                    "y": geo.loc.y,
                    "scale": scale,
                    "transform": transform,
                    "focused": focused_name.as_deref() == Some(name.as_str()),
                    "activeWorkspace": {
                        "id": aw,
                        "name": aw.to_string(),
                    },
                })
            })
            .collect();
        Value::Array(arr)
    }

    /// Hypr-shaped clients list with `at` / `size` from mapped geometry.
    pub fn clients_json_live(&self) -> serde_json::Value {
        use serde_json::{json, Value};
        let arr: Vec<Value> = self
            .wm
            .toplevels
            .iter()
            .map(|t| {
                let (ws_id, ws_name) = if t.workspace < 0 {
                    (t.workspace, "special:minimized".to_string())
                } else {
                    (t.workspace, t.workspace.to_string())
                };
                let (at_x, at_y, w, h, bbox) = if let Some(win) = self.windows.get(&t.address)
                {
                    let loc = self
                        .space
                        .element_location(win)
                        .unwrap_or_else(|| (t.loc_x, t.loc_y).into());
                    let geo = win.geometry();
                    let bb = win.bbox();
                    (
                        loc.x,
                        loc.y,
                        geo.size.w.max(0),
                        geo.size.h.max(0),
                        [bb.loc.x, bb.loc.y, bb.size.w, bb.size.h],
                    )
                } else {
                    (
                        t.loc_x,
                        t.loc_y,
                        t.size_w,
                        t.size_h,
                        [0, 0, t.size_w, t.size_h],
                    )
                };
                json!({
                    "address": t.address,
                    "class": t.class,
                    "title": t.title,
                    "workspace": {
                        "id": ws_id,
                        "name": ws_name,
                    },
                    "output": t.output,
                    "at": [at_x, at_y],
                    "size": [w, h],
                    "bbox": bbox,
                    "floating": t.floating,
                    "maximized": t.maximized,
                    "ssd": t.ssd,
                })
            })
            .collect();
        Value::Array(arr)
    }

    pub fn apply_wm_ops(&mut self, ops: Vec<WmOp>) {
        for op in ops {
            match op {
                WmOp::RefreshVisibility => self.refresh_workspace_visibility(),
                WmOp::Relayout => self.relayout_active(),
                WmOp::Focus(addr) => self.focus_address(&addr),
                WmOp::Close(addr) => self.close_address(&addr),
                WmOp::FocusOutput(name) => self.focus_output_named(&name),
                WmOp::ConfigureFullscreen { address, enabled } => {
                    self.set_fullscreen(&address, enabled);
                }
                WmOp::OutputScale { name, scale } => {
                    self.set_output_scale(&name, scale);
                }
                WmOp::OutputPos { name, x, y } => {
                    self.set_output_pos(&name, x, y);
                }
                WmOp::OutputMode {
                    name,
                    width,
                    height,
                    refresh_hz,
                } => {
                    self.set_output_mode(&name, width, height, refresh_hz);
                }
                WmOp::OutputTransform { name, transform } => {
                    self.set_output_transform(&name, transform);
                }
            }
        }
    }

    pub fn broadcast_event(&self, line: &str) {
        let Ok(mut guard) = self.ctl_subscribers.lock() else {
            return;
        };
        guard.retain_mut(|stream| writeln!(stream, "{line}").is_ok() && stream.flush().is_ok());
    }

    pub fn refresh_workspace_visibility(&mut self) {
        for name in self
            .space
            .outputs()
            .map(|o| o.name())
            .collect::<Vec<_>>()
        {
            self.wm.ensure_output(&name);
        }
        let primary = self.primary_output_name();
        let snapshot: Vec<(String, bool, i32, i32)> = self
            .wm
            .toplevels
            .iter()
            .map(|t| {
                (
                    t.address.clone(),
                    self.wm.window_on_active_board(t, &primary),
                    t.loc_x,
                    t.loc_y,
                )
            })
            .collect();

        for (addr, on_active, x, y) in snapshot {
            let Some(window) = self.windows.get(&addr).cloned() else {
                continue;
            };
            let mapped = self.space.elements().any(|w| w == &window);
            if on_active && !mapped {
                self.space.map_element(window, (x, y), false);
            } else if !on_active && mapped {
                self.space.unmap_elem(&window);
            }
        }
        self.relayout_active();
    }

    /// Tile per output for non-floating, non-fullscreen windows on each
    /// output's active board using `wm.layout`.
    pub fn relayout_active(&mut self) {
        let outputs: Vec<_> = self.space.outputs().cloned().collect();
        if outputs.is_empty() {
            return;
        }
        let primary_name = outputs[0].name();
        for o in &outputs {
            self.wm.ensure_output(&o.name());
        }
        let layout = self.wm.layout;
        let gaps_out_cfg = self.wm.gaps_out;
        let gaps_in_cfg = self.wm.gaps_in;
        let smart_gaps = self.wm.smart_gaps;
        let master_factor = self.wm.master_factor;

        for output in outputs {
            let Some(output_geo) = self.space.output_geometry(&output) else {
                continue;
            };
            let zone = layer_map_for_output(&output).non_exclusive_zone();
            let work_area = work_area_with_exclusive(output_geo, zone);
            let out_name = output.name();
            let active = self.wm.active_for_output(&out_name);

            let tiled: Vec<String> = self
                .wm
                .toplevels
                .iter()
                .filter(|t| {
                    let assigned = if t.output.is_empty() {
                        primary_name.as_str()
                    } else {
                        t.output.as_str()
                    };
                    assigned == out_name
                        && t.workspace == active
                        && t.workspace > 0
                        && !t.floating
                        && !t.fullscreen
                        && !t.maximized
                        && self.windows.contains_key(&t.address)
                })
                .map(|t| t.address.clone())
                .collect();

            let (gaps_out, gaps_in) =
                effective_gaps(gaps_out_cfg, gaps_in_cfg, tiled.len(), smart_gaps);
            let work_area = inset_rect(work_area, gaps_out);

            let tiles = match layout {
                LayoutKind::Equal => equal_column_layout(work_area, tiled.len()),
                LayoutKind::Dwindle => dwindle_layout(work_area, tiled.len()),
                LayoutKind::Master => master_layout(work_area, tiled.len(), master_factor),
            };
            for (addr, tile) in tiled.into_iter().zip(tiles) {
                let tile = inset_rect(tile, gaps_in);
                self.apply_tile_geometry(&addr, tile);
            }
        }
    }

    pub fn primary_output_name(&self) -> String {
        self.space
            .outputs()
            .next()
            .map(|o| o.name())
            .unwrap_or_default()
    }

    pub fn focus_output_named(&mut self, name: &str) {
        self.wm.ensure_output(name);
        self.wm.focused_output = Some(name.to_string());
        self.wm.sync_active_workspace();
        let Some(output) = self.space.outputs().find(|o| o.name() == name).cloned() else {
            return;
        };
        let Some(geo) = self.space.output_geometry(&output) else {
            return;
        };
        let center = (
            geo.loc.x as f64 + f64::from(geo.size.w) / 2.0,
            geo.loc.y as f64 + f64::from(geo.size.h) / 2.0,
        );
        if let Some(pointer) = self.seat.get_pointer() {
            pointer.set_location(center.into());
        }
    }

    fn apply_tile_geometry(&mut self, addr: &str, tile: Rectangle<i32, Logical>) {
        let Some(window) = self.windows.get(addr).cloned() else {
            return;
        };
        let ssd = self.wm.find(addr).map(|t| t.ssd).unwrap_or(false);
        let (content_loc, content_size) = outer_to_content_geo(tile, ssd);
        self.space
            .map_element(window.clone(), content_loc, false);
        self.wm.set_geometry(
            addr,
            (content_loc.x, content_loc.y),
            (content_size.w, content_size.h),
        );

        if let Some(toplevel) = window.toplevel() {
            toplevel.with_pending_state(|state| {
                state.size = Some(content_size);
            });
            toplevel.send_configure();
        } else if let Some(x11) = window.x11_surface() {
            let _ = x11.configure(Some(Rectangle::new(content_loc, content_size)));
        }
    }

    pub fn focus_address(&mut self, addr: &str) {
        let Some(window) = self.windows.get(addr).cloned() else {
            return;
        };
        let primary = self.primary_output_name();
        if let Some(t) = self.wm.find(addr) {
            if self.wm.window_on_active_board(t, &primary) {
                let mapped = self.space.elements().any(|w| w == &window);
                if !mapped {
                    self.space
                        .map_element(window.clone(), (t.loc_x, t.loc_y), false);
                }
                if !t.output.is_empty() {
                    self.wm.focused_output = Some(t.output.clone());
                    self.wm.sync_active_workspace();
                }
            }
        }
        self.space.raise_element(&window, true);
        self.wm.focused = Some(addr.to_string());
        let surface = window
            .toplevel()
            .map(|t| t.wl_surface().clone())
            .or_else(|| window.x11_surface().and_then(|x| x.wl_surface()));
        if let Some(surface) = surface {
            let serial = SERIAL_COUNTER.next_serial();
            self.seat
                .get_keyboard()
                .unwrap()
                .set_focus(self, Some(surface), serial);
        }
        self.broadcast_event("activewindow>>");
    }

    pub fn close_address(&mut self, addr: &str) {
        if let Some(window) = self.windows.get(addr) {
            if let Some(t) = window.toplevel() {
                t.send_close();
            } else if let Some(x11) = window.x11_surface() {
                let _ = x11.close();
            }
        }
    }

    /// Park a toplevel on `special:minimized` (SSD minimize / dock cycle).
    pub fn minimize_address(&mut self, addr: &str) {
        let verb = format!("movetoworkspacesilent special:minimized,address:{addr}");
        match self.wm.dispatch(&verb) {
            Ok(ops) => {
                self.apply_wm_ops(ops);
                self.broadcast_event(&format!("dispatch>>{verb}"));
                self.broadcast_event("activewindow>>");
            }
            Err(e) => eprintln!("proteus-compositor: minimize: {e}"),
        }
    }

    pub fn set_fullscreen(&mut self, addr: &str, enabled: bool) {
        let Some(window) = self.windows.get(addr) else {
            return;
        };
        let Some(toplevel) = window.toplevel() else {
            return;
        };
        toplevel.with_pending_state(|state| {
            if enabled {
                state.states.set(xdg_toplevel::State::Fullscreen);
            } else {
                state.states.unset(xdg_toplevel::State::Fullscreen);
            }
        });
        toplevel.send_configure();
    }

    /// Apply Displays Fact scale + position (and DRM mode when runtime attached).
    pub fn apply_displays_fact(&mut self) {
        let facts = crate::displays::load_displays_fact();
        if facts.is_empty() {
            return;
        }
        eprintln!(
            "proteus-compositor: applying displays.json ({} entries)",
            facts.len()
        );
        for f in &facts {
            self.set_output_scale(&f.name, f.scale);
            self.set_output_pos(&f.name, f.x, f.y);
            if f.width > 0 && f.height > 0 {
                self.set_output_mode(&f.name, f.width, f.height, Some(f.refresh_rate));
            }
            self.set_output_transform(&f.name, f.transform);
        }
    }

    pub fn set_output_transform(&mut self, name: &str, transform: u8) {
        let Some(output) = self.space.outputs().find(|o| o.name() == name).cloned() else {
            eprintln!("proteus-compositor: output transform: unknown {name}");
            return;
        };
        let t = crate::displays::transform_from_wl(transform);
        output.change_current_state(None, Some(t), None, None);
        layer_map_for_output(&output).arrange();
        self.relayout_active();
    }

    pub fn set_output_scale(&mut self, name: &str, scale: f64) {
        use smithay::output::Scale;
        let scale = crate::displays::clamp_scale(scale);
        let Some(output) = self.space.outputs().find(|o| o.name() == name).cloned() else {
            eprintln!("proteus-compositor: output scale: unknown {name}");
            return;
        };
        output.change_current_state(None, None, Some(Scale::Fractional(scale)), None);
        layer_map_for_output(&output).arrange();
        self.relayout_active();
    }

    pub fn set_output_pos(&mut self, name: &str, x: i32, y: i32) {
        let Some(output) = self.space.outputs().find(|o| o.name() == name).cloned() else {
            eprintln!("proteus-compositor: output pos: unknown {name}");
            return;
        };
        self.space.map_output(&output, (x, y));
        layer_map_for_output(&output).arrange();
        self.relayout_active();
    }

    pub fn set_output_mode(&mut self, name: &str, width: u32, height: u32, refresh_hz: Option<f64>) {
        // DRM path when runtime is attached.
        if let Some(rt) = self.drm_runtime.clone() {
            match crate::drm::apply_output_mode(&rt, self, name, width, height, refresh_hz) {
                Ok(()) => return,
                Err(e) => eprintln!("proteus-compositor: drm mode {name}: {e}"),
            }
        }
        // Winit / fallback: update Wayland Mode only (no DRM modeset).
        let Some(output) = self.space.outputs().find(|o| o.name() == name).cloned() else {
            eprintln!("proteus-compositor: output mode: unknown {name}");
            return;
        };
        let refresh = refresh_hz
            .map(|hz| (hz * 1000.0).round() as i32)
            .unwrap_or_else(|| {
                output
                    .current_mode()
                    .map(|m| m.refresh)
                    .unwrap_or(60_000)
            });
        let mode = smithay::output::Mode {
            size: (width as i32, height as i32).into(),
            refresh,
        };
        output.change_current_state(Some(mode), None, None, None);
        output.set_preferred(mode);
        layer_map_for_output(&output).arrange();
        self.relayout_active();
        if self.drm_runtime.is_none() {
            eprintln!(
                "proteus-compositor: output mode {name} {width}x{height}: wl-only (no DRM runtime)"
            );
        }
    }

    pub fn set_maximized_state(&mut self, addr: &str, enabled: bool) {
        let Some(window) = self.windows.get(addr) else {
            return;
        };
        let Some(toplevel) = window.toplevel() else {
            return;
        };
        toplevel.with_pending_state(|state| {
            if enabled {
                state.states.set(xdg_toplevel::State::Maximized);
            } else {
                state.states.unset(xdg_toplevel::State::Maximized);
            }
        });
        toplevel.send_configure();
    }

    /// Toggle SSD maximize: fill work area + xdg Maximized; restore prior geo.
    pub fn toggle_maximized(&mut self, addr: &str) {
        let Some(t) = self.wm.find(addr).cloned() else {
            return;
        };
        if t.fullscreen {
            return;
        }
        if t.maximized {
            if let Some(rec) = self.wm.find_mut(addr) {
                rec.maximized = false;
                rec.floating = false;
            }
            self.set_maximized_state(addr, false);
            if t.restore_w > 0 && t.restore_h > 0 {
                let restore = Rectangle::new(
                    (t.restore_x, t.restore_y).into(),
                    (t.restore_w.max(1), t.restore_h.max(1)).into(),
                );
                self.apply_tile_geometry(addr, restore);
            }
            self.relayout_active();
            return;
        }

        // Capture current outer-ish geometry for restore.
        let (rx, ry, rw, rh) = if let Some(window) = self.windows.get(addr) {
            let loc = self
                .space
                .element_location(window)
                .unwrap_or_else(|| (t.loc_x, t.loc_y).into());
            let geo = window.geometry();
            let w = geo.size.w.max(t.size_w).max(1);
            let h = geo.size.h.max(t.size_h).max(1);
            let ssd_h = if t.ssd {
                crate::decoration::TITLEBAR_H
            } else {
                0
            };
            (loc.x, loc.y - ssd_h, w, h + ssd_h)
        } else {
            (t.loc_x, t.loc_y, t.size_w.max(1), t.size_h.max(1))
        };

        if let Some(rec) = self.wm.find_mut(addr) {
            rec.restore_x = rx;
            rec.restore_y = ry;
            rec.restore_w = rw;
            rec.restore_h = rh;
            rec.maximized = true;
            rec.floating = true;
        }
        self.set_maximized_state(addr, true);

        let primary = self.primary_output_name();
        let out_name = if t.output.is_empty() {
            primary.as_str()
        } else {
            t.output.as_str()
        };
        let Some(output) = self.space.outputs().find(|o| o.name() == out_name).cloned() else {
            return;
        };
        let Some(output_geo) = self.space.output_geometry(&output) else {
            return;
        };
        let zone = layer_map_for_output(&output).non_exclusive_zone();
        let work_area = work_area_with_exclusive(output_geo, zone);
        self.apply_tile_geometry(addr, work_area);
    }

    pub fn address_for_surface(
        &self,
        surface: &smithay::reexports::wayland_server::protocol::wl_surface::WlSurface,
    ) -> Option<String> {
        for (addr, window) in &self.windows {
            if window
                .toplevel()
                .is_some_and(|t| t.wl_surface() == surface)
            {
                return Some(addr.clone());
            }
        }
        None
    }
}
