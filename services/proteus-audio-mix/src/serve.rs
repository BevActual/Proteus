//! Long-lived serve loop: dump + peaks NDJSON on stdout; stdin/ctl commands.

use crate::dump;
use crate::pactl::Cache;
use crate::peaks::{self, Peaks};
use serde_json::{json, Value};
use std::fs::{self, File, OpenOptions};
use std::io::{BufRead, BufReader, ErrorKind, Write};
use std::os::unix::fs::OpenOptionsExt;
use std::path::PathBuf;
use std::sync::mpsc::{self, Receiver, Sender, TryRecvError};
use std::thread;
use std::time::{Duration, Instant};

pub struct ServeOpts {
    pub dump_ms: u64,
    pub peaks: Vec<String>,
    pub window_ms: u64,
    pub period_ms: u64,
    pub rate: u32,
    pub ctl: Option<PathBuf>,
    pub cache_ttl_ms: u64,
}

fn emit_tagged(t: &str, body: Value) -> bool {
    let mut obj = match body {
        Value::Object(m) => m,
        other => {
            let mut m = serde_json::Map::new();
            m.insert("v".into(), other);
            m
        }
    };
    obj.insert("t".into(), json!(t));
    peaks::emit_line(&Value::Object(obj))
}

fn emit_peaks(v: Value) -> bool {
    peaks::emit_line(&json!({"t": "peaks", "v": v}))
}

fn spawn_stdin(tx: Sender<String>) {
    thread::spawn(move || {
        let stdin = std::io::stdin();
        let mut lines = stdin.lock().lines();
        while let Some(Ok(line)) = lines.next() {
            if tx.send(line).is_err() {
                break;
            }
        }
    });
}

fn spawn_ctl(path: PathBuf, tx: Sender<String>) {
    thread::spawn(move || {
        let _ = fs::remove_file(&path);
        if let Err(e) = nix_mkfifo(&path) {
            let _ = writeln!(std::io::stderr(), "proteus-audio-mix: ctl fifo: {e}");
            return;
        }
        loop {
            let file = match File::open(&path) {
                Ok(f) => f,
                Err(_) => {
                    thread::sleep(Duration::from_millis(200));
                    continue;
                }
            };
            let reader = BufReader::new(file);
            for line in reader.lines() {
                match line {
                    Ok(l) => {
                        if tx.send(l).is_err() {
                            return;
                        }
                    }
                    Err(_) => break,
                }
            }
        }
    });
}

fn nix_mkfifo(path: &PathBuf) -> std::io::Result<()> {
    // libc::mkfifo via Command as portable fallback without libc crate
    let status = std::process::Command::new("mkfifo")
        .arg(path)
        .status()?;
    if status.success() {
        Ok(())
    } else {
        Err(std::io::Error::new(
            ErrorKind::Other,
            "mkfifo failed",
        ))
    }
}

fn handle_cmd(
    line: &str,
    paused: &mut bool,
    peaks: &mut Peaks,
    cache: &mut Cache,
    force_dump: &mut bool,
) -> bool {
    let line = line.trim();
    if line.is_empty() {
        return true;
    }
    let mut parts = line.split_whitespace();
    let cmd = parts.next().unwrap_or("");
    match cmd {
        "quit" | "exit" => return false,
        "pause" => *paused = true,
        "resume" => {
            *paused = false;
            *force_dump = true;
        }
        "dump" => *force_dump = true,
        "peaks" => {
            let sinks: Vec<String> = parts.map(|s| s.to_string()).collect();
            peaks.set_sinks(sinks);
        }
        _ => {}
    }
    let _ = cache;
    true
}

pub fn run(opts: ServeOpts) -> i32 {
    let (tx, rx): (Sender<String>, Receiver<String>) = mpsc::channel();
    spawn_stdin(tx.clone());
    if let Some(ctl) = opts.ctl.clone() {
        // Ensure parent dir exists
        if let Some(parent) = ctl.parent() {
            let _ = fs::create_dir_all(parent);
        }
        spawn_ctl(ctl, tx);
    }

    let mut cache = Cache::new(opts.cache_ttl_ms);
    let mut peaks_eng = Peaks::new(opts.peaks, opts.window_ms, opts.period_ms, opts.rate);
    let dump_every = Duration::from_millis(opts.dump_ms.max(500));
    let mut paused = false;
    let mut force_dump = true;
    let mut last_dump = Instant::now() - dump_every;
    let mut next_peak = Instant::now();

    // Touch a ready marker for smokes
    if let Ok(dir) = std::env::var("XDG_RUNTIME_DIR") {
        let marker = PathBuf::from(dir).join("proteus-audio-mix.ready");
        let _ = OpenOptions::new()
            .write(true)
            .create(true)
            .mode(0o600)
            .open(&marker)
            .and_then(|mut f| writeln!(f, "ok"));
    }

    loop {
        loop {
            match rx.try_recv() {
                Ok(line) => {
                    if !handle_cmd(&line, &mut paused, &mut peaks_eng, &mut cache, &mut force_dump) {
                        return 0;
                    }
                }
                Err(TryRecvError::Empty) => break,
                Err(TryRecvError::Disconnected) => return 0,
            }
        }

        let now = Instant::now();
        if force_dump || (!paused && now.duration_since(last_dump) >= dump_every) {
            let body = dump::dump(&mut cache);
            if !emit_tagged("dump", body) {
                return 0;
            }
            last_dump = now;
            force_dump = false;
        }

        if now >= next_peak {
            let v = peaks_eng.tick();
            if !emit_peaks(v) {
                return 0;
            }
            next_peak = now + peaks_eng.period();
        }

        thread::sleep(Duration::from_millis(20));
    }
}
