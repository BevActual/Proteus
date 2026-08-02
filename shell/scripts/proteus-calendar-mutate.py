#!/usr/bin/env python3
"""Create / update / delete calendar events for Proteus Online accounts seats.

Writable:
  · CalDAV — nextcloud · caldav · apple (Basic auth)
  · OAuth — google · microsoft · exchange (Bearer; calendar.events / Calendars.ReadWrite)

Thin UX: title + day (09:00–10:00 UTC slot) + optional recurrence
(daily|weekly|monthly|none, no end) on create and whole-series update.
No attendees · COUNT/UNTIL · this-vs-all · exceptions · scoped delete.
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
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

CALDAV_WRITABLE = ("nextcloud", "caldav", "apple")
OAUTH_WRITABLE = ("google", "microsoft", "exchange")
WRITABLE = CALDAV_WRITABLE + OAUTH_WRITABLE


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


def _creds(provider: str, tok: dict) -> tuple[str, str, str, str]:
    """Return (cal_home, origin, user, password)."""
    password = str(tok.get("accessToken") or "")
    user = str(tok.get("username") or tok.get("email") or "").strip()
    if provider == "nextcloud":
        base = str(tok.get("baseUrl") or "").rstrip("/")
        cal = f"{base}/remote.php/dav/calendars/{urllib.parse.quote(user)}/"
        return cal, base, user, password
    if provider == "apple":
        base = str(tok.get("caldavUrl") or tok.get("baseUrl") or "").rstrip("/")
        return f"{base}/", base, user, password
    base = str(tok.get("baseUrl") or "").rstrip("/")
    return f"{base}/", base, user, password


def _auth_header(user: str, password: str) -> str:
    return "Basic " + base64.b64encode(f"{user}:{password}".encode()).decode()


def _first_calendar(cal_home: str, origin: str, user: str, password: str) -> tuple[str, str]:
    """Pick first calendar collection under home. Returns (abs_url, error)."""
    if not cal_home or not user or not password:
        return "", "credentials incomplete"
    propfind = """<?xml version="1.0" encoding="UTF-8"?>
<d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
  <d:prop><d:displayname/><c:calendar-description/></d:prop>
