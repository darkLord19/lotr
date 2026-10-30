#!/usr/bin/env python3
"""World population for eriador_west (M1-T06): emits game/content/regions/eriador_west_placements.json.

Run from the repo root:  .venv/bin/python tools/terrain/place_world.py [--out FILE] [--stats]

Everything is deterministic: one master seed, and every feature draws from its own RNG stream (seed + crc32 of
the feature name), so adding a feature does not reshuffle the others. Positions are region metres (x east,
z SOUTH, same as the engine) and are snapped to the *engine* terrain (the 4 m decimation the game loads), through
heightfield.HeightField, so what Python places stands on exactly what Godot's TerrainHeights returns.

Output layout (compact on purpose, ~1-2 MB):
  models        [{id, kind, lods, collide}]   id = "<category>/<name>", files game/assets/models/<id>[_lod1|_lod2].glb
  foliage       [[model_idx, x, y, z, yaw, scale], ...]   MultiMesh candidates: trees, bushes, hedges, fences, fields
  objects       [{id, model, kind, pos, yaw, scale:[x,y,z], ...}]   scene instances: buildings, props, bridges, gates
  barriers      [{id, height_m, segs: [[x1, z1, x2, z2], ...]}]       invisible collision walls (Old Forest)
  pois          [{id, name, kind, pos}]                               region POIs with ground height
  forage        [{id, item, pos, yield, zone?}]                       player/foraging.gd node format
  interactables [{id, kind, label, pos, payload, poi?}]               kinds match player/interactable.gd
"""
from __future__ import annotations

import argparse
import json
import math
import sys
import zlib
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy.spatial import cKDTree

sys.path.insert(0, str(Path(__file__).parent))
import heightfield as hfm  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
ENGINE_HEIGHTS = ROOT / "game/assets/terrain/eriador_west/height_4m.r16"
MODEL_DIR = ROOT / "game/assets/models"
OUT = ROOT / "game/content/regions/eriador_west_placements.json"

SEED = 3018
CELL_M = 256.0
MASK_RES = 2.0          # occupancy raster resolution (m)
ROAD_HW = {"road": 4.0, "path": 2.0, "ferry": 2.0}
TREE_ROAD_CLEAR = 3.0   # trees stay this far from the road *edge*
TREE_RIVER_CLEAR = 4.0
BUILDING_ROAD_GAP = 3.5
BUILDING_RIVER_CLEAR = 10.0
HOLE_SLOPE_TOL = 3.0    # hobbit-holes are dug into slopes
HOUSE_SLOPE_TOL = 1.1
BIG_SLOPE_TOL = 1.6

# Which model name prefixes get collision (trunk / hull shapes from the glb col nodes).
COLLIDE_PREFIXES = ("tree_", "rock_", "log_", "hedge_", "fence_", "gate_", "bree_dike", "bree_hedge")
SINK = {"tree_": 0.12, "bush_": 0.05}

FOREST_SPACING_M = 11.0     # Poisson radius at density 1.0; actual = this / sqrt(density)
OPEN_TREE_SPACING_M = 58.0
UNDERSTORY_SPACING_M = 17.0
GROUND_COVER_SPACING_M = 15.0
WALL_SPACING_M = 3.0

FOREST_MIX = {
    "woody_end": [("oak", 45), ("beech", 35), ("birch", 20)],
    "old_forest": [("oak", 40), ("beech", 30), ("willow", 20), ("pine", 10)],
    "chetwood": [("pine", 50), ("birch", 30), ("beech", 20)],
    "buckland_woods": [("beech", 50), ("oak", 40), ("birch", 10)],
}
FOREST_SCALE = {"old_forest": (1.1, 1.6)}

# Settlement recipes. mix = (model, weight); R = candidate radius; count = generic buildings (anchored ones extra).
HOLES = [("shire/hobbit_hole_1", 1), ("shire/hobbit_hole_2", 1), ("shire/hobbit_hole_3", 1), ("shire/hobbit_hole_4", 1)]
COTTAGES = [("shire/hobbit_cottage_1", 1), ("shire/hobbit_cottage_2", 1), ("shire/hobbit_cottage_3", 1)]
BREE_HOUSES = [("bree/bree_house_stone_1", 2), ("bree/bree_house_stone_2", 2), ("bree/bree_house_timber_1", 2),
               ("bree/bree_house_timber_2", 2), ("bree/bree_house_hobbit_1", 1), ("bree/bree_house_hobbit_2", 1)]
RECIPES: dict[str, dict] = {
    "hobbiton": dict(R=270, count=15, spacing=26, mix=[(m, 1.0) for m, _ in HOLES[:3]] + [(m, 1.6) for m, _ in COTTAGES], style="shire"),
    "bywater": dict(R=190, count=13, spacing=22, mix=[(HOLES[0][0], 0.5), (HOLES[3][0], 0.5)] + [(m, 2.0) for m, _ in COTTAGES], style="shire"),
    "frogmorton": dict(R=190, count=9, spacing=22, mix=[(m, 1.0) for m, _ in COTTAGES], style="shire"),
    "marish": dict(R=380, count=6, spacing=60, mix=[(m, 1.0) for m, _ in COTTAGES], style="shire"),
    "stock": dict(R=190, count=11, spacing=22, mix=[(HOLES[1][0], 0.5)] + [(m, 2.0) for m, _ in COTTAGES], style="shire"),
    "buckland": dict(R=420, count=17, spacing=30, mix=[(m, 1.2) for m, _ in HOLES[1:]] + [(m, 1.0) for m, _ in COTTAGES], style="shire"),
    "bree": dict(R=250, count=24, spacing=19, mix=BREE_HOUSES, style="bree"),
    "staddle": dict(R=120, count=8, spacing=19, mix=BREE_HOUSES[2:], style="bree"),
    "combe": dict(R=120, count=9, spacing=19, mix=BREE_HOUSES[2:], style="bree"),
}
INN_MODELS = {"green_dragon": "shire/inn_green_dragon", "floating_log": "shire/inn_green_dragon",
              "golden_perch": "shire/inn_golden_perch", "prancing_pony": "bree/prancing_pony"}
BEDS = {"bag_end": ("your bed at Bag End", "bed"), "crickhollow": ("a bed at Crickhollow", "bed"),
        "brandy_hall": ("a guest bed at Brandy Hall", "bed"), "green_dragon": ("a room at the Green Dragon", "inn"),
        "floating_log": ("a room at the Floating Log", "inn"), "golden_perch": ("a room at the Golden Perch", "inn"),
        "prancing_pony": ("a room at the Prancing Pony", "inn")}
INN_FOOD = [("ale_mug", "a mug of ale"), ("bread_loaf", "a loaf of bread"), ("farm_cheese", "a wedge of cheese")]
DOOR_LABELS = {"bag_end": "the round green door of Bag End", "prancing_pony": "the door of the Prancing Pony",
               "green_dragon": "the door of the Green Dragon", "floating_log": "the door of the Floating Log",
               "golden_perch": "the door of the Golden Perch", "brandy_hall": "the great door of Brandy Hall",
               "crickhollow": "the door of Crickhollow", "maggots_farm": "Farmer Maggot's door",
               "bamfurlong": "the farmhouse door", "bill_ferny_house": "Bill Ferny's door", "mill": "the mill door"}

PROP_CHOICES = ["props/barrel_1", "props/barrel_2", "props/crate", "props/sack_1", "props/sack_2", "props/hay_bale", "props/bench_1"]
FORAGE_ITEM_MODEL = {"mushrooms": "props/food_mushrooms", "apple": "props/food_apple_basket", "potatoes": "props/sack_1"}


def rng_for(name: str) -> np.random.Generator:
    return np.random.default_rng([SEED, zlib.crc32(name.encode())])


def r1(v: float) -> float:
    return round(float(v), 1)


# --- inputs ---------------------------------------------------------------------------------------------

def load_ground() -> hfm.HeightField:
    cfg = hfm.load_config()
    raw = np.fromfile(ENGINE_HEIGHTS, dtype="<u2").reshape(1024, 2048)
    lo, hi = cfg["height_min_m"], cfg["height_max_m"]
    return hfm.HeightField(raw.astype(np.float32) / 65535.0 * (hi - lo) + lo, 4.0, cfg)


