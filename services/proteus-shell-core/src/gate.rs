// App gating — the Rust twin of EnvGate.qml's launcher/dock logic
// (OWNED-STACK rung 0, slice 3). Ports manifest resolution
// (env/apps/catalog.json: id / desktopIds / match regex), the appRules +
// category heuristics, hard gates (requires / requiresAny / postures /
// device_classes) and the soft adapts profile — semantics kept verbatim,
// including fail-open before the probe is ready.
//
// Privacy/permissions: when `GateCtx.permissions` is `Some`, Ask/Deny is
// evaluated (Permissions.qml twin). When `None`, rules that carry
// `permissions` still report `permissionsGated: true` but do not block —
// matches the pre-port fail-open-on-hardware-only behavior for fixtures that
// omit a store.

use std::collections::BTreeMap;

use serde::Serialize;
use serde_json::Value;

use crate::facts::HwProbe;
use crate::permissions::PermissionsStore;

fn str_list(v: &Value, key: &str) -> Vec<String> {
    v[key]
        .as_array()
        .map(|a| {
            a.iter()
                .filter_map(|x| x.as_str())
                .map(str::to_string)
                .collect()
        })
        .unwrap_or_default()
}

#[derive(Debug, Default, Clone)]
pub struct Adapts {
    pub input: Vec<String>,
    pub nav: Vec<String>,
    pub panes: Vec<String>,
}

#[derive(Debug, Default, Clone)]
pub struct Rule {
    pub requires: Vec<String>,
    pub requires_any: Vec<String>,
    pub permissions: Vec<String>,
    pub postures: Vec<String>,
    pub prefers: Vec<String>,
    pub device_classes: Vec<String>,
    pub adapts: Option<Adapts>,
    pub reason: String,
}

#[derive(Debug, Clone)]
pub struct Manifest {
    pub id: String,
    pub desktop_ids: Vec<String>,
    pub match_re: Option<regex::Regex>,
    pub rule: Rule,
}

#[derive(Debug, Default)]
pub struct Catalog {
    pub manifests: Vec<Manifest>,
}

impl Catalog {
    /// Parse env/apps/catalog.json ({ manifests: [...] }); bad regexes are
    /// ignored per QML ("ignore bad regex in catalog").
    pub fn parse(text: &str) -> Result<Self, String> {
        let v: Value = serde_json::from_str(text).map_err(|e| format!("catalog parse: {e}"))?;
        let Some(list) = v["manifests"].as_array() else {
            return Err("catalog.manifests must be an array".into());
        };
        let manifests = list
            .iter()
            .map(|m| Manifest {
                id: m["id"].as_str().unwrap_or("").to_string(),
                desktop_ids: str_list(m, "desktopIds"),
                match_re: m["match"].as_str().and_then(|p| {
                    regex::RegexBuilder::new(p).case_insensitive(true).build().ok()
                }),
                rule: rule_from_manifest(m),
            })
            .collect();
        Ok(Catalog { manifests })
    }
}

fn rule_from_manifest(m: &Value) -> Rule {
    let adapts = m["adapts"].as_object().map(|_| Adapts {
        input: str_list(&m["adapts"], "input"),
        nav: str_list(&m["adapts"], "nav"),
        panes: str_list(&m["adapts"], "panes"),
    });
    let mut device_classes = str_list(m, "device_classes");
    if device_classes.is_empty() {
        device_classes = str_list(m, "deviceClasses");
    }
    Rule {
        requires: str_list(m, "requires"),
        requires_any: str_list(m, "requiresAny"),
        permissions: str_list(m, "permissions"),
        postures: str_list(m, "postures"),
        prefers: str_list(m, "prefers"),
        device_classes,
        adapts,
        reason: m["reason"]
            .as_str()
            .unwrap_or("Unavailable on this device")
            .to_string(),
    }
}

/// A launcher/dock entry — the fields EnvGate matches against.
#[derive(Debug, Default, Clone)]
pub struct Entry {
    pub id: String,
    pub name: String,
    pub generic_name: String,
    pub categories: String,
    pub exec: String,
}

