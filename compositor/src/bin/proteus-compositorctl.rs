//! proteus-compositorctl — one-shot query/dispatch against PROTEUS_COMPOSITOR_SOCK.

use std::env;
use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::UnixStream;
use std::path::PathBuf;
use std::process::ExitCode;

fn main() -> ExitCode {
    let sock = env::var_os("PROTEUS_COMPOSITOR_SOCK")
        .map(PathBuf::from)
        .or_else(|| {
            let wd = env::var("WAYLAND_DISPLAY").ok()?;
            let runtime = env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| "/tmp".into());
            let safe = wd.replace('/', "_");
            Some(PathBuf::from(runtime).join(format!("proteus-compositor-{safe}.sock")))
        });
    let Some(path) = sock else {
        eprintln!("proteus-compositorctl: PROTEUS_COMPOSITOR_SOCK / WAYLAND_DISPLAY unset");
        return ExitCode::from(2);
    };

    let cmd = env::args().skip(1).collect::<Vec<_>>().join(" ");
    if cmd.is_empty() {
        eprintln!("usage: proteus-compositorctl <workspaces|clients|dispatch …>");
        return ExitCode::from(2);
    }

    let mut stream = match UnixStream::connect(&path) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("proteus-compositorctl: connect {}: {e}", path.display());
            return ExitCode::from(1);
        }
    };
    if let Err(e) = writeln!(stream, "{cmd}") {
        eprintln!("proteus-compositorctl: write: {e}");
        return ExitCode::from(1);
    }
    let mut reader = BufReader::new(stream);
    let mut resp = String::new();
    if let Err(e) = reader.read_line(&mut resp) {
        eprintln!("proteus-compositorctl: read: {e}");
        return ExitCode::from(1);
    }
    print!("{resp}");
    if resp.contains("\"ok\":false") {
        return ExitCode::from(1);
    }
    ExitCode::SUCCESS
}
