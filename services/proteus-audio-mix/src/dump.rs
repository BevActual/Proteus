//! Build dump JSON compatible with Audio.qml / audio-mix.py dump.

use crate::pactl::Cache;
use crate::profile::{
    app_key, channel_rows, display_name, input_rows, load_profiles, mix_rows, normalize_cell,
    profile_path, route_media, strip_meta,
};
use serde_json::{json, Value};
use std::collections::HashSet;
use std::fs;

fn is_skipped_app(name: &str) -> bool {
    const SKIP: &[&str] = &[
        "",
        "wireplumber",
        "wireplumber [export]",
        "pipewire",
        "pipewire-pulse",
        "xdg-desktop-portal",
        "xdg-desktop-portal-hyprland",
        "xdg-desktop-portal-gtk",
        "xdg-desktop-portal-wlr",
        "loopback",
        "module-loopback",
        "parec",
        "pw-cat",
        "speech-dispatcher-dummy",
        "speech-dispatcher",
    ];
    let k = app_key(name);
    if SKIP.contains(&k.as_str()) {
        return true;
    }
    if name.contains('\\') || k.starts_with("pipewire alsa") || k.contains("loopback") {
        return true;
    }
    false
}

fn channel_for_sink(name: &str, profiles: &Value) -> Option<String> {
    strip_meta(name, profiles).map(|(id, _, _)| id)
}

fn label_for_sink(name: &str, profiles: &Value) -> String {
    if let Some((_, lab, _)) = strip_meta(name, profiles) {
        return lab;
    }
    for (_mid, sink, lab, _) in mix_rows(profiles) {
        if sink == name {
            return lab;
        }
    }
    if name.is_empty() {
        return "—".into();
    }
    let tail = name.rsplit('.').next().unwrap_or(name);
    let cleaned = tail.replace("__", " ").replace('-', " ").replace('_', " ");
    let s = cleaned.split_whitespace().collect::<Vec<_>>().join(" ");
    let s: String = s.chars().take(42).collect();
    if s.is_empty() {
        name.into()
    } else {
        s
    }
}

fn hint_channel(name: &str, profiles: &Value) -> String {
    let ids: HashSet<String> = channel_rows(profiles).into_iter().map(|(id, _, _)| id).collect();
    let lower = name.to_lowercase();
    let hints: &[(&[&str], &str)] = &[
        (
            &["discord", "zoom", "teams", "slack", "signal", "element", "mumble"],
            "proteus_mix_voice",
        ),
        (
            &[
                "spotify",
                "rhythmbox",
                "vlc",
                "mpv",
                "clementine",
                "strawberry",
                "amberol",
            ],
            "proteus_mix_music",
        ),
        (
            &[
                "firefox", "chrome", "chromium", "brave", "zen", "edge", "vivaldi", "librewolf",
            ],
            "proteus_mix_browser",
        ),
        (
            &["steam", "lutris", "heroic", "wine", "gamescope", "minecraft", "proton"],
            "proteus_mix_game",
        ),
    ];
    for (needles, ch) in hints {
        if ids.contains(*ch) && needles.iter().any(|n| lower.contains(n)) {
            return (*ch).to_string();
        }
    }
    String::new()
}

fn known_from_wireplumber() -> Vec<String> {
    let home = std::env::var("HOME").unwrap_or_default();
    let path = format!("{home}/.local/state/wireplumber/stream-properties");
    let Ok(text) = fs::read_to_string(path) else {
        return Vec::new();
    };
    let mut names = Vec::new();
    let mut seen = HashSet::new();
    let marker = "Output/Audio:application.name:";
    for line in text.split(marker).skip(1) {
        let Some(eq) = line.find('=') else {
            continue;
        };
        let raw = display_name(&line[..eq]);
        let k = app_key(&raw);
        if is_skipped_app(&raw) || !seen.insert(k) {
            continue;
        }
        names.push(raw);
    }
    names
}

