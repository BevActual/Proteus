#!/usr/bin/env python3
"""Stream playback (or capture) peak levels as one integer 0..100 per line.

Replaces the previous sample-per-spawn approach, which ran a whole
`bash -lc` pipeline (pactl | parec | head | od | awk) every ~220ms just to
read one number. This keeps a single `parec` alive and emits a peak per
window, so the cost is one long-lived pipe instead of ~30 process spawns
per second.

Usage:
    audio-peak.py [--device DEV] [--window-ms N] [--rate HZ]

`--device` defaults to @DEFAULT_MONITOR@ (the default sink's monitor), so
the stream follows the default output device across changes. Pass a source
name to meter an input instead.

Output is line-buffered so a reader can consume it incrementally. Emits 0
while audio is unavailable rather than exiting, so callers can treat a
silent stream and a missing device identically. Exits when stdout closes.
"""
from __future__ import annotations

import argparse
import array
import shutil
import subprocess
import sys
import time

RESTART_DELAY = 1.0
MAX_S16 = 32767


def emit(value: int) -> bool:
    """Write one peak line. Returns False once the reader has gone away."""
    try:
        sys.stdout.write(f"{value}\n")
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


def spawn(device: str, rate: int) -> subprocess.Popen[bytes] | None:
    try:
        return subprocess.Popen(
            [
                "parec",
                "-d",
                device,
                "--raw",
                "--format=s16le",
                f"--rate={rate}",
                "--channels=1",
                "--latency-msec=40",
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        )
    except (OSError, ValueError):
        return None


def stream(device: str, window_bytes: int, rate: int) -> bool:
    """Read one parec lifetime. Returns False if the reader disappeared."""
    proc = spawn(device, rate)
    if proc is None or proc.stdout is None:
        return emit(0)
    try:
        while True:
            chunk = proc.stdout.read(window_bytes)
            if not chunk:
                break
            if not emit(peak_of(chunk)):
                return False
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=1)
        except subprocess.TimeoutExpired:
            proc.kill()
    return True


def main() -> int:
    ap = argparse.ArgumentParser(description="Stream audio peak levels")
    ap.add_argument("--device", default="@DEFAULT_MONITOR@")
    ap.add_argument("--window-ms", type=int, default=100)
    ap.add_argument("--rate", type=int, default=8000)
    args = ap.parse_args()

    if not shutil.which("parec"):
        emit(0)
        return 0

    rate = max(1000, args.rate)
    window_ms = max(20, args.window_ms)
    # s16 mono → 2 bytes per sample
    window_bytes = max(2, (rate * window_ms // 1000) * 2)

    while True:
        if not stream(args.device, window_bytes, rate):
            return 0
        # Device vanished (sink switch, server restart). Idle at zero, retry.
        if not emit(0):
            return 0
        time.sleep(RESTART_DELAY)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(0)
