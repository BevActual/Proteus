#!/usr/bin/env python3
"""Proteus app permissions — store + Flatpak overrides + activity probe.

Store: ~/.config/proteus/permissions.json
Activity: delegates to privacy-indicators.py (SoT for in-use).
Flatpak: best-effort `flatpak override --user` for mappable categories.

Honesty: native pacman/AppImage apps are not sandboxed by this helper.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

CATEGORIES = (
    "microphone",
    "camera",
    "location",
    "notifications",
    "screen",
    "diagnostics",
)
STATES = ("allow", "ask", "deny")
DEFAULT_CATEGORIES = {c: "allow" for c in CATEGORIES}

# Flatpak categories we can map to overrides (others are store-only).
FLATPAK_MAPPABLE = frozenset({"microphone", "camera"})


def store_path() -> Path:
    return Path.home() / ".config" / "proteus" / "permissions.json"


def _run(cmd: list[str], timeout: float = 8.0) -> tuple[int, str, str]:
    try:
        r = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        return r.returncode, (r.stdout or "").strip(), (r.stderr or "").strip()
    except Exception as e:
        return 1, "", str(e)


def normalize_app_id(app_id: str) -> str:
    s = (app_id or "").strip()
    if s.endswith(".desktop"):
        s = s[: -len(".desktop")]
    return s


def default_store() -> dict:
    return {"version": 1, "categories": dict(DEFAULT_CATEGORIES), "apps": {}}


def load_store() -> dict:
    path = store_path()
    if not path.is_file():
        return default_store()
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return default_store()
    if not isinstance(data, dict):
        return default_store()
    cats = dict(DEFAULT_CATEGORIES)
    raw_cats = data.get("categories") or {}
    if isinstance(raw_cats, dict):
        for c in CATEGORIES:
            v = str(raw_cats.get(c, "allow")).lower()
            cats[c] = v if v in STATES else "allow"
    apps: dict = {}
    raw_apps = data.get("apps") or {}
    if isinstance(raw_apps, dict):
        for k, grants in raw_apps.items():
            aid = normalize_app_id(str(k))
            if not aid or not isinstance(grants, dict):
                continue
            cleaned = {}
            for c, v in grants.items():
                if c not in CATEGORIES:
                    continue
                st = str(v).lower()
                if st in STATES:
                    cleaned[c] = st
            if cleaned:
                apps[aid] = cleaned
    return {"version": 1, "categories": cats, "apps": apps}


def save_store(data: dict) -> None:
    path = store_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    try:
        os.chmod(path, 0o600)
    except Exception:
        pass


def category_state(data: dict, cat: str) -> str:
    return str((data.get("categories") or {}).get(cat, "allow"))


def app_grant(data: dict, app_id: str, cat: str) -> str:
    """Effective grant: app override or category default."""
    aid = normalize_app_id(app_id)
    apps = data.get("apps") or {}
    if aid in apps and cat in apps[aid]:
        return str(apps[aid][cat])
    return category_state(data, cat)


def granted(data: dict, app_id: str, cat: str) -> bool:
    """Adaptive enforcement: allow only; ask/deny → not granted."""
    return app_grant(data, app_id, cat) == "allow"


def cmd_store_get(_: argparse.Namespace) -> int:
    print(json.dumps({"ok": True, **load_store()}))
    return 0


def cmd_store_set_category(args: argparse.Namespace) -> int:
    cat = str(args.category)
    state = str(args.state).lower()
    if cat not in CATEGORIES:
        print(json.dumps({"ok": False, "error": f"unknown category: {cat}"}))
        return 1
    if state not in ("allow", "deny"):
        print(json.dumps({"ok": False, "error": "category state must be allow|deny"}))
        return 1
    data = load_store()
    data["categories"][cat] = state
    save_store(data)
    print(json.dumps({"ok": True, "category": cat, "state": state}))
    return 0


def cmd_store_set_app(args: argparse.Namespace) -> int:
    cat = str(args.category)
    state = str(args.state).lower()
    aid = normalize_app_id(args.app)
    if not aid:
        print(json.dumps({"ok": False, "error": "empty app id"}))
        return 1
    if cat not in CATEGORIES:
        print(json.dumps({"ok": False, "error": f"unknown category: {cat}"}))
        return 1
    if state not in STATES:
        print(json.dumps({"ok": False, "error": "state must be allow|ask|deny"}))
        return 1
    data = load_store()
    apps = data.setdefault("apps", {})
    grants = dict(apps.get(aid) or {})
    grants[cat] = state
    apps[aid] = grants
    save_store(data)
    print(json.dumps({"ok": True, "app": aid, "category": cat, "state": state}))
    return 0


def cmd_activity(_: argparse.Namespace) -> int:
    script = Path(__file__).resolve().parent / "privacy-indicators.py"
    code, out, err = _run(["python3", str(script)], timeout=5.0)
    if code != 0 or not out:
        print(json.dumps({"ok": False, "error": err or "activity probe failed", "mic": False, "camera": False, "screen": False, "apps": []}))
        return 1
    try:
        data = json.loads(out)
    except Exception as e:
        print(json.dumps({"ok": False, "error": str(e), "apps": []}))
        return 1
    data["ok"] = True
    print(json.dumps(data))
    return 0


def _flatpak_available() -> bool:
    code, _, _ = _run(["bash", "-lc", "command -v flatpak >/dev/null 2>&1"], timeout=2.0)
    return code == 0


def _parse_override_blob(text: str) -> dict:
    """Summarize flatpak override --show into coarse flags.

    Empty override → treat as allow (app manifest defaults). Explicit
    nosocket/nodevice → deny.
    """
    low = (text or "").lower()
    return {
        "pulseaudio": "nosocket=pulseaudio" not in low,
        "devices": "nodevice=all" not in low and "devices=none" not in low,
        "filesystem_home": "filesystem=home" in low or "filesystem=~" in low,
    }


def cmd_flatpak_list(_: argparse.Namespace) -> int:
    if not _flatpak_available():
        print(json.dumps({"ok": True, "available": False, "apps": [], "hint": "flatpak not installed"}))
        return 0
    code, out, err = _run(
        ["flatpak", "list", "--user", "--app", "--columns=application,name"],
        timeout=12.0,
    )
    apps = []
    if code == 0:
        for line in out.splitlines():
            line = line.strip()
            if not line or "\t" not in line:
                # columns may be space-separated
                parts = line.split(None, 1)
            else:
                parts = line.split("\t", 1)
            if not parts:
                continue
            ref = parts[0].strip()
            name = parts[1].strip() if len(parts) > 1 else ref
            if not ref or ref.lower() == "application":
                continue
            oc, oout, _ = _run(["flatpak", "override", "--user", "--show", ref], timeout=4.0)
            summary = _parse_override_blob(oout if oc == 0 else "")
            # Also peek metadata for default permissions
            apps.append(
                {
                    "id": ref,
                    "label": name or ref,
                    "microphone": "allow" if summary["pulseaudio"] else "deny",
                    "camera": "allow" if summary["devices"] else "deny",
                    "filesystemHome": bool(summary["filesystem_home"]),
                    "screen": "ask",
                    "screenHint": "Portal prompts · not override-gated",
                }
            )
    print(json.dumps({"ok": True, "available": True, "apps": apps, "error": err if code else ""}))
    return 0


def _apply_flatpak_category(ref: str, category: str, state: str) -> tuple[bool, str]:
    if category not in FLATPAK_MAPPABLE:
        return False, f"{category} is store-only (no Flatpak override)"
    if state == "ask":
        return True, "ask leaves Flatpak sandbox unchanged"
    if category == "microphone":
        flag = "--socket=pulseaudio" if state == "allow" else "--nosocket=pulseaudio"
        code, _, err = _run(["flatpak", "override", "--user", flag, ref], timeout=8.0)
        return code == 0, err or ("ok" if code == 0 else "override failed")
    if category == "camera":
        if state == "deny":
            # Hard device deny; re-add dri so GPU apps keep working.
            code1, _, err1 = _run(
                ["flatpak", "override", "--user", "--nodevice=all", ref], timeout=8.0
            )
            code2, _, err2 = _run(
                ["flatpak", "override", "--user", "--device=dri", ref], timeout=8.0
            )
            ok = code1 == 0 and code2 == 0
            return ok, (err1 or err2 or ("ok" if ok else "override failed"))
        # allow: clear nodevice=all if present; ensure device access
        code, _, err = _run(
            ["flatpak", "override", "--user", "--device=all", ref], timeout=8.0
        )
        return code == 0, err or ("ok" if code == 0 else "override failed")
    return False, "unmapped"


def cmd_flatpak_set(args: argparse.Namespace) -> int:
    if not _flatpak_available():
        print(json.dumps({"ok": False, "error": "flatpak not installed"}))
        return 1
    ref = str(args.ref).strip()
    cat = str(args.category)
    state = str(args.state).lower()
    if not ref:
        print(json.dumps({"ok": False, "error": "empty flatpak ref"}))
        return 1
    if cat not in CATEGORIES:
        print(json.dumps({"ok": False, "error": f"unknown category: {cat}"}))
        return 1
    if state not in STATES:
        print(json.dumps({"ok": False, "error": "state must be allow|ask|deny"}))
        return 1
    # Always persist in store under the flatpak application id
    data = load_store()
    apps = data.setdefault("apps", {})
    grants = dict(apps.get(ref) or {})
    grants[cat] = state
    apps[ref] = grants
    save_store(data)
    applied = False
    msg = "stored"
    if cat in FLATPAK_MAPPABLE:
        applied, msg = _apply_flatpak_category(ref, cat, state)
        if state != "ask" and not applied:
            print(json.dumps({"ok": False, "error": msg, "app": ref, "category": cat, "state": state}))
            return 1
    else:
        msg = "store-only (no Flatpak override map)"
    print(
        json.dumps(
            {
                "ok": True,
                "app": ref,
                "category": cat,
                "state": state,
                "flatpakApplied": applied and state != "ask",
                "hint": msg,
            }
        )
    )
    return 0


def cmd_granted(args: argparse.Namespace) -> int:
    data = load_store()
    aid = normalize_app_id(args.app)
    cat = str(args.category)
    if cat not in CATEGORIES:
        print(json.dumps({"ok": False, "error": f"unknown category: {cat}"}))
        return 1
    g = granted(data, aid, cat)
    print(
        json.dumps(
            {
                "ok": True,
                "app": aid,
                "category": cat,
                "grant": app_grant(data, aid, cat),
                "granted": g,
            }
        )
    )
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="Proteus app permissions")
    sub = ap.add_subparsers(dest="cmd", required=True)

    sub.add_parser("store-get", help="Print permissions.json")
    p_sc = sub.add_parser("store-set-category", help="Set global category allow|deny")
    p_sc.add_argument("category")
    p_sc.add_argument("state")

    p_sa = sub.add_parser("store-set-app", help="Set per-app grant allow|ask|deny")
    p_sa.add_argument("app")
    p_sa.add_argument("category")
    p_sa.add_argument("state")

    sub.add_parser("activity", help="In-use mic/camera/screen + apps")

    sub.add_parser("flatpak-list", help="List user Flatpaks + override summary")
    p_fs = sub.add_parser("flatpak-set", help="Set Flatpak + store grant")
    p_fs.add_argument("ref")
    p_fs.add_argument("category")
    p_fs.add_argument("state")

    p_g = sub.add_parser("granted", help="Query adaptive grant (allow only)")
    p_g.add_argument("app")
    p_g.add_argument("category")

    args = ap.parse_args()
    dispatch = {
        "store-get": cmd_store_get,
        "store-set-category": cmd_store_set_category,
        "store-set-app": cmd_store_set_app,
        "activity": cmd_activity,
        "flatpak-list": cmd_flatpak_list,
        "flatpak-set": cmd_flatpak_set,
        "granted": cmd_granted,
    }
    return dispatch[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
