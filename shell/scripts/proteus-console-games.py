#!/usr/bin/env python3
"""Installed games scan for the Console Games tab.

Titles, not just launchers:
  steam     — steamapps/libraryfolders.vdf + appmanifest_*.acf across all
              library folders (name, appid, size, last played); runtime /
              redistributable / Proton entries are skipped
  retroarch — ~/.config/retroarch/playlists/*.lpl (JSON): label, rom path,
              core path per entry

Read-only. Stdout: one JSON object.
Fixture: PROTEUS_CONSOLE_GAMES_FIXTURE=1 (smokes / chrome dev on hosts
without Steam).
Launch stays in the seat: steam -applaunch <id> · retroarch -L <core> <rom>.
"""
from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path
from typing import Any

_ACF_FIELD = re.compile(r'"(appid|name|SizeOnDisk|LastPlayed)"\s+"([^"]*)"', re.IGNORECASE)
_VDF_PATH = re.compile(r'"path"\s+"([^"]+)"')

# Non-game Steam apps that live in every library.
_SKIP_NAME = re.compile(
    r"steamworks common|proton|steam linux runtime|steamvr|redistributable",
    re.IGNORECASE,
)


def _steam_roots() -> list[Path]:
    home = Path.home()
    roots = []
    for cand in (
        home / ".local" / "share" / "Steam",
        home / ".steam" / "steam",
        home / ".var" / "app" / "com.valvesoftware.Steam" / ".local" / "share" / "Steam",
    ):
        try:
            if (cand / "steamapps").is_dir() and cand.resolve() not in [r.resolve() for r in roots]:
                roots.append(cand)
        except OSError:
            continue
    return roots


def _steam_libraries(root: Path) -> list[Path]:
    libs = [root / "steamapps"]
    vdf = root / "steamapps" / "libraryfolders.vdf"
    try:
        text = vdf.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return libs
    for m in _VDF_PATH.finditer(text):
        p = Path(m.group(1).replace("\\\\", "/")) / "steamapps"
        try:
            if p.is_dir() and p.resolve() not in [x.resolve() for x in libs]:
                libs.append(p)
        except OSError:
            continue
    return libs


def _scan_steam(errors: list[str]) -> dict[str, Any]:
    roots = _steam_roots()
    if not roots:
        return {"available": False, "titles": []}
    titles: list[dict[str, Any]] = []
    seen: set[str] = set()
    for root in roots:
        for lib in _steam_libraries(root):
            try:
                manifests = sorted(lib.glob("appmanifest_*.acf"))
            except OSError:
                continue
            for mf in manifests:
                try:
                    text = mf.read_text(encoding="utf-8", errors="replace")
                except OSError:
                    continue
                fields: dict[str, str] = {}
                for m in _ACF_FIELD.finditer(text):
                    fields.setdefault(m.group(1).lower(), m.group(2))
                app_id = fields.get("appid", "")
                name = fields.get("name", "")
                if not app_id or not name or app_id in seen:
                    continue
                if _SKIP_NAME.search(name):
                    continue
                seen.add(app_id)
                titles.append({
                    "appId": app_id,
                    "name": name,
                    "sizeBytes": int(fields.get("sizeondisk") or 0),
                    "lastPlayed": int(fields.get("lastplayed") or 0),
                })
    titles.sort(key=lambda t: t["name"].lower())
    return {"available": True, "titles": titles}


def _scan_retroarch(errors: list[str]) -> dict[str, Any]:
    playlists_dir = Path(
        os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))
    ) / "retroarch" / "playlists"
    if not playlists_dir.is_dir():
        return {"available": False, "titles": []}
    titles: list[dict[str, Any]] = []
    seen: set[str] = set()
    try:
        playlists = sorted(playlists_dir.glob("*.lpl"))
    except OSError:
        playlists = []
    for pl in playlists:
        try:
            data = json.loads(pl.read_text(encoding="utf-8", errors="replace"))
        except (OSError, ValueError):
            errors.append(f"unreadable playlist: {pl.name}")
            continue
        system = pl.stem
        for item in data.get("items") or []:
            label = str(item.get("label") or "")
            path = str(item.get("path") or "")
            if not label or not path or path in seen:
                continue
            seen.add(path)
            core = str(item.get("core_path") or "")
            if core.upper() == "DETECT":
                core = ""
            titles.append({
                "name": label,
                "path": path.split("#", 1)[0],
                "core": core,
                "system": system,
            })
    titles.sort(key=lambda t: t["name"].lower())
    return {"available": True, "titles": titles}


def _fixture() -> dict[str, Any]:
    return {
        "ok": True,
        "fixture": True,
        "steam": {
            "available": True,
            "titles": [
                {"appId": "620", "name": "Portal 2", "sizeBytes": 12884901888,
                 "lastPlayed": 1754100000},
                {"appId": "1145360", "name": "Hades", "sizeBytes": 16106127360,
                 "lastPlayed": 1754000000},
            ],
        },
        "retroarch": {
            "available": True,
            "titles": [
                {"name": "Super Metroid", "path": "/roms/snes/Super Metroid.sfc",
                 "core": "/usr/lib/libretro/snes9x_libretro.so",
                 "system": "Nintendo - Super Nintendo Entertainment System"},
            ],
        },
        "count": 3,
        "errors": [],
    }


def main() -> int:
    if os.environ.get("PROTEUS_CONSOLE_GAMES_FIXTURE") == "1":
        print(json.dumps(_fixture(), separators=(",", ":")))
        return 0
    errors: list[str] = []
    steam = _scan_steam(errors)
    retro = _scan_retroarch(errors)
    print(json.dumps({
        "ok": True,
        "fixture": False,
        "steam": steam,
        "retroarch": retro,
        "count": len(steam["titles"]) + len(retro["titles"]),
        "errors": errors[:5],
    }, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except BrokenPipeError:
        sys.exit(0)
