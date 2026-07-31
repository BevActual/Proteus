//! Cached pactl runners for mixer dump.

use std::process::Command;
use std::time::{Duration, Instant};

#[derive(Clone, Debug)]
pub struct Sink {
    pub id: String,
    pub name: String,
}

pub struct Cache {
    sinks: Option<(Instant, Vec<Sink>)>,
    sources: Option<(Instant, Vec<Sink>)>,
    modules: Option<(Instant, String)>,
    sink_inputs: Option<(Instant, String)>,
    sources_full: Option<(Instant, String)>,
    ttl: Duration,
}

impl Cache {
    pub fn new(ttl_ms: u64) -> Self {
        Self {
            sinks: None,
            sources: None,
            modules: None,
            sink_inputs: None,
            sources_full: None,
            ttl: Duration::from_millis(ttl_ms.max(200)),
        }
    }

    pub fn invalidate(&mut self) {
        self.sinks = None;
        self.sources = None;
        self.modules = None;
        self.sink_inputs = None;
        self.sources_full = None;
    }

    fn fresh<T: Clone>(slot: &Option<(Instant, T)>, ttl: Duration) -> Option<T> {
        slot.as_ref().and_then(|(t, v)| {
            if t.elapsed() < ttl {
                Some(v.clone())
            } else {
                None
            }
        })
    }

    pub fn run(args: &[&str]) -> (i32, String, String) {
        match Command::new(args[0]).args(&args[1..]).output() {
            Ok(o) => (
                o.status.code().unwrap_or(1),
                String::from_utf8_lossy(&o.stdout).into_owned(),
                String::from_utf8_lossy(&o.stderr).into_owned(),
            ),
            Err(_) => (127, String::new(), "not found".into()),
        }
    }

    pub fn which(bin: &str) -> bool {
        Command::new("sh")
            .args(["-c", &format!("command -v {bin} >/dev/null 2>&1")])
            .status()
            .map(|s| s.success())
            .unwrap_or(false)
    }

    pub fn short_sinks(&mut self) -> Vec<Sink> {
        if let Some(v) = Self::fresh(&self.sinks, self.ttl) {
            return v;
        }
        let (code, out, _) = Self::run(&["pactl", "list", "short", "sinks"]);
        let mut sinks = Vec::new();
        if code == 0 {
            for line in out.lines() {
                let parts: Vec<_> = line.split('\t').collect();
                if parts.len() >= 2 {
                    sinks.push(Sink {
                        id: parts[0].to_string(),
                        name: parts[1].to_string(),
                    });
                }
            }
        }
        self.sinks = Some((Instant::now(), sinks.clone()));
        sinks
    }

    pub fn short_sources(&mut self) -> Vec<Sink> {
        if let Some(v) = Self::fresh(&self.sources, self.ttl) {
            return v;
        }
        let (code, out, _) = Self::run(&["pactl", "list", "short", "sources"]);
        let mut sources = Vec::new();
        if code == 0 {
            for line in out.lines() {
                let parts: Vec<_> = line.split('\t').collect();
                if parts.len() >= 2 {
                    sources.push(Sink {
                        id: parts[0].to_string(),
                        name: parts[1].to_string(),
                    });
                }
            }
        }
        self.sources = Some((Instant::now(), sources.clone()));
        sources
    }

    pub fn modules_short(&mut self) -> String {
        if let Some(v) = Self::fresh(&self.modules, self.ttl) {
            return v;
        }
        let (_, out, _) = Self::run(&["pactl", "list", "short", "modules"]);
        let text = if out.trim().is_empty() {
            let (_, out2, _) = Self::run(&["pactl", "list", "modules", "short"]);
            out2
        } else {
            out
        };
        self.modules = Some((Instant::now(), text.clone()));
        text
    }

    pub fn sink_inputs_raw(&mut self) -> String {
        if let Some(v) = Self::fresh(&self.sink_inputs, self.ttl) {
            return v;
        }
        let (code, out, _) = Self::run(&["pactl", "list", "sink-inputs"]);
        let text = if code == 0 { out } else { String::new() };
        self.sink_inputs = Some((Instant::now(), text.clone()));
        text
    }

    pub fn sources_full(&mut self) -> String {
        if let Some(v) = Self::fresh(&self.sources_full, self.ttl) {
            return v;
        }
        let (code, out, _) = Self::run(&["pactl", "list", "sources"]);
        let text = if code == 0 { out } else { String::new() };
        self.sources_full = Some((Instant::now(), text.clone()));
        text
    }

    pub fn sink_exists(&mut self, name: &str) -> bool {
        self.short_sinks().iter().any(|s| s.name == name)
    }

    pub fn source_exists(&mut self, name: &str) -> bool {
        self.short_sources().iter().any(|s| s.name == name)
    }

    pub fn sink_volume_mute(&mut self, name: &str) -> (i64, bool) {
        let (code, out, _) = Self::run(&["pactl", "get-sink-volume", name]);
        let mut vol = 100i64;
        if code == 0 {
            if let Some(cap) = percent_re(&out) {
                vol = cap;
            }
        }
        let (code2, out2, _) = Self::run(&["pactl", "get-sink-mute", name]);
        let muted = code2 == 0 && out2.to_lowercase().contains("yes");
        (vol, muted)
    }

    pub fn default_sink(&mut self) -> String {
        let (code, out, _) = Self::run(&["pactl", "get-default-sink"]);
        if code == 0 {
            out.trim().to_string()
        } else {
            String::new()
        }
    }

    pub fn move_sink_input(&mut self, id: &str, sink: &str) {
        let _ = Self::run(&["pactl", "move-sink-input", id, sink]);
        self.invalidate();
    }
}

fn percent_re(s: &str) -> Option<i64> {
    for part in s.split(|c: char| !c.is_ascii_digit() && c != '%') {
        if let Some(num) = part.strip_suffix('%') {
            if let Ok(v) = num.parse::<i64>() {
                return Some(v);
            }
        }
    }
    // fallback: find N%
    let bytes = s.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i].is_ascii_digit() {
            let start = i;
            while i < bytes.len() && bytes[i].is_ascii_digit() {
                i += 1;
            }
            if i < bytes.len() && bytes[i] == b'%' {
                if let Some(v) = std::str::from_utf8(&bytes[start..i])
                    .ok()
                    .and_then(|t| t.parse::<i64>().ok())
                {
                    return Some(v);
                }
            }
        } else {
            i += 1;
        }
    }
    None
}
