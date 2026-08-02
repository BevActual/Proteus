#!/usr/bin/env python3
"""Create / update / delete contacts for Proteus Online accounts seats.

Writable: carddav · apple (Basic auth) · google · microsoft · exchange (OAuth).

Thin UX: display name + one email. No photos · groups · full vCard.
Stdout: one JSON object. Never logs passwords/tokens.
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

CARDDAV_WRITABLE = ("carddav", "apple")
OAUTH_WRITABLE = ("google", "microsoft", "exchange")
WRITABLE = CARDDAV_WRITABLE + OAUTH_WRITABLE


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
    # Google People: /v1/people/cXXX → people/cXXX
    if "/people/" in path:
        idx = path.find("/people/")
        return path[idx + 1 :].lstrip("/")  # people/cXXX
    return base.strip()


def _bearer(tok: dict) -> str:
    return str(tok.get("accessToken") or "")


def _http_json(
    url: str,
    headers: dict,
    method: str = "GET",
    body: bytes | None = None,
    timeout: float = 15.0,
) -> tuple[int, dict | list | None, str]:
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
            if not raw.strip():
                return resp.status, {}, ""
            return resp.status, json.loads(raw), ""
    except urllib.error.HTTPError as e:
        try:
            err_body = e.read().decode("utf-8", errors="replace")
        except Exception:
            err_body = str(e)
        return e.code, None, err_body[:300]
    except Exception as e:
        return 0, None, str(e)


def _oauth_contact_href(provider: str, contact_id: str) -> str:
    cid = str(contact_id or "").strip()
    if provider == "google":
        rn = cid if cid.startswith("people/") else f"people/{cid}"
        return f"https://people.googleapis.com/v1/{rn}"
    eid = urllib.parse.quote(cid, safe="")
    return f"https://graph.microsoft.com/v1.0/me/contacts/{eid}"


def _oauth_resource_id(provider: str, href: str, uid: str) -> str:
    uid = (uid or "").strip()
    href = (href or "").strip()
    if provider == "google":
        if uid.startswith("people/"):
            return uid
        if "people.googleapis.com" in href:
            path = urllib.parse.urlparse(href).path
            if "/people/" in path:
                return path[path.find("/people/") + 1 :]
        if uid:
            return uid if uid.startswith("people/") else f"people/{uid}"
        return ""
    if uid:
        return uid
    if href.startswith("http"):
        return href.rstrip("/").rsplit("/", 1)[-1]
    return ""


def _cmd_create_oauth(provider: str, name: str, email: str, tok: dict) -> dict:
    access = _bearer(tok)
    if not access:
        return {
            "ok": False,
            "error": "empty access token",
            "action": "create",
            "provider": provider,
        }
    headers = {
        "Authorization": f"Bearer {access}",
        "Accept": "application/json",
        "Content-Type": "application/json",
    }
    if provider == "google":
        url = "https://people.googleapis.com/v1/people:createContact"
        payload: dict = {
            "names": [{"givenName": name, "unstructuredName": name}],
        }
        if email:
            payload["emailAddresses"] = [{"value": email}]
    else:
        url = "https://graph.microsoft.com/v1.0/me/contacts"
        payload = {"displayName": name}
        if email:
            payload["emailAddresses"] = [{"address": email, "name": name}]
    status, data, err = _http_json(
        url, headers, method="POST", body=json.dumps(payload).encode()
    )
    if status not in (200, 201) or not isinstance(data, dict):
        hint = ""
        if status == 403:
            hint = "reconnect seat for contacts scope"
        return {
            "ok": False,
            "error": err or f"create HTTP {status}",
            "action": "create",
            "provider": provider,
            **({"hint": hint} if hint else {}),
        }
    if provider == "google":
        cid = str(data.get("resourceName") or "")
    else:
        cid = str(data.get("id") or "")
    return {
        "ok": True,
        "action": "create",
        "provider": provider,
        "id": cid,
        "uid": cid,
        "href": _oauth_contact_href(provider, cid) if cid else "",
        "name": name,
        "email": email,
        "status": status,
        "mutable": True,
    }


def _cmd_update_oauth(
    provider: str, href: str, name: str, email: str, uid: str, tok: dict
) -> dict:
    access = _bearer(tok)
    if not access:
        return {
            "ok": False,
            "error": "empty access token",
            "action": "update",
            "provider": provider,
        }
    cid = _oauth_resource_id(provider, href, uid)
    if not cid:
        return {"ok": False, "error": "href or uid required", "action": "update"}
    headers = {
        "Authorization": f"Bearer {access}",
        "Accept": "application/json",
        "Content-Type": "application/json",
    }
    if provider == "google":
        get_url = f"https://people.googleapis.com/v1/{cid}?personFields=names,emailAddresses"
        st0, cur, err0 = _http_json(get_url, headers)
        if st0 != 200 or not isinstance(cur, dict):
            return {
                "ok": False,
                "error": err0 or f"get HTTP {st0}",
                "action": "update",
                "provider": provider,
            }
        etag = str(cur.get("etag") or "")
        url = (
            f"https://people.googleapis.com/v1/{cid}:updateContact"
            "?updatePersonFields=names,emailAddresses"
        )
        payload: dict = {
            "names": [{"givenName": name, "unstructuredName": name}],
            "emailAddresses": [{"value": email}] if email else [],
        }
        if etag:
            payload["etag"] = etag
        method = "PATCH"
    else:
        url = _oauth_contact_href(provider, cid)
        payload = {"displayName": name}
        if email:
            payload["emailAddresses"] = [{"address": email, "name": name}]
        else:
            payload["emailAddresses"] = []
        method = "PATCH"
    status, data, err = _http_json(
        url, headers, method=method, body=json.dumps(payload).encode()
    )
    if status not in (200, 201) or not isinstance(data, dict):
        hint = ""
        if status == 403:
            hint = "reconnect seat for contacts scope"
        return {
            "ok": False,
            "error": err or f"update HTTP {status}",
            "action": "update",
            "provider": provider,
            **({"hint": hint} if hint else {}),
        }
    out_id = (
        str(data.get("resourceName") or cid)
        if provider == "google"
        else str(data.get("id") or cid)
    )
    return {
        "ok": True,
        "action": "update",
        "provider": provider,
        "id": out_id,
        "uid": out_id,
        "href": _oauth_contact_href(provider, out_id),
        "name": name,
        "email": email,
        "status": status,
        "mutable": True,
    }


def _cmd_delete_oauth(provider: str, href: str, uid: str, tok: dict) -> dict:
    access = _bearer(tok)
    if not access:
        return {
            "ok": False,
            "error": "empty access token",
            "action": "delete",
            "provider": provider,
        }
    cid = _oauth_resource_id(provider, href, uid)
    if not cid:
        return {"ok": False, "error": "href or uid required", "action": "delete"}
    if provider == "google":
        url = f"https://people.googleapis.com/v1/{cid}:deleteContact"
    else:
        url = _oauth_contact_href(provider, cid)
    status, _data, err = _http_json(
        url,
        {"Authorization": f"Bearer {access}", "Accept": "application/json"},
        method="DELETE",
    )
    if status in (200, 204):
        return {
            "ok": True,
            "action": "delete",
            "provider": provider,
            "href": _oauth_contact_href(provider, cid),
            "status": status,
        }
    if status == 404:
        return {
            "ok": True,
            "action": "delete",
            "provider": provider,
            "href": _oauth_contact_href(provider, cid),
            "status": 404,
            "hint": "already gone",
        }
    hint = ""
    if status == 403:
        hint = "reconnect seat for contacts scope"
    return {
        "ok": False,
        "error": err or f"delete HTTP {status}",
        "action": "delete",
        "provider": provider,
        **({"hint": hint} if hint else {}),
    }


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
    if provider in OAUTH_WRITABLE:
        return _cmd_create_oauth(provider, name, email, tok)
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
    tok = _token(provider)
    if tok is None:
        return {"ok": False, "error": "proteus-accounts not installed", "action": "update"}
    if not tok.get("ok"):
        return {
            "ok": False,
            "error": str(tok.get("error") or f"no {provider} seat"),
            "action": "update",
        }
    if provider in OAUTH_WRITABLE:
        return _cmd_update_oauth(provider, href, name, email, uid, tok)
    if not href.startswith("http"):
        return {"ok": False, "error": "href required", "action": "update"}
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


def cmd_delete(provider: str, href: str, uid: str = "") -> dict:
    href = (href or "").strip()
    if provider not in WRITABLE:
        return {"ok": False, "error": f"provider {provider} is read-only", "action": "delete"}
    tok = _token(provider)
    if tok is None:
        return {"ok": False, "error": "proteus-accounts not installed", "action": "delete"}
    if not tok.get("ok"):
        return {
            "ok": False,
            "error": str(tok.get("error") or f"no {provider} seat"),
            "action": "delete",
        }
    if provider in OAUTH_WRITABLE:
        return _cmd_delete_oauth(provider, href, uid, tok)
    if not href.startswith("http"):
        return {"ok": False, "error": "href required", "action": "delete"}
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
    ap = argparse.ArgumentParser(description="Proteus contacts mutate")
    ap.add_argument("action", choices=("create", "update", "delete", "providers"))
    ap.add_argument("--provider", default="")
    ap.add_argument("--name", default="Untitled")
    ap.add_argument("--email", default="")
    ap.add_argument("--href", default="")
    ap.add_argument("--uid", default="")
    args = ap.parse_args()

    if os.environ.get("PROTEUS_CONTACTS_MUTATE_FIXTURE") == "1":
        prov = (args.provider or "carddav").strip().lower() or "carddav"
        if args.action == "providers":
            print(
                json.dumps(
                    {
                        "ok": True,
                        "fixture": True,
                        "providers": ["carddav", "google", "microsoft"],
                    }
                )
            )
            return 0
        if args.action == "create":
            if prov in OAUTH_WRITABLE:
                href = _oauth_contact_href(
                    prov, "people/c-fixture" if prov == "google" else "fixture-ms-id"
                )
                uid = "people/c-fixture" if prov == "google" else "fixture-ms-id"
            else:
                uid = "fixture-contact-uid"
                href = (
                    "https://cal.example/dav/addressbooks/alice/default/"
                    "fixture-contact-uid.vcf"
                )
            print(
                json.dumps(
                    {
                        "ok": True,
                        "fixture": True,
                        "action": "create",
                        "provider": prov,
                        "id": uid,
                        "uid": uid,
                        "href": href,
                        "name": (args.name or "Untitled").strip() or "Untitled",
                        "email": (args.email or "").strip(),
                        "mutable": True,
                    }
                )
            )
            return 0
        if args.action == "update":
            if prov in OAUTH_WRITABLE:
                href = args.href or _oauth_contact_href(
                    prov, args.uid or ("people/c-fixture" if prov == "google" else "fixture-ms-id")
                )
                uid = args.uid or _uid_from_href(href) or (
                    "people/c-fixture" if prov == "google" else "fixture-ms-id"
                )
            else:
                href = args.href or (
                    "https://cal.example/dav/addressbooks/alice/default/"
                    "fixture-contact-uid.vcf"
                )
                uid = args.uid or _uid_from_href(href) or "fixture-contact-uid"
            print(
                json.dumps(
                    {
                        "ok": True,
                        "fixture": True,
                        "action": "update",
                        "provider": prov,
                        "id": uid,
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
                    "provider": prov,
                    "href": args.href
                    or (
                        _oauth_contact_href(prov, "people/c-fixture")
                        if prov == "google"
                        else "https://cal.example/dav/addressbooks/alice/default/fixture-contact-uid.vcf"
                    ),
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
                    "error": "no writable CardDAV/Apple/Google/MS contacts seat",
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
        result = cmd_delete(provider, args.href, args.uid)
    print(json.dumps(result))
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    sys.exit(main())
