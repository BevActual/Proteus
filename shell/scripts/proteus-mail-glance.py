#!/usr/bin/env python3
"""Fetch unread / recent mail for Proteus Online accounts seats.

Uses `proteus-accounts token` (refresh when needed). Providers:
  google    — Gmail API metadata (gmail.metadata)
  microsoft — Graph Mail.ReadBasic inbox
  imap      — IMAP4_SSL via stdlib imaplib (vault password)
  apple     — IMAP4_SSL on imapHost/imapPort (iCloud app-specific password)
  exchange  — Microsoft Graph mail (work/school seat; same API as microsoft)

Stdout: one JSON object. Never logs access tokens.
Honesty: read-only glance consumer — not a mail app.
"""
from __future__ import annotations

import argparse
import email
import imaplib
import json
import os
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from email.header import decode_header, make_header
from email.utils import parsedate_to_datetime
from pathlib import Path


def _run(cmd: list[str], timeout: float = 20.0) -> tuple[int, str, str]:
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except Exception as e:
        return 1, "", str(e)
    return r.returncode, (r.stdout or "").strip(), (r.stderr or "").strip()


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


def _http_json(
    url: str, headers: dict, timeout: float = 15.0
) -> tuple[int, dict | list | None, str]:
    req = urllib.request.Request(url, headers=headers, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            body = resp.read().decode("utf-8", errors="replace")
            return resp.status, json.loads(body), ""
    except urllib.error.HTTPError as e:
        try:
            err_body = e.read().decode("utf-8", errors="replace")
        except Exception:
            err_body = str(e)
        return e.code, None, err_body[:300]
    except Exception as e:
        return 0, None, str(e)


def _header_map(payload: dict) -> dict[str, str]:
    out: dict[str, str] = {}
    for h in (payload.get("payload") or {}).get("headers") or []:
        if not isinstance(h, dict):
            continue
        name = str(h.get("name") or "").lower()
        if name:
            out[name] = str(h.get("value") or "")
    return out


def fetch_google(access: str, limit: int) -> tuple[int, list[dict], str]:
    headers = {"Authorization": f"Bearer {access}", "Accept": "application/json"}
    unread = 0
    st, label, err = _http_json(
        "https://gmail.googleapis.com/gmail/v1/users/me/labels/INBOX", headers
    )
    if st == 200 and isinstance(label, dict):
        unread = int(label.get("messagesUnread") or 0)
    elif st not in (0, 200):
        return 0, [], err or f"google labels HTTP {st}"

    q = urllib.parse.urlencode({"q": "in:inbox is:unread", "maxResults": str(limit)})
    st, listing, err = _http_json(
        f"https://gmail.googleapis.com/gmail/v1/users/me/messages?{q}", headers
    )
    if st != 200 or not isinstance(listing, dict):
        return unread, [], err or f"google list HTTP {st}"

    messages: list[dict] = []
    for item in (listing.get("messages") or [])[:limit]:
        if not isinstance(item, dict):
            continue
        mid = str(item.get("id") or "")
        if not mid:
            continue
        gq = urllib.parse.urlencode(
            {
                "format": "metadata",
                "metadataHeaders": ["Subject", "From", "Date"],
            },
            doseq=True,
        )
        st2, msg, err2 = _http_json(
            f"https://gmail.googleapis.com/gmail/v1/users/me/messages/{mid}?{gq}",
            headers,
        )
        if st2 != 200 or not isinstance(msg, dict):
            if err2:
                return unread, messages, err2
            continue
        hm = _header_map(msg)
        messages.append(
            {
                "subject": hm.get("subject") or "(No subject)",
                "from": hm.get("from") or "",
                "received": hm.get("date") or "",
                "provider": "google",
            }
        )
    return unread, messages, ""


def fetch_microsoft(access: str, limit: int) -> tuple[int, list[dict], str]:
    headers = {"Authorization": f"Bearer {access}", "Accept": "application/json"}
    unread = 0
    st, folder, err = _http_json(
        "https://graph.microsoft.com/v1.0/me/mailFolders/inbox"
        "?$select=unreadItemCount",
        headers,
    )
    if st == 200 and isinstance(folder, dict):
        unread = int(folder.get("unreadItemCount") or 0)
    elif st not in (0, 200):
        return 0, [], err or f"microsoft folder HTTP {st}"

    q = urllib.parse.urlencode(
        {
            "$filter": "isRead eq false",
            "$top": str(limit),
            "$orderby": "receivedDateTime desc",
            "$select": "subject,from,receivedDateTime,isRead",
        }
    )
    st, data, err = _http_json(
        f"https://graph.microsoft.com/v1.0/me/mailFolders/inbox/messages?{q}",
        headers,
    )
    if st != 200 or not isinstance(data, dict):
        return unread, [], err or f"microsoft messages HTTP {st}"

    messages: list[dict] = []
    for item in data.get("value") or []:
        if not isinstance(item, dict):
            continue
        fr = item.get("from") or {}
        ea = fr.get("emailAddress") if isinstance(fr, dict) else {}
        name = ""
        addr = ""
        if isinstance(ea, dict):
            name = str(ea.get("name") or "")
            addr = str(ea.get("address") or "")
        from_s = name if name else addr
        if name and addr and name != addr:
            from_s = f"{name} <{addr}>"
        messages.append(
            {
                "subject": str(item.get("subject") or "(No subject)"),
                "from": from_s,
                "received": str(item.get("receivedDateTime") or ""),
                "provider": "microsoft",
            }
        )
    return unread, messages[:limit], ""


def fetch_exchange(access: str, limit: int) -> tuple[int, list[dict], str]:
    unread, messages, err = fetch_microsoft(access, limit)
    for m in messages:
        m["provider"] = "exchange"
    return unread, messages, err


def _decode_hdr(raw: str | None) -> str:
    if not raw:
        return ""
    try:
        return str(make_header(decode_header(raw)))
    except Exception:
        return str(raw)


def _imap_received(msg: email.message.Message) -> str:
    date_s = msg.get("Date") or ""
    if not date_s:
        return ""
    try:
        return parsedate_to_datetime(date_s).isoformat()
    except Exception:
        return str(date_s)


def fetch_imap(
    base_url: str,
    user: str,
    password: str,
    limit: int,
    provider: str = "imap",
    host: str = "",
    port: int = 0,
) -> tuple[int, list[dict], str]:
    user = (user or "").strip()
    password = password or ""
    host = (host or "").strip()
    if not host:
        base = (base_url or "").strip()
        if not base or not user or not password:
            return 0, [], f"{provider} seat incomplete (host/user/password)"
        u = urllib.parse.urlparse(base if "://" in base else f"imaps://{base}")
        host = u.hostname or ""
        port = int(u.port or 993)
    else:
        if not user or not password:
            return 0, [], f"{provider} seat incomplete (host/user/password)"
        port = int(port or 993)
    if not host:
        return 0, [], f"{provider} host missing"
    try:
        M = imaplib.IMAP4_SSL(host, port, timeout=15)
    except Exception as e:
        return 0, [], f"{provider} connect: {e}"
    try:
        typ, _ = M.login(user, password)
        if typ != "OK":
            return 0, [], f"{provider} login failed"
        typ, _ = M.select("INBOX", readonly=True)
        if typ != "OK":
            return 0, [], f"{provider} INBOX select failed"
        typ, data = M.search(None, "UNSEEN")
        if typ != "OK":
            return 0, [], f"{provider} SEARCH UNSEEN failed"
        ids = (data[0] or b"").split()
        unread = len(ids)
        messages: list[dict] = []
        # Newest first when servers return ascending UIDs/seq.
        for num in reversed(ids[-limit:]):
            typ, fetched = M.fetch(num, "(BODY.PEEK[HEADER.FIELDS (SUBJECT FROM DATE)])")
            if typ != "OK" or not fetched:
                continue
            raw = b""
            for part in fetched:
                if isinstance(part, tuple) and len(part) >= 2 and isinstance(part[1], bytes):
                    raw = part[1]
                    break
            if not raw:
                continue
            msg = email.message_from_bytes(raw)
            messages.append(
                {
                    "subject": _decode_hdr(msg.get("Subject")) or "(No subject)",
                    "from": _decode_hdr(msg.get("From")),
                    "received": _imap_received(msg),
                    "provider": provider,
                }
            )
        return unread, messages[:limit], ""
    except Exception as e:
        return 0, [], f"{provider}: {e}"
    finally:
        try:
            M.logout()
        except Exception:
            pass


def main() -> int:
    ap = argparse.ArgumentParser(description="Proteus mail glance fetch")
    ap.add_argument("--limit", type=int, default=5, help="max messages per provider")
    args = ap.parse_args()
    limit = max(1, min(20, int(args.limit or 5)))

    if os.environ.get("PROTEUS_MAIL_FIXTURE") == "1":
        print(
            json.dumps(
                {
                    "ok": True,
                    "unread": 2,
                    "messages": [
                        {
                            "subject": "Fixture unread",
                            "from": "fixture@example.com",
                            "received": "2026-08-01T12:00:00Z",
                            "provider": "fixture",
                        },
                        {
                            "subject": "Another fixture",
                            "from": "noreply@example.com",
                            "received": "2026-08-01T11:00:00Z",
                            "provider": "fixture",
                        },
                    ],
                    "seats": 0,
                    "errors": [],
                    "hint": "",
                }
            )
        )
        return 0

    providers = ("google", "microsoft", "exchange", "imap", "apple")
    messages: list[dict] = []
    errors: list[str] = []
    seats = 0
    unread_total = 0
    for prov in providers:
        tok = _token(prov)
        if tok is None:
            errors.append("proteus-accounts not installed")
            break
        if not tok.get("ok"):
            continue
        seats += 1
        access = str(tok.get("accessToken") or "")
        if prov == "google":
            unread, msgs, err = fetch_google(access, limit)
        elif prov == "microsoft":
            unread, msgs, err = fetch_microsoft(access, limit)
        elif prov == "exchange":
            unread, msgs, err = fetch_exchange(access, limit)
        elif prov == "apple":
            unread, msgs, err = fetch_imap(
                str(tok.get("baseUrl") or ""),
                str(tok.get("username") or tok.get("email") or ""),
                access,
                limit,
                provider="apple",
                host=str(tok.get("imapHost") or ""),
                port=int(tok.get("imapPort") or 993),
            )
        else:
            unread, msgs, err = fetch_imap(
                str(tok.get("baseUrl") or ""),
                str(tok.get("username") or tok.get("email") or ""),
                access,
                limit,
            )
        unread_total += unread
        if err:
            errors.append(f"{prov}: {err}")
        messages.extend(msgs)

    def sort_key(m: dict) -> str:
        return str(m.get("received") or "")

    messages.sort(key=sort_key, reverse=True)
    print(
        json.dumps(
            {
                "ok": True,
                "unread": unread_total,
                "messages": messages[:limit],
                "seats": seats,
                "errors": errors,
                "hint": (
                    "Reconnect Google/Microsoft seats if mail scope was added after connect"
                    if any(
                        "403" in e
                        or "insufficient" in e.lower()
                        or "InvalidAuthenticationToken" in e
                        for e in errors
                    )
                    else ""
                ),
            }
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
