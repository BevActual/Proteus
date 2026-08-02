#!/usr/bin/env python3
"""Send a thin plain-text mail for Proteus Online accounts seats.

Writable:
  · OAuth — google (gmail.send) · microsoft / exchange (Mail.Send)
  · IMAP / Apple — SMTP derived from IMAP host (STARTTLS :587)

Thin UX: To + Subject + Body only. No CC/BCC · attachments · HTML · drafts ·
reply/forward. Stdout: one JSON object. Never logs passwords/tokens.
"""
from __future__ import annotations

import argparse
import base64
import email.message
import json
import os
import smtplib
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from email.utils import formataddr, formatdate, make_msgid
from pathlib import Path

OAUTH_SENDABLE = ("google", "microsoft", "exchange")
SMTP_SENDABLE = ("imap", "apple")
SENDABLE = OAUTH_SENDABLE + SMTP_SENDABLE


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


def _http_json(
    url: str,
    headers: dict,
    body: dict | None = None,
    method: str = "GET",
    timeout: float = 20.0,
) -> tuple[int, dict | list | None, str]:
    data = None
    hdrs = dict(headers)
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        hdrs.setdefault("Content-Type", "application/json")
    req = urllib.request.Request(url, data=data, headers=hdrs, method=method)
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
        err_body = e.read().decode("utf-8", errors="replace") if e.fp else ""
        return e.code, None, err_body[:400] or str(e)
    except Exception as e:
        return 0, None, str(e)


def _rfc2822(
    *,
    from_addr: str,
    to_addr: str,
    subject: str,
    body: str,
) -> bytes:
    msg = email.message.EmailMessage()
    msg["From"] = from_addr
    msg["To"] = to_addr
    msg["Subject"] = subject
    msg["Date"] = formatdate(localtime=True)
    msg["Message-ID"] = make_msgid()
    msg.set_content(body or "")
    return msg.as_bytes()


def _b64url(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).decode("ascii").rstrip("=")


def send_google(access: str, from_addr: str, to_addr: str, subject: str, body: str) -> dict:
    raw = _b64url(_rfc2822(from_addr=from_addr, to_addr=to_addr, subject=subject, body=body))
    status, data, err = _http_json(
        "https://gmail.googleapis.com/gmail/v1/users/me/messages/send",
        {"Authorization": f"Bearer {access}"},
        body={"raw": raw},
        method="POST",
    )
    if status in (200, 202) and isinstance(data, dict):
        return {
            "ok": True,
            "provider": "google",
            "id": str(data.get("id") or ""),
            "to": to_addr,
            "subject": subject,
        }
    return {
        "ok": False,
        "error": f"gmail send HTTP {status}: {err or data}",
        "provider": "google",
    }


def send_microsoft(
    access: str, to_addr: str, subject: str, body: str, provider: str = "microsoft"
) -> dict:
    payload = {
        "message": {
            "subject": subject,
            "body": {"contentType": "Text", "content": body or ""},
            "toRecipients": [{"emailAddress": {"address": to_addr}}],
        },
        "saveToSentItems": True,
    }
    status, data, err = _http_json(
        "https://graph.microsoft.com/v1.0/me/sendMail",
        {"Authorization": f"Bearer {access}"},
        body=payload,
        method="POST",
    )
    # Graph sendMail returns 202 Accepted with empty body on success.
    if status in (200, 202):
        return {
            "ok": True,
            "provider": provider,
            "to": to_addr,
            "subject": subject,
        }
    return {
        "ok": False,
        "error": f"{provider} sendMail HTTP {status}: {err or data}",
        "provider": provider,
    }


def _smtp_endpoint(provider: str, tok: dict) -> tuple[str, int]:
    if provider == "apple":
        host = str(tok.get("imapHost") or "imap.mail.me.com").strip()
        if host.startswith("imap."):
            return "smtp." + host[5:], 587
        if "mail.me.com" in host:
            return "smtp.mail.me.com", 587
        return "smtp.mail.me.com", 587
    base = str(tok.get("baseUrl") or "").strip()
    host = ""
    if base:
        u = urllib.parse.urlparse(base if "://" in base else f"imaps://{base}")
        host = u.hostname or ""
    if not host:
        host = str(tok.get("imapHost") or "").strip()
    if host.startswith("imap."):
        return "smtp." + host[5:], 587
    return host, 587


