#!/usr/bin/env python3
"""Fetch today's calendar events for Proteus Online accounts seats.

Uses `proteus-accounts token` (refresh when needed). Providers:
  google    — Calendar API v3 primary calendar
  microsoft — Graph calendarView
  nextcloud — CalDAV REPORT under Nextcloud DAV path (best-effort)
  caldav    — CalDAV REPORT on vault calendar-home URL (best-effort)
  apple     — CalDAV REPORT on iCloud caldavUrl / baseUrl (app-specific password)

Stdout: one JSON object. Never logs access tokens.
Honesty: glance consumer — create/update/delete via proteus-calendar-mutate.py
(CalDAV + Google/MS/Exchange; create may include daily/weekly/monthly RRULE).
Series edit / COUNT/UNTIL / attendees Out.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from datetime import date, datetime, timedelta, timezone
from pathlib import Path


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
        data = json.loads(out)
    except Exception as e:
        return {"ok": False, "error": str(e), "provider": provider}
    return data


def _day_bounds_utc(day: date) -> tuple[datetime, datetime]:
    start = datetime(day.year, day.month, day.day, tzinfo=timezone.utc)
    end = start + timedelta(days=1)
    return start, end


def _http_json(url: str, headers: dict, timeout: float = 15.0) -> tuple[int, dict | list | None, str]:
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


def fetch_google(access: str, day: date) -> tuple[list[dict], str]:
    start, end = _day_bounds_utc(day)
    q = urllib.parse.urlencode(
        {
            "timeMin": start.isoformat().replace("+00:00", "Z"),
            "timeMax": end.isoformat().replace("+00:00", "Z"),
            "singleEvents": "true",
            "orderBy": "startTime",
            "maxResults": "20",
        }
    )
    url = f"https://www.googleapis.com/calendar/v3/calendars/primary/events?{q}"
    status, data, err = _http_json(
        url, {"Authorization": f"Bearer {access}", "Accept": "application/json"}
    )
    if status != 200 or not isinstance(data, dict):
        return [], err or f"google HTTP {status}"
    out = []
    for item in data.get("items") or []:
        if not isinstance(item, dict):
            continue
        st = item.get("start") or {}
        en = item.get("end") or {}
        all_day = "date" in st and "dateTime" not in st
        eid = str(item.get("id") or "")
        out.append(
            {
                "id": eid,
                "title": str(item.get("summary") or "(No title)"),
                "start": str(st.get("dateTime") or st.get("date") or ""),
                "end": str(en.get("dateTime") or en.get("date") or ""),
                "allDay": bool(all_day),
                "provider": "google",
                "mutable": bool(eid),
                "href": (
                    f"https://www.googleapis.com/calendar/v3/calendars/primary/events/"
                    f"{urllib.parse.quote(eid, safe='')}"
                    if eid
                    else ""
                ),
            }
        )
    return out, ""


def fetch_microsoft(access: str, day: date) -> tuple[list[dict], str]:
    start, end = _day_bounds_utc(day)
    q = urllib.parse.urlencode(
        {
            "startDateTime": start.isoformat().replace("+00:00", "Z"),
            "endDateTime": end.isoformat().replace("+00:00", "Z"),
            "$top": "20",
            "$orderby": "start/dateTime",
            "$select": "id,subject,start,end,isAllDay",
        }
    )
    url = f"https://graph.microsoft.com/v1.0/me/calendarview?{q}"
    status, data, err = _http_json(
        url,
        {
            "Authorization": f"Bearer {access}",
            "Accept": "application/json",
            "Prefer": 'outlook.timezone="UTC"',
        },
    )
    if status != 200 or not isinstance(data, dict):
        return [], err or f"microsoft HTTP {status}"
    out = []
    for item in data.get("value") or []:
        if not isinstance(item, dict):
            continue
        st = item.get("start") or {}
        en = item.get("end") or {}
        eid = str(item.get("id") or "")
        out.append(
            {
                "id": eid,
                "title": str(item.get("subject") or "(No title)"),
                "start": str(st.get("dateTime") or ""),
                "end": str(en.get("dateTime") or ""),
                "allDay": bool(item.get("isAllDay")),
                "provider": "microsoft",
                "mutable": bool(eid),
                "href": (
                    f"https://graph.microsoft.com/v1.0/me/events/"
                    f"{urllib.parse.quote(eid, safe='')}"
                    if eid
                    else ""
                ),
            }
        )
    return out, ""


def fetch_exchange(access: str, day: date) -> tuple[list[dict], str]:
    """Same Graph calendar view as Microsoft; labeled exchange for work/school seats."""
    ev, err = fetch_microsoft(access, day)
    for e in ev:
        e["provider"] = "exchange"
    return ev, err


def _fetch_caldav_home(
    cal_url: str,
    origin_base: str,
    user: str,
    password: str,
    day: date,
    provider: str,
    fallback_hrefs: list[str] | None = None,
) -> tuple[list[dict], str]:
    """Best-effort CalDAV calendar-query under a calendar-home URL."""
    if not cal_url or not user or not password:
        return [], f"{provider} credentials incomplete"
    import base64

    auth = base64.b64encode(f"{user}:{password}".encode()).decode()
    cal_url = cal_url if cal_url.endswith("/") else f"{cal_url}/"
    start, end = _day_bounds_utc(day)
    start_s = start.strftime("%Y%m%dT000000Z")
    end_s = end.strftime("%Y%m%dT000000Z")
    body = f"""<?xml version="1.0" encoding="UTF-8"?>
