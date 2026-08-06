// proteus-shell-core CLI — owned shell spine (OWNED-STACK rung 0).
//
// Subcommands land slice by slice: tokens (env/chrome generator), then
// facts / schema-keys, gate, serve. JSON out; no state owned here.

use std::io::Write;

fn usage() -> ! {
    eprintln!(
        "usage: proteus-shell-core <command>\n\
         \n\
         commands:\n\
         \x20 tokens --json           print chrome-tokens.json to stdout\n\
         \x20 tokens --css            print chrome-tokens.css to stdout\n\
         \x20 tokens --write <dir>    write both artifacts into <dir>\n\
         \x20 facts [--config DIR]    normalized posture/hw/settings state JSON\n\
         \x20 schema-keys             sorted settings.json schema keys (one per line)\n\
         \x20 settings-write [--config DIR] <json>  patch+write settings.json\n\
         \x20 posture-write [--config DIR] <id>     write posture fact\n\
         \x20 gate app <id> [opts]    evaluate app gating (JSON)\n\
         \x20 gate pane <id> [opts]   evaluate Settings pane gating (JSON)\n\
         \x20   opts: --posture P --caps a,b --device-class D --probe-ready 0|1\n\
         \x20         --pane-density full|minimal --catalog F --settings-catalog F\n\
         \x20         --permissions F   permissions.json (omit = no privacy layer)\n\
         \x20 gate matrix <file>      run a gate fixture matrix; nonzero on mismatch\n\
         \x20 serve [--config DIR]    NDJSON facts stream (line on start + fact change)\n\
         \x20 version                 print version"
    );
    std::process::exit(2);
}

fn cmd_tokens(args: &[String]) -> i32 {
    match args.first().map(String::as_str) {
        Some("--json") => {
            print!("{}", proteus_shell_core::tokens::render_json());
            0
        }
        Some("--css") => {
            print!("{}", proteus_shell_core::tokens::render_css());
            0
        }
        Some("--write") => {
            let Some(dir) = args.get(1) else {
                eprintln!("tokens --write: missing <dir>");
                return 2;
            };
            let dir = std::path::Path::new(dir);
            for (name, body) in [
                ("chrome-tokens.json", proteus_shell_core::tokens::render_json()),
                ("chrome-tokens.css", proteus_shell_core::tokens::render_css()),
            ] {
                let path = dir.join(name);
                match std::fs::File::create(&path)
                    .and_then(|mut f| f.write_all(body.as_bytes()))
                {
                    Ok(()) => println!("wrote {}", path.display()),
                    Err(e) => {
                        eprintln!("tokens --write: {}: {e}", path.display());
                        return 1;
                    }
                }
            }
            0
        }
        _ => usage(),
    }
}

fn config_base_arg(args: &[String]) -> Result<std::path::PathBuf, String> {
    match args.first().map(String::as_str) {
        Some("--config") => args
            .get(1)
            .map(std::path::PathBuf::from)
            .ok_or_else(|| "--config: missing DIR".into()),
        Some(other) => Err(format!("unknown flag {other}")),
        None => Ok(proteus_shell_core::facts::config_base()),
    }
}

fn facts_json(base: &std::path::Path) -> serde_json::Value {
    proteus_shell_core::subscribe::facts_snapshot(base)
}

/// Minimal NDJSON stream — thin adapter over FactsWatch (library-first).
fn cmd_serve(args: &[String]) -> i32 {
    let base = match config_base_arg(args) {
        Ok(b) => b,
        Err(e) => {
            eprintln!("serve: {e}");
            return 2;
        }
    };
    let mut watch = proteus_shell_core::subscribe::FactsWatch::new(base);
    watch.run_ndjson(
        |snap| {
            use std::io::Write;
            let mut out = std::io::stdout().lock();
            writeln!(out, "{snap}").and_then(|()| out.flush()).is_ok()
        },
        std::time::Duration::from_millis(500),
    );
    0
}

