#!/usr/bin/env python3
"""Wave Link–style mixer for Proteus Sound.

Channels (rows) are user-managed folders (default: Apps / Voice / Music /
Browser / Game). Mixes (columns): Monitor / Stream.

Each channel→mix cell is a module-loopback with its own volume/mute
(media.name = proteus_route_<short>_<mix>). Profiles: ~/.config/proteus/audio-mix.json

Usage:
  audio-mix.py dump
  audio-mix.py ensure
  audio-mix.py add-channel <label>
  audio-mix.py remove-channel <channel-sink>
  audio-mix.py rename-channel <channel-sink> <label>
  audio-mix.py add-mix <label> [--hear]
  audio-mix.py remove-mix <mix-id>
  audio-mix.py rename-mix <mix-id> <label>
  audio-mix.py listen <mix-id|system>
  audio-mix.py add-input <source-name> [--label NAME]
  audio-mix.py remove-input <input-id>
  audio-mix.py rename-input <input-id> <label>
  audio-mix.py move-channel <channel-sink> <index>
  audio-mix.py move-mix <mix-id> <index>
  audio-mix.py move-input <input-id> <index>
  audio-mix.py assign <app-key> <channel-sink> [--stream-id ID] [--label NAME] [--desktop-id ID]
  audio-mix.py unassign <app-key>
  audio-mix.py route <channel-sink> <mix-id> <on|off>
  audio-mix.py volume <channel-sink> <0-150>
  audio-mix.py mute <channel-sink> <0|1>
  audio-mix.py cell-volume <channel-sink> <mix-id> <0-150>
  audio-mix.py cell-mute <channel-sink> <mix-id> <0|1>
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

DEFAULT_CHANNELS = [
    ("proteus_mix_system", "Apps", "system"),
    ("proteus_mix_voice", "Voice", "voice"),
    ("proteus_mix_music", "Music", "music"),
    ("proteus_mix_browser", "Browser", "browser"),
    ("proteus_mix_game", "Game", "game"),
]

# id, sink, label, hear (loopback bus → default speakers)
DEFAULT_MIXES = [
    ("monitor", "proteus_bus_monitor", "Monitor", True),
    ("stream", "proteus_bus_stream", "Stream", False),
]

PROFILE_PATH = Path(os.environ.get("HOME", "")) / ".config" / "proteus" / "audio-mix.json"

SKIP_APP_NAMES = {
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
}

DEFAULT_CHANNEL_HINTS = [
    (re.compile(r"discord|zoom|teams|slack|signal|element|mumble", re.I), "proteus_mix_voice"),
    (re.compile(r"spotify|rhythmbox|vlc|mpv|clementine|strawberry|amberol", re.I), "proteus_mix_music"),
    (re.compile(r"firefox|chrome|chromium|brave|zen|edge|vivaldi|librewolf", re.I), "proteus_mix_browser"),
    (re.compile(r"steam|lutris|heroic|wine|gamescope|minecraft|proton", re.I), "proteus_mix_game"),
]


def run(args: list[str]) -> tuple[int, str, str]:
    try:
        r = subprocess.run(args, capture_output=True, text=True, check=False)
    except FileNotFoundError:
        return 127, "", "not found"
    return r.returncode, r.stdout or "", r.stderr or ""


def app_key(name: str) -> str:
    return re.sub(r"\s+", " ", (name or "").strip()).lower()


def display_name(name: str) -> str:
    return (name or "").strip().replace("\\s", " ") or "App"


def is_skipped_app(name: str) -> bool:
    k = app_key(name)
    if k in SKIP_APP_NAMES:
        return True
    if "\\" in (name or "") or k.startswith("pipewire alsa"):
        return True
    if "loopback" in k:
        return True
    return False


def short_sinks() -> list[dict]:
    code, out, _ = run(["pactl", "list", "short", "sinks"])
    if code != 0:
        return []
    sinks = []
    for line in out.splitlines():
        parts = line.split("\t")
        if len(parts) < 2:
            continue
        sinks.append({"id": parts[0], "name": parts[1]})
    return sinks


def sink_exists(name: str, sinks: list[dict] | None = None) -> bool:
    sinks = sinks if sinks is not None else short_sinks()
    return any(s["name"] == name for s in sinks)


def default_channel_dicts() -> list[dict]:
    return [{"id": a, "label": b, "short": c} for a, b, c in DEFAULT_CHANNELS]


def slugify_channel(label: str) -> str:
    s = re.sub(r"[^a-z0-9]+", "_", (label or "").strip().lower()).strip("_")
    return (s[:24] or "channel")


def normalize_channel_entry(raw) -> dict | None:
    if not isinstance(raw, dict):
        return None
    short = slugify_channel(str(raw.get("short") or raw.get("id") or raw.get("label") or ""))
    if short.startswith("proteus_mix_"):
        short = short[len("proteus_mix_") :]
    short = slugify_channel(short)
    if not short:
        return None
    lab = display_name(str(raw.get("label") or short.replace("_", " ").title()))[:40]
    entry_id = f"proteus_mix_{short}"
    # Stock rename: listen target is "Speakers"; default channel is "Apps".
    if entry_id == "proteus_mix_system" and lab == "System":
        lab = "Apps"
    return {"id": entry_id, "label": lab or short.title(), "short": short}


def normalize_channels_list(raw) -> list[dict]:
    """Normalize a channels array (may be empty if the user deleted all)."""
    if not isinstance(raw, list):
        return default_channel_dicts()
    out: list[dict] = []
    seen: set[str] = set()
    for item in raw:
        c = normalize_channel_entry(item)
        if not c or c["id"] in seen:
            continue
        seen.add(c["id"])
        out.append(c)
    return out


def channel_rows(profiles: dict | None = None) -> list[tuple[str, str, str]]:
    p = profiles if profiles is not None else load_profiles()
    rows = []
    for c in p.get("channels") or []:
        if isinstance(c, dict) and c.get("id"):
            rows.append((str(c["id"]), str(c.get("label") or c["id"]), str(c.get("short") or "")))
    return rows


def channel_meta(name: str, profiles: dict | None = None) -> tuple[str, str, str] | None:
    for sid, lab, short in channel_rows(profiles):
        if name == sid:
            return sid, lab, short
    return None


def input_rows(profiles: dict | None = None) -> list[tuple[str, str, str, str]]:
    """(id, label, short, source-name) for mic/line strips."""
    p = profiles if profiles is not None else load_profiles()
    rows = []
    for c in p.get("inputs") or []:
        if not isinstance(c, dict) or not c.get("id"):
            continue
        sid = str(c["id"])
        lab = str(c.get("label") or sid)
        short = str(c.get("short") or sid.replace("proteus_in_", ""))
        source = str(c.get("source") or "")
        rows.append((sid, lab, short, source))
    return rows


def input_meta(name: str, profiles: dict | None = None) -> tuple[str, str, str, str] | None:
    for sid, lab, short, source in input_rows(profiles):
        if name == sid:
            return sid, lab, short, source
    return None


def strip_meta(name: str, profiles: dict | None = None) -> tuple[str, str, str] | None:
    """App channel or input strip id/label/short for routing helpers."""
    m = channel_meta(name, profiles)
    if m:
        return m
    inn = input_meta(name, profiles)
    if inn:
        return inn[0], inn[1], inn[2]
    return None


def channel_for_sink(name: str, profiles: dict | None = None) -> str | None:
    m = strip_meta(name, profiles)
    return m[0] if m else None


def label_for_sink(name: str, profiles: dict | None = None) -> str:
    m = strip_meta(name, profiles)
    if m:
        return m[1]
    for mid, sink, lab, _hear in mix_rows(profiles):
        if name == sink:
            return lab
    if not name:
        return "—"
    tail = name.split(".")[-1] if "." in name else name
    tail = re.sub(r"__+", " ", tail).replace("-", " ").replace("_", " ")
    return re.sub(r"\s+", " ", tail).strip()[:42] or name


def default_mix_dicts() -> list[dict]:
    return [
        {"id": i, "sink": s, "label": l, "hear": h}
        for i, s, l, h in DEFAULT_MIXES
    ]


def normalize_mix_entry(raw) -> dict | None:
    if not isinstance(raw, dict):
        return None
    mid = slugify_channel(str(raw.get("id") or raw.get("short") or raw.get("label") or ""))
    if mid.startswith("proteus_bus_"):
        mid = mid[len("proteus_bus_") :]
    mid = slugify_channel(mid)
    if not mid:
        return None
    lab = display_name(str(raw.get("label") or mid.replace("_", " ").title()))[:40]
    sink = str(raw.get("sink") or f"proteus_bus_{mid}")
    if not sink.startswith("proteus_bus_"):
        sink = f"proteus_bus_{mid}"
    hear = bool(raw.get("hear")) if "hear" in raw else (mid == "monitor")
    return {"id": mid, "sink": sink, "label": lab or mid.title(), "hear": hear}


def normalize_mixes_list(raw) -> list[dict]:
    if not isinstance(raw, list):
        return default_mix_dicts()
    out: list[dict] = []
    seen: set[str] = set()
    for item in raw:
        m = normalize_mix_entry(item)
        if not m or m["id"] in seen:
            continue
        seen.add(m["id"])
        out.append(m)
    return out


def mix_rows(profiles: dict | None = None) -> list[tuple[str, str, str, bool]]:
    p = profiles if profiles is not None else load_profiles()
    rows = []
    for m in p.get("mixes") or []:
        if isinstance(m, dict) and m.get("id"):
            rows.append(
                (
                    str(m["id"]),
                    str(m.get("sink") or f"proteus_bus_{m['id']}"),
                    str(m.get("label") or m["id"]),
                    bool(m.get("hear")),
                )
            )
    return rows


def resolve_mix(mix_id: str, profiles: dict | None = None) -> tuple[str, str, str, bool] | None:
    for mid, sink, lab, hear in mix_rows(profiles):
        if mid == mix_id:
            return mid, sink, lab, hear
    return None


def empty_route_slot(profiles: dict | None = None) -> dict:
    return {mid: default_cell() for mid, _, _, _ in mix_rows(profiles)}


def hear_media(mix_id: str) -> str:
    return f"proteus_hear_{mix_id}"


def route_media(channel: str, mix_id: str, profiles: dict | None = None) -> str:
    meta = strip_meta(channel, profiles)
    if meta:
        short = slugify_channel(meta[2])
    elif channel.startswith("proteus_in_"):
        short = slugify_channel(channel.replace("proteus_in_", ""))
    else:
        short = slugify_channel(channel.replace("proteus_mix_", ""))
    if channel.startswith("proteus_in_"):
        return f"proteus_inroute_{short}_{mix_id}"
    return f"proteus_route_{short}_{mix_id}"


def capture_media(short: str) -> str:
    return f"proteus_incapture_{slugify_channel(short)}"


def normalize_input_entry(raw) -> dict | None:
    if not isinstance(raw, dict):
        return None
    source = str(raw.get("source") or "").strip()
    if not source or source.endswith(".monitor"):
        return None
    if source.startswith("proteus_"):
        return None
    short = slugify_channel(str(raw.get("short") or raw.get("id") or raw.get("label") or source.split(".")[-1]))
    if short.startswith("proteus_in_"):
        short = short[len("proteus_in_") :]
    short = slugify_channel(short)
    if not short:
        return None
    lab = display_name(str(raw.get("label") or short.replace("_", " ").title()))[:48]
    return {
        "id": f"proteus_in_{short}",
        "label": lab or short.title(),
        "short": short,
        "source": source,
    }


def normalize_inputs_list(raw) -> list[dict]:
    if not isinstance(raw, list):
        return []
    out: list[dict] = []
    seen: set[str] = set()
    seen_src: set[str] = set()
    for item in raw:
        c = normalize_input_entry(item)
        if not c or c["id"] in seen or c["source"] in seen_src:
            continue
        seen.add(c["id"])
        seen_src.add(c["source"])
        out.append(c)
    return out


def default_cell() -> dict:
    return {"on": True, "volume": 100, "muted": False}


def normalize_cell(raw) -> dict:
    cell = default_cell()
    if isinstance(raw, bool):
        cell["on"] = raw
        return cell
    if isinstance(raw, dict):
        if "on" in raw:
            cell["on"] = bool(raw["on"])
        elif "enabled" in raw:
            cell["on"] = bool(raw["enabled"])
        if "volume" in raw:
            try:
                cell["volume"] = max(0, min(150, int(raw["volume"])))
            except Exception:
                pass
        if "muted" in raw:
            cell["muted"] = bool(raw["muted"])
    return cell


def load_profiles() -> dict:
    empty = {
        "apps": {},
        "routes": {},
        "channels": default_channel_dicts(),
        "mixes": default_mix_dicts(),
        "inputs": [],
    }
    if not PROFILE_PATH.is_file():
        return empty
    try:
        data = json.loads(PROFILE_PATH.read_text(encoding="utf-8"))
    except Exception:
        return empty
    if not isinstance(data, dict):
        return empty
    apps = data.get("apps") if isinstance(data.get("apps"), dict) else {}
    # Missing key → seed defaults; present [] → user cleared all.
    if "channels" not in data:
        channels = default_channel_dicts()
    else:
        channels = normalize_channels_list(data.get("channels"))
    if "mixes" not in data:
        mixes = default_mix_dicts()
    else:
        mixes = normalize_mixes_list(data.get("mixes"))
    inputs = normalize_inputs_list(data.get("inputs")) if "inputs" in data else []
    routes_in = data.get("routes") if isinstance(data.get("routes"), dict) else {}
    routes: dict = {}
    mix_ids = [m["id"] for m in mixes]
    for ch in channels + inputs:
        sid = ch["id"]
        slot_in = routes_in.get(sid) if isinstance(routes_in.get(sid), dict) else {}
        slot = {}
        for mid in mix_ids:
            slot[mid] = normalize_cell(slot_in.get(mid, True))
        routes[sid] = slot
    return {
        "apps": apps,
        "routes": routes,
        "channels": channels,
        "mixes": mixes,
        "inputs": inputs,
    }


def save_profiles(data: dict) -> None:
    PROFILE_PATH.parent.mkdir(parents=True, exist_ok=True)
    tmp = PROFILE_PATH.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    tmp.replace(PROFILE_PATH)


def hint_channel(name: str, profiles: dict | None = None) -> str:
    ids = {sid for sid, _, _ in channel_rows(profiles)}
    for rx, ch in DEFAULT_CHANNEL_HINTS:
        if ch in ids and rx.search(name or ""):
            return ch
    return ""


def known_from_wireplumber() -> list[str]:
    path = Path(os.environ.get("HOME", "")) / ".local/state/wireplumber/stream-properties"
    if not path.is_file():
        return []
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except Exception:
        return []
    names: list[str] = []
    seen: set[str] = set()
    for m in re.finditer(r"Output/Audio:application\.name:([^=]+)=", text):
        raw = display_name(m.group(1))
        k = app_key(raw)
        if is_skipped_app(raw) or k in seen:
            continue
        seen.add(k)
        names.append(raw)
    return names


def list_playing(sinks: list[dict]) -> list[dict]:
    code, out, _ = run(["pactl", "list", "sink-inputs"])
    if code != 0:
        return []
    by_id = {s["id"]: s["name"] for s in sinks}
    apps = []
    for block in re.split(r"\n(?=Sink Input #)", out):
        id_m = re.search(r"Sink Input #(\d+)", block)
        if not id_m:
            continue
        sink_m = re.search(r"^\s*Sink:\s*(\d+)\s*$", block, re.M)
        vol_m = re.search(r"Volume:[^\n]*?(\d+)%", block)
        app_m = re.search(r'application\.name\s*=\s*"([^"]*)"', block)
        bin_m = re.search(r'application\.process\.binary\s*=\s*"([^"]*)"', block)
        media_m = re.search(r'media\.name\s*=\s*"([^"]*)"', block)
        media_name = media_m.group(1) if media_m else ""
        app_name = app_m.group(1) if app_m else ""
        if media_name.startswith("proteus_loop_") or media_name.startswith("proteus_bus_"):
            continue
        if media_name.startswith("proteus_route_") or media_name.startswith("proteus_inroute_"):
            continue
        if media_name.startswith("proteus_incapture_") or media_name.startswith("proteus_hear_"):
            continue
        if "node.group = \"loopback-" in block or "node.link-group = \"loopback-" in block:
            continue
        bin_name = bin_m.group(1) if bin_m else ""
        if "loopback" in bin_name.lower() or app_name in ("Loopback", "module-loopback"):
            continue
        name = display_name(app_name or bin_name or "")
        if not name or is_skipped_app(name):
            continue
        detail = ""
        if media_name and media_name != name and not media_name.startswith("loopback"):
            detail = media_name
        elif bin_name and bin_name != name:
            detail = bin_name
        sink_id = sink_m.group(1) if sink_m else ""
        sink_name = by_id.get(sink_id, "")
        ch = channel_for_sink(sink_name) if sink_name else None
        apps.append(
            {
                "id": id_m.group(1),
                "key": app_key(name),
                "name": name,
                "detail": detail,
                "volume": int(vol_m.group(1)) if vol_m else 100,
                "muted": bool(re.search(r"Mute:\s*yes", block, re.I)),
                "sink": sink_name,
                "sinkLabel": label_for_sink(sink_name) if sink_name else "—",
                "channel": ch or "",
                "inMix": bool(ch),
                "playing": True,
            }
        )
    return apps


def sink_volume_mute(name: str) -> tuple[int, bool]:
    code, out, _ = run(["pactl", "get-sink-volume", name])
    vol = 100
    if code == 0:
        m = re.search(r"(\d+)%", out or "")
        if m:
            vol = int(m.group(1))
    code2, out2, _ = run(["pactl", "get-sink-mute", name])
    muted = code2 == 0 and "yes" in (out2 or "").lower()
    return vol, muted


def modules_short() -> str:
    _, out, _ = run(["pactl", "list", "short", "modules"])
    if out.strip():
        return out
    _, out2, _ = run(["pactl", "list", "modules", "short"])
    return out2


def unload_module_id(mid: str) -> None:
    if mid.isdigit():
        run(["pactl", "unload-module", mid])


def unload_legacy_channel_to_default() -> None:
    """Remove old proteus_loop_* channel→default helpers (not route cells)."""
    text = modules_short()
    for line in text.splitlines():
        if "proteus_loop_" not in line:
            continue
        if (
            "proteus_route_" in line
            or "proteus_inroute_" in line
            or "proteus_incapture_" in line
            or "proteus_hear_" in line
            or "proteus_bus_monitor_hear" in line
        ):
            continue
        mid = line.split("\t")[0].split()[0] if line.strip() else ""
        unload_module_id(mid)


def unlink_direct_pw_routes(profiles: dict | None = None) -> None:
    """Drop prior pw-link channel→bus edges (replaced by route loopbacks)."""
    for ch, _, _ in channel_rows(profiles):
        for _, bus, _, _ in mix_rows(profiles):
            for side in ("FL", "FR", "MONO"):
                run(["pw-link", "-d", f"{ch}:monitor_{side}", f"{bus}:playback_{side}"])


def ensure_null_sink(name: str) -> bool:
    if sink_exists(name):
        return True
    code, _, _ = run(["pactl", "load-module", "module-null-sink", f"sink_name={name}"])
    return code == 0 and sink_exists(name)


def short_sources() -> list[dict]:
    code, out, _ = run(["pactl", "list", "short", "sources"])
    if code != 0:
        return []
    srcs = []
    for line in out.splitlines():
        parts = line.split("\t")
        if len(parts) < 2:
            continue
        srcs.append({"id": parts[0], "name": parts[1]})
    return srcs


def source_exists(name: str) -> bool:
    return any(s["name"] == name for s in short_sources())


def source_descriptions() -> dict[str, str]:
    code, out, _ = run(["pactl", "list", "sources"])
    if code != 0:
        return {}
    descs: dict[str, str] = {}
    name = ""
    for line in (out or "").splitlines():
        s = line.strip()
        if s.startswith("Name:"):
            name = s.split(":", 1)[1].strip()
        elif s.startswith("Description:") and name:
            descs[name] = s.split(":", 1)[1].strip()
            name = ""
    return descs


def list_available_sources(profiles: dict | None = None) -> list[dict]:
    """Hardware/capture sources not already added as mixer inputs."""
    used = {src for _i, _l, _s, src in input_rows(profiles) if src}
    descs = source_descriptions()
    out = []
    for s in short_sources():
        name = s["name"]
        if not name or name.endswith(".monitor"):
            continue
        if name.startswith("proteus_"):
            continue
        if name in used:
            continue
        label = descs.get(name) or label_for_sink(name)
        out.append({"id": name, "label": label, "name": name})
    out.sort(key=lambda x: (x.get("label") or "").lower())
    return out


def ensure_capture(source: str, sink_id: str, short: str) -> bool:
    """Loop hardware source → input null-sink (mixer gain stage)."""
    if not source or not sink_id:
        return False
    media = capture_media(short)
    if module_has_media(media):
        return True
    if not source_exists(source):
        return False
    if not ensure_null_sink(sink_id):
        return False
    code, _, _ = run(
        [
            "pactl",
            "load-module",
            "module-loopback",
            f"source={source}",
            f"sink={sink_id}",
            "sink_dont_move=true",
            "source_dont_move=true",
            f"media.name={media}",
        ]
    )
    return code == 0 and module_has_media(media)


def unload_capture(short: str) -> None:
    mid = find_route_module(capture_media(short))
    if mid:
        unload_module_id(mid)


def unload_null_sink(name: str) -> None:
    """Unload the module-null-sink that owns this sink name."""
    needle = f"sink_name={name}"
    for line in modules_short().splitlines():
        if needle not in line or "module-null-sink" not in line:
            continue
        mid = line.split("\t")[0].split()[0] if line.strip() else ""
        unload_module_id(mid)
        return


def module_has_media(media: str) -> bool:
    return media in modules_short()


def find_route_module(media: str) -> str:
    for line in modules_short().splitlines():
        if media in line and "module-loopback" in line:
            return line.split("\t")[0].split()[0]
    return ""


def find_route_sink_input(media: str) -> dict | None:
    code, out, _ = run(["pactl", "list", "sink-inputs"])
    if code != 0:
        return None
    needle = f'media.name = "{media}"'
    for block in re.split(r"\n(?=Sink Input #)", out):
        if needle not in block:
            continue
        id_m = re.search(r"Sink Input #(\d+)", block)
        if not id_m:
            continue
        vol_m = re.search(r"Volume:[^\n]*?(\d+)%", block)
        return {
            "id": id_m.group(1),
            "volume": int(vol_m.group(1)) if vol_m else 100,
            "muted": bool(re.search(r"Mute:\s*yes", block, re.I)),
        }
    return None


def load_route_loopback(channel: str, mix_id: str, bus: str) -> bool:
    media = route_media(channel, mix_id)
    if module_has_media(media):
        return True
    code, _, _ = run(
        [
            "pactl",
            "load-module",
            "module-loopback",
            f"source={channel}.monitor",
            f"sink={bus}",
            "sink_dont_move=true",
            "source_dont_move=true",
            f"media.name={media}",
        ]
    )
    return code == 0 and module_has_media(media)


def unload_route_loopback(channel: str, mix_id: str) -> None:
    media = route_media(channel, mix_id)
    mid = find_route_module(media)
    if mid:
        unload_module_id(mid)


def apply_cell_to_input(channel: str, mix_id: str, cell: dict) -> None:
    if not cell.get("on"):
        return
    media = route_media(channel, mix_id)
    info = find_route_sink_input(media)
    if not info:
        return
    run(["pactl", "set-sink-input-volume", info["id"], f"{int(cell.get('volume', 100))}%"])
    run(["pactl", "set-sink-input-mute", info["id"], "1" if cell.get("muted") else "0"])


def ensure_cell(channel: str, mix_id: str, bus: str, cell: dict) -> None:
    if cell.get("on"):
        if load_route_loopback(channel, mix_id, bus):
            apply_cell_to_input(channel, mix_id, cell)
    else:
        unload_route_loopback(channel, mix_id)


def set_route(channel: str, mix_id: str, on: bool) -> dict:
    profiles = load_profiles()
    resolved = resolve_mix(mix_id, profiles)
    if not resolved or not channel_for_sink(channel, profiles):
        return {"ok": False, "error": "unknown channel or mix"}
    _mid, bus, _lab, _hear = resolved
    routes = profiles.setdefault("routes", {})
    slot = routes.setdefault(channel, empty_route_slot(profiles))
    cell = normalize_cell(slot.get(mix_id))
    cell["on"] = bool(on)
    if on and cell.get("volume", 100) <= 0:
        cell["volume"] = 100
    slot[mix_id] = cell
    save_profiles(profiles)
    ensure_cell(channel, mix_id, bus, cell)
    return {"ok": True, "error": ""}


def set_cell_volume(channel: str, mix_id: str, pct: int) -> dict:
    profiles = load_profiles()
    resolved = resolve_mix(mix_id, profiles)
    if not resolved or not channel_for_sink(channel, profiles):
        return {"ok": False, "error": "unknown channel or mix"}
    _mid, bus, _lab, _hear = resolved
    routes = profiles.setdefault("routes", {})
    slot = routes.setdefault(channel, empty_route_slot(profiles))
    cell = normalize_cell(slot.get(mix_id))
    cell["on"] = True
    cell["volume"] = max(0, min(150, int(pct)))
    slot[mix_id] = cell
    save_profiles(profiles)
    ensure_cell(channel, mix_id, bus, cell)
    return {"ok": True, "error": ""}


def set_cell_mute(channel: str, mix_id: str, muted: bool) -> dict:
    profiles = load_profiles()
    resolved = resolve_mix(mix_id, profiles)
    if not resolved or not channel_for_sink(channel, profiles):
        return {"ok": False, "error": "unknown channel or mix"}
    _mid, bus, _lab, _hear = resolved
    routes = profiles.setdefault("routes", {})
    slot = routes.setdefault(channel, empty_route_slot(profiles))
    cell = normalize_cell(slot.get(mix_id))
    cell["on"] = True
    cell["muted"] = bool(muted)
    slot[mix_id] = cell
    save_profiles(profiles)
    ensure_cell(channel, mix_id, bus, cell)
    return {"ok": True, "error": ""}


def unload_hear(mix_id: str) -> None:
    media = hear_media(mix_id)
    mid = find_route_module(media)
    if mid:
        unload_module_id(mid)
    # Legacy name from earlier mixer builds
    if mix_id == "monitor":
        legacy = find_route_module("proteus_bus_monitor_hear")
        if legacy:
            unload_module_id(legacy)


def ensure_hear(mix_id: str, bus: str, want: bool) -> None:
    media = hear_media(mix_id)
    if want:
        if module_has_media(media) or (
            mix_id == "monitor" and module_has_media("proteus_bus_monitor_hear")
        ):
            return
        if not sink_exists(bus):
            return
        run(
            [
                "pactl",
                "load-module",
                "module-loopback",
                f"source={bus}.monitor",
                "sink=@DEFAULT_SINK@",
                "sink_dont_move=true",
                "source_dont_move=true",
                f"media.name={media}",
            ]
        )
    else:
        unload_hear(mix_id)


def apply_hear_flags(profiles: dict) -> None:
    for mid, bus, _lab, hear in mix_rows(profiles):
        ensure_hear(mid, bus, hear)


def set_listen(mix_id: str) -> dict:
    """Exclusive listen target: a mix bus, or system (no mix → speakers)."""
    if not shutil.which("pactl"):
        return {"ok": False, "error": "pactl not found"}
    target = (mix_id or "").strip().lower()
    to_system = target in ("", "system", "none", "off", "-")
    profiles = load_profiles()
    mixes = profiles.get("mixes") or []
    if not to_system:
        resolved = resolve_mix(mix_id, profiles)
        if not resolved:
            return {"ok": False, "error": "unknown mix"}
        target = resolved[0]
    found = to_system
    for m in mixes:
        if not isinstance(m, dict):
            continue
        on = (not to_system) and m.get("id") == target
        m["hear"] = on
        if on:
            found = True
    if not found:
        return {"ok": False, "error": "unknown mix"}
    save_profiles(profiles)
    apply_hear_flags(profiles)
    return {"ok": True, "id": "system" if to_system else target, "error": ""}


def ensure_channels() -> dict:
    if not shutil.which("pactl"):
        return {"ok": False, "error": "pactl not found"}

    profiles = load_profiles()
    # Persist stock Apps label (was System) when ensure runs.
    for c in profiles.get("channels") or []:
        if isinstance(c, dict) and c.get("id") == "proteus_mix_system" and c.get("label") == "System":
            c["label"] = "Apps"
    unload_legacy_channel_to_default()
    unlink_direct_pw_routes(profiles)
    created: list[str] = []
    errors: list[str] = []

    sinks = (
        [s for _, s, _, _ in mix_rows(profiles)]
        + [s for s, _, _ in channel_rows(profiles)]
        + [s for s, _, _, _ in input_rows(profiles)]
    )
    for sink in sinks:
        if sink_exists(sink):
            continue
        if ensure_null_sink(sink):
            created.append(sink)
        else:
            errors.append(sink)

    apply_hear_flags(profiles)

    for sid, _lab, short, source in input_rows(profiles):
        if source and not ensure_capture(source, sid, short):
            errors.append(sid)

    routes = profiles.setdefault("routes", {})
    routable = [s for s, _, _ in channel_rows(profiles)] + [s for s, _, _, _ in input_rows(profiles)]
    for ch in routable:
        slot = routes.setdefault(ch, empty_route_slot(profiles))
        for mix_id, bus, _lab, _hear in mix_rows(profiles):
            cell = normalize_cell(slot.get(mix_id))
            slot[mix_id] = cell
            ensure_cell(ch, mix_id, bus, cell)
    save_profiles(profiles)

    return {
        "ok": len(errors) == 0,
        "error": ("failed: " + ", ".join(errors)) if errors else "",
        "created": created,
    }


def add_channel(label: str) -> dict:
    if not shutil.which("pactl"):
        return {"ok": False, "error": "pactl not found"}
    lab = display_name(label)[:40]
    if not lab:
        return {"ok": False, "error": "name required"}
    profiles = load_profiles()
    channels = profiles.setdefault("channels", default_channel_dicts())
    base = slugify_channel(lab)
    short = base
    n = 2
    used_short = {str(c.get("short") or "") for c in channels if isinstance(c, dict)}
    used_ids = {str(c.get("id") or "") for c in channels if isinstance(c, dict)}
    while short in used_short or f"proteus_mix_{short}" in used_ids:
        short = f"{base}_{n}"
        n += 1
        if n > 99:
            return {"ok": False, "error": "too many channels with that name"}
    sid = f"proteus_mix_{short}"
    if not ensure_null_sink(sid):
        return {"ok": False, "error": "could not create channel"}
    entry = {"id": sid, "label": lab, "short": short}
    channels.append(entry)
    routes = profiles.setdefault("routes", {})
    slot = empty_route_slot(profiles)
    routes[sid] = slot
    save_profiles(profiles)
    for mix_id, bus, _lab, _hear in mix_rows(profiles):
        ensure_cell(sid, mix_id, bus, slot[mix_id])
    return {"ok": True, "id": sid, "label": lab, "short": short, "error": ""}


def remove_channel(channel: str) -> dict:
    profiles = load_profiles()
    meta = channel_meta(channel, profiles)
    if not meta:
        return {"ok": False, "error": "unknown channel"}
    sid, _, _ = meta
    # Drop app memberships on this channel
    apps = profiles.setdefault("apps", {})
    for key, prof in list(apps.items()):
        if isinstance(prof, dict) and prof.get("sink") == sid:
            del apps[key]
    for mix_id, _, _, _ in mix_rows(profiles):
        unload_route_loopback(sid, mix_id)
    unload_null_sink(sid)
    profiles["channels"] = [
        c for c in (profiles.get("channels") or []) if isinstance(c, dict) and c.get("id") != sid
    ]
    (profiles.get("routes") or {}).pop(sid, None)
    save_profiles(profiles)
    # Playing streams on this sink → default output
    code, out, _ = run(["pactl", "get-default-sink"])
    default = (out or "").strip() if code == 0 else ""
    if default:
        sinks = short_sinks()
        for a in list_playing(sinks):
            if a.get("sink") == sid and a.get("id"):
                run(["pactl", "move-sink-input", str(a["id"]), default])
    return {"ok": True, "id": sid, "error": ""}


def rename_channel(channel: str, label: str) -> dict:
    """Display name only — sink id stays stable for routes / app assign."""
    lab = display_name(label)[:40]
    if not lab:
        return {"ok": False, "error": "name required"}
    profiles = load_profiles()
    meta = channel_meta(channel, profiles)
    if not meta:
        return {"ok": False, "error": "unknown channel"}
    sid, _, _ = meta
    channels = profiles.get("channels") or []
    for c in channels:
        if isinstance(c, dict) and c.get("id") == sid:
            c["label"] = lab
            save_profiles(profiles)
            return {"ok": True, "id": sid, "label": lab, "error": ""}
    return {"ok": False, "error": "unknown channel"}


def add_mix(label: str, hear: bool = False) -> dict:
    if not shutil.which("pactl"):
        return {"ok": False, "error": "pactl not found"}
    lab = display_name(label)[:40]
    if not lab:
        return {"ok": False, "error": "name required"}
    profiles = load_profiles()
    mixes = profiles.setdefault("mixes", default_mix_dicts())
    base = slugify_channel(lab)
    mid = base
    n = 2
    used = {str(m.get("id") or "") for m in mixes if isinstance(m, dict)}
    while mid in used:
        mid = f"{base}_{n}"
        n += 1
        if n > 99:
            return {"ok": False, "error": "too many mixes with that name"}
    bus = f"proteus_bus_{mid}"
    if not ensure_null_sink(bus):
        return {"ok": False, "error": "could not create mix bus"}
    if hear:
        for m in mixes:
            if isinstance(m, dict):
                m["hear"] = False
    entry = {"id": mid, "sink": bus, "label": lab, "hear": bool(hear)}
    mixes.append(entry)
    routes = profiles.setdefault("routes", {})
    routable = [s for s, _, _ in channel_rows(profiles)] + [s for s, _, _, _ in input_rows(profiles)]
    for ch in routable:
        slot = routes.setdefault(ch, {})
        slot[mid] = default_cell()
        ensure_cell(ch, mid, bus, slot[mid])
    save_profiles(profiles)
    apply_hear_flags(profiles)
    return {"ok": True, "id": mid, "label": lab, "sink": bus, "hear": bool(hear), "error": ""}


def remove_mix(mix_id: str) -> dict:
    profiles = load_profiles()
    resolved = resolve_mix(mix_id, profiles)
    if not resolved:
        return {"ok": False, "error": "unknown mix"}
    mid, bus, _lab, _hear = resolved
    routable = [s for s, _, _ in channel_rows(profiles)] + [s for s, _, _, _ in input_rows(profiles)]
    for ch in routable:
        unload_route_loopback(ch, mid)
        slot = (profiles.get("routes") or {}).get(ch)
        if isinstance(slot, dict):
            slot.pop(mid, None)
    unload_hear(mid)
    unload_null_sink(bus)
    profiles["mixes"] = [
        m for m in (profiles.get("mixes") or []) if isinstance(m, dict) and m.get("id") != mid
    ]
    save_profiles(profiles)
    return {"ok": True, "id": mid, "error": ""}


def rename_mix(mix_id: str, label: str) -> dict:
    """Display name only — bus id stays stable for routes / hear."""
    lab = display_name(label)[:40]
    if not lab:
        return {"ok": False, "error": "name required"}
    profiles = load_profiles()
    resolved = resolve_mix(mix_id, profiles)
    if not resolved:
        return {"ok": False, "error": "unknown mix"}
    mid, _bus, _old, _hear = resolved
    for m in profiles.get("mixes") or []:
        if isinstance(m, dict) and m.get("id") == mid:
            m["label"] = lab
            save_profiles(profiles)
            return {"ok": True, "id": mid, "label": lab, "error": ""}
    return {"ok": False, "error": "unknown mix"}


def add_input(source_name: str, label: str = "") -> dict:
    if not shutil.which("pactl"):
        return {"ok": False, "error": "pactl not found"}
    source = (source_name or "").strip()
    if not source or source.endswith(".monitor") or source.startswith("proteus_"):
        return {"ok": False, "error": "invalid source"}
    if not source_exists(source):
        return {"ok": False, "error": "source not found"}
    profiles = load_profiles()
    inputs = profiles.setdefault("inputs", [])
    if any(isinstance(i, dict) and i.get("source") == source for i in inputs):
        return {"ok": False, "error": "source already in mixer"}
    descs = source_descriptions()
    lab = display_name(label or descs.get(source) or source.split(".")[-1])[:48]
    base = slugify_channel(lab)
    short = base
    n = 2
    used = {str(i.get("short") or "") for i in inputs if isinstance(i, dict)}
    used_ids = {str(i.get("id") or "") for i in inputs if isinstance(i, dict)}
    while short in used or f"proteus_in_{short}" in used_ids:
        short = f"{base}_{n}"
        n += 1
        if n > 99:
            return {"ok": False, "error": "too many inputs with that name"}
    sid = f"proteus_in_{short}"
    if not ensure_null_sink(sid):
        return {"ok": False, "error": "could not create input strip"}
    if not ensure_capture(source, sid, short):
        unload_null_sink(sid)
        return {"ok": False, "error": "could not bridge source"}
    entry = {"id": sid, "label": lab, "short": short, "source": source}
    inputs.append(entry)
    routes = profiles.setdefault("routes", {})
    slot = empty_route_slot(profiles)
    routes[sid] = slot
    save_profiles(profiles)
    for mix_id, bus, _lab, _hear in mix_rows(profiles):
        ensure_cell(sid, mix_id, bus, slot[mix_id])
    return {"ok": True, "id": sid, "label": lab, "source": source, "error": ""}


def remove_input(input_id: str) -> dict:
    profiles = load_profiles()
    meta = input_meta(input_id, profiles)
    if not meta:
        return {"ok": False, "error": "unknown input"}
    sid, _lab, short, _source = meta
    for mix_id, _, _, _ in mix_rows(profiles):
        unload_route_loopback(sid, mix_id)
    unload_capture(short)
    unload_null_sink(sid)
    profiles["inputs"] = [
        i for i in (profiles.get("inputs") or []) if isinstance(i, dict) and i.get("id") != sid
    ]
    (profiles.get("routes") or {}).pop(sid, None)
    save_profiles(profiles)
    return {"ok": True, "id": sid, "error": ""}


def rename_input(input_id: str, label: str) -> dict:
    lab = display_name(label)[:48]
    if not lab:
        return {"ok": False, "error": "name required"}
    profiles = load_profiles()
    meta = input_meta(input_id, profiles)
    if not meta:
        return {"ok": False, "error": "unknown input"}
    sid, _old, _short, _src = meta
    for i in profiles.get("inputs") or []:
        if isinstance(i, dict) and i.get("id") == sid:
            i["label"] = lab
            save_profiles(profiles)
            return {"ok": True, "id": sid, "label": lab, "error": ""}
    return {"ok": False, "error": "unknown input"}


def _move_in_list(items: list, item_id: str, to_index: int, pinned_ids: set[str] | None = None) -> tuple[bool, str]:
    pinned_ids = pinned_ids or set()
    if item_id in pinned_ids:
        return False, "pinned"
    ordered = [x for x in items if isinstance(x, dict)]
    by_id = {str(x.get("id") or ""): x for x in ordered}
    if item_id not in by_id:
        return False, "unknown"
    pinned = [x for x in ordered if str(x.get("id") or "") in pinned_ids]
    movable = [x for x in ordered if str(x.get("id") or "") not in pinned_ids]
    item = by_id[item_id]
    rest = [x for x in movable if str(x.get("id") or "") != item_id]
    idx = max(0, min(int(to_index), len(rest)))
    rest.insert(idx, item)
    items[:] = pinned + rest
    return True, ""


def move_channel(channel: str, index: int) -> dict:
    profiles = load_profiles()
    channels = profiles.setdefault("channels", default_channel_dicts())
    ok, err = _move_in_list(channels, channel, index, pinned_ids={"proteus_mix_system"})
    if not ok:
        return {"ok": False, "error": err or "could not move"}
    profiles["channels"] = channels
    save_profiles(profiles)
    return {"ok": True, "id": channel, "index": int(index), "error": ""}


def move_mix(mix_id: str, index: int) -> dict:
    profiles = load_profiles()
    mixes = profiles.setdefault("mixes", default_mix_dicts())
    ok, err = _move_in_list(mixes, mix_id, index, pinned_ids=set())
    if not ok:
        return {"ok": False, "error": err or "could not move"}
    profiles["mixes"] = mixes
    save_profiles(profiles)
    return {"ok": True, "id": mix_id, "index": int(index), "error": ""}


def move_input(input_id: str, index: int) -> dict:
    profiles = load_profiles()
    inputs = profiles.setdefault("inputs", [])
    ok, err = _move_in_list(inputs, input_id, index, pinned_ids=set())
    if not ok:
        return {"ok": False, "error": err or "could not move"}
    profiles["inputs"] = inputs
    save_profiles(profiles)
    return {"ok": True, "id": input_id, "index": int(index), "error": ""}


def apply_profiles(playing: list[dict], profiles: dict, sinks: list[dict]) -> None:
    apps_prof = profiles.get("apps") or {}
    if not isinstance(apps_prof, dict):
        return
    for a in playing:
        want = ""
        for pkey, prof in apps_prof.items():
            if not isinstance(prof, dict):
                continue
            desk = str(prof.get("desktopId") or "")
            if a.get("key") == pkey or _matches_profile_key(a, pkey, desk):
                want = str(prof.get("sink") or "")
                break
        if not want or not sink_exists(want, sinks) or a.get("sink") == want:
            continue
        sid = a.get("id") or ""
        if sid:
            run(["pactl", "move-sink-input", str(sid), want])


def merge_apps(playing: list[dict], profiles: dict) -> list[dict]:
    by_key: dict[str, dict] = {}
    for name in known_from_wireplumber():
        k = app_key(name)
        by_key[k] = {
            "id": "",
            "key": k,
            "name": name,
            "detail": "",
            "volume": 100,
            "muted": False,
            "sink": "",
            "sinkLabel": "—",
            "channel": "",
            "inMix": False,
            "playing": False,
        }
    for key, prof in (profiles.get("apps") or {}).items():
        if not isinstance(prof, dict) or is_skipped_app(str(key)):
            continue
        k = app_key(str(key))
        label = display_name(str(prof.get("label") or key))
        sink = str(prof.get("sink") or "")
        ch = channel_for_sink(sink) if sink else ""
        slot = by_key.get(k) or {
            "id": "",
            "key": k,
            "name": label,
            "detail": "",
            "volume": 100,
            "muted": False,
            "sink": "",
            "sinkLabel": "—",
            "channel": "",
            "inMix": False,
            "playing": False,
        }
        slot["name"] = label or slot["name"]
        desk = str(prof.get("desktopId") or "")
        if desk:
            slot["desktopId"] = desk
        if sink:
            slot["sink"] = sink
            slot["sinkLabel"] = label_for_sink(sink)
            slot["channel"] = ch or ""
            slot["inMix"] = bool(ch)
        by_key[k] = slot
    for a in playing:
        k = a.get("key") or ""
        if k and not is_skipped_app(k):
            prev = by_key.get(k) or {}
            if prev.get("desktopId") and not a.get("desktopId"):
                a["desktopId"] = prev["desktopId"]
            # Prefer profile sink if playing hasn't been moved yet
            if prev.get("sink") and not a.get("inMix"):
                a["sink"] = prev["sink"]
                a["sinkLabel"] = prev.get("sinkLabel") or label_for_sink(prev["sink"])
                a["channel"] = prev.get("channel") or ""
                a["inMix"] = bool(prev.get("channel"))
            by_key[k] = a
    apps = list(by_key.values())
    apps.sort(key=lambda x: (not x.get("playing"), (x.get("name") or "").lower()))
    return apps


def live_cell(channel: str, mix_id: str, saved: dict) -> dict:
    cell = normalize_cell(saved)
    media = route_media(channel, mix_id)
    present = module_has_media(media)
    cell["on"] = present
    if present:
        info = find_route_sink_input(media)
        if info:
            cell["volume"] = info["volume"]
            cell["muted"] = info["muted"]
    return cell


def dump() -> dict:
    if not shutil.which("pactl"):
        return {"ok": False, "error": "pactl not found", "channels": [], "mixes": [], "apps": []}
    sinks = short_sinks()
    profiles = load_profiles()
    playing = list_playing(sinks)
    apply_profiles(playing, profiles, sinks)
    playing = list_playing(sinks)
    apps = merge_apps(playing, profiles)
    saved_routes = profiles.get("routes") or {}

    mixes = []
    for mid, sink, lab, hear in mix_rows(profiles):
        vol, muted = sink_volume_mute(sink) if sink_exists(sink, sinks) else (100, False)
        mixes.append(
            {
                "id": mid,
                "sink": sink,
                "label": lab,
                "hear": hear,
                "present": sink_exists(sink, sinks),
                "volume": vol,
                "muted": muted,
            }
        )

    rows = channel_rows(profiles)
    channels = []
    for sid, lab, short in rows:
        vol, muted = sink_volume_mute(sid) if sink_exists(sid, sinks) else (100, False)
        members = [a for a in apps if a.get("channel") == sid or a.get("sink") == sid]
        # Prefer profile order; enrich with desktopId from profile
        prof_apps = profiles.get("apps") or {}
        folder = []
        seen_keys: set[str] = set()
        for a in members:
            k = a.get("key") or ""
            if k in seen_keys:
                continue
            seen_keys.add(k)
            p = prof_apps.get(k) if isinstance(prof_apps, dict) else None
            desk = ""
            if isinstance(p, dict):
                desk = str(p.get("desktopId") or "")
            folder.append(
                {
                    "key": k,
                    "name": a.get("name") or k,
                    "playing": bool(a.get("playing")),
                    "desktopId": desk,
                    "streamId": a.get("id") or "",
                }
            )
        # Profile-only members not yet in merge (shouldn't happen) — already in merge_apps
        slot = saved_routes.get(sid) or {}
        cells = {}
        for mid, _, _, _ in mix_rows(profiles):
            cells[mid] = live_cell(sid, mid, slot.get(mid, True))
        channels.append(
            {
                "id": sid,
                "label": lab,
                "short": short,
                "kind": "channel",
                "present": sink_exists(sid, sinks),
                "volume": vol,
                "muted": muted,
                "apps": folder,
                "count": len(folder),
                "cells": cells,
                # keep routes bool map for older UI bindings
                "routes": {mid: bool(cells[mid].get("on")) for mid, _, _, _ in mix_rows(profiles)},
            }
        )

    src_descs = source_descriptions()
    inputs = []
    for sid, lab, short, source in input_rows(profiles):
        vol, muted = sink_volume_mute(sid) if sink_exists(sid, sinks) else (100, False)
        slot = saved_routes.get(sid) or {}
        cells = {}
        for mid, _, _, _ in mix_rows(profiles):
            cells[mid] = live_cell(sid, mid, slot.get(mid, True))
        inputs.append(
            {
                "id": sid,
                "label": lab,
                "short": short,
                "kind": "input",
                "source": source,
                "sourceLabel": src_descs.get(source) or label_for_sink(source),
                "present": sink_exists(sid, sinks) and bool(source) and source_exists(source),
                "volume": vol,
                "muted": muted,
                "apps": [],
                "count": 0,
                "cells": cells,
                "routes": {mid: bool(cells[mid].get("on")) for mid, _, _, _ in mix_rows(profiles)},
            }
        )

    unassigned = [a for a in apps if not a.get("inMix")]
    first_ch = rows[0][0] if rows else ""
    for a in unassigned:
        if not a.get("sink"):
            a["suggested"] = hint_channel(a.get("name") or "", profiles) or first_ch

    assign = [{"id": sid, "label": lab, "kind": "mix", "present": sink_exists(sid, sinks)} for sid, lab, _ in rows]
    default = ""
    code, out, _ = run(["pactl", "get-default-sink"])
    if code == 0:
        default = (out or "").strip()
        if default:
            assign.append({"id": default, "label": "Speakers", "kind": "device", "present": True})

    listening = "system"
    for m in mixes:
        if m.get("hear"):
            listening = m["id"]
            break

    return {
        "ok": True,
        "error": "",
        "listening": listening,
        "mixes": mixes,
        "channels": channels,
        "inputs": inputs,
        "availableSources": list_available_sources(profiles),
        "apps": apps,
        "unassigned": unassigned,
        "assignOptions": assign,
        "defaultSink": default,
        "profilePath": str(PROFILE_PATH),
    }


def assign_app(
    app_key_arg: str,
    sink_name: str,
    stream_id: str = "",
    label: str = "",
    desktop_id: str = "",
) -> dict:
    key = app_key(app_key_arg)
    if not key or is_skipped_app(key) or not sink_name:
        return {"ok": False, "error": "invalid app or sink"}
    profiles = load_profiles()
    # Apps only go to app channels (not input strips).
    if not channel_meta(sink_name, profiles) and not (
        sink_exists(sink_name) and not str(sink_name).startswith("proteus_in_")
    ):
        return {"ok": False, "error": "unknown sink"}
    nice = display_name(label or app_key_arg)
    sinks = short_sinks()
    playing = list_playing(sinks)
    for a in playing:
        if a.get("key") == key or _matches_profile_key(a, key, desktop_id):
            nice = a.get("name") or nice
            if not stream_id:
                stream_id = a.get("id") or ""
            break
    entry: dict = {"label": nice, "sink": sink_name}
    desk = (desktop_id or "").strip().removesuffix(".desktop")
    if desk:
        entry["desktopId"] = desk
    profiles.setdefault("apps", {})[key] = entry
    save_profiles(profiles)
    if stream_id:
        run(["pactl", "move-sink-input", str(stream_id), sink_name])
    else:
        for a in playing:
            if a.get("key") == key or _matches_profile_key(a, key, desk):
                run(["pactl", "move-sink-input", str(a["id"]), sink_name])
    return {"ok": True, "saved": True, "error": ""}


def unassign_app(app_key_arg: str) -> dict:
    key = app_key(app_key_arg)
    if not key:
        return {"ok": False, "error": "invalid app"}
    profiles = load_profiles()
    apps = profiles.setdefault("apps", {})
    if key not in apps:
        # also try by label match
        for k, v in list(apps.items()):
            if isinstance(v, dict) and app_key(str(v.get("label") or "")) == key:
                key = k
                break
    if key in apps:
        del apps[key]
        save_profiles(profiles)
    # Return playing streams for this app to the default sink
    code, out, _ = run(["pactl", "get-default-sink"])
    default = (out or "").strip() if code == 0 else ""
    if default:
        sinks = short_sinks()
        for a in list_playing(sinks):
            if a.get("key") == key and a.get("inMix"):
                run(["pactl", "move-sink-input", str(a["id"]), default])
    return {"ok": True, "error": ""}


def _matches_profile_key(playing: dict, key: str, desktop_id: str = "") -> bool:
    if playing.get("key") == key:
        return True
    name = app_key(playing.get("name") or "")
    if name == key:
        return True
    detail = app_key(playing.get("detail") or "")
    if detail and detail == key:
        return True
    desk = app_key((desktop_id or "").replace(".desktop", "").split(".")[-1])
    if desk and (name == desk or detail == desk or playing.get("key") == desk):
        return True
    return False


def set_volume(channel: str, pct: int) -> dict:
    if not channel_for_sink(channel):
        return {"ok": False, "error": "unknown channel"}
    v = max(0, min(150, int(pct)))
    code, _, err = run(["pactl", "set-sink-volume", channel, f"{v}%"])
    return {"ok": code == 0, "error": (err or "").strip()}


def set_mute(channel: str, muted: bool) -> dict:
    if not channel_for_sink(channel):
        return {"ok": False, "error": "unknown channel"}
    code, _, err = run(["pactl", "set-sink-mute", channel, "1" if muted else "0"])
    return {"ok": code == 0, "error": (err or "").strip()}


def _truthy(s: str) -> bool:
    return s in ("on", "1", "true")


def main() -> int:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("dump")
    sub.add_parser("ensure")
    addc = sub.add_parser("add-channel")
    addc.add_argument("label")
    remc = sub.add_parser("remove-channel")
    remc.add_argument("channel")
    renc = sub.add_parser("rename-channel")
    renc.add_argument("channel")
    renc.add_argument("label")
    addm = sub.add_parser("add-mix")
    addm.add_argument("label")
    addm.add_argument("--hear", action="store_true", help="Loop this mix to speakers")
    remm = sub.add_parser("remove-mix")
    remm.add_argument("mix")
    renm = sub.add_parser("rename-mix")
    renm.add_argument("mix")
    renm.add_argument("label")
    lis = sub.add_parser("listen")
    lis.add_argument("mix")
    addi = sub.add_parser("add-input")
    addi.add_argument("source")
    addi.add_argument("--label", default="")
    remi = sub.add_parser("remove-input")
    remi.add_argument("input")
    reni = sub.add_parser("rename-input")
    reni.add_argument("input")
    reni.add_argument("label")
    movc = sub.add_parser("move-channel")
    movc.add_argument("channel")
    movc.add_argument("index", type=int)
    movm = sub.add_parser("move-mix")
    movm.add_argument("mix")
    movm.add_argument("index", type=int)
    movi = sub.add_parser("move-input")
    movi.add_argument("input")
    movi.add_argument("index", type=int)
    asg = sub.add_parser("assign")
    asg.add_argument("app_key")
    asg.add_argument("sink")
    asg.add_argument("--stream-id", default="")
    asg.add_argument("--label", default="")
    asg.add_argument("--desktop-id", default="")
    una = sub.add_parser("unassign")
    una.add_argument("app_key")
    rt = sub.add_parser("route")
    rt.add_argument("channel")
    rt.add_argument("mix")
    rt.add_argument("state", choices=["on", "off", "1", "0", "true", "false"])
    vol = sub.add_parser("volume")
    vol.add_argument("channel")
    vol.add_argument("percent", type=int)
    mu = sub.add_parser("mute")
    mu.add_argument("channel")
    mu.add_argument("state", choices=["0", "1", "on", "off", "true", "false"])
    cv = sub.add_parser("cell-volume")
    cv.add_argument("channel")
    cv.add_argument("mix")
    cv.add_argument("percent", type=int)
    cm = sub.add_parser("cell-mute")
    cm.add_argument("channel")
    cm.add_argument("mix")
    cm.add_argument("state", choices=["0", "1", "on", "off", "true", "false"])
    args = ap.parse_args()
    if args.cmd == "dump":
        print(json.dumps(dump()))
        return 0
    if args.cmd == "ensure":
        print(json.dumps(ensure_channels()))
        return 0
    if args.cmd == "add-channel":
        print(json.dumps(add_channel(args.label)))
        return 0
    if args.cmd == "remove-channel":
        print(json.dumps(remove_channel(args.channel)))
        return 0
    if args.cmd == "rename-channel":
        print(json.dumps(rename_channel(args.channel, args.label)))
        return 0
    if args.cmd == "add-mix":
        print(json.dumps(add_mix(args.label, bool(args.hear))))
        return 0
    if args.cmd == "remove-mix":
        print(json.dumps(remove_mix(args.mix)))
        return 0
    if args.cmd == "rename-mix":
        print(json.dumps(rename_mix(args.mix, args.label)))
        return 0
    if args.cmd == "listen":
        print(json.dumps(set_listen(args.mix)))
        return 0
    if args.cmd == "add-input":
        print(json.dumps(add_input(args.source, args.label)))
        return 0
    if args.cmd == "remove-input":
        print(json.dumps(remove_input(args.input)))
        return 0
    if args.cmd == "rename-input":
        print(json.dumps(rename_input(args.input, args.label)))
        return 0
    if args.cmd == "move-channel":
        print(json.dumps(move_channel(args.channel, args.index)))
        return 0
    if args.cmd == "move-mix":
        print(json.dumps(move_mix(args.mix, args.index)))
        return 0
    if args.cmd == "move-input":
        print(json.dumps(move_input(args.input, args.index)))
        return 0
    if args.cmd == "assign":
        print(
            json.dumps(
                assign_app(
                    args.app_key,
                    args.sink,
                    args.stream_id,
                    args.label,
                    args.desktop_id,
                )
            )
        )
        return 0
    if args.cmd == "unassign":
        print(json.dumps(unassign_app(args.app_key)))
        return 0
    if args.cmd == "route":
        print(json.dumps(set_route(args.channel, args.mix, _truthy(args.state))))
        return 0
    if args.cmd == "volume":
        print(json.dumps(set_volume(args.channel, args.percent)))
        return 0
    if args.cmd == "mute":
        print(json.dumps(set_mute(args.channel, _truthy(args.state))))
        return 0
    if args.cmd == "cell-volume":
        print(json.dumps(set_cell_volume(args.channel, args.mix, args.percent)))
        return 0
    if args.cmd == "cell-mute":
        print(json.dumps(set_cell_mute(args.channel, args.mix, _truthy(args.state))))
        return 0
    return 2


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as e:
        print(json.dumps({"ok": False, "error": str(e)}))
        raise SystemExit(0)
