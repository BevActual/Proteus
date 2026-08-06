//! Full-bleed lock overlay UI — shared by proteus-shell and proteus-session-lock.
//! Auth path + Lock Customize thin (lockWidgets[] strip zones + applets).

use iced::widget::{button, column, container, row, text, text_input, Space};
use iced::{Alignment, Background, Border, Color, Element, Length, Padding};

use proteus_ui::theme::Theme;

use crate::platform;

#[derive(Debug, Clone)]
pub enum LockMsg {
    Reveal,
    PinDigit(char),
    PinBackspace,
    PinClear,
    UsePassword,
    UsePin,
    PinEntry(String),
    Unlock,
    CustomizeAdd(String),
    CustomizeRemove(String),
    /// (id, delta) — move a strip widget left (-1) / right (+1).
    CustomizeMove(String, i32),
    CustomizeDone,
}

/// One entry of settings.json `lockWidgets[]` (schema: CONFIG-SCHEMA.md).
/// `raw` keeps unmanaged fields (clockWeight, noteText, tz…) intact on write.
#[derive(Debug, Clone)]
pub struct LockWidget {
    pub id: String,
    pub kind: String,
    pub enabled: bool,
    pub slot: i64,
    pub raw: serde_json::Value,
}

/// Applet catalog (QML Widgets.widgetCatalog parity, thin). `unique=false`
/// only for worldclock.
pub const LOCK_WIDGET_CATALOG: &[(&str, &str)] = &[
    ("clock", "Clock"),
    ("media", "Now playing"),
    ("battery", "Battery"),
    ("weather", "Weather"),
    ("calendar", "Calendar"),
    ("system", "System glance"),
    ("notes", "Note"),
    ("worldclock", "World clock"),
];

pub fn catalog_label(kind: &str) -> &'static str {
    LOCK_WIDGET_CATALOG
        .iter()
        .find(|(k, _)| *k == kind)
        .map(|(_, l)| *l)
        .unwrap_or("Widget")
}

pub fn read_lock_widgets() -> Vec<LockWidget> {
    let base = proteus_shell_core::facts::config_base();
    let s = proteus_shell_core::facts::read_settings(&base);
    let Some(arr) = s.get("lockWidgets").and_then(|v| v.as_array()) else {
        return Vec::new();
    };
    arr.iter()
        .filter_map(|w| {
            let kind = w.get("type")?.as_str()?.to_string();
            Some(LockWidget {
                id: w
                    .get("id")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .to_string(),
                kind,
                enabled: w.get("enabled").and_then(|v| v.as_bool()).unwrap_or(true),
                slot: w.get("slot").and_then(|v| v.as_i64()).unwrap_or(0),
                raw: w.clone(),
            })
        })
        .collect()
}

pub fn persist_lock_widgets(widgets: &[LockWidget]) -> Result<(), String> {
    let arr: Vec<serde_json::Value> = widgets
        .iter()
        .map(|w| {
            let mut v = w.raw.clone();
            if let Some(o) = v.as_object_mut() {
                o.insert("id".into(), serde_json::json!(w.id));
                o.insert("type".into(), serde_json::json!(w.kind));
                o.insert("enabled".into(), serde_json::json!(w.enabled));
                o.insert("slot".into(), serde_json::json!(w.slot));
            }
            v
        })
        .collect();
    let base = proteus_shell_core::facts::config_base();
    proteus_shell_core::facts::write_settings(
        &base,
        &serde_json::json!({ "lockWidgets": arr }),
    )
    .map(|_| ())
}

/// Rendered strip applet — label + live read-only value.
#[derive(Debug, Clone)]
pub struct StripEntry {
    pub id: String,
    pub kind: String,
    pub label: String,
    pub value: String,
}

