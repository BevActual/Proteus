//! Profile load for ~/.config/proteus/audio-mix.json (read-only for dump/serve).

use serde_json::{json, Map, Value};
use std::fs;
use std::path::PathBuf;

pub const DEFAULT_CHANNELS: &[(&str, &str, &str)] = &[
    ("proteus_mix_system", "Apps", "system"),
    ("proteus_mix_voice", "Voice", "voice"),
    ("proteus_mix_music", "Music", "music"),
    ("proteus_mix_browser", "Browser", "browser"),
    ("proteus_mix_game", "Game", "game"),
];

pub const DEFAULT_MIXES: &[(&str, &str, &str, bool)] = &[
    ("monitor", "proteus_bus_monitor", "Monitor", true),
    ("stream", "proteus_bus_stream", "Stream", false),
];

pub fn profile_path() -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_default();
    PathBuf::from(home).join(".config/proteus/audio-mix.json")
}

pub fn slugify(label: &str) -> String {
    let s: String = label
        .trim()
        .to_lowercase()
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() { c } else { '_' })
        .collect();
    let s = s.trim_matches('_').chars().take(24).collect::<String>();
    if s.is_empty() {
        "channel".into()
    } else {
        s
    }
}

pub fn display_name(name: &str) -> String {
    let t = name.trim().replace("\\s", " ");
    if t.is_empty() {
        "App".into()
    } else {
        t
    }
}

pub fn app_key(name: &str) -> String {
    display_name(name)
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
        .to_lowercase()
}

fn default_channel_dicts() -> Vec<Value> {
    DEFAULT_CHANNELS
        .iter()
        .map(|(id, lab, short)| json!({"id": id, "label": lab, "short": short}))
        .collect()
}

fn default_mix_dicts() -> Vec<Value> {
    DEFAULT_MIXES
        .iter()
        .map(|(id, sink, lab, hear)| {
            json!({"id": id, "sink": sink, "label": lab, "hear": hear})
        })
        .collect()
}

fn default_cell() -> Value {
    json!({"on": true, "volume": 100, "muted": false})
}

pub fn normalize_cell(raw: &Value) -> Value {
    let mut cell = default_cell();
    match raw {
        Value::Bool(b) => {
            cell["on"] = json!(*b);
        }
        Value::Object(m) => {
            if let Some(on) = m.get("on") {
                cell["on"] = json!(on.as_bool().unwrap_or(true));
            } else if let Some(en) = m.get("enabled") {
                cell["on"] = json!(en.as_bool().unwrap_or(true));
            }
            if let Some(v) = m.get("volume").and_then(|x| x.as_i64()) {
                cell["volume"] = json!(v.clamp(0, 150));
            }
            if let Some(mu) = m.get("muted") {
                cell["muted"] = json!(mu.as_bool().unwrap_or(false));
            }
        }
        _ => {}
    }
    cell
}

fn normalize_channel_entry(raw: &Value) -> Option<Value> {
    let m = raw.as_object()?;
    let mut short = slugify(
        m.get("short")
            .or_else(|| m.get("id"))
            .or_else(|| m.get("label"))
            .and_then(|v| v.as_str())
            .unwrap_or(""),
    );
    if let Some(rest) = short.strip_prefix("proteus_mix_") {
        short = slugify(rest);
    }
    if short.is_empty() {
        return None;
    }
    let entry_id = format!("proteus_mix_{short}");
    let mut lab = display_name(
        m.get("label")
            .and_then(|v| v.as_str())
            .unwrap_or(&short.replace('_', " ")),
    );
    lab = lab.chars().take(40).collect();
    if entry_id == "proteus_mix_system" && lab == "System" {
        lab = "Apps".into();
    }
    Some(json!({"id": entry_id, "label": lab, "short": short}))
}

fn normalize_channels_list(raw: &Value) -> Vec<Value> {
    let Some(arr) = raw.as_array() else {
        return default_channel_dicts();
    };
    let mut out = Vec::new();
    let mut seen = std::collections::HashSet::new();
    for item in arr {
        if let Some(c) = normalize_channel_entry(item) {
            let id = c["id"].as_str().unwrap_or("").to_string();
            if seen.insert(id) {
                out.push(c);
            }
        }
    }
    out
}

