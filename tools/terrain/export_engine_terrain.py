"""Downsamples the build/terrain data into the small copy the game loads (M1-T03, engine side).

Regenerate (after build_heightmap.py, ~85 s):
    .venv/bin/python tools/terrain/build_heightmap.py && .venv/bin/python tools/terrain/export_engine_terrain.py

Outputs in game/assets/terrain/eriador_west/ (Git LFS):
  height_4m.r16  raw little-endian uint16, 2048x1024, row 0 = north edge (z = 0), height_m = v / 65535 * 320.
                 Sample i sits at x = i * 4 m (same vertex convention as the 1 m source), so it is a plain decimation.
  splat_4m.png   RGBA8, 2048x1024: R = path/dirt, G = riverbank, B = forest floor, A = field. Grass is the remainder
                 (255 - R - G - B - A). Rock is derived from slope in the shader, so it is not stored.
Engine world coordinates equal region coordinates: x east, z SOUTH (see docs/REVIEW.md, M1-T03).
"""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "build/terrain"
DST = ROOT / "game/assets/terrain/eriador_west"
FACTOR = 4
SRC_SIZE = (4096, 8192)  # rows, cols at 1 m


def main() -> int:
    DST.mkdir(parents=True, exist_ok=True)
    h = np.fromfile(SRC / "eriador_west_height.r16", dtype="<u2").reshape(SRC_SIZE)
    h_small = np.ascontiguousarray(h[::FACTOR, ::FACTOR])
    h_small.astype("<u2").tofile(DST / "height_4m.r16")

    sa = np.asarray(Image.open(SRC / "eriador_west_splat_a.png").convert("RGBA"), np.float32)
    sb = np.asarray(Image.open(SRC / "eriador_west_splat_b.png").convert("RGBA"), np.float32)
    rows, cols = SRC_SIZE[0] // FACTOR, SRC_SIZE[1] // FACTOR

    def block_mean(a: np.ndarray) -> np.ndarray:
        return a.reshape(rows, FACTOR, cols, FACTOR).mean(axis=(1, 3))

    path, field, bank = block_mean(sa[..., 1]), block_mean(sa[..., 2]), block_mean(sa[..., 3])
    forest = block_mean(sb[..., 0])
    out = np.stack([path, bank, forest, field], -1)
    Image.fromarray(np.clip(np.round(out), 0, 255).astype(np.uint8), "RGBA").save(DST / "splat_4m.png", optimize=True)
    meta = {"size_px": [cols, rows], "metres_per_px": FACTOR, "height_max_m": json.loads((ROOT / "game/config/terrain.json").read_text())["height_max_m"]}
    print("wrote", DST, meta)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
