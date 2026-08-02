#!/usr/bin/env python3
"""Probe mic / camera / screen-capture in use → JSON for menu-bar + Privacy.

Honest, best-effort: PipeWire + pactl + /dev/video*. Not a grant store —
Settings → Privacy holds Allow/Ask/Deny; this script only reports activity.
"""
from __future__ import annotations

import glob
import json
import os
import re
import subprocess
import sys
from pathlib import Path


def _run(cmd: list[str], timeout: float = 2.0) -> str:
    try:
        return subprocess.check_output(
            cmd, text=True, stderr=subprocess.DEVNULL, timeout=timeout
        )
    except Exception:
        return ""


def _desktop_dirs() -> list[Path]:
    dirs: list[Path] = []
    home = Path.home()
    dirs.append(home / ".local/share/applications")
    data = os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share")
    for part in data.split(":"):
        if part:
            dirs.append(Path(part) / "applications")
    return dirs


def _read_desktop_name(desktop_id: str) -> str:
    if not desktop_id:
        return ""
    fname = desktop_id if desktop_id.endswith(".desktop") else desktop_id + ".desktop"
    for d in _desktop_dirs():
        p = d / fname
        if not p.is_file():
            continue
        try:
            text = p.read_text(encoding="utf-8", errors="replace")
        except Exception:
            continue
        m = re.search(r"(?m)^Name=(.+)$", text)
        if m:
            return m.group(1).strip()
    return desktop_id.replace(".desktop", "").replace("-", " ").replace(".", " ")


def _resolve_desktop_id(app_name: str, binary: str) -> str:
    """Best-effort map process name → desktop id stem."""
    candidates = []
    for raw in (app_name, binary, Path(binary).name if binary else ""):
        s = (raw or "").strip()
        if not s:
            continue
        candidates.append(s)
        candidates.append(s.lower())
        candidates.append(s.replace(" ", "-").lower())
        # flatpak-style org.foo.Bar
        if "." in s:
            candidates.append(s)

    seen: set[str] = set()
    for c in candidates:
        if c in seen:
            continue
        seen.add(c)
        for d in _desktop_dirs():
            for fname in (c + ".desktop", c):
                p = d / fname if fname.endswith(".desktop") else d / (fname + ".desktop")
                if p.is_file():
                    stem = p.name[: -len(".desktop")]
                    return stem
    # Heuristic: chromium / firefox common names
    blob = f"{app_name} {binary}".lower()
    if "chromium" in blob:
        return "chromium"
    if "firefox" in blob:
        return "firefox"
    if "chrome" in blob:
        return "google-chrome"
    return ""


def _app_entry(kind: str, app_name: str, binary: str) -> dict:
    label = (app_name or Path(binary).name if binary else "" or "Unknown").strip()
    desk = _resolve_desktop_id(app_name, binary)
    if desk:
        pretty = _read_desktop_name(desk)
        if pretty:
            label = pretty
    return {
        "kind": kind,
        "id": desk,
        "label": label or "Unknown",
        "binary": (Path(binary).name if binary else "") or "",
    }


def _dedupe(apps: list[dict]) -> list[dict]:
    out: list[dict] = []
    seen: set[str] = set()
    for a in apps:
        key = f"{a.get('kind')}|{a.get('id')}|{a.get('binary')}|{a.get('label')}"
        if key in seen:
            continue
        seen.add(key)
        out.append(a)
    return out


_PW_DUMP: list | None = None


def _pw_dump() -> list:
    global _PW_DUMP
    if _PW_DUMP is not None:
        return _PW_DUMP
    raw = _run(["pw-dump"], timeout=3.0)
    if not raw.strip():
        _PW_DUMP = []
        return _PW_DUMP
    try:
        data = json.loads(raw)
        _PW_DUMP = data if isinstance(data, list) else []
    except Exception:
        _PW_DUMP = []
    return _PW_DUMP


