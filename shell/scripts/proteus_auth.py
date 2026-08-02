#!/usr/bin/env python3
"""Shared lock-screen auth: PAM password + hashed unlock PIN.

PIN lives under ~/.local/share/proteus/auth/pin (0600) — never settings.json.
"""
from __future__ import annotations

import hashlib
import json
import os
import secrets
from typing import Any

# Re-use PAM stack from check-password when available; keep a local copy of the
# essentials so this module stays importable on its own for smoke tests.
import ctypes
import ctypes.util

PAM_SUCCESS = 0
PAM_SERVICE_DIR = "/etc/pam.d"
FALLBACK_SERVICE = "login"
PAM_PROMPT_ECHO_OFF = 1
PAM_PROMPT_ECHO_ON = 2

PIN_MIN_LEN = 4
PIN_MAX_LEN = 8
PIN_VERSION = 1
# scrypt params — interactive unlock; not a password-hashing competition.
SCRYPT_N = 2**14
SCRYPT_R = 8
SCRYPT_P = 1
SCRYPT_DKLEN = 32


def pin_path(home: str | None = None) -> str:
    base = home if home is not None else os.environ.get("HOME", "")
    if not base:
        base = os.path.expanduser("~")
    return os.path.join(base, ".local", "share", "proteus", "auth", "pin")


def pin_status(home: str | None = None) -> dict[str, Any]:
    path = pin_path(home)
    if not os.path.isfile(path):
        return {"configured": False, "length": 0, "path": path}
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
        length = int(data.get("length") or 0)
        if length < PIN_MIN_LEN or length > PIN_MAX_LEN:
            return {"configured": False, "length": 0, "path": path, "error": "bad length"}
        return {"configured": True, "length": length, "path": path}
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        return {"configured": False, "length": 0, "path": path, "error": str(exc)}


def _validate_pin(pin: str) -> str | None:
    if not pin.isdigit():
        return "PIN must be digits only"
    if not (PIN_MIN_LEN <= len(pin) <= PIN_MAX_LEN):
        return f"PIN must be {PIN_MIN_LEN}–{PIN_MAX_LEN} digits"
    return None


def hash_pin(pin: str, salt: bytes | None = None) -> dict[str, Any]:
    err = _validate_pin(pin)
    if err:
        raise ValueError(err)
    if salt is None:
        salt = secrets.token_bytes(16)
    digest = hashlib.scrypt(
        pin.encode("utf-8"),
        salt=salt,
        n=SCRYPT_N,
        r=SCRYPT_R,
        p=SCRYPT_P,
        dklen=SCRYPT_DKLEN,
    )
    return {
        "version": PIN_VERSION,
        "salt": salt.hex(),
        "hash": digest.hex(),
        "length": len(pin),
        "n": SCRYPT_N,
        "r": SCRYPT_R,
        "p": SCRYPT_P,
        "dklen": SCRYPT_DKLEN,
    }


def verify_pin(pin: str, home: str | None = None) -> bool:
    path = pin_path(home)
    if not os.path.isfile(path):
        return False
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, json.JSONDecodeError):
        return False
    if int(data.get("version") or 0) != PIN_VERSION:
        return False
    try:
        salt = bytes.fromhex(data["salt"])
        expect = bytes.fromhex(data["hash"])
        length = int(data["length"])
        n = int(data.get("n") or SCRYPT_N)
        r = int(data.get("r") or SCRYPT_R)
        p = int(data.get("p") or SCRYPT_P)
        dklen = int(data.get("dklen") or SCRYPT_DKLEN)
    except (KeyError, ValueError, TypeError):
        return False
    if len(pin) != length or not pin.isdigit():
        # Still run scrypt with a dummy so timing stays roughly similar.
        hashlib.scrypt(
            b"0" * length,
            salt=salt,
            n=n,
            r=r,
            p=p,
            dklen=dklen,
        )
        return False
    got = hashlib.scrypt(
        pin.encode("utf-8"),
        salt=salt,
        n=n,
        r=r,
        p=p,
        dklen=dklen,
    )
    return secrets.compare_digest(got, expect)