fn cmd_settings_write(args: &[String]) -> i32 {
    let (base, rest) = match args.first().map(String::as_str) {
        Some("--config") => {
            let Some(dir) = args.get(1) else {
                eprintln!("settings-write: --config missing DIR");
                return 2;
            };
            (std::path::PathBuf::from(dir), &args[2..])
        }
        _ => (proteus_shell_core::facts::config_base(), args),
    };
    let Some(json) = rest.first() else {
        eprintln!("settings-write: missing <json>");
        return 2;
    };
    let patch: serde_json::Value = match serde_json::from_str(json) {
        Ok(v) => v,
        Err(e) => {
            eprintln!("settings-write: parse: {e}");
            return 2;
        }
    };
    match proteus_shell_core::facts::write_settings(&base, &patch) {
        Ok(full) => {
            println!("{full}");
            0
        }
        Err(e) => {
            eprintln!("settings-write: {e}");
            1
        }
    }
}

fn cmd_posture_write(args: &[String]) -> i32 {
    let (base, rest) = match args.first().map(String::as_str) {
        Some("--config") => {
            let Some(dir) = args.get(1) else {
                eprintln!("posture-write: --config missing DIR");
                return 2;
            };
            (std::path::PathBuf::from(dir), &args[2..])
        }
        _ => (proteus_shell_core::facts::config_base(), args),
    };
    let Some(id) = rest.first() else {
        eprintln!("posture-write: missing <id>");
        return 2;
    };
    match proteus_shell_core::facts::write_posture(&base, id) {
        Ok(p) => {
            println!("{{\"posture\":\"{p}\"}}");
            0
        }
        Err(e) => {
            eprintln!("posture-write: {e}");
            1
        }
    }
}

fn cmd_facts(args: &[String]) -> i32 {
    match config_base_arg(args) {
        Ok(base) => {
            println!("{}", facts_json(&base));
            0
        }
        Err(e) => {
            eprintln!("facts: {e}");
            2
        }
    }
}

/// Repo-relative data file — same resolution ladder as EnvGate.catalogPath
/// (PROTEUS_ROOT, /mnt/proteus, dev checkout).
fn repo_data_path(rel: &str) -> Option<std::path::PathBuf> {
    let mut roots: Vec<std::path::PathBuf> = Vec::new();
    if let Ok(r) = std::env::var("PROTEUS_ROOT") {
        if !r.trim().is_empty() {
            roots.push(r.into());
        }
    }
    roots.push("/mnt/proteus".into());
    if let Ok(home) = std::env::var("HOME") {
        roots.push(std::path::Path::new(&home).join("Projects/Proteus"));
    }
    roots.into_iter().map(|r| r.join(rel)).find(|p| p.is_file())
}

fn flag<'a>(args: &'a [String], name: &str) -> Option<&'a str> {
    args.iter()
        .position(|a| a == name)
        .and_then(|i| args.get(i + 1))
        .map(String::as_str)
}

fn read_gate_catalog(args: &[String], flag_name: &str, rel: &str) -> Result<String, String> {
    let path = flag(args, flag_name)
        .map(std::path::PathBuf::from)
        .or_else(|| repo_data_path(rel))
        .ok_or_else(|| format!("{rel} not found (set PROTEUS_ROOT or {flag_name})"))?;
    std::fs::read_to_string(&path).map_err(|e| format!("{}: {e}", path.display()))
}

