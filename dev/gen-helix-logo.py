#!/usr/bin/env python3
"""Regenerate the compact Proteus “P” monogram in env/fastfetch/proteus-helix.txt.

Maintainer tooling: run it after editing LINES, then commit the generated art.
Nothing at install or runtime invokes this — the .txt is the shipped artefact.
"""
from pathlib import Path

LINES = [
    "$2",
    "$2  ██████╗",
    "$2  ██╔══██╗",
    "$2  ██████╔╝",
    "$2  ██╔═══╝",
    "$2  ██║",
    "$2  ╚═╝",
    "$1",
    "$1  proteus",
]


def main() -> None:
    # Lives in dev/ (maintainer tooling is never installed) but writes into
    # env/, which is shipped data — hence the explicit repo-relative path.
    out = Path(__file__).resolve().parents[1] / "env/fastfetch/proteus-helix.txt"
    out.write_text("\n".join(LINES) + "\n")
    print(f"wrote {out} (P monogram)")


if __name__ == "__main__":
    main()
