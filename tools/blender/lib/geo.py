"""Low-poly geometry builder, materials, LOD generation, collision and glTF export (Blender 4.0).

Conventions: 1 Blender unit = 1 m, +Z up, building fronts face -Y (Blender front view). The glTF exporter
converts to Y-up so fronts face +Z in Godot. Everything is flat shaded; one mesh per asset with one
material slot per palette colour. Collision is added as child objects named `<asset>_col-convcolonly`
(convex) or `-colonly` (trimesh), which Godot's importer turns into StaticBody3D shapes.
"""
from __future__ import annotations

import contextlib
import json
import math
import os
import random

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

from . import style

REPO = style.REPO
MODEL_ROOT = os.path.join(REPO, "game", "assets", "models")
LOD_RATIOS = (1.0, 0.4, 0.15)

MatKey = tuple  # (hex, emission_strength, double_sided)


def m(hex_: str, emit: float = 0.0, ds: bool = False) -> MatKey:
    return (hex_.lower(), float(emit), bool(ds))


def _norm(mat) -> MatKey:
    return m(mat) if isinstance(mat, str) else tuple(mat)


_MAT_CACHE: dict[MatKey, bpy.types.Material] = {}


def get_material(key: MatKey) -> bpy.types.Material:
    mat = _MAT_CACHE.get(key)
    if mat is not None and mat.name in bpy.data.materials:
        return mat
    hex_, emit, ds = key
    mat = bpy.data.materials.new("m_%s%s%s" % (hex_.lstrip("#"), "_e" if emit else "", "_ds" if ds else ""))
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    lin = style.to_linear(hex_)
    bsdf.inputs["Base Color"].default_value = (lin[0], lin[1], lin[2], 1.0)
    bsdf.inputs["Roughness"].default_value = 1.0
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.0
    if emit > 0:
        bsdf.inputs["Emission Color"].default_value = (lin[0], lin[1], lin[2], 1.0)
        bsdf.inputs["Emission Strength"].default_value = emit
    mat.diffuse_color = (lin[0], lin[1], lin[2], 1.0)
    mat.use_backface_culling = not ds
    _MAT_CACHE[key] = mat
    return mat


def reset_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _MAT_CACHE.clear()