class Models:
    """Asset manifests: footprints and LOD counts for every model id."""

    def __init__(self) -> None:
        self.info: dict[str, dict] = {}
        for cat in ("nature", "shire", "bree", "props"):
            for a in json.loads((MODEL_DIR / cat / "manifest.json").read_text())["assets"]:
                self.info[f"{cat}/{a['name']}"] = a

    def size(self, mid: str) -> tuple[float, float, float]:
        return tuple(self.info[mid]["size_m"])  # type: ignore[return-value]

    def lods(self, mid: str) -> int:
        return len(self.info[mid]["files"])

    def footprint(self, mid: str) -> tuple[float, float]:
        """Half extents (width along local x, depth along local z) of the ground footprint."""
        sx, sy, _ = self.size(mid)
        if "hobbit_hole" in mid:
            # sy includes the flagstone path in front; the dome itself is ~0.85 as deep as wide.
            return sx / 2 * 0.95, sx / 2 * 0.85 * 0.95
        return sx / 2, sy / 2

    def door_front(self, mid: str) -> float:
        """Distance from the model origin to its front door along the local +z axis."""
        if "hobbit_hole" in mid:
            return self.size(mid)[0] / 2 * 0.85 * 0.96
        return self.size(mid)[1] / 2


class Lines:
    """Densified polylines with per-sample half width, for nearest-edge distance queries."""

    def __init__(self, items: list[tuple[str, list[list[float]], float]], step: float = 2.0) -> None:
        pts, tans, hws, ids = [], [], [], []
        for lid, poly, hw in items:
            for a, b in zip(poly, poly[1:]):
                a_, b_ = np.array(a, float), np.array(b, float)
                length = float(np.linalg.norm(b_ - a_))
                if length < 1e-6:
                    continue
                t = (b_ - a_) / length
                n = max(1, int(math.ceil(length / step)))
                for i in range(n):
                    pts.append(a_ + t * (length * i / n))
                    tans.append(t)
                    hws.append(hw)
                    ids.append(lid)
            pts.append(np.array(poly[-1], float))
            tans.append(tans[-1])
            hws.append(hw)
            ids.append(lid)
        self.p = np.array(pts)
        self.t = np.array(tans)
        self.hw = np.array(hws)
        self.ids = ids
        self.tree = cKDTree(self.p)

    def edge_dist(self, x, z):
        d, i = self.tree.query(np.stack([np.asarray(x, float), np.asarray(z, float)], -1))
        return d - self.hw[i]

    def nearest(self, x: float, z: float) -> tuple[np.ndarray, np.ndarray, float, str]:
        d, i = self.tree.query([x, z])
        return self.p[i], self.t[i], float(d), self.ids[i]


class Mask:
    """Occupancy raster (2 m) for 'something stands here'. Drawn on a PIL image, read as numpy."""

    def __init__(self, size_m: tuple[float, float]) -> None:
        self.w, self.h = int(size_m[0] / MASK_RES), int(size_m[1] / MASK_RES)
        self.img = Image.new("L", (self.w, self.h), 0)
        self.draw = ImageDraw.Draw(self.img)
        self._arr: np.ndarray | None = None

    def _px(self, x: float, z: float) -> tuple[float, float]:
        return x / MASK_RES, z / MASK_RES

    def poly(self, pts: list[tuple[float, float]]) -> None:
        self.draw.polygon([self._px(*p) for p in pts], fill=255)
        self._arr = None

    def circle(self, x: float, z: float, r: float) -> None:
        a, b = self._px(x - r, z - r), self._px(x + r, z + r)
        self.draw.ellipse([a, b], fill=255)
        self._arr = None

    def line(self, pts: list[list[float]], width_m: float) -> None:
        self.draw.line([self._px(*p) for p in pts], fill=255, width=max(1, int(round(width_m / MASK_RES))))
        self._arr = None

    @property
    def arr(self) -> np.ndarray:
        if self._arr is None:
            self._arr = np.asarray(self.img) > 0
        return self._arr

    def blocked(self, x, z):
        if isinstance(x, (int, float)):   # scalar fast path: np.clip on scalars dominates Poisson sampling otherwise
            ix = min(self.w - 1, max(0, int(x / MASK_RES)))
            iz = min(self.h - 1, max(0, int(z / MASK_RES)))
            return bool(self.arr[iz, ix])
        ix = np.clip((np.asarray(x) / MASK_RES).astype(int), 0, self.w - 1)
        iz = np.clip((np.asarray(z) / MASK_RES).astype(int), 0, self.h - 1)
        return self.arr[iz, ix]


def in_polygon(x, z, poly: list[list[float]]):
    """Even-odd test, vectorised over x/z."""
    x, z = np.asarray(x, float), np.asarray(z, float)
    inside = np.zeros(x.shape, bool)
    n = len(poly)
    for i in range(n):
        x1, z1 = poly[i]
        x2, z2 = poly[(i + 1) % n]
        cond = (z1 > z) != (z2 > z)
        with np.errstate(divide="ignore", invalid="ignore"):
            xc = (x2 - x1) * (z - z1) / (z2 - z1) + x1
        inside ^= cond & (x < xc)
    return inside


def poisson(rng: np.random.Generator, bbox: tuple[float, float, float, float], r: float, accept, k: int = 16) -> list[tuple[float, float]]:
    """Bridson Poisson-disk sampling; `accept(x, z)` filters candidates *before* they take up space."""
    x0, z0, x1, z1 = bbox
    cs = r / math.sqrt(2)
    gw, gh = int(math.ceil((x1 - x0) / cs)) + 1, int(math.ceil((z1 - z0) / cs)) + 1
    grid = -np.ones((gh, gw), np.int32)
    pts: list[tuple[float, float]] = []
    active: list[int] = []

    def fits(x: float, z: float) -> bool:
        gx, gz = int((x - x0) / cs), int((z - z0) / cs)
        for j in range(max(0, gz - 2), min(gh, gz + 3)):
            for i in range(max(0, gx - 2), min(gw, gx + 3)):
                q = grid[j, i]
                if q >= 0 and (pts[q][0] - x) ** 2 + (pts[q][1] - z) ** 2 < r * r:
                    return False
        return True

    def add(x: float, z: float) -> None:
        grid[int((z - z0) / cs), int((x - x0) / cs)] = len(pts)
        active.append(len(pts))
        pts.append((x, z))

    for _ in range(200):  # seed points: the accepted region may be an odd shape
        sx, sz = rng.uniform(x0, x1), rng.uniform(z0, z1)
        if accept(sx, sz):
            add(sx, sz)
            break
    while active:
        ai = int(rng.integers(len(active)))
        bx, bz = pts[active[ai]]
        for _ in range(k):
            ang, rad = rng.uniform(0, math.tau), rng.uniform(r, 2 * r)
            x, z = bx + math.cos(ang) * rad, bz + math.sin(ang) * rad
            if x0 <= x < x1 and z0 <= z < z1 and accept(x, z) and fits(x, z):
                add(x, z)
                break
        else:
            active[ai] = active[-1]
            active.pop()
    return pts


# --- the builder ---------------------------------------------------------------------------------------