/// Gating context — posture + probe + soft density (FocusMode.paneDensity).
pub struct GateCtx<'a> {
    pub probe: &'a HwProbe,
    pub remote_stub: bool,
    pub posture: String,
    pub pane_density: String,
    /// When set, privacy Ask/Deny participates in `gate_app`.
    pub permissions: Option<&'a PermissionsStore>,
}

impl GateCtx<'_> {
    /// gatingActive = Hardware.ready (fail open before the probe lands).
    pub fn gating_active(&self) -> bool {
        self.probe.ready
    }

    fn has(&self, cap: &str) -> bool {
        self.probe.has(cap, self.remote_stub)
    }

    fn has_all(&self, list: &[String]) -> bool {
        list.iter().all(|c| self.has(c))
    }

    fn has_any(&self, list: &[String]) -> bool {
        list.is_empty() || list.iter().any(|c| self.has(c))
    }
}

pub fn normalize_desktop_id(id: &str) -> String {
    let s = id.trim().to_lowercase();
    s.strip_suffix(".desktop").unwrap_or(&s).to_string()
}

pub fn manifest_for_app<'a>(catalog: &'a Catalog, entry: &Entry) -> Option<&'a Manifest> {
    let id = normalize_desktop_id(&entry.id);
    let hay = format!("{} {} {} {}", entry.id, entry.name, entry.generic_name, entry.exec);
    catalog.manifests.iter().find(|m| {
        if !m.id.is_empty() && normalize_desktop_id(&m.id) == id {
            return true;
        }
        if m.desktop_ids.iter().any(|d| normalize_desktop_id(d) == id) {
            return true;
        }
        m.match_re.as_ref().is_some_and(|re| re.is_match(&hay))
    })
}

/// EnvGate.appRules — regex heuristics for apps with no manifest.
fn builtin_rules() -> Vec<(regex::Regex, Rule)> {
    let mk = |pat: &str, requires_any: &[&str], reason: &str| {
        (
            regex::RegexBuilder::new(pat)
                .case_insensitive(true)
                .build()
                .expect("builtin rule regex"),
            Rule {
                requires_any: requires_any.iter().map(|s| s.to_string()).collect(),
                reason: reason.to_string(),
                ..Rule::default()
            },
        )
    };
    vec![
        mk(
            "(pavucontrol|easyeffects|qpwgraph|helvum|cadence|carla|audacity)",
            &["speaker", "mic", "qs_pipewire"],
            "Needs audio",
        ),
        mk(
            "(nm-connection|nmtui|networkmanager|wifi|wi-fi)",
            &["wifi", "ethernet"],
            "Needs network",
        ),
        mk("(blueman|blueberry|bluetooth)", &["bt"], "Needs Bluetooth"),
        mk(
            "(virt-manager|virtualbox|gnome-boxes|aqemu)",
            &["libvirt", "containers"],
            "Needs virtualization",
        ),
        mk("(steam|lutris|heroic|gamescope)", &["display"], "Needs a display"),
    ]
}

/// ruleForApp: manifest first, then heuristics, then Freedesktop category
/// inference (AudioVideo/Audio → audio caps; Network → network caps).
pub fn rule_for_app(catalog: &Catalog, entry: &Entry) -> Option<Rule> {
    if let Some(m) = manifest_for_app(catalog, entry) {
        return Some(m.rule.clone());
    }
    let hay = format!(
        "{} {} {} {} {}",
        entry.id, entry.name, entry.generic_name, entry.categories, entry.exec
    );
    for (re, rule) in builtin_rules() {
        if re.is_match(&hay) {
            return Some(rule);
        }
    }
    let cats = entry.categories.to_lowercase();
    if cats.contains("audiovideo")
        || cats.split(';').any(|c| c == "audio")
    {
        return Some(Rule {
            requires_any: vec!["speaker".into(), "mic".into(), "qs_pipewire".into()],
            reason: "Needs audio".into(),
            ..Rule::default()
        });
    }
    if cats.contains("network") {
        return Some(Rule {
            requires_any: vec!["wifi".into(), "ethernet".into(), "bt".into()],
            reason: "Needs network".into(),
            ..Rule::default()
        });
    }
    None
}

