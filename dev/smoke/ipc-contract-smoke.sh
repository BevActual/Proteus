#!/usr/bin/env bash
# ipc-contract-smoke — every `qs ipc call <target> <method>` in smokes must exist
# on an IpcHandler in shell / Settings entry QML.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

die() { echo "ipc-contract-smoke: FAIL $*" >&2; exit 1; }
ok() { echo "ipc-contract-smoke: OK $*"; }

python3 - "${ROOT}" <<'PY' || die "contract check"
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
sources = [
    root / "shell/surfaces/DesktopShell.qml",
    root / "apps/proteus-settings/shell.qml",
]
for p in sources:
    if not p.is_file():
        print(f"missing source {p}", file=sys.stderr)
        sys.exit(1)

# target -> set(method)
handlers: dict[str, set[str]] = {}
target_re = re.compile(r'target:\s*"([^"]+)"')
fn_re = re.compile(r"function\s+(\w+)\s*\(")

for path in sources:
    text = path.read_text(encoding="utf-8")
    # Manual scan: find IpcHandler { … matching }
    i = 0
    while True:
        j = text.find("IpcHandler", i)
        if j < 0:
            break
        brace = text.find("{", j)
        if brace < 0:
            break
        depth = 0
        k = brace
        while k < len(text):
            if text[k] == "{":
                depth += 1
            elif text[k] == "}":
                depth -= 1
                if depth == 0:
                    break
            k += 1
        body = text[brace + 1 : k]
        tm = target_re.search(body)
        if tm:
            target = tm.group(1)
            methods = set(fn_re.findall(body))
            handlers.setdefault(target, set()).update(methods)
        i = k + 1

if not handlers:
    print("no IpcHandler targets parsed", file=sys.stderr)
    sys.exit(1)

# Calls from smoke scripts — require qs/quickshell so prose ("ipc call sites")
# inside this smoke does not false-positive.
call_re = re.compile(
    r"(?:qs|quickshell)\b(?:\s+\S+)*?\s+ipc\s+call\s+(\w+)\s+(\w+)"
)
calls: list[tuple[str, str, str]] = []
smoke_dir = root / "dev/smoke"
for sh in sorted(smoke_dir.glob("*-smoke.sh")):
    if sh.name == "ipc-contract-smoke.sh":
        continue
    for line_no, line in enumerate(sh.read_text(encoding="utf-8").splitlines(), 1):
        stripped = line.lstrip()
        if stripped.startswith("#"):
            continue
        for m in call_re.finditer(line):
            calls.append((m.group(1), m.group(2), f"{sh.name}:{line_no}"))

if not calls:
    print("no ipc call sites found in dev/smoke", file=sys.stderr)
    sys.exit(1)

missing = []
for target, method, where in calls:
    methods = handlers.get(target)
    if methods is None:
        missing.append(f"{where}: target '{target}' not in IpcHandler sources")
        continue
    if method not in methods:
        missing.append(
            f"{where}: {target}.{method} missing (have: {', '.join(sorted(methods))})"
        )

if missing:
    print("ipc-contract-smoke: FAIL", file=sys.stderr)
    for row in missing:
        print(f"  {row}", file=sys.stderr)
    sys.exit(1)

print(
    f"handlers={len(handlers)} targets; calls={len(calls)} sites; OK"
)
for t in sorted(handlers):
    print(f"  {t}: {', '.join(sorted(handlers[t]))}")
PY

ok "smoke IPC calls ⊆ shell/Settings handlers"
echo "ipc-contract-smoke: OK"
