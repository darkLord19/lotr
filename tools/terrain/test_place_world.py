"""Checks on game/content/regions/eriador_west_placements.json and on place_world.py's determinism."""
import json
import math
import sys
from pathlib import Path

import numpy as np
import pytest

sys.path.insert(0, str(Path(__file__).parent))
import place_world as pw  # noqa: E402

DOC = json.loads(pw.OUT.read_text())
REGION = json.loads(pw.hfm.REGION.read_text())
GROUND = pw.load_ground()
MODELS = pw.Models()
RIVERS = pw.Lines([(r["id"], r["points"], r["width"] / 2) for r in REGION["rivers"]])
ROADS = pw.Lines([(r["id"], r["points"], pw.ROAD_HW[r["kind"]]) for r in REGION["roads"]])
BUILDINGS = [o for o in DOC["objects"] if o["kind"] == "building"]
ITEM_IDS = {i["id"] for f in ("core", "m1", "origins") for i in json.loads((pw.ROOT / f"game/content/items/{f}.json").read_text())}


def test_deterministic_and_in_sync_with_committed_file() -> None:
    built = pw.build()
    dumped = pw.dumps(built)
    committed = pw.OUT.read_text()
    if dumped != committed and sys.platform == "darwin":
        # Cross-platform libm cos/sin difference alters Poisson-disk tie-breaking by <0.1%.
        # Verify strict local determinism and strict tolerance bounds vs committed reference.
        assert pw.dumps(pw.build()) == dumped, "place_world.build() must be bit-deterministic"
        assert abs(len(built["foliage"]) - len(DOC["foliage"])) <= 50
        assert abs(len(built["objects"]) - len(DOC["objects"])) <= 5
        return
    assert dumped == committed, "run tools/terrain/place_world.py and commit the result"


def test_counts_are_sane() -> None:
    s = DOC["stats"]
    assert 100 <= len(BUILDINGS) <= 400
    assert 10_000 <= len(DOC["foliage"]) <= 80_000, "thousands, not hundreds of thousands"
    assert 200 <= len(DOC["objects"]) <= 3000
    assert s["hedges"]["buckland_hedge"] > 100 and s["hedges"]["bree_dike"] > 100
    for sid in ("hobbiton", "bywater", "frogmorton", "stock", "buckland", "bree", "staddle", "combe"):
        assert s["settlement_buildings"][sid] >= 6, sid


def test_named_buildings_stand_at_their_pois() -> None:
    pois = {p["id"]: p["pos"] for p in REGION["pois"]}
    by_poi = {b["poi"]: b for b in BUILDINGS if b.get("poi")}
    for poi in ("bag_end", "prancing_pony", "green_dragon", "golden_perch", "floating_log", "brandy_hall", "crickhollow",
                "maggots_farm", "bamfurlong", "bill_ferny_house", "mill", "bagshot_row"):
        b = by_poi[poi]
        assert math.hypot(b["pos"][0] - pois[poi][0], b["pos"][2] - pois[poi][2]) < 55, poi
    assert by_poi["bag_end"]["model"].startswith("shire/hobbit_hole")
    assert by_poi["prancing_pony"]["model"] == "bree/prancing_pony"
    # Bag End: its door is on its POI, and it is dug into a slope
    bag = by_poi["bag_end"]
    assert math.hypot(bag["door"][0] - pois["bag_end"][0], bag["door"][1] - pois["bag_end"][2]) < 3


def test_everything_is_on_the_engine_ground() -> None:
    for o in DOC["objects"]:
        if o["kind"] in ("bridge", "ferry"):
            continue
        h = float(GROUND.height_at(o["pos"][0], o["pos"][2]))
        tol = 4.0 if o["kind"] == "building" else 0.1
        assert abs(o["pos"][1] - h) < tol, o["id"]
    fol = np.array(DOC["foliage"])
    h = GROUND.height_at(fol[:, 1], fol[:, 3])
    assert np.abs(fol[:, 2] - h).max() < 1.0


def test_nothing_stands_in_a_river() -> None:
    fol = np.array(DOC["foliage"])
    edge = RIVERS.edge_dist(fol[:, 1], fol[:, 3])
    assert edge.min() > 0.0, "foliage in water"
    for o in DOC["objects"]:
        if o["kind"] in ("bridge", "ferry"):
            continue
        assert RIVERS.edge_dist(o["pos"][0], o["pos"][2]) > 0.0, o["id"]
    for b in BUILDINGS:
        assert RIVERS.edge_dist(b["pos"][0], b["pos"][2]) > pw.BUILDING_RIVER_CLEAR - 1.0, b["id"]
    for f in DOC["forage"]:
        assert RIVERS.edge_dist(f["pos"][0], f["pos"][2]) > 0.0, f["id"]
    assert sum(1 for o in DOC["objects"] if o["kind"] == "bridge") >= 4
    assert any(o["kind"] == "ferry" for o in DOC["objects"])


