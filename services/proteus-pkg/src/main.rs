//! Privileged pacman mutator for Proteus Settings.
//! Invoked via `pkexec proteus-pkg <sync|upgrade|install> [pkg]`.
//! Docs: docs/proteus/STACK.md (privileged mutators → Rust)

use std::env;
use std::fs;
use std::io::{self, Write};
use std::process::{Command, ExitCode};

fn usage() -> ! {
    eprintln!(
        "Usage: proteus-pkg <sync|upgrade|install> [package]\n\
         sync     — pacman -Sy\n\
         upgrade  — pacman -Syu\n\
         install  — pacman -S <package>"
    );
    std::process::exit(2);
}

fn valid_pkg_name(name: &str) -> bool {
    !name.is_empty()
        && name.len() <= 128
        && name
            .bytes()
            .all(|b| matches!(b, b'a'..=b'z' | b'A'..=b'Z' | b'0'..=b'9' | b'@' | b'.' | b'+' | b'_' | b'-'))
}

fn euid() -> Option<u32> {
    let status = fs::read_to_string("/proc/self/status").ok()?;
    for line in status.lines() {
        if let Some(rest) = line.strip_prefix("Uid:") {
            // Uid: real effective saved fs
            return rest.split_whitespace().nth(1)?.parse().ok();
        }
    }
    None
}

fn require_root() {
    if euid() != Some(0) {
        eprintln!("proteus-pkg: must run as root (use pkexec)");
        std::process::exit(1);
    }
}

fn run_pacman(args: &[&str]) -> ExitCode {
    println!("proteus-pkg: pacman {}", args.join(" "));
    let _ = io::stdout().flush();

    let status = Command::new("pacman")
        .args(args)
        .status()
        .unwrap_or_else(|e| {
            eprintln!("proteus-pkg: failed to exec pacman: {e}");
            std::process::exit(127);
        });

    if status.success() {
        println!("proteus-pkg: ok");
        ExitCode::SUCCESS
    } else {
        let code = status.code().unwrap_or(1);
        eprintln!("proteus-pkg: pacman exited {code}");
        ExitCode::from(code as u8)
    }
}

fn main() -> ExitCode {
    let mut args = env::args().skip(1);
    let Some(action) = args.next() else {
        usage();
    };

    match action.as_str() {
        "-h" | "--help" | "help" => usage(),
        "sync" | "upgrade" | "install" => {}
        other => {
            eprintln!("proteus-pkg: unknown action {other:?}");
            usage();
        }
    }

    require_root();

    match action.as_str() {
        "sync" => run_pacman(&["-Sy", "--noconfirm"]),
        "upgrade" => run_pacman(&["-Syu", "--noconfirm"]),
        "install" => {
            let Some(pkg) = args.next() else {
                eprintln!("proteus-pkg: install requires a package name");
                return ExitCode::from(2);
            };
            if !valid_pkg_name(&pkg) {
                eprintln!("proteus-pkg: invalid package name");
                return ExitCode::from(2);
            }
            run_pacman(&["-S", "--noconfirm", "--needed", "--", &pkg])
        }
        _ => unreachable!(),
    }
}
