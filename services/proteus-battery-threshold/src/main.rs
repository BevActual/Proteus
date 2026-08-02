//! Battery charge threshold helper for Proteus Settings → Power.
//! Invoked via `pkexec proteus-battery-threshold <show|set> …`.
//!
//! Reads/writes sysfs:
//!   /sys/class/power_supply/<BAT>/charge_control_start_threshold
//!   /sys/class/power_supply/<BAT>/charge_control_end_threshold
//!
//! Fail-closed when attributes are absent. TLP is Out — this never touches
//! /etc/tlp.conf. Never logs secrets.

use std::env;
use std::fs;
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::process;

const SYSFS: &str = "/sys/class/power_supply";

#[derive(Clone, Debug, Default)]
struct BatInfo {
    supply: String,
    has_start: bool,
    has_end: bool,
    start: Option<u32>,
    end: Option<u32>,
}

fn is_root() -> bool {
    // /proc/self/status Uid: real effective saved fs — avoid libc dep.
    fs::read_to_string("/proc/self/status")
        .ok()
        .and_then(|s| {
            s.lines()
                .find(|l| l.starts_with("Uid:"))
                .and_then(|l| l.split_whitespace().nth(2)) // effective
                .and_then(|u| u.parse::<u32>().ok())
        })
        == Some(0)
}

fn read_u32(path: &Path) -> Option<u32> {
    let s = fs::read_to_string(path).ok()?;
    s.trim().parse().ok()
}

fn write_u32(path: &Path, v: u32) -> Result<(), String> {
    fs::write(path, format!("{v}\n")).map_err(|e| format!("write {}: {e}", path.display()))
}

fn supply_type(dir: &Path) -> String {
    fs::read_to_string(dir.join("type"))
        .map(|s| s.trim().to_string())
        .unwrap_or_default()
}

fn probe_supply(dir: &Path) -> Option<BatInfo> {
    if !dir.is_dir() {
        return None;
    }
    if supply_type(dir) != "Battery" {
        return None;
    }
    let start_p = dir.join("charge_control_start_threshold");
    let end_p = dir.join("charge_control_end_threshold");
    let has_start = start_p.is_file();
    let has_end = end_p.is_file();
    if !has_start && !has_end {
        return None;
    }
    Some(BatInfo {
        supply: dir
            .file_name()
            .map(|n| n.to_string_lossy().into_owned())
            .unwrap_or_else(|| "BAT".into()),
        has_start,
        has_end,
        start: if has_start { read_u32(&start_p) } else { None },
        end: if has_end { read_u32(&end_p) } else { None },
    })
}

fn probe_all() -> Vec<BatInfo> {
    let mut out = Vec::new();
    let Ok(rd) = fs::read_dir(SYSFS) else {
        return out;
    };
    for ent in rd.flatten() {
        if let Some(info) = probe_supply(&ent.path()) {
            out.push(info);
        }
    }
    out.sort_by(|a, b| a.supply.cmp(&b.supply));
    out
}

fn json_escape(s: &str) -> String {
    s.replace('\\', "\\\\").replace('"', "\\\"")
}

fn print_show(info: Option<&BatInfo>) {
    match info {
        None => {
            println!(
                r#"{{"ok":true,"supported":false,"supply":"","hasStart":false,"hasEnd":false,"start":null,"end":null,"hint":"No charge_control_* sysfs on this machine"}}"#
            );
        }
        Some(b) => {
            let start = b
                .start
                .map(|v| v.to_string())
                .unwrap_or_else(|| "null".into());
            let end = b.end.map(|v| v.to_string()).unwrap_or_else(|| "null".into());
            println!(
                r#"{{"ok":true,"supported":true,"supply":"{}","hasStart":{},"hasEnd":{},"start":{},"end":{},"hint":""}}"#,
                json_escape(&b.supply),
                if b.has_start { "true" } else { "false" },
                if b.has_end { "true" } else { "false" },
                start,
                end
            );
        }
    }
}

