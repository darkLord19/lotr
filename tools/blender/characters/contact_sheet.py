"""Contact sheet: every exported character glb imported back into Blender and rendered in T-pose and at walk frame 10.

  .venv/bin/python tools/blender/characters/contact_sheet.py [--only frodo,sam] [--pose=T,walk,eat] [--frame=10]
      [--size=420] [--span=2.6] [--focus=head] [--out=build/previews/characters_sheet.png]
Importing the exported .glb (not the source scene) means the sheet shows what the game gets, animation included.
Rendering uses Workbench under xvfb (software GL); workers run in parallel, one batch of characters each.
"""
from __future__ import annotations

import json
import math
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BLENDER_DIR = os.path.abspath(os.path.join(HERE, ".."))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
CHARS = os.path.join(REPO, "game", "assets", "characters")
TILES = os.path.join(REPO, "build", "previews", "characters")
FINAL = os.path.join(REPO, "docs", "reports", "m1_characters", "contact_sheet.png")
sys.path.insert(0, BLENDER_DIR)


def render_worker(ids: list[str], poses: list[str], frame: int, size: int, span: float, focus: str) -> None:
    import bpy
    from mathutils import Vector

    from lib import style

    os.makedirs(TILES, exist_ok=True)
    for cid in ids:
        for pose in poses:
            bpy.ops.wm.read_factory_settings(use_empty=True)
            sc = bpy.context.scene
            sc.render.engine = "BLENDER_WORKBENCH"
            sc.render.resolution_x = sc.render.resolution_y = size
            sh = sc.display.shading
            sh.light, sh.color_type, sh.show_shadows, sh.show_cavity = "STUDIO", "MATERIAL", True, False
            sh.shadow_intensity = 0.3
            sc.world = bpy.data.worlds.new("w")
            sc.world.color = style.to_linear("#c9d9ea")
            bpy.ops.import_scene.gltf(filepath=os.path.join(CHARS, f"{cid}.glb"))
            arm = next(o for o in sc.objects if o.type == "ARMATURE")
            # the importer leaves the last clip bound; start from rest, then bind the wanted clip
            arm.animation_data.action = None
            for pb in arm.pose.bones:
                pb.rotation_mode = "QUATERNION"
                pb.rotation_quaternion = (1, 0, 0, 0)
                pb.location = (0, 0, 0)
            if pose != "T":
                act = next((a for a in bpy.data.actions if a.name == pose or a.name.startswith(pose + "_")), None)
                if act is None:
                    print("NO_ACTION", cid, pose, [a.name for a in bpy.data.actions])
                else:
                    arm.animation_data.action = act
                    sc.frame_set(frame if pose in ("walk", "run", "crouch_walk") else int(act.frame_range[1] * 0.6))
            bpy.context.view_layer.update()
            meshes = [o for o in sc.objects if o.type == "MESH"]
            dg = bpy.context.evaluated_depsgraph_get()
            pts = []
            for o in meshes:
                ev = o.evaluated_get(dg)
                pts += [ev.matrix_world @ Vector(c) for c in ev.bound_box]
            zmax, zmin, cx, cy = max(p.z for p in pts), 0.0, 0.0, 0.0  # characters stand at the origin; skinned bound boxes are unreliable
            cam = bpy.data.cameras.new("c")
            cam.type = "ORTHO"
            ctr = Vector((cx, cy, span / 2 if focus == "full" else zmax - 0.15))
            cam.ortho_scale = span if focus == "full" else span * 0.4
            if focus == "full":
                ctr.z = zmin + span * 0.48
            co = bpy.data.objects.new("c", cam)
            sc.collection.objects.link(co)
            sc.camera = co
            face = _face_dir(meshes)
            side = Vector((-face.y, face.x, 0))
            d = (face * 0.82 + side * 0.45 + Vector((0, 0, 0.32))).normalized()
            co.location = ctr + d * 8
            co.rotation_euler = (ctr - co.location).to_track_quat("-Z", "Y").to_euler()
            sun = bpy.data.objects.new("s", bpy.data.lights.new("s", "SUN"))
            sc.collection.objects.link(sun)
            g = _ground(sc, cx, cy, zmin, span)
            sc.render.filepath = os.path.join(TILES, f"{cid}__{pose}.png")
            bpy.ops.render.render(write_still=True)
    print("TILES_DONE")


