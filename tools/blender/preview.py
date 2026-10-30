"""Contact sheets: one PNG per category (and an LOD strip) in build/previews/.

  .venv/bin/python tools/blender/preview.py [--only nature,shire] [--final]   # launcher (needs xvfb-run on a headless box)
  blender -b -P tools/blender/preview.py -- --tiles nature                    # worker: renders one 384px tile per LOD0 .glb
--final also copies the sheets to docs/reports/m1_style/.
"""
from __future__ import annotations

import json
import math
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
MODELS = os.path.join(REPO, "game", "assets", "models")
OUT = os.path.join(REPO, "build", "previews")
TILE = 384
CATEGORIES = ["nature", "shire", "bree", "props"]


def lod_sample(assets: list[dict]) -> list[dict]:
    """Eight evenly spaced assets that have LODs; only these get LOD tiles (software GL is ~2.5 s per tile)."""
    withl = [a for a in assets if len(a["files"]) > 1]
    step = max(1, len(withl) // 8)
    return withl[::step][:8]


def render_tiles(cat: str) -> None:
    import bpy
    from mathutils import Vector

    sys.path.insert(0, HERE)
    from lib import style

    with open(os.path.join(MODELS, cat, "manifest.json"), encoding="utf-8") as f:
        assets = json.load(f)["assets"]
    region = "bree" if cat == "bree" else "shire"
    tdir = os.path.join(OUT, "tiles", cat)
    os.makedirs(tdir, exist_ok=True)
    sampled = {a["name"] for a in lod_sample(assets)}
    for a in assets:
        for lod, fn in enumerate(a["files"]):
            if lod > 0 and a["name"] not in sampled:
                continue
            bpy.ops.wm.read_factory_settings(use_empty=True)
            sc = bpy.context.scene
            sc.render.engine = "BLENDER_WORKBENCH"
            sc.render.resolution_x = sc.render.resolution_y = TILE
            sc.render.film_transparent = False
            sh = sc.display.shading
            sh.light, sh.color_type, sh.show_shadows, sh.show_cavity = "STUDIO", "MATERIAL", True, False
            sh.shadow_intensity = 0.35
            sh.studio_light = "Default"
            sc.display.shading.background_type = "WORLD"
            sc.world = bpy.data.worlds.new("w")
            sc.world.color = style.to_linear("#cfe0f0" if region == "shire" else "#c4c8cc")
            bpy.ops.import_scene.gltf(filepath=os.path.join(MODELS, cat, fn))
            meshes = [o for o in bpy.context.scene.objects if o.type == "MESH" and "-col" not in o.name and "_col" not in o.name]
            for o in bpy.context.scene.objects:
                if "_col-" in o.name or o.name.endswith("colonly"):
                    o.hide_render = True
            pts = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
            lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
            hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
            ctr, size = (lo + hi) / 2, hi - lo
            radius = max(size.length / 2, 0.05)
            # ground disc
            bpy.ops.mesh.primitive_circle_add(vertices=24, radius=radius * 1.5, fill_type="NGON", location=(ctr.x, ctr.y, lo.z - 0.001))
            g = bpy.context.object
            mat = bpy.data.materials.new("g")
            gc = style.ramp(region, "grass")[1] if region == "shire" else style.ramp(region, "grass_alt")[1]
            mat.diffuse_color = (*style.to_linear(gc), 1)
            g.data.materials.append(mat)
            cam = bpy.data.cameras.new("c")
            cam.angle = math.radians(32)
            co = bpy.data.objects.new("c", cam)
            sc.collection.objects.link(co)
            sc.camera = co
            d = Vector((-0.62, -0.78, 0.5)).normalized()
            dist = radius / math.sin(cam.angle / 2) * 1.05
            co.location = ctr + d * dist
            co.rotation_euler = (ctr - co.location).to_track_quat("-Z", "Y").to_euler()
            sc.render.filepath = os.path.join(tdir, os.path.splitext(fn)[0] + ".png")
            bpy.ops.render.render(write_still=True)
    print(f"TILES_DONE {cat}")


def compose(cat: str, lods: bool = False) -> str:
    from PIL import Image, ImageDraw, ImageFont

    with open(os.path.join(MODELS, cat, "manifest.json"), encoding="utf-8") as f:
        assets = json.load(f)["assets"]
    if lods:
        assets = lod_sample(assets)
    cols_per_asset = 3 if lods else 1
    n = len(assets)
    cols = 2 if lods else min(6, max(1, math.ceil(math.sqrt(n * 1.5))))
    rows = math.ceil(n / cols)
    tw, th = TILE // 2 if not lods else TILE // 2, TILE // 2
    tw = th = int(TILE * (0.62 if not lods else 0.5))
    W, H = cols * cols_per_asset * tw, rows * (th + 26)
    sheet = Image.new("RGB", (W, H), (30, 30, 34))
    dr = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 13)
    except OSError:
        font = ImageFont.load_default()
    for i, a in enumerate(assets):
        cx, cy = i % cols, i // cols
        for l in range(cols_per_asset):
            fn = os.path.splitext(a["files"][l])[0] + ".png"
            p = os.path.join(OUT, "tiles", cat, fn)
            if os.path.exists(p):
                im = Image.open(p).convert("RGB").resize((tw, th), Image.LANCZOS)
                sheet.paste(im, ((cx * cols_per_asset + l) * tw, cy * (th + 26) + 26))
        sx, sy, sz = a["size_m"]
        label = f"{a['name']}  {sx:.1f}x{sy:.1f}x{sz:.1f}m  tris {'/'.join(str(t) for t in a['tris'])}"
        dr.text((cx * cols_per_asset * tw + 4, cy * (th + 26) + 5), label, fill=(235, 235, 220), font=font)
    out = os.path.join(OUT, f"{cat}{'_lods' if lods else ''}.png")
    sheet.save(out)
    return out


def main() -> int:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    a = {k: v for k, _, v in (x[2:].partition("=") for x in argv if x.startswith("--"))}
    try:
        import bpy  # noqa: F401
        have = True
    except ImportError:
        have = False
    if have:
        render_tiles(a["tiles"])
        return 0
    sys.path.insert(0, HERE)
    from runner import blender_env
    env = blender_env()
    only = a["only"].split(",") if "only" in a else CATEGORIES
    pre = ["xvfb-run", "-a"] if not os.environ.get("DISPLAY") and shutil.which("xvfb-run") else []
    procs = []
    for cat in only:
        procs.append(subprocess.Popen(pre + ["blender", "-b", "-noaudio", "-P", os.path.join(HERE, "preview.py"), "--", f"--tiles={cat}"],
                                      stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, env=env))
    for cat, p in zip(only, procs):
        out = p.communicate()[0]
        if p.returncode or "TILES_DONE" not in out:
            print(out[-2000:])
            return 1
    outs = []
    for cat in only:
        outs.append(compose(cat))
        outs.append(compose(cat, lods=True))
    print("\n".join(outs))
    if "final" in a:
        dst = os.path.join(REPO, "docs", "reports", "m1_style")
        os.makedirs(dst, exist_ok=True)
        for o in outs:
            shutil.copy(o, dst)
    return 0


if __name__ == "__main__":
    sys.exit(main())