pub fn normalize_posture_id(raw: &str) -> String {
    let p = raw.trim().to_lowercase();
    match p.as_str() {
        "couch" | "media" => "console".into(),
        _ => p,
    }
}

/// Empty postures list = allowed on any posture (fail-open).
pub fn posture_allowed(rule: &Rule, posture: &str) -> bool {
    rule.postures.is_empty()
        || rule.postures.iter().any(|p| normalize_posture_id(p) == posture)
}

fn posture_block_reason(rule: &Rule) -> String {
    let labels: Vec<String> = rule
        .postures
        .iter()
        .map(|p| normalize_posture_id(p))
        .filter(|p| !p.is_empty())
        .collect();
    if labels.is_empty() {
        "Unavailable in this posture".into()
    } else {
        format!("Needs {} posture", labels.join(" / "))
    }
}

/// Empty device_classes or unknown current class = fail-open.
pub fn device_class_allowed(rule: &Rule, device_class: &str) -> bool {
    if rule.device_classes.is_empty() || device_class.is_empty() {
        return true;
    }
    rule.device_classes
        .iter()
        .any(|d| d.trim().to_lowercase() == device_class)
}

fn device_class_block_reason(rule: &Rule) -> String {
    let labels: Vec<String> = rule
        .device_classes
        .iter()
        .map(|d| d.trim().to_lowercase())
        .filter(|d| !d.is_empty())
        .collect();
    if labels.is_empty() {
        "Unavailable on this device class".into()
    } else {
        format!("Needs {} device class", labels.join(" / "))
    }
}

pub fn prefers_satisfied(rule: &Rule, ctx: &GateCtx) -> bool {
    rule.prefers.is_empty() || ctx.has_all(&rule.prefers)
}

#[derive(Debug, Default, Serialize, PartialEq, Eq)]
pub struct AdaptProfile {
    pub input: String,
    pub nav: String,
    pub panes: String,
}

/// appAdaptProfile — soft shaping hints; empty until gating is active.
pub fn adapt_profile(rule: Option<&Rule>, ctx: &GateCtx) -> AdaptProfile {
    let mut out = AdaptProfile::default();
    if !ctx.gating_active() {
        return out;
    }
    let Some(adapts) = rule.and_then(|r| r.adapts.as_ref()) else {
        return out;
    };
    // input: first listed capability that is present.
    for cap in &adapts.input {
        let c = cap.trim().to_lowercase();
        if !c.is_empty() && ctx.has(&c) {
            out.input = c;
            break;
        }
    }
    // nav: console wants sparse, else dense; fall back to first known value.
    if !adapts.nav.is_empty() {
        let want = if ctx.posture == "console" { "sparse" } else { "dense" };
        let mut pick = String::new();
        for n in &adapts.nav {
            let n = n.trim().to_lowercase();
            if n == want {
                pick = n;
                break;
            }
            if pick.is_empty() && (n == "dense" || n == "sparse") {
                pick = n;
            }
        }
        out.nav = pick;
    }
    // panes: Focus density (minimal|full); soft only.
    if !adapts.panes.is_empty() {
        let want = if ctx.pane_density.trim().to_lowercase() == "minimal" {
            "minimal"
        } else {
            "full"
        };
        let mut pick = String::new();
        for p in &adapts.panes {
            let p = p.trim().to_lowercase();
            if p == want {
                pick = p;
                break;
            }
            if pick.is_empty() && (p == "full" || p == "minimal") {
                pick = p;
            }
        }
        out.panes = pick;
    }
    out
}

/// Launch env from the adapts profile (PROTEUS_ADAPT_* — soft, never blocks).
pub fn adapt_launch_env(rule: Option<&Rule>, ctx: &GateCtx) -> BTreeMap<String, String> {
    let p = adapt_profile(rule, ctx);
    let mut env = BTreeMap::new();
    if !p.input.is_empty() {
        env.insert("PROTEUS_ADAPT_INPUT".into(), p.input);
    }
    if !p.nav.is_empty() {
        env.insert("PROTEUS_ADAPT_NAV".into(), p.nav);
    }
    if !p.panes.is_empty() {
        env.insert("PROTEUS_ADAPT_PANES".into(), p.panes);
    }
    env
}

