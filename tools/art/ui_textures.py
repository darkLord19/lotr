#!/usr/bin/env python3
"""UI textures with the same mflux Z-Image-Turbo setup as portraits.py -> game/assets/ui/.
parchment / journal_page / inventory_panel are text-to-image; region_map is image-to-image from the control map.
Usage: .venv-art/bin/python tools/art/ui_textures.py [name ...]   (needs build/art/zimage-q4, see portraits.py)
"""
import subprocess
import sys
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/terrain"))
OUT = ROOT / "game/assets/ui"
MODEL = ROOT / "build/art/zimage-q4"
NO_TEXT = "no text, no letters, no writing, no figures"
JOBS = {
    "parchment": dict(size=(1024, 1024), prompt=f"gouache illustration style flat texture, aged cream parchment paper with soft warm stains, faint fibres and gently darkened edges, empty, {NO_TEXT}"),
    "journal_page": dict(size=(768, 1024), prompt=f"gouache illustration style, an open blank page of an old traveller's journal on aged cream paper, a thin brown ink border with small leaf flourishes in the corners, empty centre, {NO_TEXT}"),
    "inventory_panel": dict(size=(1024, 768), prompt=f"gouache illustration style, a worn leather satchel panel background, dark warm brown stitched leather with brass studs along the border and an empty centre, {NO_TEXT}"),
    "region_map": dict(size=(2048, 1024), image=ROOT / "build/art/map_reference.png", strength=0.55,
                       prompt=f"hand-drawn illustrated fantasy map on aged parchment, gouache and ink, rolling green fields, little hills, a winding blue river, a brown road running left to right, dark forests drawn as clusters of small trees, small village houses along the road, soft warm colours, {NO_TEXT}, no labels"),
}


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    import check_region as cr  # noqa: E402  (tools/terrain)
    import render_control_map as rcm  # noqa: E402
    ref = JOBS["region_map"]["image"]
    ref.parent.mkdir(parents=True, exist_ok=True)
    rcm.render(cr.load_region(), labels=False).save(ref)
    for name in sys.argv[1:] or JOBS:
        j = JOBS[name]
        w, h = j["size"]
        dest = OUT / f"{name}.png"
        dest.unlink(missing_ok=True)
        cmd = [str(ROOT / ".venv-art/bin/mflux-generate-z-image-turbo"), "--model", str(MODEL), "--prompt", j["prompt"], "--steps", "8",
               "--seed", str(zlib.crc32(name.encode()) % 1_000_000), "--width", str(w), "--height", str(h), "--output", str(dest)]
        if "image" in j:
            cmd += ["--image-path", str(j["image"]), "--image-strength", str(j["strength"])]
        print(name, flush=True)
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode != 0:
            print(f"FAILED {name}: {r.stderr[-400:]}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