def send_smtp(
    provider: str,
    tok: dict,
    to_addr: str,
    subject: str,
    body: str,
) -> dict:
    user = str(tok.get("username") or tok.get("email") or "").strip()
    password = str(tok.get("accessToken") or "")
    if not user or not password:
        return {"ok": False, "error": f"{provider} seat incomplete", "provider": provider}
    smtp_host, smtp_port = _smtp_endpoint(provider, tok)
    if not smtp_host:
        return {"ok": False, "error": f"{provider} SMTP host unknown", "provider": provider}
    from_addr = user if "@" in user else formataddr(("", user))
    raw = _rfc2822(from_addr=from_addr, to_addr=to_addr, subject=subject, body=body)
    try:
        with smtplib.SMTP(smtp_host, smtp_port, timeout=20) as smtp:
            smtp.ehlo()
            smtp.starttls()
            smtp.ehlo()
            smtp.login(user, password)
            smtp.sendmail(user, [to_addr], raw)
        return {
            "ok": True,
            "provider": provider,
            "to": to_addr,
            "subject": subject,
            "via": f"{smtp_host}:{smtp_port}",
        }
    except Exception as e:
        return {"ok": False, "error": f"{provider} SMTP: {e}", "provider": provider}


def list_providers() -> dict:
    if os.environ.get("PROTEUS_MAIL_SEND_FIXTURE") == "1":
        return {
            "ok": True,
            "providers": list(SENDABLE),
            "sendableSeats": 1,
            "seats": [{"provider": "fixture", "label": "fixture"}],
        }
    seats = []
    for prov in SENDABLE:
        tok = _token(prov)
        if tok is None:
            return {
                "ok": False,
                "error": "proteus-accounts not installed",
                "providers": list(SENDABLE),
                "sendableSeats": 0,
                "seats": [],
            }
        if tok.get("ok"):
            seats.append(
                {
                    "provider": prov,
                    "label": str(tok.get("email") or tok.get("username") or prov),
                }
            )
    return {
        "ok": True,
        "providers": list(SENDABLE),
        "sendableSeats": len(seats),
        "seats": seats,
    }


def send_mail(to_addr: str, subject: str, body: str, provider: str = "") -> dict:
    to_addr = (to_addr or "").strip()
    subject = (subject or "").strip()
    body = body or ""
    if not to_addr or "@" not in to_addr:
        return {"ok": False, "error": "To address required"}
    if not subject:
        return {"ok": False, "error": "Subject required"}

    if os.environ.get("PROTEUS_MAIL_SEND_FIXTURE") == "1":
        return {
            "ok": True,
            "action": "send",
            "provider": provider or "fixture",
            "to": to_addr,
            "subject": subject,
        }

    order = [provider] if provider in SENDABLE else list(SENDABLE)
    last_err = "no sendable seat"
    for prov in order:
        tok = _token(prov)
        if tok is None:
            return {"ok": False, "error": "proteus-accounts not installed"}
        if not tok.get("ok"):
            continue
        access = str(tok.get("accessToken") or "")
        from_addr = str(tok.get("email") or tok.get("username") or "").strip()
        if prov == "google":
            result = send_google(access, from_addr or "me", to_addr, subject, body)
        elif prov in ("microsoft", "exchange"):
            result = send_microsoft(access, to_addr, subject, body, provider=prov)
        else:
            result = send_smtp(prov, tok, to_addr, subject, body)
        if result.get("ok"):
            result["action"] = "send"
            return result
        last_err = str(result.get("error") or last_err)
        if provider:
            return result
    return {"ok": False, "error": last_err}


def main() -> int:
    ap = argparse.ArgumentParser(description="Proteus mail send")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p_send = sub.add_parser("send", help="send plain-text mail")
    p_send.add_argument("--to", required=True)
    p_send.add_argument("--subject", required=True)
    p_send.add_argument("--body", default="")
    p_send.add_argument("--provider", default="")

    sub.add_parser("providers", help="list sendable providers / seats")

    args = ap.parse_args()
    if args.cmd == "providers":
        print(json.dumps(list_providers()))
        return 0
    if args.cmd == "send":
        print(
            json.dumps(
                send_mail(
                    args.to,
                    args.subject,
                    args.body,
                    provider=str(args.provider or ""),
                )
            )
        )
        return 0
    print(json.dumps({"ok": False, "error": "unknown command"}))
    return 2


if __name__ == "__main__":
    sys.exit(main())