fn applet_value(
    w: &LockWidget,
    mpris: &[platform::MprisPlayer],
    power: &platform::PowerStatus,
) -> String {
    match w.kind.as_str() {
        "media" => mpris
            .first()
            .map(|p| {
                if p.artist.is_empty() {
                    p.title.clone()
                } else {
                    format!("{} — {}", p.title, p.artist)
                }
            })
            .filter(|s| !s.trim().is_empty())
            .unwrap_or_else(|| "Nothing playing".into()),
        "battery" => {
            if power.percent > 0 {
                format!(
                    "{}%{}",
                    power.percent,
                    if power.on_battery { "" } else { " ⚡" }
                )
            } else {
                "—".into()
            }
        }
        "weather" => "—".into(), // honest stub — no fetcher on owned yet
        "calendar" => chrono_date_stub(),
        "system" => std::fs::read_to_string("/proc/loadavg")
            .ok()
            .and_then(|s| s.split_whitespace().next().map(|x| format!("load {x}")))
            .unwrap_or_else(|| "—".into()),
        "notes" => {
            let t = w
                .raw
                .get("noteText")
                .and_then(|v| v.as_str())
                .unwrap_or("");
            let short: String = t.chars().take(40).collect();
            if short.is_empty() { "…".into() } else { short }
        }
        "worldclock" => {
            let tz = w.raw.get("tzId").and_then(|v| v.as_str()).unwrap_or("UTC");
            std::process::Command::new("date")
                .env("TZ", tz)
                .arg("+%H:%M")
                .output()
                .ok()
                .and_then(|o| String::from_utf8(o.stdout).ok())
                .map(|s| s.trim().to_string())
                .filter(|s| !s.is_empty())
                .unwrap_or_else(|| "—".into())
        }
        _ => String::new(),
    }
}

fn new_widget_id() -> String {
    let n = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.subsec_nanos())
        .unwrap_or(0);
    format!("lw-{n:08x}")
}

#[derive(Debug, Clone)]
pub struct LockUiState {
    pub pin: String,
    pub fail_count: u32,
    pub cooldown_until: Option<std::time::Instant>,
    pub status: String,
    pub reveal: bool,
    pub pin_configured: bool,
    pub pin_length: usize,
    pub use_password: bool,
    pub user: String,
    pub customize: bool,
    pub widgets: Vec<LockWidget>,
    pub strip: Vec<StripEntry>,
    /// Auth-failure shake (x-offset keyframes, QML parity).
    pub shake: Option<crate::anim::Keyframes>,
    /// Last snapshot values for strip applets (fed by the heavy worker —
    /// applet rendering must never spawn subprocesses on the UI thread).
    last_mpris: Vec<platform::MprisPlayer>,
    last_power: platform::PowerStatus,
}

impl Default for LockUiState {
    fn default() -> Self {
        let pin_st = platform::pin_status();
        let mut st = Self {
            pin: String::new(),
            fail_count: 0,
            cooldown_until: None,
            status: String::new(),
            reveal: false,
            pin_configured: pin_st.configured,
            pin_length: if pin_st.length > 0 { pin_st.length } else { 6 },
            use_password: !pin_st.configured,
            user: std::env::var("USER").unwrap_or_else(|_| "user".into()),
            customize: false,
            widgets: Vec::new(),
            strip: Vec::new(),
            shake: None,
            last_mpris: Vec::new(),
            last_power: platform::PowerStatus::default(),
        };
        st.refresh_applets_cached();
        st
    }
}

impl LockUiState {
    pub fn cooldown_secs(&self) -> u64 {
        self.cooldown_until
            .map(|u| {
                u.saturating_duration_since(std::time::Instant::now())
                    .as_secs()
            })
            .unwrap_or(0)
    }

    pub fn clear_expired_cooldown(&mut self) {
        if let Some(until) = self.cooldown_until {
            if std::time::Instant::now() >= until {
                self.cooldown_until = None;
            }
        }
    }

    /// Apply digit; returns true if auto-submit should fire.
    pub fn push_digit(&mut self, ch: char) -> bool {
        if self.cooldown_secs() > 0 || !ch.is_ascii_digit() {
            return false;
        }
        if !self.reveal {
            self.reveal = true;
        }
        if self.use_password {
            return false;
        }
        if self.pin.chars().count() >= self.pin_length.max(4).min(8) {
            return false;
        }
        self.pin.push(ch);
        self.pin.chars().count() >= self.pin_length && self.pin_length > 0
    }

    pub fn on_fail(&mut self) {
        self.fail_count = self.fail_count.saturating_add(1);
        self.status = "Authentication failed".into();
        self.pin.clear();
        self.shake = Some(crate::anim::Keyframes::shake());
        let secs = platform::lock_cooldown_secs(self.fail_count);
        if secs > 0 {
            self.cooldown_until =
                Some(std::time::Instant::now() + std::time::Duration::from_secs(secs));
            self.status = format!("Too many attempts · {secs}s cooldown");
        }
    }

