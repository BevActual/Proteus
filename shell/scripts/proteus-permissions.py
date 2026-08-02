#!/usr/bin/env python3
"""Proteus app permissions — store + Flatpak + portal sync + capture enforce.

Store: ~/.config/proteus/permissions.json
Activity: delegates to privacy-indicators.py (SoT for in-use).
Flatpak: best-effort `flatpak override --user` for mappable categories.
Portal: PermissionStore SetPermission for devices/microphone|camera (+ screen best-effort);
best-effort org.freedesktop.portal.Session.Close for screencast sessions on Deny/Ask.
Capture: pactl mute denied mic source-outputs; PipeWire destroy denied camera
and screencast-like streams (Deny + Ask; session Allow-once).

Honesty: not a full OS sandbox (no AppArmor/v4l2 ACL). Screen kill is best-effort
(portal Session.Close + PW heuristic; attribution imperfect). QML fail-closes until
Permissions.ready — this CLI always reads the on-disk store.
"""
from __future__ import annotations

import argparse
import json
import os
import re
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

PORTAL_DEST = "org.freedesktop.impl.portal.PermissionStore"
PORTAL_PATH = "/org/freedesktop/impl/portal/PermissionStore"
PORTAL_IFACE = "org.freedesktop.impl.portal.PermissionStore"

PORTAL_DESKTOP_DEST = "org.freedesktop.portal.Desktop"
PORTAL_DESKTOP_PATH = "/org/freedesktop/portal/desktop"
PORTAL_SESSION_IFACE = "org.freedesktop.portal.Session"

# Category → PermissionStore (table, resource id)
PORTAL_MAP = {
    "microphone": ("devices", "microphone"),
    "camera": ("devices", "camera"),
    "screen": ("screencast", "all"),
}


def store_path() -> Path:
    return Path.home() / ".config" / "proteus" / "permissions.json"


def session_path() -> Path:
    """Ephemeral Allow-once grants written by Permissions.qml (not the durable store)."""
    runtime = os.environ.get("XDG_RUNTIME_DIR", "").strip()
    if runtime:
        return Path(runtime) / "proteus" / "permissions-session.json"
    return Path.home() / ".local" / "state" / "proteus" / "permissions-session.json"


def load_session_allows() -> set[str]:
    """Keys 'appId\\tcategory' from session file."""
    path = session_path()
    if not path.is_file():
        return set()
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return set()
    out: set[str] = set()
    for item in raw.get("grants") or []:
        s = str(item or "").strip()
        if "\t" in s:
            out.add(s)
    return out


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


def _portal_available() -> bool:
    code, _, _ = _run(
        [
            "gdbus",
            "call",
            "--session",
            "--dest",
            PORTAL_DEST,
            "--object-path",
            PORTAL_PATH,
            "--method",
            "org.freedesktop.DBus.Peer.Ping",
        ],
        timeout=2.0,
    )
    return code == 0


def _portal_perm_list(state: str) -> list[str]:
    st = str(state).lower()
    if st == "allow":
        return ["yes"]
    if st == "deny":
        return ["no"]
    return ["ask"]


def _gdbus_as(strings: list[str]) -> str:
    # gdbus CLI array-of-string literal: "['yes']"
    inner = ", ".join("'" + s.replace("'", "'\\''") + "'" for s in strings)
    return f"[{inner}]"


def portal_set_permission(table: str, resource: str, app: str, state: str) -> tuple[bool, str]:
    aid = normalize_app_id(app)
    if not aid:
        return False, "empty app id"
    if not _portal_available():
        return False, "portal PermissionStore unavailable"
    perms = _portal_perm_list(state)
    code, out, err = _run(
        [
            "gdbus",
            "call",
            "--session",
            "--dest",
            PORTAL_DEST,
            "--object-path",
            PORTAL_PATH,
            "--method",
            f"{PORTAL_IFACE}.SetPermission",
            table,
            "true",
            resource,
            aid,
            _gdbus_as(perms),
        ],
        timeout=4.0,
    )
    if code != 0:
        return False, err or out or "SetPermission failed"
    return True, "ok"


def portal_delete_permission(table: str, resource: str, app: str) -> tuple[bool, str]:
    aid = normalize_app_id(app)
    if not aid:
        return False, "empty app id"
    if not _portal_available():
        return False, "portal PermissionStore unavailable"
    code, out, err = _run(
        [
            "gdbus",
            "call",
            "--session",
            "--dest",
            PORTAL_DEST,
            "--object-path",
            PORTAL_PATH,
            "--method",
            f"{PORTAL_IFACE}.DeletePermission",
            table,
            resource,
            aid,
        ],
        timeout=4.0,
    )
    if code != 0:
        return False, err or out or "DeletePermission failed"
    return True, "ok"


