use std::io::{BufRead, BufReader};
use std::process::{Command, Stdio};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

use serde::Serialize;

#[derive(Debug, Clone, Default, Serialize)]
pub struct Notification {
    pub id: u32,
    pub app_name: String,
    pub summary: String,
    pub body: String,
}

#[derive(Debug, Default)]
pub struct NotifBus {
    pub next_id: u32,
    pub items: Vec<Notification>,
    pub dnd: bool,
}

pub type SharedNotifs = Arc<Mutex<NotifBus>>;

impl NotifBus {
    pub fn notify(&mut self, app: &str, summary: &str, body: &str) -> u32 {
        if self.dnd {
            return 0;
        }
        self.next_id = self.next_id.saturating_add(1);
        let id = self.next_id;
        self.items.push(Notification {
            id,
            app_name: app.into(),
            summary: summary.into(),
            body: body.into(),
        });
        if self.items.len() > 50 {
            self.items.remove(0);
        }
        id
    }
}

/// In-process notification bus + real `org.freedesktop.Notifications` zbus server.
/// Falls back to dbus-monitor feeder if the bus name is already taken.
pub fn start_local_notifd() -> SharedNotifs {
    let bus = Arc::new(Mutex::new(NotifBus::default()));
    {
        let base = proteus_shell_core::facts::config_base();
        let settings = proteus_shell_core::facts::read_settings(&base);
        if let Ok(mut b) = bus.lock() {
            b.dnd = settings
                .get("notificationsDnd")
                .and_then(|v| v.as_bool())
                .unwrap_or(false);
        }
    }

    let bus_srv = Arc::clone(&bus);
    thread::spawn(move || {
        if let Err(e) = run_notifications_server(bus_srv.clone()) {
            eprintln!("proteus-shell: Notifications zbus server: {e} — falling back to dbus-monitor");
            spawn_dbus_monitor_feeder(bus_srv);
        }
    });

    let bus_dnd = Arc::clone(&bus);
    thread::spawn(move || loop {
        thread::sleep(Duration::from_secs(2));
        let base = proteus_shell_core::facts::config_base();
        let settings = proteus_shell_core::facts::read_settings(&base);
        if let Ok(mut b) = bus_dnd.lock() {
            b.dnd = settings
                .get("notificationsDnd")
                .and_then(|v| v.as_bool())
                .unwrap_or(false);
        }
    });
    bus
}

struct NotificationsIface {
    bus: SharedNotifs,
}

#[zbus::interface(name = "org.freedesktop.Notifications")]
impl NotificationsIface {
    fn notify(
        &mut self,
        app_name: &str,
        replaces_id: u32,
        _app_icon: &str,
        summary: &str,
        body: &str,
        _actions: Vec<String>,
        _hints: std::collections::HashMap<String, zvariant::Value<'_>>,
        _expire_timeout: i32,
    ) -> u32 {
        let Ok(mut b) = self.bus.lock() else {
            return 0;
        };
        if b.dnd {
            return 0;
        }
        if replaces_id != 0 {
            if let Some(existing) = b.items.iter_mut().find(|n| n.id == replaces_id) {
                existing.app_name = app_name.into();
                existing.summary = summary.into();
                existing.body = body.into();
                return replaces_id;
            }
        }
        b.notify(app_name, summary, body)
    }

    fn close_notification(&mut self, id: u32) {
        if let Ok(mut b) = self.bus.lock() {
            b.items.retain(|n| n.id != id);
        }
    }

    fn get_capabilities(&self) -> Vec<String> {
        vec![
            "body".into(),
            "body-markup".into(),
            "actions".into(),
            "persistence".into(),
        ]
    }

    fn get_server_information(&self) -> (String, String, String, String) {
        (
            "proteus-shell".into(),
            "Proteus".into(),
            "0.1".into(),
            "1.2".into(),
        )
    }
}

fn run_notifications_server(bus: SharedNotifs) -> Result<(), String> {
    let conn = zbus::blocking::Connection::session().map_err(|e| e.to_string())?;
    conn.object_server()
        .at("/org/freedesktop/Notifications", NotificationsIface { bus })
        .map_err(|e| e.to_string())?;
    conn.request_name("org.freedesktop.Notifications")
        .map_err(|e| e.to_string())?;
    // Keep the connection (and object server) alive.
    loop {
        thread::sleep(Duration::from_secs(3600));
    }
}

fn spawn_dbus_monitor_feeder(bus_mon: SharedNotifs) {
    thread::spawn(move || {
        let child = Command::new("dbus-monitor")
            .args([
                "--session",
                "interface='org.freedesktop.Notifications',member='Notify'",
            ])
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn();
        let Ok(mut child) = child else {
            return;
        };
        let Some(stdout) = child.stdout.take() else {
            return;
        };
        let reader = BufReader::new(stdout);
        let mut app = String::new();
        let mut summary = String::new();
        let mut body = String::new();
        let mut str_idx = 0u8;
        for line in reader.lines().flatten() {
            let t = line.trim();
            if t.starts_with("method call") && t.contains("Notify") {
                app.clear();
                summary.clear();
                body.clear();
                str_idx = 0;
            } else if let Some(rest) = t.strip_prefix("string \"") {
                let s = rest.trim_end_matches('"').to_string();
                match str_idx {
                    0 => app = s,
                    1 => {}
                    2 => summary = s,
                    3 => {
                        body = s;
                        if let Ok(mut b) = bus_mon.lock() {
                            let _ = b.notify(&app, &summary, &body);
                        }
                    }
                    _ => {}
                }
                str_idx = str_idx.saturating_add(1);
            }
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn notif_ids_increment() {
        let mut bus = NotifBus::default();
        let a = bus.notify("test", "hi", "");
        let b = bus.notify("test", "hi2", "");
        assert_eq!(a + 1, b);
    }

    #[test]
    fn dnd_suppresses() {
        let mut bus = NotifBus {
            dnd: true,
            ..Default::default()
        };
        assert_eq!(bus.notify("a", "b", "c"), 0);
    }
}
