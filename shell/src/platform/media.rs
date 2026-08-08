use std::process::Command;

use serde::Serialize;

#[derive(Debug, Clone, Default, Serialize)]
pub struct MprisPlayer {
    pub name: String,
    pub title: String,
    pub artist: String,
    pub playing: bool,
}

pub fn mpris_players() -> Vec<MprisPlayer> {
    let out = Command::new("busctl").args(["--user", "list"]).output();
    let Ok(out) = out else {
        return Vec::new();
    };
    let text = String::from_utf8_lossy(&out.stdout);
    text.lines()
        .filter(|l| l.contains("org.mpris.MediaPlayer2."))
        .filter_map(|l| {
            let name = l.split_whitespace().next()?.to_string();
            let (title, artist, playing) = mpris_metadata(&name);
            Some(MprisPlayer {
                name,
                title,
                artist,
                playing,
            })
        })
        .collect()
}

/// Transport command (`PlayPause` / `Next` / `Previous`) to an MPRIS player.
pub fn mpris_control(bus: &str, method: &str) -> Result<(), String> {
    let ok = Command::new("busctl")
        .args([
            "--user",
            "call",
            bus,
            "/org/mpris/MediaPlayer2",
            "org.mpris.MediaPlayer2.Player",
            method,
        ])
        .status()
        .map(|s| s.success())
        .unwrap_or(false);
    if ok {
        Ok(())
    } else {
        Err(format!("mpris {method} failed for {bus}"))
    }
}

fn mpris_metadata(bus: &str) -> (String, String, bool) {
    let meta = Command::new("busctl")
        .args([
            "--user",
            "get-property",
            bus,
            "/org/mpris/MediaPlayer2",
            "org.mpris.MediaPlayer2.Player",
            "Metadata",
        ])
        .output()
        .ok();
    let playing = Command::new("busctl")
        .args([
            "--user",
            "get-property",
            bus,
            "/org/mpris/MediaPlayer2",
            "org.mpris.MediaPlayer2.Player",
            "PlaybackStatus",
        ])
        .output()
        .ok()
        .and_then(|o| {
            let t = String::from_utf8_lossy(&o.stdout);
            Some(t.contains("Playing"))
        })
        .unwrap_or(false);
    let text = meta
        .map(|o| String::from_utf8_lossy(&o.stdout).to_string())
        .unwrap_or_default();
    let title = extract_mpris_str(&text, "xesam:title").unwrap_or_default();
    let artist = extract_mpris_str(&text, "xesam:artist").unwrap_or_default();
    (title, artist, playing)
}

fn extract_mpris_str(blob: &str, key: &str) -> Option<String> {
    let idx = blob.find(key)?;
    let rest = &blob[idx..];
    let q1 = rest.find('"')? + 1;
    let q2 = rest[q1..].find('"')? + q1;
    Some(rest[q1..q2].to_string())
}

pub fn audio_mix_available() -> bool {
    Command::new("sh")
        .args(["-c", "command -v proteus-audio-mix"])
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}
