#!/usr/bin/env python3
"""Unlock helper for the Proteus lock screen.

Usage:
  check-unlock.py --status
  check-unlock.py <user> pin|password   # secret on stdin (one line)

Exit codes: 0 success / status printed, 1 auth fail, 2 helper error.
"""
from __future__ import annotations

import json
import os
import sys

_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if _SCRIPT_DIR not in sys.path:
    sys.path.insert(0, _SCRIPT_DIR)

import proteus_auth  # noqa: E402


def main() -> int:
    if len(sys.argv) >= 2 and sys.argv[1] in ("--status", "status"):
        print(json.dumps(proteus_auth.pin_status(), separators=(",", ":")))
        return 0

    user = sys.argv[1] if len(sys.argv) > 1 else ""
    mode = (sys.argv[2] if len(sys.argv) > 2 else "password").strip().lower()
    secret = sys.stdin.readline().rstrip("\n\r")
    if not user:
        sys.stderr.write("usage: check-unlock.py <user> pin|password\n")
        return 2
    if mode not in ("pin", "password"):
        sys.stderr.write("mode must be pin or password\n")
        return 2

    try:
        if mode == "pin":
            ok = proteus_auth.verify_pin(secret)
        else:
            ok = proteus_auth.authenticate_password(user, secret, service="proteus-lock")
    except OSError as exc:
        sys.stderr.write(f"auth error: {exc}\n")
        return 2
    except Exception as exc:  # noqa: BLE001 — surface helper crashes to QS
        sys.stderr.write(f"auth error: {exc}\n")
        return 2
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