    pub fn on_success(&mut self) {
        self.pin.clear();
        self.fail_count = 0;
        self.status.clear();
        self.cooldown_until = None;
        self.reveal = false;
        self.shake = None;
    }

    /// Whether the failure shake is still animating.
    pub fn shake_active(&self) -> bool {
        self.shake.as_ref().is_some_and(|k| !k.done())
    }

    /// Re-read lockWidgets[] and refresh live strip values (heavy-tick cadence).
    pub fn refresh_applets(
        &mut self,
        mpris: &[platform::MprisPlayer],
        power: &platform::PowerStatus,
    ) {
        self.last_mpris = mpris.to_vec();
        self.last_power = power.clone();
        self.refresh_applets_cached();
    }

    /// Rebuild the strip from the last cached snapshot (no subprocesses).
    fn refresh_applets_cached(&mut self) {
        self.widgets = read_lock_widgets();
        let mut strip: Vec<&LockWidget> = self
            .widgets
            .iter()
            .filter(|w| w.enabled && w.kind != "clock")
            .collect();
        strip.sort_by(|a, b| a.slot.cmp(&b.slot).then(a.id.cmp(&b.id)));
        let entries = strip
            .into_iter()
            .map(|w| StripEntry {
                id: w.id.clone(),
                kind: w.kind.clone(),
                label: catalog_label(&w.kind).to_string(),
                value: applet_value(w, &self.last_mpris, &self.last_power),
            })
            .collect();
        self.strip = entries;
    }

    fn compact_strip_slots(&mut self) {
        let mut ids: Vec<(i64, String)> = self
            .widgets
            .iter()
            .filter(|w| w.kind != "clock")
            .map(|w| (w.slot, w.id.clone()))
            .collect();
        ids.sort();
        for (i, (_, id)) in ids.iter().enumerate() {
            if let Some(w) = self.widgets.iter_mut().find(|w| &w.id == id) {
                w.slot = i as i64;
            }
        }
    }

    fn persist_and_refresh(&mut self) {
        if let Err(e) = persist_lock_widgets(&self.widgets) {
            self.status = format!("Save failed: {e}");
        }
        self.refresh_applets_cached();
    }

    /// Add (or re-enable, for unique types) an applet from the catalog.
    pub fn customize_add(&mut self, kind: &str) {
        if !LOCK_WIDGET_CATALOG.iter().any(|(k, _)| *k == kind) {
            return;
        }
        let unique = kind != "worldclock";
        if unique {
            if let Some(w) = self.widgets.iter_mut().find(|w| w.kind == kind) {
                w.enabled = true;
                self.persist_and_refresh();
                return;
            }
        }
        let slot = self.widgets.iter().filter(|w| w.kind != "clock").count() as i64;
        let id = new_widget_id();
        self.widgets.push(LockWidget {
            id: id.clone(),
            kind: kind.to_string(),
            enabled: true,
            slot,
            raw: serde_json::json!({
                "id": id, "type": kind, "enabled": true, "slot": slot, "size": "md",
            }),
        });
        self.persist_and_refresh();
    }

    /// Remove a strip applet (the clock is lock chrome — cannot be removed).
    pub fn customize_remove(&mut self, id: &str) {
        if self
            .widgets
            .iter()
            .any(|w| w.id == id && w.kind == "clock")
        {
            return;
        }
        self.widgets.retain(|w| w.id != id);
        self.compact_strip_slots();
        self.persist_and_refresh();
    }

    /// Cycle a strip applet one zone slot left (-1) / right (+1).
    pub fn customize_move(&mut self, id: &str, delta: i32) {
        self.compact_strip_slots();
        let Some(cur) = self
            .widgets
            .iter()
            .find(|w| w.id == id && w.kind != "clock")
            .map(|w| w.slot)
        else {
            return;
        };
        let target = cur + delta as i64;
        let Some(other) = self
            .widgets
            .iter()
            .find(|w| w.kind != "clock" && w.slot == target)
            .map(|w| w.id.clone())
        else {
            return;
        };
        for w in &mut self.widgets {
            if w.id == id {
                w.slot = target;
            } else if w.id == other {
                w.slot = cur;
            }
        }
        self.persist_and_refresh();
    }
}

fn chrono_stub() -> String {
    // Local wall clock without chrono crate — QML ClockWidget "h:mm" (no AM/PM).
    use std::process::Command;
    Command::new("date")
        .arg("+%-I:%M")
        .output()
        .ok()
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "--:--".into())
}

