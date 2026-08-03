#!/usr/bin/env bash
# doc-links-smoke — every relative link in every tracked .md must resolve.
#
# The install/ layout split rewrote link *labels* but left relative hrefs like
# `guest/` and `../guest/` pointing at directories that no longer existed, and
# nothing noticed: the docs are the SoT this project routes agents and
# contributors through, so a dangling path is a real defect, not a typo.
#
# Executable, not a grep assertion — it resolves each path against the filesystem.
set -euo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"
cd "${ROOT}"

python3 - "${ROOT}" <<'PY'
import re, subprocess, sys
from pathlib import Path

root = Path(sys.argv[1])
files = subprocess.check_output(["git", "ls-files", "*.md"], cwd=root, text=True).split()

# [label](href) — skip external schemes and pure anchors; strip #fragment and
# any "title" suffix inside the parens.
LINK = re.compile(r'\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)')
broken = []
checked = 0

for rel in files:
    md = root / rel
    try:
        text = md.read_text(errors="ignore")
    except OSError:
        continue
    for m in LINK.finditer(text):
        href = m.group(2).split("#")[0].strip()
        if not href or href.startswith(("http://", "https://", "mailto:", "#", "file://")):
            continue
        checked += 1
        if not (md.parent / href).exists():
            broken.append(f"{rel}: [{m.group(1)[:44]}] -> {href}")

if broken:
    print(f"doc-links-smoke: FAIL {len(broken)} broken relative link(s) of {checked} checked",
          file=sys.stderr)
    for b in broken:
        print(f"  {b}", file=sys.stderr)
    sys.exit(1)

print(f"doc-links-smoke: OK {checked} relative links across {len(files)} docs all resolve")
PY