class World:
    def __init__(self) -> None:
        self.region = hfm.load_region()
        self.ground = load_ground()
        self.models = Models()
        size = tuple(self.region["size_m"])
        self.size = size
        self.pois = {p["id"]: p for p in self.region["pois"]}
        self.settlements = {s["id"]: s for s in self.region["settlements"]}
        self.forests = {f["id"]: f for f in self.region["forests"]}
        self.roads = Lines([(r["id"], r["points"], ROAD_HW[r["kind"]]) for r in self.region["roads"]])
        self.road_kind = {r["id"]: r["kind"] for r in self.region["roads"]}
        self.rivers = Lines([(r["id"], r["points"], r["width"] / 2.0) for r in self.region["rivers"]])
        self.struct = Mask(size)     # buildings + yards (dilated): nothing else may stand here
        # Static clearances rasterised once: scalar KD-tree queries per Poisson candidate would dominate the run time.
        self.tree_block = Mask(size)
        for r in self.region["roads"]:
            self.tree_block.line(r["points"], 2 * (ROAD_HW[r["kind"]] + TREE_ROAD_CLEAR))
        for r in self.region["rivers"]:
            self.tree_block.line(r["points"], r["width"] + 2 * TREE_RIVER_CLEAR)
        self.forest_mask: dict[str, Mask] = {}
        self.any_forest = Mask(size)
        for f in self.region["forests"]:
            m = Mask(size)
            m.poly([tuple(p) for p in f["polygon"]])
            self.forest_mask[f["id"]] = m
            self.any_forest.poly([tuple(p) for p in f["polygon"]])
        self.model_idx: dict[str, int] = {}
        self.model_list: list[dict] = []
        self.foliage: list[list[float]] = []     # [mi, x, z, yaw, scale] until heights are snapped
        self.objects: list[dict] = []
        self.buildings: list[dict] = []
        self.barriers: list[dict] = []
        self.forage: list[dict] = []
        self.interactables: list[dict] = []
        self._ids: dict[str, int] = {}
        self.noise = self._clump_noise()

    # -- small helpers --
    def h(self, x: float, z: float) -> float:
        return float(self.ground.height_at(x, z))

    def next_id(self, prefix: str) -> str:
        self._ids[prefix] = self._ids.get(prefix, 0) + 1
        return f"{prefix}_{self._ids[prefix]:03d}"

    def _clump_noise(self) -> np.ndarray:
        rng = rng_for("clump_noise")
        shape = (int(self.size[1] / 16), int(self.size[0] / 16))
        return hfm.fft_noise(shape, rng, (200.0, 1200.0), 16.0)

    def clump(self, x: float, z: float) -> float:
        iz = min(self.noise.shape[0] - 1, int(z / 16))
        ix = min(self.noise.shape[1] - 1, int(x / 16))
        return float(self.noise[iz, ix])

    def midx(self, mid: str) -> int:
        if mid not in self.model_idx:
            info = self.models.info[mid]
            name = mid.split("/", 1)[1]
            kind = info["kind"]
            if name.startswith(("hedge_", "bree_dike", "bree_hedge")):
                kind = "hedge"
            elif name.startswith(("fence_", "gate_")):
                kind = "fence"
            elif name.startswith("garden_plot"):
                kind = "field"
            self.model_idx[mid] = len(self.model_list)
            self.model_list.append({"id": mid, "kind": kind, "lods": self.models.lods(mid), "tris": info["tris"],
                                    "collide": name.startswith(COLLIDE_PREFIXES) and info.get("collision") is not None})
        return self.model_idx[mid]

    def add_foliage(self, mid: str, x: float, z: float, yaw: float, scale: float = 1.0) -> None:
        self.foliage.append([self.midx(mid), x, z, yaw, scale])

    def in_forest(self, x, z):
        return self.any_forest.blocked(x, z)

    def free_for_tree(self, x: float, z: float) -> bool:
        return not (self.struct.blocked(x, z) or self.tree_block.blocked(x, z))

    # -- footprints --
    @staticmethod
    def rect_corners(cx: float, cz: float, yaw: float, hx: float, hz: float, grow: float = 0.0):
        ax, az = math.cos(yaw), -math.sin(yaw)
        fx, fz = math.sin(yaw), math.cos(yaw)
        hx, hz = hx + grow, hz + grow
        return [(cx + ax * sx * hx + fx * sz * hz, cz + az * sx * hx + fz * sz * hz) for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1))]

    def footprint_samples(self, cx: float, cz: float, yaw: float, hx: float, hz: float, step: float = 2.0):
        ax, az = math.cos(yaw), -math.sin(yaw)
        fx, fz = math.sin(yaw), math.cos(yaw)
        nx, nz = max(2, int(2 * hx / step) + 1), max(2, int(2 * hz / step) + 1)
        pts = []
        for i in range(nx):
            for j in range(nz):
                u = -hx + 2 * hx * i / (nx - 1)
                v = -hz + 2 * hz * j / (nz - 1)
                pts.append((cx + ax * u + fx * v, cz + az * u + fz * v))
        return np.array(pts)

    def site_ok(self, cx: float, cz: float, yaw: float, hx: float, hz: float, slope_tol: float, gap: float = 3.0,
                allow_road: bool = False, settlement: dict | None = None) -> bool:
        samp = self.footprint_samples(cx, cz, yaw, hx + gap, hz + gap)
        if self.struct.blocked(samp[:, 0], samp[:, 1]).any():
            return False
        if self.in_forest(samp[:, 0], samp[:, 1]).any():
            return False
        inner = self.footprint_samples(cx, cz, yaw, hx, hz)
        if not allow_road and (self.roads.edge_dist(inner[:, 0], inner[:, 1]) < BUILDING_ROAD_GAP).any():
            return False
        if (self.rivers.edge_dist(samp[:, 0], samp[:, 1]) < BUILDING_RIVER_CLEAR).any():
            return False
        if samp[:, 0].min() < 60 or samp[:, 0].max() > self.size[0] - 60 or samp[:, 1].min() < 60 or samp[:, 1].max() > self.size[1] - 60:
            return False
        hs = self.ground.height_at(inner[:, 0], inner[:, 1])
        return float(hs.max() - hs.min()) <= slope_tol

    def claim(self, cx: float, cz: float, yaw: float, hx: float, hz: float, gap: float = 1.2) -> None:
        self.struct.poly(self.rect_corners(cx, cz, yaw, hx, hz, gap))

    # -- buildings --
    def place_building(self, bid: str, mid: str, cx: float, cz: float, yaw: float, settlement: str | None, poi: str | None = None,
                       scale: float = 1.0, role: str = "house", slope_tol: float | None = None, check: bool = True,
                       allow_road: bool = False) -> dict | None:
        hx, hz = self.models.footprint(mid)
        hx, hz = hx * scale, hz * scale
        is_hole = "hobbit_hole" in mid
        tol = slope_tol if slope_tol is not None else (HOLE_SLOPE_TOL if is_hole else (BIG_SLOPE_TOL if hx > 7 else HOUSE_SLOPE_TOL))
        if check and not self.site_ok(cx, cz, yaw, hx, hz, tol, allow_road=allow_road):
            return None
        inner = self.footprint_samples(cx, cz, yaw, hx, hz)
        hs = self.ground.height_at(inner[:, 0], inner[:, 1])
        # Stand on the low side: a buried corner reads as a foundation, a floating one as a bug.
        y = float(hs.min()) + 0.05 + (-0.15 if is_hole else 0.0)
        self.claim(cx, cz, yaw, hx, hz)
        door_d = self.models.door_front(mid) * scale
        fx, fz = math.sin(yaw), math.cos(yaw)
        b = {"id": bid, "model": mid, "kind": "building", "role": role, "pos": [r1(cx), round(y, 2), r1(cz)], "yaw": round(yaw, 3),
             "scale": [scale] * 3, "settlement": settlement, "hx": round(hx, 2), "hz": round(hz, 2),
             "door": [r1(cx + fx * (door_d + 0.9)), r1(cz + fz * (door_d + 0.9))], "slope_tol": tol}
        if poi:
            b["poi"] = poi
        self.objects.append(b)
        self.buildings.append(b)
        return b

    def beside_road(self, bid: str, mid: str, px: float, pz: float, settlement: str | None, poi: str | None, scale: float = 1.0,
                    role: str = "house", gap: float = 4.0) -> dict | None:
        """Building next to the road nearest (px, pz), front door facing the road; tries both sides and slides along it."""
        p0, t, _, rid = self.roads.nearest(px, pz)
        hx, hz = self.models.footprint(mid)
        hx, hz = hx * scale, hz * scale
        hw = ROAD_HW[self.road_kind[rid]]
        for slide in (0, 8, -8, 16, -16, 24, -24, 36, -36):
            for side in (1, -1):
                n = np.array([-t[1], t[0]]) * side
                c = p0 + t * slide + n * (hw + gap + hz)
                f = -n
                yaw = math.atan2(f[0], f[1])
                b = self.place_building(bid, mid, c[0], c[1], yaw, settlement, poi, scale, role)
                if b is not None:
                    return b
        return None

    def scatter_buildings(self, sid: str, rec: dict) -> int:
        s = self.settlements[sid]
        cx, cz = s["center"]
        rng = rng_for(f"buildings_{sid}")
        R = rec["R"]
        cands = poisson(rng, (cx - R, cz - R, cx + R, cz + R), rec["spacing"],
                        lambda x, z: (x - cx) ** 2 + (z - cz) ** 2 <= R * R)
        scored = []
        for x, z in cands:
            p0, t, d, rid = self.roads.nearest(x, z)
            edge = d - ROAD_HW[self.road_kind[rid]]
            near = 6.0 <= edge <= 38.0
            score = math.hypot(x - cx, z - cz) / R + (0.0 if near else 0.6) + rng.uniform(0, 0.35)
            scored.append((score, x, z, p0, d))
        scored.sort()
        mixm = [m for m, _ in rec["mix"]]
        mixw = np.array([w for _, w in rec["mix"]], float)
        mixw /= mixw.sum()
        placed = 0
        for _, x, z, p0, d in scored:
            if placed >= rec["count"]:
                break
            mid = mixm[int(rng.choice(len(mixm), p=mixw))]
            if d < 70:
                f = p0 - np.array([x, z])
            else:
                f = np.array([cx - x, cz - z])
            yaw = math.atan2(f[0], f[1])
            if self.place_building(self.next_id(f"{sid}_house"), mid, x, z, yaw, sid) is not None:
                placed += 1
        return placed

    # -- props --
    def place_prop(self, mid: str, x: float, z: float, yaw: float, owner: str | None = None, scale: float = 1.0, r: float = 0.9,
                   check: bool = True, kind: str = "prop") -> dict | None:
        if check:
            if self.struct.blocked(x, z) or self.roads.edge_dist(x, z) < 1.5 or self.rivers.edge_dist(x, z) < 3.0:
                return None
        if check:
            self.struct.circle(x, z, r)
        o = {"id": self.next_id("prop"), "model": mid, "kind": kind, "pos": [r1(x), round(self.h(x, z), 2), r1(z)],
             "yaw": round(yaw, 3), "scale": [scale] * 3}
        if owner:
            o["owner"] = owner
        self.objects.append(o)
        return o

    def dress_building(self, b: dict, rng: np.random.Generator, n_props: int) -> None:
        cx, cz = b["pos"][0], b["pos"][2]
        yaw = b["yaw"]
        ax, az = math.cos(yaw), -math.sin(yaw)
        fx, fz = math.sin(yaw), math.cos(yaw)
        hx, hz = b["hx"], b["hz"]
        tries = 0
        placed = 0
        while placed < n_props and tries < 12:
            tries += 1
            side = rng.choice([-1, 1])
            u = side * (hx + rng.uniform(1.3, 2.5))
            v = rng.uniform(-hz * 0.4, hz * 0.9)
            x, z = cx + ax * u + fx * v, cz + az * u + fz * v
            mid = PROP_CHOICES[int(rng.integers(len(PROP_CHOICES)))]
            if self.place_prop(mid, x, z, yaw + rng.uniform(-0.5, 0.5), owner=b["id"]) is not None:
                placed += 1

    def garden_for(self, b: dict, rng: np.random.Generator) -> None:
        hx, hz = b["hx"], b["hz"]
        cx, cz = b["pos"][0], b["pos"][2]
        yaw = b["yaw"]
        ax, az = math.cos(yaw), -math.sin(yaw)
        fx, fz = math.sin(yaw), math.cos(yaw)
        for side in rng.permutation([-1, 1]):
            u = side * (hx + 5.0)
            v = rng.uniform(-hz * 0.3, hz * 0.3)
            x, z = cx + ax * u + fx * v, cz + az * u + fz * v
            if self.site_ok(x, z, yaw, 2.1, 2.1, 0.7, gap=0.8):
                self.claim(x, z, yaw, 2.1, 2.1, 0.8)
                self.add_foliage(f"shire/garden_plot_{int(rng.integers(1, 4))}", x, z, yaw)
                if rng.random() < 0.4:
                    self.add_forage("apple", x, z, 2, None, "garden")
                return

    def front_fence(self, b: dict, rng: np.random.Generator) -> None:
        """Picket fence across the front yard with a gate in the middle, skipped where it hits road/river/other yards."""
        cx, cz = b["pos"][0], b["pos"][2]
        yaw = b["yaw"]
        ax, az = math.cos(yaw), -math.sin(yaw)
        fx, fz = math.sin(yaw), math.cos(yaw)
        door_d = self.models.door_front(b["model"]) * b["scale"][0]
        dist = door_d + (7.0 if "hobbit_hole" in b["model"] else 4.5)
        half = max(5.0, b["hx"] + 1.0)
        seg = 2.1
        n = int(half / seg)
        for i in range(-n, n + 1):
            u = i * seg
            x, z = cx + ax * u + fx * dist, cz + az * u + fz * dist
            if self.roads.edge_dist(x, z) < 1.5 or self.rivers.edge_dist(x, z) < 3.0 or self.struct.blocked(x, z):
                continue
            mid = "shire/gate_picket" if i == 0 else "shire/fence_picket"
            self.add_foliage(mid, x, z, yaw, 1.0)

    # -- generic placement of lines of segments --
    def line_of(self, poly: list[list[float]], models: list[str], spacing: float, lateral: float, rng: np.random.Generator,
                scale: float = 1.0, gaps: list[tuple[float, float, float]] | None = None, axis: str = "x", closed: bool = False,
                clear_roads: bool = True, jitter_yaw: float = 0.0) -> list[tuple[float, float]]:
        """Segments along a polyline, tangent-aligned. gaps = [(x, z, radius)] where nothing is placed."""
        pts = list(poly) + ([poly[0]] if closed else [])
        placed = []
        carry = 0.0
        for a, b in zip(pts, pts[1:]):
            a_, b_ = np.array(a, float), np.array(b, float)
            length = float(np.linalg.norm(b_ - a_))
            if length < 1e-6:
                continue
            t = (b_ - a_) / length
            n = np.array([-t[1], t[0]])
            s = carry
            while s < length:
                p = a_ + t * s + n * lateral
                s += spacing
                if gaps and any((p[0] - gx) ** 2 + (p[1] - gz) ** 2 < gr * gr for gx, gz, gr in gaps):
                    continue
                if clear_roads and self.roads.edge_dist(p[0], p[1]) < 1.0:
                    continue
                if self.rivers.edge_dist(p[0], p[1]) < 2.0:
                    continue
                yaw = math.atan2(-t[1], t[0]) if axis == "x" else math.atan2(t[0], t[1])
                yaw += rng.uniform(-jitter_yaw, jitter_yaw)
                mid = models[int(rng.integers(len(models)))]
                self.add_foliage(mid, float(p[0]), float(p[1]), yaw, scale)
                placed.append((float(p[0]), float(p[1])))
            carry = s - length
        return placed

    # -- forage / interactables --
    def add_forage(self, item: str, x: float, z: float, yield_: int, zone: str | None, tag: str) -> None:
        node = {"id": self.next_id(f"forage_{tag}"), "item": item, "pos": [r1(x), round(self.h(x, z) + 0.05, 2), r1(z)], "yield": yield_}
        if zone:
            node["zone"] = zone
        self.forage.append(node)

    def add_interactable(self, kind: str, label: str, x: float, z: float, payload: dict | None = None, poi: str | None = None,
                         building: str | None = None) -> None:
        it = {"id": self.next_id(f"it_{kind}"), "kind": kind, "label": label, "pos": [r1(x), round(self.h(x, z) + 0.9, 2), r1(z)],
              "payload": payload or {}}
        if poi:
            it["poi"] = poi
        if building:
            it["building"] = building
        self.interactables.append(it)