def sync_portal_for_app(data: dict, app_id: str, cat: str) -> dict:
    """Write one app×category into PermissionStore when mapped."""
    if cat not in PORTAL_MAP:
        return {"synced": False, "reason": "unmapped"}
    table, resource = PORTAL_MAP[cat]
    grant = app_grant(data, app_id, cat)
    if grant == "ask":
        # Leave portal prompt behavior; clear sticky yes/no if we set one earlier.
        ok, msg = portal_delete_permission(table, resource, app_id)
        return {"synced": ok, "action": "delete", "hint": msg, "grant": grant}
    ok, msg = portal_set_permission(table, resource, app_id, grant)
    return {"synced": ok, "action": "set", "hint": msg, "grant": grant}


def sync_portal_store(data: dict | None = None, category: str | None = None) -> dict:
    """Best-effort sync of store apps (and activity ids) to portal tables."""
    data = data or load_store()
    available = _portal_available()
    results = []
    if not available:
        return {"ok": True, "portalAvailable": False, "synced": 0, "results": []}
    cats = [category] if category else list(PORTAL_MAP.keys())
    apps = set((data.get("apps") or {}).keys())
    for aid in sorted(apps):
        for cat in cats:
            if cat not in PORTAL_MAP:
                continue
            # Only sync when app has an override or category is deny (tighten).
            row = (data.get("apps") or {}).get(aid) or {}
            if cat not in row and category_state(data, cat) != "deny":
                continue
            r = sync_portal_for_app(data, aid, cat)
            r["app"] = aid
            r["category"] = cat
            results.append(r)
    # Category deny with no per-app rows: nothing to stamp (portal is per-app).
    synced = sum(1 for r in results if r.get("synced"))
    return {
        "ok": True,
        "portalAvailable": True,
        "synced": synced,
        "attempted": len(results),
        "results": results,
    }


def _portal_desktop_available() -> bool:
    code, _, _ = _run(
        [
            "gdbus",
            "call",
            "--session",
            "--dest",
            PORTAL_DESKTOP_DEST,
            "--object-path",
            PORTAL_DESKTOP_PATH,
            "--method",
            "org.freedesktop.DBus.Peer.Ping",
        ],
        timeout=2.0,
    )
    return code == 0


def _list_portal_session_paths() -> list[str]:
    """Best-effort list of portal Session object paths under Desktop."""
    paths: list[str] = []
    code, out, _ = _run(
        ["busctl", "--user", "tree", PORTAL_DESKTOP_DEST], timeout=3.0
    )
    blob = out if code == 0 else ""
    if not blob.strip():
        code2, out2, _ = _run(
            [
                "gdbus",
                "introspect",
                "--session",
                "--dest",
                PORTAL_DESKTOP_DEST,
                "--object-path",
                PORTAL_DESKTOP_PATH,
                "--recurse",
            ],
            timeout=4.0,
        )
        blob = out2 if code2 == 0 else ""
    for line in blob.splitlines():
        for tok in re.findall(
            r"/org/freedesktop/portal/desktop/session/[^\s\"']+", line
        ):
            tok = tok.rstrip(".,;)}")
            # Prefer leaf sessions (…/session/<sender>/<id>), skip bare …/session
            parts = [p for p in tok.split("/") if p]
            if len(parts) >= 6 and tok not in paths:
                paths.append(tok)
    return paths


def _session_matches_app(path: str, app_id: str) -> bool:
    if not app_id:
        return False
    p = path.lower()
    a = normalize_app_id(app_id).lower()
    if not a:
        return False
    if a in p:
        return True
    if a.replace(".", "_") in p:
        return True
    if a.replace(".", "-") in p:
        return True
    tail = a.rsplit(".", 1)[-1]
    return bool(tail) and len(tail) >= 4 and tail in p


def _portal_session_close(path: str) -> tuple[bool, str]:
    code, out, err = _run(
        [
            "gdbus",
            "call",
            "--session",
            "--dest",
            PORTAL_DESKTOP_DEST,
            "--object-path",
            path,
            "--method",
            f"{PORTAL_SESSION_IFACE}.Close",
        ],
        timeout=3.0,
    )
    if code != 0:
        return False, err or out or "Session.Close failed"
    return True, "ok"


