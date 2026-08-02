#!/usr/bin/env python3
"""Create / update / delete CardDAV contacts for Proteus Online accounts seats.

Writable: carddav · apple (Basic auth via proteus-accounts token).

Thin UX: display name + one email. No photos · groups · full vCard · OAuth
People APIs. Stdout: one JSON object. Never logs passwords/tokens.
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid
import xml.etree.ElementTree as ET
from pathlib import Path

WRITABLE = ("carddav", "apple")


def _run(cmd: list[str], timeout: float = 20.0) -> tuple[int, str, str]:
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return r.returncode, (r.stdout or "").strip(), (r.stderr or "").strip()
    except Exception as e:
        return 1, "", str(e)


def _accounts_bin() -> str:
    root = os.environ.get("PROTEUS_ROOT", "")
    candidates = []
    if root:
        candidates += [
            f"{root}/services/proteus-accounts/target/release/proteus-accounts",
            f"{root}/services/proteus-accounts/bin/proteus-accounts",
        ]
    here = Path(__file__).resolve()
    repo = here.parents[2] if len(here.parents) >= 2 else here.parent
    candidates += [
        str(repo / "services/proteus-accounts/target/release/proteus-accounts"),
        str(repo / "services/proteus-accounts/bin/proteus-accounts"),
        str(Path.home() / ".local/bin/proteus-accounts"),
        "/usr/local/bin/proteus-accounts",
    ]
    which = _run(["bash", "-lc", "command -v proteus-accounts"])
    if which[0] == 0 and which[1]:
        candidates.insert(0, which[1])
    for c in candidates:
        if c and os.path.isfile(c) and os.access(c, os.X_OK):
            return c
    return ""


def _token(provider: str) -> dict | None:
    bin_path = _accounts_bin()
    if not bin_path:
        return None
    code, out, err = _run([bin_path, "token", provider], timeout=25.0)
    if code != 0 or not out:
        return {"ok": False, "error": err or out or "token failed", "provider": provider}
    try:
        return json.loads(out)
    except Exception as e:
        return {"ok": False, "error": str(e), "provider": provider}


def _creds(provider: str, tok: dict) -> tuple[str, str, str]:
    password = str(tok.get("accessToken") or "")
    user = str(tok.get("username") or tok.get("email") or "").strip()
    if provider == "apple":
        base = str(tok.get("carddavUrl") or tok.get("baseUrl") or "").rstrip("/")
    else:
        base = str(tok.get("baseUrl") or "").rstrip("/")
    return f"{base}/", user, password


def _auth_header(user: str, password: str) -> str:
    return "Basic " + base64.b64encode(f"{user}:{password}".encode()).decode()


def _first_addressbook(home: str, user: str, password: str) -> tuple[str, str]:
    if not home or not user or not password:
        return "", "credentials incomplete"
    propfind = """<?xml version="1.0" encoding="UTF-8"?>
<d:propfind xmlns:d="DAV:" xmlns:card="urn:ietf:params:xml:ns:carddav">
  <d:prop><d:displayname/><d:resourcetype/></d:prop>
