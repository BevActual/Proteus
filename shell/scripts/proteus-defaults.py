#!/usr/bin/env python3
"""Default applications — query / set via xdg-mime (+ gio for candidates).

Used by Settings → Desktop → Default apps.
Writes user mimeapps via `xdg-mime default` (no polkit).
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

# Categories we expose in Settings. Each set applies to every mime listed.
# desktop_cats: FreeDesktop Categories= tokens used to trim noise (e.g. Amberol
# claiming inode/directory). Empty = no filter. Current default always kept.
CATEGORIES: list[dict] = [
    {
        "id": "browser",
        "label": "Web browser",
        "hint": "http, https, and HTML",
        "mimes": [
            "x-scheme-handler/http",
            "x-scheme-handler/https",
            "text/html",
            "application/xhtml+xml",
        ],
        "desktop_cats": ["WebBrowser"],
    },
    {
        "id": "mail",
        "label": "Mail",
        "hint": "mailto: links",
        "mimes": ["x-scheme-handler/mailto"],
        "desktop_cats": ["Email", "EmailClient"],
    },
    {
        "id": "files",
        "label": "File manager",
        "hint": "Folders",
        "mimes": ["inode/directory"],
        "desktop_cats": ["FileManager"],
    },
    {
        "id": "images",
        "label": "Images",
        "hint": "JPEG, PNG, WebP, GIF, …",
        "mimes": [
            "image/jpeg",
            "image/png",
            "image/webp",
            "image/gif",
            "image/svg+xml",
            "image/avif",
        ],
        "desktop_cats": ["Viewer", "Graphics", "2DGraphics"],
    },
    {
        "id": "audio",
        "label": "Music",
        "hint": "Audio files",
        "mimes": [
            "audio/mpeg",
            "audio/flac",
            "audio/x-wav",
            "audio/mp4",
            "audio/ogg",
            "audio/x-vorbis+ogg",
        ],
        "desktop_cats": ["Audio", "Player", "AudioVideo"],
    },
    {
        "id": "video",
        "label": "Video",
        "hint": "Video files",
        "mimes": [
            "video/mp4",
            "video/x-matroska",
            "video/webm",
            "video/x-msvideo",
            "video/quicktime",
        ],
        "desktop_cats": ["Video", "Player", "AudioVideo"],
    },
    {
        "id": "pdf",
        "label": "PDF",
        "hint": "PDF documents",
        "mimes": ["application/pdf"],
        "desktop_cats": ["Viewer", "Office"],
    },
    {
        "id": "text",
        "label": "Text editor",
        "hint": "Plain text",
        "mimes": ["text/plain"],
        "desktop_cats": ["TextEditor"],
    },
    {
        "id": "archive",
        "label": "Archives",
        "hint": "zip, tar, …",
        "mimes": [
            "application/zip",
            "application/x-tar",
            "application/x-compressed-tar",
            "application/x-xz-compressed-tar",
            "application/vnd.rar",
            "application/x-7z-compressed",
        ],
        "desktop_cats": ["Archiving", "Compression"],
    },
    {
        "id": "calendar",
        "label": "Calendar",
        "hint": "Calendar invites (.ics)",
        "mimes": ["text/calendar"],
        "desktop_cats": ["Calendar", "Office"],
    },
]


def _run(cmd: list[str], timeout: float = 4.0) -> str:
    try:
        return subprocess.check_output(
            cmd, text=True, stderr=subprocess.DEVNULL, timeout=timeout
        ).strip()
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


def _desktop_path(desktop_id: str) -> Path | None:
    if not desktop_id:
        return None
    fname = desktop_id if desktop_id.endswith(".desktop") else desktop_id + ".desktop"
    for d in _desktop_dirs():
        p = d / fname
        if p.is_file():
            return p
    return None


def _read_desktop_field(desktop_id: str, field: str) -> str:
    p = _desktop_path(desktop_id)
    if not p:
        return ""
    try:
        text = p.read_text(encoding="utf-8", errors="replace")
    except Exception:
        return ""
    m = re.search(rf"(?m)^{re.escape(field)}=(.+)$", text)
    return m.group(1).strip() if m else ""


def _read_desktop_name(desktop_id: str) -> str:
    if not desktop_id:
        return ""
    name = _read_desktop_field(desktop_id, "Name")
    if name:
        return name
    fname = desktop_id if desktop_id.endswith(".desktop") else desktop_id + ".desktop"
    return fname.replace(".desktop", "").replace("-", " ").replace(".", " ")


def _desktop_categories(desktop_id: str) -> set[str]:
    raw = _read_desktop_field(desktop_id, "Categories")
    if not raw:
        return set()
    return {c for c in raw.split(";") if c}


def _filter_candidates(cand_ids: list[str], want_cats: list[str], current: str) -> list[str]:
    """Keep apps matching FreeDesktop Categories; always keep current; fall back if empty."""
    if not want_cats:
        return cand_ids
    want = set(want_cats)
    filtered: list[str] = []
    for d in cand_ids:
        if d == current or (_desktop_categories(d) & want):
            if d not in filtered:
                filtered.append(d)
    return filtered if filtered else list(cand_ids)


def query_default(mime: str) -> str:
    out = _run(["xdg-mime", "query", "default", mime])
    return out.strip()


def list_candidates(mime: str) -> list[str]:
    """Registered handlers for a MIME type (gio preferred, mimeinfo.cache fallback)."""
    found: list[str] = []
    gio = _run(["gio", "mime", mime])
    if gio:
        for line in gio.splitlines():
            line = line.strip()
            # "\tapp.desktop" under Registered / Recommended
            if line.endswith(".desktop") and " " not in line:
                # lines like "\tchromium.desktop" already stripped
                if line not in found:
                    found.append(line)
            # "Default application for …: foo.desktop"
            if ":" in line and line.endswith(".desktop"):
                desk = line.rsplit(":", 1)[-1].strip()
                if desk.endswith(".desktop") and desk not in found:
                    found.append(desk)

    # mimeinfo.cache: mime/type=app1.desktop;app2.desktop;
    for base in _desktop_dirs():
        cache = base.parent / "applications" / "mimeinfo.cache"
        # dirs are …/applications — cache is beside them
        cache = base / "mimeinfo.cache"
        if not cache.is_file():
            # also try parent share/applications/mimeinfo.cache via DATA dirs
            continue
        try:
            for line in cache.read_text(encoding="utf-8", errors="replace").splitlines():
                if not line.startswith(mime + "="):
                    continue
                apps = line.split("=", 1)[1].strip().rstrip(";").split(";")
                for a in apps:
                    a = a.strip()
                    if a.endswith(".desktop") and a not in found:
                        found.append(a)
        except Exception:
            pass

    # Broader cache search under XDG data
    data = os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share")
    for part in data.split(":"):
        cache = Path(part) / "applications" / "mimeinfo.cache"
        if not cache.is_file():
            continue
        try:
            for line in cache.read_text(encoding="utf-8", errors="replace").splitlines():
                if not line.startswith(mime + "="):
                    continue
                apps = line.split("=", 1)[1].strip().rstrip(";").split(";")
                for a in apps:
                    a = a.strip()
                    if a.endswith(".desktop") and a not in found:
                        found.append(a)
        except Exception:
            pass

    cur = query_default(mime)
    if cur and cur not in found:
        found.insert(0, cur)
    return found


def category_by_id(cid: str) -> dict | None:
    for c in CATEGORIES:
        if c["id"] == cid:
            return c
    return None


def build_list() -> dict:
    cats = []
    for c in CATEGORIES:
        mimes = c["mimes"]
        current = ""
        for m in mimes:
            current = query_default(m)
            if current:
                break
        # Union candidates across mimes (prefer first mime’s list order)
        cand_ids: list[str] = []
        for m in mimes:
            for a in list_candidates(m):
                if a not in cand_ids:
                    cand_ids.append(a)
        if current and current not in cand_ids:
            cand_ids.insert(0, current)
        cand_ids = _filter_candidates(cand_ids, c.get("desktop_cats") or [], current)
        candidates = [
            {"id": d, "label": _read_desktop_name(d)} for d in cand_ids
        ]
        cats.append(
            {
                "id": c["id"],
                "label": c["label"],
                "hint": c["hint"],
                "current": current,
                "currentLabel": _read_desktop_name(current) if current else "Not set",
                "candidates": candidates,
            }
        )
    return {"ok": True, "categories": cats}


def set_category(cid: str, desktop_id: str) -> dict:
    cat = category_by_id(cid)
    if not cat:
        return {"ok": False, "error": f"unknown category: {cid}"}
    desk = desktop_id.strip()
    if not desk:
        return {"ok": False, "error": "empty desktop id"}
    if not desk.endswith(".desktop"):
        desk = desk + ".desktop"
    errors = []
    for mime in cat["mimes"]:
        try:
            subprocess.check_call(
                ["xdg-mime", "default", desk, mime],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
                timeout=5,
            )
        except subprocess.CalledProcessError as e:
            err = (e.stderr or b"").decode("utf-8", "replace").strip()
            errors.append(f"{mime}: {err or 'failed'}")
        except Exception as e:
            errors.append(f"{mime}: {e}")
    if errors:
        return {"ok": False, "error": "; ".join(errors[:3]), "desktop": desk}
    return {
        "ok": True,
        "desktop": desk,
        "label": _read_desktop_name(desk),
        "category": cid,
    }


def main() -> int:
    ap = argparse.ArgumentParser(description="Proteus default applications")
    sub = ap.add_subparsers(dest="cmd", required=True)

    sub.add_parser("list", help="JSON snapshot of categories + candidates")

    p_set = sub.add_parser("set", help="Set default app for a category")
    p_set.add_argument("category")
    p_set.add_argument("desktop")

    args = ap.parse_args()
    if args.cmd == "list":
        print(json.dumps(build_list()))
        return 0
    if args.cmd == "set":
        print(json.dumps(set_category(args.category, args.desktop)))
        return 0
    return 2


if __name__ == "__main__":
    sys.exit(main())