// ------------------------------------------------------------------ panes --

/// env/settings/catalog.json — Settings hub gating data, shared with
/// EnvGate.qml (which loads the same file) and proteus-cli-surface.
#[derive(Debug, Default)]
pub struct PaneCatalog {
    pub hubs: Vec<(String, Rule)>,
    pub minimal_allow: Vec<String>,
}

impl PaneCatalog {
    pub fn parse(text: &str) -> Result<Self, String> {
        let v: Value = serde_json::from_str(text).map_err(|e| format!("pane catalog parse: {e}"))?;
        let Some(list) = v["hubs"].as_array() else {
            return Err("catalog.hubs must be an array".into());
        };
        let hubs = list
            .iter()
            .map(|h| {
                (
                    h["id"].as_str().unwrap_or("").to_string(),
                    Rule {
                        requires: str_list(h, "requires"),
                        requires_any: str_list(h, "requiresAny"),
                        postures: str_list(h, "postures"),
                        ..Rule::default()
                    },
                )
            })
            .collect();
        Ok(PaneCatalog { hubs, minimal_allow: str_list(&v, "minimalPaneAllow") })
    }

    fn spec(&self, id: &str) -> Option<&Rule> {
        self.hubs.iter().find(|(hid, _)| hid == id).map(|(_, r)| r)
    }

    /// paneHubFor — leaf pages inherit their hub's gates
    /// (desktop-gaps → desktop; keyboard → peripherals).
    pub fn hub_for(&self, id: &str) -> Option<&str> {
        if id.is_empty() {
            return None;
        }
        if id == "keyboard" || id.starts_with("peripherals") {
            return Some("peripherals");
        }
        self.hubs
            .iter()
            .map(|(hid, _)| hid.as_str())
            .find(|hub| id == *hub || id.starts_with(&format!("{hub}-")))
    }

    fn spec_resolved(&self, id: &str) -> Option<&Rule> {
        self.spec(id)
            .or_else(|| self.hub_for(id).and_then(|hub| self.spec(hub)))
    }

    /// Focus paneDensity=minimal allow list; privacy- leaves always stay.
    pub fn allowed_when_minimal(&self, id: &str) -> bool {
        id.is_empty()
            || self.minimal_allow.iter().any(|a| a == id)
            || id.starts_with("privacy-")
    }
}

#[derive(Debug, Serialize)]
pub struct PaneGate {
    pub available: bool,
    pub block_reason: String,
    pub gating_active: bool,
}

/// paneAvailable + paneBlockReason. Focus hide and posture gates apply even
/// before Hardware.ready; capability gates need the probe.
pub fn gate_pane(catalog: &PaneCatalog, id: &str, ctx: &GateCtx) -> PaneGate {
    let minimal = ctx.pane_density.trim().to_lowercase() == "minimal";
    let done = |available: bool, block: String| PaneGate {
        available,
        block_reason: block,
        gating_active: ctx.gating_active(),
    };
    if minimal && !catalog.allowed_when_minimal(id) {
        return done(false, "Hidden while Focus is on".into());
    }
    let spec = catalog.spec_resolved(id);
    if let Some(spec) = spec {
        if !posture_allowed(spec, &ctx.posture) {
            return done(false, posture_block_reason(spec));
        }
    }
    if !ctx.gating_active() {
        return done(true, String::new());
    }
    let Some(spec) = spec else {
        // Unknown pane: fail open, matching QML ("Unavailable on this
        // device" is only reachable there through inconsistent state).
        return done(true, String::new());
    };
    if !ctx.has_all(&spec.requires) || !ctx.has_any(&spec.requires_any) {
        // Reason precedence mirrors paneBlockReason: requiresAny wording
        // wins whenever the spec lists one, regardless of which gate failed.
        let block = if !spec.requires_any.is_empty() {
            format!("Needs {}", spec.requires_any.join(" or "))
        } else {
            format!("Needs {}", spec.requires.join(", "))
        };
        return done(false, block);
    }
    done(true, String::new())
}