fn chrono_date_stub() -> String {
    use std::process::Command;
    Command::new("date")
        .arg("+%A, %B %-d")
        .output()
        .ok()
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "—".into())
}

/// Lock text colors — the lock is always a dark surface over the dimmed
/// wallpaper (QML LockSurface parity), independent of chrome mode.
const LOCK_TEXT: Color = Color::from_rgba(1.0, 1.0, 1.0, 0.96);
const LOCK_TEXT_DIM: Color = Color::from_rgba(1.0, 1.0, 1.0, 0.72);
const LOCK_TEXT_MUTE: Color = Color::from_rgba(1.0, 1.0, 1.0, 0.45);

/// 64px avatar circle with the user's initial (white 0.14 fill).
fn avatar_view<'a>(user: &str) -> Element<'a, LockMsg> {
    let initial = user
        .chars()
        .next()
        .map(|c| c.to_uppercase().to_string())
        .unwrap_or_else(|| "?".into());
    container(
        text(initial)
            .size(26)
            .font(crate::surfaces::semibold())
            .color(LOCK_TEXT),
    )
    .width(Length::Fixed(64.0))
    .height(Length::Fixed(64.0))
    .align_x(Alignment::Center)
    .align_y(Alignment::Center)
    .style(|_t| container::Style {
        background: Some(Background::Color(Color::from_rgba(1.0, 1.0, 1.0, 0.14))),
        border: Border {
            radius: 32.0.into(),
            ..Default::default()
        },
        ..Default::default()
    })
    .into()
}