def _ground(sc, cx, cy, z, span):
    import bpy
    bpy.ops.mesh.primitive_circle_add(vertices=24, radius=span * 0.34, fill_type="NGON", location=(cx, cy, z - 0.002))
    g = bpy.context.object
    m = bpy.data.materials.new("g")
    m.diffuse_color = (0.30, 0.45, 0.2, 1)
    g.data.materials.append(m)
    return g


def _face_dir(meshes):
    """Direction the character faces in the imported scene (glTF -Z maps to Blender +Y): read it off the eye boxes' centroid vs the head."""
    from mathutils import Vector
    return Vector((0, 1, 0))


def compose(ids: list[str], poses: list[str], size: int, out: str, cols: int, labels: dict[str, str]) -> str:
    from PIL import Image, ImageDraw, ImageFont

    rows = math.ceil(len(ids) / cols)
    cw, lab = size * len(poses), 22
    sheet = Image.new("RGB", (cols * cw, rows * (size + lab)), (28, 28, 32))
    dr = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 14)
    except OSError:
        font = ImageFont.load_default()
    for i, cid in enumerate(ids):
        cx, cy = i % cols, i // cols
        for j, pose in enumerate(poses):
            p = os.path.join(TILES, f"{cid}__{pose}.png")
            if os.path.exists(p):
                sheet.paste(Image.open(p).convert("RGB"), (cx * cw + j * size, cy * (size + lab) + lab))
        dr.text((cx * cw + 6, cy * (size + lab) + 3), labels.get(cid, cid), fill=(240, 236, 220), font=font)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    sheet.save(out)
    return out


def run(only: list[str] | None = None, poses: list[str] | None = None, frame: int = 10, size: int = 420, span: float = 2.6,
        focus: str = "full", out: str | None = None, workers: int = 4) -> int:
    from runner import blender_env

    with open(os.path.join(CHARS, "manifest.json"), encoding="utf-8") as f:
        mf = json.load(f)["characters"]
    ids = [c["id"] for c in mf if not only or c["id"] in only]
    poses = poses or ["T", "walk"]
    labels = {c["id"]: f"{c['id']}  {c['height_m']:.2f} m  {c['tris']} tris" for c in mf}
    env = blender_env()
    pre = ["xvfb-run", "-a"] if not os.environ.get("DISPLAY") and shutil.which("xvfb-run") else []
    shutil.rmtree(TILES, ignore_errors=True)
    procs = []
    for w in range(workers):
        part = ids[w::workers]
        if not part:
            continue
        cmd = pre + ["blender", "-b", "-noaudio", "-P", os.path.join(HERE, "contact_sheet.py"), "--", f"--render={','.join(part)}",
                     f"--pose={','.join(poses)}", f"--frame={frame}", f"--size={size}", f"--span={span}", f"--focus={focus}"]
        procs.append(subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, env=env))
    for p in procs:
        o = p.communicate()[0]
        if p.returncode or "TILES_DONE" not in o:
            print(o[-3000:])
            return 1
        for l in o.splitlines():
            if l.startswith("NO_ACTION"):
                print(l)
    dest = out or FINAL
    cols = min(len(ids), 5 if len(poses) == 2 else max(1, 5 // len(poses)))
    print(compose(ids, poses, size, dest, cols, labels))
    return 0


def _args(argv: list[str]) -> dict[str, str]:
    return {k: v for k, _, v in (x[2:].partition("=") for x in argv if x.startswith("--"))}


def main() -> int:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    a = _args(argv)
    try:
        import bpy  # noqa: F401
        have = True
    except ImportError:
        have = False
    if have:
        render_worker(a["render"].split(","), a["pose"].split(","), int(a["frame"]), int(a["size"]), float(a["span"]), a["focus"])
        return 0
    return run(a["only"].split(",") if "only" in a else None, a["pose"].split(",") if "pose" in a else None, int(a.get("frame", 10)),
               int(a.get("size", 420)), float(a.get("span", 2.6)), a.get("focus", "full"),
               os.path.abspath(a["out"]) if "out" in a else None, int(a.get("workers", 4)))


if __name__ == "__main__":
    sys.exit(main())
