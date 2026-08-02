#!/usr/bin/env python3
"""Fallback greetd status JSON when proteus-greetd binary is not installed."""
from __future__ import annotations

import json
import pathlib
import re
import shutil
import subprocess


def main() -> None:
    o = {
        "ok": True,
        "active": False,
        "enabled": False,
        "autologin": False,
        "user": "",
        "command": "",
        "hint": "greetd not installed",
        "conf": "/etc/greetd/config.toml",
    }
    conf = pathlib.Path("/etc/greetd/config.toml")
    o["conf"] = str(conf)
    has_systemctl = bool(shutil.which("systemctl"))
    if has_systemctl:
        a = subprocess.run(
            ["systemctl", "is-active", "greetd"], capture_output=True, text=True
        )
        o["active"] = (a.stdout or "").strip() == "active"
        e = subprocess.run(
            ["systemctl", "is-enabled", "greetd"], capture_output=True, text=True
        )
        o["enabled"] = (e.stdout or "").strip() in (
            "enabled",
            "enabled-runtime",
            "static",
        )
    if conf.is_file():
        t = conf.read_text(errors="replace")
        m = re.search(r"\[initial_session\](.*?)(?=\n\[|\Z)", t, re.S)
        if m:
            block = m.group(1)
            um = re.search(r'^\s*user\s*=\s*"([^"]+)"', block, re.M)
            cm = re.search(r'^\s*command\s*=\s*"([^"]+)"', block, re.M)
            if um:
                o["user"] = um.group(1)
            if cm:
                o["command"] = cm.group(1)
            o["autologin"] = bool(o["user"] and o["command"])
        bits = []
        if o["active"]:
            bits.append("active")
        elif o["enabled"]:
            bits.append("enabled")
        elif has_systemctl:
            bits.append("inactive")
        if o["autologin"]:
            bits.append("autologin " + o["user"])
        else:
            bits.append("no initial_session")
        o["hint"] = " · ".join(bits) if bits else "config present"
    elif has_systemctl:
        o["hint"] = (
            "greetd unit "
            + (
                "active"
                if o["active"]
                else ("enabled" if o["enabled"] else "inactive")
            )
            + " · no config.toml"
        )
    print(json.dumps(o))


if __name__ == "__main__":
    main()
