"""Procedural rigged low-poly humanoids -> game/assets/characters/<id>.glb (one per named NPC + one per villager base).

Fallback for the Quaternius packs (not downloadable in the sandbox, PLAN §8): body, clothes, hair and a 17-bone
armature are modelled from code, weights are assigned by position, and animations are keyframed procedurally
(characters/anims.py) and exported as separate glTF animations with fixed names.

  .venv/bin/python tools/blender/characters/build_bases.py [--only frodo,sam] [--no-sheet]   # launcher
  blender -b -P tools/blender/characters/build_bases.py -- --only frodo                       # in-process
Outputs: game/assets/characters/<id>.glb, manifest.json (tris, size, natural speeds, anims), and the contact
sheet docs/reports/m1_characters/contact_sheet.png (needs xvfb for the software-GL render).
"""
from __future__ import annotations

import json
import os
import random
import subprocess
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
BLENDER_DIR = os.path.abspath(os.path.join(HERE, ".."))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
OUT = os.path.join(REPO, "game", "assets", "characters")
sys.path.insert(0, BLENDER_DIR)


def load_json(name: str) -> dict:
    with open(os.path.join(HERE, name), encoding="utf-8") as f:
        return json.load(f)


def resolve_race(races: dict, name: str) -> dict:
    name = races["aliases"].get(name, name)
    return races["races"][name]


def all_looks(looks: dict) -> dict[str, dict]:
    """id -> look dict. Villager bases take the first palette value of each role."""
    out = dict(looks["named"])
    for vid, v in looks["villagers"].items():
        look = {k: val for k, val in v.items() if k != "palettes"}
        look["colors"] = {role: vals[0] for role, vals in v["palettes"].items()}
        look["villager"] = True
        out[vid] = look
    return out


def build_one(cid: str, look: dict, races: dict) -> dict:
    import bpy

    from characters import anims, body, outfits
    from characters.rig import Dims, Skin, bind, make_armature
    from lib import style

    bpy.ops.wm.read_factory_settings(use_empty=True)
    race_name = look["race"]
    race = resolve_race(races, race_name)
    d = Dims(race, look)
    rng = random.Random(zlib.crc32(cid.encode()))
    s = Skin()
    body.build_body(s, d, look, rng)
    body.build_hair(s, d, look, rng)
    body.build_beard(s, d, look, rng)
    body.build_hat(s, d, look)
    for piece in look["pieces"]:
        outfits.add_piece(s, d, piece, look, rng)

    colors = _colors(look)
    mats = {}
    for role in sorted(set(s.fm)):
        mats[role] = _material(role, colors.get(role, "#ff00ff"), role in outfits.DOUBLE_SIDED)
    mesh = s.to_object(cid, mats)
    arm = make_armature(f"{cid}_rig", d)
    bind(mesh, arm)
    style_anim = dict(race.get("anim", {}))
    names = anims.RIDER_CLIPS if style_anim.get("rider") else anims.HUMAN_CLIPS
    anims.build_actions(arm, d, style_anim, names)

    path = os.path.join(OUT, f"{cid}.glb")
    os.makedirs(OUT, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    mesh.select_set(True)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True, export_yup=True, export_apply=False,
        export_materials="EXPORT", export_normals=True, export_texcoords=False, export_cameras=False, export_lights=False,
        export_skins=True, export_animations=True, export_animation_mode="ACTIONS", export_frame_range=False,
        export_force_sampling=True, export_optimize_animation_size=True, export_extras=False)
    tris = sum(len(p.vertices) - 2 for p in mesh.data.polygons)
    return {"id": cid, "file": f"{cid}.glb", "race": race_name, "villager": bool(look.get("villager")),
            "tris": tris, "height_m": round(d.head_top, 3), "anims": names, "bytes": os.path.getsize(path),
            "natural_speed": {k: round(v, 2) for k, v in anims.natural_speeds(d, style_anim).items()},
            "foot_to_hip_m": round(d.hip_z, 3)}