fn prop_quoted(block: &str, key: &str) -> String {
    let needle = format!("{key} = \"");
    if let Some(i) = block.find(&needle) {
        let rest = &block[i + needle.len()..];
        if let Some(end) = rest.find('"') {
            return rest[..end].to_string();
        }
    }
    String::new()
}

fn first_percent(block: &str) -> i64 {
    if let Some(i) = block.find("Volume:") {
        let slice = &block[i..block[i..].find('\n').map(|n| i + n).unwrap_or(block.len())];
        let bytes = slice.as_bytes();
        let mut j = 0;
        while j < bytes.len() {
            if bytes[j].is_ascii_digit() {
                let start = j;
                while j < bytes.len() && bytes[j].is_ascii_digit() {
                    j += 1;
                }
                if j < bytes.len() && bytes[j] == b'%' {
                    if let Some(v) = std::str::from_utf8(&bytes[start..j])
                        .ok()
                        .and_then(|t| t.parse().ok())
                    {
                        return v;
                    }
                }
            } else {
                j += 1;
            }
        }
    }
    100
}

fn split_sink_inputs(out: &str) -> Vec<String> {
    let mut blocks = Vec::new();
    let mut cur = String::new();
    for line in out.lines() {
        if line.starts_with("Sink Input #") {
            if !cur.is_empty() {
                blocks.push(cur);
            }
            cur = line.to_string();
            cur.push('\n');
        } else if !cur.is_empty() {
            cur.push_str(line);
            cur.push('\n');
        }
    }
    if !cur.is_empty() {
        blocks.push(cur);
    }
    blocks
}

fn list_playing(cache: &mut Cache, sinks: &[crate::pactl::Sink], profiles: &Value) -> Vec<Value> {
    let out = cache.sink_inputs_raw();
    let by_id: std::collections::HashMap<&str, &str> =
        sinks.iter().map(|s| (s.id.as_str(), s.name.as_str())).collect();
    let mut apps = Vec::new();
    for block in split_sink_inputs(&out) {
        let id = block
            .strip_prefix("Sink Input #")
            .and_then(|r| r.split(|c: char| !c.is_ascii_digit()).next())
            .unwrap_or("")
            .to_string();
        if id.is_empty() {
            continue;
        }
        let media_name = prop_quoted(&block, "media.name");
        let app_name = prop_quoted(&block, "application.name");
        if media_name.starts_with("proteus_loop_")
            || media_name.starts_with("proteus_bus_")
            || media_name.starts_with("proteus_route_")
            || media_name.starts_with("proteus_inroute_")
            || media_name.starts_with("proteus_incapture_")
            || media_name.starts_with("proteus_hear_")
        {
            continue;
        }
        if block.contains("node.group = \"loopback-") || block.contains("node.link-group = \"loopback-")
        {
            continue;
        }
        let bin_name = prop_quoted(&block, "application.process.binary");
        if bin_name.to_lowercase().contains("loopback")
            || app_name == "Loopback"
            || app_name == "module-loopback"
        {
            continue;
        }
        let name_src = if !app_name.is_empty() {
            app_name.as_str()
        } else {
            bin_name.as_str()
        };
        let name = display_name(name_src);
        if name.is_empty() || is_skipped_app(&name) {
            continue;
        }
        let detail = if !media_name.is_empty()
            && media_name != name
            && !media_name.starts_with("loopback")
        {
            media_name
        } else if !bin_name.is_empty() && bin_name != name {
            bin_name
        } else {
            String::new()
        };
        let mut sink_id = String::new();
        for line in block.lines() {
            let t = line.trim();
            if let Some(rest) = t.strip_prefix("Sink:") {
                sink_id = rest.trim().to_string();
                break;
            }
        }
        let sink_name = by_id.get(sink_id.as_str()).copied().unwrap_or("").to_string();
        let ch = if sink_name.is_empty() {
            None
        } else {
            channel_for_sink(&sink_name, profiles)
        };
        let muted = block.to_lowercase().contains("mute: yes");
        apps.push(json!({
            "id": id,
            "key": app_key(&name),
            "name": name,
            "detail": detail,
            "volume": first_percent(&block),
            "muted": muted,
            "sink": sink_name,
            "sinkLabel": if sink_name.is_empty() { "—".into() } else { label_for_sink(&sink_name, profiles) },
            "channel": ch.clone().unwrap_or_default(),
            "inMix": ch.is_some(),
            "playing": true,
        }));
    }
    apps
}

