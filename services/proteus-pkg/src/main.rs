//! Privileged pacman mutator for Proteus Settings.
//! Invoked via `pkexec proteus-pkg <sync|upgrade|install|remove|orphans> [pkg]`.
//! Docs: docs/proteus/STACK.md (privileged mutators → Rust)

use std::env;
use std::fs;
use std::io::{self, BufRead, BufReader, Write};
use std::process::{Command, ExitCode, Stdio};
use std::thread;

fn usage() -> ! {
    eprintln!(
        "Usage: proteus-pkg <sync|upgrade|install|remove|orphans> [package]\n\
         sync     — pacman -Sy\n\
         upgrade  — pacman -Syu\n\
         install  — pacman -S <package>\n\
         remove   — pacman -Rns <package>\n\
         orphans  — pacman -Rns $(pacman -Qdtq)"
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

fn relay_pipe(pipe: impl io::Read + Send + 'static, err: bool) {
    thread::spawn(move || {
        let reader = BufReader::new(pipe);
        let mut out: Box<dyn Write> = if err {
            Box::new(io::stderr())
        } else {
            Box::new(io::stdout())
        };
        for line in reader.lines().map_while(Result::ok) {
            let _ = writeln!(out, "{line}");
            let _ = out.flush();
        }
    });
}

fn run_pacman(args: &[&str]) -> ExitCode {
    println!("proteus-pkg: pacman {}", args.join(" "));
    let _ = io::stdout().flush();

    let mut child = Command::new("pacman")
        .args(args)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap_or_else(|e| {
            eprintln!("proteus-pkg: failed to exec pacman: {e}");
            std::process::exit(127);
        });

    if let Some(stdout) = child.stdout.take() {
        relay_pipe(stdout, false);
    }
    if let Some(stderr) = child.stderr.take() {
        relay_pipe(stderr, true);
    }

    let status = child.wait().unwrap_or_else(|e| {
        eprintln!("proteus-pkg: wait failed: {e}");
        std::process::exit(127);
    });

    if status.success() {
        println!("proteus-pkg: ok");
        let _ = io::stdout().flush();
        ExitCode::SUCCESS
    } else {
        let code = status.code().unwrap_or(1);
        eprintln!("proteus-pkg: pacman exited {code}");
        let _ = io::stderr().flush();
        ExitCode::from(code as u8)
    }
}

fn orphan_names() -> Result<Vec<String>, String> {
    let output = Command::new("pacman")
        .args(["-Qdtq"])
        .output()
        .map_err(|e| format!("failed to list orphans: {e}"))?;
    // pacman exits 1 when the orphan list is empty
    let text = String::from_utf8_lossy(&output.stdout);
    let mut names = Vec::new();
    for line in text.lines() {
        let name = line.trim();
        if name.is_empty() {
            continue;
        }
        if !valid_pkg_name(name) {
            return Err(format!("unexpected orphan name {name:?}"));
        }
        names.push(name.to_string());
    }
    Ok(names)
}

fn main() -> ExitCode {
    let mut args = env::args().skip(1);
    let Some(action) = args.next() else {
        usage();
    };

    match action.as_str() {
        "-h" | "--help" | "help" => usage(),
        "sync" | "upgrade" | "install" | "remove" | "orphans" => {}
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
        "remove" => {
            let Some(pkg) = args.next() else {
                eprintln!("proteus-pkg: remove requires a package name");
                return ExitCode::from(2);
            };
            if !valid_pkg_name(&pkg) {
                eprintln!("proteus-pkg: invalid package name");
                return ExitCode::from(2);
            }
            run_pacman(&["-Rns", "--noconfirm", "--", &pkg])
        }
        "orphans" => match orphan_names() {
            Ok(names) if names.is_empty() => {
                println!("proteus-pkg: no orphans");
                let _ = io::stdout().flush();
                ExitCode::SUCCESS
            }
            Ok(names) => {
                println!("proteus-pkg: removing {} orphan(s)", names.len());
                let _ = io::stdout().flush();
                let mut argv: Vec<&str> = vec!["-Rns", "--noconfirm", "--"];
                for name in &names {
                    argv.push(name.as_str());
                }
                run_pacman(&argv)
            }
            Err(e) => {
                eprintln!("proteus-pkg: {e}");
                ExitCode::from(1)
            }
        },
        _ => unreachable!(),
    }
}
