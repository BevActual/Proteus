#!/usr/bin/env python3
"""Beacon Files — lightweight home path index + search.

Cache: ~/.cache/proteus/beacon-files.json
Rebuild via fd (preferred) or os.walk. Search filters the index in-process
so repeated queries stay fast without re-walking the tree.
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

MAX_DEPTH = 5
MAX_HITS = 40
STALE_SEC = 300  # 5 minutes
SKIP_DIRS = {
    ".git",
    "node_modules",
    ".cache",
    "Trash",
    ".Trash",
    ".npm",
    ".cargo",
    ".local",
    ".rustup",
    "__pycache__",
}


def cache_path() -> Path:
    xdg = os.environ.get("XDG_CACHE_HOME")
    base = Path(xdg) if xdg else Path.home() / ".cache"
    return base / "proteus" / "beacon-files.json"


def _load() -> dict | None:
    p = cache_path()
    if not p.is_file():
        return None
    try:
        data = json.loads(p.read_text(encoding="utf-8"))
    except Exception:
        return None
    if not isinstance(data, dict) or not isinstance(data.get("paths"), list):
        return None
    return data


def _save(paths: list[dict], engine: str) -> None:
    p = cache_path()
    p.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "version": 1,
        "built_at": time.time(),
        "home": str(Path.home()),
        "engine": engine,
        "paths": paths,
    }
    p.write_text(json.dumps(payload, separators=(",", ":")) + "\n", encoding="utf-8")


def _collect_fd(home: Path) -> list[dict]:
    fd = shutil.which("fd") or shutil.which("fdfind")
    if not fd:
        return []
    try:
        r = subprocess.run(
            [
                fd,
                "--max-depth",
                str(MAX_DEPTH),
                # Default skips hidden; do not pass --hidden.
                "-t",
                "f",
                "-t",
                "d",
                ".",
                str(home),
            ],
            capture_output=True,
            text=True,
            timeout=12,
        )
    except Exception:
        return []
    # fd: 0 = matches, 1 = no matches; other = error → fall through to walk
    if r.returncode not in (0, 1):
        return []
    out: list[dict] = []
    for line in (r.stdout or "").splitlines():
        path = line.strip()
        if not path:
            continue
        name = os.path.basename(path.rstrip(os.sep)) or path
        out.append({"path": path, "name": name, "dir": os.path.isdir(path)})
        if len(out) >= 20000:
            break
    return out


def _collect_walk(home: Path) -> list[dict]:
    home_s = str(home)
    home_depth = home_s.count(os.sep)
    out: list[dict] = []
    for root, dirs, files in os.walk(home_s):
        if root.count(os.sep) - home_depth > MAX_DEPTH:
            dirs[:] = []
            continue
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS and not d.startswith(".")]
        for name in list(files) + list(dirs):
            if name.startswith("."):
                continue
            path = os.path.join(root, name)
            out.append({"path": path, "name": name, "dir": os.path.isdir(path)})
            if len(out) >= 20000:
                return out
    return out


def rebuild(force: bool = False) -> dict:
    home = Path.home()
    existing = _load()
    if (
        not force
        and existing
        and existing.get("home") == str(home)
        and (time.time() - float(existing.get("built_at") or 0)) < STALE_SEC
    ):
        return {
            "ok": True,
            "rebuilt": False,
            "count": len(existing.get("paths") or []),
            "engine": existing.get("engine") or "cache",
            "stale_sec": STALE_SEC,
        }
    paths = _collect_fd(home)
    engine = "fd"
    if not paths:
        paths = _collect_walk(home)
        engine = "walk"
    _save(paths, engine)
    return {
        "ok": True,
        "rebuilt": True,
        "count": len(paths),
        "engine": engine,
        "stale_sec": STALE_SEC,
    }


def search(query: str) -> dict:
    q = (query or "").strip().lower()
    if not q:
        return {"ok": True, "hits": [], "capped": False, "engine": "index"}
    info = rebuild(force=False)
    data = _load() or {"paths": [], "engine": "empty"}
    hits: list[dict] = []
    capped = False
    for row in data.get("paths") or []:
        if not isinstance(row, dict):
            continue
        name = str(row.get("name") or "").lower()
        path = str(row.get("path") or "")
        parent = os.path.basename(os.path.dirname(path)).lower() if path else ""
        if q not in name and q not in parent and q not in path.lower():
            continue
        hits.append(
            {
                "path": path,
                "name": row.get("name") or os.path.basename(path),
                "dir": bool(row.get("dir")),
            }
        )
        if len(hits) >= MAX_HITS:
            capped = True
            break
    return {
        "ok": True,
        "hits": hits,
        "capped": capped,
        "engine": "index:" + str(data.get("engine") or info.get("engine") or "?"),
        "indexed": int(info.get("count") or len(data.get("paths") or [])),
    }


def main() -> int:
    ap = argparse.ArgumentParser(description="Beacon home file index")
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("rebuild", help="Force rebuild index")
    p_s = sub.add_parser("search", help="Search index (rebuilds if stale)")
    p_s.add_argument("query")
    sub.add_parser("status", help="Index metadata")
    args = ap.parse_args()
    if args.cmd == "rebuild":
        print(json.dumps(rebuild(force=True)))
        return 0
    if args.cmd == "search":
        print(json.dumps(search(args.query)))
        return 0
    if args.cmd == "status":
        data = _load()
        if not data:
            print(json.dumps({"ok": True, "present": False}))
            return 0
        age = time.time() - float(data.get("built_at") or 0)
        print(
            json.dumps(
                {
                    "ok": True,
                    "present": True,
                    "count": len(data.get("paths") or []),
                    "engine": data.get("engine"),
                    "age_sec": round(age, 1),
                    "stale": age > STALE_SEC,
                    "path": str(cache_path()),
                }
            )
        )
        return 0
    return 2


if __name__ == "__main__":
    sys.exit(main())