/// Full-bleed dim plate — clock, PIN pad / password, reveal, cooldown.
pub fn lock_screen_view<'a>(theme: &'a Theme, st: &'a LockUiState) -> Element<'a, LockMsg> {
    let date = chrono_date_stub();
    let time = chrono_stub();
    let pin_mode = st.pin_configured && !st.use_password;
    let cool = st.cooldown_secs();
    let blocked = cool > 0;
    let pin = st.pin.as_str();

    let feedback = if cool > 0 {
        format!("Try again in {cool}s")
    } else if !st.status.is_empty() {
        st.status.clone()
    } else if st.fail_count > 0 {
        format!("Authentication failed · {}", st.fail_count)
    } else if pin_mode {
        "Enter PIN".into()
    } else {
        "Enter password".into()
    };
    let feedback_c = if st.fail_count > 0 || cool > 0 {
        theme.danger
    } else {
        LOCK_TEXT_DIM
    };

    // Clock — large Light time "h:mm", date "dddd, MMMM d" (QML ClockWidget lg).
    let clock = column![
        text(time).size(96).font(crate::surfaces::light_font()).color(LOCK_TEXT),
        text(date).size(20).color(LOCK_TEXT_DIM),
    ]
    .spacing(2)
    .align_x(Alignment::Center);

    let auth: Element<'a, LockMsg> = if !st.reveal {
        column![
            text("Click or type to unlock")
                .size(13)
                .color(LOCK_TEXT_MUTE),
        ]
        .spacing(20)
        .align_x(Alignment::Center)
        .into()
    } else if pin_mode {
        // PIN dots — 12px circles, spacing 12.
        let mut dots = row![].spacing(12);
        let filled = pin.chars().count();
        let slots = st.pin_length.max(4).min(8);
        for i in 0..slots {
            let on = i < filled;
            let accent = theme.accent;
            dots = dots.push(container(Space::new().width(12).height(12)).style(
                move |_t| container::Style {
                    background: Some(Background::Color(if on {
                        accent
                    } else {
                        Color::from_rgba(1.0, 1.0, 1.0, 0.25)
                    })),
                    border: Border {
                        radius: 6.0.into(),
                        ..Default::default()
                    },
                    ..Default::default()
                },
            ));
        }

        // PIN pad — 60px circular glass keys, gap 10 (QML auth column).
        let key = |label: String, msg: Option<LockMsg>| {
            proteus_ui::widgets::circle_button(
                theme,
                60.0,
                proteus_ui::widgets::CircleStyle::Glass,
                text(label).size(20).color(LOCK_TEXT),
                if blocked { None } else { msg },
            )
        };
        let mut pad = column![].spacing(10);
        for row_digits in [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"]] {
            let mut r = row![].spacing(10);
            for d in row_digits {
                let ch = d.chars().next().unwrap();
                r = r.push(key(d.to_string(), Some(LockMsg::PinDigit(ch))));
            }
            pad = pad.push(r);
        }
        pad = pad.push(
            row![
                proteus_ui::widgets::circle_button(
                    theme,
                    60.0,
                    proteus_ui::widgets::CircleStyle::GlassDim,
                    text("C").size(16).color(LOCK_TEXT_DIM),
                    if blocked { None } else { Some(LockMsg::PinClear) },
                ),
                key("0".into(), Some(LockMsg::PinDigit('0'))),
                proteus_ui::widgets::circle_button(
                    theme,
                    60.0,
                    proteus_ui::widgets::CircleStyle::GlassDim,
                    crate::icons::glyph_view("backspace", 18.0, LOCK_TEXT_DIM),
                    if blocked { None } else { Some(LockMsg::PinBackspace) },
                ),
            ]
            .spacing(10),
        );

        let mut col = column![
            avatar_view(&st.user),
            text(st.user.as_str())
                .size(16)
                .font(crate::surfaces::semibold())
                .color(LOCK_TEXT),
            text(feedback).size(14).color(feedback_c),
            dots,
            pad,
        ]
        .spacing(14)
        .align_x(Alignment::Center);
        if st.pin_configured {
            col = col.push(
                button(text("Use password").size(12).color(LOCK_TEXT_MUTE))
                    .on_press(LockMsg::UsePassword)
                    .padding(8)
                    .style(theme.ghost_button_style()),
            );
        }
        col.into()
    } else {
        // Password — pill field H46 r22, accent unlock.
        let field = text_input("Password", pin)
            .on_input(LockMsg::PinEntry)
            .on_submit(LockMsg::Unlock)
            .secure(true)
            .padding(Padding::new(13.0).left(20.0).right(20.0))
            .size(14)
            .width(Length::Fixed(280.0))
            .style({
                let accent = theme.accent;
                move |_t, status| iced::widget::text_input::Style {
                    background: Background::Color(Color::from_rgba(0.09, 0.09, 0.11, 0.88)),
                    border: Border {
                        radius: 22.0.into(),
                        width: 1.0,
                        color: match status {
                            iced::widget::text_input::Status::Focused { .. } => accent,
                            _ => Color::from_rgba(1.0, 1.0, 1.0, 0.12),
                        },
                    },
                    icon: Color::TRANSPARENT,
                    placeholder: LOCK_TEXT_MUTE,
                    value: LOCK_TEXT,
                    selection: Color::from_rgba(1.0, 1.0, 1.0, 0.25),
                }
            });
        let unlock_btn = button(text("Unlock").size(14))
            .padding(Padding::new(10.0).left(24.0).right(24.0))
            .style(theme.accent_button_style());
        let unlock_btn = if blocked {
            unlock_btn
        } else {
            unlock_btn.on_press(LockMsg::Unlock)
        };
        let mut col = column![
            avatar_view(&st.user),
            text(st.user.as_str())
                .size(16)
                .font(crate::surfaces::semibold())
                .color(LOCK_TEXT),
            text(feedback).size(14).color(feedback_c),
            field,
            unlock_btn,
        ]
        .spacing(14)
        .align_x(Alignment::Center);
        if st.pin_configured {
            col = col.push(
                button(text("Use PIN").size(12).color(LOCK_TEXT_MUTE))
                    .on_press(LockMsg::UsePin)
                    .padding(8)
                    .style(theme.ghost_button_style()),
            );
        }
        col.into()
    };

    // Full dim is always dark — the lock is a dark surface over the wallpaper.
    let dim = Color {
        r: 0.02,
        g: 0.02,
        b: 0.04,
        a: 0.72,
    };

    // Failure shake — x-offset keyframes applied as asymmetric padding.
    let shake_x = st.shake.as_ref().map(|k| k.value()).unwrap_or(0.0);

    // Customize replaces the auth column; strip applets hide while PIN is up
    // (QML LockSurface parity).
    let center: Element<'a, LockMsg> = if st.customize {
        customize_view(theme, st)
    } else if !st.reveal && !st.strip.is_empty() {
        column![clock, auth, strip_view(theme, st)]
            .spacing(28)
            .align_x(Alignment::Center)
            .into()
    } else {
        column![clock, auth]
            .spacing(28)
            .align_x(Alignment::Center)
            .into()
    };

    let inner = container(center).padding(Padding {
        top: 0.0,
        bottom: 0.0,
        left: 16.0 + shake_x,
        right: 16.0 - shake_x,
    });

    let body = container(inner)
        .width(Length::Fill)
        .height(Length::Fill)
        .center_x(Length::Fill)
        .center_y(Length::Fill)
        .style(move |_t| container::Style {
            background: Some(Background::Color(dim)),
            ..Default::default()
        });

    if st.reveal || st.customize {
        body.into()
    } else {
        button(body)
            .on_press(LockMsg::Reveal)
            .padding(0)
            .style(|_t, _s| button::Style {
                background: None,
                border: Border::default(),
                text_color: Color::TRANSPARENT,
                ..Default::default()
            })
            .width(Length::Fill)
            .height(Length::Fill)
            .into()
    }
}