# --- features --------------------------------------------------------------------------------------------

def place_anchored(w: World) -> None:
    """Buildings that must stand at a named POI."""
    P = w.pois

    # Bag End: dug into the south face of The Hill, door on the lane, which runs through the POI.
    bx, _, bz = P["bag_end"]["pos"]
    fx, fz = 0.0, 1.0   # downhill (south); the lane and the Hill-path both arrive from this side
    door_d = w.models.door_front("shire/hobbit_hole_1")
    cx, cz = bx - fx * door_d, bz - fz * door_d
    yaw = math.atan2(fx, fz)
    w.place_building("bag_end", "shire/hobbit_hole_1", cx, cz, yaw, "hobbiton", "bag_end", role="hole_home", check=False, allow_road=True)

    # Bagshot Row: a terrace of holes along the contour, doors downhill.
    rx, _, rz = P["bagshot_row"]["pos"]
    gx = w.h(rx + 4, rz) - w.h(rx - 4, rz)
    gz = w.h(rx, rz + 4) - w.h(rx, rz - 4)
    down = np.array([gx, gz])
    down = -down / (np.linalg.norm(down) + 1e-9)
    if abs(down[0]) + abs(down[1]) < 0.1:
        down = np.array([0.0, 1.0])
    along = np.array([-down[1], down[0]])
    ddoor = w.models.door_front("shire/hobbit_hole_2")
    for i, (mid, off) in enumerate((("shire/hobbit_hole_2", -17.0), ("shire/hobbit_hole_4", 0.0), ("shire/hobbit_hole_3", 19.0))):
        door = np.array([rx, rz]) + along * off
        c = door - down * (ddoor if i != 2 else w.models.door_front(mid))
        w.place_building(f"bagshot_row_{i + 1}", mid, c[0], c[1], math.atan2(down[0], down[1]), "hobbiton", "bagshot_row" if i == 1 else None,
                        role="hole", slope_tol=HOLE_SLOPE_TOL * 1.3, check=True, allow_road=True) or \
            w.place_building(f"bagshot_row_{i + 1}", mid, c[0], c[1], math.atan2(down[0], down[1]), "hobbiton", None, role="hole", check=False, allow_road=True)

    anchored = [
        ("mill", "shire/mill_water", "hobbiton", 1.0, "mill"),
        ("green_dragon", INN_MODELS["green_dragon"], "bywater", 1.0, "inn"),
        ("floating_log", INN_MODELS["floating_log"], "frogmorton", 1.0, "inn"),
        ("golden_perch", INN_MODELS["golden_perch"], "stock", 1.0, "inn"),
        ("maggots_farm", "shire/hobbit_cottage_3", "marish", 1.15, "farm"),
        ("bamfurlong", "shire/hobbit_cottage_2", "marish", 1.1, "farm"),
        ("brandy_hall", "shire/hobbit_hole_3", "buckland", 1.9, "hall"),
        ("crickhollow", "shire/hobbit_cottage_2", "buckland", 1.0, "house"),
        ("prancing_pony", INN_MODELS["prancing_pony"], "bree", 1.0, "inn"),
        ("bill_ferny_house", "bree/bill_ferny_house", "bree", 1.0, "house"),
    ]
    for poi, mid, sett, scale, role in anchored:
        x, _, z = P[poi]["pos"]
        b = w.beside_road(poi, mid, x, z, sett, poi, scale, role)
        if b is None:
            raise RuntimeError(f"could not site {poi}")


