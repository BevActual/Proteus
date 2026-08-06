// Launch resolution — the proteus-open half of rung 0, and its only runtime
// behavior swap. Ports the resolution ladders + env injection that
// ShellState.qml string-built in openSettings / openWorkloadsApp; ShellState
// now execs `proteus-open` and keeps the old bash as fallback while both
// install side by side (survivability rule 4).

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

pub const WORKLOADS_TABS: [&str; 3] = ["workloads", "apps", "shares"];

/// Repo root candidates: $PROTEUS_ROOT, then /mnt/proteus (VM mount).
fn repo_roots(root_env: Option<&str>) -> Vec<PathBuf> {
    let mut roots = Vec::new();
    if let Some(r) = root_env {
        if !r.trim().is_empty() {
            roots.push(PathBuf::from(r.trim()));
        }
    }
    roots.push(PathBuf::from("/mnt/proteus"));
    roots
}

/// Settings ladder (openSettings): the live tree launcher first — PATH may
/// still point at a stale /usr/local copy — then PATH, then the live path
/// again so the failure names the expected location.
pub fn settings_candidates(root_env: Option<&str>) -> Vec<PathBuf> {
    repo_roots(root_env)
        .iter()
        .map(|r| r.join("apps/proteus-settings/proteus-settings"))
        .collect()
}

/// Workloads ladder (openWorkloadsApp): installed binary on PATH first, then
/// sibling dev builds — $PROTEUS_WORKLOADS_ROOT, $PROTEUS_ROOT/../ProteusWorkloads,
/// /mnt/proteus-workloads (VM 9p share).
pub fn workloads_sibling_candidates(
    workloads_root_env: Option<&str>,
    root_env: Option<&str>,
) -> Vec<PathBuf> {
    let mut siblings = Vec::new();
    if let Some(w) = workloads_root_env {
        if !w.trim().is_empty() {
            siblings.push(PathBuf::from(w.trim()));
        }
    }
    if let Some(r) = root_env {
        if !r.trim().is_empty() {
            siblings.push(Path::new(r.trim()).join("../ProteusWorkloads"));
        }
    }
    siblings.push(PathBuf::from("/mnt/proteus-workloads"));
    siblings
        .iter()
        .map(|s| s.join("app/src-tauri/target/release/proteus-workloads"))
        .collect()
}

fn is_executable(p: &Path) -> bool {
    use std::os::unix::fs::PermissionsExt;
    p.is_file()
        && p.metadata()
            .map(|m| m.permissions().mode() & 0o111 != 0)
            .unwrap_or(false)
}

/// First executable candidate, or None (caller falls to PATH / error).
pub fn first_executable(candidates: &[PathBuf]) -> Option<PathBuf> {
    candidates.iter().find(|p| is_executable(p)).cloned()
}

pub fn path_lookup(bin: &str) -> Option<PathBuf> {
    let path = std::env::var("PATH").ok()?;
    std::env::split_paths(&path)
        .map(|d| d.join(bin))
        .find(|p| is_executable(p))
}

/// Deep-link env for the Settings launch (PROTEUS_SETTINGS_PAGE / _QUERY),
/// merged with the soft adapts profile (PROTEUS_ADAPT_*).
pub fn settings_env(
    page: &str,
    query: &str,
    adapt: BTreeMap<String, String>,
) -> BTreeMap<String, String> {
    let mut env = adapt;
    let page = page.trim();
    let query = query.trim();
    if !page.is_empty() {
        env.insert("PROTEUS_SETTINGS_PAGE".into(), page.into());
    }
    if !query.is_empty() {
        env.insert("PROTEUS_SETTINGS_QUERY".into(), query.into());
    }
    env
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    fn touch_exec(path: &Path) {
        use std::os::unix::fs::PermissionsExt;
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(path, "#!/bin/sh\n").unwrap();
        fs::set_permissions(path, fs::Permissions::from_mode(0o755)).unwrap();
    }

    #[test]
    fn settings_ladder_prefers_proteus_root() {
        let cands = settings_candidates(Some("/opt/checkout"));
        assert_eq!(
            cands,
            vec![
                PathBuf::from("/opt/checkout/apps/proteus-settings/proteus-settings"),
                PathBuf::from("/mnt/proteus/apps/proteus-settings/proteus-settings"),
            ]
        );
        // Blank root env falls back to the VM mount alone.
        assert_eq!(
            settings_candidates(Some("  ")),
            vec![PathBuf::from("/mnt/proteus/apps/proteus-settings/proteus-settings")]
        );
    }

    #[test]
    fn workloads_ladder_order_matches_shellstate() {
        let cands = workloads_sibling_candidates(Some("/w"), Some("/opt/checkout"));
        assert_eq!(
            cands,
            vec![
                PathBuf::from("/w/app/src-tauri/target/release/proteus-workloads"),
                PathBuf::from(
                    "/opt/checkout/../ProteusWorkloads/app/src-tauri/target/release/proteus-workloads"
                ),
                PathBuf::from("/mnt/proteus-workloads/app/src-tauri/target/release/proteus-workloads"),
            ]
        );
    }

    #[test]
    fn first_executable_skips_non_executable() {
        let tmp = std::env::temp_dir().join(format!("psc-open-test-{}", std::process::id()));
        let plain = tmp.join("plain");
        fs::create_dir_all(&tmp).unwrap();
        fs::write(&plain, "data").unwrap();
        let exec = tmp.join("nested/bin");
        touch_exec(&exec);
        let found = first_executable(&[plain.clone(), exec.clone(), tmp.join("missing")]);
        assert_eq!(found, Some(exec));
        fs::remove_dir_all(&tmp).unwrap();
    }

    #[test]
    fn settings_env_sets_deep_link_keys() {
        let mut adapt = BTreeMap::new();
        adapt.insert("PROTEUS_ADAPT_INPUT".to_string(), "pointer".to_string());
        let env = settings_env(" network ", "", adapt);
        assert_eq!(env.get("PROTEUS_SETTINGS_PAGE").unwrap(), "network");
        assert!(!env.contains_key("PROTEUS_SETTINGS_QUERY"));
        assert_eq!(env.get("PROTEUS_ADAPT_INPUT").unwrap(), "pointer");
    }
}