fn matches_profile_key(playing: &Value, key: &str, desktop_id: &str) -> bool {
    if playing.get("key").and_then(|v| v.as_str()) == Some(key) {
        return true;
    }
    let name = app_key(playing.get("name").and_then(|v| v.as_str()).unwrap_or(""));
    if name == key {
        return true;
    }
    let detail = app_key(playing.get("detail").and_then(|v| v.as_str()).unwrap_or(""));
    if !detail.is_empty() && detail == key {
        return true;
    }
    let desk_raw = desktop_id.replace(".desktop", "");
    let desk = app_key(desk_raw.rsplit('.').next().unwrap_or(""));
    if !desk.is_empty()
        && (name == desk
            || detail == desk
            || playing.get("key").and_then(|v| v.as_str()) == Some(desk.as_str()))
    {
        return true;
    }
    false
}

fn apply_profiles(cache: &mut Cache, playing: &[Value], profiles: &Value, sinks: &[crate::pactl::Sink]) {
    let Some(apps_prof) = profiles.get("apps").and_then(|v| v.as_object()) else {
        return;
    };
    for a in playing {
        let mut want = String::new();
        for (pkey, prof) in apps_prof {
            let Some(prof) = prof.as_object() else {
                continue;
            };
            let desk = prof
                .get("desktopId")
                .and_then(|v| v.as_str())
                .unwrap_or("");
            if a.get("key").and_then(|v| v.as_str()) == Some(pkey.as_str())
                || matches_profile_key(a, pkey, desk)
            {
                want = prof
                    .get("sink")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .to_string();
                break;
            }
        }
        if want.is_empty()
            || !sinks.iter().any(|s| s.name == want)
            || a.get("sink").and_then(|v| v.as_str()) == Some(want.as_str())
        {
            continue;
        }
        if let Some(sid) = a.get("id").and_then(|v| v.as_str()) {
            if !sid.is_empty() {
                cache.move_sink_input(sid, &want);
            }
        }
    }
}

