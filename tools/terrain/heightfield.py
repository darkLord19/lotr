"""Procedural terrain for eriador_west (M1-T03): the single source of ground height.

Coordinates are region metres as in the region JSON: x east, z SOUTH (z=0 is the north edge).
Raster row = z/res, column = x/res; vertex convention (pixel i sits at x = i*res).
"""
from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import fft as sfft
from scipy import ndimage as ndi

ROOT = Path(__file__).resolve().parents[2]
REGION = ROOT / "game/content/regions/eriador_west.json"
CONFIG = ROOT / "game/config/terrain.json"
BUILD = ROOT / "build/terrain"
R16 = BUILD / "eriador_west_height.r16"


def load_config(path: Path = CONFIG) -> dict:
    return json.loads(path.read_text())


def load_region(path: Path = REGION) -> dict:
    return json.loads(path.read_text())


def _ss(t: np.ndarray) -> np.ndarray:
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def fft_noise(shape: tuple[int, int], rng: np.random.Generator, wl: tuple[float, float], res: float) -> np.ndarray:
    """Band-limited ~1/f noise, unit std, vectorised (periodic, so it is seamless)."""
    f = sfft.rfft2(rng.standard_normal(shape, dtype=np.float32), workers=-1)
    fy = sfft.fftfreq(shape[0], d=res).astype(np.float32)[:, None]
    fx = sfft.rfftfreq(shape[1], d=res).astype(np.float32)[None, :]
    r = np.sqrt(fx * fx + fy * fy)
    r[0, 0] = 1.0
    lo, hi = 1.0 / wl[1], 1.0 / wl[0]
    filt = (1.0 / r) * np.exp(-((r / hi) ** 2)) * (1.0 - np.exp(-((r / lo) ** 2)))
    filt[0, 0] = 0.0
    out = sfft.irfft2(f * filt.astype(np.float32), s=shape, workers=-1)
    return (out / out.std()).astype(np.float32)


def _raster_lines(items: list[tuple[list[list[float]], int]], shape: tuple[int, int], res: float) -> np.ndarray:
    img = Image.new("L", (shape[1], shape[0]), 0)
    d = ImageDraw.Draw(img)
    for pts, code in items:
        d.line([(p[0] / res, p[1] / res) for p in pts], fill=code, width=1)
    return np.asarray(img)


@dataclass
class Features:
    """Sparse per-pixel info near roads/rivers (flat indices), reused by the splat pass."""
    road_idx: np.ndarray = field(default_factory=lambda: np.empty(0, np.int64))
    road_d: np.ndarray = field(default_factory=lambda: np.empty(0, np.float32))
    road_code: np.ndarray = field(default_factory=lambda: np.empty(0, np.uint8))
    river_idx: np.ndarray = field(default_factory=lambda: np.empty(0, np.int64))
    river_d: np.ndarray = field(default_factory=lambda: np.empty(0, np.float32))
    river_hw: np.ndarray = field(default_factory=lambda: np.empty(0, np.float32))


class HeightField:
    def __init__(self, heights: np.ndarray, res: float, cfg: dict, features: Features | None = None):
        self.h = heights
        self.res = res
        self.cfg = cfg
        self.features = features

    @property
    def shape(self) -> tuple[int, int]:
        return self.h.shape

    def height_at(self, x, z):
        """Bilinear ground height in metres at region (x, z); accepts scalars or arrays."""
        x = np.asarray(x, dtype=np.float64) / self.res
        z = np.asarray(z, dtype=np.float64) / self.res
        H, W = self.h.shape
        x = np.clip(x, 0, W - 1.000001)
        z = np.clip(z, 0, H - 1.000001)
        x0, z0 = x.astype(int), z.astype(int)
        fx, fz = x - x0, z - z0
        h = self.h
        v = (h[z0, x0] * (1 - fx) * (1 - fz) + h[z0, x0 + 1] * fx * (1 - fz)
             + h[z0 + 1, x0] * (1 - fx) * fz + h[z0 + 1, x0 + 1] * fx * fz)
        return float(v) if v.ndim == 0 else v

    def to_r16(self) -> np.ndarray:
        lo, hi = self.cfg["height_min_m"], self.cfg["height_max_m"]
        return np.round((self.h - lo) / (hi - lo) * 65535.0).clip(0, 65535).astype("<u2")