def _colors(look: dict) -> dict[str, str]:
    from lib import style
    c = dict(look.get("colors", {}))
    skin = c.get("skin", "#e8b98e")
    hair = c.get("hair", "#3a2a1a")
    defaults = {"skin": skin, "hand": skin, "hair": hair, "brow": hair, "beard": hair, "foot_hair": hair,
                "eye": "#17120e", "mouth": style.mix(skin, "#6a2a22", 0.45), "hat": "#6a5a40", "hat_band": style.shade(c.get("hat", "#6a5a40"), 0.6),
                "shirt": "#d8cfb0", "vest": "#3d6a48", "jerkin": "#6a4a34", "pants": "#5a4a34", "apron": "#d8cfb0", "dress": "#8a4a3a",
                "cloak": "#4a5a42", "robe": "#15151a", "robe2": "#0b0b0e", "void": "#020203", "shoe": "#3a2c20", "belt": "#3a2a1c",
                "trim": "#c8a038", "metal": "#9a9a9a"}
    defaults.update(c)
    return defaults


def _material(role: str, hexc: str, double_sided: bool):
    import bpy
    from lib import style

    mat = bpy.data.materials.new(role)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    lin = style.to_linear(hexc)
    bsdf.inputs["Base Color"].default_value = (lin[0], lin[1], lin[2], 1.0)
    bsdf.inputs["Roughness"].default_value = 1.0
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.0
    mat.diffuse_color = (lin[0], lin[1], lin[2], 1.0)
    mat.use_backface_culling = not double_sided
    return mat


def build(ids: list[str] | None) -> int:
    races = load_json("races.json")
    looks = all_looks(load_json("looks.json"))
    entries, failed = [], 0
    import traceback
    for cid, look in looks.items():
        if ids and cid not in ids:
            continue
        try:
            e = build_one(cid, look, races)
            entries.append(e)
            print(f"BUILT {cid}: {e['tris']} tris, {e['bytes'] // 1024} KB, {e['height_m']} m")
        except Exception:
            failed += 1
            print(f"BUILD_FAIL {cid}")
            traceback.print_exc()
    if entries and not ids:
        os.makedirs(OUT, exist_ok=True)
        with open(os.path.join(OUT, "manifest.json"), "w", encoding="utf-8") as f:
            # villager palettes ride along so the engine can randomise colours per spawn without reading tools/
            pal = {k: v["palettes"] for k, v in load_json("looks.json")["villagers"].items()}
            json.dump({"characters": sorted(entries, key=lambda e: e["id"]), "villager_palettes": pal}, f, indent=1)
            f.write("\n")
    return failed


def _args(argv: list[str]) -> dict[str, str]:
    out = {}
    for a in argv:
        if a.startswith("--"):
            k, _, v = a[2:].partition("=")
            out[k] = v or "true"
    return out


def main() -> int:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    a = _args(argv)
    ids = a["only"].split(",") if "only" in a else None
    try:
        import bpy  # noqa: F401
        have = True
    except ImportError:
        have = False
    if have:
        return 1 if build(ids) else 0
    from runner import blender_env
    env = blender_env()
    cmd = ["blender", "-b", "-noaudio", "-P", os.path.join(HERE, "build_bases.py"), "--"] + ([f"--only={a['only']}"] if ids else [])
    p = subprocess.run(cmd, env=env, capture_output=True, text=True)
    lines = [l for l in p.stdout.splitlines() if l.startswith(("BUILT", "BUILD_FAIL")) or "Error" in l or l.startswith(("Traceback", "  File"))]
    print("\n".join(lines))
    if p.returncode or "BUILD_FAIL" in p.stdout:
        print(p.stdout[-3000:], p.stderr[-2000:])
        return 1
    if "no-sheet" not in a:
        sys.path.insert(0, HERE)
        import contact_sheet
        return contact_sheet.run(ids)
    return 0


if __name__ == "__main__":
    sys.exit(main())
