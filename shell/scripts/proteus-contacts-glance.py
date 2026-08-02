#!/usr/bin/env python3
"""Fetch a few contacts for Proteus Online accounts CardDAV / Apple seats.

Uses `proteus-accounts token carddav` and `token apple`. Best-effort
addressbook-query REPORT (Apple via carddavUrl).

Stdout: one JSON object. Never logs access tokens.
Honesty: glance consumer — CardDAV/Apple write via proteus-contacts-mutate.py;
not a contacts app.
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


def _uid_from_href(href: str) -> str:
    path = urllib.parse.urlparse(href).path
    base = path.rsplit("/", 1)[-1]
    for ext in (".vcf", ".vcard"):
        if base.lower().endswith(ext):
            base = base[: -len(ext)]
    return base.strip()


def _parse_vcard_fields(
    block: str, provider: str = "carddav", href: str = ""
) -> dict:
    name = ""
    email = ""
    uid = ""
    for raw in block.splitlines():
        line = raw.strip()
        if line.startswith("FN:") or line.startswith("FN;"):
            name = line.split(":", 1)[-1].strip()
        elif line.startswith("EMAIL:") or line.startswith("EMAIL;"):
            if not email:
                email = line.split(":", 1)[-1].strip()
        elif line.startswith("UID:") or line.startswith("UID;"):
            uid = line.split(":", 1)[-1].strip()
    abs_href = href
    if not uid and abs_href:
        uid = _uid_from_href(abs_href)
    mutable = provider in WRITABLE and bool(abs_href)
    return {
        "id": uid or abs_href,
        "uid": uid,
        "name": name or "(No name)",
        "email": email,
        "provider": provider,
        "mutable": mutable,
        "href": abs_href,
    }


def fetch_carddav(
    base: str, user: str, password: str, limit: int, provider: str = "carddav"
) -> tuple[list[dict], str]:
    if not base or not user or not password:
        return [], f"{provider} credentials incomplete"
    auth = base64.b64encode(f"{user}:{password}".encode()).decode()
    home = base if base.endswith("/") else f"{base}/"
    propfind = """<?xml version="1.0" encoding="UTF-8"?>
<d:propfind xmlns:d="DAV:" xmlns:card="urn:ietf:params:xml:ns:carddav">
  <d:prop><d:displayname/><d:resourcetype/></d:prop>
</d:propfind>
"""
    req = urllib.request.Request(
        home,
        data=propfind.encode(),
        method="PROPFIND",
        headers={
            "Authorization": f"Basic {auth}",
            "Depth": "1",
            "Content-Type": "application/xml; charset=utf-8",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=12) as resp:
            listing = resp.read().decode("utf-8", errors="replace")
    except Exception as e:
        return [], f"carddav PROPFIND: {e}"

    hrefs: list[str] = []
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
            hrefs.append(href)
    except Exception:
        pass
    if not hrefs:
        hrefs = [home]

    body = """<?xml version="1.0" encoding="UTF-8"?>
<card:addressbook-query xmlns:d="DAV:" xmlns:card="urn:ietf:params:xml:ns:carddav">
  <d:prop>
    <d:getetag/>
    <card:address-data/>
  </d:prop>
</card:addressbook-query>
"""
    contacts: list[dict] = []
    errors: list[str] = []
    seen: set[str] = set()
    origin = urllib.parse.urlparse(base)
    for href in hrefs[:3]:
        if href in seen:
            continue
        seen.add(href)
        if href.startswith("http"):
            report_url = href
        else:
            report_url = f"{origin.scheme}://{origin.netloc}{href}"
        req2 = urllib.request.Request(
            report_url,
            data=body.encode(),
            method="REPORT",
            headers={
                "Authorization": f"Basic {auth}",
                "Depth": "1",
                "Content-Type": "application/xml; charset=utf-8",
            },
        )
        try:
            with urllib.request.urlopen(req2, timeout=15) as resp:
                xml_body = resp.read().decode("utf-8", errors="replace")
        except Exception as e:
            errors.append(str(e))
            continue
        card_ns = {"d": "DAV:", "card": "urn:ietf:params:xml:ns:carddav"}
        try:
            root = ET.fromstring(xml_body)
            for resp_el in root.findall("d:response", card_ns):
                c_href = resp_el.findtext("d:href", default="", namespaces=card_ns) or ""
                addr_data = ""
                for el in resp_el.iter():
                    tag = el.tag.rsplit("}", 1)[-1] if "}" in el.tag else el.tag
                    if tag == "address-data" and el.text:
                        addr_data = el.text
                        break
                if not addr_data or "BEGIN:VCARD" not in addr_data:
                    continue
                if c_href.startswith("http"):
                    abs_href = c_href
                else:
                    abs_href = f"{origin.scheme}://{origin.netloc}{c_href}"
                contacts.append(_parse_vcard_fields(addr_data, provider, abs_href))
                if len(contacts) >= limit:
                    break
        except ET.ParseError:
            for block in xml_body.split("BEGIN:VCARD"):
                if (
                    "FN:" not in block
                    and "FN;" not in block
                    and "EMAIL:" not in block
                    and "EMAIL;" not in block
                ):
                    continue
                contacts.append(_parse_vcard_fields(block, provider, ""))
                if len(contacts) >= limit:
                    break
        if contacts:
            break
    if not contacts and errors:
        return [], errors[0]
    return contacts[:limit], ""


def main() -> int:
    ap = argparse.ArgumentParser(description="Proteus contacts glance fetch")
    ap.add_argument("--limit", type=int, default=5)
    args = ap.parse_args()
    limit = max(1, min(20, int(args.limit or 5)))

    if os.environ.get("PROTEUS_CONTACTS_FIXTURE") == "1":
        print(
            json.dumps(
                {
                    "ok": True,
                    "contacts": [
                        {
                            "id": "fixture-contact-uid",
                            "uid": "fixture-contact-uid",
                            "name": "Fixture Person",
                            "email": "fixture@example.com",
                            "provider": "carddav",
                            "mutable": True,
                            "href": "https://cal.example/dav/addressbooks/alice/default/fixture-contact-uid.vcf",
                        }
                    ],
                    "seats": 1,
                    "mutableSeats": 1,
                    "errors": [],
                }
            )
        )
        return 0

    providers = ("carddav", "apple")
    errors: list[str] = []
    contacts: list[dict] = []
    seats = 0
    mutable_seats = 0
    for prov in providers:
        tok = _token(prov)
        if tok is None:
            errors.append("proteus-accounts not installed")
            break
        if not tok.get("ok"):
            continue
        seats += 1
        if prov in WRITABLE:
            mutable_seats += 1
        if prov == "apple":
            base = str(tok.get("carddavUrl") or tok.get("baseUrl") or "")
        else:
            base = str(tok.get("baseUrl") or "")
        ev, err = fetch_carddav(
            base,
            str(tok.get("username") or tok.get("email") or ""),
            str(tok.get("accessToken") or ""),
            limit,
            provider=prov,
        )
        if err:
            errors.append(f"{prov}: {err}")
        contacts.extend(ev)

    print(
        json.dumps(
            {
                "ok": True,
                "contacts": contacts[:limit],
                "seats": seats,
                "mutableSeats": mutable_seats,
                "errors": errors,
                "hint": "",
            }
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