def write_pin(pin: str, home: str | None = None) -> None:
    err = _validate_pin(pin)
    if err:
        raise ValueError(err)
    path = pin_path(home)
    os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
    payload = hash_pin(pin)
    tmp = path + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(payload, fh, separators=(",", ":"))
            fh.write("\n")
        os.replace(tmp, path)
        os.chmod(path, 0o600)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def clear_pin(home: str | None = None) -> bool:
    path = pin_path(home)
    if not os.path.isfile(path):
        return False
    os.unlink(path)
    return True


# --- PAM (mirrors check-password.py) ----------------------------------------


class PamHandle(ctypes.c_void_p):
    pass


class PamMessage(ctypes.Structure):
    _fields_ = [
        ("msg_style", ctypes.c_int),
        ("msg", ctypes.c_char_p),
    ]


class PamResponse(ctypes.Structure):
    _fields_ = [
        ("resp", ctypes.c_char_p),
        ("resp_retcode", ctypes.c_int),
    ]


CONV_FUNC = ctypes.CFUNCTYPE(
    ctypes.c_int,
    ctypes.c_int,
    ctypes.POINTER(ctypes.POINTER(PamMessage)),
    ctypes.POINTER(ctypes.POINTER(PamResponse)),
    ctypes.c_void_p,
)


class PamConv(ctypes.Structure):
    _fields_ = [
        ("conv", CONV_FUNC),
        ("appdata_ptr", ctypes.c_void_p),
    ]


def load_pam():
    name = ctypes.util.find_library("pam") or "libpam.so.0"
    lib = ctypes.CDLL(name)
    lib.pam_start.argtypes = [
        ctypes.c_char_p,
        ctypes.c_char_p,
        ctypes.POINTER(PamConv),
        ctypes.POINTER(PamHandle),
    ]
    lib.pam_start.restype = ctypes.c_int
    lib.pam_authenticate.argtypes = [PamHandle, ctypes.c_int]
    lib.pam_authenticate.restype = ctypes.c_int
    lib.pam_acct_mgmt.argtypes = [PamHandle, ctypes.c_int]
    lib.pam_acct_mgmt.restype = ctypes.c_int
    lib.pam_end.argtypes = [PamHandle, ctypes.c_int]
    lib.pam_end.restype = ctypes.c_int
    return lib


def resolve_service(service: str) -> str:
    name = (service or "").strip() or FALLBACK_SERVICE
    if os.path.exists(os.path.join(PAM_SERVICE_DIR, name)):
        return name
    return FALLBACK_SERVICE


def authenticate_password(user: str, password: str, service: str = "proteus-lock") -> bool:
    lib = load_pam()
    password_bytes = password.encode("utf-8")
    libc = ctypes.CDLL(ctypes.util.find_library("c") or "libc.so.6")
    libc.malloc.restype = ctypes.c_void_p
    libc.strdup.argtypes = [ctypes.c_char_p]
    libc.strdup.restype = ctypes.c_void_p

    @CONV_FUNC
    def conv_malloc(n_msg, msg, resp, app_data):
        raw = libc.malloc(ctypes.sizeof(PamResponse) * n_msg)
        if not raw:
            return 15  # PAM_BUF_ERR
        arr = (PamResponse * n_msg).from_address(raw)
        for i in range(n_msg):
            style = msg[i].contents.msg_style
            if style in (PAM_PROMPT_ECHO_OFF, PAM_PROMPT_ECHO_ON):
                dup = libc.strdup(password_bytes)
                arr[i].resp = ctypes.cast(dup, ctypes.c_char_p)
                arr[i].resp_retcode = 0
            else:
                arr[i].resp = None
                arr[i].resp_retcode = 0
        resp[0] = ctypes.cast(raw, ctypes.POINTER(PamResponse))
        return PAM_SUCCESS

    handle = PamHandle()
    conversation = PamConv(conv_malloc, None)
    status = lib.pam_start(
        resolve_service(service).encode(),
        user.encode(),
        ctypes.byref(conversation),
        ctypes.byref(handle),
    )
    if status != PAM_SUCCESS:
        return False
    status = lib.pam_authenticate(handle, 0)
    if status == PAM_SUCCESS:
        status = lib.pam_acct_mgmt(handle, 0)
    lib.pam_end(handle, status)
    return status == PAM_SUCCESS


def current_user() -> str:
    return os.environ.get("USER") or os.environ.get("LOGNAME") or ""