def from_r16(path: Path = R16, cfg: dict | None = None, region: dict | None = None, res: float = 1.0) -> HeightField:
    cfg = cfg or load_config()
    region = region or load_region()
    W, H = int(region["size_m"][0] / res), int(region["size_m"][1] / res)
    raw = np.fromfile(path, dtype="<u2").reshape(H, W)
    lo, hi = cfg["height_min_m"], cfg["height_max_m"]
    return HeightField(raw.astype(np.float32) / 65535.0 * (hi - lo) + lo, res, cfg)


_cache: HeightField | None = None


def default_field() -> HeightField:
    """Generated R16 if present (1 m/px), else rebuild procedurally (slow, ~1 min)."""
    global _cache
    if _cache is None:
        _cache = from_r16() if R16.exists() else build()
    return _cache


def height_at(x, z):
    """Module-level convenience for place_world.py and POI/NPC ground snapping."""
    return default_field().height_at(x, z)


def build(region: dict | None = None, cfg: dict | None = None, seed: int | None = None, res: float = 1.0) -> HeightField:
    region = region or load_region()
    cfg = cfg or load_config()
    seed = cfg["seed"] if seed is None else seed
    rng = np.random.default_rng(seed)
    W, H = int(region["size_m"][0] / res), int(region["size_m"][1] / res)
    shape = (H, W)
    xs = (np.arange(W, dtype=np.float32) * res)[None, :]
    zs = (np.arange(H, dtype=np.float32) * res)[:, None]
    feat = Features()

    # --- rivers: distance field first, because valleys suppress hills and noise ---
    rivers = region.get("rivers", [])
    rcode = _raster_lines([(r["points"], i + 1) for i, r in enumerate(sorted(rivers, key=lambda r: r["width"]))], shape, res)
    rsorted = sorted(rivers, key=lambda r: r["width"])
    rhw = np.array([0.0] + [r["width"] / 2 for r in rsorted], np.float32)
    rd, ridx = ndi.distance_transform_edt(rcode == 0, sampling=res, return_indices=True)
    rd = rd.astype(np.float32)
    hc = cfg["hills"]
    valley = _ss((rd - hc["river_valley_inner_m"]) / (hc["river_valley_outer_m"] - hc["river_valley_inner_m"]))

    # --- base rolling noise, stronger toward the Barrow-downs ---
    barrows = [h for h in region["hills"] if h.get("enterable") is False]
    nc = cfg["noise"]
    prox = np.zeros(shape, np.float32)
    rise = np.zeros(shape, np.float32)
    for b in barrows:
        d2 = (xs - b["center"][0]) ** 2 + (zs - b["center"][1]) ** 2
        prox = np.maximum(prox, np.exp(-d2 / nc["barrow_sigma_m"] ** 2))
        rise = np.maximum(rise, np.exp(-d2 / cfg["rise"]["barrow_sigma_m"] ** 2))
        del d2
    amp_scale = (1.0 + nc["barrow_amp_gain"] * prox) * (hc["valley_noise_floor"] + (1 - hc["valley_noise_floor"]) * valley)
    h = np.full(shape, cfg["base_level_m"], np.float32)
    h += cfg["rise"]["barrow_rise_m"] * rise
    h += nc["large_amp_m"] * amp_scale * fft_noise(shape, rng, tuple(nc["large_wavelength_m"]), res)
    h += nc["small_amp_m"] * amp_scale * fft_noise(shape, rng, tuple(nc["small_wavelength_m"]), res)
    del prox, rise, amp_scale

    # --- hills as smooth cosine bumps (bbox-local, valley-suppressed) ---
    def window(cx: float, cz: float, r: float):
        x0, x1 = max(0, int((cx - r) / res)), min(W, int((cx + r) / res) + 2)
        z0, z1 = max(0, int((cz - r) / res)), min(H, int((cz + r) / res) + 2)
        return slice(z0, z1), slice(x0, x1)

    for hl in region["hills"]:
        cx, cz = hl["center"]
        r = hl["radius"]
        sz, sx = window(cx, cz, r)
        d = np.sqrt((xs[:, sx] - cx) ** 2 + (zs[sz] - cz) ** 2)
        bump = np.where(d < r, 0.5 + 0.5 * np.cos(np.pi * np.clip(d / r, 0, 1)), 0.0)
        h[sz, sx] += hl["height"] * bump.astype(np.float32) * valley[sz, sx]

    # --- border ridges hide the world's end ---
    ec = cfg["edge_ridge"]
    tx = _ss(1 - np.minimum(xs, (W - 1) * res - xs) / ec["width_m"])
    tz = _ss(1 - np.minimum(zs, (H - 1) * res - zs) / ec["width_m"])
    ridge = tx + tz - tx * tz
    ridge_noise = np.clip(1.0 + ec["noise_gain"] * fft_noise(shape, rng, (150.0, 900.0), res), 0.5, 1.6)
    h += ec["height_m"] * ridge * ridge_noise * (ridge > 0)
    del tx, tz, ridge, ridge_noise

    # --- flat bench per settlement ---
    bc = cfg["bench"]
    for s in region["settlements"]:
        ov = {**{k: bc[k] for k in ("core_frac", "blend_frac")}, **bc.get("overrides", {}).get(s["id"], {})}
        cx, cz = s["center"]
        r = s["radius"]
        core, blend = r * ov["core_frac"], r * ov["blend_frac"]
        sz, sx = window(cx, cz, blend)
        d = np.sqrt((xs[:, sx] - cx) ** 2 + (zs[sz] - cz) ** 2)
        level = float(h[sz, sx][d <= core].mean())
        w = 1.0 - _ss((d - core) / (blend - core))
        h[sz, sx] += w * (level - h[sz, sx])

    # --- roads: flattened to the smoothed centerline height, slightly sunken ---
    rc = cfg["roads"]
    kinds = {"path": 1, "road": 2}  # roads drawn last so they win at junctions
    road_items = sorted(((r["points"], kinds[r["kind"]]) for r in region["roads"] if r["kind"] in kinds), key=lambda t: t[1])
    if road_items:
        code = _raster_lines(road_items, shape, res)
        hw = np.array([0, rc["half_width_m"]["path"], rc["half_width_m"]["road"]], np.float32)
        sh = np.array([0, rc["shoulder_m"]["path"], rc["shoulder_m"]["road"]], np.float32)
        sink = np.array([0, rc["sink_m"]["path"], rc["sink_m"]["road"]], np.float32)
        d, idx = ndi.distance_transform_edt(code == 0, sampling=res, return_indices=True)
        lim = float((hw + sh).max())
        sel = np.flatnonzero(d.ravel() < lim)
        iz, ix = idx[0].ravel()[sel], idx[1].ravel()[sel]
        del idx
        blur = _blur(h, rc["smooth_sigma_m"], res)
        k = code[iz, ix]
        dd = d.ravel()[sel].astype(np.float32)
        target = blur[iz, ix] - sink[k]
        w = 1.0 - _ss((dd - hw[k]) / sh[k])
        hf = h.ravel()
        hf[sel] += w * (target - hf[sel])
        feat.road_idx, feat.road_d, feat.road_code = sel, dd, k
        del d, blur, code

    # --- river channels carved last, so they win under bridges ---
    rv = cfg["rivers"]
    lim = float(rhw.max()) + rv["bank_m"] + rv["bank_per_width"] * float(rhw.max()) * 2
    sel = np.flatnonzero(rd.ravel() < lim)
    iz, ix = ridx[0].ravel()[sel], ridx[1].ravel()[sel]
    del ridx
    k = rcode[iz, ix]
    hwk = rhw[k]
    dd = rd.ravel()[sel]
    ref = _blur(h, rv["smooth_sigma_m"], res)[iz, ix]
    depth = np.clip(rv["depth_per_width"] * hwk * 2, rv["depth_min_m"], rv["depth_max_m"])
    inside = np.clip(dd / hwk, 0, 1)
    prof = ref - depth * (1 - inside**2)
    bank = rv["bank_m"] + rv["bank_per_width"] * hwk * 2
    w = 1.0 - _ss((dd - hwk) / bank)
    hf = h.ravel()
    hf[sel] += w * (prof - hf[sel])
    feat.river_idx, feat.river_d, feat.river_hw = sel, dd.astype(np.float32), hwk.astype(np.float32)

    np.clip(h, cfg["height_min_m"], cfg["height_max_m"], out=h)
    return HeightField(h, res, cfg, feat)


def _blur(h: np.ndarray, sigma_m: float, res: float) -> np.ndarray:
    """Gaussian blur computed at ~sigma/4 resolution, then bilinearly upsampled."""
    f = max(1, int(sigma_m / res / 4))
    small = h[: h.shape[0] // f * f, : h.shape[1] // f * f].reshape(h.shape[0] // f, f, h.shape[1] // f, f).mean(axis=(1, 3))
    small = ndi.gaussian_filter(small, sigma_m / res / f, mode="nearest")
    full = ndi.zoom(small, f, order=3, mode="nearest", grid_mode=True)
    out = np.empty(h.shape, np.float32)
    hh, ww = min(h.shape[0], full.shape[0]), min(h.shape[1], full.shape[1])
    out[:] = full[-1, -1]
    out[:hh, :ww] = full[:hh, :ww]
    return out