</d:propfind>
"""
    home = cal_home if cal_home.endswith("/") else f"{cal_home}/"
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
    hrefs: list[str] = []
    try:
        root = ET.fromstring(listing)
        ns = {"d": "DAV:"}
        home_path = urllib.parse.urlparse(home).path.rstrip("/")
        for resp_el in root.findall("d:response", ns):
            href = resp_el.findtext("d:href", default="", namespaces=ns) or ""
            if not href or not href.endswith("/"):
                continue
            if href.rstrip("/") == home_path:
                continue
            hrefs.append(href)
    except Exception:
        pass
    if not hrefs:
        # Nextcloud personal fallback
        if "/remote.php/dav/calendars/" in home:
            hrefs = [home.rstrip("/") + "/personal/"]
        else:
            hrefs = [home]
    href = hrefs[0]
    if href.startswith("http"):
        return href if href.endswith("/") else href + "/", ""
    parsed = urllib.parse.urlparse(origin or home)
    path = href if href.endswith("/") else href + "/"
    return f"{parsed.scheme}://{parsed.netloc}{path}", ""


def _normalize_recurrence(raw: str) -> str:
    """Return daily|weekly|monthly or '' (none / invalid)."""
    v = (raw or "").strip().lower()
    if v in ("", "none", "off", "once"):
        return ""
    if v in ("daily", "day", "d"):
        return "daily"
    if v in ("weekly", "week", "w"):
        return "weekly"
    if v in ("monthly", "month", "m"):
        return "monthly"
    return ""


def _rrule_line(recurrence: str) -> str:
    freq = {
        "daily": "DAILY",
        "weekly": "WEEKLY",
        "monthly": "MONTHLY",
    }.get(recurrence or "", "")
    return f"RRULE:FREQ={freq}" if freq else ""


def _graph_recurrence(recurrence: str, day: date) -> dict | None:
    """Microsoft Graph recurrence (noEnd). Weekly needs daysOfWeek."""
    if recurrence == "daily":
        pattern: dict = {"type": "daily", "interval": 1}
    elif recurrence == "weekly":
        # Graph weekday names are lowercase English.
        names = (
            "monday",
            "tuesday",
            "wednesday",
            "thursday",
            "friday",
            "saturday",
            "sunday",
        )
        pattern = {
            "type": "weekly",
            "interval": 1,
            "daysOfWeek": [names[day.weekday()]],
        }
    elif recurrence == "monthly":
        pattern = {
            "type": "absoluteMonthly",
            "interval": 1,
            "dayOfMonth": day.day,
        }
    else:
        return None
    return {
        "pattern": pattern,
        "range": {
            "type": "noEnd",
            "startDate": day.isoformat(),
        },
    }


def _ics(uid: str, title: str, day: date, hours: int = 1, recurrence: str = "") -> str:
    start = datetime(day.year, day.month, day.day, 9, 0, 0, tzinfo=timezone.utc)
    end = start + timedelta(hours=max(1, hours))
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    dtstart = start.strftime("%Y%m%dT%H%M%SZ")
    dtend = end.strftime("%Y%m%dT%H%M%SZ")
    # Escape SUMMARY commas/semicolons lightly
    summary = title.replace("\\", "\\\\").replace(";", "\\;").replace(",", "\\,")
    rrule = _rrule_line(recurrence)
    rrule_block = f"{rrule}\r\n" if rrule else ""
    return (
        "BEGIN:VCALENDAR\r\n"
        "VERSION:2.0\r\n"
        "PRODID:-//Proteus//Calendar mutate//EN\r\n"
        "CALSCALE:GREGORIAN\r\n"
        "BEGIN:VEVENT\r\n"
        f"UID:{uid}\r\n"
        f"DTSTAMP:{stamp}\r\n"
        f"DTSTART:{dtstart}\r\n"
        f"DTEND:{dtend}\r\n"
        f"SUMMARY:{summary}\r\n"
        f"{rrule_block}"
        "END:VEVENT\r\n"
        "END:VCALENDAR\r\n"
    )


def _slot_times(day: date) -> tuple[str, str]:
    start = datetime(day.year, day.month, day.day, 9, 0, 0, tzinfo=timezone.utc)
    end = start + timedelta(hours=1)
    return (
        start.isoformat().replace("+00:00", "Z"),
        end.isoformat().replace("+00:00", "Z"),
    )


def _oauth_event_href(provider: str, event_id: str) -> str:
    eid = urllib.parse.quote(str(event_id or ""), safe="")
    if provider == "google":
        return f"https://www.googleapis.com/calendar/v3/calendars/primary/events/{eid}"
    # microsoft + exchange share Graph
    return f"https://graph.microsoft.com/v1.0/me/events/{eid}"


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


def _bearer(tok: dict) -> str:
    return str(tok.get("accessToken") or "")


def _cmd_create_oauth(
    provider: str, title: str, day: date, tok: dict, recurrence: str = ""
) -> dict:
    access = _bearer(tok)
    if not access:
        return {"ok": False, "error": "empty access token", "action": "create", "provider": provider}
    start_iso, end_iso = _slot_times(day)
    recurrence = _normalize_recurrence(recurrence)
    if provider == "google":
        url = "https://www.googleapis.com/calendar/v3/calendars/primary/events"
        payload = {
            "summary": title,
            "start": {"dateTime": start_iso},
            "end": {"dateTime": end_iso},
        }
        rrule = _rrule_line(recurrence)
        if rrule:
            payload["recurrence"] = [rrule]
    else:
        url = "https://graph.microsoft.com/v1.0/me/events"
        payload = {
            "subject": title,
            "start": {"dateTime": start_iso.replace("Z", ""), "timeZone": "UTC"},
            "end": {"dateTime": end_iso.replace("Z", ""), "timeZone": "UTC"},
        }
        graph_r = _graph_recurrence(recurrence, day)
        if graph_r:
            payload["recurrence"] = graph_r
    status, data, err = _http_json(
        url,
        {
            "Authorization": f"Bearer {access}",
            "Accept": "application/json",
            "Content-Type": "application/json",
        },
        method="POST",
        body=json.dumps(payload).encode(),
    )
    if status not in (200, 201) or not isinstance(data, dict):
        return {
            "ok": False,
            "error": err or f"create HTTP {status}",
            "action": "create",
            "provider": provider,
        }
    eid = str(data.get("id") or "")
    out = {
        "ok": True,
        "action": "create",
        "provider": provider,
        "id": eid,
        "href": _oauth_event_href(provider, eid) if eid else "",
        "title": title,
        "date": day.isoformat(),
        "status": status,
        "mutable": True,
    }
    if recurrence:
        out["recurrence"] = recurrence
    return out


def _cmd_update_oauth(
    provider: str,
    href: str,
    title: str,
    day: date,
    uid: str,
    tok: dict,
    recurrence: str | None = None,
) -> dict:
    access = _bearer(tok)
    if not access:
        return {"ok": False, "error": "empty access token", "action": "update", "provider": provider}
    event_id = (uid or "").strip()
    url = (href or "").strip()
    if not url.startswith("http"):
        if not event_id:
            return {"ok": False, "error": "href or uid required", "action": "update"}
        url = _oauth_event_href(provider, event_id)
    elif not event_id:
        event_id = url.rstrip("/").rsplit("/", 1)[-1]
    # Prefer series master id when glance expanded an instance (id_YYYYMMDD…).
    if "_" in event_id and provider == "google" and "T" in event_id.split("_", 1)[-1]:
        event_id = event_id.split("_", 1)[0]
        url = _oauth_event_href(provider, event_id)
    start_iso, end_iso = _slot_times(day)
    touch_rec = recurrence is not None
    recurrence_n = _normalize_recurrence(recurrence or "") if touch_rec else ""
    if provider == "google":
        payload = {
            "summary": title,
            "start": {"dateTime": start_iso},
            "end": {"dateTime": end_iso},
        }
        if touch_rec:
            payload["recurrence"] = (
                [_rrule_line(recurrence_n)] if recurrence_n else []
            )
        method = "PUT"
    else:
        payload = {
            "subject": title,
            "start": {"dateTime": start_iso.replace("Z", ""), "timeZone": "UTC"},
            "end": {"dateTime": end_iso.replace("Z", ""), "timeZone": "UTC"},
        }
        if touch_rec:
            graphed = _graph_recurrence(recurrence_n, day)
            payload["recurrence"] = graphed if graphed else None
        method = "PATCH"
    status, data, err = _http_json(
        url,
        {
            "Authorization": f"Bearer {access}",
            "Accept": "application/json",
            "Content-Type": "application/json",
        },
        method=method,
        body=json.dumps(payload).encode(),
    )
    if status not in (200, 201) or not isinstance(data, dict):
        return {
            "ok": False,
            "error": err or f"update HTTP {status}",
            "action": "update",
            "provider": provider,
        }
    eid = str(data.get("id") or event_id)
    out = {
        "ok": True,
        "action": "update",
        "provider": provider,
        "id": eid,
        "href": url,
        "title": title,
        "date": day.isoformat(),
        "status": status,
        "mutable": True,
    }
    if touch_rec and recurrence_n:
        out["recurrence"] = recurrence_n
    return out


def _cmd_delete_oauth(provider: str, href: str, uid: str, tok: dict) -> dict:
    access = _bearer(tok)
    if not access:
        return {"ok": False, "error": "empty access token", "action": "delete", "provider": provider}
    url = (href or "").strip()
    if not url.startswith("http"):
        eid = (uid or "").strip()
        if not eid:
            return {"ok": False, "error": "href or uid required", "action": "delete"}
        url = _oauth_event_href(provider, eid)
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
            "href": url,
            "status": status,
        }
    if status == 404:
        return {
            "ok": True,
            "action": "delete",
            "provider": provider,
            "href": url,
            "status": 404,
            "hint": "already gone",
        }
    return {
        "ok": False,
        "error": err or f"delete HTTP {status}",
        "action": "delete",
        "provider": provider,
    }


def cmd_create(provider: str, title: str, day: date, recurrence: str = "") -> dict:
    title = (title or "").strip() or "New event"
    recurrence = _normalize_recurrence(recurrence)
    if provider not in WRITABLE:
        return {
            "ok": False,
            "error": f"provider {provider} is read-only",
            "action": "create",
        }
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
        return _cmd_create_oauth(provider, title, day, tok, recurrence=recurrence)
    cal_home, origin, user, password = _creds(provider, tok)
    cal_url, err = _first_calendar(cal_home, origin, user, password)
    if err or not cal_url:
        return {"ok": False, "error": err or "no calendar collection", "action": "create"}
    uid = str(uuid.uuid4())
    put_url = cal_url.rstrip("/") + f"/{uid}.ics"
    body = _ics(uid, title, day, recurrence=recurrence).encode()
    req = urllib.request.Request(
        put_url,
        data=body,
        method="PUT",
        headers={
            "Authorization": _auth_header(user, password),
            "Content-Type": "text/calendar; charset=utf-8",
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
    out = {
        "ok": True,
        "action": "create",
        "provider": provider,
        "id": uid,
        "href": put_url,
        "title": title,
        "date": day.isoformat(),
        "status": status,
        "mutable": True,
    }
    if recurrence:
        out["recurrence"] = recurrence
    return out


def _uid_from_href(href: str) -> str:
    path = urllib.parse.urlparse(href).path
    base = path.rsplit("/", 1)[-1]
    if base.lower().endswith(".ics"):
        base = base[:-4]
    return base.strip()


def cmd_update(
    provider: str,
    href: str,
    title: str,
    day: date,
    uid: str = "",
    recurrence: str | None = None,
) -> dict:
    """Overwrite an existing event (title + day + optional whole-series recurrence).

    recurrence=None preserves prior RRULE on CalDAV (GET not performed — omit
    means rewrite without RRULE only when explicitly none|daily|…).
    """
    href = (href or "").strip()
    title = (title or "").strip() or "Untitled"
    touch_rec = recurrence is not None
    recurrence_n = _normalize_recurrence(recurrence or "") if touch_rec else ""
    if provider not in WRITABLE:
        return {
            "ok": False,
            "error": f"provider {provider} is read-only",
            "action": "update",
        }
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
        return _cmd_update_oauth(
            provider, href, title, day, uid, tok, recurrence=recurrence
        )
    if not href.startswith("http"):
        return {"ok": False, "error": "href required (absolute event URL)", "action": "update"}
    _cal_home, _origin, user, password = _creds(provider, tok)
    event_uid = (uid or "").strip() or _uid_from_href(href)
    if not event_uid:
        return {"ok": False, "error": "uid required (or href basename .ics)", "action": "update"}
    # When recurrence omitted, preserve existing RRULE via GET (best-effort).
    cal_rec = recurrence_n if touch_rec else ""
    if not touch_rec:
        try:
            get_req = urllib.request.Request(
                href,
                method="GET",
                headers={"Authorization": _auth_header(user, password)},
            )
            with urllib.request.urlopen(get_req, timeout=12) as resp:
                existing = resp.read().decode("utf-8", errors="replace")
            for line in existing.splitlines():
                if line.startswith("RRULE:") or line.startswith("RRULE;"):
                    if "FREQ=DAILY" in line.upper():
                        cal_rec = "daily"
                    elif "FREQ=WEEKLY" in line.upper():
                        cal_rec = "weekly"
                    elif "FREQ=MONTHLY" in line.upper():
                        cal_rec = "monthly"
                    break
        except Exception:
            cal_rec = ""
    body = _ics(event_uid, title, day, recurrence=cal_rec).encode()
    req = urllib.request.Request(
        href,
        data=body,
        method="PUT",
        headers={
            "Authorization": _auth_header(user, password),
            "Content-Type": "text/calendar; charset=utf-8",
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
    out = {
        "ok": True,
        "action": "update",
        "provider": provider,
        "id": event_uid,
        "href": href,
        "title": title,
        "date": day.isoformat(),
        "status": status,
        "mutable": True,
    }
    if touch_rec and recurrence_n:
        out["recurrence"] = recurrence_n
    elif not touch_rec and cal_rec:
        out["recurrence"] = cal_rec
    return out


def cmd_delete(provider: str, href: str, uid: str = "") -> dict:
    href = (href or "").strip()
    if provider not in WRITABLE:
        return {
            "ok": False,
            "error": f"provider {provider} is read-only",
            "action": "delete",
        }
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
        return {"ok": False, "error": "href required (absolute event URL)", "action": "delete"}
    _cal_home, _origin, user, password = _creds(provider, tok)
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
    ap = argparse.ArgumentParser(description="Proteus calendar event mutate (CalDAV + OAuth)")
    ap.add_argument("action", choices=("create", "update", "delete", "providers"))
    ap.add_argument(
        "--provider",
        default="",
        help="nextcloud|caldav|apple|google|microsoft|exchange",
    )
    ap.add_argument("--title", default="New event")
    ap.add_argument("--date", default="", help="YYYY-MM-DD (default today)")
    ap.add_argument("--href", default="", help="Absolute event URL for update/delete")
    ap.add_argument(
        "--uid",
        default="",
        help="Event UID / API id (CalDAV .ics basename or OAuth event id)",
    )
    ap.add_argument(
        "--recurrence",
        default=None,
        help="create/update: none|daily|weekly|monthly (whole series, no end)",
    )
    args = ap.parse_args()

    if os.environ.get("PROTEUS_CALENDAR_MUTATE_FIXTURE") == "1":
        day = date.fromisoformat(args.date) if args.date else date.today()
        if args.action == "providers":
            print(json.dumps({"ok": True, "fixture": True, "providers": ["caldav"]}))
            return 0
        if args.action == "create":
            rec = _normalize_recurrence(args.recurrence or "")
            payload = {
                "ok": True,
                "fixture": True,
                "action": "create",
                "provider": args.provider or "caldav",
                "id": "fixture-new-uid",
                "href": "https://cal.example/dav/calendars/alice/personal/fixture-new-uid.ics",
                "title": (args.title or "New event").strip() or "New event",
                "date": day.isoformat(),
                "mutable": True,
            }
            if rec:
                payload["recurrence"] = rec
            print(json.dumps(payload))
            return 0
        if args.action == "update":
            href = args.href or (
                "https://cal.example/dav/calendars/alice/personal/fixture-uid-1.ics"
            )
            payload = {
                "ok": True,
                "fixture": True,
                "action": "update",
                "provider": args.provider or "caldav",
                "id": (args.uid or _uid_from_href(href) or "fixture-uid-1"),
                "href": href,
                "title": (args.title or "Updated").strip() or "Updated",
                "date": day.isoformat(),
                "mutable": True,
            }
            if args.recurrence is not None:
                rec = _normalize_recurrence(args.recurrence)
                if rec:
                    payload["recurrence"] = rec
            print(json.dumps(payload))
            return 0
        print(
            json.dumps(
                {
                    "ok": True,
                    "fixture": True,
                    "action": "delete",
                    "provider": args.provider or "caldav",
                    "href": args.href
                    or "https://cal.example/dav/calendars/alice/personal/fixture-uid-1.ics",
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

    day = date.fromisoformat(args.date) if args.date else date.today()
    provider = (args.provider or "").strip().lower()
    if not provider:
        # Prefer first connected writable seat
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
                    "error": "no writable seat (CalDAV or Google/Microsoft/Exchange)",
                    "action": args.action,
                }
            )
        )
        return 1

    if args.action == "create":
        result = cmd_create(
            provider, args.title, day, recurrence=args.recurrence or ""
        )
    elif args.action == "update":
        result = cmd_update(
            provider,
            args.href,
            args.title,
            day,
            args.uid,
            recurrence=args.recurrence,
        )
    else:
        result = cmd_delete(provider, args.href, args.uid)
    print(json.dumps(result))
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    sys.exit(main())
