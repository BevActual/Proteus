#!/usr/bin/env python3
"""Thin Headscale remote admin for Proteus Settings → Network.

Controls a *remote* Headscale control plane over HTTPS (Bearer API key).
Does not install or run Headscale on this machine.

Commands:
  status                 — URL + key present + optional /version + node count
  nodes                  — list nodes (GET /api/v1/node)
  expire <node-id>       — expire now (POST …/expire)
  enable <node-id>       — clear expiry (POST …/expire {"disableExpiry": true})
  set-key                — read API key from stdin; vault 0600
  clear-key              — remove vault key
  key-status             — whether a key is stored (never prints the key)

Stdout: one JSON object. Never logs the API key.
Honesty: ACL/policy · user CRUD · preauth keys · DNS/routes · server install Out.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

VAULT_DIR = Path.home() / ".local" / "share" / "proteus" / "headscale"
KEY_PATH = VAULT_DIR / "api-key"


def _out(obj: dict) -> int:
    print(json.dumps(obj))
    return 0 if obj.get("ok") else 1


def _read_key() -> str:
    try:
        return KEY_PATH.read_text(encoding="utf-8").strip()
    except FileNotFoundError:
        return ""
    except Exception:
        return ""


def _admin_url() -> str:
    # Prefer explicit env (tests); else settings-adjacent env; else empty.
    for env in ("PROTEUS_HEADSCALE_ADMIN_URL", "HEADSCALE_CLI_ADDRESS"):
        v = (os.environ.get(env) or "").strip()
        if v:
            return v.rstrip("/")
    # Optional side file written by Settings apply (keeps script usable without QML).
    url_path = VAULT_DIR / "admin-url"
    try:
        return url_path.read_text(encoding="utf-8").strip().rstrip("/")
    except Exception:
        return ""


def _write_admin_url(url: str) -> None:
    VAULT_DIR.mkdir(parents=True, exist_ok=True)
    path = VAULT_DIR / "admin-url"
    path.write_text((url or "").strip().rstrip("/") + "\n", encoding="utf-8")
    os.chmod(path, 0o600)


def _http(
    method: str,
    url: str,
    *,
    headers: dict | None = None,
    body: bytes | None = None,
    timeout: float = 15.0,
) -> tuple[int, dict | list | None, str]:
    req = urllib.request.Request(url, data=body, headers=headers or {}, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
            if not raw.strip():
                return resp.status, {}, ""
            try:
                return resp.status, json.loads(raw), ""
            except Exception:
                return resp.status, None, raw[:200]
    except urllib.error.HTTPError as e:
        err = ""
        try:
            err = e.read().decode("utf-8", errors="replace")[:300]
        except Exception:
            err = str(e)
        return e.code, None, err
    except Exception as e:
        return 0, None, str(e)


def _normalize_node(n: dict) -> dict:
    if not isinstance(n, dict):
        return {}
    nid = n.get("id")
    if nid is None:
        nid = n.get("nodeId") or n.get("ID") or ""
    name = (
        n.get("givenName")
        or n.get("name")
        or n.get("hostname")
        or n.get("Name")
        or ""
    )
    ips = n.get("ipAddresses") or n.get("ip_addresses") or n.get("ips") or []
    if isinstance(ips, str):
        ips = [ips]
    user = n.get("user") or n.get("userName") or ""
    if isinstance(user, dict):
        user = user.get("name") or user.get("displayName") or ""
    online = n.get("online")
    if online is None:
        online = n.get("Online")
    return {
        "id": str(nid),
        "name": str(name),
        "ips": [str(x) for x in ips if x],
        "online": bool(online),
        "lastSeen": str(n.get("lastSeen") or n.get("last_seen") or ""),
        "expiry": str(n.get("expiry") or n.get("expiration") or ""),
        "user": str(user or ""),
    }


def cmd_set_key() -> dict:
    key = sys.stdin.read().strip()
    if not key:
        return {"ok": False, "error": "empty API key on stdin"}
    VAULT_DIR.mkdir(parents=True, exist_ok=True)
    KEY_PATH.write_text(key + "\n", encoding="utf-8")
    os.chmod(KEY_PATH, 0o600)
    return {"ok": True, "action": "set-key", "hasKey": True}


def cmd_clear_key() -> dict:
    try:
        if KEY_PATH.exists():
            KEY_PATH.unlink()
    except Exception as e:
        return {"ok": False, "error": str(e)}
    return {"ok": True, "action": "clear-key", "hasKey": False}


def cmd_key_status() -> dict:
    return {"ok": True, "hasKey": bool(_read_key()), "vault": str(KEY_PATH)}


def cmd_set_url(url: str) -> dict:
    u = (url or "").strip().rstrip("/")
    _write_admin_url(u)
    return {"ok": True, "action": "set-url", "url": u}


def cmd_status() -> dict:
    if os.environ.get("PROTEUS_HEADSCALE_FIXTURE") == "1":
        return {
            "ok": True,
            "fixture": True,
            "url": "https://headscale.example.com",
            "hasKey": True,
            "reachable": True,
            "version": "fixture",
            "nodeCount": 2,
        }
    url = _admin_url()
    has_key = bool(_read_key())
    out: dict = {
        "ok": True,
        "url": url,
        "hasKey": has_key,
        "reachable": False,
        "version": "",
        "nodeCount": 0,
        "hint": "",
    }
    if not url:
        out["hint"] = "Set Headscale admin URL in Settings → Network → Headscale"
        return out
    # Unauthenticated version probe
    status, data, err = _http("GET", f"{url}/version")
    if status == 200:
        out["reachable"] = True
        if isinstance(data, dict):
            out["version"] = str(data.get("version") or data.get("Version") or "")
        elif isinstance(data, str):
            out["version"] = data
    elif status:
        out["hint"] = f"/version HTTP {status}: {err}"
    else:
        out["hint"] = err or "unreachable"
    if has_key:
        nodes = cmd_nodes()
        if nodes.get("ok"):
            out["nodeCount"] = len(nodes.get("nodes") or [])
            out["reachable"] = True
        elif not out["hint"]:
            out["hint"] = str(nodes.get("error") or "")
    elif not out["hint"]:
        out["hint"] = "API key not set (vault)"
    return out


def cmd_nodes() -> dict:
    if os.environ.get("PROTEUS_HEADSCALE_FIXTURE") == "1":
        return {
            "ok": True,
            "fixture": True,
            "nodes": [
                {
                    "id": "1",
                    "name": "fixture-laptop",
                    "ips": ["100.64.0.1"],
                    "online": True,
                    "lastSeen": "2026-08-02T00:00:00Z",
                    "expiry": "",
                    "user": "alice",
                },
                {
                    "id": "2",
                    "name": "fixture-phone",
                    "ips": ["100.64.0.2"],
                    "online": False,
                    "lastSeen": "2026-08-01T12:00:00Z",
                    "expiry": "2026-08-01T12:00:00Z",
                    "user": "alice",
                },
            ],
        }
    url = _admin_url()
    key = _read_key()
    if not url:
        return {"ok": False, "error": "admin URL not set", "nodes": []}
    if not key:
        return {"ok": False, "error": "API key not set", "nodes": []}
    status, data, err = _http(
        "GET",
        f"{url}/api/v1/node",
        headers={"Authorization": f"Bearer {key}", "Accept": "application/json"},
    )
    if status != 200 or data is None:
        return {
            "ok": False,
            "error": err or f"nodes HTTP {status}",
            "nodes": [],
        }
    raw_nodes = []
    if isinstance(data, dict):
        raw_nodes = data.get("nodes") or data.get("Nodes") or data.get("node") or []
        if isinstance(raw_nodes, dict):
            raw_nodes = [raw_nodes]
    elif isinstance(data, list):
        raw_nodes = data
    nodes = [_normalize_node(n) for n in raw_nodes if isinstance(n, dict)]
    nodes = [n for n in nodes if n.get("id")]
    return {"ok": True, "nodes": nodes, "url": url}


def cmd_expire(node_id: str, *, enable: bool = False) -> dict:
    if os.environ.get("PROTEUS_HEADSCALE_FIXTURE") == "1":
        return {
            "ok": True,
            "fixture": True,
            "action": "enable" if enable else "expire",
            "id": str(node_id),
        }
    url = _admin_url()
    key = _read_key()
    nid = str(node_id or "").strip()
    if not url:
        return {"ok": False, "error": "admin URL not set"}
    if not key:
        return {"ok": False, "error": "API key not set"}
    if not nid:
        return {"ok": False, "error": "node id required"}
    body = None
    if enable:
        body = json.dumps({"disableExpiry": True}).encode()
    status, data, err = _http(
        "POST",
        f"{url}/api/v1/node/{urllib.parse.quote(nid, safe='')}/expire",
        headers={
            "Authorization": f"Bearer {key}",
            "Accept": "application/json",
            "Content-Type": "application/json",
        },
        body=body if body is not None else b"{}",
    )
    if status not in (200, 201):
        return {
            "ok": False,
            "error": err or f"expire HTTP {status}",
            "action": "enable" if enable else "expire",
            "id": nid,
        }
    return {
        "ok": True,
        "action": "enable" if enable else "expire",
        "id": nid,
        "node": _normalize_node(data.get("node") if isinstance(data, dict) else {})
        if isinstance(data, dict)
        else {},
    }


def main() -> int:
    ap = argparse.ArgumentParser(description="Proteus Headscale remote admin")
    sub = ap.add_subparsers(dest="cmd", required=True)

    sub.add_parser("status")
    sub.add_parser("nodes")
    sub.add_parser("key-status")
    sub.add_parser("set-key")
    sub.add_parser("clear-key")

    p_url = sub.add_parser("set-url")
    p_url.add_argument("url")

    p_exp = sub.add_parser("expire")
    p_exp.add_argument("node_id")

    p_en = sub.add_parser("enable")
    p_en.add_argument("node_id")

    args = ap.parse_args()
    if args.cmd == "status":
        return _out(cmd_status())
    if args.cmd == "nodes":
        return _out(cmd_nodes())
    if args.cmd == "key-status":
        return _out(cmd_key_status())
    if args.cmd == "set-key":
        return _out(cmd_set_key())
    if args.cmd == "clear-key":
        return _out(cmd_clear_key())
    if args.cmd == "set-url":
        return _out(cmd_set_url(args.url))
    if args.cmd == "expire":
        return _out(cmd_expire(args.node_id, enable=False))
    if args.cmd == "enable":
        return _out(cmd_expire(args.node_id, enable=True))
    return _out({"ok": False, "error": "unknown command"})


if __name__ == "__main__":
    sys.exit(main())