#[derive(Debug, Serialize)]
pub struct AppGate {
    pub available: bool,
    pub block_reason: String,
    pub prefers_satisfied: bool,
    pub permissions_gated: bool,
    pub gating_active: bool,
    pub privacy_ask_category: String,
    pub privacy_block_pane: String,
    pub adapt: AdaptProfile,
}

fn app_gate_ok(adapt: AdaptProfile, permissions_gated: bool, gating_active: bool) -> AppGate {
    AppGate {
        available: true,
        block_reason: String::new(),
        prefers_satisfied: true,
        permissions_gated,
        gating_active,
        privacy_ask_category: String::new(),
        privacy_block_pane: String::new(),
        adapt,
    }
}

/// appAvailable + appBlockReason: hardware/posture/device class, then privacy.
pub fn gate_app(catalog: &Catalog, entry: &Entry, ctx: &GateCtx) -> AppGate {
    let rule = rule_for_app(catalog, entry);
    let adapt = adapt_profile(rule.as_ref(), ctx);
    let permissions_gated = rule.as_ref().is_some_and(|r| !r.permissions.is_empty());
    if !ctx.gating_active() {
        return app_gate_ok(adapt, permissions_gated, false);
    }
    let Some(rule) = rule else {
        return app_gate_ok(adapt, false, true);
    };
    let mut block = String::new();
    if !posture_allowed(&rule, &ctx.posture) {
        block = posture_block_reason(&rule);
    } else if !device_class_allowed(&rule, &ctx.probe.device_class.to_lowercase()) {
        block = device_class_block_reason(&rule);
    } else if !ctx.has_all(&rule.requires) || !ctx.has_any(&rule.requires_any) {
        block = rule.reason.clone();
    }

    let mut privacy_ask_category = String::new();
    let mut privacy_block_pane = String::new();
    if block.is_empty() {
        if let Some(store) = ctx.permissions {
            let reason = store.denied_reason(&entry.id, &rule.permissions);
            if !reason.is_empty() {
                block = reason;
                privacy_ask_category = store.ask_category(&entry.id, &rule.permissions);
                privacy_block_pane = store.block_pane(&entry.id, &rule.permissions);
            }
        }
    }

    AppGate {
        available: block.is_empty(),
        block_reason: block,
        prefers_satisfied: prefers_satisfied(&rule, ctx),
        permissions_gated,
        gating_active: true,
        privacy_ask_category,
        privacy_block_pane,
        adapt,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const CATALOG: &str = include_str!("../../../env/apps/catalog.json");
    const PANES: &str = include_str!("../../../env/settings/catalog.json");
    const MATRIX: &str = include_str!("../../../dev/fixtures/gate-matrix.json");

    fn probe(caps: &[&str], device_class: &str, ready: bool) -> HwProbe {
        HwProbe {
            device_class: device_class.into(),
            posture_hint: "desktop".into(),
            capabilities: caps.iter().map(|c| (c.to_string(), true)).collect(),
            ready,
            ..HwProbe::default()
        }
    }

    #[test]
    fn catalog_parses_with_regexes() {
        let cat = Catalog::parse(CATALOG).unwrap();
        assert!(cat.manifests.len() >= 8);
        assert!(cat.manifests.iter().all(|m| !m.id.is_empty()));
        // steam's \bsteam\b regex must have compiled.
        let steam = cat.manifests.iter().find(|m| m.id == "steam").unwrap();
        assert!(steam.match_re.as_ref().unwrap().is_match("run steam now"));
        assert!(!steam.match_re.as_ref().unwrap().is_match("steamroller"));
    }

    #[test]
    fn manifest_matching_mirrors_envgate() {
        let cat = Catalog::parse(CATALOG).unwrap();
        // desktopId normalization: trailing .desktop + case.
        let e = Entry { id: "Org.PulseAudio.Pavucontrol.desktop".into(), ..Entry::default() };
        assert_eq!(manifest_for_app(&cat, &e).unwrap().id, "pavucontrol");
        // match regex over the haystack (exec string).
        let e = Entry { id: "custom".into(), exec: "/usr/bin/nmtui".into(), ..Entry::default() };
        assert_eq!(manifest_for_app(&cat, &e).unwrap().id, "nm-connection-editor");
    }

    #[test]
    fn heuristics_and_category_fallbacks() {
        let cat = Catalog::parse(CATALOG).unwrap();
        let e = Entry { id: "lutris".into(), name: "Lutris".into(), ..Entry::default() };
        let r = rule_for_app(&cat, &e).unwrap();
        assert_eq!(r.requires_any, vec!["display"]);
        let e = Entry {
            id: "some.player".into(),
            categories: "AudioVideo;Player".into(),
            ..Entry::default()
        };
        assert_eq!(rule_for_app(&cat, &e).unwrap().reason, "Needs audio");
        let e = Entry { id: "plain-editor".into(), ..Entry::default() };
        assert!(rule_for_app(&cat, &e).is_none());
    }

    #[test]
    fn fail_open_before_probe_ready() {
        let cat = Catalog::parse(CATALOG).unwrap();
        let p = probe(&[], "", false);
        let ctx = GateCtx {
            probe: &p,
            remote_stub: false,
            posture: "desktop".into(),
            pane_density: "full".into(),
            permissions: None,
        };
        let e = Entry { id: "proteus-workloads".into(), ..Entry::default() };
        let g = gate_app(&cat, &e, &ctx);
        assert!(g.available && !g.gating_active);
    }

    #[test]
    fn fixture_matrix_passes() {
        let failures = run_matrix_impl(MATRIX, CATALOG, PANES).unwrap();
        assert!(failures.is_empty(), "{failures:#?}");
    }

    #[test]
    fn pane_catalog_parses_and_resolves_hubs() {
        let cat = PaneCatalog::parse(PANES).unwrap();
        assert_eq!(cat.hubs.len(), 15);
        assert!(!cat.minimal_allow.is_empty());
        assert_eq!(cat.hub_for("desktop-gaps"), Some("desktop"));
        assert_eq!(cat.hub_for("keyboard"), Some("peripherals"));
        assert_eq!(cat.hub_for("peripherals-mouse"), Some("peripherals"));
        assert_eq!(cat.hub_for("nonexistent-thing"), None);
    }

    #[test]
    fn pane_gating_mirrors_envgate() {
        let cat = PaneCatalog::parse(PANES).unwrap();
        let p = probe(&["display"], "desktop", true);
        fn mk_ctx<'a>(posture: &str, density: &str, probe: &'a HwProbe) -> GateCtx<'a> {
            GateCtx {
                probe,
                remote_stub: false,
                posture: posture.into(),
                pane_density: density.into(),
                permissions: None,
            }
        }
        // Desktop hub is desktop-posture only; leaves inherit.
        let ctx = mk_ctx("console", "full", &p);
        assert!(!gate_pane(&cat, "desktop", &ctx).available);
        assert!(!gate_pane(&cat, "desktop-gaps", &ctx).available);
        assert_eq!(gate_pane(&cat, "desktop", &ctx).block_reason, "Needs desktop posture");
        // Sound needs audio caps (requiresAny wording).
        let ctx = mk_ctx("desktop", "full", &p);
        let g = gate_pane(&cat, "sound", &ctx);
        assert!(!g.available);
        assert_eq!(g.block_reason, "Needs speaker or mic or qs_pipewire");
        // Focus minimal hides non-allowlisted panes even before probe ready;
        // privacy leaves stay.
        let unready = probe(&[], "", false);
        let ctx = mk_ctx("desktop", "minimal", &unready);
        assert!(!gate_pane(&cat, "style", &ctx).available);
        assert_eq!(gate_pane(&cat, "style", &ctx).block_reason, "Hidden while Focus is on");
        assert!(gate_pane(&cat, "privacy-camera", &ctx).available);
        assert!(gate_pane(&cat, "system", &ctx).available);
        // Posture gate applies before probe ready; caps gate does not.
        let ctx = mk_ctx("console", "full", &unready);
        assert!(!gate_pane(&cat, "virtualization", &ctx).available);
        assert!(gate_pane(&cat, "sound", &ctx).available, "caps fail open before probe");
    }
}

