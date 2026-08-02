#!/usr/bin/env python3
"""VM/container inventory + mutate for Proteus Host.

Probes libvirt (virsh) and podman/docker when present.
Mutations: start|stop|kill|create|destroy
  VM: virsh start/shutdown · destroy (force power-off) · define · undefine (stopped)
  CTR: engine start/stop/kill · run -d · rm (stopped only)
Stdout: one JSON object. Fixture: PROTEUS_WORKLOADS_FIXTURE=1.
Honesty: kill = force power-off (keep definition). Settings virt · headless-no-QS Out.
Remove while running (rm -f) stays Out.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

_NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,62}$")


def _run(cmd: list[str], timeout: float = 30.0) -> tuple[int, str, str]:
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


def _virsh_connect() -> tuple[str, str, list[str]]:
    """Return (tool, uri, errs). uri may be '' for default."""
    errs: list[str] = []
    tool = _which("virsh")
    if not tool:
        return "", "", []
    for uri in ("qemu:///system", "qemu:///session", ""):
        cmd = [tool, "list", "--all"]
        if uri:
            cmd = [tool, "-c", uri, "list", "--all"]
        code, stdout, err = _run(cmd, timeout=8.0)
        if code == 0 and stdout is not None:
            return tool, uri, errs
        if err:
            errs.append(err.split("\n")[0][:160])
    return tool, "", errs


def _virsh_cmd(tool: str, uri: str, *args: str) -> list[str]:
    if uri:
        return [tool, "-c", uri, *args]
    return [tool, *args]


def _virsh_domains() -> tuple[dict[str, Any], list[str]]:
    tool, uri, errs = _virsh_connect()
    if not tool:
        return {"available": False, "tool": "", "domains": []}, []
    code, out, err = _run(_virsh_cmd(tool, uri, "list", "--all"), timeout=8.0)
    if code != 0:
        if err:
            errs.append(err.split("\n")[0][:160])
        return {"available": True, "tool": "virsh", "domains": []}, errs[:3]

    domains: list[dict[str, str]] = []
    for line in out.splitlines():
        line = line.strip()
        if not line or line.startswith("Id") or set(line) <= {"-", " "}:
            continue
        parts = line.split()
        if len(parts) >= 3 and parts[0].lstrip("-").isdigit():
            name = parts[1]
            state = " ".join(parts[2:])
            domains.append({"name": name, "state": state})
        elif len(parts) >= 2 and parts[0] == "-":
            name = parts[1]
            state = " ".join(parts[2:]) if len(parts) > 2 else "shut off"
            domains.append({"name": name, "state": state})
    return {"available": True, "tool": "virsh", "domains": domains}, errs[:3]


def _container_engine() -> tuple[str, str]:
    for eng in ("podman", "docker"):
        tool = _which(eng)
        if tool:
            return eng, tool
    return "", ""


def _containers() -> tuple[dict[str, Any], list[str]]:
    errs: list[str] = []
    engine, tool = _container_engine()
    if not tool:
        return {"available": False, "engine": "", "items": []}, []
    code, out, err = _run(
        [tool, "ps", "-a", "--format", "{{.Names}}\t{{.Status}}\t{{.ID}}"],
        timeout=8.0,
    )
    if code != 0:
        if err:
            errs.append(err.split("\n")[0][:160])
        return {"available": True, "engine": engine, "items": []}, errs[:3]
    items: list[dict[str, str]] = []
    for line in out.splitlines():
        bits = line.split("\t")
        if not bits or not bits[0]:
            continue
        items.append(
            {
                "name": bits[0],
                "status": bits[1] if len(bits) > 1 else "",
                "id": (bits[2][:12] if len(bits) > 2 else ""),
            }
        )
    return {"available": True, "engine": engine, "items": items}, errs[:3]


def _summary(libvirt: dict[str, Any], containers: dict[str, Any]) -> str:
    n_vm = len(libvirt.get("domains") or [])
    n_ct = len(containers.get("items") or [])
    bits = []
    if libvirt.get("available"):
        bits.append(f"{n_vm} VM" + ("s" if n_vm != 1 else ""))
    if containers.get("available"):
        eng = containers.get("engine") or "ctr"
        bits.append(f"{n_ct} {eng}")
    return " · ".join(bits) if bits else "No workload engines"


def _emit_inventory() -> int:
    if os.environ.get("PROTEUS_WORKLOADS_FIXTURE") == "1":
        print(json.dumps(_fixture(), separators=(",", ":")))
        return 0
    errors: list[str] = []
    libvirt, e1 = _virsh_domains()
    containers, e2 = _containers()
    errors.extend(e1)
    errors.extend(e2)
    hint = ""
    if not libvirt.get("available") and not containers.get("available"):
        hint = "Install libvirt (virsh) and/or podman|docker for Host workloads"
    elif not libvirt.get("available"):
        hint = "libvirt/virsh not found — showing containers only"
    elif not containers.get("available"):
        hint = "podman/docker not found — showing libvirt only"

    print(
        json.dumps(
            {
                "ok": True,
                "fixture": False,
                "libvirt": libvirt,
                "containers": containers,
                "summary": _summary(libvirt, containers),
                "hint": hint,
                "errors": errors[:5],
            },
            separators=(",", ":"),
        )
    )
    return 0


def _vm_running(state: str) -> bool:
    return "run" in state.lower()


def _ctr_running(status: str) -> bool:
    s = status.lower()
    return s.startswith("up") or "running" in s


def _valid_name(name: str) -> bool:
    return bool(_NAME_RE.match(name or ""))


def _ok_json(**kwargs: Any) -> int:
    print(json.dumps({"ok": True, **kwargs}, separators=(",", ":")))
    return 0


def _err_json(msg: str, **kwargs: Any) -> int:
    print(json.dumps({"ok": False, "error": msg, **kwargs}, separators=(",", ":")))
    return 1


def _minimal_vm_xml(name: str, disk: str) -> str:
    # Thin define — existing qcow2 only; no ISO/network wizard.
    disk_esc = disk.replace("&", "&amp;").replace("'", "&apos;")
    name_esc = name.replace("&", "&amp;").replace("'", "&apos;")
    return f"""<domain type='kvm'>
  <name>{name_esc}</name>
  <memory unit='MiB'>512</memory>
  <vcpu>1</vcpu>
  <os>
    <type arch='x86_64' machine='q35'>hvm</type>
    <boot dev='hd'/>
  </os>
  <devices>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2'/>
      <source file='{disk_esc}'/>
      <target dev='vda' bus='virtio'/>
    </disk>
    <console type='pty'/>
  </devices>
