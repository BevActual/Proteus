#!/usr/bin/env python3
"""Host dashboard metrics for Proteus Host posture (HexOS-style glance).

Probes, honestly and read-only:
  storage — lsblk drives · findmnt --real mounts + statvfs usage ·
            SMART via smartctl -jH (direct, then sudo -n; null when not runnable) ·
            ZFS pools via zpool list/status when present · btrfs mounts flagged
  network — per-interface rx/tx byte rates from two /proc/net/dev samples;
            primary interface from `ip route show default`
  shares  — Samba usershares glance via `net usershare info` (read-only;
            CRUD lives in the Workloads app) + smb service state
  health  — aggregated alerts: mount >90%/>95% full · SMART failing ·
            pool not ONLINE · systemd --failed units

Stdout: one JSON object. Fixture: PROTEUS_HOST_METRICS_FIXTURE=1.
Mutations are Out here — this is glance data for HostHome cards only.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import time
from typing import Any

PSEUDO_FS = {
    "proc", "sysfs", "devtmpfs", "devpts", "tmpfs", "cgroup", "cgroup2",
    "pstore", "securityfs", "debugfs", "tracefs", "configfs", "fusectl",
    "mqueue", "hugetlbfs", "bpf", "autofs", "binfmt_misc", "efivarfs",
    "ramfs", "squashfs", "overlay", "nsfs", "fuse.portal", "fuse.gvfsd-fuse",
}


def _run(cmd: list[str], timeout: float = 10.0) -> tuple[int, str, str]:
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
        "storage": {
            "drives": [
                {"name": "sda", "size": "1.8T", "model": "WD Red Plus", "rota": True,
                 "tran": "sata", "smart": "passed"},
                {"name": "nvme0n1", "size": "465.8G", "model": "Samsung 980", "rota": False,
                 "tran": "nvme", "smart": "passed"},
            ],
            "mounts": [
                {"target": "/", "source": "/dev/nvme0n1p2", "fstype": "ext4",
                 "usedGiB": 42.0, "totalGiB": 456.0, "usedPct": 9},
                {"target": "/tank/media", "source": "tank/media", "fstype": "zfs",
                 "usedGiB": 1210.0, "totalGiB": 1800.0, "usedPct": 67},
            ],
            "pools": [
                {"name": "tank", "size": "1.81T", "alloc": "1.18T", "free": "645G",
                 "health": "ONLINE", "kind": "zfs"},
            ],
            "smartAvailable": True,
        },
        "network": {
            "primary": "enp1s0",
            "interfaces": [
                {"name": "enp1s0", "up": True, "rxBps": 1250000, "txBps": 84000},
            ],
        },
        "shares": {
            "available": True,
            "smbActive": True,
            "items": [
                {"name": "media", "path": "/tank/media", "guestOk": True},
            ],
        },
        "health": {
            "alerts": [
                {"severity": "warn", "message": "/tank/media is 67% full"},
            ],
            "failedUnits": 0,
        },
        "summary": "2 drives · 1 pool ONLINE · enp1s0 up · 1 share",
        "hint": "Fixture metrics — live data comes from lsblk/findmnt/zpool/smartctl",
        "errors": [],
    }


# ---------------------------------------------------------------- storage

def _drives(errors: list[str]) -> tuple[list[dict[str, Any]], bool]:
    tool = _which("lsblk")
    if not tool:
        errors.append("lsblk not found")
        return [], False
    code, out, err = _run(
        [tool, "-J", "-d", "-o", "NAME,SIZE,TYPE,MODEL,ROTA,TRAN"], timeout=8.0
    )
    if code != 0:
        if err:
            errors.append(err.split("\n")[0][:160])
        return [], False
    try:
        data = json.loads(out or "{}")
    except ValueError:
        errors.append("lsblk JSON parse failed")
        return [], False

    smartctl = _which("smartctl")
    smart_available = False
    drives: list[dict[str, Any]] = []
    for dev in data.get("blockdevices") or []:
        if str(dev.get("type") or "") != "disk":
            continue
        name = str(dev.get("name") or "")
        if not name or name.startswith(("loop", "zram", "ram", "sr")):
            continue
        smart = None
        if smartctl:
            smart = _smart_health(smartctl, f"/dev/{name}")
            if smart is not None:
                smart_available = True
        drives.append({
            "name": name,
            "size": str(dev.get("size") or ""),
            "model": str(dev.get("model") or "").strip(),
            "rota": bool(dev.get("rota")),
            "tran": str(dev.get("tran") or ""),
            "smart": smart,
        })
    return drives, smart_available


def _smart_health(smartctl: str, dev: str) -> str | None:
    """passed | failed | None (not runnable / unsupported). Never guesses."""
    for cmd in ([smartctl, "-jH", dev], ["sudo", "-n", smartctl, "-jH", dev]):
        if cmd[0] == "sudo" and not _which("sudo"):
            continue
        code, out, _err = _run(cmd, timeout=10.0)
        if not out:
            continue
        try:
            data = json.loads(out)
        except ValueError:
            continue
        status = data.get("smart_status")
        if isinstance(status, dict) and "passed" in status:
            return "passed" if status.get("passed") else "failed"
        # JSON came back but no status (permissions / unsupported transport)
        msgs = data.get("smartctl", {}).get("messages") or []
        if any("permission" in str(m.get("string", "")).lower() for m in msgs):
            continue
    return None


def _mounts(errors: list[str]) -> list[dict[str, Any]]:
    tool = _which("findmnt")
    if not tool:
        errors.append("findmnt not found")
        return []
    code, out, err = _run(
        [tool, "--real", "-J", "-o", "TARGET,SOURCE,FSTYPE"], timeout=8.0
    )
    if code != 0:
        if err:
            errors.append(err.split("\n")[0][:160])
        return []
    try:
        data = json.loads(out or "{}")
    except ValueError:
        errors.append("findmnt JSON parse failed")
        return []

    flat: list[dict[str, str]] = []

    def walk(nodes: list[dict[str, Any]]) -> None:
        for n in nodes:
            flat.append({
                "target": str(n.get("target") or ""),
                "source": str(n.get("source") or ""),
                "fstype": str(n.get("fstype") or ""),
            })
            walk(n.get("children") or [])

    walk(data.get("filesystems") or [])

    seen_sources: set[str] = set()
    mounts: list[dict[str, Any]] = []
    for m in flat:
        if not m["target"] or m["fstype"] in PSEUDO_FS:
            continue
        # Dedupe bind mounts / btrfs subvolumes: first target per source wins.
        src_key = m["source"].split("[", 1)[0]
        if src_key in seen_sources:
            continue
        seen_sources.add(src_key)
        try:
            st = os.statvfs(m["target"])
        except OSError:
            continue
        total = st.f_blocks * st.f_frsize
        if total <= 0:
            continue
        free = st.f_bavail * st.f_frsize
        used = total - free
        mounts.append({
            "target": m["target"],
            "source": src_key,
            "fstype": m["fstype"],
            "usedGiB": round(used / (1024 ** 3), 1),
            "totalGiB": round(total / (1024 ** 3), 1),
            "usedPct": int(round(used * 100.0 / total)),
        })
    mounts.sort(key=lambda m: m["target"])
    return mounts


def _pools(errors: list[str]) -> list[dict[str, Any]]:
    pools: list[dict[str, Any]] = []
    zpool = _which("zpool")
    if zpool:
        code, out, err = _run(
            [zpool, "list", "-H", "-o", "name,size,alloc,free,health"], timeout=8.0
        )
        if code == 0 and out:
            for line in out.splitlines():
                bits = line.split("\t")
                if len(bits) >= 5:
                    pools.append({
                        "name": bits[0], "size": bits[1], "alloc": bits[2],
                        "free": bits[3], "health": bits[4], "kind": "zfs",
                    })
        elif err and "no pools" not in err.lower():
            errors.append(err.split("\n")[0][:160])
    return pools


# ---------------------------------------------------------------- network

def _read_net_dev() -> dict[str, tuple[int, int]]:
    stats: dict[str, tuple[int, int]] = {}
    try:
        with open("/proc/net/dev", encoding="utf-8") as f:
            for line in f.readlines()[2:]:
                if ":" not in line:
                    continue
                name, rest = line.split(":", 1)
                name = name.strip()
                fields = rest.split()
                if len(fields) >= 9:
                    stats[name] = (int(fields[0]), int(fields[8]))
    except OSError:
        pass
    return stats


def _iface_up(name: str) -> bool:
    try:
        with open(f"/sys/class/net/{name}/operstate", encoding="utf-8") as f:
            return f.read().strip() == "up"
    except OSError:
        return False


def _primary_iface() -> str:
    ip = _which("ip")
    if not ip:
        return ""
    code, out, _err = _run([ip, "route", "show", "default"], timeout=5.0)
    if code != 0 or not out:
        return ""
    for tok_line in out.splitlines():
        toks = tok_line.split()
        if "dev" in toks:
            i = toks.index("dev")
            if i + 1 < len(toks):
                return toks[i + 1]
    return ""


def _network(sample_secs: float) -> dict[str, Any]:
    a = _read_net_dev()
    time.sleep(sample_secs)
    b = _read_net_dev()
    interfaces: list[dict[str, Any]] = []
    for name, (rx1, tx1) in b.items():
        if name == "lo" or name.startswith(("veth", "docker", "podman", "br-", "virbr", "tap")):
            continue
        rx0, tx0 = a.get(name, (rx1, tx1))
        interfaces.append({
            "name": name,
            "up": _iface_up(name),
            "rxBps": max(0, int((rx1 - rx0) / sample_secs)),
            "txBps": max(0, int((tx1 - tx0) / sample_secs)),
        })
    interfaces.sort(key=lambda i: (not i["up"], i["name"]))
    return {"primary": _primary_iface(), "interfaces": interfaces}


# ---------------------------------------------------------------- shares

def _shares() -> dict[str, Any]:
    """Samba usershares glance. Read-only — CRUD is in the Workloads app."""
    net = _which("net")
    if not net:
        return {"available": False, "smbActive": False, "items": []}
    smb_active = False
    systemctl = _which("systemctl")
    if systemctl:
        for unit in ("smb", "smbd"):
            code, out, _err = _run([systemctl, "is-active", unit], timeout=5.0)
            if code == 0 and out.strip() == "active":
                smb_active = True
                break
    code, out, _err = _run([net, "usershare", "info"], timeout=8.0)
    items: list[dict[str, Any]] = []
    if code == 0 and out:
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
    return {"available": True, "smbActive": smb_active, "items": items}


# ---------------------------------------------------------------- health

def _failed_units() -> int:
    tool = _which("systemctl")
    if not tool:
        return 0
    code, out, _err = _run(
        [tool, "--failed", "--plain", "--no-legend", "--no-pager"], timeout=8.0
    )
    if code != 0 and not out:
        return 0
    return len([ln for ln in out.splitlines() if ln.strip()])


def _health(storage: dict[str, Any]) -> dict[str, Any]:
    alerts: list[dict[str, str]] = []
    for m in storage.get("mounts") or []:
        pct = int(m.get("usedPct") or 0)
        if pct >= 95:
            alerts.append({"severity": "crit",
                           "message": f"{m['target']} is {pct}% full"})
        elif pct >= 90:
            alerts.append({"severity": "warn",
                           "message": f"{m['target']} is {pct}% full"})
    for d in storage.get("drives") or []:
        if d.get("smart") == "failed":
            alerts.append({"severity": "crit",
                           "message": f"SMART failing on /dev/{d['name']}"})
    for p in storage.get("pools") or []:
        if str(p.get("health") or "").upper() not in ("ONLINE", ""):
            alerts.append({"severity": "crit",
                           "message": f"pool {p['name']} is {p['health']}"})
    failed = _failed_units()
    if failed > 0:
        alerts.append({"severity": "warn",
                       "message": f"{failed} systemd unit{'s' if failed != 1 else ''} failed"})
    return {"alerts": alerts, "failedUnits": failed}


def _summary(storage: dict[str, Any], network: dict[str, Any],
             shares: dict[str, Any], health: dict[str, Any]) -> str:
    bits: list[str] = []
    n_drives = len(storage.get("drives") or [])
    if n_drives:
        bits.append(f"{n_drives} drive" + ("s" if n_drives != 1 else ""))
    pools = storage.get("pools") or []
    if pools:
        healthy = all(str(p.get("health") or "").upper() == "ONLINE" for p in pools)
        bits.append(f"{len(pools)} pool" + ("s" if len(pools) != 1 else "")
                    + (" ONLINE" if healthy else " DEGRADED"))
    primary = network.get("primary") or ""
    if primary:
        up = any(i["name"] == primary and i["up"] for i in network.get("interfaces") or [])
        bits.append(f"{primary} {'up' if up else 'down'}")
    n_shares = len(shares.get("items") or [])
    if n_shares:
        bits.append(f"{n_shares} share" + ("s" if n_shares != 1 else ""))
    n_alerts = len(health.get("alerts") or [])
    if n_alerts:
        bits.append(f"{n_alerts} alert" + ("s" if n_alerts != 1 else ""))
    return " · ".join(bits) if bits else "No metrics sources found"


def main() -> int:
    if os.environ.get("PROTEUS_HOST_METRICS_FIXTURE") == "1":
        print(json.dumps(_fixture(), separators=(",", ":")))
        return 0

    sample = 0.5
    try:
        sample = max(0.1, float(os.environ.get("PROTEUS_HOST_METRICS_SAMPLE", "0.5")))
    except ValueError:
        pass

    errors: list[str] = []
    drives, smart_available = _drives(errors)
    storage = {
        "drives": drives,
        "mounts": _mounts(errors),
        "pools": _pools(errors),
        "smartAvailable": smart_available,
    }
    network = _network(sample)
    shares = _shares()
    health = _health(storage)

    hint = ""
    if not drives and not storage["mounts"]:
        hint = "No storage data — install util-linux (lsblk/findmnt)"
    elif not smart_available and not _which("smartctl"):
        hint = "smartctl not found — drive health unavailable (install smartmontools)"

    print(json.dumps({
        "ok": True,
        "fixture": False,
        "storage": storage,
        "network": network,
        "shares": shares,
        "health": health,
        "summary": _summary(storage, network, shares, health),
        "hint": hint,
        "errors": errors[:5],
    }, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except BrokenPipeError:
        sys.exit(0)
