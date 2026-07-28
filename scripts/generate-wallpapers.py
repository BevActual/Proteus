#!/usr/bin/env python3
"""Generate Proteus built-in atmospheric wallpapers (2560x1440 JPEG).

Soft elliptical gaussian blooms + subtle film grain + dither. No hard bands.
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path

import numpy as np
from PIL import Image

W, H = 2560, 1440

REPO = Path(__file__).resolve().parents[1]
DEFAULT_ASSETS = REPO / "shell" / "assets"
DEFAULT_PREVIEW = Path("/tmp/proteus-wp-preview2")
JPEG_QUALITY = 92


def hex_rgb(h: str) -> np.ndarray:
    h = h.lstrip("#")
    return np.array([int(h[i : i + 2], 16) for i in (0, 2, 4)], dtype=np.float64)


def soft_blob(
    yy: np.ndarray,
    xx: np.ndarray,
    cx: float,
    cy: float,
    sigma_x: float,
    sigma_y: float,
    color: np.ndarray,
    intensity: float,
) -> np.ndarray:
    g = np.exp(
        -(
            ((xx - cx) ** 2) / (2.0 * sigma_x**2)
            + ((yy - cy) ** 2) / (2.0 * sigma_y**2)
        )
    )
    return g[..., None] * (color * intensity)


def box_blur(ch: np.ndarray, passes: int = 3) -> np.ndarray:
    """Cheap separable-ish blur via neighbor averaging (periodic edges OK for LF)."""
    out = ch
    for _ in range(passes):
        out = (
            out
            + np.roll(out, 1, 0)
            + np.roll(out, -1, 0)
            + np.roll(out, 1, 1)
            + np.roll(out, -1, 1)
        ) / 5.0
    return out


def low_freq_noise(rng: np.random.Generator, h: int, w: int, scale: int = 32) -> np.ndarray:
    """Very blurred noise upsampled for organic variation / anti-banding."""
    sh, sw = max(1, h // scale), max(1, w // scale)
    small = rng.normal(0.0, 1.0, (sh, sw)).astype(np.float64)
    # heavy blur in low-res domain
    small = box_blur(small, passes=8)
    # nearest upsample then mild blur at full-ish intermediate
    up = np.repeat(np.repeat(small, scale, axis=0), scale, axis=1)[:h, :w]
    # extra smooth
    mid = up[::4, ::4]
    mid = box_blur(mid, passes=4)
    up = np.repeat(np.repeat(mid, 4, axis=0), 4, axis=1)[:h, :w]
    # normalize roughly
    std = up.std()
    if std > 1e-9:
        up = up / std
    return up


def make_wallpaper(
    base_hex: str,
    blooms: list[tuple],
    *,
    grain_fine: float = 0.008,
    grain_lf: float = 0.012,
    vignette_strength: float = 0.52,
    seed: int = 0,
) -> Image.Image:
    rng = np.random.default_rng(seed)
    base = hex_rgb(base_hex) / 255.0
    img = np.broadcast_to(base, (H, W, 3)).astype(np.float64).copy()
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float64)

    for cx, cy, sx, sy, color_hex, intensity in blooms:
        c = hex_rgb(color_hex) / 255.0
        img += soft_blob(yy, xx, cx, cy, sx, sy, c, intensity)

    # Subtle film: fine grain (low amp) + mild low-frequency organic noise
    fine = rng.normal(0.0, 1.0, (H, W, 1)).astype(np.float64)
    lf = low_freq_noise(rng, H, W, scale=40)[..., None]
    # slight chroma tint on LF so it doesn't look like gray grit
    lf_rgb = lf * np.array([0.95, 1.0, 1.05], dtype=np.float64)
    img = img + fine * grain_fine + lf_rgb * grain_lf

    # Soft vignette
    cx, cy = W / 2.0, H / 2.0
    rx = np.sqrt(((xx - cx) / (W * 0.75)) ** 2 + ((yy - cy) / (H * 0.75)) ** 2)
    vig = 1.0 - vignette_strength * np.clip(rx**1.55, 0.0, 1.0)
    img *= vig[..., None]

    # Triangular dither before quantize (reduces banding in soft transitions)
    # TPDF: sum of two uniform(-0.5, 0.5) => triangular on [-1, 1]
    dither = (
        rng.random((H, W, 3)) + rng.random((H, W, 3)) - 1.0
    ) / 255.0
    img = img + dither

    img = np.clip(img, 0.0, 1.0)
    out = (img * 255.0).astype(np.uint8)
    return Image.fromarray(out, mode="RGB")


# Bloom tuples: (cx, cy, sigma_x, sigma_y, hex, intensity)
THEMES: dict[str, dict] = {
    "wallpaper.jpg": dict(
        base_hex="#050708",
        seed=101,
        grain_fine=0.007,
        grain_lf=0.011,
        vignette_strength=0.55,
        blooms=[
            # primary lower-center teal
            (1280, 1180, 920, 480, "#1a6f7a", 0.48),
            (1180, 1050, 620, 360, "#2a8a8a", 0.30),
            # secondary softer blooms — different positions/colors
            (720, 780, 540, 460, "#0e4a52", 0.26),
            (1900, 920, 580, 500, "#164e56", 0.24),
            (1500, 1320, 780, 300, "#1f7a7a", 0.22),
            (980, 500, 480, 400, "#0a3038", 0.16),
        ],
    ),
    "wallpaper-harbor.jpg": dict(
        base_hex="#0b1220",
        seed=202,
        grain_fine=0.0065,
        grain_lf=0.012,
        vignette_strength=0.48,
        blooms=[
            # soft horizontal horizon mist (wide sigma_x, narrower sigma_y)
            (1280, 880, 1600, 280, "#3d8bfd", 0.36),
            (1280, 980, 1400, 340, "#2a5a9a", 0.30),
            (900, 860, 900, 260, "#5aa0ff", 0.20),
            (1700, 900, 850, 250, "#3d8bfd", 0.18),
            (600, 700, 520, 420, "#1e3a6a", 0.22),
            (2000, 720, 540, 400, "#243a68", 0.18),
            (1280, 560, 1100, 480, "#1a2f50", 0.14),
        ],
    ),
    "wallpaper-ember.jpg": dict(
        base_hex="#080605",
        seed=303,
        grain_fine=0.007,
        grain_lf=0.011,
        vignette_strength=0.58,
        blooms=[
            (1280, 1280, 980, 400, "#c45c26", 0.42),
            (1040, 1180, 680, 320, "#a84a1c", 0.30),
            (1580, 1220, 620, 300, "#c45c26", 0.26),
            (1280, 1080, 420, 260, "#e07830", 0.16),
            (780, 880, 460, 380, "#4a2818", 0.24),
            (1880, 980, 500, 360, "#3a2010", 0.20),
            (520, 620, 400, 340, "#2a1810", 0.14),
        ],
    ),
    "wallpaper-signal.jpg": dict(
        base_hex="#0c0e12",
        seed=404,
        grain_fine=0.0065,
        grain_lf=0.010,
        vignette_strength=0.48,
        blooms=[
            # NW Proteus blue
            (620, 400, 720, 520, "#3d8bfd", 0.40),
            (420, 520, 480, 400, "#2a6fd0", 0.24),
            (900, 340, 420, 360, "#3d8bfd", 0.18),
            # SE teal
            (1980, 1080, 680, 480, "#2dd4bf", 0.36),
            (2180, 920, 460, 380, "#1aa896", 0.22),
            # slate center depth
            (1280, 780, 860, 560, "#2a3548", 0.18),
            (1100, 980, 560, 420, "#1a2838", 0.14),
        ],
    ),
    "wallpaper-reef.jpg": dict(
        base_hex="#061418",
        seed=505,
        grain_fine=0.007,
        grain_lf=0.012,
        vignette_strength=0.52,
        blooms=[
            (1280, 900, 960, 600, "#1a6f7a", 0.36),
            (780, 760, 680, 480, "#0e5a62", 0.32),
            (1780, 980, 720, 460, "#2a8a8a", 0.28),
            (1120, 1180, 760, 380, "#145860", 0.30),
            (1580, 580, 520, 420, "#1f7a72", 0.20),
            (520, 1000, 480, 380, "#0a4048", 0.22),
            (2000, 700, 460, 360, "#167068", 0.16),
        ],
    ),
}


def generate_all(assets: Path, preview: Path | None = None) -> None:
    assets.mkdir(parents=True, exist_ok=True)
    if preview is not None:
        preview.mkdir(parents=True, exist_ok=True)

    for name, cfg in THEMES.items():
        print(f"writing {name} ...", flush=True)
        blooms = cfg["blooms"]
        im = make_wallpaper(
            cfg["base_hex"],
            blooms,
            grain_fine=cfg.get("grain_fine", 0.008),
            grain_lf=cfg.get("grain_lf", 0.012),
            vignette_strength=cfg.get("vignette_strength", 0.52),
            seed=cfg.get("seed", 0),
        )
        out = assets / name
        # JPEG, not PNG. These are smooth gradients plus film grain: the grain
        # defeats PNG's predictor, so PNG lands at ~4.2MB each while q92 4:4:4
        # JPEG is ~300KB at 44.6dB PSNR — visually identical as a backdrop, and
        # the difference is 21MB vs 1.5MB of git history.
        im.save(
            out,
            format="JPEG",
            quality=JPEG_QUALITY,
            subsampling=0,  # 4:4:4 — no chroma loss on saturated accent blooms
            optimize=True,
            progressive=True,
        )
        if preview is not None:
            im.resize((640, 360), Image.Resampling.LANCZOS).save(
                preview / name, format="JPEG", quality=92
            )

    stale = (
        "wallpaper-dusk.png",
        "wallpaper-tide.png",
        "wallpaper-violet.png",
        # Superseded by the JPEG variants above.
        "wallpaper.png",
        "wallpaper-harbor.png",
        "wallpaper-ember.png",
        "wallpaper-signal.png",
        "wallpaper-reef.png",
    )
    for old in stale:
        p = assets / old
        if p.exists():
            p.unlink()
            print(f"removed {old}")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--assets",
        type=Path,
        default=DEFAULT_ASSETS,
        help="Output directory for wallpapers",
    )
    ap.add_argument(
        "--preview",
        type=Path,
        default=DEFAULT_PREVIEW,
        help="Optional JPEG preview directory (640x360). Empty string to skip.",
    )
    ap.add_argument("--no-preview", action="store_true")
    args = ap.parse_args()
    preview = None if args.no_preview else args.preview
    generate_all(args.assets, preview)
    print("done")


if __name__ == "__main__":
    main()
