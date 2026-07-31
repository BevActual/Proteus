//! proteus-audio-mix — resident mixer dump + peaks for Proteus Settings.

mod dump;
mod pactl;
mod peaks;
mod profile;
mod serve;

use std::env;
use std::path::PathBuf;
use std::process::ExitCode;

fn usage() {
    eprintln!(
        "usage:
  proteus-audio-mix dump
  proteus-audio-mix serve [--dump-ms N] [--peaks SINK…] [--ctl PATH]
                          [--window-ms N] [--period-ms N] [--rate HZ]
  proteus-audio-mix version"
    );
}

fn main() -> ExitCode {
    let mut args: Vec<String> = env::args().skip(1).collect();
    if args.is_empty() {
        usage();
        return ExitCode::from(2);
    }
    let cmd = args.remove(0);
    match cmd.as_str() {
        "version" | "--version" | "-V" => {
            println!("proteus-audio-mix {}", env!("CARGO_PKG_VERSION"));
            ExitCode::SUCCESS
        }
        "dump" => {
            let mut cache = pactl::Cache::new(1500);
            let d = dump::dump(&mut cache);
            println!("{}", d);
            ExitCode::SUCCESS
        }
        "serve" => {
            let mut dump_ms = 4500u64;
            let mut window_ms = 35u64;
            let mut period_ms = 140u64;
            let mut rate = 16000u32;
            let mut peaks = Vec::new();
            let mut ctl: Option<PathBuf> = None;
            let mut i = 0;
            while i < args.len() {
                match args[i].as_str() {
                    "--dump-ms" => {
                        i += 1;
                        dump_ms = args.get(i).and_then(|s| s.parse().ok()).unwrap_or(dump_ms);
                    }
                    "--window-ms" => {
                        i += 1;
                        window_ms = args.get(i).and_then(|s| s.parse().ok()).unwrap_or(window_ms);
                    }
                    "--period-ms" => {
                        i += 1;
                        period_ms = args.get(i).and_then(|s| s.parse().ok()).unwrap_or(period_ms);
                    }
                    "--rate" => {
                        i += 1;
                        rate = args.get(i).and_then(|s| s.parse().ok()).unwrap_or(rate);
                    }
                    "--ctl" => {
                        i += 1;
                        if let Some(p) = args.get(i) {
                            ctl = Some(PathBuf::from(p));
                        }
                    }
                    "--peaks" => {
                        i += 1;
                        while i < args.len() && !args[i].starts_with("--") {
                            peaks.push(args[i].clone());
                            i += 1;
                        }
                        continue;
                    }
                    other if other.starts_with('-') => {
                        eprintln!("unknown flag: {other}");
                        usage();
                        return ExitCode::from(2);
                    }
                    sink => peaks.push(sink.to_string()),
                }
                i += 1;
            }
            if ctl.is_none() {
                if let Ok(dir) = env::var("XDG_RUNTIME_DIR") {
                    ctl = Some(PathBuf::from(dir).join("proteus-audio-mix.ctl"));
                }
            }
            let code = serve::run(serve::ServeOpts {
                dump_ms,
                peaks,
                window_ms,
                period_ms,
                rate,
                ctl,
                cache_ttl_ms: 1500,
            });
            ExitCode::from(code as u8)
        }
        _ => {
            usage();
            ExitCode::from(2)
        }
    }
}
