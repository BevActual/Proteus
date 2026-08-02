#!/usr/bin/env python3
"""Read-only VM/container glance for Proteus HostHome.

Probes libvirt (virsh) and podman/docker when present. Never mutates state.
Stdout: one JSON object. Fixture: PROTEUS_WORKLOADS_FIXTURE=1.
Honesty: thin glance — not the Host workloads app / create-destroy UI.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from typing import Any


def _run(cmd: list[str], timeout: float = 8.0) -> tuple[int, str, str]:
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return r.returncode, (r.stdout or "").strip(), (r.stderr or "").strip()
    except FileNotFoundError:
        return 127, "", "not found"
    except Exception as e:
        return 1, "", str(e)


def _which(name: str) -> str:
    return shutil.which(name) or ""


def _fixture() -> dict[str, Any]:
    return {
        "ok": True,
        "fixture": True,
        "libvirt": {
            "available": True,
            "tool": "virsh",
            "domains": [
                {"name": "proteus-guest", "state": "running"},
                {"name": "idle-box", "state": "shut off"},
            ],
        },
        "containers": {
            "available": True,
            "engine": "podman",
            "items": [
                {"name": "registry", "status": "Up 2 hours", "id": "abcd1234"},
            ],
        },
        "summary": "2 VMs · 1 container",
        "hint": "Fixture glance — install libvirt/podman for live data",
        "errors": [],
    }


def _virsh_domains() -> tuple[dict[str, Any], list[str]]:
    errs: list[str] = []
    tool = _which("virsh")
    if not tool:
        return {
            "available": False,
            "tool": "",
            "domains": [],
        }, []
    # Prefer system URI; fall back to session / default.
    uris = ["qemu:///system", "qemu:///session", ""]
    out = ""
    code = 1
    for uri in uris:
        cmd = [tool, "list", "--all", "--name"]
        if uri:
            cmd = [tool, "-c", uri, "list", "--all"]
            # state+name: list --all prints table
            code, stdout, err = _run(cmd)
            if code == 0 and stdout:
                out = stdout
                break
            if err and "error" in err.lower():
                errs.append(err.split("\n")[0][:160])
        else:
            code, stdout, err = _run([tool, "list", "--all"])
            if code == 0 and stdout:
                out = stdout
                break
            if err:
                errs.append(err.split("\n")[0][:160])

    domains: list[dict[str, str]] = []
    if out:
        for line in out.splitlines():
            line = line.strip()
            if not line or line.startswith("Id") or set(line) <= {"-", " "}:
                continue
            # Formats: " 2  name  running" or name-only from --name
            parts = line.split()
            if len(parts) >= 3 and parts[0].lstrip("-").isdigit():
                name = parts[1]
                state = " ".join(parts[2:])
            elif len(parts) == 1:
                name = parts[0]
                state = "unknown"
            else:
                # session list without Id column sometimes: name state…
                name = parts[0]
                state = " ".join(parts[1:]) if len(parts) > 1 else "unknown"
            if name in ("-", "Name"):
                continue
            domains.append({"name": name, "state": state})

    # Enrich states via domstate if we only got names
    if domains and all(d["state"] == "unknown" for d in domains):
        for d in domains[:12]:
            c, st, _ = _run([tool, "domstate", d["name"]], timeout=3.0)
            if c == 0 and st:
                d["state"] = st.split("\n")[0].strip()

    return {
        "available": True,
        "tool": "virsh",
        "domains": domains[:24],
    }, errs[:3]


def _containers() -> tuple[dict[str, Any], list[str]]:
    errs: list[str] = []
    for engine in ("podman", "docker"):
        tool = _which(engine)
        if not tool:
            continue
        code, stdout, err = _run(
            [
                tool,
                "ps",
                "-a",
                "--format",
                "{{.Names}}\t{{.Status}}\t{{.ID}}",
            ]
        )
        if code != 0:
            if err:
                errs.append(f"{engine}: {err.split(chr(10))[0][:140]}")
            continue
        items: list[dict[str, str]] = []
        for line in stdout.splitlines():
            line = line.strip()
            if not line:
                continue
            bits = line.split("\t")
            name = bits[0] if bits else ""
            status = bits[1] if len(bits) > 1 else ""
            cid = bits[2] if len(bits) > 2 else ""
            if name:
                items.append(
                    {
                        "name": name,
                        "status": status,
                        "id": cid[:12],
                    }
                )
        return {
            "available": True,
            "engine": engine,
            "items": items[:24],
        }, errs[:3]
    return {
        "available": False,
        "engine": "",
        "items": [],
    }, errs[:3]


def _summary(libvirt: dict[str, Any], containers: dict[str, Any]) -> str:
    parts: list[str] = []
    if libvirt.get("available"):
        n = len(libvirt.get("domains") or [])
        running = sum(
            1
            for d in (libvirt.get("domains") or [])
            if "run" in str(d.get("state", "")).lower()
        )
        if n:
            label = f"{n} VM" + ("s" if n != 1 else "")
            if running:
                label += f" ({running} up)"
            parts.append(label)
        else:
            parts.append("No VMs")
    if containers.get("available"):
        n = len(containers.get("items") or [])
        eng = containers.get("engine") or "container"
        if n:
            parts.append(f"{n} container" + ("s" if n != 1 else "") + f" ({eng})")
        else:
            parts.append(f"No containers ({eng})")
    if not parts:
        return "No libvirt or container engine"
    return " · ".join(parts)


def main() -> int:
    if os.environ.get("PROTEUS_WORKLOADS_FIXTURE") == "1":
        print(json.dumps(_fixture(), separators=(",", ":")))
        return 0

    errors: list[str] = []
    libvirt, e1 = _virsh_domains()
    errors.extend(e1)
    containers, e2 = _containers()
    errors.extend(e2)

    hint = ""
    if not libvirt.get("available") and not containers.get("available"):
        hint = "Install libvirt (virsh) and/or podman/docker for live glance"
    elif not libvirt.get("available"):
        hint = "libvirt/virsh not found — showing containers only"
    elif not containers.get("available"):
        hint = "podman/docker not found — showing libvirt only"

    payload = {
        "ok": True,
        "fixture": False,
        "libvirt": libvirt,
        "containers": containers,
        "summary": _summary(libvirt, containers),
        "hint": hint,
        "errors": errors[:5],
    }
    print(json.dumps(payload, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except BrokenPipeError:
        sys.exit(0)