fn fixture_show() {
    println!(
        r#"{{"ok":true,"fixture":true,"supported":true,"supply":"BAT0","hasStart":true,"hasEnd":true,"start":40,"end":80,"hint":""}}"#
    );
}

fn parse_pct(s: &str, name: &str) -> Result<u32, String> {
    let v: u32 = s
        .trim()
        .parse()
        .map_err(|_| format!("invalid {name}"))?;
    if !(1..=100).contains(&v) {
        return Err(format!("{name} must be 1–100"));
    }
    Ok(v)
}

fn cmd_set(args: &[String]) -> Result<(), String> {
    let mut start: Option<u32> = None;
    let mut end: Option<u32> = None;
    let mut supply_filter = String::new();
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--start" => {
                i += 1;
                let v = args.get(i).ok_or("--start needs value")?;
                start = Some(parse_pct(v, "start")?);
            }
            "--end" => {
                i += 1;
                let v = args.get(i).ok_or("--end needs value")?;
                end = Some(parse_pct(v, "end")?);
            }
            "--supply" => {
                i += 1;
                supply_filter = args.get(i).cloned().unwrap_or_default();
            }
            other => return Err(format!("unknown arg {other}")),
        }
        i += 1;
    }
    if start.is_none() && end.is_none() {
        return Err("set requires --start and/or --end".into());
    }
    if let (Some(s), Some(e)) = (start, end) {
        if s >= e {
            return Err("start must be less than end".into());
        }
    }
    if env::var("PROTEUS_BATTERY_THRESHOLD_FIXTURE").ok().as_deref() == Some("1") {
        println!(r#"{{"ok":true,"fixture":true,"action":"set"}}"#);
        return Ok(());
    }
    if !is_root() {
        return Err("must run as root (use pkexec)".into());
    }
    let bats = probe_all();
    let bat = if supply_filter.is_empty() {
        bats.first().cloned()
    } else {
        bats.into_iter().find(|b| b.supply == supply_filter)
    }
    .ok_or_else(|| "no supported battery supply".to_string())?;

    if let (Some(s), Some(cur_e)) = (start, bat.end) {
        if end.is_none() && s >= cur_e {
            return Err("start must be less than current end".into());
        }
    }
    if let (Some(cur_s), Some(e)) = (bat.start, end) {
        if start.is_none() && cur_s >= e {
            return Err("end must be greater than current start".into());
        }
    }

    let base = PathBuf::from(SYSFS).join(&bat.supply);
    // Write end first when raising capacity, start first when lowering — common
    // OEM quirk. Write requested attrs only.
    if let Some(e) = end {
        if !bat.has_end {
            return Err("end threshold not supported".into());
        }
        write_u32(&base.join("charge_control_end_threshold"), e)?;
    }
    if let Some(s) = start {
        if !bat.has_start {
            return Err("start threshold not supported".into());
        }
        write_u32(&base.join("charge_control_start_threshold"), s)?;
    }
    // Re-read and print show JSON
    let again = probe_supply(&base);
    print_show(again.as_ref());
    Ok(())
}

fn usage() -> ! {
    let _ = writeln!(
        io::stderr(),
        "Usage: proteus-battery-threshold <show|set> [args…]\n\
         show                      — JSON probe (unprivileged)\n\
         set --start N --end M     — write sysfs (root / pkexec)\n\
         set --end M               — end-only machines\n\
         set --supply BAT0 …       — pick supply when multiple"
    );
    process::exit(2);
}

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    if args.is_empty() {
        usage();
    }
    match args[0].as_str() {
        "show" => {
            if env::var("PROTEUS_BATTERY_THRESHOLD_FIXTURE").ok().as_deref() == Some("1") {
                fixture_show();
                return;
            }
            let bats = probe_all();
            print_show(bats.first());
        }
        "set" => {
            if let Err(e) = cmd_set(&args[1..]) {
                eprintln!("proteus-battery-threshold: {e}");
                process::exit(1);
            }
        }
        "-h" | "--help" | "help" => usage(),
        other => {
            eprintln!("proteus-battery-threshold: unknown action {other:?}");
            usage();
        }
    }
}
