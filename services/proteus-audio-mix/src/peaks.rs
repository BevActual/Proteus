//! Round-robin parec peaks (port of audio-mix-peaks.py).

use serde_json::{json, Map, Value};
use std::collections::HashMap;
use std::io::{Read, Write};
use std::process::{Command, Stdio};
use std::time::Duration;

const MAX_S16: i32 = 32767;

fn source_for(sink: &str) -> String {
    let s = sink.trim();
    if s.is_empty() {
        return String::new();
    }
    if s.ends_with(".monitor") || s.starts_with('@') {
        s.to_string()
    } else {
        format!("{s}.monitor")
    }
}

fn peak_of(chunk: &[u8]) -> i32 {
    if chunk.len() < 2 {
        return 0;
    }
    let even = chunk.len() - (chunk.len() % 2);
    let mut hi: i32 = 0;
    let mut lo: i32 = 0;
    for pair in chunk[..even].chunks_exact(2) {
        let sample = i16::from_le_bytes([pair[0], pair[1]]) as i32;
        hi = hi.max(sample);
        lo = lo.min(sample);
    }
    let loudest = hi.max((-lo).min(MAX_S16));
    ((loudest * 100) / MAX_S16).min(100)
}

fn sample(device: &str, window_bytes: usize, rate: u32) -> i32 {
    if device.is_empty() || !crate::pactl::Cache::which("parec") {
        return 0;
    }
    let mut child = match Command::new("parec")
        .args([
            "-d",
            device,
            "--raw",
            "--format=s16le",
            &format!("--rate={rate}"),
            "--channels=1",
            "--latency-msec=30",
        ])
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
    {
        Ok(c) => c,
        Err(_) => return 0,
    };
    let mut buf = vec![0u8; window_bytes];
    let n = child
        .stdout
        .as_mut()
        .and_then(|o| o.read(&mut buf).ok())
        .unwrap_or(0);
    let _ = child.kill();
    let _ = child.wait();
    peak_of(&buf[..n])
}

pub struct Peaks {
    sinks: Vec<String>,
    levels: HashMap<String, i32>,
    idx: usize,
    window_bytes: usize,
    rate: u32,
    period: Duration,
    has_parec: bool,
}

impl Peaks {
    pub fn new(sinks: Vec<String>, window_ms: u64, period_ms: u64, rate: u32) -> Self {
        let window_bytes = ((rate as f64) * (window_ms as f64 / 1000.0) * 2.0).max(256.0) as usize;
        let mut levels = HashMap::new();
        for s in &sinks {
            levels.insert(s.clone(), 0);
        }
        Self {
            sinks,
            levels,
            idx: 0,
            window_bytes,
            rate,
            period: Duration::from_millis(period_ms.max(50)),
            has_parec: crate::pactl::Cache::which("parec"),
        }
    }

    pub fn set_sinks(&mut self, sinks: Vec<String>) {
        let mut levels = HashMap::new();
        for s in &sinks {
            levels.insert(s.clone(), self.levels.get(s).copied().unwrap_or(0));
        }
        self.sinks = sinks;
        self.levels = levels;
        self.idx = 0;
    }

    pub fn period(&self) -> Duration {
        self.period
    }

    pub fn tick(&mut self) -> Value {
        if self.sinks.is_empty() {
            return json!({});
        }
        if !self.has_parec {
            let mut m = Map::new();
            for s in &self.sinks {
                m.insert(s.clone(), json!(0));
            }
            return Value::Object(m);
        }
        let sink = self.sinks[self.idx % self.sinks.len()].clone();
        self.idx += 1;
        let lvl = sample(&source_for(&sink), self.window_bytes, self.rate);
        self.levels.insert(sink.clone(), lvl);
        for (k, v) in self.levels.iter_mut() {
            if *k != sink {
                *v = ((*v as f64) * 0.72) as i32;
            }
        }
        let mut m = Map::new();
        for s in &self.sinks {
            m.insert(s.clone(), json!(self.levels.get(s).copied().unwrap_or(0)));
        }
        Value::Object(m)
    }
}

pub fn emit_line(obj: &Value) -> bool {
    let mut out = std::io::stdout().lock();
    if writeln!(out, "{}", obj).is_err() {
        return false;
    }
    out.flush().is_ok()
}
