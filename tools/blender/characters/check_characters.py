"""Budget/contract check for game/assets/characters: every id in looks.json has a glb, triangle and size budgets hold,
and the baked animations carry the exact names the engine expects. Run from verify.sh."""
from __future__ import annotations

import json
import os
import struct
import sys

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
CHARS = os.path.join(REPO, "game", "assets", "characters")
MAX_TRIS = 4000
MAX_TOTAL_MB = 25
HUMAN = {"idle", "walk", "run", "sit", "talk_gesture", "crouch_walk", "sleep", "eat", "pick_up", "faint"}
RIDER = {"idle", "walk", "sniff"}


def glb_anims(path: str) -> set[str]:
    b = open(path, "rb").read()
    n = struct.unpack("<I", b[12:16])[0]
    return {a["name"] for a in json.loads(b[20:20 + n]).get("animations", [])}


def main() -> int:
    looks = json.load(open(os.path.join(REPO, "tools", "blender", "characters", "looks.json"), encoding="utf-8"))
    ids = list(looks["named"]) + list(looks["villagers"])
    bad = []
    total = 0
    for cid in ids:
        p = os.path.join(CHARS, f"{cid}.glb")
        if not os.path.exists(p):
            bad.append(f"{cid}: missing glb")
            continue
        total += os.path.getsize(p)
        want = RIDER if looks["named"].get(cid, {}).get("race") == "black_rider" else HUMAN
        got = glb_anims(p)
        if got != want:
            bad.append(f"{cid}: animations {sorted(got)} != {sorted(want)}")
    mf = json.load(open(os.path.join(CHARS, "manifest.json"), encoding="utf-8"))["characters"]
    for e in mf:
        if e["tris"] > MAX_TRIS:
            bad.append(f"{e['id']}: {e['tris']} tris > {MAX_TRIS}")
    if total > MAX_TOTAL_MB * 1024 * 1024:
        bad.append(f"total {total / 1048576:.1f} MB > {MAX_TOTAL_MB}")
    print("CHARACTERS_OK %d glbs, %.1f MB, max %d tris" % (len(ids), total / 1048576, max(e["tris"] for e in mf)) if not bad else "\n".join(bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
