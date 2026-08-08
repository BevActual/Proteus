// proteus-open — owned launcher for first-party apps (OWNED-STACK rung 0).
//
// Replaces the bash resolution ladders ShellState.qml string-built in
// openSettings / openWorkloadsApp. Same semantics: live tree first for
// Settings (PATH may be stale), installed binary first for Workloads (then
// sibling dev builds); deep links travel as env (Settings) or argv
// (Workloads); the soft adapts profile is injected as PROTEUS_ADAPT_*.

use std::process::Command;

use proteus_shell_core::{facts, gate, open};

fn usage() -> ! {
    eprintln!(
        "usage: proteus-open <app> [options]\n\
         \n\
         apps:\n\
         \x20 settings [--page ID] [--query TEXT]\n\
         \x20 workloads [--tab workloads|apps|shares]"
    );
    std::process::exit(2);
}

fn flag<'a>(args: &'a [String], name: &str) -> Option<&'a str> {
    args.iter()
        .position(|a| a == name)
        .and_then(|i| args.get(i + 1))
        .map(String::as_str)
}

fn env_opt(key: &str) -> Option<String> {
    std::env::var(key).ok().filter(|v| !v.trim().is_empty())
}

/// Soft adapts env for an app id — same profile EnvGate injects on dock
/// launches. Any failure (no catalog, no probe) degrades to empty: adapts
/// never block a launch.
fn adapt_env(app_id: &str) -> std::collections::BTreeMap<String, String> {
    let try_adapt = || -> Option<std::collections::BTreeMap<String, String>> {
        let root = env_opt("PROTEUS_ROOT").unwrap_or_else(|| "/mnt/proteus".into());
        let catalog_path = std::path::Path::new(&root).join("env/apps/catalog.json");
        let catalog = gate::Catalog::parse(&std::fs::read_to_string(catalog_path).ok()?).ok()?;
        let base = facts::config_base();
        let probe = facts::HwProbe::read(&base);
        let ctx = gate::GateCtx {
            probe: &probe,
            remote_stub: facts::remote_stub_from_env(),
            posture: facts::read_posture(&base).to_string(),
            pane_density: "full".into(),
            permissions: None,
        };
        let entry = gate::Entry { id: app_id.into(), ..gate::Entry::default() };
        let rule = gate::rule_for_app(&catalog, &entry);
        Some(gate::adapt_launch_env(rule.as_ref(), &ctx))
    };
    try_adapt().unwrap_or_default()
}

fn spawn(bin: &std::path::Path, args: &[String], env: &std::collections::BTreeMap<String, String>) -> i32 {
    let mut cmd = Command::new(bin);
    cmd.args(args);
    for (k, v) in env {
        cmd.env(k, v);
    }
    match cmd.spawn() {
        Ok(_) => 0,
        Err(e) => {
            eprintln!("proteus-open: {}: {e}", bin.display());
            1
        }
    }
}

fn open_settings(args: &[String]) -> i32 {
    let page = flag(args, "--page").unwrap_or("");
    let query = flag(args, "--query").unwrap_or("");
    let env = open::settings_env(page, query, adapt_env("proteus-settings"));
    let root = env_opt("PROTEUS_ROOT");
    let candidates = open::settings_candidates(root.as_deref());
    // Live tree first (stale /usr/local copies), then PATH.
    let bin = open::first_executable(&candidates)
        .or_else(|| open::path_lookup("proteus-settings"))
        .or_else(|| open::path_lookup("proteus-settings-next"));
    let Some(bin) = bin else {
        eprintln!(
            "proteus-open: proteus-settings not found (tried {}, PATH)",
            candidates
                .iter()
                .map(|p| p.display().to_string())
                .collect::<Vec<_>>()
                .join(", ")
        );
        return 1;
    };
    // Prefer argv deep links when the iced binary understands --page/--query.
    let mut argv = Vec::new();
    if !page.is_empty() {
        argv.push(format!("--page={page}"));
    }
    if !query.is_empty() {
        argv.push(format!("--query={query}"));
    }
    spawn(&bin, &argv, &env)
}

fn open_workloads(args: &[String]) -> i32 {
    let mut argv: Vec<String> = Vec::new();
    if let Some(tab) = flag(args, "--tab") {
        let t = tab.trim().to_lowercase();
        if !open::WORKLOADS_TABS.contains(&t.as_str()) {
            eprintln!("proteus-open: unknown workloads tab '{t}' (workloads|apps|shares)");
            return 2;
        }
        argv.push("--tab".into());
        argv.push(t);
    }
    // Installed binary first, then sibling dev builds.
    let siblings = open::workloads_sibling_candidates(
        env_opt("PROTEUS_WORKLOADS_ROOT").as_deref(),
        env_opt("PROTEUS_ROOT").as_deref(),
    );
    let bin = open::path_lookup("proteus-workloads").or_else(|| open::first_executable(&siblings));
    let Some(bin) = bin else {
        eprintln!("proteus-open: proteus-workloads not installed (PATH or sibling dev build)");
        return 1;
    };
    spawn(&bin, &argv, &std::collections::BTreeMap::new())
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let code = match args.first().map(String::as_str) {
        Some("settings") => open_settings(&args[1..]),
        Some("workloads") => open_workloads(&args[1..]),
        _ => usage(),
    };
    std::process::exit(code);
}
