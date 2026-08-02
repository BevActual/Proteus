#!/usr/bin/env python3
"""Manage the lock-screen unlock PIN (user-owned hash under ~/.local/share).

Usage:
  proteus-pin.py status
  proteus-pin.py set     # stdin: password\\n pin\\n pin_confirm\\n
  proteus-pin.py change  # same as set (overwrite)
  proteus-pin.py clear   # stdin: password\\n   OR   pin\\n  (with --with pin|password)

Exit: 0 ok, 1 auth/validation fail, 2 usage/helper error.
Stdout: JSON status (or {"ok":true,...} on mutate).
"""
from __future__ import annotations

import json
import os
import sys

_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if _SCRIPT_DIR not in sys.path:
    sys.path.insert(0, _SCRIPT_DIR)

import proteus_auth  # noqa: E402


def _read_line() -> str:
    return sys.stdin.readline().rstrip("\n\r")


def cmd_status() -> int:
    print(json.dumps(proteus_auth.pin_status(), separators=(",", ":")))
    return 0


def cmd_set() -> int:
    user = proteus_auth.current_user()
    if not user:
        sys.stderr.write("no USER\n")
        return 2
    password = _read_line()
    pin = _read_line()
    confirm = _read_line()
    try:
        if not proteus_auth.authenticate_password(user, password, service="proteus-lock"):
            print(json.dumps({"ok": False, "error": "wrong_password"}))
            return 1
        if pin != confirm:
            print(json.dumps({"ok": False, "error": "pin_mismatch"}))
            return 1
        proteus_auth.write_pin(pin)
    except ValueError as exc:
        print(json.dumps({"ok": False, "error": str(exc)}))
        return 1
    except OSError as exc:
        sys.stderr.write(f"pin write error: {exc}\n")
        return 2
    st = proteus_auth.pin_status()
    st["ok"] = True
    print(json.dumps(st, separators=(",", ":")))
    return 0


def cmd_clear() -> int:
    user = proteus_auth.current_user()
    if not user:
        sys.stderr.write("no USER\n")
        return 2
    # Optional: proteus-pin.py clear password|pin
    mode = "auto"
    if len(sys.argv) > 2 and sys.argv[2] in ("password", "pin"):
        mode = sys.argv[2]
    secret = _read_line()
    try:
        if mode == "password":
            ok = proteus_auth.authenticate_password(user, secret, service="proteus-lock")
        elif mode == "pin":
            ok = proteus_auth.verify_pin(secret)
        else:
            # Prefer password if secret is not a pure digit PIN of configured length.
            st = proteus_auth.pin_status()
            if st.get("configured") and secret.isdigit() and len(secret) == int(st.get("length") or 0):
                ok = proteus_auth.verify_pin(secret)
            else:
                ok = proteus_auth.authenticate_password(user, secret, service="proteus-lock")
        if not ok:
            print(json.dumps({"ok": False, "error": "auth_failed"}))
            return 1
        proteus_auth.clear_pin()
    except OSError as exc:
        sys.stderr.write(f"pin clear error: {exc}\n")
        return 2
    print(json.dumps({"ok": True, "configured": False, "length": 0}, separators=(",", ":")))
    return 0


def main() -> int:
    cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
    if cmd in ("status", "--status"):
        return cmd_status()
    if cmd in ("set", "change"):
        return cmd_set()
    if cmd == "clear":
        return cmd_clear()
    sys.stderr.write("usage: proteus-pin.py status|set|change|clear\n")
    return 2


if __name__ == "__main__":
    sys.exit(main())