def portal_close_screencast_sessions(
    data: dict,
    session_allows: set[str] | None = None,
    *,
    prefer_app: str = "",
) -> list[dict]:
    """Best-effort Session.Close for portal sessions when screen is Deny/Ask.

    Category deny → close all discoverable sessions. Per-app Deny/Ask → close
    sessions whose path matches the app id (heuristic). When prefer_app is set
    and blocked, close matching sessions or all sessions if none match (helps
    release restore tokens after an explicit store deny).
    """
    if os.environ.get("PROTEUS_PORTAL_SESSION_FIXTURE") == "1":
        return [
            {
                "kind": "portalScreen",
                "session": "/org/freedesktop/portal/desktop/session/fixture/u1",
                "app": prefer_app or "fixture.app",
                "closed": True,
                "fixture": True,
                "error": "",
            }
        ]

    allows = session_allows if session_allows is not None else load_session_allows()
    if not _portal_desktop_available():
        return []

    paths = _list_portal_session_paths()
    if not paths:
        return []

    cat_deny = category_state(data, "screen") == "deny"
    blocked_apps: list[str] = []
    for aid in (data.get("apps") or {}):
        if capture_should_block(data, aid, "screen", allows):
            blocked_apps.append(aid)
    pref = normalize_app_id(prefer_app)
    if pref and capture_should_block(data, pref, "screen", allows) and pref not in blocked_apps:
        blocked_apps.append(pref)

    if not cat_deny and not blocked_apps:
        return []

    actions: list[dict] = []
    matched_any = False
    pending: list[tuple[str, str]] = []  # path, app label

    for path in paths:
        if cat_deny:
            pending.append((path, ""))
            continue
        matched = ""
        for aid in blocked_apps:
            if _session_matches_app(path, aid):
                matched = aid
                break
        if matched:
            matched_any = True
            pending.append((path, matched))

    if (
        not cat_deny
        and not matched_any
        and pref
        and capture_should_block(data, pref, "screen", allows)
    ):
        # Explicit deny/ask for this app: release portal tokens best-effort.
        pending = [(path, pref) for path in paths]

    for path, app_label in pending:
        ok, msg = _portal_session_close(path)
        actions.append(
            {
                "kind": "portalScreen",
                "session": path,
                "app": app_label,
                "closed": ok,
                "error": "" if ok else msg,
                "reason": "category-deny" if cat_deny and not app_label else "deny-or-ask",
            }
        )
    return actions


def _source_outputs() -> list[dict]:
    """Parse pactl list source-outputs → [{index, name, binary}]."""
    code, out, _ = _run(["pactl", "list", "source-outputs"], timeout=3.0)
    if code != 0 or not out:
        return []
    rows: list[dict] = []
    cur: dict | None = None
    for line in out.splitlines():
        if line.startswith("Source Output #"):
            if cur:
                rows.append(cur)
            m = re.search(r"#(\d+)", line)
            cur = {
                "index": int(m.group(1)) if m else -1,
                "name": "",
                "binary": "",
            }
            continue
        if cur is None:
            continue
        s = line.strip()
        if s.startswith("application.name ="):
            cur["name"] = s.split("=", 1)[-1].strip().strip('"')
        elif s.startswith("application.process.binary ="):
            cur["binary"] = s.split("=", 1)[-1].strip().strip('"')
    if cur:
        rows.append(cur)
    return rows


def _resolve_desktop_id(app_name: str, binary: str) -> str:
    # Keep local (do not import privacy-indicators — keep CLI light).
    candidates = []
    for raw in (app_name, binary, Path(binary).name if binary else ""):
        s = (raw or "").strip()
        if not s:
            continue
        candidates.extend([s, s.lower(), s.replace(" ", "-").lower()])
    home = Path.home()
    dirs = [home / ".local/share/applications"]
    for part in os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":"):
        if part:
            dirs.append(Path(part) / "applications")
    seen: set[str] = set()
    for c in candidates:
        if c in seen:
            continue
        seen.add(c)
        for d in dirs:
            for fname in (c + ".desktop", c):
                p = d / fname if str(fname).endswith(".desktop") else d / (str(fname) + ".desktop")
                if p.is_file():
                    return p.name[: -len(".desktop")]
    blob = f"{app_name} {binary}".lower()
    if "chromium" in blob:
        return "chromium"
    if "firefox" in blob:
        return "firefox"
    if "chrome" in blob:
        return "google-chrome"
    return ""


