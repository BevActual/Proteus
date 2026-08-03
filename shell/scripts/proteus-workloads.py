#!/usr/bin/env python3
"""VM/container inventory + mutate for Proteus Host.

Probes libvirt (virsh) and podman/docker when present.
Mutations: start|stop|kill|create|destroy|deploy|share-add|share-remove
  VM: virsh start/shutdown · destroy (force power-off) · define · undefine (stopped)
  CTR: engine start/stop/kill · run -d · rm (stopped only)
  APP: deploy = curated one-click catalog (env/apps/host-apps.json) → container
       named proteus-app-<id>; volumes under ~/.local/share/proteus/apps/<id>/
  SHARE: Samba usershares (net usershare add/delete) — no root once the
       usershare dir exists and the user is in sambashare
Reads: apps (catalog + deploy status) · shares (usershare list + smb state)
Stdout: one JSON object. Fixture: PROTEUS_WORKLOADS_FIXTURE=1.
Honesty: kill = force power-off (keep definition). Settings virt · headless-no-QS Out.
Remove while running (rm -f) stays Out. Privileged deploys stay Out.
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
_APP_PREFIX = "proteus-app-"


def _proteus_root() -> Path:
    env = os.environ.get("PROTEUS_ROOT", "").strip()
    if env and (Path(env) / "env").is_dir():
        return Path(env)
    return Path(__file__).resolve().parent.parent.parent


def _load_catalog() -> list[dict[str, Any]]:
    path = _proteus_root() / "env" / "apps" / "host-apps.json"
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return []
    apps = data.get("apps")
    return apps if isinstance(apps, list) else []


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


# -------------------------------------------------------- one-click apps

def _apps_fixture() -> dict[str, Any]:
    apps = _load_catalog()
    for a in apps:
        a["containerName"] = _APP_PREFIX + str(a.get("id") or "")
        a["deployed"] = a.get("id") == "jellyfin"
        a["running"] = a.get("id") == "jellyfin"
        a["status"] = "Up 3 hours" if a.get("id") == "jellyfin" else ""
    return {
        "ok": True,
        "fixture": True,
        "engine": "podman",
        "available": True,
        "apps": apps,
    }


def _emit_apps() -> int:
    if os.environ.get("PROTEUS_WORKLOADS_FIXTURE") == "1":
        print(json.dumps(_apps_fixture(), separators=(",", ":")))
        return 0
    apps = _load_catalog()
    containers, _errs = _containers()
    by_name = {str(c.get("name") or ""): c for c in containers.get("items") or []}
    for a in apps:
        cname = _APP_PREFIX + str(a.get("id") or "")
        a["containerName"] = cname
        ctr = by_name.get(cname)
        a["deployed"] = ctr is not None
        a["running"] = _ctr_running(str(ctr.get("status") or "")) if ctr else False
        a["status"] = str(ctr.get("status") or "") if ctr else ""
    print(json.dumps({
        "ok": True,
        "fixture": False,
        "engine": containers.get("engine") or "",
        "available": bool(containers.get("available")),
        "apps": apps,
    }, separators=(",", ":")))
    return 0


def _mutate_deploy(app_id: str, dry_run: bool) -> int:
    app_id = app_id.strip().lower()
    if not _valid_name(app_id):
        return _err_json("invalid app id")
    catalog = {str(a.get("id") or ""): a for a in _load_catalog()}
    app = catalog.get(app_id)
    if not app:
        return _err_json(f"unknown app: {app_id} (see env/apps/host-apps.json)")
    name = _APP_PREFIX + app_id
    image = str(app.get("image") or "")
    if not image or any(c in image for c in (";", "|", "&", "`", "\n", " ")):
        return _err_json("catalog image ref invalid")

    if os.environ.get("PROTEUS_WORKLOADS_FIXTURE") == "1":
        return _ok_json(
            fixture=True, action="deploy", app=app_id, name=name, dryRun=dry_run,
            command=["fixture", "deploy", app_id], noop=False,
        )

    engine, tool = _container_engine()
    if not tool:
        return _err_json("podman/docker not available")
    code, stdout, _err = _run(
        [tool, "ps", "-a", "--format", "{{.Names}}", "--filter", f"name=^{name}$"],
        timeout=8.0,
    )
    if code == 0 and any(ln.strip() == name for ln in stdout.splitlines()):
        return _err_json(
            f"already deployed: {name} — use Start/Stop/Remove instead",
            action="deploy", app=app_id, name=name,
        )

    data_root = Path.home() / ".local" / "share" / "proteus" / "apps" / app_id
    # Never a privileged deploy; graceful lifecycle only (rm -f stays Out).
    cmd = [tool, "run", "-d", "--name", name, "--restart", "unless-stopped"]
    for spec in app.get("ports") or []:
        spec = str(spec)
        if not re.match(r"^\d{1,5}:\d{1,5}$", spec):
            return _err_json(f"catalog port spec invalid: {spec}")
        cmd += ["-p", spec]
    volumes = []
    for vol in app.get("volumes") or []:
        vname = str(vol.get("name") or "")
        vpath = str(vol.get("path") or "")
        if not _valid_name(vname) or not vpath.startswith("/"):
            return _err_json(f"catalog volume invalid: {vname}:{vpath}")
        host_dir = data_root / vname
        volumes.append((host_dir, vpath))
        cmd += ["-v", f"{host_dir}:{vpath}"]
    for k, v in (app.get("env") or {}).items():
        k = str(k)
        v = str(v)
        if not re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", k):
            return _err_json(f"catalog env key invalid: {k}")
        cmd += ["-e", f"{k}={v}"]
    cmd.append(image)

    if dry_run:
        return _ok_json(
            action="deploy", app=app_id, name=name, dryRun=True,
            command=cmd, engine=engine, noop=False,
        )
    for host_dir, _cpath in volumes:
        try:
            host_dir.mkdir(parents=True, exist_ok=True)
        except OSError as e:
            return _err_json(f"could not create {host_dir}: {e}")
    code, out, err = _run(cmd, timeout=600.0)
    if code != 0:
        return _err_json(
            (err or out or f"{engine} run failed")[:240],
            action="deploy", app=app_id, name=name, engine=engine,
        )
    return _ok_json(
        action="deploy", app=app_id, name=name, dryRun=False, noop=False,
        command=cmd, engine=engine,
    )


# -------------------------------------------------------- samba shares

def _shares_fixture() -> dict[str, Any]:
    return {
        "ok": True,
        "fixture": True,
        "available": True,
        "smbActive": True,
        "items": [
            {"name": "media", "path": "/tank/media", "guestOk": True},
        ],
    }


def _smb_active() -> bool:
    systemctl = _which("systemctl")
    if not systemctl:
        return False
    for unit in ("smb", "smbd"):
        code, out, _err = _run([systemctl, "is-active", unit], timeout=5.0)
        if code == 0 and out.strip() == "active":
            return True
    return False


def _emit_shares() -> int:
    if os.environ.get("PROTEUS_WORKLOADS_FIXTURE") == "1":
        print(json.dumps(_shares_fixture(), separators=(",", ":")))
        return 0
    net = _which("net")
    if not net:
        print(json.dumps({
            "ok": True, "fixture": False, "available": False,
            "smbActive": False, "items": [],
            "hint": "samba not installed — install samba for shared folders",
        }, separators=(",", ":")))
        return 0
    code, out, err = _run([net, "usershare", "info"], timeout=8.0)
    items: list[dict[str, Any]] = []
    errors: list[str] = []
    if code != 0 and err:
        errors.append(err.split("\n")[0][:160])
    elif out:
        cur: dict[str, Any] = {}
        for line in out.splitlines():
            line = line.strip()
            if line.startswith("[") and line.endswith("]"):
                if cur.get("name"):
                    items.append(cur)
                cur = {"name": line[1:-1], "path": "", "guestOk": False}
            elif line.startswith("path=") and cur:
                cur["path"] = line[len("path="):]
            elif line.startswith("guest_ok=") and cur:
                cur["guestOk"] = line[len("guest_ok="):].strip().lower() == "y"
        if cur.get("name"):
            items.append(cur)
    print(json.dumps({
        "ok": True, "fixture": False, "available": True,
        "smbActive": _smb_active(), "items": items,
        "errors": errors[:3],
    }, separators=(",", ":")))
    return 0


def _share_add(name: str, path: str, dry_run: bool) -> int:
    name = name.strip()
    path = path.strip()
    if not _valid_name(name):
        return _err_json("invalid share name")
    if not path.startswith("/"):
        return _err_json("share path must be absolute")

    if os.environ.get("PROTEUS_WORKLOADS_FIXTURE") == "1":
        return _ok_json(
            fixture=True, action="share-add", name=name, path=path,
            dryRun=dry_run, command=["fixture", "share-add", name, path], noop=False,
        )

    if not Path(path).is_dir():
        return _err_json(f"not a directory: {path}")
    net = _which("net")
    if not net:
        return _err_json("samba (net) not available — install samba")
    # Guest-readable usershare; ACL edits beyond this are Out (use Samba tools).
    cmd = [net, "usershare", "add", name, path, "", "Everyone:F", "guest_ok=y"]
    if dry_run:
        return _ok_json(action="share-add", name=name, path=path,
                        dryRun=True, command=cmd, noop=False)
    code, out, err = _run(cmd, timeout=15.0)
    if code != 0:
        return _err_json((err or out or "net usershare add failed")[:240],
                         action="share-add", name=name, path=path)
    return _ok_json(action="share-add", name=name, path=path,
                    dryRun=False, noop=False, command=cmd)


def _share_remove(name: str, dry_run: bool) -> int:
    name = name.strip()
    if not _valid_name(name):
        return _err_json("invalid share name")

    if os.environ.get("PROTEUS_WORKLOADS_FIXTURE") == "1":
        return _ok_json(
            fixture=True, action="share-remove", name=name, dryRun=dry_run,
            command=["fixture", "share-remove", name], noop=False,
        )

    net = _which("net")
    if not net:
        return _err_json("samba (net) not available")
    cmd = [net, "usershare", "delete", name]
    if dry_run:
        return _ok_json(action="share-remove", name=name, dryRun=True,
                        command=cmd, noop=False)
    code, out, err = _run(cmd, timeout=15.0)
    if code != 0:
        return _err_json((err or out or "net usershare delete failed")[:240],
                         action="share-remove", name=name)
    return _ok_json(action="share-remove", name=name, dryRun=False,
                    noop=False, command=cmd)


def main() -> int:
    ap = argparse.ArgumentParser(description="Proteus workloads inventory / mutate")
    ap.add_argument(
        "action",
        nargs="?",
        default="list",
        choices=["list", "start", "stop", "kill", "create", "destroy",
                 "apps", "deploy", "shares", "share-add", "share-remove"],
        help="list (default) | start | stop | kill | create | destroy | "
             "apps | deploy | shares | share-add | share-remove",
    )
    ap.add_argument("--kind", default="", help="vm | container")
    ap.add_argument("--name", default="", help="domain or container name / share name")
    ap.add_argument("--disk", default="", help="existing qcow2 path (vm create)")
    ap.add_argument("--image", default="", help="container image ref (container create)")
    ap.add_argument("--app", default="", help="catalog app id (deploy)")
    ap.add_argument("--path", default="", help="folder path (share-add)")
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
    if args.action == "apps":
        return _emit_apps()
    if args.action == "deploy":
        return _mutate_deploy(args.app, args.dry_run)
    if args.action == "shares":
        return _emit_shares()
    if args.action == "share-add":
        return _share_add(args.name, args.path, args.dry_run)
    if args.action == "share-remove":
        return _share_remove(args.name, args.dry_run)
    return _err_json("unknown action")


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except BrokenPipeError:
        sys.exit(0)
