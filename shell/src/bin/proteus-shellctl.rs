//! proteus-shellctl — qs-parity IPC client for the owned shell.
//!
//! usage: proteus-shellctl <target> <method> [args…]
//! targets: lock | chrome | widgets | hud

use proteus_shell::ctl::{self, Request};
use proteus_shell::ipc_targets;

fn usage() -> ! {
    eprintln!(
        "usage: proteus-shellctl <target> <method> [args…]\n\
         targets: {} ",
        ipc_targets::all().join(" | ")
    );
    std::process::exit(2);
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.len() < 2 {
        usage();
    }
    let target = &args[0];
    let method = &args[1];
    if !ipc_targets::all().contains(&target.as_str()) {
        eprintln!("unknown target {target}");
        usage();
    }
    let req = Request {
        target: target.clone(),
        method: method.clone(),
        args: args[2..].to_vec(),
    };
    match ctl::call(&req) {
        Ok(resp) => {
            println!("{}", serde_json::to_string(&resp).unwrap_or_default());
            std::process::exit(if resp.ok { 0 } else { 1 });
        }
        Err(e) => {
            eprintln!("proteus-shellctl: {e}");
            std::process::exit(1);
        }
    }
}