def place_settlements(w: World) -> dict[str, int]:
    counts = {}
    for sid, rec in RECIPES.items():
        counts[sid] = w.scatter_buildings(sid, rec)
    return counts


def dress_settlements(w: World) -> None:
    rng = rng_for("dressing")
    for b in list(w.buildings):
        role = b["role"]
        poi = b.get("poi")
        shire = b["model"].startswith("shire/")
        if role == "inn":
            w.dress_building(b, rng, 5)
            _inn_yard(w, b, rng)
        elif role == "farm":
            w.dress_building(b, rng, 6)
            _farm(w, b, rng)
        elif role in ("hole_home", "hole"):
            if role == "hole_home" or poi:
                w.dress_building(b, rng, 2)
            else:
                w.dress_building(b, rng, int(rng.integers(0, 3)))
            w.garden_for(b, rng)
        else:
            w.dress_building(b, rng, int(rng.integers(1, 4)))
            if shire:
                if rng.random() < 0.7:
                    w.garden_for(b, rng)
                if rng.random() < 0.6:
                    w.front_fence(b, rng)
    # wells in the middle of each village
    for sid, s in w.settlements.items():
        if sid in ("marish", "buckland"):
            continue
        rng = rng_for(f"well_{sid}")
        cx, cz = s["center"]
        for _ in range(60):
            x, z = cx + rng.uniform(-35, 35), cz + rng.uniform(-35, 35)
            if w.struct.blocked(x, z) or w.roads.edge_dist(x, z) < 5 or w.rivers.edge_dist(x, z) < 8:
                continue
            p = w.place_prop(f"shire/well_{int(rng.integers(1, 3))}", x, z, rng.uniform(0, math.tau), r=2.2, check=True, kind="well")
            if p is not None:
                w.add_interactable("well", "the village well", x, z, {"settlement": sid})
                break
    place_bree_lanterns(w)


def place_bree_lanterns(w: World) -> None:
    rng = rng_for("lanterns")
    road = next(r for r in w.region["roads"] if r["id"] == "east_road")
    pts = _densify(np.array([q for q in road["points"] if 7290 <= q[0] <= 7700], float), 38.0)
    for i in range(len(pts) - 1):
        t = pts[i + 1] - pts[i]
        t /= np.linalg.norm(t)
        n = np.array([-t[1], t[0]]) * (1 if i % 2 else -1)
        p = pts[i] + n * (ROAD_HW["road"] + 1.8)
        w.place_prop("props/lantern_post", p[0], p[1], rng.uniform(0, 6.28), r=0.5)


def _inn_yard(w: World, b: dict, rng: np.random.Generator) -> None:
    cx, cz = b["pos"][0], b["pos"][2]
    yaw = b["yaw"]
    ax, az = math.cos(yaw), -math.sin(yaw)
    fx, fz = math.sin(yaw), math.cos(yaw)
    door_d = w.models.door_front(b["model"])
    # table in front of the door; the food interactables sit on it, since the interiors are not modelled
    dist = door_d + 3.2
    tx, tz = cx + fx * dist + ax * 2.5, cz + fz * dist + az * 2.5
    if w.place_prop("props/table_2", tx, tz, yaw, owner=b["id"], r=1.8) is None:
        tx, tz = cx + fx * dist - ax * 2.5, cz + fz * dist - az * 2.5
        w.place_prop("props/table_2", tx, tz, yaw, owner=b["id"], r=1.8)
    for k, (item, label) in enumerate(INN_FOOD):
        x, z = tx + ax * (k - 1) * 0.9, tz + az * (k - 1) * 0.9
        w.add_interactable("food", label, x, z, {"item": item, "count": 1}, poi=b.get("poi"), building=b["id"])
    for side in (-1, 1):
        w.place_prop("props/stool", tx + fx * 1.3 + ax * side * 1.0, tz + fz * 1.3 + az * side * 1.0, rng.uniform(0, 6), owner=b["id"], r=0.5)
    # lantern posts flanking the door
    for side in (-1, 1):
        x, z = cx + fx * (door_d + 1.5) + ax * side * 3.0, cz + fz * (door_d + 1.5) + az * side * 3.0
        w.place_prop("props/lantern_post", x, z, 0.0, owner=b["id"], r=0.5)
    if b.get("poi") == "prancing_pony":
        x, z = cx + fx * (door_d + 5.5) - ax * 7.0, cz + fz * (door_d + 5.5) - az * 7.0
        w.place_prop("props/signpost_2", x, z, yaw, owner=b["id"], r=0.6)
        w.place_prop("props/cart_1", cx - ax * (b["hx"] + 3.5), cz - az * (b["hx"] + 3.5) + fz * 3, yaw + 1.2, owner=b["id"], r=2.5)


def _farm(w: World, b: dict, rng: np.random.Generator) -> None:
    """Fenced yard with a gap in front, plus two crop fields of garden plots on the flank."""
    cx, cz = b["pos"][0], b["pos"][2]
    yaw = b["yaw"]
    ax, az = math.cos(yaw), -math.sin(yaw)
    fx, fz = math.sin(yaw), math.cos(yaw)
    half = 20.0
    seg = 2.1
    n = int(2 * half / seg)
    for side in range(4):
        for i in range(n):
            u = -half + i * seg
            if side == 0:   # front: leave a 6 m opening in the middle
                if abs(u) < 3.2:
                    continue
                x, z, ya = cx + ax * u + fx * half, cz + az * u + fz * half, yaw
            elif side == 1:
                x, z, ya = cx + ax * u - fx * half, cz + az * u - fz * half, yaw
            elif side == 2:
                x, z, ya = cx + ax * half + fx * u, cz + az * half + fz * u, yaw + math.pi / 2
            else:
                x, z, ya = cx - ax * half + fx * u, cz - az * half + fz * u, yaw + math.pi / 2
            if w.roads.edge_dist(x, z) < 1.0 or w.rivers.edge_dist(x, z) < 3.0:
                continue
            w.add_foliage("shire/fence_rail", x, z, ya)
    # fields behind the house
    zone = "maggots_fields" if b["poi"] == "maggots_farm" else None
    for fi, side in enumerate((-1, 1)):
        ox = ax * side * (half + 18.0) - fx * 4.0
        oz = az * side * (half + 18.0) - fz * 4.0
        for gi in range(3):
            for gj in range(4):
                u, v = (gi - 1) * 4.6, (gj - 1.5) * 4.6
                x, z = cx + ox + ax * u + fx * v, cz + oz + az * u + fz * v
                if w.in_forest(x, z) or w.roads.edge_dist(x, z) < 2.5 or w.rivers.edge_dist(x, z) < 8.0 or w.struct.blocked(x, z):
                    continue
                w.add_foliage(f"shire/garden_plot_{int(rng.integers(1, 4))}", x, z, yaw)
                if rng.random() < 0.55:
                    item = "mushrooms" if (fi == 0 or rng.random() < 0.4) else "potatoes"
                    w.add_forage(item, x + rng.uniform(-1, 1), z + rng.uniform(-1, 1), int(rng.integers(2, 5)), zone, b["poi"].split("_")[0])
        w.struct.poly(w.rect_corners(cx + ox, cz + oz, yaw, 7.5, 11.0, 1.0))