def mic_apps() -> list[dict]:
    apps: list[dict] = []
    # pactl source-outputs — verbose blocks
    out = _run(["pactl", "list", "source-outputs"], timeout=3.0)
    if out:
        cur_name = ""
        cur_bin = ""
        for line in out.splitlines():
            if line.startswith("Source Output #"):
                if cur_name or cur_bin:
                    apps.append(_app_entry("microphone", cur_name, cur_bin))
                cur_name = ""
                cur_bin = ""
                continue
            s = line.strip()
            if s.startswith("application.name ="):
                cur_name = s.split("=", 1)[-1].strip().strip('"')
            elif s.startswith("application.process.binary ="):
                cur_bin = s.split("=", 1)[-1].strip().strip('"')
        if cur_name or cur_bin:
            apps.append(_app_entry("microphone", cur_name, cur_bin))

    if not apps:
        short = _run(["pactl", "list", "source-outputs", "short"])
        if any(line.strip() for line in short.splitlines()):
            apps.append(
                {
                    "kind": "microphone",
                    "id": "",
                    "label": "Audio capture",
                    "binary": "",
                }
            )
    return _dedupe(apps)


def mic_active() -> bool:
    return len(mic_apps()) > 0


def camera_apps() -> list[dict]:
    apps: list[dict] = []
    # fuser on /dev/video*
    for path in sorted(glob.glob("/dev/video*")):
        try:
            r = subprocess.run(
                ["fuser", "-v", path],
                capture_output=True,
                text=True,
                timeout=1.5,
            )
            blob = (r.stdout or "") + (r.stderr or "")
        except Exception:
            blob = ""
        # fuser -v lines often include COMMAND column
        for line in blob.splitlines():
            parts = line.split()
            if not parts:
                continue
            # skip header
            if "USER" in parts and "PID" in parts:
                continue
            cmd = parts[-1] if parts else ""
            if cmd in ("fuser", "kernel", "") or cmd.startswith("/"):
                # sometimes full path
                cmd = Path(cmd).name if cmd else ""
            if cmd and cmd not in ("fuser",):
                apps.append(_app_entry("camera", cmd, cmd))

    dump = _pw_dump()
    for obj in dump:
        info = obj.get("info") or {}
        props = info.get("props") or {}
        state = str(info.get("state") or "").lower()
        if state != "running":
            continue
        mc = str(props.get("media.class") or "")
        name = (
            str(props.get("node.name") or "")
            + " "
            + str(props.get("node.description") or "")
        ).lower()
        app_name = str(props.get("application.name") or "")
        binary = str(props.get("application.process.binary") or "")
        if mc == "Stream/Input/Video" and (
            "v4l2" in name or "camera" in name or "libcamera" in name
        ):
            apps.append(_app_entry("camera", app_name or "Camera", binary))
        elif mc == "Video/Source" and ("v4l2" in name or "camera" in name):
            if app_name or binary:
                apps.append(_app_entry("camera", app_name, binary))
    return _dedupe(apps)


def camera_active() -> bool:
    return len(camera_apps()) > 0


def screen_apps() -> list[dict]:
    apps: list[dict] = []
    dump = _pw_dump()
    tokens = (
        "xdg-desktop-portal",
        "screencast",
        "screen share",
        "screen-share",
        "hyprland-share",
        "wf-recorder",
        "obs",
        "screencopy",
        "xdp",
        "portal",
    )
    for obj in dump:
        info = obj.get("info") or {}
        props = info.get("props") or {}
        state = str(info.get("state") or "").lower()
        if state != "running":
            continue
        blob = " ".join(
            str(props.get(k) or "")
            for k in (
                "media.class",
                "node.name",
                "node.description",
                "application.name",
                "application.process.binary",
            )
        ).lower()
        mc = str(props.get("media.class") or "")
        hit = any(t in blob for t in tokens) and (
            "video" in blob or "stream" in blob or "source" in blob
        )
        hit = hit or (
            mc == "Stream/Input/Video"
            and ("xdp" in blob or "portal" in blob or "screencopy" in blob)
        )
        if not hit:
            continue
        app_name = str(props.get("application.name") or "")
        binary = str(props.get("application.process.binary") or "")
        if not app_name and not binary:
            # Derive label from node
            app_name = str(props.get("node.description") or props.get("node.name") or "Screen capture")
        apps.append(_app_entry("screen", app_name, binary))
    return _dedupe(apps)


def screen_active() -> bool:
    return len(screen_apps()) > 0


def main() -> int:
    mics = mic_apps()
    cams = camera_apps()
    screens = screen_apps()
    print(
        json.dumps(
            {
                "mic": len(mics) > 0,
                "camera": len(cams) > 0,
                "screen": len(screens) > 0,
                "apps": mics + cams + screens,
            }
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
