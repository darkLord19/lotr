import sys
from pathlib import Path

import numpy as np
import pytest

sys.path.insert(0, str(Path(__file__).parent))
import heightfield as hf  # noqa: E402

RES = 2.0  # coarser than the shipped 1 m so the suite stays fast


@pytest.fixture(scope="module")
def fld() -> hf.HeightField:
    return hf.build(res=RES)


@pytest.fixture(scope="module")
def region() -> dict:
    return hf.load_region()


def _seg_points(pts, step=40.0):
    for a, b in zip(pts, pts[1:]):
        a, b = np.array(a, float), np.array(b, float)
        n = max(1, int(np.linalg.norm(b - a) / step))
        d = (b - a) / np.linalg.norm(b - a)
        for i in range(n):
            yield a + (b - a) * i / n, np.array([-d[1], d[0]])


def test_deterministic() -> None:
    a = hf.build(res=8.0, seed=7).h
    b = hf.build(res=8.0, seed=7).h
    c = hf.build(res=8.0, seed=8).h
    assert np.array_equal(a, b) and not np.array_equal(a, c)


def test_range_and_r16_roundtrip(fld: hf.HeightField) -> None:
    cfg = fld.cfg
    assert fld.h.min() >= cfg["height_min_m"] and fld.h.max() <= cfg["height_max_m"]
    step = (cfg["height_max_m"] - cfg["height_min_m"]) / 65535
    back = fld.to_r16().astype(np.float32) * step + cfg["height_min_m"]
    assert np.abs(back - fld.h).max() <= step


def test_river_cells_lower_than_neighbours(fld: hf.HeightField, region: dict) -> None:
    for rv in region["rivers"]:
        checked = 0
        for p, n in _seg_points(rv["points"], 150):
            if not (400 < p[0] < 7800 and 400 < p[1] < 3900):
                continue
            c = fld.height_at(*p)
            sides = [fld.height_at(*(p + s * n * (rv["width"] / 2 + 60))) for s in (-1, 1)]
            assert min(sides) > c and np.mean(sides) - c > 0.8, (rv["id"], p)
            checked += 1
        assert checked > 3


def test_roads_flat_across_and_sunken(fld: hf.HeightField, region: dict) -> None:
    rivers = [np.array(r["points"], float) for r in region["rivers"]]
    dense = {r['id']: np.array([q for q, _ in _seg_points(r['points'], 5)]) for r in region['roads']}
    checked = 0
    for rd in region["roads"]:
        if rd["kind"] not in ("road", "path"):
            continue
        hw = fld.cfg["roads"]["half_width_m"][rd["kind"]]
        for p, n in _seg_points(rd["points"], 100):
            if not (300 < p[0] < 7850):
                continue
            if any(np.min(np.linalg.norm(r - p, axis=1)) < 200 for r in rivers):
                continue  # bridges / fords are separate meshes
            if any(np.min(np.linalg.norm(o - p, axis=1)) < 30 for oid, o in dense.items() if oid != rd['id']):
                continue  # junctions
            c = fld.height_at(*p)
            for s in (-0.7, 0.7):
                assert abs(fld.height_at(*(p + s * hw * n)) - c) < 0.3
            checked += 1
    assert checked > 50
    # the East Road is slightly below the verge
    east = next(r for r in region["roads"] if r["id"] == "east_road")["points"]
    diffs = [np.mean([fld.height_at(*(p + sg * n * 14)) for sg in (-1, 1)]) - fld.height_at(*p)
             for p, n in _seg_points(east, 100) if 1000 < p[0] < 7000 and not any(np.min(np.linalg.norm(np.array(r['points'], float) - p, axis=1)) < 300 for r in region['rivers'])]
    assert np.mean(diffs) > 0.1


def test_settlement_bench_flat(fld: hf.HeightField, region: dict) -> None:
    bc = fld.cfg["bench"]
    for s in region["settlements"]:
        core = s["radius"] * {**bc, **bc.get("overrides", {}).get(s["id"], {})}["core_frac"] * 0.9
        cx, cz = s["center"]
        ang = np.linspace(0, 2 * np.pi, 24, endpoint=False)
        hs = [fld.height_at(cx + r * np.cos(a), cz + r * np.sin(a)) for r in (0, core * 0.5, core) for a in ang]
        hs = np.array(hs)
        # roads sunk into the bench and rivers are the only allowed deviations
        assert np.percentile(hs, 90) - np.percentile(hs, 10) < 0.6, s["id"]


def test_bree_hill_raised(fld: hf.HeightField) -> None:
    ring = [fld.height_at(7520 + 700 * np.cos(a), 2250 + 700 * np.sin(a)) for a in np.linspace(np.pi / 2, 3 * np.pi / 2, 9)]
    assert fld.height_at(7520, 2250) - np.mean(ring) > 30


def test_rising_toward_barrow_downs(fld: hf.HeightField) -> None:
    assert fld.height_at(6900, 3700) > fld.height_at(1500, 1000) + 40


def test_edges_high(fld: hf.HeightField) -> None:
    h, interior = fld.h, fld.h[len(fld.h) // 4 : -len(fld.h) // 4, len(fld.h[0]) // 8 : -len(fld.h[0]) // 8]
    edge = 40
    for band in (h[:edge], h[-edge:], h[:, :edge], h[:, -edge:]):
        assert band.mean() > interior.mean() + 40
        assert band.min() > fld.cfg["base_level_m"] * 0.4  # no holes to the void


def test_height_at_matches_array_and_vectorised(fld: hf.HeightField) -> None:
    assert fld.height_at(100 * RES, 50 * RES) == pytest.approx(float(fld.h[50, 100]))
    out = fld.height_at(np.array([10.0, 500.0]), np.array([10.0, 900.0]))
    assert out.shape == (2,)