fn cmd_gate(args: &[String]) -> i32 {
    use proteus_shell_core::{facts, gate};
    let catalog_text = match read_gate_catalog(args, "--catalog", "env/apps/catalog.json") {
        Ok(t) => t,
        Err(e) => {
            eprintln!("gate: {e}");
            return 1;
        }
    };
    let pane_catalog_text =
        match read_gate_catalog(args, "--settings-catalog", "env/settings/catalog.json") {
            Ok(t) => t,
            Err(e) => {
                eprintln!("gate: {e}");
                return 1;
            }
        };
    match args.first().map(String::as_str) {
        Some("matrix") => {
            let Some(file) = args.get(1) else {
                eprintln!("gate matrix: missing <file>");
                return 2;
            };
            let matrix = match std::fs::read_to_string(file) {
                Ok(t) => t,
                Err(e) => {
                    eprintln!("gate matrix: {file}: {e}");
                    return 1;
                }
            };
            match gate::run_matrix_impl(&matrix, &catalog_text, &pane_catalog_text) {
                Ok(failures) if failures.is_empty() => {
                    println!("gate matrix: ok");
                    0
                }
                Ok(failures) => {
                    for f in &failures {
                        eprintln!("gate matrix: FAIL {f}");
                    }
                    1
                }
                Err(e) => {
                    eprintln!("gate matrix: {e}");
                    1
                }
            }
        }
        Some(kind @ ("app" | "pane")) => {
            let Some(id) = args.get(1).filter(|a| !a.starts_with("--")) else {
                eprintln!("gate {kind}: missing <id>");
                return 2;
            };
            // Live inputs unless overridden — same sources as the QML spine.
            let base = facts::config_base();
            let mut probe = facts::HwProbe::read(&base);
            if let Some(caps) = flag(args, "--caps") {
                probe.capabilities = caps
                    .split(',')
                    .filter(|c| !c.trim().is_empty())
                    .map(|c| (c.trim().to_lowercase(), true))
                    .collect();
                probe.ready = true;
            }
            if let Some(dc) = flag(args, "--device-class") {
                probe.device_class = dc.into();
            }
            if let Some(pr) = flag(args, "--probe-ready") {
                probe.ready = pr == "1" || pr == "true";
            }
            let posture = flag(args, "--posture")
                .map(|p| facts::normalize_posture(p).to_string())
                .unwrap_or_else(|| facts::read_posture(&base).to_string());
            let perm_store = flag(args, "--permissions")
                .map(|p| {
                    std::fs::read_to_string(p)
                        .ok()
                        .map(|t| proteus_shell_core::permissions::PermissionsStore::parse(&t))
                        .unwrap_or_default()
                })
                .or_else(|| {
                    let s = proteus_shell_core::permissions::PermissionsStore::read(&base);
                    if s.ready {
                        Some(s)
                    } else {
                        None
                    }
                });
            let ctx = gate::GateCtx {
                probe: &probe,
                remote_stub: facts::remote_stub_from_env(),
                posture,
                pane_density: flag(args, "--pane-density").unwrap_or("full").into(),
                permissions: perm_store.as_ref(),
            };
            let out = if kind == "pane" {
                let panes = match gate::PaneCatalog::parse(&pane_catalog_text) {
                    Ok(c) => c,
                    Err(e) => {
                        eprintln!("gate: {e}");
                        return 1;
                    }
                };
                serde_json::to_string(&gate::gate_pane(&panes, id, &ctx))
            } else {
                let catalog = match gate::Catalog::parse(&catalog_text) {
                    Ok(c) => c,
                    Err(e) => {
                        eprintln!("gate: {e}");
                        return 1;
                    }
                };
                let entry = gate::Entry {
                    id: id.clone(),
                    name: flag(args, "--name").unwrap_or("").into(),
                    generic_name: String::new(),
                    categories: flag(args, "--categories").unwrap_or("").into(),
                    exec: flag(args, "--exec").unwrap_or("").into(),
                };
                serde_json::to_string(&gate::gate_app(&catalog, &entry, &ctx))
            };
            println!("{}", out.expect("gate JSON"));
            0
        }
        _ => usage(),
    }
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let code = match args.first().map(String::as_str) {
        Some("tokens") => cmd_tokens(&args[1..]),
        Some("facts") => cmd_facts(&args[1..]),
        Some("settings-write") => cmd_settings_write(&args[1..]),
        Some("posture-write") => cmd_posture_write(&args[1..]),
        Some("gate") => cmd_gate(&args[1..]),
        Some("serve") => cmd_serve(&args[1..]),
        Some("schema-keys") => {
            for key in proteus_shell_core::facts::schema_keys() {
                println!("{key}");
            }
            0
        }
        Some("version") => {
            println!("proteus-shell-core {}", env!("CARGO_PKG_VERSION"));
            0
        }
        _ => usage(),
    };
    std::process::exit(code);
}
