"""Builds the eriador_west heightmap, splat maps and hillshade previews (M1-T03, data side).

  .venv/bin/python tools/terrain/build_heightmap.py [--res 1] [--seed N] [--no-previews]

Outputs (build/terrain/, git-ignored): eriador_west_height.r16 (raw little-endian uint16, 8192x4096,
height = v/65535*(height_max-height_min)+height_min), eriador_west_height.png (16-bit preview),
eriador_west_splat_a.png (R grass, G path/dirt, B field, A riverbank), eriador_west_splat_b.png
(R forest floor, G rock, B/A unused), plus previews in docs/reports/m1_terrain/.
"""
from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi

sys.path.insert(0, str(Path(__file__).parent))
import heightfield as hf  # noqa: E402

REPORT = hf.ROOT / "docs/reports/m1_terrain"
LAYERS_A = ("grass", "path", "field", "riverbank")
LAYERS_B = ("forest_floor", "rock")
COLOURS = {"grass": (0.45, 0.65, 0.30), "path": (0.70, 0.55, 0.35), "field": (0.80, 0.75, 0.40),
           "riverbank": (0.35, 0.50, 0.65), "forest_floor": (0.15, 0.35, 0.18), "rock": (0.5, 0.5, 0.5)}


def _window(cx: float, cz: float, r: float, res: float, shape: tuple[int, int]) -> tuple[slice, slice]:
    H, W = shape
    return (slice(max(0, int((cz - r) / res)), min(H, int((cz + r) / res) + 1)),
            slice(max(0, int((cx - r) / res)), min(W, int((cx + r) / res) + 1)))


def build_splats(fld: hf.HeightField, region: dict) -> tuple[np.ndarray, np.ndarray]:
    """Returns (A, B) uint8 HxWx4 arrays. Weights sum to 255 across all layers per pixel."""
    cfg, res = fld.cfg["splat"], fld.res
    H, W = fld.shape
    ft = fld.features
    rng = np.random.default_rng(fld.cfg["seed"] + 1)
    rc = fld.cfg["roads"]

    path = np.zeros(H * W, np.float32)
    hwid = np.array([0, rc["half_width_m"]["path"], rc["half_width_m"]["road"]], np.float32)[ft.road_code]
    path[ft.road_idx] = 1.0 - hf._ss((ft.road_d - hwid) / cfg["path_edge_m"])
    path = path.reshape(H, W)

    bank = np.zeros(H * W, np.float32)
    bank[ft.river_idx] = 1.0 - hf._ss((ft.river_d - ft.river_hw * 0.7) / (ft.river_hw * 0.3 + cfg["riverbank_m"]))
    bank = bank.reshape(H, W)

    img = Image.new("L", (W, H), 0)
    dr = ImageDraw.Draw(img)
    for f in region["forests"]:
        dr.polygon([(p[0] / res, p[1] / res) for p in f["polygon"]], fill=255)
    forest = ndi.gaussian_filter(np.asarray(img, np.float32) / 255.0, cfg["forest_feather_m"] / res / 2)
    forest = np.clip(forest * 1.6 - 0.3, 0, 1)

    # fields: patchy ring around settlements (outside the buildings) and discs around farms
    xs = (np.arange(W, dtype=np.float32) * res)[None, :]
    zs = (np.arange(H, dtype=np.float32) * res)[:, None]
    ring = np.zeros((H, W), np.float32)
    a, b = cfg["field_ring"]
    for s in region["settlements"]:
        cx, cz = s["center"]
        sz, sx = _window(cx, cz, s["radius"] * 1.6, res, (H, W))
        d = np.sqrt((xs[:, sx] - cx) ** 2 + (zs[sz] - cz) ** 2) / s["radius"]
        v = hf._ss((d - a) / 0.15) * (1 - hf._ss((d - b) / 0.3))
        ring[sz, sx] = np.maximum(ring[sz, sx], v)
    r = cfg["field_farm_radius_m"]
    for p in region["pois"]:
        if p["kind"] in ("farm", "field"):
            cx, cz = p["pos"][0], p["pos"][2]
            sz, sx = _window(cx, cz, r, res, (H, W))
            d = np.sqrt((xs[:, sx] - cx) ** 2 + (zs[sz] - cz) ** 2) / r
            ring[sz, sx] = np.maximum(ring[sz, sx], 1 - hf._ss((d - 0.6) / 0.4))
    patch = hf.fft_noise((H, W), rng, tuple(cfg["field_noise_wavelength_m"]), res)
    field = ring * hf._ss(patch * 2.5 + 0.2)
    del ring, patch

    gy, gx = np.gradient(fld.h, res)
    slope = np.hypot(gx, gy)
    lo, hi = cfg["rock_slope"]
    rock = hf._ss((slope - lo) / (hi - lo))
    del gx, gy, slope

    # priority stacking: each layer takes what is left, so weights always sum to 1
    remaining = np.ones((H, W), np.float32)
    w = {}
    for name, m in (("path", path), ("riverbank", bank), ("rock", rock), ("forest_floor", forest), ("field", field)):
        w[name] = m * remaining
        remaining -= w[name]
    w["grass"] = remaining
    q = {k: np.round(np.clip(v, 0, 1) * 255).astype(np.int16) for k, v in w.items()}
    q["grass"] = 255 - sum(q[k] for k in q if k != "grass")  # absorb rounding error
    sa = np.stack([q[k] for k in LAYERS_A], -1).astype(np.uint8)
    sb = np.zeros((H, W, 4), np.uint8)
    sb[..., 0], sb[..., 1] = q["forest_floor"], q["rock"]
    return sa, sb