def place_interactables_for_buildings(w: World) -> None:
    for b in w.buildings:
        dx, dz = b["door"]
        poi = b.get("poi")
        if b["model"].startswith("shire/hobbit_hole"):
            label = DOOR_LABELS.get(poi or "", "a round door")
        else:
            label = DOOR_LABELS.get(poi or "", "the door")
        w.add_interactable("door", label, dx, dz, {"building": b["id"]}, poi=poi, building=b["id"])
        if poi in BEDS:
            yaw = b["yaw"]
            ax, az = math.cos(yaw), -math.sin(yaw)
            blabel, place = BEDS[poi]
            w.add_interactable("bed", blabel, dx + ax * 1.8, dz + az * 1.8, {"hours": 8, "place": place}, poi=poi, building=b["id"])


def place_crossings(w: World) -> None:
    """Bridges where roads cross rivers, the ferry raft, the Three-Farthing Stone and the Bree gates."""
    def seg_hits(a, b, c, d):
        a, b, c, d = map(lambda q: np.array(q, float), (a, b, c, d))
        r_, s_ = b - a, d - c
        den = r_[0] * s_[1] - r_[1] * s_[0]
        if abs(den) < 1e-9:
            return None
        t = ((c - a)[0] * s_[1] - (c - a)[1] * s_[0]) / den
        u = ((c - a)[0] * r_[1] - (c - a)[1] * r_[0]) / den
        return a + t * r_ if 0 <= t <= 1 and 0 <= u <= 1 else None

    for rd in w.region["roads"]:
        for rv in w.region["rivers"]:
            for i in range(len(rd["points"]) - 1):
                for j in range(len(rv["points"]) - 1):
                    p = seg_hits(rd["points"][i], rd["points"][i + 1], rv["points"][j], rv["points"][j + 1])
                    if p is None:
                        continue
                    t = np.array(rd["points"][i + 1], float) - np.array(rd["points"][i], float)
                    t /= np.linalg.norm(t)
                    hw = rv["width"] / 2
                    if rd["kind"] == "ferry":
                        _ferry(w, p, t, hw)
                        continue
                    if any(abs(o["pos"][0] - p[0]) < 30 and abs(o["pos"][2] - p[1]) < 30 for o in w.objects if o["kind"] == "bridge"):
                        continue  # two roads share one crossing (buckland_road / east_road)
                    _bridge(w, rd, rv, p, t, hw)

    # Three-Farthing Stone beside the East Road
    x, _, z = w.pois["three_farthing_stone"]["pos"]
    p0, t, _, rid = w.roads.nearest(x, z)
    n = np.array([-t[1], t[0]])
    for side in (-1, 1):
        c = p0 + n * side * (ROAD_HW["road"] + 4.5)
        if not w.struct.blocked(c[0], c[1]):
            w.place_prop("shire/three_farthing_stone", c[0], c[1], math.atan2(-n[0] * side, -n[1] * side), r=3.0, kind="landmark")
            break

    # Bree gates where roads cross the dike polygon
    dike = w.region["walls"][1]["points"]
    gates = []
    for rd in w.region["roads"]:
        for i in range(len(rd["points"]) - 1):
            for j in range(len(dike)):
                p = seg_hits(rd["points"][i], rd["points"][i + 1], dike[j], dike[(j + 1) % len(dike)])
                if p is not None:
                    t = np.array(rd["points"][i + 1], float) - np.array(rd["points"][i], float)
                    t /= np.linalg.norm(t)
                    gates.append((p, t, rd["id"]))
    seen: list[np.ndarray] = []
    for p, t, rid in gates:
        if any(np.linalg.norm(p - q) < 40 for q in seen):
            continue
        seen.append(p)
        poi_name = min(("bree_west_gate", "bree_south_gate"), key=lambda k: np.hypot(w.pois[k]["pos"][0] - p[0], w.pois[k]["pos"][2] - p[1]))
        near_poi = np.hypot(w.pois[poi_name]["pos"][0] - p[0], w.pois[poi_name]["pos"][2] - p[1]) < 40
        mid = "bree/bree_gate_watch" if near_poi and poi_name == "bree_south_gate" else "bree/bree_gate_stone"
        gid = poi_name if near_poi else "bree_east_gate"
        yaw = math.atan2(t[0], t[1])
        w.objects.append({"id": gid + "_model", "model": mid, "kind": "gate", "pos": [r1(p[0]), round(w.h(*p), 2), r1(p[1])], "yaw": round(yaw, 3),
                          "scale": [1.0, 1.0, 1.0], "poi": gid if near_poi else None})
    w.bree_gates = seen  # type: ignore[attr-defined]


def _bridge(w: World, rd: dict, rv: dict, p: np.ndarray, t: np.ndarray, hw: float) -> None:
    if rv["width"] > 30:
        mid, deck, length, sy, margin = "shire/bridge_brandywine", 3.44, 36.1, 1.6, 12.0
    elif rd["kind"] == "road":
        mid, deck, length, sy, margin = "shire/bridge_small_stone", 1.4, 6.0, 2.2, 7.0
    else:
        mid, deck, length, sy, margin = "shire/bridge_small_wood", 0.6, 6.0, 2.0, 7.0
    sx = (2 * hw + 2 * margin) / length
    ends = [w.h(*(p - t * (hw + margin))), w.h(*(p + t * (hw + margin)))]
    y = float(np.mean(ends)) - deck
    yaw = math.atan2(-t[1], t[0])
    w.objects.append({"id": w.next_id("bridge"), "model": mid, "kind": "bridge", "pos": [r1(p[0]), round(y, 2), r1(p[1])], "yaw": round(yaw, 3),
                      "scale": [round(sx, 3), 1.0, round(sy, 3)], "road": rd["id"], "river": rv["id"]})
    for sgn in (-1, 1):  # signposts at both ends
        q = p + t * sgn * (hw + margin + 4) + np.array([-t[1], t[0]]) * 6.0
        w.place_prop("props/signpost_1", q[0], q[1], yaw, r=0.6)


def _ferry(w: World, p: np.ndarray, t: np.ndarray, hw: float) -> None:
    bed = w.h(*p)
    water = bed + 0.6 * float(np.clip(0.09 * hw * 2, 1.5, 4.5))   # same depth rule as the terrain/water generators
    yaw = math.atan2(-t[1], t[0])
    w.objects.append({"id": "bucklebury_ferry_raft", "model": "shire/ferry_raft", "kind": "ferry", "pos": [r1(p[0]), round(water - 0.25, 2), r1(p[1])],
                      "yaw": round(yaw, 3), "scale": [1.0, 1.0, 1.0], "poi": "bucklebury_ferry"})