/// Read-only applet strip below the clock — glass cards (zone: bottom).
fn strip_view<'a>(theme: &'a Theme, st: &'a LockUiState) -> Element<'a, LockMsg> {
    let mut r = row![].spacing(10);
    let _ = theme;
    for e in &st.strip {
        r = r.push(
            container(
                column![
                    text(e.label.as_str())
                        .size(11)
                        .font(crate::surfaces::semibold())
                        .color(LOCK_TEXT_MUTE),
                    text(e.value.as_str()).size(13).color(LOCK_TEXT_DIM),
                ]
                .spacing(3)
                .align_x(Alignment::Center),
            )
            .padding(Padding::new(10.0).left(16.0).right(16.0))
            .style(|_t| container::Style {
                background: Some(Background::Color(Color::from_rgba(1.0, 1.0, 1.0, 0.08))),
                border: Border {
                    radius: 14.0.into(),
                    width: 1.0,
                    color: Color::from_rgba(1.0, 1.0, 1.0, 0.10),
                },
                ..Default::default()
            }),
        );
    }
    r.into()
}

/// Customize Lock Screen — applet catalog add/remove + zone (slot) cycling.
/// Persisted to settings.json `lockWidgets[]`. Free-drag editor stays out.
fn customize_view<'a>(theme: &'a Theme, st: &'a LockUiState) -> Element<'a, LockMsg> {
    // Catalog — glass chips; already-present unique applets read muted.
    let chip_style = |present: bool| {
        move |_t: &iced::Theme, status: button::Status| {
            let base = if present {
                Color::from_rgba(1.0, 1.0, 1.0, 0.05)
            } else {
                match status {
                    button::Status::Hovered | button::Status::Pressed => {
                        Color::from_rgba(1.0, 1.0, 1.0, 0.20)
                    }
                    _ => Color::from_rgba(1.0, 1.0, 1.0, 0.12),
                }
            };
            button::Style {
                background: Some(Background::Color(base)),
                text_color: if present { LOCK_TEXT_MUTE } else { LOCK_TEXT },
                border: Border {
                    radius: 14.0.into(),
                    ..Default::default()
                },
                ..Default::default()
            }
        }
    };
    let mut catalog = row![].spacing(8);
    for (kind, label) in LOCK_WIDGET_CATALOG {
        let present = st
            .widgets
            .iter()
            .any(|w| w.kind == *kind && w.enabled && *kind != "worldclock");
        let mut btn = button(text(*label).size(12))
            .padding(Padding::new(6.0).left(12.0).right(12.0))
            .style(chip_style(present));
        if !present {
            btn = btn.on_press(LockMsg::CustomizeAdd((*kind).to_string()));
        }
        catalog = catalog.push(btn);
    }

    // Strip rows — glass card per applet with move / remove circles.
    let mut strip_col = column![].spacing(6);
    let n = st.strip.len();
    for (i, e) in st.strip.iter().enumerate() {
        let arrow = |glyph: &'static str, msg: Option<LockMsg>| {
            proteus_ui::widgets::circle_button(
                theme,
                26.0,
                proteus_ui::widgets::CircleStyle::GlassDim,
                text(glyph).size(11).color(LOCK_TEXT_DIM),
                msg,
            )
        };
        let r = row![
            text(e.label.as_str())
                .size(13)
                .color(LOCK_TEXT)
                .width(Length::Fixed(140.0)),
            arrow(
                "◀",
                (i > 0).then(|| LockMsg::CustomizeMove(e.id.clone(), -1)),
            ),
            arrow(
                "▶",
                (i + 1 < n).then(|| LockMsg::CustomizeMove(e.id.clone(), 1)),
            ),
            proteus_ui::widgets::circle_button(
                theme,
                26.0,
                proteus_ui::widgets::CircleStyle::GlassDim,
                crate::icons::glyph_view("close", 10.0, theme.danger),
                Some(LockMsg::CustomizeRemove(e.id.clone())),
            ),
        ]
        .spacing(8)
        .align_y(Alignment::Center);
        strip_col = strip_col.push(
            container(r)
                .padding(Padding::new(8.0).left(14.0).right(10.0))
                .style(|_t| container::Style {
                    background: Some(Background::Color(Color::from_rgba(
                        1.0, 1.0, 1.0, 0.08,
                    ))),
                    border: Border {
                        radius: 12.0.into(),
                        ..Default::default()
                    },
                    ..Default::default()
                }),
        );
    }
    if n == 0 {
        strip_col = strip_col.push(
            text("No applets — add from the catalog")
                .size(12)
                .color(LOCK_TEXT_MUTE),
        );
    }

    column![
        text("Customize Lock Screen")
            .size(18)
            .font(crate::surfaces::semibold())
            .color(LOCK_TEXT),
        text("Add applets, cycle zones — clock is lock chrome")
            .size(12)
            .color(LOCK_TEXT_MUTE),
        catalog,
        strip_col,
        button(text("Done").size(14))
            .on_press(LockMsg::CustomizeDone)
            .padding(Padding::new(8.0).left(22.0).right(22.0))
            .style(theme.accent_button_style()),
    ]
    .spacing(16)
    .align_x(Alignment::Center)
    .into()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_config() -> tempfile_dir::TempDir {
        tempfile_dir::TempDir::new()
    }

    /// Minimal temp-dir helper (avoid a dev-dependency for one test).
    mod tempfile_dir {
        pub struct TempDir(pub std::path::PathBuf);
        impl TempDir {
            pub fn new() -> Self {
                let p = std::env::temp_dir().join(format!(
                    "proteus-lockui-test-{}-{}",
                    std::process::id(),
                    std::time::SystemTime::now()
                        .duration_since(std::time::UNIX_EPOCH)
                        .unwrap()
                        .subsec_nanos()
                ));
                std::fs::create_dir_all(&p).unwrap();
                Self(p)
            }
        }
        impl Drop for TempDir {
            fn drop(&mut self) {
                let _ = std::fs::remove_dir_all(&self.0);
            }
        }
    }

    /// Customize round-trip: add → persist → re-read → move → remove, with
    /// unmanaged raw fields (noteText) surviving the writes.
    #[test]
    fn lock_widgets_customize_roundtrip() {
        let tmp = temp_config();
        // config_base honors XDG_CONFIG_HOME; scope it to this test process.
        std::env::set_var("XDG_CONFIG_HOME", &tmp.0);

        let mut st = LockUiState {
            pin: String::new(),
            fail_count: 0,
            cooldown_until: None,
            status: String::new(),
            reveal: false,
            pin_configured: false,
            pin_length: 6,
            use_password: true,
            user: "test".into(),
            customize: true,
            widgets: Vec::new(),
            strip: Vec::new(),
            shake: None,
            last_mpris: Vec::new(),
            last_power: platform::PowerStatus::default(),
        };

        st.customize_add("battery");
        st.customize_add("notes");
        assert_eq!(st.strip.len(), 2, "two strip applets after add");

        // Unmanaged field survives a later persist.
        if let Some(w) = st.widgets.iter_mut().find(|w| w.kind == "notes") {
            w.raw.as_object_mut().unwrap().insert(
                "noteText".into(),
                serde_json::json!("keep me"),
            );
        }
        persist_lock_widgets(&st.widgets).unwrap();

        let read = read_lock_widgets();
        assert_eq!(read.len(), 2);
        let notes = read.iter().find(|w| w.kind == "notes").unwrap();
        assert_eq!(
            notes.raw.get("noteText").and_then(|v| v.as_str()),
            Some("keep me")
        );

        // Zone cycle: notes (slot 1) left → slot 0.
        let notes_id = notes.id.clone();
        st.customize_move(&notes_id, -1);
        assert_eq!(st.strip.first().map(|e| e.kind.as_str()), Some("notes"));

        st.customize_remove(&notes_id);
        assert_eq!(st.strip.len(), 1);
        assert_eq!(read_lock_widgets().len(), 1);

        std::env::remove_var("XDG_CONFIG_HOME");
    }
}