def capture_should_block(
    data: dict,
    desk: str,
    category: str,
    session_allows: set[str] | None = None,
) -> bool:
    """Active capture enforce: Deny + Ask block; Allow / session once-grant pass.

    Mid-session Ask dialog (PrivacyAsk.promptCapture) + session file lets
    Allow once skip mute/destroy. Unknown desktop id: category Deny only.
    """
    if desk:
        key = f"{normalize_app_id(desk)}\t{category}"
        allows = session_allows if session_allows is not None else load_session_allows()
        if key in allows:
            return False
        return app_grant(data, desk, category) in ("deny", "ask")
    return category_state(data, category) == "deny"


def enforce_mic(data: dict, session_allows: set[str] | None = None) -> list[dict]:
    actions = []
    allows = session_allows if session_allows is not None else load_session_allows()
    for row in _source_outputs():
        idx = int(row.get("index", -1))
        if idx < 0:
            continue
        desk = _resolve_desktop_id(str(row.get("name") or ""), str(row.get("binary") or ""))
        # Category deny → mute everyone; per-app Deny + Ask mute active captures.
        if not capture_should_block(data, desk, "microphone", allows):
            continue
        code, _, err = _run(["pactl", "set-source-output-mute", str(idx), "1"], timeout=2.0)
        actions.append(
            {
                "kind": "microphone",
                "index": idx,
                "app": desk or str(row.get("binary") or row.get("name") or ""),
                "muted": code == 0,
                "error": err if code else "",
                "reason": app_grant(data, desk, "microphone") if desk else "category-deny",
            }
        )
    return actions


def enforce_camera(data: dict, session_allows: set[str] | None = None) -> list[dict]:
    """Best-effort: destroy running PipeWire Stream/Input/Video nodes for Deny/Ask apps."""
    actions = []
    allows = session_allows if session_allows is not None else load_session_allows()
    code, raw, _ = _run(["pw-dump"], timeout=3.0)
    if code != 0 or not raw.strip():
        return actions
    try:
        dump = json.loads(raw)
    except Exception:
        return actions
    if not isinstance(dump, list):
        return actions
    for obj in dump:
        info = obj.get("info") or {}
        props = info.get("props") or {}
        state = str(info.get("state") or "").lower()
        if state != "running":
            continue
        mc = str(props.get("media.class") or "")
        if "Stream/Input/Video" not in mc:
            continue
        app_name = str(props.get("application.name") or props.get("node.name") or "")
        binary = str(props.get("application.process.binary") or "")
        desk = _resolve_desktop_id(app_name, binary)
        if not capture_should_block(data, desk, "camera", allows):
            continue
        nid = obj.get("id")
        if nid is None:
            continue
        c2, _, err = _run(["pw-cli", "destroy", str(nid)], timeout=2.0)
        actions.append(
            {
                "kind": "camera",
                "node": nid,
                "app": desk or binary or app_name,
                "destroyed": c2 == 0,
                "error": err if c2 else "",
                "reason": app_grant(data, desk, "camera") if desk else "category-deny",
            }
        )
    return actions