fn merge_apps(playing: Vec<Value>, profiles: &Value) -> Vec<Value> {
    let mut by_key: std::collections::HashMap<String, Value> = std::collections::HashMap::new();
    for name in known_from_wireplumber() {
        let k = app_key(&name);
        by_key.insert(
            k.clone(),
            json!({
                "id": "",
                "key": k,
                "name": name,
                "detail": "",
                "volume": 100,
                "muted": false,
                "sink": "",
                "sinkLabel": "—",
                "channel": "",
                "inMix": false,
                "playing": false,
            }),
        );
    }
    if let Some(apps_prof) = profiles.get("apps").and_then(|v| v.as_object()) {
        for (key, prof) in apps_prof {
            let Some(prof) = prof.as_object() else {
                continue;
            };
            if is_skipped_app(key) {
                continue;
            }
            let k = app_key(key);
            let label = display_name(prof.get("label").and_then(|v| v.as_str()).unwrap_or(key));
            let sink = prof
                .get("sink")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();
            let ch = if sink.is_empty() {
                None
            } else {
                channel_for_sink(&sink, profiles)
            };
            let mut slot = by_key.get(&k).cloned().unwrap_or_else(|| {
                json!({
                    "id": "",
                    "key": k,
                    "name": label,
                    "detail": "",
                    "volume": 100,
                    "muted": false,
                    "sink": "",
                    "sinkLabel": "—",
                    "channel": "",
                    "inMix": false,
                    "playing": false,
                })
            });
            let prev_name = slot
                .get("name")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();
            slot["name"] = json!(if label.is_empty() { prev_name } else { label });
            if let Some(desk) = prof.get("desktopId").and_then(|v| v.as_str()) {
                if !desk.is_empty() {
                    slot["desktopId"] = json!(desk);
                }
            }
            if !sink.is_empty() {
                slot["sink"] = json!(sink);
                slot["sinkLabel"] = json!(label_for_sink(&sink, profiles));
                slot["channel"] = json!(ch.clone().unwrap_or_default());
                slot["inMix"] = json!(ch.is_some());
            }
            by_key.insert(k, slot);
        }
    }
    for mut a in playing {
        let k = a.get("key").and_then(|v| v.as_str()).unwrap_or("").to_string();
        if k.is_empty() || is_skipped_app(&k) {
            continue;
        }
        if let Some(prev) = by_key.get(&k) {
            if prev.get("desktopId").is_some() && a.get("desktopId").is_none() {
                a["desktopId"] = prev["desktopId"].clone();
            }
            if prev
                .get("sink")
                .and_then(|v| v.as_str())
                .filter(|s| !s.is_empty())
                .is_some()
                && !a.get("inMix").and_then(|v| v.as_bool()).unwrap_or(false)
            {
                a["sink"] = prev["sink"].clone();
                a["sinkLabel"] = prev.get("sinkLabel").cloned().unwrap_or_else(|| {
                    json!(label_for_sink(
                        prev["sink"].as_str().unwrap_or(""),
                        profiles
                    ))
                });
                a["channel"] = prev.get("channel").cloned().unwrap_or(json!(""));
                a["inMix"] = json!(prev
                    .get("channel")
                    .and_then(|v| v.as_str())
                    .filter(|s| !s.is_empty())
                    .is_some());
            }
        }
        by_key.insert(k, a);
    }
    let mut apps: Vec<Value> = by_key.into_values().collect();
    apps.sort_by(|a, b| {
        let ap = a.get("playing").and_then(|v| v.as_bool()).unwrap_or(false);
        let bp = b.get("playing").and_then(|v| v.as_bool()).unwrap_or(false);
        (!ap).cmp(&(!bp)).then_with(|| {
            let an = a
                .get("name")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_lowercase();
            let bn = b
                .get("name")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_lowercase();
            an.cmp(&bn)
        })
    });
    apps
}

fn module_has_media(cache: &mut Cache, media: &str) -> bool {
    cache.modules_short().contains(media)
}

fn find_route_sink_input(cache: &mut Cache, media: &str) -> Option<(i64, bool)> {
    let out = cache.sink_inputs_raw();
    let needle = format!("media.name = \"{media}\"");
    for block in split_sink_inputs(&out) {
        if !block.contains(&needle) {
            continue;
        }
        let muted = block.to_lowercase().contains("mute: yes");
        return Some((first_percent(&block), muted));
    }
    None
}

fn live_cell(
    cache: &mut Cache,
    channel: &str,
    mix_id: &str,
    saved: &Value,
    profiles: &Value,
) -> Value {
    let mut cell = normalize_cell(saved);
    let media = route_media(channel, mix_id, profiles);
    let present = module_has_media(cache, &media);
    cell["on"] = json!(present);
    if present {
        if let Some((vol, muted)) = find_route_sink_input(cache, &media) {
            cell["volume"] = json!(vol);
            cell["muted"] = json!(muted);
        }
    }
    cell
}

fn source_descriptions(cache: &mut Cache) -> std::collections::HashMap<String, String> {
    let mut descs = std::collections::HashMap::new();
    let mut name = String::new();
    for line in cache.sources_full().lines() {
        let s = line.trim();
        if let Some(rest) = s.strip_prefix("Name:") {
            name = rest.trim().to_string();
        } else if let Some(rest) = s.strip_prefix("Description:") {
            if !name.is_empty() {
                descs.insert(name.clone(), rest.trim().to_string());
                name.clear();
            }
        }
    }
    descs
}

