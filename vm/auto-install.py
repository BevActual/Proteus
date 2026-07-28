#!/usr/bin/env python3
"""Drive Arch live ISO over QEMU serial and run guest-install.sh."""
from __future__ import annotations

import os
import socket
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VM = ROOT / "vm"
_cache = Path(
    os.environ.get(
        "PROTEUS_VM_CACHE",
        Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "proteus-vm",
    )
)
RUNTIME = _cache / "runtime"
RUNTIME.mkdir(parents=True, exist_ok=True)
SERIAL = Path(os.environ.get("PROTEUS_VM_SERIAL_SOCK", RUNTIME / "serial.sock"))
QMP = Path(os.environ.get("PROTEUS_VM_QMP_SOCK", RUNTIME / "qmp.sock"))
SSH_PORT = os.environ.get("PROTEUS_VM_SSH_PORT", "2222")
PASSWORD = "proteus"
LOG = Path(os.environ.get("PROTEUS_VM_AUTO_INSTALL_LOG", RUNTIME / "auto-install.log"))


def log(msg: str) -> None:
    line = f"[{time.strftime('%H:%M:%S')}] {msg}"
    print(line, flush=True)
    with LOG.open("a") as f:
        f.write(line + "\n")


def wait_sock(path: Path, timeout: float = 120) -> None:
    deadline = time.time() + timeout
    while time.time() < deadline:
        if path.exists():
            return
        time.sleep(0.2)
    raise TimeoutError(f"socket not ready: {path}")


class Serial:
    def __init__(self, path: Path):
        wait_sock(path)
        time.sleep(0.5)
        self.s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.s.connect(str(path))
        self.s.settimeout(0.5)
        self.buf = bytearray()

    def close(self) -> None:
        try:
            self.s.close()
        except OSError:
            pass

    def read_more(self) -> bytes:
        try:
            data = self.s.recv(65536)
            if data:
                self.buf.extend(data)
            return data
        except socket.timeout:
            return b""

    def drain(self, seconds: float = 1.0) -> str:
        end = time.time() + seconds
        while time.time() < end:
            self.read_more()
            time.sleep(0.05)
        text = self.buf.decode("utf-8", "replace")
        self.buf.clear()
        return text

    def wait_for(self, needles: list[str], timeout: float = 300) -> str:
        deadline = time.time() + timeout
        collected = ""
        while time.time() < deadline:
            self.read_more()
            collected = self.buf.decode("utf-8", "replace")
            for n in needles:
                if n in collected:
                    self.buf.clear()
                    return collected
            time.sleep(0.1)
        snippet = collected[-2000:]
        raise TimeoutError(f"wait_for {needles!r} timed out; tail:\n{snippet}")

    def send(self, data: str) -> None:
        self.s.sendall(data.encode())

    def cmd(self, line: str, wait: list[str] | None = None, timeout: float = 120) -> str:
        self.drain(0.2)
        self.send(line + "\n")
        if wait is None:
            wait = ["@archiso"]
        return self.wait_for(wait, timeout=timeout)


def ssh(cmd: str, user: str = "root", password: str = PASSWORD, timeout: int = 30) -> subprocess.CompletedProcess:
    # Use sshpass if available, else ssh with Prefer/Batch and expect via python paramiko-less:
    env = os.environ.copy()
    if Path("/usr/bin/sshpass").exists():
        full = [
            "sshpass", "-p", password,
            "ssh", "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-o", "PreferredAuthentications=password",
            "-o", "PubkeyAuthentication=no",
            "-p", SSH_PORT, f"{user}@127.0.0.1", cmd,
        ]
        return subprocess.run(full, capture_output=True, text=True, timeout=timeout)

    # Fallback: SSH_ASKPASS
    ask = VM / "_askpass.sh"
    ask.write_text(f"#!/bin/sh\necho {password}\n")
    ask.chmod(0o755)
    env["SSH_ASKPASS"] = str(ask)
    env["SSH_ASKPASS_REQUIRE"] = "force"
    env["DISPLAY"] = env.get("DISPLAY", ":0")
    full = [
        "ssh", "-o", "StrictHostKeyChecking=no",
        "-o", "UserKnownHostsFile=/dev/null",
        "-o", "PreferredAuthentications=password",
        "-o", "PubkeyAuthentication=no",
        "-o", "NumberOfPasswordPrompts=1",
        "-p", SSH_PORT, f"{user}@127.0.0.1", cmd,
    ]
    return subprocess.run(full, capture_output=True, text=True, timeout=timeout, env=env)


def main() -> int:
    LOG.write_text("")
    log("Connecting to serial…")
    ser = Serial(SERIAL)
    try:
        log("Waiting for live root shell…")
        # Boot can take a while with copy-to-ram disabled
        out = ser.wait_for(["@archiso", "login:"], timeout=300)
        if "login:" in out and "@archiso" not in out.split("login:")[-1]:
            ser.send("root\n")
            ser.wait_for(["@archiso", "Password:"], timeout=60)
        log("Live shell ready")

        # Set password + ensure sshd (for later verification path)
        ser.cmd("echo 'root:proteus' | chpasswd", wait=["@archiso"])
        ser.cmd("systemctl start sshd || true", wait=["@archiso"])
        ser.cmd("mkdir -p /mnt/proteus && mount -t 9p -o trans=virtio,version=9p2000.L proteus /mnt/proteus", wait=["@archiso"])
        # Confirm share
        ser.cmd("test -f /mnt/proteus/vm/guest-install.sh && echo SHARE_OK", wait=["SHARE_OK", "@archiso"])
        log("Running guest-install.sh (this takes several minutes)…")
        ser.send("bash /mnt/proteus/vm/guest-install.sh 2>&1 | tee /tmp/guest-install.log; echo EXIT:$?\n")
        # pacstrap can take a long time
        result = ser.wait_for(["EXIT:0", "EXIT:"], timeout=1800)
        if "EXIT:0" not in result:
            log("Install failed; serial tail follows")
            log(result[-3000:])
            return 1
        log("Install succeeded")
        ser.cmd("sync; umount -R /mnt || true", wait=["@archiso"], timeout=60)
        log("Requesting poweroff")
        ser.send("poweroff\n")
        time.sleep(5)
        return 0
    finally:
        ser.close()


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:
        log(f"ERROR: {e}")
        sys.exit(1)