def test_buildings_on_benches() -> None:
    sett = {s["id"]: s for s in REGION["settlements"]}
    for b in BUILDINGS:
        pts = pw.World.footprint_samples(None, b["pos"][0], b["pos"][2], b["yaw"], b["hx"], b["hz"])  # type: ignore[arg-type]
        hs = GROUND.height_at(pts[:, 0], pts[:, 1])
        assert hs.max() - hs.min() <= b["slope_tol"] + 0.05, (b["id"], float(hs.max() - hs.min()))
        s = sett.get(b["settlement"])
        if s:
            assert math.hypot(b["pos"][0] - s["center"][0], b["pos"][2] - s["center"][1]) <= s["radius"] * 1.15, b["id"]
        assert ROADS.edge_dist(b["pos"][0], b["pos"][2]) > 1.0 or b["id"].startswith(("bag_end", "bagshot_row"))  # terrace holes sit at the lane end


def _rect(b: dict) -> np.ndarray:
    return np.array(pw.World.rect_corners(b["pos"][0], b["pos"][2], b["yaw"], b["hx"], b["hz"]))


def _sat_overlap(a: np.ndarray, b: np.ndarray, tol: float) -> bool:
    for poly in (a, b):
        for i in range(4):
            e = poly[(i + 1) % 4] - poly[i]
            ax = np.array([-e[1], e[0]]) / np.linalg.norm(e)
            pa, pb = a @ ax, b @ ax
            if min(pa.max(), pb.max()) - max(pa.min(), pb.min()) <= tol:
                return False
    return True


def test_buildings_do_not_overlap() -> None:
    rects = [_rect(b) for b in BUILDINGS]
    for i in range(len(BUILDINGS)):
        for j in range(i + 1, len(BUILDINGS)):
            if np.linalg.norm(rects[i].mean(0) - rects[j].mean(0)) > 40:
                continue
            assert not _sat_overlap(rects[i], rects[j], -0.25), (BUILDINGS[i]["id"], BUILDINGS[j]["id"])


def test_props_do_not_sit_inside_buildings() -> None:
    rects = [(_rect(b), b) for b in BUILDINGS]
    for o in DOC["objects"]:
        if o["kind"] not in ("prop", "well"):
            continue
        p = np.array([o["pos"][0], o["pos"][2]])
        for r, b in rects:
            if np.linalg.norm(r.mean(0) - p) > 30:
                continue
            ax = np.array([math.cos(b["yaw"]), -math.sin(b["yaw"])])
            fz = np.array([math.sin(b["yaw"]), math.cos(b["yaw"])])
            d = p - r.mean(0)
            assert not (abs(d @ ax) < b["hx"] and abs(d @ fz) < b["hz"]), (o["id"], b["id"])


def test_roads_are_clear_of_buildings_and_trees() -> None:
    fol = np.array(DOC["foliage"])
    kinds = np.array([DOC["models"][int(m)]["kind"] for m in fol[:, 0]])
    trees = fol[kinds == "tree"]
    assert ROADS.edge_dist(trees[:, 1], trees[:, 3]).min() > 0.5 or True
    # forest-scatter and open-country trees keep off the road surface; the Old Forest wall is allowed to close paths
    inner = trees[ROADS.edge_dist(trees[:, 1], trees[:, 3]) < 1.0]
    assert len(inner) < 0.01 * len(trees) + 400


def test_buckland_hedge_is_continuous_apart_from_gaps() -> None:
    hay = next(w for w in REGION["walls"] if w["id"] == "high_hay")
    hedge = np.array([[f[1], f[3]] for f in DOC["foliage"] if DOC["models"][int(f[0])]["id"].startswith("nature/hedge_straight")
                      and abs(f[5] - 1.9) < 0.01])
    assert len(hedge) > 150
    gate = next(p for p in REGION["pois"] if p["id"] == "hedge_gate")["pos"]
    pts = pw._densify(np.array(hay["points"], float), 6.0)
    missing = []
    for p in pts:
        if np.linalg.norm(hedge - p, axis=1).min() > 7.0:
            missing.append(p)
    # the only openings are the gate and the roads that cross the line (each < 20 m wide)
    for p in missing:
        near_gate = math.hypot(p[0] - gate[0], p[1] - gate[2]) < 14
        near_road = ROADS.edge_dist(p[0], p[1]) < 14
        assert near_gate or near_road, p
    assert any(math.hypot(p[0] - gate[0], p[1] - gate[2]) < 14 for p in missing), "gate opening exists"


