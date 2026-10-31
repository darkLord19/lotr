"""Checks the eriador_west road graph against the itineraries (M1-T02)."""
from __future__ import annotations

import heapq
import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REGION = ROOT / "game/content/regions/eriador_west.json"
ITINERARIES = ROOT / "game/content/timeline/itineraries"
WALK_SPEED = 1.4  # m/s
# Roads wind; edges are chords between POIs, so lengthen them to real path length.
WINDING = {"road": 1.10, "path": 1.20, "bridge": 1.0, "ferry": 1.0}
MIN_MINUTES, MAX_MINUTES = 60.0, 110.0


def load_region(path: Path = REGION) -> dict:
    return json.loads(path.read_text())


def edge_length(region: dict, a: str, b: str, kind: str) -> float:
    pos = {p["id"]: p["pos"] for p in region["pois"]}
    d = math.hypot(pos[a][0] - pos[b][0], pos[a][2] - pos[b][2])
    return d * WINDING.get(kind, 1.0)


def adjacency(region: dict) -> dict[str, list[tuple[str, float]]]:
    adj: dict[str, list[tuple[str, float]]] = {n: [] for n in region["road_graph"]["nodes"]}
    for a, b, kind in region["road_graph"]["edges"]:
        w = edge_length(region, a, b, kind)
        adj[a].append((b, w))
        adj[b].append((a, w))
    return adj


def shortest(region: dict, src: str, dst: str) -> float:
    """Dijkstra distance in metres, inf if unreachable."""
    adj = adjacency(region)
    dist = {src: 0.0}
    heap = [(0.0, src)]
    while heap:
        d, n = heapq.heappop(heap)
        if n == dst:
            return d
        if d > dist.get(n, math.inf):
            continue
        for m, w in adj.get(n, []):
            if d + w < dist.get(m, math.inf):
                dist[m] = d + w
                heapq.heappush(heap, (d + w, m))
    return math.inf


def itinerary_pois(directory: Path = ITINERARIES) -> dict[str, set[str]]:
    out: dict[str, set[str]] = {}
    for f in sorted(directory.glob("*.json")):
        data = json.loads(f.read_text())
        for s in data["steps"]:
            for key in ("from", "to", "at_poi"):
                if s.get(key):
                    out.setdefault(s[key], set()).add(data["character"])
    return out


def check(region: dict, itins: dict[str, set[str]], hub: str = "bag_end") -> list[str]:
    errors: list[str] = []
    pois = {p["id"]: p for p in region["pois"]}
    for poi, who in sorted(itins.items()):
        if poi not in pois:
            errors.append(f"{poi}: unknown POI used by {sorted(who)}")
        elif pois[poi].get("abstract"):
            continue
        elif math.isinf(shortest(region, hub, poi)):
            errors.append(f"{poi}: unreachable from {hub} (used by {sorted(who)})")
    for p in region["pois"]:
        x, _, z = p["pos"]
        if not (0 <= x <= region["size_m"][0] and 0 <= z <= region["size_m"][1]):
            errors.append(f"{p['id']}: outside region bounds")
    settlement_ids = {s["id"] for s in region["settlements"]}
    for s in region["settlements"]:
        if not s.get("faction"):
            errors.append(f"settlement {s['id']}: no faction")
    for p in region["pois"]:
        if p.get("settlement") and p["settlement"] not in settlement_ids:
            errors.append(f"{p['id']}: unknown settlement")
    return errors


def walk_minutes(region: dict, a: str = "bag_end", b: str = "prancing_pony") -> float:
    return shortest(region, a, b) / WALK_SPEED / 60.0


def main() -> int:
    region = load_region()
    itins = itinerary_pois()
    errors = check(region, itins)
    metres = shortest(region, "bag_end", "prancing_pony")
    minutes = walk_minutes(region)
    print(f"itinerary POIs checked: {len(itins)}")
    print(f"Bag End -> Prancing Pony: {metres:.0f} m, {minutes:.1f} min at {WALK_SPEED} m/s")
    if not MIN_MINUTES <= minutes <= MAX_MINUTES:
        errors.append(f"walking time {minutes:.1f} min outside {MIN_MINUTES:.0f}-{MAX_MINUTES:.0f}")
    for e in errors:
        print("ERROR", e)
    print("REGION_OK" if not errors else "REGION_FAILED")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