</d:propfind>
"""
    home = home if home.endswith("/") else f"{home}/"
    req = urllib.request.Request(
        home,
        data=propfind.encode(),
        method="PROPFIND",
        headers={
            "Authorization": _auth_header(user, password),
            "Depth": "1",
            "Content-Type": "application/xml; charset=utf-8",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=12) as resp:
            listing = resp.read().decode("utf-8", errors="replace")
    except Exception as e:
        return "", f"PROPFIND: {e}"
    try:
        root = ET.fromstring(listing)
        ns = {"d": "DAV:"}
        home_path = urllib.parse.urlparse(home).path.rstrip("/")
        for resp_el in root.findall("d:response", ns):
            href = resp_el.findtext("d:href", default="", namespaces=ns)
            if not href or not href.endswith("/"):
                continue
            if href.rstrip("/") == home_path:
                continue
            if href.startswith("http"):
                return href if href.endswith("/") else href + "/", ""
            parsed = urllib.parse.urlparse(home)
            path = href if href.endswith("/") else href + "/"
            return f"{parsed.scheme}://{parsed.netloc}{path}", ""
    except Exception:
        pass
    return home, ""


def _vcard(uid: str, name: str, email: str) -> str:
    fn = (name or "").replace("\\", "\\\\").replace(";", "\\;").replace(",", "\\,")
    em = (email or "").strip()
    lines = [
        "BEGIN:VCARD",
        "VERSION:3.0",
        f"UID:{uid}",
        f"FN:{fn or 'Untitled'}",
    ]
    if em:
        lines.append(f"EMAIL:{em}")
    lines.append("END:VCARD")
    return "\r\n".join(lines) + "\r\n"


def _uid_from_href(href: str) -> str:
    path = urllib.parse.urlparse(href).path
    base = path.rsplit("/", 1)[-1]
    for ext in (".vcf", ".vcard"):
        if base.lower().endswith(ext):
            base = base[: -len(ext)]
    return base.strip()


def cmd_create(provider: str, name: str, email: str) -> dict:
    name = (name or "").strip() or "Untitled"
    email = (email or "").strip()
    if provider not in WRITABLE:
        return {"ok": False, "error": f"provider {provider} is read-only", "action": "create"}
    tok = _token(provider)
    if tok is None:
        return {"ok": False, "error": "proteus-accounts not installed", "action": "create"}
    if not tok.get("ok"):
        return {
            "ok": False,
            "error": str(tok.get("error") or f"no {provider} seat"),
            "action": "create",
        }
    home, user, password = _creds(provider, tok)
    book, err = _first_addressbook(home, user, password)
    if err or not book:
        return {"ok": False, "error": err or "no addressbook", "action": "create"}
    uid = str(uuid.uuid4())
    put_url = book.rstrip("/") + f"/{uid}.vcf"
    body = _vcard(uid, name, email).encode()
    req = urllib.request.Request(
        put_url,
        data=body,
        method="PUT",
        headers={
            "Authorization": _auth_header(user, password),
            "Content-Type": "text/vcard; charset=utf-8",
            "If-None-Match": "*",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            status = resp.status
    except urllib.error.HTTPError as e:
        try:
            err_body = e.read().decode("utf-8", errors="replace")[:200]
        except Exception:
            err_body = str(e)
        return {
            "ok": False,
            "error": f"PUT HTTP {e.code}: {err_body}",
            "action": "create",
            "provider": provider,
        }
    except Exception as e:
        return {"ok": False, "error": str(e), "action": "create", "provider": provider}
    return {
        "ok": True,
        "action": "create",
        "provider": provider,
        "id": uid,
        "uid": uid,
        "href": put_url,
        "name": name,
        "email": email,
        "status": status,
        "mutable": True,
    }


def cmd_update(
    provider: str, href: str, name: str, email: str, uid: str = ""
) -> dict:
    href = (href or "").strip()
    name = (name or "").strip() or "Untitled"
    email = (email or "").strip()
    if provider not in WRITABLE:
        return {"ok": False, "error": f"provider {provider} is read-only", "action": "update"}
    if not href.startswith("http"):
        return {"ok": False, "error": "href required", "action": "update"}
    tok = _token(provider)
    if tok is None:
        return {"ok": False, "error": "proteus-accounts not installed", "action": "update"}
    if not tok.get("ok"):
        return {
            "ok": False,
            "error": str(tok.get("error") or f"no {provider} seat"),
            "action": "update",
        }
    _home, user, password = _creds(provider, tok)
    event_uid = (uid or "").strip() or _uid_from_href(href)
    if not event_uid:
        return {"ok": False, "error": "uid required", "action": "update"}
    body = _vcard(event_uid, name, email).encode()
    req = urllib.request.Request(
        href,
        data=body,
        method="PUT",
        headers={
            "Authorization": _auth_header(user, password),
            "Content-Type": "text/vcard; charset=utf-8",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            status = resp.status
    except urllib.error.HTTPError as e:
        try:
            err_body = e.read().decode("utf-8", errors="replace")[:200]
        except Exception:
            err_body = str(e)
        return {
            "ok": False,
            "error": f"PUT HTTP {e.code}: {err_body}",
            "action": "update",
            "provider": provider,
        }
    except Exception as e:
        return {"ok": False, "error": str(e), "action": "update", "provider": provider}
    return {
        "ok": True,
        "action": "update",
        "provider": provider,
        "id": event_uid,
        "uid": event_uid,
        "href": href,
        "name": name,
        "email": email,
        "status": status,
        "mutable": True,
    }


def cmd_delete(provider: str, href: str) -> dict:
    href = (href or "").strip()
    if provider not in WRITABLE:
        return {"ok": False, "error": f"provider {provider} is read-only", "action": "delete"}
    if not href.startswith("http"):
        return {"ok": False, "error": "href required", "action": "delete"}
    tok = _token(provider)
    if tok is None:
        return {"ok": False, "error": "proteus-accounts not installed", "action": "delete"}
    if not tok.get("ok"):
        return {
            "ok": False,
            "error": str(tok.get("error") or f"no {provider} seat"),
            "action": "delete",
        }
    _home, user, password = _creds(provider, tok)
    req = urllib.request.Request(
        href,
        method="DELETE",
        headers={"Authorization": _auth_header(user, password)},
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            status = resp.status
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return {
                "ok": True,
                "action": "delete",
                "provider": provider,
                "href": href,
                "status": 404,
                "hint": "already gone",
            }
        try:
            err_body = e.read().decode("utf-8", errors="replace")[:200]
        except Exception:
            err_body = str(e)
        return {
            "ok": False,
            "error": f"DELETE HTTP {e.code}: {err_body}",
            "action": "delete",
            "provider": provider,
        }
    except Exception as e:
        return {"ok": False, "error": str(e), "action": "delete", "provider": provider}
    return {
        "ok": True,
        "action": "delete",
        "provider": provider,
        "href": href,
        "status": status,
    }


def main() -> int:
    ap = argparse.ArgumentParser(description="Proteus contacts mutate (CardDAV)")
    ap.add_argument("action", choices=("create", "update", "delete", "providers"))
    ap.add_argument("--provider", default="")
    ap.add_argument("--name", default="Untitled")
    ap.add_argument("--email", default="")
    ap.add_argument("--href", default="")
    ap.add_argument("--uid", default="")
    args = ap.parse_args()

    if os.environ.get("PROTEUS_CONTACTS_MUTATE_FIXTURE") == "1":
        if args.action == "providers":
            print(json.dumps({"ok": True, "fixture": True, "providers": ["carddav"]}))
            return 0
        if args.action == "create":
            print(
                json.dumps(
                    {
                        "ok": True,
                        "fixture": True,
                        "action": "create",
                        "provider": args.provider or "carddav",
                        "id": "fixture-contact-uid",
                        "uid": "fixture-contact-uid",
                        "href": "https://cal.example/dav/addressbooks/alice/default/fixture-contact-uid.vcf",
                        "name": (args.name or "Untitled").strip() or "Untitled",
                        "email": (args.email or "").strip(),
                        "mutable": True,
                    }
                )
            )
            return 0
        if args.action == "update":
            href = args.href or (
                "https://cal.example/dav/addressbooks/alice/default/fixture-contact-uid.vcf"
            )
            print(
                json.dumps(
                    {
                        "ok": True,
                        "fixture": True,
                        "action": "update",
                        "provider": args.provider or "carddav",
                        "id": args.uid or _uid_from_href(href) or "fixture-contact-uid",
                        "href": href,
                        "name": (args.name or "Updated").strip() or "Updated",
                        "email": (args.email or "").strip(),
                        "mutable": True,
                    }
                )
            )
            return 0
        print(
            json.dumps(
                {
                    "ok": True,
                    "fixture": True,
                    "action": "delete",
                    "provider": args.provider or "carddav",
                    "href": args.href
                    or "https://cal.example/dav/addressbooks/alice/default/fixture-contact-uid.vcf",
                }
            )
        )
        return 0

    if args.action == "providers":
        found = []
        for p in WRITABLE:
            tok = _token(p)
            if tok is None:
                print(json.dumps({"ok": False, "error": "proteus-accounts not installed"}))
                return 1
            if tok.get("ok"):
                found.append(p)
        print(json.dumps({"ok": True, "providers": found}))
        return 0

    provider = (args.provider or "").strip().lower()
    if not provider:
        for p in WRITABLE:
            tok = _token(p)
            if tok and tok.get("ok"):
                provider = p
                break
    if not provider:
        print(
            json.dumps(
                {
                    "ok": False,
                    "error": "no writable CardDAV/Apple seat",
                    "action": args.action,
                }
            )
        )
        return 1

    if args.action == "create":
        result = cmd_create(provider, args.name, args.email)
    elif args.action == "update":
        result = cmd_update(provider, args.href, args.name, args.email, args.uid)
    else:
        result = cmd_delete(provider, args.href)
    print(json.dumps(result))
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    sys.exit(main())
