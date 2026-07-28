#!/usr/bin/env python3
"""Check a password via libpam (ctypes). No python-pam package required."""
from __future__ import annotations

import ctypes
import ctypes.util
import os
import sys

PAM_SUCCESS = 0
PAM_SERVICE_DIR = "/etc/pam.d"
FALLBACK_SERVICE = "login"
PAM_PROMPT_ECHO_OFF = 1
PAM_PROMPT_ECHO_ON = 2


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
    """Fall back to the login stack if the requested service isn't installed.

    A missing /etc/pam.d/<service> otherwise falls through to `other`, which on
    most distros is pam_deny — i.e. the user could never unlock. Degrading to
    `login` keeps the lock screen usable when the Proteus PAM file hasn't been
    installed on this host yet.
    """
    name = (service or "").strip() or FALLBACK_SERVICE
    if os.path.exists(os.path.join(PAM_SERVICE_DIR, name)):
        return name
    return FALLBACK_SERVICE


def authenticate(user: str, password: str, service: str = "login") -> bool:
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


def main() -> int:
    user = sys.argv[1] if len(sys.argv) > 1 else ""
    service = sys.argv[2] if len(sys.argv) > 2 else "proteus-lock"
    # readline so a single password\n works even if stdin isn't closed yet
    password = sys.stdin.readline().rstrip("\n\r")
    if not user:
        return 1
    try:
        ok = authenticate(user, password, service=service)
    except OSError as exc:
        sys.stderr.write(f"pam error: {exc}\n")
        return 2
    except Exception as exc:  # noqa: BLE001 — surface helper crashes to QS
        sys.stderr.write(f"auth error: {exc}\n")
        return 2
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