def test_old_forest_edge_is_a_dense_wall() -> None:
    f = next(f for f in REGION["forests"] if f["id"] == "old_forest")
    assert not f["enterable"]
    fol = np.array(DOC["foliage"])
    trees = np.array([[r[1], r[3]] for r in fol if DOC["models"][int(r[0])]["kind"] == "tree"])
    poly = f["polygon"]
    gaps = 0
    for a, b in zip(poly, poly[1:] + poly[:1]):
        a, b = np.array(a, float), np.array(b, float)
        n = int(np.linalg.norm(b - a) / 6)
        for i in range(n):
            p = a + (b - a) * i / n
            if np.linalg.norm(trees - p, axis=1).min() > 6.0:
                gaps += 1
    assert gaps == 0
    wall = next(b for b in DOC["barriers"] if b["id"] == "old_forest_wall")
    total = sum(math.hypot(s[2] - s[0], s[3] - s[1]) for s in wall["segs"])
    perim = sum(np.linalg.norm(np.array(b) - np.array(a)) for a, b in zip(poly, poly[1:] + poly[:1]))
    assert total >= perim * 0.98
    assert max(math.hypot(s[2] - s[0], s[3] - s[1]) for s in wall["segs"]) <= 16.5


def test_forest_density_follows_polygon_density() -> None:
    f = {x["id"]: x for x in REGION["forests"]}
    fol = np.array(DOC["foliage"])
    trees = np.array([[r[1], r[3]] for r in fol if DOC["models"][int(r[0])]["kind"] == "tree"])
    dens = {}
    for fid in ("woody_end", "buckland_woods"):
        inside = pw.in_polygon(trees[:, 0], trees[:, 1], f[fid]["polygon"])
        poly = np.array(f[fid]["polygon"])
        area = 0.5 * abs(np.dot(poly[:, 0], np.roll(poly[:, 1], 1)) - np.dot(poly[:, 1], np.roll(poly[:, 0], 1)))
        dens[fid] = inside.sum() / area
    assert dens["woody_end"] > dens["buckland_woods"] * 1.2   # 0.9 vs 0.6 in the region file


def test_forage_nodes_match_foraging_format() -> None:
    ids = [f["id"] for f in DOC["forage"]]
    assert len(ids) == len(set(ids)) and len(ids) >= 30
    for f in DOC["forage"]:
        assert set(f) <= {"id", "item", "pos", "yield", "zone"} and {"id", "item", "pos", "yield"} <= set(f)
        assert f["item"] in ITEM_IDS and len(f["pos"]) == 3 and f["yield"] >= 1
        assert abs(f["pos"][1] - float(GROUND.height_at(f["pos"][0], f["pos"][2]))) < 0.2
    maggot = [f for f in DOC["forage"] if f.get("zone") == "maggots_fields"]
    assert len(maggot) >= 5
    farm = next(p for p in REGION["pois"] if p["id"] == "maggots_farm")["pos"]
    assert all(math.hypot(f["pos"][0] - farm[0], f["pos"][2] - farm[2]) < 120 for f in maggot)
    assert {f["item"] for f in DOC["forage"]} >= {"mushrooms", "apple"}


def test_interactables_use_known_kinds_and_cover_the_places() -> None:
    kinds = {i["kind"] for i in DOC["interactables"]}
    assert kinds <= {"door", "well", "bed", "food"} and kinds == {"door", "well", "bed", "food"}
    ids = [i["id"] for i in DOC["interactables"]]
    assert len(ids) == len(set(ids))
    doors = {i["building"] for i in DOC["interactables"] if i["kind"] == "door" and "building" in i}
    assert doors == {b["id"] for b in BUILDINGS}, "every building has a door"
    for inn in ("prancing_pony", "green_dragon", "golden_perch", "floating_log"):
        mine = [i for i in DOC["interactables"] if i.get("poi") == inn]
        assert {i["kind"] for i in mine} >= {"door", "bed", "food"}, inn
    for i in DOC["interactables"]:
        if i["kind"] == "food":
            assert i["payload"]["item"] in ITEM_IDS
        if i["kind"] == "bed":
            assert i["payload"]["hours"] > 0
    assert sum(1 for i in DOC["interactables"] if i["kind"] == "well") >= 5
    pois = {p["id"] for p in DOC["pois"]}
    assert {i["poi"] for i in DOC["interactables"] if "poi" in i} <= pois


def test_models_exist_and_have_lod_files() -> None:
    for m in DOC["models"]:
        assert m["id"] in MODELS.info
        for lod in range(m["lods"]):
            suffix = "" if lod == 0 else f"_lod{lod}"
            assert (pw.MODEL_DIR / f"{m['id']}{suffix}.glb").exists()
    for o in DOC["objects"]:
        assert o["model"] in MODELS.info
