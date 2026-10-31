"""Checks triangle budgets of the built .glb files (pure Python, no Blender; ~1 s).

  .venv/bin/python tools/blender/check_budget.py
Reads game/assets/models/*/manifest.json for asset kinds and counts triangles from the .glb itself
(visual meshes only: nodes with a Godot -col/-colonly/-convcol/-convcolonly suffix are collision shapes).
"""
from __future__ import annotations

import json
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MODELS = os.path.abspath(os.path.join(HERE, "..", "..", "game", "assets", "models"))


COL_SUFFIXES = ("-col", "-colonly", "-convcol", "-convcolonly")


def glb_tris(path: str) -> int:
    with open(path, "rb") as f:
        data = f.read()
    magic, _ver, _ln = struct.unpack_from("<III", data, 0)
    if magic != 0x46546C67:
        raise ValueError("not a glb")
    clen, ctype = struct.unpack_from("<II", data, 12)
    gltf = json.loads(data[20:20 + clen])
    col_nodes = {n.get("mesh") for n in gltf.get("nodes", []) if n.get("name", "").endswith(COL_SUFFIXES) and "mesh" in n}
    tris = 0
    for mi, mesh in enumerate(gltf.get("meshes", [])):
        if mi in col_nodes:
            continue
        for prim in mesh["primitives"]:
            acc = gltf["accessors"][prim["indices"]] if "indices" in prim else gltf["accessors"][prim["attributes"]["POSITION"]]
            tris += acc["count"] // 3
    return tris


def main() -> int:
    with open(os.path.join(HERE, "budgets.json"), encoding="utf-8") as f:
        bud = json.load(f)
    errors, n, total_bytes = [], 0, 0
    for cat in sorted(os.listdir(MODELS)):
        mp = os.path.join(MODELS, cat, "manifest.json")
        if not os.path.isfile(mp):
            continue
        with open(mp, encoding="utf-8") as f:
            assets = json.load(f)["assets"]
        for a in assets:
            limit = bud["kinds"].get(a["kind"])
            if limit is None:
                errors.append(f"{a['name']}: unknown kind {a['kind']}")
                continue
            counts = []
            for fn in a["files"]:
                p = os.path.join(MODELS, cat, fn)
                if not os.path.isfile(p):
                    errors.append(f"{a['name']}: missing {fn}")
                    continue
                total_bytes += os.path.getsize(p)
                counts.append(glb_tris(p))
            n += 1
            if not counts:
                continue
            if counts[0] > limit:
                errors.append(f"{a['name']}: LOD0 {counts[0]} tris > budget {limit} ({a['kind']})")
            if counts != a["tris"]:
                errors.append(f"{a['name']}: glb tris {counts} differ from manifest {a['tris']} (stale build?)")
            for i, c in enumerate(counts[1:], start=1):
                r = bud["lod_max_ratio"].get(str(i))
                if r and counts[0] >= bud["lod_min_tris_checked"] and c > counts[0] * r:
                    errors.append(f"{a['name']}: LOD{i} {c} tris > {r:.0%} of LOD0 {counts[0]}")
    mb = total_bytes / 1e6
    if mb > bud["total_size_mb"]:
        errors.append(f"total glb size {mb:.1f} MB > {bud['total_size_mb']} MB")
    for e in errors:
        print("BUDGET_FAIL", e)
    print(f"{'BUDGET_OK' if not errors else 'BUDGET_FAILED'}: {n} assets, {mb:.1f} MB")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