/// Evaluate a gate-matrix fixture (dev/fixtures/gate-matrix.json) against the
/// apps + panes catalogs; returns failure descriptions (empty = pass). Cases
/// with a `pane` field exercise gate_pane, the rest gate_app. Used by both
/// the cargo test above and the `gate matrix` CLI so smoke and unit
/// expectations can never diverge.
pub fn run_matrix_impl(
    matrix_text: &str,
    catalog_text: &str,
    pane_catalog_text: &str,
) -> Result<Vec<String>, String> {
    let catalog = Catalog::parse(catalog_text)?;
    let panes = PaneCatalog::parse(pane_catalog_text)?;
    let v: Value = serde_json::from_str(matrix_text).map_err(|e| format!("matrix parse: {e}"))?;
    let Some(cases) = v["cases"].as_array() else {
        return Err("matrix.cases must be an array".into());
    };
    let mut failures = Vec::new();
    for case in cases {
        let name = case["name"].as_str().unwrap_or("unnamed");
        let entry = Entry {
            id: case["entry"]["id"].as_str().unwrap_or("").into(),
            name: case["entry"]["name"].as_str().unwrap_or("").into(),
            generic_name: case["entry"]["genericName"].as_str().unwrap_or("").into(),
            categories: case["entry"]["categories"].as_str().unwrap_or("").into(),
            exec: case["entry"]["exec"].as_str().unwrap_or("").into(),
        };
        let probe = HwProbe {
            device_class: case["deviceClass"].as_str().unwrap_or("").into(),
            posture_hint: "desktop".into(),
            capabilities: str_list(case, "caps")
                .into_iter()
                .map(|c| (c, true))
                .collect(),
            ready: case["probeReady"].as_bool().unwrap_or(true),
            ..HwProbe::default()
        };
        let ctx = GateCtx {
            probe: &probe,
            remote_stub: case["remoteStub"].as_bool().unwrap_or(false),
            posture: case["posture"].as_str().unwrap_or("desktop").into(),
            pane_density: case["paneDensity"].as_str().unwrap_or("full").into(),
            permissions: None,
        };
        let expect = &case["expect"];
        if let Some(pane) = case["pane"].as_str() {
            let g = gate_pane(&panes, pane, &ctx);
            if let Some(want) = expect["available"].as_bool() {
                if want != g.available {
                    failures.push(format!(
                        "{name}: pane available = {} ({}), want {want}",
                        g.available, g.block_reason
                    ));
                }
            }
            if let Some(want) = expect["blockReason"].as_str() {
                if want != g.block_reason {
                    failures.push(format!(
                        "{name}: pane blockReason = {:?}, want {want:?}",
                        g.block_reason
                    ));
                }
            }
            continue;
        }
        let g = gate_app(&catalog, &entry, &ctx);
        if let Some(want) = expect["available"].as_bool() {
            if want != g.available {
                failures.push(format!(
                    "{name}: available = {} ({}), want {want}",
                    g.available, g.block_reason
                ));
            }
        }
        for (field, got) in [
            ("blockReason", g.block_reason.as_str()),
            ("adaptInput", g.adapt.input.as_str()),
            ("adaptNav", g.adapt.nav.as_str()),
            ("adaptPanes", g.adapt.panes.as_str()),
        ] {
            if let Some(want) = expect[field].as_str() {
                if want != got {
                    failures.push(format!("{name}: {field} = {got:?}, want {want:?}"));
                }
            }
        }
        if let Some(want) = expect["prefersSatisfied"].as_bool() {
            if want != g.prefers_satisfied {
                failures.push(format!("{name}: prefersSatisfied = {}", g.prefers_satisfied));
            }
        }
        if let Some(want) = expect["permissionsGated"].as_bool() {
            if want != g.permissions_gated {
                failures.push(format!("{name}: permissionsGated = {}", g.permissions_gated));
            }
        }
    }
    Ok(failures)
}
