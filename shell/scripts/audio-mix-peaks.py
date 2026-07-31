#!/usr/bin/env python3
"""Round-robin peak levels for mixer channel/input sinks.

Emits one JSON object per cycle: {"proteus_mix_apps": 12, "proteus_in_mic": 40, …}
Devices are sink names; we meter sink.monitor (or the name if it is already a
source). Keeps cost bounded vs one parec per row.

Usage:
  audio-mix-peaks.py [--window-ms N] [--rate HZ] sink [sink…]
"""
from __future__ import annotations

import argparse
import array
import json
import shutil
import subprocess
import sys
import time

RESTART_DELAY = 0.4
MAX_S16 = 32767


def emit(obj: dict) -> bool:
    try:
        sys.stdout.write(json.dumps(obj, separators=(",", ":")) + "\n")
        sys.stdout.flush()
    except (BrokenPipeError, ValueError):
        return False
    return True


def peak_of(chunk: bytes) -> int:
    if len(chunk) < 2:
        return 0
    samples = array.array("h")
    samples.frombytes(chunk[: len(chunk) - (len(chunk) % 2)])
    if sys.byteorder != "little":
        samples.byteswap()
    hi = max(samples, default=0)
    lo = min(samples, default=0)
    loudest = max(hi, -lo if lo > -MAX_S16 - 1 else MAX_S16)
    return min(100, (loudest * 100) // MAX_S16)


def source_for(sink: str) -> str:
    s = (sink or "").strip()
    if not s:
        return ""
    if s.endswith(".monitor") or s.startswith("@"):
        return s
    return f"{s}.monitor"


def sample(device: str, window_bytes: int, rate: int) -> int:
    if not device or not shutil.which("parec"):
        return 0
    try:
        proc = subprocess.Popen(
            [
                "parec",
                "-d",
                device,
                "--raw",
                "--format=s16le",
                f"--rate={rate}",
                "--channels=1",
                "--latency-msec=30",
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        )
    except (OSError, ValueError):
        return 0
    assert proc.stdout is not None
    try:
        chunk = proc.stdout.read(window_bytes)
        return peak_of(chunk or b"")
    except Exception:
        return 0
    finally:
        try:
            proc.kill()
        except Exception:
            pass
        try:
            proc.wait(timeout=0.5)
        except Exception:
            pass


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("sinks", nargs="+")
    ap.add_argument("--window-ms", type=int, default=40)
    ap.add_argument("--rate", type=int, default=16000)
    args = ap.parse_args()
    if not shutil.which("parec"):
        while emit({s: 0 for s in args.sinks}):
            time.sleep(1.0)
        return 0
    window_bytes = max(256, int(args.rate * (args.window_ms / 1000.0) * 2))
    levels = {s: 0 for s in args.sinks}
    idx = 0
    while True:
        if not args.sinks:
            if not emit({}):
                return 0
            time.sleep(0.25)
            continue
        sink = args.sinks[idx % len(args.sinks)]
        idx += 1
        levels[sink] = sample(source_for(sink), window_bytes, args.rate)
        # Decay others slightly so meters fall when silent
        for k in list(levels.keys()):
            if k != sink:
                levels[k] = max(0, int(levels[k] * 0.72))
        if not emit(levels):
            return 0
        time.sleep(0.05)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(0)