fn normalize_mix_entry(raw: &Value) -> Option<Value> {
    let m = raw.as_object()?;
    let mut mid = slugify(
        m.get("id")
            .or_else(|| m.get("short"))
            .or_else(|| m.get("label"))
            .and_then(|v| v.as_str())
            .unwrap_or(""),
    );
    if let Some(rest) = mid.strip_prefix("proteus_bus_") {
        mid = slugify(rest);
    }
    if mid.is_empty() {
        return None;
    }
    let lab = display_name(
        m.get("label")
            .and_then(|v| v.as_str())
            .unwrap_or(&mid.replace('_', " ")),
    )
    .chars()
    .take(40)
    .collect::<String>();
    let mut sink = m
        .get("sink")
        .and_then(|v| v.as_str())
        .unwrap_or(&format!("proteus_bus_{mid}"))
        .to_string();
    if !sink.starts_with("proteus_bus_") {
        sink = format!("proteus_bus_{mid}");
    }
    let hear = if m.contains_key("hear") {
        m.get("hear").and_then(|v| v.as_bool()).unwrap_or(false)
    } else {
        mid == "monitor"
    };
    Some(json!({"id": mid, "sink": sink, "label": lab, "hear": hear}))
}

fn normalize_mixes_list(raw: &Value) -> Vec<Value> {
    let Some(arr) = raw.as_array() else {
        return default_mix_dicts();
    };
    let mut out = Vec::new();
    let mut seen = std::collections::HashSet::new();
    for item in arr {
        if let Some(m) = normalize_mix_entry(item) {
            let id = m["id"].as_str().unwrap_or("").to_string();
            if seen.insert(id) {
                out.push(m);
            }
        }
    }
    out
}

fn normalize_input_entry(raw: &Value) -> Option<Value> {
    let m = raw.as_object()?;
    let source = m.get("source").and_then(|v| v.as_str()).unwrap_or("").trim();
    if source.is_empty() || source.ends_with(".monitor") || source.starts_with("proteus_") {
        return None;
    }
    let mut short = slugify(
        m.get("short")
            .or_else(|| m.get("id"))
            .or_else(|| m.get("label"))
            .and_then(|v| v.as_str())
            .unwrap_or(source.rsplit('.').next().unwrap_or(source)),
    );
    if let Some(rest) = short.strip_prefix("proteus_in_") {
        short = slugify(rest);
    }
    if short.is_empty() {
        return None;
    }
    let lab = display_name(
        m.get("label")
            .and_then(|v| v.as_str())
            .unwrap_or(&short.replace('_', " ")),
    )
    .chars()
    .take(48)
    .collect::<String>();
    Some(json!({
        "id": format!("proteus_in_{short}"),
        "label": lab,
        "short": short,
        "source": source,
    }))
}

fn normalize_inputs_list(raw: &Value) -> Vec<Value> {
    let Some(arr) = raw.as_array() else {
        return Vec::new();
    };
    let mut out = Vec::new();
    let mut seen = std::collections::HashSet::new();
    let mut seen_src = std::collections::HashSet::new();
    for item in arr {
        if let Some(c) = normalize_input_entry(item) {
            let id = c["id"].as_str().unwrap_or("").to_string();
            let src = c["source"].as_str().unwrap_or("").to_string();
            if seen.insert(id) && seen_src.insert(src) {
                out.push(c);
            }
        }
    }
    out
}