def place_hedges(w: World) -> dict[str, int]:
    out = {}
    # Buckland Hedge (the High Hay): a scaled-up thick hedge with an opening at the gate and one where each road passes through.
    rng = rng_for("high_hay")
    hay = next(x for x in w.region["walls"] if x["id"] == "high_hay")
    gate = w.pois["hedge_gate"]["pos"]
    gaps = [(gate[0], gate[2], 5.5)]
    for rd in w.region["roads"]:
        if rd["kind"] == "ferry":
            continue
        for i in range(len(rd["points"]) - 1):
            for j in range(len(hay["points"]) - 1):
                a, b = np.array(rd["points"][i], float), np.array(rd["points"][i + 1], float)
                c, d = np.array(hay["points"][j], float), np.array(hay["points"][j + 1], float)
                r_, s_ = b - a, d - c
                den = r_[0] * s_[1] - r_[1] * s_[0]
                if abs(den) < 1e-9:
                    continue
                tt = ((c - a)[0] * s_[1] - (c - a)[1] * s_[0]) / den
                uu = ((c - a)[0] * r_[1] - (c - a)[1] * r_[0]) / den
                if 0 <= tt <= 1 and 0 <= uu <= 1:
                    q = a + tt * r_
                    gaps.append((float(q[0]), float(q[1]), 9.0))
    w.hay_gaps = gaps  # type: ignore[attr-defined]
    scale = 1.9
    placed = w.line_of(hay["points"], ["nature/hedge_straight_1", "nature/hedge_straight_2"], 4.7 * scale * 0.97, 0.0, rng, scale=scale, gaps=gaps,
                       clear_roads=False)
    out["buckland_hedge"] = len(placed)
    # gate leaves at the Hedge gate
    for side in (-1, 1):
        t = _tangent_at(hay["points"], gate[0], gate[2])
        x, z = gate[0] + t[0] * side * 2.4, gate[2] + t[1] * side * 2.4
        w.add_foliage("shire/gate_rail", x, z, math.atan2(-t[1], t[0]), 2.2)
    w.add_interactable("door", "the Hedge gate", gate[0], gate[2], {"gate": "hedge_gate"}, poi="hedge_gate")

    # Bree dike (bank + ditch with a hedge on top), open at the gates
    rng = rng_for("bree_dike")
    dike = next(x for x in w.region["walls"] if x["id"] == "bree_dyke")
    gaps = [(float(q[0]), float(q[1]), 10.0) for q in w.bree_gates]  # type: ignore[attr-defined]
    placed = w.line_of(dike["points"], ["bree/bree_dike_hedge", "bree/bree_dike_hedge", "bree/bree_dike"], 6.0, 0.0, rng, gaps=gaps,
                       closed=True, clear_roads=False)
    out["bree_dike"] = len(placed)

    # Field hedges along roads in the Shire: runs of 30-90 m with gaps, on one side of the road.
    rng = rng_for("road_hedges")
    count = 0
    for rd in w.region["roads"]:
        if rd["kind"] == "ferry":
            continue
        pts = np.array(rd["points"], float)
        dense = _densify(pts, 6.0)
        run_end = -1
        side = 1
        for i, q in enumerate(dense):
            sett = _settlement_at(w, q[0], q[1])
            if sett is None or w.settlements[sett]["faction"] == "bree":
                continue
            if i > run_end and rng.random() < 0.06:
                run_end = i + int(rng.integers(5, 15))
                side = int(rng.choice([-1, 1]))
            if i > run_end or i + 1 >= len(dense):
                continue
            t = dense[i + 1] - q
            t /= np.linalg.norm(t) + 1e-9
            n = np.array([-t[1], t[0]]) * side
            hw = ROAD_HW[w.road_kind[rd["id"]]]
            p = q + n * (hw + 5.0)
            if w.struct.blocked(p[0], p[1]) or w.in_forest(p[0], p[1]) or w.roads.edge_dist(p[0], p[1]) < 2.5 or w.rivers.edge_dist(p[0], p[1]) < 5.0:
                continue
            w.add_foliage(["nature/hedge_straight_1", "nature/hedge_straight_2"][int(rng.integers(2))], float(p[0]), float(p[1]), math.atan2(-t[1], t[0]))
            count += 1
    out["road_hedges"] = count
    return out


def _tangent_at(poly: list[list[float]], x: float, z: float) -> np.ndarray:
    best = (1e18, np.array([1.0, 0.0]))
    for a, b in zip(poly, poly[1:]):
        a_, b_ = np.array(a, float), np.array(b, float)
        d = b_ - a_
        L2 = float(d @ d)
        s = float(np.clip(((np.array([x, z]) - a_) @ d) / L2, 0, 1))
        dist = float(np.linalg.norm(a_ + s * d - np.array([x, z])))
        if dist < best[0]:
            best = (dist, d / math.sqrt(L2))
    return best[1]


def _densify(pts: np.ndarray, step: float) -> np.ndarray:
    out = []
    for a, b in zip(pts, pts[1:]):
        n = max(1, int(np.linalg.norm(b - a) / step))
        for i in range(n):
            out.append(a + (b - a) * i / n)
    out.append(pts[-1])
    return np.array(out)


def _settlement_at(w: World, x: float, z: float) -> str | None:
    for sid, s in w.settlements.items():
        if (x - s["center"][0]) ** 2 + (z - s["center"][1]) ** 2 <= (s["radius"] * 0.9) ** 2:
            return sid
    return None


VARIANTS = {"tree": 3, "bush": 2, "rock": 3, "flower_patch": 2, "grass_tuft": 2}


def variant(rng: np.random.Generator, kind: str) -> int:
    """Fewer distinct meshes per cell means fewer MultiMeshes; three tree variants still read as varied."""
    return int(rng.integers(1, VARIANTS[kind] + 1))


def pick_species(rng: np.random.Generator, mix: list[tuple[str, int]]) -> str:
    names = [m for m, _ in mix]
    p = np.array([c for _, c in mix], float)
    p /= p.sum()
    return names[int(rng.choice(len(names), p=p))]


def place_forests(w: World) -> dict[str, int]:
    counts = {}
    for fid, f in w.forests.items():
        rng = rng_for(f"forest_{fid}")
        poly = f["polygon"]
        xs, zs = [p[0] for p in poly], [p[1] for p in poly]
        r = FOREST_SPACING_M / math.sqrt(f["density"])
        lo, hi = FOREST_SCALE.get(fid, (0.85, 1.3))
        mix = FOREST_MIX[fid]
        pts = poisson(rng, (min(xs), min(zs), max(xs), max(zs)), r,
                      lambda x, z, fm=w.forest_mask[fid]: bool(fm.blocked(x, z)) and w.free_for_tree(x, z) and 0 < x < w.size[0] and 0 < z < w.size[1])
        for x, z in pts:
            sp = pick_species(rng, mix)
            w.add_foliage(f"nature/tree_{sp}_{variant(rng, 'tree')}", x, z, rng.uniform(0, math.tau), float(rng.uniform(lo, hi)))
        n_trees = len(pts)
        # understory
        rng2 = rng_for(f"understory_{fid}")
        under = poisson(rng2, (min(xs), min(zs), max(xs), max(zs)), UNDERSTORY_SPACING_M,
                        lambda x, z, fm=w.forest_mask[fid]: bool(fm.blocked(x, z)) and w.free_for_tree(x, z) and 0 < x < w.size[0] and 0 < z < w.size[1])
        for x, z in under:
            u = rng2.random()
            if u < 0.55:
                mid = f"nature/bush_{variant(rng2, 'bush')}"
            elif u < 0.85:
                mid = f"nature/rock_{variant(rng2, 'rock')}"
            elif u < 0.95:
                mid = ["nature/log_single", "nature/log_stump"][int(rng2.integers(2))]
            else:
                mid = f"nature/flower_patch_{variant(rng2, 'flower_patch')}"
            w.add_foliage(mid, x, z, rng2.uniform(0, math.tau), float(rng2.uniform(0.8, 1.3)))
        counts[fid] = n_trees + len(under)
        if not f["enterable"]:
            _old_forest_wall(w, f, rng_for(f"wall_{fid}"))
    return counts


def _old_forest_wall(w: World, f: dict, rng: np.random.Generator) -> None:
    """Two staggered rows of large trees along the polygon edge, backed by an invisible collision wall."""
    poly = f["polygon"]
    segs = []
    for (x1, z1), (x2, z2) in zip(poly, poly[1:] + poly[:1]):
        a, b = np.array([x1, z1], float), np.array([x2, z2], float)
        L = float(np.linalg.norm(b - a))
        t = (b - a) / L
        n = np.array([-t[1], t[0]])
        if in_polygon(*(a + t * L / 2 + n * 3.0), poly):
            pass
        else:
            n = -n  # inward normal
        steps = int(L / WALL_SPACING_M)
        for i in range(steps):
            for row, inset in enumerate((1.5, 4.5)):
                s = (i + 0.5 * row) * WALL_SPACING_M
                p = a + t * s + n * (inset + rng.uniform(-0.5, 0.5))
                if w.rivers.edge_dist(p[0], p[1]) < 2.0:
                    continue
                sp = pick_species(rng, [("oak", 40), ("beech", 35), ("willow", 15), ("pine", 10)])
                w.add_foliage(f"nature/tree_{sp}_{variant(rng, 'tree')}", float(p[0]), float(p[1]), rng.uniform(0, math.tau), float(rng.uniform(1.3, 1.8)))
        # collision wall: 16 m boxes just inside the edge
        nseg = max(1, int(math.ceil(L / 16.0)))
        for i in range(nseg):
            s0, s1 = L * i / nseg, L * (i + 1) / nseg
            p0, p1 = a + t * s0 + n * 3.0, a + t * s1 + n * 3.0
            segs.append([r1(p0[0]), r1(p0[1]), r1(p1[0]), r1(p1[1])])
    w.barriers.append({"id": f["id"] + "_wall", "height_m": 14.0, "thickness_m": 3.0, "segs": segs})


