//! zwp_idle_inhibit_manager_v1 — track client inhibitors; bridge to systemd-inhibit
//! so owned `proteus-idle` skips lock while any inhibitor is active (thin).

use std::process::{Child, Command, Stdio};

use smithay::{
    delegate_idle_inhibit,
    reexports::wayland_server::protocol::wl_surface::WlSurface,
    utils::IsAlive,
    wayland::idle_inhibit::IdleInhibitHandler,
};

use crate::CompositorNext;

/// Holds a long-lived `systemd-inhibit --what=idle` child while Wayland inhibitors exist.
#[derive(Default)]
pub struct SystemdIdleInhibit {
    child: Option<Child>,
}

impl Drop for SystemdIdleInhibit {
    fn drop(&mut self) {
        self.release();
    }
}

impl SystemdIdleInhibit {
    fn hold(&mut self) {
        if self.child.is_some() {
            return;
        }
        match Command::new("systemd-inhibit")
            .args([
                "--what=idle",
                "--who=proteus-compositor",
                "--why=wayland idle-inhibit",
                "--mode=block",
                "sleep",
                "infinity",
            ])
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
        {
            Ok(child) => {
                eprintln!("proteus-compositor: idle-inhibit → systemd-inhibit held");
                self.child = Some(child);
            }
            Err(e) => {
                eprintln!(
                    "proteus-compositor: idle-inhibit systemd-inhibit soft-fail: {e}"
                );
            }
        }
    }

    fn release(&mut self) {
        if let Some(mut child) = self.child.take() {
            let _ = child.kill();
            let _ = child.wait();
            eprintln!("proteus-compositor: idle-inhibit → systemd-inhibit released");
        }
    }

    pub fn active(&self) -> bool {
        self.child.is_some()
    }
}

impl IdleInhibitHandler for CompositorNext {
    fn inhibit(&mut self, surface: WlSurface) {
        self.idle_inhibit_surfaces.push(surface);
        self.sync_idle_inhibit_bridge();
    }

    fn uninhibit(&mut self, surface: WlSurface) {
        if let Some(i) = self
            .idle_inhibit_surfaces
            .iter()
            .position(|s| s == &surface)
        {
            self.idle_inhibit_surfaces.remove(i);
        }
        self.sync_idle_inhibit_bridge();
    }
}

impl CompositorNext {
    pub fn idle_inhibit_count(&self) -> usize {
        self.idle_inhibit_surfaces
            .iter()
            .filter(|s| s.alive())
            .count()
    }

    pub fn idle_inhibit_active(&self) -> bool {
        self.idle_inhibit_count() > 0
    }

    pub fn sync_idle_inhibit_bridge(&mut self) {
        self.idle_inhibit_surfaces.retain(|s| s.alive());
        if self.idle_inhibit_surfaces.is_empty() {
            self.idle_inhibit_bridge.release();
        } else {
            self.idle_inhibit_bridge.hold();
        }
    }
}

delegate_idle_inhibit!(CompositorNext);