fn list_available_sources(cache: &mut Cache, profiles: &Value) -> Vec<Value> {
    let used: HashSet<String> = input_rows(profiles)
        .into_iter()
        .filter_map(|(_, _, _, src)| if src.is_empty() { None } else { Some(src) })
        .collect();
    let descs = source_descriptions(cache);
    let mut out = Vec::new();
    for s in cache.short_sources() {
        let name = s.name;
        if name.is_empty()
            || name.ends_with(".monitor")
            || name.starts_with("proteus_")
            || used.contains(&name)
        {
            continue;
        }
        let label = descs
            .get(&name)
            .cloned()
            .unwrap_or_else(|| label_for_sink(&name, profiles));
        out.push(json!({"id": name, "label": label, "name": name}));
    }
    out.sort_by(|a, b| {
        let al = a
            .get("label")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_lowercase();
        let bl = b
            .get("label")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_lowercase();
        al.cmp(&bl)
    });
    out
}

pub fn dump(cache: &mut Cache) -> Value {
    if !Cache::which("pactl") {
        return json!({
            "ok": false,
            "error": "pactl not found",
            "channels": [],
            "mixes": [],
            "apps": [],
            "inputs": [],
            "unassigned": [],
            "assignOptions": [],
            "availableSources": [],
        });
    }
    cache.invalidate();
    let sinks = cache.short_sinks();
    let profiles = load_profiles();
    let playing = list_playing(cache, &sinks, &profiles);
    apply_profiles(cache, &playing, &profiles, &sinks);
    cache.invalidate();
    let sinks = cache.short_sinks();
    let playing = list_playing(cache, &sinks, &profiles);
    let apps = merge_apps(playing, &profiles);
    let saved_routes = profiles.get("routes").cloned().unwrap_or(json!({}));

    let mut mixes = Vec::new();
    for (mid, sink, lab, hear) in mix_rows(&profiles) {
        let present = cache.sink_exists(&sink);
        let (vol, muted) = if present {
            cache.sink_volume_mute(&sink)
        } else {
            (100, false)
        };
        mixes.push(json!({
            "id": mid,
            "sink": sink,
            "label": lab,
            "hear": hear,
            "present": present,
            "volume": vol,
            "muted": muted,
        }));
    }

    let rows = channel_rows(&profiles);
    let mut channels = Vec::new();
    for (sid, lab, short) in &rows {
        let present = cache.sink_exists(sid);
        let (vol, muted) = if present {
            cache.sink_volume_mute(sid)
        } else {
            (100, false)
        };
        let members: Vec<&Value> = apps
            .iter()
            .filter(|a| {
                a.get("channel").and_then(|v| v.as_str()) == Some(sid.as_str())
                    || a.get("sink").and_then(|v| v.as_str()) == Some(sid.as_str())
            })
            .collect();
        let prof_apps = profiles.get("apps").cloned().unwrap_or(json!({}));
        let mut folder = Vec::new();
        let mut seen_keys = HashSet::new();
        for a in members {
            let k = a.get("key").and_then(|v| v.as_str()).unwrap_or("");
            if k.is_empty() || !seen_keys.insert(k.to_string()) {
                continue;
            }
            let desk = prof_apps
                .get(k)
                .and_then(|p| p.get("desktopId"))
                .and_then(|v| v.as_str())
                .unwrap_or("");
            folder.push(json!({
                "key": k,
                "name": a.get("name").and_then(|v| v.as_str()).unwrap_or(k),
                "playing": a.get("playing").and_then(|v| v.as_bool()).unwrap_or(false),
                "desktopId": desk,
                "streamId": a.get("id").and_then(|v| v.as_str()).unwrap_or(""),
            }));
        }
        let slot = saved_routes.get(sid).cloned().unwrap_or(json!({}));
        let mut cells = serde_json::Map::new();
        for (mid, _, _, _) in mix_rows(&profiles) {
            let raw = slot.get(&mid).cloned().unwrap_or(Value::Bool(true));
            cells.insert(mid.clone(), live_cell(cache, sid, &mid, &raw, &profiles));
        }
        let routes: serde_json::Map<String, Value> = cells
            .iter()
            .map(|(mid, cell)| {
                (
                    mid.clone(),
                    json!(cell.get("on").and_then(|v| v.as_bool()).unwrap_or(false)),
                )
            })
            .collect();
        let count = folder.len();
        channels.push(json!({
            "id": sid,
            "label": lab,
            "short": short,
            "kind": "channel",
            "present": present,
            "volume": vol,
            "muted": muted,
            "apps": folder,
            "count": count,
            "cells": cells,
            "routes": routes,
        }));
    }

    let src_descs = source_descriptions(cache);
    let mut inputs = Vec::new();
    for (sid, lab, short, source) in input_rows(&profiles) {
        let present = cache.sink_exists(&sid) && !source.is_empty() && cache.source_exists(&source);
        let (vol, muted) = if cache.sink_exists(&sid) {
            cache.sink_volume_mute(&sid)
        } else {
            (100, false)
        };
        let slot = saved_routes.get(&sid).cloned().unwrap_or(json!({}));
        let mut cells = serde_json::Map::new();
        for (mid, _, _, _) in mix_rows(&profiles) {
            let raw = slot.get(&mid).cloned().unwrap_or(Value::Bool(true));
            cells.insert(mid.clone(), live_cell(cache, &sid, &mid, &raw, &profiles));
        }
        let routes: serde_json::Map<String, Value> = cells
            .iter()
            .map(|(mid, cell)| {
                (
                    mid.clone(),
                    json!(cell.get("on").and_then(|v| v.as_bool()).unwrap_or(false)),
                )
            })
            .collect();
        let source_label = src_descs
            .get(&source)
            .cloned()
            .unwrap_or_else(|| label_for_sink(&source, &profiles));
        inputs.push(json!({
            "id": sid,
            "label": lab,
            "short": short,
            "kind": "input",
            "source": source,
            "sourceLabel": source_label,
            "present": present,
            "volume": vol,
            "muted": muted,
            "apps": [],
            "count": 0,
            "cells": cells,
            "routes": routes,
        }));
    }

    let mut unassigned: Vec<Value> = apps
        .iter()
        .filter(|a| !a.get("inMix").and_then(|v| v.as_bool()).unwrap_or(false))
        .cloned()
        .collect();
    let first_ch = rows
        .first()
        .map(|(id, _, _)| id.clone())
        .unwrap_or_default();
    for a in &mut unassigned {
        if a.get("sink")
            .and_then(|v| v.as_str())
            .filter(|s| !s.is_empty())
            .is_none()
        {
            let name = a.get("name").and_then(|v| v.as_str()).unwrap_or("");
            let suggested = hint_channel(name, &profiles);
            a["suggested"] = json!(if suggested.is_empty() {
                first_ch.clone()
            } else {
                suggested
            });
        }
    }

    let mut assign = Vec::new();
    for (sid, lab, _) in &rows {
        assign.push(json!({
            "id": sid,
            "label": lab,
            "kind": "mix",
            "present": cache.sink_exists(sid),
        }));
    }
    let default = cache.default_sink();
    if !default.is_empty() {
        assign.push(json!({
            "id": default,
            "label": "Speakers",
            "kind": "device",
            "present": true,
        }));
    }

    let mut listening = "system".to_string();
    for m in &mixes {
        if m.get("hear").and_then(|v| v.as_bool()).unwrap_or(false) {
            listening = m
                .get("id")
                .and_then(|v| v.as_str())
                .unwrap_or("system")
                .to_string();
            break;
        }
    }

    json!({
        "ok": true,
        "error": "",
        "listening": listening,
        "mixes": mixes,
        "channels": channels,
        "inputs": inputs,
        "availableSources": list_available_sources(cache, &profiles),
        "apps": apps,
        "unassigned": unassigned,
        "assignOptions": assign,
        "defaultSink": default,
        "profilePath": profile_path().display().to_string(),
    })
}