pub fn load_profiles() -> Value {
    let empty = json!({
        "apps": {},
        "routes": {},
        "channels": default_channel_dicts(),
        "mixes": default_mix_dicts(),
        "inputs": [],
    });
    let path = profile_path();
    let Ok(text) = fs::read_to_string(&path) else {
        return empty;
    };
    let Ok(data) = serde_json::from_str::<Value>(&text) else {
        return empty;
    };
    let Some(obj) = data.as_object() else {
        return empty;
    };
    let apps = obj
        .get("apps")
        .and_then(|v| v.as_object())
        .cloned()
        .map(Value::Object)
        .unwrap_or_else(|| json!({}));
    let channels = if obj.contains_key("channels") {
        normalize_channels_list(obj.get("channels").unwrap_or(&Value::Null))
    } else {
        default_channel_dicts()
    };
    let mixes = if obj.contains_key("mixes") {
        normalize_mixes_list(obj.get("mixes").unwrap_or(&Value::Null))
    } else {
        default_mix_dicts()
    };
    let inputs = if obj.contains_key("inputs") {
        normalize_inputs_list(obj.get("inputs").unwrap_or(&Value::Null))
    } else {
        Vec::new()
    };
    let routes_in = obj
        .get("routes")
        .and_then(|v| v.as_object())
        .cloned()
        .unwrap_or_default();
    let mix_ids: Vec<String> = mixes
        .iter()
        .filter_map(|m| m.get("id").and_then(|v| v.as_str()).map(|s| s.to_string()))
        .collect();
    let mut routes = Map::new();
    for ch in channels.iter().chain(inputs.iter()) {
        let sid = ch.get("id").and_then(|v| v.as_str()).unwrap_or("");
        let slot_in = routes_in
            .get(sid)
            .and_then(|v| v.as_object())
            .cloned()
            .unwrap_or_default();
        let mut slot = Map::new();
        for mid in &mix_ids {
            let raw = slot_in.get(mid).cloned().unwrap_or(Value::Bool(true));
            slot.insert(mid.clone(), normalize_cell(&raw));
        }
        routes.insert(sid.to_string(), Value::Object(slot));
    }
    json!({
        "apps": apps,
        "routes": Value::Object(routes),
        "channels": channels,
        "mixes": mixes,
        "inputs": inputs,
    })
}

pub fn channel_rows(profiles: &Value) -> Vec<(String, String, String)> {
    profiles
        .get("channels")
        .and_then(|v| v.as_array())
        .into_iter()
        .flatten()
        .filter_map(|c| {
            let id = c.get("id")?.as_str()?.to_string();
            let lab = c
                .get("label")
                .and_then(|v| v.as_str())
                .unwrap_or(&id)
                .to_string();
            let short = c
                .get("short")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();
            Some((id, lab, short))
        })
        .collect()
}

pub fn mix_rows(profiles: &Value) -> Vec<(String, String, String, bool)> {
    profiles
        .get("mixes")
        .and_then(|v| v.as_array())
        .into_iter()
        .flatten()
        .filter_map(|m| {
            let id = m.get("id")?.as_str()?.to_string();
            let sink = m
                .get("sink")
                .and_then(|v| v.as_str())
                .map(|s| s.to_string())
                .unwrap_or_else(|| format!("proteus_bus_{id}"));
            let lab = m
                .get("label")
                .and_then(|v| v.as_str())
                .unwrap_or(&id)
                .to_string();
            let hear = m.get("hear").and_then(|v| v.as_bool()).unwrap_or(false);
            Some((id, sink, lab, hear))
        })
        .collect()
}

pub fn input_rows(profiles: &Value) -> Vec<(String, String, String, String)> {
    profiles
        .get("inputs")
        .and_then(|v| v.as_array())
        .into_iter()
        .flatten()
        .filter_map(|c| {
            let id = c.get("id")?.as_str()?.to_string();
            let lab = c
                .get("label")
                .and_then(|v| v.as_str())
                .unwrap_or(&id)
                .to_string();
            let short = c
                .get("short")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();
            let source = c
                .get("source")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();
            Some((id, lab, short, source))
        })
        .collect()
}

pub fn strip_meta(name: &str, profiles: &Value) -> Option<(String, String, String)> {
    for (sid, lab, short) in channel_rows(profiles) {
        if sid == name {
            return Some((sid, lab, short));
        }
    }
    for (sid, lab, short, _) in input_rows(profiles) {
        if sid == name {
            return Some((sid, lab, short));
        }
    }
    None
}

pub fn route_media(channel: &str, mix_id: &str, profiles: &Value) -> String {
    let short = if let Some((_, _, s)) = strip_meta(channel, profiles) {
        slugify(&s)
    } else if let Some(rest) = channel.strip_prefix("proteus_in_") {
        slugify(rest)
    } else {
        slugify(channel.strip_prefix("proteus_mix_").unwrap_or(channel))
    };
    if channel.starts_with("proteus_in_") {
        format!("proteus_inroute_{short}_{mix_id}")
    } else {
        format!("proteus_route_{short}_{mix_id}")
    }
}