class Builder:
    """Accumulates primitives into one bmesh (visual) and one for collision."""

    def __init__(self, name: str, seed: int = 0):
        self.name = name
        self.rng = random.Random(seed)
        self.bm = bmesh.new()
        self.col_bm = bmesh.new()
        self.col_kind = "convcolonly"
        self.mats: list[MatKey] = []
        self._stack: list[Matrix] = [Matrix.Identity(4)]
        self._target = self.bm
        self._is_col = False

    # --- plumbing -----------------------------------------------------------------------------
    def _mi(self, mat) -> int:
        k = _norm(mat)
        if k not in self.mats:
            self.mats.append(k)
        return self.mats.index(k)

    def _emit(self, verts, mat, local: Matrix) -> None:
        full = self._stack[-1] @ local
        bmesh.ops.transform(self._target, matrix=full, verts=verts)
        if not self._is_col:
            idx = self._mi(mat)
            faces = {f for v in verts if v.is_valid for f in v.link_faces}
            for f in faces:
                f.material_index = idx
        # Mirrored transforms flip winding; fix so normals still point out.
        if full.determinant() < 0:
            faces = list({f for v in verts if v.is_valid for f in v.link_faces})
            bmesh.ops.reverse_faces(self._target, faces=faces)

    @contextlib.contextmanager
    def at(self, loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
        """Group transform: everything built inside is placed relative to loc/rot/scale."""
        mat = Matrix.Translation(loc) @ Euler(rot, "XYZ").to_matrix().to_4x4() @ Matrix.Diagonal((*scale, 1.0))
        self._stack.append(self._stack[-1] @ mat)
        try:
            yield
        finally:
            self._stack.pop()

    @contextlib.contextmanager
    def collision(self, kind: str = "convcolonly"):
        """Primitives built inside go to the collision mesh instead of the visual one."""
        self._target, self._is_col, self.col_kind = self.col_bm, True, kind
        try:
            yield
        finally:
            self._target, self._is_col = self.bm, False

    @staticmethod
    def _local(loc, rot, extra=None) -> Matrix:
        mt = Matrix.Translation(loc) @ Euler(rot, "XYZ").to_matrix().to_4x4()
        return mt if extra is None else mt @ extra

    # --- primitives ---------------------------------------------------------------------------
    def box(self, center, size, mat=None, rot=(0, 0, 0), top=None):
        """Axis box centred at `center`. `top=(fx, fy)` scales the top face (taper)."""
        verts = bmesh.ops.create_cube(self._target, size=1.0)["verts"]
        for v in verts:
            if top is not None and v.co.z > 0:
                v.co.x *= top[0]
                v.co.y *= top[1]
            v.co.x *= size[0]
            v.co.y *= size[1]
            v.co.z *= size[2]
        self._emit(verts, mat, self._local(center, rot))

    def slab(self, p0, p1, mat=None, rot=(0, 0, 0)):
        c = ((p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2, (p0[2] + p1[2]) / 2)
        self.box(c, (abs(p1[0] - p0[0]), abs(p1[1] - p0[1]), abs(p1[2] - p0[2])), mat, rot)

    def cyl(self, base, r, h, mat=None, seg=8, top_r=None, rot=(0, 0, 0), cap_top=True):
        """Cylinder/cone frustum standing on `base` (rot about base)."""
        res = bmesh.ops.create_cone(self._target, cap_ends=True, cap_tris=False, segments=seg,
                                    radius1=r, radius2=r if top_r is None else top_r, depth=h)
        verts = res["verts"]
        self._emit(verts, mat, self._local(base, rot, Matrix.Translation((0, 0, h / 2))))

    def cone(self, base, r, h, mat=None, seg=8, rot=(0, 0, 0)):
        self.cyl(base, r, h, mat, seg, top_r=0.0, rot=rot)

    def between(self, p0, p1, r, mat=None, seg=6, top_r=None):
        """Cylinder from p0 to p1."""
        a, b = Vector(p0), Vector(p1)
        d = b - a
        quat = Vector((0, 0, 1)).rotation_difference(d.normalized())
        eul = quat.to_euler("XYZ")
        self.cyl(tuple(a), r, d.length, mat, seg, top_r=top_r, rot=tuple(eul))

    def beam(self, p0, p1, w, t, mat=None):
        """Rectangular beam between two points (w x t cross-section)."""
        a, b = Vector(p0), Vector(p1)
        d = b - a
        quat = Vector((0, 0, 1)).rotation_difference(d.normalized())
        mid = (a + b) / 2
        self.box(tuple(mid), (w, t, d.length), mat, rot=tuple(quat.to_euler("XYZ")))

    def blob(self, center, radii, mat=None, sub=1, jitter=0.15, rot=(0, 0, 0)):
        """Jittered icosphere (leaf clumps, boulders, bushes)."""
        r = bmesh.ops.create_icosphere(self._target, subdivisions=sub + 1, radius=1.0)
        verts = r["verts"]
        for v in verts:
            f = 1.0 + self.rng.uniform(-jitter, jitter)
            v.co.x *= radii[0] * f
            v.co.y *= radii[1] * f
            v.co.z *= radii[2] * f
        self._emit(verts, mat, self._local(center, rot))

    def dome(self, center, radii, mat=None, seg=12, rings=6, jitter=0.0):
        """Upper half of an ellipsoid (hills, haystacks, round roofs). Open at the bottom."""
        r = bmesh.ops.create_uvsphere(self._target, u_segments=seg, v_segments=rings * 2, radius=1.0)
        verts = r["verts"]
        kill = [v for v in verts if v.co.z < -1e-4]
        bmesh.ops.delete(self._target, geom=kill, context="VERTS")
        keep = [v for v in verts if v.is_valid]
        for v in keep:
            f = 1.0 + (self.rng.uniform(-jitter, jitter) if jitter and v.co.z > 0.01 else 0.0)
            v.co.x *= radii[0] * f
            v.co.y *= radii[1] * f
            v.co.z *= radii[2] * f
        self._emit(keep, mat, self._local(center, (0, 0, 0)))

    def prism(self, pts, length, mat=None, loc=(0, 0, 0), rot=(0, 0, 0), flip=False):
        """Closed extrusion of an XZ profile along local Y (centred on y=0). Profile may be concave."""
        bm = self._target
        y0, y1 = -length / 2, length / 2
        front = [bm.verts.new((x, y0, z)) for x, z in pts]
        back = [bm.verts.new((x, y1, z)) for x, z in pts]
        faces = [bm.faces.new(front), bm.faces.new(back[::-1])]
        n = len(pts)
        for i in range(n):
            j = (i + 1) % n
            faces.append(bm.faces.new((front[i], front[j], back[j], back[i])))
        bmesh.ops.recalc_face_normals(bm, faces=faces)
        self._emit(front + back, mat, self._local(loc, rot))

    def poly(self, pts3, mat=None, loc=(0, 0, 0), rot=(0, 0, 0)):
        """Single flat polygon from 3D points (blades, cards)."""
        bm = self._target
        vs = [bm.verts.new(p) for p in pts3]
        bm.faces.new(vs)
        self._emit(vs, mat, self._local(loc, rot))

    def gable(self, x0, y0, x1, y1, z, rise, wall, roof, overhang=0.3, thick=0.14, ridge="x", gable_wall=True):
        """Gable roof over the rectangle (x0,y0)-(x1,y1) with eaves at height z, ridge `rise` higher.
        Adds a triangular gable infill in `wall` colour and a chevron roof slab in `roof` colour."""
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        if ridge == "x":
            span, length, rz = (y1 - y0), (x1 - x0), math.pi / 2
        else:
            span, length, rz = (x1 - x0), (y1 - y0), 0.0
        hw = span / 2
        o = overhang
        zE = z - rise * o / hw
        zR = z + rise
        if gable_wall:
            self.prism([(-hw, z), (hw, z), (0, zR)], length - 0.02, wall, loc=(cx, cy, 0), rot=(0, 0, rz))
        up = 0.02
        pts = [(-hw - o, zE + up), (0, zR + up), (hw + o, zE + up),
               (hw + o, zE + up + thick), (0, zR + up + thick), (-hw - o, zE + up + thick)]
        self.prism(pts, length + 2 * o, roof, loc=(cx, cy, 0), rot=(0, 0, rz))

    # --- finishing ----------------------------------------------------------------------------
    @staticmethod
    def _clean(bm) -> None:
        bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-4)
        bmesh.ops.dissolve_degenerate(bm, edges=bm.edges[:], dist=1e-5)
        bmesh.ops.triangulate(bm, faces=bm.faces[:])
        # Drop zero-area leftovers.
        bad = [f for f in bm.faces if f.calc_area() < 1e-7]
        if bad:
            bmesh.ops.delete(bm, geom=bad, context="FACES_ONLY")
        loose = [v for v in bm.verts if not v.link_faces]
        if loose:
            bmesh.ops.delete(bm, geom=loose, context="VERTS")

    def to_object(self, name: str | None = None) -> bpy.types.Object:
        name = name or self.name
        self._clean(self.bm)
        me = bpy.data.meshes.new(name)
        self.bm.to_mesh(me)
        for p in me.polygons:
            p.use_smooth = False
        for key in self.mats:
            me.materials.append(get_material(key))
        obj = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(obj)
        return obj

    def col_object(self, parent: bpy.types.Object) -> bpy.types.Object | None:
        if not self.col_bm.verts:
            return None
        self._clean(self.col_bm)
        name = f"{self.name}_col-{self.col_kind}"
        me = bpy.data.meshes.new(name)
        self.col_bm.to_mesh(me)
        obj = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(obj)
        obj.parent = parent
        obj.display_type = "WIRE"
        return obj


def tri_count(obj: bpy.types.Object) -> int:
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def make_lod(obj: bpy.types.Object, ratio: float, name: str) -> bpy.types.Object:
    """Decimated copy of `obj` (collapse, keeps material assignment, flat shaded)."""
    mod = obj.modifiers.new("dec", "DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.ratio = ratio
    mod.use_collapse_triangulate = True
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(obj.evaluated_get(dg))
    obj.modifiers.remove(mod)
    me.name = name
    for p in me.polygons:
        p.use_smooth = False
    lod = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(lod)
    return lod


def _export(objs: list[bpy.types.Object], path: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_yup=True,
        export_materials="EXPORT", export_normals=True, export_texcoords=False, export_cameras=False,
        export_lights=False, export_extras=False, export_animations=False, export_skins=False,
    )


def export_asset(b: Builder, category: str, kind: str, lods: bool, out_root: str = MODEL_ROOT) -> dict:
    """Writes <cat>/<name>.glb (+ _lod1/_lod2) and returns a manifest entry."""
    obj = b.to_object()
    col = b.col_object(obj)
    tris = [tri_count(obj)]
    files = [f"{b.name}.glb"]
    d = os.path.join(out_root, category)
    _export([obj] + ([col] if col else []), os.path.join(d, files[0]))
    if lods:
        for i, ratio in enumerate(LOD_RATIOS[1:], start=1):
            lo = make_lod(obj, ratio, f"{b.name}_lod{i}")
            fn = f"{b.name}_lod{i}.glb"
            _export([lo], os.path.join(d, fn))
            files.append(fn)
            tris.append(tri_count(lo))
    dims = [round(v, 2) for v in obj.dimensions]
    bb_min_z = min((obj.matrix_world @ Vector(c)).z for c in obj.bound_box)
    return {"name": b.name, "category": category, "kind": kind, "files": files, "tris": tris,
            "size_m": dims, "collision": col.name.rsplit("-", 1)[-1] if col else None,
            "min_z": round(bb_min_z, 2)}


def write_manifest(category: str, entries: list[dict], out_root: str = MODEL_ROOT) -> None:
    path = os.path.join(out_root, category, "manifest.json")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump({"category": category, "assets": sorted(entries, key=lambda e: e["name"])}, f, indent=1)
        f.write("\n")