_SCREEN_TOKENS = (
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


def _is_screencast_node(props: dict) -> bool:
    """Match privacy-indicators.screen_apps heuristics (token + video/stream/source)."""
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
    hit = any(t in blob for t in _SCREEN_TOKENS) and (
        "video" in blob or "stream" in blob or "source" in blob
    )
    hit = hit or (
        mc == "Stream/Input/Video"
        and ("xdp" in blob or "portal" in blob or "screencopy" in blob)
    )
    return hit


def enforce_screen(data: dict, session_allows: set[str] | None = None) -> list[dict]:
    """Best-effort: destroy running PipeWire screencast-like nodes for Deny/Ask apps."""
    actions = []
    allows = session_allows if session_allows is not None else load_session_allows()
    code, raw, _ = _run(["pw-dump"], timeout=3.0)
    if code != 0 or not raw.strip():
        return actions
    try:
        dump = json.loads(raw)
    except Exception:
        return actions
    if not isinstance(dump, list):
        return actions
    for obj in dump:
        info = obj.get("info") or {}
        props = info.get("props") or {}
        state = str(info.get("state") or "").lower()
        if state != "running":
            continue
        if not _is_screencast_node(props):
            continue
        app_name = str(props.get("application.name") or props.get("node.name") or "")
        binary = str(props.get("application.process.binary") or "")
        if not app_name and not binary:
            app_name = str(
                props.get("node.description") or props.get("node.name") or "Screen capture"
            )
        desk = _resolve_desktop_id(app_name, binary)
        if not capture_should_block(data, desk, "screen", allows):
            continue
        nid = obj.get("id")
        if nid is None:
            continue
        c2, _, err = _run(["pw-cli", "destroy", str(nid)], timeout=2.0)
        actions.append(
            {
                "kind": "screen",
                "node": nid,
                "app": desk or binary or app_name,
                "destroyed": c2 == 0,
                "error": err if c2 else "",
                "reason": app_grant(data, desk, "screen") if desk else "category-deny",
            }
        )
    return actions


def cmd_portal_sync(args: argparse.Namespace) -> int:
    cat = str(args.category) if getattr(args, "category", None) else ""
    data = load_store()
    out = sync_portal_store(data, category=cat if cat in PORTAL_MAP else None)
    print(json.dumps(out))
    return 0


def cmd_enforce_capture(_: argparse.Namespace) -> int:
    data = load_store()
    session = load_session_allows()
    portal_scr = portal_close_screencast_sessions(data, session)
    mic = enforce_mic(data, session)
    cam = enforce_camera(data, session)
    scr = enforce_screen(data, session)
    print(
        json.dumps(
            {
                "ok": True,
                "microphone": mic,
                "camera": cam,
                "screen": scr,
                "portalScreen": portal_scr,
                "muted": sum(1 for a in mic if a.get("muted")),
                "destroyed": sum(
                    1 for a in (cam + scr) if a.get("destroyed")
                ),
                "portalClosed": sum(1 for a in portal_scr if a.get("closed")),
            }
        )
    )
    return 0


def _after_store_mutate(data: dict, category: str | None = None) -> dict:
    portal = sync_portal_store(data, category=category if category in PORTAL_MAP else None)
    portal_scr: list[dict] = []
    if not category or category == "screen":
        portal_scr = portal_close_screencast_sessions(data)
    enforce = {
        "microphone": enforce_mic(data) if (not category or category == "microphone") else [],
        "camera": enforce_camera(data) if (not category or category == "camera") else [],
        "screen": enforce_screen(data) if (not category or category == "screen") else [],
        "portalScreen": portal_scr,
    }
    return {"portal": portal, "enforce": enforce}


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
    extra = _after_store_mutate(data, category=cat)
    print(json.dumps({"ok": True, "category": cat, "state": state, **extra}))
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
    portal_one = sync_portal_for_app(data, aid, cat) if cat in PORTAL_MAP else {"synced": False}
    portal_scr = (
        portal_close_screencast_sessions(data, prefer_app=aid) if cat == "screen" else []
    )
    enforce = {
        "microphone": enforce_mic(data) if cat == "microphone" else [],
        "camera": enforce_camera(data) if cat == "camera" else [],
        "screen": enforce_screen(data) if cat == "screen" else [],
        "portalScreen": portal_scr,
    }
    print(
        json.dumps(
            {
                "ok": True,
                "app": aid,
                "category": cat,
                "state": state,
                "portal": portal_one,
                "enforce": enforce,
            }
        )
    )
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
    portal_one = sync_portal_for_app(data, ref, cat) if cat in PORTAL_MAP else {"synced": False}
    enforce = {
        "microphone": enforce_mic(data) if cat == "microphone" else [],
        "camera": enforce_camera(data) if cat == "camera" else [],
        "screen": enforce_screen(data) if cat == "screen" else [],
    }
    print(
        json.dumps(
            {
                "ok": True,
                "app": ref,
                "category": cat,
                "state": state,
                "flatpakApplied": applied and state != "ask",
                "hint": msg,
                "portal": portal_one,
                "enforce": enforce,
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

    p_ps = sub.add_parser("portal-sync", help="Sync store apps → portal PermissionStore")
    p_ps.add_argument("category", nargs="?", default="", help="optional: microphone|camera|screen")

    sub.add_parser(
        "enforce-capture",
        help="Mute/destroy active mic/camera/screen captures that violate Deny or Ask",
    )

    args = ap.parse_args()
    dispatch = {
        "store-get": cmd_store_get,
        "store-set-category": cmd_store_set_category,
        "store-set-app": cmd_store_set_app,
        "activity": cmd_activity,
        "flatpak-list": cmd_flatpak_list,
        "flatpak-set": cmd_flatpak_set,
        "granted": cmd_granted,
        "portal-sync": cmd_portal_sync,
        "enforce-capture": cmd_enforce_capture,
    }
    return dispatch[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