def hillshade(h: np.ndarray, res: float, step: int, vexag: float) -> np.ndarray:
    H, W = h.shape[0] // step * step, h.shape[1] // step * step
    s = h[:H, :W].reshape(H // step, step, W // step, step).mean(axis=(1, 3))
    gy, gx = np.gradient(s * vexag, res * step)
    az, alt = np.radians(315), np.radians(40)  # light from the NW
    slope, aspect = np.arctan(np.hypot(gx, gy)), np.arctan2(gy, -gx)
    hs = np.sin(alt) * np.cos(slope) + np.cos(alt) * np.sin(slope) * np.cos(az - aspect)
    return np.clip(hs, 0, 1)


def _tint(sa: np.ndarray, sb: np.ndarray, shade: np.ndarray) -> np.ndarray:
    sa, sb = sa.astype(np.float32) / 255, sb.astype(np.float32) / 255
    w = [sa[..., 0], sa[..., 1], sa[..., 2], sa[..., 3], sb[..., 0], sb[..., 1]]
    col = sum(wi[..., None] * np.array(COLOURS[n], np.float32) for wi, n in zip(w, COLOURS))
    return (np.clip(col * (0.35 + 0.9 * shade[..., None]), 0, 1) * 255).astype(np.uint8)


def previews(fld: hf.HeightField, sa: np.ndarray, sb: np.ndarray) -> None:
    REPORT.mkdir(parents=True, exist_ok=True)
    step = fld.cfg["preview"]["hillshade_step"]
    vex = fld.cfg["preview"]["vertical_exaggeration"]
    hs = hillshade(fld.h, fld.res, step, vex)
    n0, n1 = hs.shape
    Image.fromarray((hs * 255).astype(np.uint8)).save(REPORT / "hillshade.png")
    Image.fromarray(_tint(sa[::step, ::step][:n0, :n1], sb[::step, ::step][:n0, :n1], hs)).save(REPORT / "hillshade_splat.png")
    # full-res crops (hillshade + splat), 800x500 m, upscaled 2x
    full = hillshade(fld.h, fld.res, 1, vex)
    crops = {"brandywine_bridge": (5380, 2320), "hobbiton": (950, 2150), "bree": (7420, 2300), "stock_ferry": (5100, 2760)}
    for name, (cx, cz) in crops.items():
        x0 = int(np.clip(cx / fld.res - 400, 0, full.shape[1] - 800))
        z0 = int(np.clip(cz / fld.res - 250, 0, full.shape[0] - 500))
        sl = (slice(z0, z0 + 500), slice(x0, x0 + 800))
        Image.fromarray(_tint(sa[sl], sb[sl], full[sl])).resize((1600, 1000), Image.NEAREST).save(REPORT / f"crop_{name}.png")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--res", type=float, default=1.0, help="metres per pixel (1 = final)")
    ap.add_argument("--seed", type=int, default=None)
    ap.add_argument("--no-previews", action="store_true")
    ap.add_argument("--out", type=Path, default=hf.BUILD)
    args = ap.parse_args()
    t0 = time.time()
    region = hf.load_region()
    fld = hf.build(region, seed=args.seed, res=args.res)
    t1 = time.time()
    print(f"heights {fld.shape[1]}x{fld.shape[0]} in {t1 - t0:.1f}s, min {fld.h.min():.1f} max {fld.h.max():.1f} m")
    args.out.mkdir(parents=True, exist_ok=True)
    r16 = fld.to_r16()
    r16.tofile(args.out / "eriador_west_height.r16")
    Image.fromarray(r16.astype(np.uint16)).save(args.out / "eriador_west_height.png")
    sa, sb = build_splats(fld, region)
    Image.fromarray(sa, "RGBA").save(args.out / "eriador_west_splat_a.png", compress_level=3)
    Image.fromarray(sb, "RGBA").save(args.out / "eriador_west_splat_b.png", compress_level=3)
    print(f"splats in {time.time() - t1:.1f}s")
    if not args.no_previews:
        previews(fld, sa, sb)
    for f in sorted(args.out.glob("eriador_west_*")):
        print(f"  {f.relative_to(hf.ROOT)}  {f.stat().st_size / 1e6:.1f} MB")
    print(f"total {time.time() - t0:.1f}s")
    return 0


if __name__ == "__main__":
    sys.exit(main())