def place_open_country(w: World) -> dict[str, int]:
    rng = rng_for("open_trees")
    W, H = w.size
    margin = 260.0
    in_settle = lambda x, z: _settlement_at(w, x, z) is not None  # noqa: E731

    def accept(x: float, z: float) -> bool:
        if not (margin < x < W - margin and margin < z < H - margin):
            return False
        if not w.free_for_tree(x, z) or bool(w.in_forest(x, z)):
            return False
        a = 0.5 + 0.5 * math.tanh(1.6 * w.clump(x, z))   # clumpy: copses and open meadow
        if in_settle(x, z):
            a *= 0.25
        return rng.random() < a + 0.05

    pts = poisson(rng, (margin, margin, W - margin, H - margin), OPEN_TREE_SPACING_M, accept, k=10)
    for x, z in pts:
        if x > 6900:
            sp = pick_species(rng, [("birch", 40), ("pine", 25), ("oak", 25), ("beech", 10)])
        elif x > 5300:
            sp = pick_species(rng, [("beech", 40), ("oak", 40), ("birch", 20)])
        else:
            sp = pick_species(rng, [("oak", 55), ("beech", 20), ("birch", 25)])
        w.add_foliage(f"nature/tree_{sp}_{variant(rng, 'tree')}", x, z, rng.uniform(0, math.tau), float(rng.uniform(0.8, 1.3)))
    n_open = len(pts)

    # bushes, flowers and grass tufts in the yards of each settlement, thinning out toward its edge
    rng = rng_for("bushes")
    n_bush = 0
    for sid, s in w.settlements.items():
        cx, cz = s["center"]
        R = s["radius"] * 0.75
        spts = poisson(rng, (cx - R, cz - R, cx + R, cz + R), GROUND_COVER_SPACING_M,
                       lambda x, z: (x - cx) ** 2 + (z - cz) ** 2 < R * R and w.free_for_tree(x, z) and not bool(w.in_forest(x, z)))
        for x, z in spts:
            if rng.random() < math.hypot(x - cx, z - cz) / R * 0.9:
                continue
            u = rng.random()
            if u < 0.35:
                w.add_foliage(f"nature/bush_{variant(rng, 'bush')}", x, z, rng.uniform(0, math.tau), float(rng.uniform(0.7, 1.1)))
            elif u < 0.6:
                w.add_foliage(f"nature/flower_patch_{variant(rng, 'flower_patch')}", x, z, rng.uniform(0, math.tau), float(rng.uniform(0.9, 1.4)))
            else:
                w.add_foliage(f"nature/grass_tuft_{variant(rng, 'grass_tuft')}", x, z, rng.uniform(0, math.tau), float(rng.uniform(1.0, 1.8)))
            n_bush += 1

    # rocks on steep ground
    rng = rng_for("rocks")
    n_rock = 0
    for x, z in poisson(rng, (60, 60, W - 60, H - 60), 38.0, lambda x, z: True, k=4):
        slope = abs(w.h(x + 4, z) - w.h(x - 4, z)) + abs(w.h(x, z + 4) - w.h(x, z - 4))
        if slope < 3.0 or not w.free_for_tree(x, z) or bool(w.in_forest(x, z)):
            continue
        w.add_foliage(f"nature/rock_{variant(rng, 'rock')}", x, z, rng.uniform(0, math.tau), float(rng.uniform(0.8, 2.0)))
        n_rock += 1

    # willows and reeds along the rivers
    rng = rng_for("riverbank")
    n_bank = 0
    for rv in w.region["rivers"]:
        hw = rv["width"] / 2
        dense = _densify(np.array(rv["points"], float), 22.0)
        for i in range(len(dense) - 1):
            t = dense[i + 1] - dense[i]
            t /= np.linalg.norm(t) + 1e-9
            n = np.array([-t[1], t[0]])
            for side in (-1, 1):
                if rng.random() < 0.55:
                    p = dense[i] + n * side * (hw + rng.uniform(6.0, 12.0)) + t * rng.uniform(-8, 8)
                    if w.free_for_tree(p[0], p[1]) and not w.in_forest(p[0], p[1]) and 40 < p[0] < W - 40 and 40 < p[1] < H - 40:
                        w.add_foliage(f"nature/tree_willow_{variant(rng, 'tree')}", float(p[0]), float(p[1]), rng.uniform(0, math.tau), float(rng.uniform(0.9, 1.3)))
                        n_bank += 1
                if rng.random() < 0.5:
                    p = dense[i] + n * side * (hw + rng.uniform(0.6, 2.2)) + t * rng.uniform(-8, 8)
                    if w.rivers.edge_dist(p[0], p[1]) >= 0.4 and not w.struct.blocked(p[0], p[1]) and w.roads.edge_dist(p[0], p[1]) > 4 \
                            and 40 < p[0] < W - 40 and 40 < p[1] < H - 40:
                        w.add_foliage(f"nature/reeds_{int(rng.integers(1, 3))}", float(p[0]), float(p[1]), rng.uniform(0, math.tau), float(rng.uniform(0.9, 1.4)))
                        n_bank += 1
    return {"open_trees": n_open, "settlement_ground_cover": n_bush, "rocks": n_rock, "riverbank": n_bank}


def place_woodland_forage(w: World) -> None:
    rng = rng_for("forage_wild")
    for fid, count, item in (("woody_end", 22, "mushrooms"), ("chetwood", 8, "mushrooms"), ("buckland_woods", 8, "mushrooms")):
        poly = w.forests[fid]["polygon"]
        xs, zs = [p[0] for p in poly], [p[1] for p in poly]
        placed = 0
        for _ in range(4000):
            x, z = rng.uniform(min(xs), max(xs)), rng.uniform(min(zs), max(zs))
            if in_polygon(x, z, poly) and w.free_for_tree(x, z) and w.roads.edge_dist(x, z) < 60:
                w.add_forage(item, x, z, int(rng.integers(1, 4)), None, fid)
                placed += 1
                if placed >= count:
                    break


def place_pois(w: World) -> list[dict]:
    out = []
    for p in w.region["pois"]:
        x, _, z = p["pos"]
        out.append({"id": p["id"], "name": p["name"], "kind": p["kind"], "pos": [x, round(w.h(x, z), 2), z]})
    return out


# --- driver ------------------------------------------------------------------------------------------

def build() -> dict:
    w = World()
    w.bree_gates = []  # type: ignore[attr-defined]
    place_crossings(w)          # first: gates are needed by the dike; bridges fix their own spots
    place_anchored(w)
    counts = place_settlements(w)
    dress_settlements(w)
    place_interactables_for_buildings(w)
    hedge_counts = place_hedges(w)
    forest_counts = place_forests(w)
    other = place_open_country(w)
    place_woodland_forage(w)

    # snap foliage to the ground (and sink trunks slightly)
    fol = np.array(w.foliage, float)
    ys = w.ground.height_at(fol[:, 1], fol[:, 2])
    out_fol = []
    for row, y in zip(fol, ys):
        mi = int(row[0])
        name = w.model_list[mi]["id"].split("/", 1)[1]
        sink = next((v for k, v in SINK.items() if name.startswith(k)), 0.0) * row[4]
        out_fol.append([mi, r1(row[1]), round(float(y) - sink, 2), r1(row[2]), round(float(row[3]), 2), round(float(row[4]), 2)])
    # keep [mi, x, y, z, yaw, scale]
    doc = {
        "version": 1,
        "region": "eriador_west",
        "seed": SEED,
        "cell_m": CELL_M,
        "forage_models": FORAGE_ITEM_MODEL,
        "models": w.model_list,
        "foliage": out_fol,
        "objects": w.objects,
        "barriers": w.barriers,
        "pois": place_pois(w),
        "forage": w.forage,
        "interactables": w.interactables,
        "stats": {"settlement_buildings": counts, "hedges": hedge_counts, "forest": forest_counts, **other,
                  "foliage": len(out_fol), "objects": len(w.objects), "buildings": len(w.buildings),
                  "forage": len(w.forage), "interactables": len(w.interactables)},
    }
    return doc


def dumps(doc: dict) -> str:
    """One record per line for the big arrays keeps diffs and file size sane."""
    parts = ["{"]
    keys = list(doc)
    for i, k in enumerate(keys):
        v = doc[k]
        comma = "," if i < len(keys) - 1 else ""
        if isinstance(v, list) and v and isinstance(v[0], (list, dict)):
            body = ",\n".join("  " + json.dumps(e, separators=(",", ":")) for e in v)
            parts.append(f' "{k}": [\n{body}\n ]{comma}')
        else:
            parts.append(f' "{k}": {json.dumps(v, separators=(",", ":"))}{comma}')
    parts.append("}")
    return "\n".join(parts) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=Path, default=OUT)
    ap.add_argument("--stats", action="store_true")
    args = ap.parse_args()
    doc = build()
    args.out.write_text(dumps(doc))
    print(f"wrote {args.out} ({args.out.stat().st_size / 1e6:.2f} MB)")
    if args.stats:
        print(json.dumps(doc["stats"], indent=1))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