</domain>
"""


def _mutate_power(action: str, kind: str, name: str, dry_run: bool) -> int:
    kind = kind.strip().lower()
    action = action.strip().lower()
    name = name.strip()
    if action not in ("start", "stop", "kill"):
        return _err_json("action must be start|stop|kill")
    if kind not in ("vm", "container"):
        return _err_json("kind must be vm|container")
    if not _valid_name(name):
        return _err_json("invalid name")

    if os.environ.get("PROTEUS_WORKLOADS_FIXTURE") == "1":
        return _ok_json(
            fixture=True,
            action=action,
            kind=kind,
            name=name,
            dryRun=dry_run,
            command=["fixture", action, kind, name],
            noop=False,
        )

    if kind == "vm":
        tool, uri, _ = _virsh_connect()
        if not tool:
            return _err_json("virsh not available")
        code, st, err = _run(_virsh_cmd(tool, uri, "domstate", name), timeout=5.0)
        state = st.split("\n")[0].strip() if code == 0 and st else ""
        if code != 0 and err and "no domain" in err.lower():
            return _err_json(f"unknown domain: {name}")
        running = _vm_running(state) if state else False
        if action == "start" and running:
            return _ok_json(action=action, kind=kind, name=name, noop=True, dryRun=dry_run)
        if action in ("stop", "kill") and state and not running:
            return _ok_json(action=action, kind=kind, name=name, noop=True, dryRun=dry_run)
        if action == "start":
            sub = "start"
        elif action == "kill":
            # Force power-off — keeps domain defined (≠ undefine / Remove).
            sub = "destroy"
        else:
            sub = "shutdown"
        cmd = _virsh_cmd(tool, uri, sub, name)
        if dry_run:
            return _ok_json(
                action=action, kind=kind, name=name, dryRun=True, command=cmd, noop=False
            )
        code, out, err = _run(cmd, timeout=60.0)
        if code != 0:
            return _err_json(
                (err or out or f"virsh {sub} failed")[:240],
                action=action,
                kind=kind,
                name=name,
            )
        return _ok_json(
            action=action, kind=kind, name=name, dryRun=False, noop=False, command=cmd
        )

    engine, tool = _container_engine()
    if not tool:
        return _err_json("podman/docker not available")
    code, stdout, err = _run(
        [tool, "ps", "-a", "--format", "{{.Names}}\t{{.Status}}", "--filter", f"name=^{name}$"],
        timeout=8.0,
    )
    status = ""
    if code == 0 and stdout:
        for line in stdout.splitlines():
            bits = line.split("\t")
            if bits and bits[0] == name:
                status = bits[1] if len(bits) > 1 else ""
                break
    running = _ctr_running(status) if status else False
    if action == "start" and running:
        return _ok_json(
            action=action, kind=kind, name=name, noop=True, dryRun=dry_run, engine=engine
        )
    if action in ("stop", "kill") and status and not running:
        return _ok_json(
            action=action, kind=kind, name=name, noop=True, dryRun=dry_run, engine=engine
        )
    # kill = engine kill (SIGKILL main); stop = graceful; never rm -f here.
    eng_action = "kill" if action == "kill" else action
    cmd = [tool, eng_action, name]
    if dry_run:
        return _ok_json(
            action=action,
            kind=kind,
            name=name,
            dryRun=True,
            command=cmd,
            engine=engine,
            noop=False,
        )
    code, out, err = _run(cmd, timeout=60.0)
    if code != 0:
        return _err_json(
            (err or out or f"{engine} {action} failed")[:240],
            action=action,
            kind=kind,
            name=name,
            engine=engine,
        )
    return _ok_json(
        action=action,
        kind=kind,
        name=name,
        dryRun=False,
        noop=False,
        command=cmd,
        engine=engine,
    )


def _mutate_create(kind: str, name: str, disk: str, image: str, dry_run: bool) -> int:
    kind = kind.strip().lower()
    name = name.strip()
    disk = disk.strip()
    image = image.strip()
    if kind not in ("vm", "container"):
        return _err_json("kind must be vm|container")
    if not _valid_name(name):
        return _err_json("invalid name")

    if os.environ.get("PROTEUS_WORKLOADS_FIXTURE") == "1":
        extra = disk if kind == "vm" else image
        return _ok_json(
            fixture=True,
            action="create",
            kind=kind,
            name=name,
            dryRun=dry_run,
            command=["fixture", "create", kind, name, extra],
            noop=False,
        )

    if kind == "vm":
        if not disk:
            return _err_json("vm create needs --disk (existing qcow2 path)")
        if not Path(disk).is_file():
            return _err_json(f"disk not found: {disk}")
        tool, uri, _ = _virsh_connect()
        if not tool:
            return _err_json("virsh not available")
        code, st, _ = _run(_virsh_cmd(tool, uri, "domstate", name), timeout=5.0)
        if code == 0 and st:
            return _err_json(f"domain already exists: {name}")
        xml = _minimal_vm_xml(name, str(Path(disk).resolve()))
        if dry_run:
            return _ok_json(
                action="create",
                kind=kind,
                name=name,
                dryRun=True,
                command=_virsh_cmd(tool, uri, "define", "<xml>"),
                disk=disk,
                noop=False,
            )
        with tempfile.NamedTemporaryFile("w", suffix=".xml", delete=False) as tf:
            tf.write(xml)
            xml_path = tf.name
        try:
            cmd = _virsh_cmd(tool, uri, "define", xml_path)
            code, out, err = _run(cmd, timeout=30.0)
        finally:
            try:
                os.unlink(xml_path)
            except OSError:
                pass
        if code != 0:
            return _err_json(
                (err or out or "virsh define failed")[:240],
                action="create",
                kind=kind,
                name=name,
            )
        return _ok_json(
            action="create",
            kind=kind,
            name=name,
            dryRun=False,
            noop=False,
            command=["virsh", "define", name],
            disk=disk,
        )

    # container
    if not image:
        return _err_json("container create needs --image")
    if any(c in image for c in (";", "|", "&", "`", "\n", " ")):
        return _err_json("invalid image ref")
    engine, tool = _container_engine()
    if not tool:
        return _err_json("podman/docker not available")
    cmd = [tool, "run", "-d", "--name", name, image]
    if dry_run:
        return _ok_json(
            action="create",
            kind=kind,
            name=name,
            dryRun=True,
            command=cmd,
            engine=engine,
            image=image,
            noop=False,
        )
    code, out, err = _run(cmd, timeout=120.0)
    if code != 0:
        return _err_json(
            (err or out or f"{engine} run failed")[:240],
            action="create",
            kind=kind,
            name=name,
            engine=engine,
        )
    return _ok_json(
        action="create",
        kind=kind,
        name=name,
        dryRun=False,
        noop=False,
        command=cmd,
        engine=engine,
        image=image,
    )


def _mutate_destroy(kind: str, name: str, dry_run: bool) -> int:
    kind = kind.strip().lower()
    name = name.strip()
    if kind not in ("vm", "container"):
        return _err_json("kind must be vm|container")
    if not _valid_name(name):
        return _err_json("invalid name")

    if os.environ.get("PROTEUS_WORKLOADS_FIXTURE") == "1":
        return _ok_json(
            fixture=True,
            action="destroy",
            kind=kind,
            name=name,
            dryRun=dry_run,
            command=["fixture", "destroy", kind, name],
            noop=False,
        )

    if kind == "vm":
        tool, uri, _ = _virsh_connect()
        if not tool:
            return _err_json("virsh not available")
        code, st, err = _run(_virsh_cmd(tool, uri, "domstate", name), timeout=5.0)
        state = st.split("\n")[0].strip() if code == 0 and st else ""
        if code != 0:
            return _err_json(
                (err or f"unknown domain: {name}")[:240], action="destroy", kind=kind, name=name
            )
        if _vm_running(state):
            return _err_json(
                "Stop or Force stop first — Remove while running is Out",
                action="destroy",
                kind=kind,
                name=name,
            )
        # Remove definition only — force power-off is kill (virsh destroy).
        cmd = _virsh_cmd(tool, uri, "undefine", name)
        if dry_run:
            return _ok_json(
                action="destroy", kind=kind, name=name, dryRun=True, command=cmd, noop=False
            )
        code, out, err = _run(cmd, timeout=30.0)
        if code != 0:
            return _err_json(
                (err or out or "virsh undefine failed")[:240],
                action="destroy",
                kind=kind,
                name=name,
            )
        return _ok_json(
            action="destroy", kind=kind, name=name, dryRun=False, noop=False, command=cmd
        )

    engine, tool = _container_engine()
    if not tool:
        return _err_json("podman/docker not available")
    code, stdout, err = _run(
        [tool, "ps", "-a", "--format", "{{.Names}}\t{{.Status}}", "--filter", f"name=^{name}$"],
        timeout=8.0,
    )
    status = ""
    found = False
    if code == 0 and stdout:
        for line in stdout.splitlines():
            bits = line.split("\t")
            if bits and bits[0] == name:
                found = True
                status = bits[1] if len(bits) > 1 else ""
                break
    if not found:
        return _err_json(f"unknown container: {name}", action="destroy", kind=kind, name=name)
    if _ctr_running(status):
        return _err_json(
            "Stop or Force stop first — Remove while running is Out",
            action="destroy",
            kind=kind,
            name=name,
            engine=engine,
        )
    # Graceful rm only — never rm -f.
    cmd = [tool, "rm", name]
    if dry_run:
        return _ok_json(
            action="destroy",
            kind=kind,
            name=name,
            dryRun=True,
            command=cmd,
            engine=engine,
            noop=False,
        )
    code, out, err = _run(cmd, timeout=60.0)
    if code != 0:
        return _err_json(
            (err or out or f"{engine} rm failed")[:240],
            action="destroy",
            kind=kind,
            name=name,
            engine=engine,
        )
    return _ok_json(
        action="destroy",
        kind=kind,
        name=name,
        dryRun=False,
        noop=False,
        command=cmd,
        engine=engine,
    )


def main() -> int:
    ap = argparse.ArgumentParser(description="Proteus workloads inventory / mutate")
    ap.add_argument(
        "action",
        nargs="?",
        default="list",
        choices=["list", "start", "stop", "kill", "create", "destroy"],
        help="list (default) | start | stop | kill | create | destroy",
    )
    ap.add_argument("--kind", default="", help="vm | container")
    ap.add_argument("--name", default="", help="domain or container name")
    ap.add_argument("--disk", default="", help="existing qcow2 path (vm create)")
    ap.add_argument("--image", default="", help="container image ref (container create)")
    ap.add_argument("--dry-run", action="store_true", help="print command only")
    args = ap.parse_args()

    if args.action == "list":
        return _emit_inventory()
    if args.action in ("start", "stop", "kill"):
        return _mutate_power(args.action, args.kind, args.name, args.dry_run)
    if args.action == "create":
        return _mutate_create(args.kind, args.name, args.disk, args.image, args.dry_run)
    if args.action == "destroy":
        return _mutate_destroy(args.kind, args.name, args.dry_run)
    return _err_json("unknown action")


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except BrokenPipeError:
        sys.exit(0)
