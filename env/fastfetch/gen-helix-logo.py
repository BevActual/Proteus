#!/usr/bin/env python3
"""Write compact Proteus “P” monogram for fastfetch."""
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
    out = Path(__file__).resolve().parent / "proteus-helix.txt"
    out.write_text("\n".join(LINES) + "\n")
    print(f"wrote {out} (P monogram)")


if __name__ == "__main__":
    main()
