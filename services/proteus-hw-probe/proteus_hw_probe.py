#!/usr/bin/env python3
"""
Proteus hardware probe — Wave A (desktop / laptop) + thin Wave B remote.

Emits JSON: device class, modules present, derived capabilities.
See docs/proteus/HARDWARE.md § Wave A / input.remote.

Usage:
  proteus-hw-probe           # pretty JSON to stdout
  proteus-hw-probe --compact
  proteus-hw-probe --wave A
  PROTEUS_HW_PROBE_FORCE_REMOTE=1     # CI / dogfood without CEC/IR/BT hardware
  PROTEUS_HW_PROBE_FORCE_REMOTE_BT=1  # CI force Bluetooth HID remote path only
  PROTEUS_HW_PROBE_INPUT_DEVICES=/path # override /proc/bus/input/devices (fixture)
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any


WAVE = "A"
SCHEMA = "proteus.hw.probe/v0"


def which(cmd: str) -> bool:
    return shutil.which(cmd) is not None


def run(cmd: list[str], timeout: float = 3.0) -> str:
    try:
        r = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
        return (r.stdout or "") + (r.stderr or "")
    except (OSError, subprocess.TimeoutExpired):
        return ""


def read_text(path: Path) -> str | None:
    try:
        return path.read_text(encoding="utf-8", errors="replace").strip()
    except OSError:
        return None


def chassis_type() -> str | None:
    # systemd: chassis
    out = run(["hostnamectl", "chassis"])
    if out.strip():
        # hostnamectl chassis → "laptop" on some versions; others need --json
        line = out.strip().splitlines()[0].strip().lower()
        if line and " " not in line and line.isalpha():
            return line
    out = run(["hostnamectl", "--json=short"])
    if out.strip().startswith("{"):
        try:
            data = json.loads(out)
            ch = data.get("Chassis") or data.get("chassis")
            if isinstance(ch, str) and ch:
                return ch.lower()
        except json.JSONDecodeError:
            pass
    # DMI
    dmi = read_text(Path("/sys/class/dmi/id/chassis_type"))
    # SMBIOS chassis types: 9/10/14 ≈ laptop/notebook/subnotebook
    if dmi in {"8", "9", "10", "14"}:
        return "laptop"
    if dmi in {"3", "4", "6", "7"}:
        return "desktop"
    return None


def has_battery() -> bool:
    power = Path("/sys/class/power_supply")
    if not power.is_dir():
        return False
    for ps in power.iterdir():
        t = read_text(ps / "type")
        if t and t.upper() == "BATTERY":
            return True
    # UPower fallback
    if which("upower"):
        out = run(["upower", "-e"])
        return "battery" in out.lower()
    return False


def on_ac() -> bool | None:
    power = Path("/sys/class/power_supply")
    if not power.is_dir():
        return None
    found = False
    online = False
    for ps in power.iterdir():
        t = read_text(ps / "type")
        if not t:
            continue
        tu = t.upper()
        if tu in {"MAINS", "USB"}:
            found = True
            o = read_text(ps / "online")
            if o == "1":
                online = True
    if not found:
        return None
    return online


def has_lid() -> bool:
    if Path("/proc/acpi/button/lid").is_dir():
        return True
    text = read_text(Path("/proc/bus/input/devices")) or ""
    return "lid switch" in text.lower()


def drm_connectors() -> list[dict[str, Any]]:
    cards = sorted(Path("/sys/class/drm").glob("card*-*"))
    out: list[dict[str, Any]] = []
    for conn in cards:
        name = conn.name
        if name.count("-") < 1:
            continue
        status = read_text(conn / "status") or "unknown"
        enabled = read_text(conn / "enabled")
        out.append(
            {
                "id": name,
                "status": status,
                "enabled": enabled,
                "connected": status == "connected",
            }
        )
    return out


def _sysfs_nonempty(path: Path) -> bool:
    try:
        return path.is_dir() and any(path.iterdir())
    except OSError:
        return False


def _input_devices_text() -> str:
    """/proc/bus/input/devices, or PROTEUS_HW_PROBE_INPUT_DEVICES fixture path."""
    override = os.environ.get("PROTEUS_HW_PROBE_INPUT_DEVICES", "").strip()
    if override:
        return read_text(Path(override)) or ""
    return read_text(Path("/proc/bus/input/devices")) or ""


def _env_truthy(name: str) -> bool:
    return os.environ.get(name, "").strip().lower() in ("1", "true", "yes", "on")


def _looks_like_bt_remote_name(name: str) -> bool:
    """Name heuristics for Bluetooth HID remotes — not bare Consumer Control."""
    n = name.lower().strip()
    if not n:
        return False
    # Exclude common non-remote BT HID that mention "remote" loosely.
    if any(x in n for x in ("remote desktop", "headset", "hands-free", "handsfree")):
        return False
    needles = (
        "remote control",
        "media remote",
        "tv remote",
        "bluetooth remote",
        "smart remote",
        "presentation remote",
        "presentation clicker",
        "fire tv",
        "fire stick",
        "roku",
        "harmony",
        "apple tv",
        "keyspan",
        "satechi",
        "logitech spotlight",
        "logitech present",
    )
    if any(x in n for x in needles):
        return True
    # Bare "remote" on BT (e.g. "Acme Remote") — skip Consumer Control alone.
    if "remote" in n and "consumer control" not in n:
        return True
    return False


def has_bluetooth_hid_remote() -> bool:
    """Thin: Bluetooth (Bus=0005) input device with remote-like Name=.

    Out: pairing UI · key decode · IR-over-BT proprietary stacks.
    Honors PROTEUS_HW_PROBE_FORCE_REMOTE_BT=1 for smoke without hardware.
    """
    if _env_truthy("PROTEUS_HW_PROBE_FORCE_REMOTE_BT"):
        return True
    text = _input_devices_text()
    if not text.strip():
        return False
    for block in text.split("\n\n"):
        bus_raw = ""
        name = ""
        phys = ""
        for line in block.splitlines():
            if line.startswith("I:") and "Bus=" in line:
                for part in line.split():
                    if part.startswith("Bus="):
                        bus_raw = part.split("=", 1)[1].strip().lower()
            elif line.startswith("N: Name="):
                raw = line.split("=", 1)[1].strip()
                if len(raw) >= 2 and raw[0] == '"' and raw[-1] == '"':
                    raw = raw[1:-1]
                name = raw
            elif line.startswith("P: Phys="):
                phys = line.split("=", 1)[1].strip().lower()
        is_bt = bus_raw == "0005" or "bluetooth" in phys
        if is_bt and _looks_like_bt_remote_name(name):
            return True
    return False


def has_remote_input() -> bool:
    """Thin Wave B: CEC / IR (rc) / lirc / Bluetooth HID remote names.

    Also honors PROTEUS_HW_PROBE_FORCE_REMOTE=1 for smoke without hardware.
    QML still accepts PROTEUS_REMOTE_PROBE stub when probe finds nothing.
    """
    if _env_truthy("PROTEUS_HW_PROBE_FORCE_REMOTE"):
        return True
    if _sysfs_nonempty(Path("/sys/class/cec")):
        return True
    if _sysfs_nonempty(Path("/sys/class/rc")):
        return True
    if _sysfs_nonempty(Path("/sys/class/lirc")):
        return True
    try:
        for p in Path("/dev").glob("cec*"):
            if p.exists():
                return True
        for p in Path("/dev").glob("lirc*"):
            if p.exists():
                return True
    except OSError:
        pass
    # /proc/bus/input Name= lines for common IR receivers
    text = _input_devices_text().lower()
    if any(
        n in text
        for n in (
            "gpio_ir",
            "gpio-ir",
            "meson-ir",
            "sunxi-ir",
            "ite cir",
            "nuvoton cir",
            "ene cir",
            "rc-core",
            "infrared",
        )
    ):
        return True
    if has_bluetooth_hid_remote():
        return True
    return False


def input_devices() -> dict[str, bool]:
    """Heuristic from /proc/bus/input/devices and by-path."""
    text = _input_devices_text()
    low = text.lower()
    # libinput list if available
    li = run(["libinput", "list-devices"]) if which("libinput") else ""
    blob = low + "\n" + li.lower()

    def hit(*needles: str) -> bool:
        return any(n in blob for n in needles)

    return {
        "input.keyboard": hit("keyboard", "kbd"),
        "input.pointer": hit("mouse", "touchpad", "trackpoint", "pointer"),
        "input.touch": hit("touchscreen", "touch screen", "finger"),
        "input.gamepad": hit("joystick", "gamepad", "x-box", "xbox"),
        "input.remote": has_remote_input(),
    }


def audio_nodes() -> dict[str, bool]:
    speaker = mic = False
    if which("pactl"):
        sinks = run(["pactl", "list", "short", "sinks"])
        sources = run(["pactl", "list", "short", "sources"])
        speaker = bool(sinks.strip())
        # exclude monitor sources
        mic = any(
            line.strip() and ".monitor" not in line
            for line in sources.splitlines()
        )
    elif which("wpctl"):
        out = run(["wpctl", "status"])
        speaker = "sinks" in out.lower() or "audio" in out.lower()
        mic = "sources" in out.lower()
    return {"audio.speaker": speaker, "audio.mic": mic}


def net_modules() -> dict[str, bool]:
    wifi = ethernet = bt = False
    # sysfs net
    net = Path("/sys/class/net")
    if net.is_dir():
        for iface in net.iterdir():
            if iface.name == "lo":
                continue
            wireless = iface / "wireless"
            type_path = iface / "type"
            # type 1 = ether
            if wireless.is_dir() or (iface / "phy80211").exists():
                wifi = True
            else:
                t = read_text(type_path)
                if t == "1":
                    ethernet = True
    if which("nmcli"):
        out = run(["nmcli", "-t", "-f", "TYPE,DEVICE", "dev"])
        for line in out.splitlines():
            parts = line.split(":")
            if not parts:
                continue
            typ = parts[0].lower()
            if typ == "wifi":
                wifi = True
            elif typ == "ethernet":
                ethernet = True
            elif typ in {"bt", "bluetooth"}:
                bt = True
    if Path("/sys/class/bluetooth").is_dir() and any(Path("/sys/class/bluetooth").iterdir()):
        bt = True
    elif which("bluetoothctl"):
        # presence of controller
        out = run(["bluetoothctl", "list"])
        bt = bool(out.strip())
    return {
        "net.wifi": wifi,
        "net.ethernet": ethernet,
        "net.bt": bt,
    }


def session_modules() -> dict[str, bool]:
    wayland = bool(os.environ.get("WAYLAND_DISPLAY"))
    x11 = bool(os.environ.get("DISPLAY"))
    local_graphical = wayland or x11
    ssh = bool(os.environ.get("SSH_CONNECTION") or os.environ.get("SSH_CLIENT"))
    return {
        "session.wayland": wayland,
        "session.x11": x11,
        "session.local_seat": local_graphical,
        "session.ssh": ssh,
        "session.headless": not local_graphical,
    }


def engine_modules() -> dict[str, bool]:
    return {
        "engine.hyprland": which("Hyprland") or which("hyprctl"),
        "engine.quickshell": which("quickshell"),
        "engine.pipewire": which("pipewire") or which("pw-cli") or which("pactl"),
        "engine.networkmanager": which("nmcli"),
    }


def classify(chassis: str | None, battery: bool, lid: bool) -> str:
    if chassis in {"laptop", "notebook", "convertible", "handset", "tablet"}:
        if chassis == "handset":
            return "phone"  # out of wave A, but honest
        if chassis == "tablet":
            return "tablet"
        return "laptop"
    if chassis in {"desktop", "tower", "all-in-one", "server", "mini-tower"}:
        if chassis == "server":
            return "server"
        return "desktop"
    # Heuristic
    if battery or lid:
        return "laptop"
    return "desktop"


def collect_wave_a() -> dict[str, Any]:
    chassis = chassis_type()
    battery = has_battery()
    lid = has_lid()
    connectors = drm_connectors()
    connected_displays = [c for c in connectors if c.get("connected")]
    inputs = input_devices()
    audio = audio_nodes()
    net = net_modules()
    session = session_modules()
    engines = engine_modules()
    ac = on_ac()

    device_class = classify(chassis, battery, lid)

    modules: dict[str, bool] = {
        "display.panel": len(connected_displays) >= 1 or session.get("session.local_seat", False),
        "display.multi": len(connected_displays) >= 2,
        **inputs,
        **audio,
        **net,
        "power.battery": battery,
        "power.ac": bool(ac) if ac is not None else False,
        "chassis.lid": lid,
        **session,
        **engines,
    }

    # Derived capabilities (HARDWARE.md §4) — wave A subset
    capabilities: dict[str, bool] = {
        "display": modules["display.panel"],
        "headless": modules["session.headless"] and not modules["display.panel"],
        "keyboard": modules["input.keyboard"],
        "pointer": modules["input.pointer"],
        "touch": modules["input.touch"],
        "gamepad": modules["input.gamepad"],
        "remote": modules.get("input.remote", False),
        "mic": modules["audio.mic"],
        "speaker": modules["audio.speaker"],
        "battery": modules["power.battery"],
        "wifi": modules["net.wifi"],
        "ethernet": modules["net.ethernet"],
        "bt": modules["net.bt"],
        "multi_monitor": modules["display.multi"],
        "tiling": modules["engine.hyprland"] and modules["display.panel"],
        "qs_hyprland": modules["engine.hyprland"] and modules["engine.quickshell"],
        "qs_pipewire": modules["engine.pipewire"],
    }

    return {
        "schema": SCHEMA,
        "wave": WAVE,
        "device_class": device_class,
        "chassis": chassis,
        "posture_hint": "desktop" if device_class in {"desktop", "laptop"} else None,
        "modules": {k: v for k, v in sorted(modules.items()) if v},
        "modules_absent": sorted(k for k, v in modules.items() if not v),
        "capabilities": {k: v for k, v in sorted(capabilities.items()) if v},
        "capabilities_false": sorted(k for k, v in capabilities.items() if not v),
        "details": {
            "drm_connectors": connectors,
            "power_ac_online": ac,
            "env": {
                "WAYLAND_DISPLAY": os.environ.get("WAYLAND_DISPLAY"),
                "DISPLAY": os.environ.get("DISPLAY"),
                "XDG_SESSION_TYPE": os.environ.get("XDG_SESSION_TYPE"),
            },
        },
    }


def main() -> int:
    ap = argparse.ArgumentParser(description="Proteus Wave A hardware probe")
    ap.add_argument("--compact", action="store_true", help="Single-line JSON")
    ap.add_argument(
        "--cache",
        nargs="?",
        const="DEFAULT",
        default=None,
        help="Write probe JSON to path (default: ~/.config/proteus/hw-probe.json)",
    )
    ap.add_argument("--wave", default="A", help="Probe wave (only A implemented)")
    args = ap.parse_args()
    if str(args.wave).upper() != "A":
        print(
            json.dumps(
                {
                    "error": "only wave A is implemented",
                    "requested": args.wave,
                }
            ),
            file=sys.stderr,
        )
        return 2

    from datetime import datetime, timezone

    report = collect_wave_a()
    report["probed_at"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    report["source"] = "proteus-hw-probe"

    if args.cache is not None:
        cache_path = (
            Path.home() / ".config" / "proteus" / "hw-probe.json"
            if args.cache == "DEFAULT"
            else Path(args.cache).expanduser()
        )
        try:
            cache_path.parent.mkdir(parents=True, exist_ok=True)
            cache_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        except OSError as e:
            print(f"warning: could not write cache {cache_path}: {e}", file=sys.stderr)

    if args.compact:
        print(json.dumps(report, separators=(",", ":")))
    else:
        print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
