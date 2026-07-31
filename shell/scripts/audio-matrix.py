#!/usr/bin/env python3
"""PipeWire audio matrix helper for Proteus Settings → Sound → Audio matrix.

Omnibus-style node grid: group ports by node, report cells, link/unlink
matching channels via pw-link. stdout = one JSON object.

Usage:
  audio-matrix.py dump [--midi] [--monitors]
  audio-matrix.py link <out-node> <in-node>
  audio-matrix.py unlink <out-node> <in-node>
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from collections import defaultdict

SKIP_NODE_PREFIXES = (
    "Midi-Bridge:",
    "bluez_midi.",
    "Midi-Bridge",
)


def run(args: list[str]) -> str:
    try:
        r = subprocess.run(args, capture_output=True, text=True, check=False)
    except FileNotFoundError:
        return ""
    if r.returncode != 0:
        return ""
    return r.stdout or ""


def node_of(port: str) -> str:
    if ":" not in port:
        return port
    return port.rsplit(":", 1)[0]


def channel_of(port: str) -> str:
    name = port.rsplit(":", 1)[-1]
    for prefix in (
        "playback_",
        "capture_",
        "output_",
        "input_",
        "monitor_",
    ):
        if name.startswith(prefix):
            return name[len(prefix) :]
    return name


def is_monitor_port(port: str) -> bool:
    leaf = port.rsplit(":", 1)[-1]
    return leaf.startswith("monitor_")


MIX_LABELS = {
    "proteus_mix_system": "System",
    "proteus_mix_voice": "Voice",
    "proteus_mix_music": "Music",
    "proteus_mix_browser": "Browser",
    "proteus_mix_game": "Game",
}


def is_midi_node(node: str) -> bool:
    n = node.lower()
    if n.startswith("midi-bridge") or "bluez_midi" in n:
        return True
    if ":midi" in n or n.endswith(" midi"):
        return True
    return False


def is_noise_node(node: str) -> bool:
    """Hide loopbacks, Pulse helpers, and other graph clutter from the UI grid."""
    n = node.lower()
    if n.startswith("loopback") or "loopback-" in n or ".loopback" in n:
        return True
    if n.startswith("proteus_loop"):
        return True
    if "pulseaudio volume control" in n or n.startswith("pavucontrol"):
        return True
    if n.startswith("speech-dispatcher") or n.startswith("midi-bridge"):
        return True
    return False


def short_label(node: str) -> str:
    if node in MIX_LABELS:
        return MIX_LABELS[node]
    n = node
    for p in (
        "alsa_output.",
        "alsa_input.",
        "bluez_output.",
        "bluez_input.",
    ):
        if n.startswith(p):
            n = n[len(p) :]
            break
    # Drop usb-VID_PID-00. style prefix when a richer profile follows.
    n = re.sub(r"^usb-[^.]+\.", "", n)
    n = re.sub(r"^pci-[^.]+\.", "", n)
    n = re.sub(r"^hw_", "hw ", n)
    # HiFi__Headphones__sink → Headphones
    m = re.search(r"HiFi__([A-Za-z0-9]+)__", n)
    if m:
        return m.group(1).replace("_", " ")
    parts = [p for p in n.split(".") if p]
    if not parts:
        parts = [node]
    # Avoid lone numeric tails (hw_EVO4_0 → "0")
    if len(parts) >= 2 and re.fullmatch(r"\d+", parts[-1] or ""):
        tail = parts[-2] + " " + parts[-1]
    else:
        tail = parts[-1]
    if ":" in tail:
        tail = tail.split(":")[0]
    for suffix in (" sink", " source", " monitor"):
        if tail.lower().endswith(suffix.strip()):
            # handled below via replace
            pass
    tail = re.sub(r"__+", " ", tail)
    tail = tail.replace("-", " ").replace("_", " ")
    tail = re.sub(r"\b(sink|source|monitor)\b", "", tail, flags=re.I)
    tail = re.sub(r"\s+", " ", tail).strip()
    if not tail:
        return node[-32:] if len(node) > 32 else node
    return tail[:28]


def list_ports(flag: str) -> list[str]:
    text = run(["pw-link", flag])
    out: list[str] = []
    for line in text.splitlines():
        s = line.strip()
        if not s or s.startswith("="):
            continue
        out.append(s)
    return out


def list_links() -> list[dict]:
    """Parse `pw-link -lI` into directed out→in edges with link ids."""
    text = run(["pw-link", "-lI"])
    links: list[dict] = []
    # Lines look like:
    #   102 alsa_output...:playback_FL
    #  158   |<-  162 qemu:output_FL
    #  158   |->  102 ...  (alternate orientation depending on list root)
    port_by_id: dict[int, str] = {}
    pending_port: str | None = None
    pending_id: int | None = None

    port_re = re.compile(r"^\s*(\d+)\s+(\S+)\s*$")
    edge_re = re.compile(r"^\s*(\d+)\s+\|([<>])-\s+(\d+)\s+(\S+)\s*$")

    for line in text.splitlines():
        m = edge_re.match(line)
        if m:
            link_id = int(m.group(1))
            direction = m.group(2)  # < means peer is source into pending; > means peer is sink
            peer_port_id = int(m.group(3))
            peer_port = m.group(4)
            port_by_id[peer_port_id] = peer_port
            if pending_port is None:
                continue
            if direction == "<":
                # pending is input, peer is output
                links.append(
                    {
                        "id": link_id,
                        "out": peer_port,
                        "in": pending_port,
                        "outId": peer_port_id,
                        "inId": pending_id,
                    }
                )
            else:
                # pending is output, peer is input
                links.append(
                    {
                        "id": link_id,
                        "out": pending_port,
                        "in": peer_port,
                        "outId": pending_id,
                        "inId": peer_port_id,
                    }
                )
            continue
        m = port_re.match(line)
        if m:
            pending_id = int(m.group(1))
            pending_port = m.group(2)
            port_by_id[pending_id] = pending_port
    # Deduplicate by link id
    by_id: dict[int, dict] = {}
    for L in links:
        by_id[int(L["id"])] = L
    return list(by_id.values())


def group_nodes(
    ports: list[str], *, want_midi: bool, want_monitors: bool, role: str
) -> list[dict]:
    buckets: dict[str, list[str]] = defaultdict(list)
    for p in ports:
        if not want_monitors and is_monitor_port(p):
            continue
        n = node_of(p)
        if not want_midi and is_midi_node(n):
            continue
        if is_noise_node(n):
            continue
        buckets[n].append(p)
    nodes = []
    for n in sorted(buckets.keys(), key=lambda s: short_label(s).lower()):
        nodes.append(
            {
                "id": n,
                "label": short_label(n),
                "role": role,
                "ports": sorted(buckets[n]),
            }
        )
    return nodes


def cell_key(out_id: str, in_id: str) -> str:
    return out_id + "\x1f" + in_id


def build_cells(outputs: list[dict], inputs: list[dict], links: list[dict]) -> dict:
    out_ports = {n["id"]: set(n["ports"]) for n in outputs}
    in_ports = {n["id"]: set(n["ports"]) for n in inputs}
    cells: dict[str, dict] = {}
    for L in links:
        on = node_of(L["out"])
        inn = node_of(L["in"])
        if on not in out_ports or inn not in in_ports:
            continue
        if L["out"] not in out_ports[on] or L["in"] not in in_ports[inn]:
            continue
        k = cell_key(on, inn)
        slot = cells.setdefault(k, {"linked": False, "partial": False, "linkIds": [], "count": 0})
        slot["linkIds"].append(L["id"])
        slot["count"] += 1
    for on, ops in out_ports.items():
        for inn, ips in in_ports.items():
            k = cell_key(on, inn)
            # Potential channel pairs
            och = {channel_of(p) for p in ops}
            ich = {channel_of(p) for p in ips}
            possible = len(och & ich)
            if possible == 0:
                # still allow mono↔first later at link time; mark possible=1 if both nonempty
                possible = 1 if ops and ips else 0
            slot = cells.get(k)
            if not slot:
                cells[k] = {
                    "linked": False,
                    "partial": False,
                    "linkIds": [],
                    "count": 0,
                    "possible": possible,
                }
                continue
            slot["possible"] = possible
            if slot["count"] > 0 and possible > 0 and slot["count"] < possible:
                slot["partial"] = True
                slot["linked"] = True
            elif slot["count"] > 0:
                slot["linked"] = True
                slot["partial"] = False
    # JSON-friendly keys (node ids may contain ':' but not '|')
    out: dict[str, dict] = {}
    for k, v in cells.items():
        a, _, b = k.partition("\x1f")
        out[f"{a}|{b}"] = v
    return out


def dump(want_midi: bool, want_monitors: bool) -> dict:
    if not shutil.which("pw-link"):
        return {"ok": False, "error": "pw-link not found", "outputs": [], "inputs": [], "links": [], "cells": {}}
    outs = list_ports("-o")
    inns = list_ports("-i")
    links = list_links()
    outputs = group_nodes(outs, want_midi=want_midi, want_monitors=want_monitors, role="out")
    inputs = group_nodes(inns, want_midi=want_midi, want_monitors=want_monitors, role="in")
    cells = build_cells(outputs, inputs, links)
    return {
        "ok": True,
        "error": "",
        "outputs": outputs,
        "inputs": inputs,
        "links": links,
        "cells": cells,
    }


def port_map(ports: list[str]) -> dict[str, str]:
    return {channel_of(p): p for p in ports}


def link_nodes(out_node: str, in_node: str) -> dict:
    outs = [p for p in list_ports("-o") if node_of(p) == out_node]
    inns = [p for p in list_ports("-i") if node_of(p) == in_node]
    if not outs or not inns:
        return {"ok": False, "error": "missing ports", "linked": 0}
    om = port_map(outs)
    im = port_map(inns)
    pairs: list[tuple[str, str]] = []
    for ch, op in om.items():
        if ch in im:
            pairs.append((op, im[ch]))
    if not pairs:
        # Fallback: zip in sorted order
        for op, ip in zip(sorted(outs), sorted(inns)):
            pairs.append((op, ip))
    linked = 0
    errors: list[str] = []
    for op, ip in pairs:
        r = subprocess.run(["pw-link", "-L", op, ip], capture_output=True, text=True)
        if r.returncode == 0:
            linked += 1
        else:
            err = (r.stderr or r.stdout or "").strip()
            if err and "exists" not in err.lower() and "in use" not in err.lower():
                errors.append(err.split("\n")[0])
            else:
                linked += 1  # already linked counts as success
    return {"ok": linked > 0, "error": errors[0] if errors and linked == 0 else "", "linked": linked}


def unlink_nodes(out_node: str, in_node: str) -> dict:
    links = list_links()
    ids = [L["id"] for L in links if node_of(L["out"]) == out_node and node_of(L["in"]) == in_node]
    # Also disconnect by port pair if id fails
    pairs = [(L["out"], L["in"]) for L in links if node_of(L["out"]) == out_node and node_of(L["in"]) == in_node]
    removed = 0
    for lid in ids:
        r = subprocess.run(["pw-link", "-d", str(lid)], capture_output=True, text=True)
        if r.returncode == 0:
            removed += 1
    if removed == 0:
        for op, ip in pairs:
            r = subprocess.run(["pw-link", "-d", op, ip], capture_output=True, text=True)
            if r.returncode == 0:
                removed += 1
    return {"ok": True, "error": "", "removed": removed}


def main() -> int:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)

    d = sub.add_parser("dump")
    d.add_argument("--midi", action="store_true")
    d.add_argument("--monitors", action="store_true")

    lk = sub.add_parser("link")
    lk.add_argument("out_node")
    lk.add_argument("in_node")

    ul = sub.add_parser("unlink")
    ul.add_argument("out_node")
    ul.add_argument("in_node")

    args = ap.parse_args()
    if args.cmd == "dump":
        print(json.dumps(dump(args.midi, args.monitors)))
        return 0
    if args.cmd == "link":
        print(json.dumps(link_nodes(args.out_node, args.in_node)))
        return 0
    if args.cmd == "unlink":
        print(json.dumps(unlink_nodes(args.out_node, args.in_node)))
        return 0
    return 2


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as e:
        print(json.dumps({"ok": False, "error": str(e)}))
        raise SystemExit(0)