<c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
  <d:prop>
    <d:getetag/>
    <c:calendar-data/>
  </d:prop>
  <c:filter>
    <c:comp-filter name="VCALENDAR">
      <c:comp-filter name="VEVENT">
        <c:time-range start="{start_s}" end="{end_s}"/>
      </c:comp-filter>
    </c:comp-filter>
  </c:filter>
</c:calendar-query>
"""
    propfind = """<?xml version="1.0" encoding="UTF-8"?>
<d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
  <d:prop><d:displayname/><c:calendar-description/></d:prop>
</d:propfind>
"""
    req = urllib.request.Request(
        cal_url,
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
        return [], f"{provider} PROPFIND: {e}"

    hrefs: list[str] = []
    try:
        root = ET.fromstring(listing)
        ns = {"d": "DAV:"}
        home_path = urllib.parse.urlparse(cal_url).path.rstrip("/")
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
        # Home itself may be a calendar collection
        hrefs = [cal_url]
    if fallback_hrefs:
        hrefs = hrefs + fallback_hrefs

    events: list[dict] = []
    errors: list[str] = []
    seen: set[str] = set()
    for href in hrefs[:4]:
        if href in seen:
            continue
        seen.add(href)
        if href.startswith("http"):
            report_url = href
        else:
            parsed = urllib.parse.urlparse(origin_base or cal_url)
            report_url = f"{parsed.scheme}://{parsed.netloc}{href}"
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
        cal_ns = {"d": "DAV:", "c": "urn:ietf:params:xml:ns:caldav"}
        try:
            root = ET.fromstring(xml_body)
            for resp_el in root.findall("d:response", cal_ns):
                ev_href = resp_el.findtext("d:href", default="", namespaces=cal_ns) or ""
                cal_data = ""
                for el in resp_el.iter():
                    tag = el.tag.rsplit("}", 1)[-1] if "}" in el.tag else el.tag
                    if tag == "calendar-data" and el.text:
                        cal_data = el.text
                        break
                if not cal_data or "BEGIN:VEVENT" not in cal_data:
                    continue
                title = "(No title)"
                start_ev = ""
                uid = ""
                for line in cal_data.splitlines():
                    if line.startswith("SUMMARY:") or line.startswith("SUMMARY;"):
                        title = line.split(":", 1)[-1].strip() or title
                    if line.startswith("DTSTART:") or line.startswith("DTSTART;"):
                        start_ev = line.split(":", 1)[-1].strip()
                    if line.startswith("UID:") or line.startswith("UID;"):
                        uid = line.split(":", 1)[-1].strip()
                if ev_href.startswith("http"):
                    abs_href = ev_href
                else:
                    parsed = urllib.parse.urlparse(origin_base or cal_url)
                    abs_href = f"{parsed.scheme}://{parsed.netloc}{ev_href}"
                events.append(
                    {
                        "id": uid or abs_href,
                        "title": title,
                        "start": start_ev,
                        "end": "",
                        "allDay": "T" not in start_ev,
                        "provider": provider,
                        "mutable": True,
                        "href": abs_href,
                    }
                )
        except ET.ParseError:
            for block in xml_body.split("BEGIN:VEVENT"):
                if "SUMMARY:" not in block and "SUMMARY;" not in block:
                    continue
                title = "(No title)"
                start_ev = ""
                uid = ""
                for line in block.splitlines():
                    if line.startswith("SUMMARY:") or line.startswith("SUMMARY;"):
                        title = line.split(":", 1)[-1].strip() or title
                    if line.startswith("DTSTART:") or line.startswith("DTSTART;"):
                        start_ev = line.split(":", 1)[-1].strip()
                    if line.startswith("UID:") or line.startswith("UID;"):
                        uid = line.split(":", 1)[-1].strip()
                events.append(
                    {
                        "id": uid,
                        "title": title,
                        "start": start_ev,
                        "end": "",
                        "allDay": "T" not in start_ev,
                        "provider": provider,
                        "mutable": bool(uid),
                        "href": "",
                    }
                )
        if events:
            break
    if not events and errors:
        return [], errors[0]
    return events[:20], ""


def fetch_nextcloud(base: str, user: str, password: str, day: date) -> tuple[list[dict], str]:
    """Best-effort CalDAV under Nextcloud personal calendars path."""
    if not base or not user or not password:
        return [], "nextcloud credentials incomplete"
    cal_url = f"{base.rstrip('/')}/remote.php/dav/calendars/{urllib.parse.quote(user)}/"
    fallback = [f"/remote.php/dav/calendars/{urllib.parse.quote(user)}/personal/"]
    return _fetch_caldav_home(cal_url, base, user, password, day, "nextcloud", fallback)


def fetch_caldav(base: str, user: str, password: str, day: date) -> tuple[list[dict], str]:
    """Best-effort CalDAV on a user-supplied calendar-home URL."""
    return _fetch_caldav_home(base.rstrip("/") + "/", base, user, password, day, "caldav")


def fetch_apple(tok: dict, day: date) -> tuple[list[dict], str]:
    """Best-effort CalDAV on Apple / iCloud seat endpoints."""
    base = str(tok.get("caldavUrl") or tok.get("baseUrl") or "").strip()
    user = str(tok.get("username") or tok.get("email") or "").strip()
    password = str(tok.get("accessToken") or "")
    return _fetch_caldav_home(base.rstrip("/") + "/", base, user, password, day, "apple")


def main() -> int:
    ap = argparse.ArgumentParser(description="Proteus calendar glance fetch")
    ap.add_argument("--date", default="", help="YYYY-MM-DD (default today local)")
    args = ap.parse_args()
    if args.date:
        day = date.fromisoformat(args.date)
    else:
        day = date.today()

    # Offline fixture for smoke
    if os.environ.get("PROTEUS_CALENDAR_FIXTURE") == "1":
        print(
            json.dumps(
                {
                    "ok": True,
                    "date": day.isoformat(),
                    "events": [
                        {
                            "id": "fixture-uid-1",
                            "title": "Fixture event",
                            "start": f"{day.isoformat()}T09:00:00Z",
                            "end": f"{day.isoformat()}T10:00:00Z",
                            "allDay": False,
                            "provider": "caldav",
                            "mutable": True,
                            "href": "https://cal.example/dav/calendars/alice/personal/fixture-uid-1.ics",
                        }
                    ],
                    "seats": 1,
                    "mutableSeats": 1,
                    "errors": [],
                }
            )
        )
        return 0

    providers = ("google", "microsoft", "exchange", "nextcloud", "caldav", "apple")
    writable = frozenset(
        {"google", "microsoft", "exchange", "nextcloud", "caldav", "apple"}
    )
    events: list[dict] = []
    errors: list[str] = []
    seats = 0
    mutable_seats = 0
    for prov in providers:
        tok = _token(prov)
        if tok is None:
            errors.append("proteus-accounts not installed")
            break
        if not tok.get("ok"):
            # No seat for this provider — skip quietly
            continue
        seats += 1
        if prov in writable:
            mutable_seats += 1
        access = str(tok.get("accessToken") or "")
        if prov == "google":
            ev, err = fetch_google(access, day)
        elif prov == "microsoft":
            ev, err = fetch_microsoft(access, day)
        elif prov == "exchange":
            ev, err = fetch_exchange(access, day)
        elif prov == "caldav":
            ev, err = fetch_caldav(
                str(tok.get("baseUrl") or ""),
                str(tok.get("username") or ""),
                access,
                day,
            )
        elif prov == "apple":
            ev, err = fetch_apple(tok, day)
        else:
            ev, err = fetch_nextcloud(
                str(tok.get("baseUrl") or ""),
                str(tok.get("username") or ""),
                access,
                day,
            )
        if err:
            errors.append(f"{prov}: {err}")
        events.extend(ev)

    def sort_key(e: dict) -> str:
        return str(e.get("start") or "")

    events.sort(key=sort_key)
    print(
        json.dumps(
            {
                "ok": True,
                "date": day.isoformat(),
                "events": events[:30],
                "seats": seats,
                "mutableSeats": mutable_seats,
                "errors": errors,
                "hint": (
                    "Reconnect Google/Microsoft seats if calendar scope was added after connect"
                    if any("403" in e or "insufficient" in e.lower() for e in errors)
                    else ""
                ),
            }
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
