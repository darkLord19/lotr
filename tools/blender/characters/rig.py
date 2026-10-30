"""Skinned-mesh plumbing for the procedural humanoids: body dimensions, a weighted mesh accumulator and the armature.

Conventions (Blender): +Z up, the character FACES +Y, character-right is +X. The glTF exporter turns +Y into
Godot's -Z, which is the game's "forward" (see PlayerController), so no yaw fix is needed in the engine.
T-pose rest: arms along +-X. Bone names are the same for every race; only bone lengths differ.

Skinning is by *position functions* (w_torso / w_arm / w_leg): every body part and every clothing shell asks the
same function, so a waistcoat deforms exactly like the torso under it. This avoids Blender's heat-diffusion
auto-weights, which are unreliable headless on many separate shells.
"""
from __future__ import annotations

import math
import os
import random
from collections.abc import Callable

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))

BONES = ["Hips", "Spine", "Chest", "Neck", "Head",
         "UpperArm_L", "LowerArm_L", "Hand_L", "UpperArm_R", "LowerArm_R", "Hand_R",
         "UpperLeg_L", "LowerLeg_L", "Foot_L", "UpperLeg_R", "LowerLeg_R", "Foot_R"]
Weights = dict[str, float]
WFun = Callable[[Vector], Weights]


def sm(x: float) -> float:
    x = max(0.0, min(1.0, x))
    return x * x * (3 - 2 * x)


def chain(t: float, joints: list[float], bones: list[str], bw: float) -> Weights:
    """Blend along a bone chain: `joints` ascending positions of the joints between consecutive `bones`."""
    s = [sm((t - (j - bw)) / (2 * bw)) for j in joints]
    out: Weights = {}
    prev = 0.0
    for i, b in enumerate(bones):
        w = (1.0 - s[0]) if i == 0 else (s[i - 1] - s[i] if i < len(joints) else s[-1])
        if w > 0.01:
            out[b] = w
        prev = w
    return out


class Dims:
    """All body measurements (metres) for one character: race preset x per-NPC overrides."""

    def __init__(self, race: dict, look: dict):
        r = race
        g = float(look.get("girth", 1.0)) * float(r.get("girth", 1.0))
        raw_top = r["leg"] + r["torso"] + r["neck"] + r["head"] * 0.5 * 1.85
        H = float(r["height_m"]) * float(look.get("height_mul", 1.0))
        k = H / raw_top
        self.H, self.k, self.g, self.r = H, k, g, r
        self.hip_z = r["leg"] * k
        self.torso = r["torso"] * k
        self.waist_z = self.hip_z + 0.36 * self.torso
        self.chest_z = self.hip_z + 0.70 * self.torso
        self.shoulder_z = self.hip_z + self.torso
        self.neck_len = r["neck"] * k
        self.neck_top = self.shoulder_z + self.neck_len
        self.head_r = r["head"] * 0.5 * k
        self.head_c = self.neck_top + self.head_r * 0.85
        self.head_top = self.head_c + self.head_r
        self.neck_r = float(r.get("neck_r", 0.034)) * k * g ** 0.5
        # Torso half-width/depth at hip, waist, chest (x = width, y = depth), girth and belly aware.
        self.hip_hw, self.hip_hd = r["hip_hw"] * k * g, r["hip_hd"] * k * g
        self.waist_hw, self.waist_hd = r["waist_hw"] * k * g, r["waist_hd"] * k * g * float(r.get("belly", 1.0)) * float(look.get("belly", 1.0))
        self.chest_hw, self.chest_hd = r["chest_hw"] * k * g ** 0.8, r["chest_hd"] * k * g * 0.9
        self.sx = r["shoulder"] * k * (1.0 + 0.1 * (g - 1.0))  # shoulder joint x
        self.arm_r = r["limb_r"] * k * g ** 0.6
        self.ua, self.la, self.hand_len = r["arm_up"] * k, r["arm_low"] * k, r["hand"] * k
        self.leg_r = r["leg_r"] * k * g ** 0.8
        self.leg_x = self.hip_hw * 0.52
        self.foot_h = r["foot_h"] * k
        self.ankle_z = self.foot_h * 1.05
        self.knee_z = self.ankle_z + (self.hip_z - self.ankle_z) * 0.50
        self.foot_len, self.foot_w = r["foot_len"] * k, r["foot_w"] * k
        self.az = self.shoulder_z - self.arm_r * 1.25  # arm axis height in T-pose
        self.thigh = self.hip_z - self.knee_z
        self.shin = self.knee_z - self.ankle_z

    # --- body profiles ------------------------------------------------------------------------
    def torso_profile(self, z: float) -> tuple[float, float]:
        """(half-width, half-depth) of the torso at height z (piecewise-linear through the key sections)."""
        pts = [(self.hip_z - 0.16 * self.torso, self.hip_hw * 0.86, self.hip_hd * 0.9),
               (self.hip_z, self.hip_hw, self.hip_hd),
               (self.waist_z, self.waist_hw, self.waist_hd),
               (self.chest_z, self.chest_hw, self.chest_hd),
               (self.shoulder_z - 0.02 * self.torso, self.chest_hw * 0.95, self.chest_hd * 0.82),
               (self.shoulder_z + self.neck_len * 0.25, self.neck_r * 1.9, self.neck_r * 1.7)]
        if z <= pts[0][0]:
            return pts[0][1], pts[0][2]
        for a, b in zip(pts, pts[1:]):
            if z <= b[0]:
                t = (z - a[0]) / (b[0] - a[0])
                return a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t
        return pts[-1][1], pts[-1][2]

    def leg_radius(self, z: float) -> float:
        pts = [(self.hip_z + 0.03, 1.08), (self.hip_z - 0.45 * self.thigh, 1.0), (self.knee_z, 0.72),
               (self.knee_z - 0.3 * self.shin, 0.80), (self.ankle_z + 0.05, 0.5), (self.ankle_z - 0.04, 0.5)]
        for a, b in zip(pts, pts[1:]):
            if z >= b[0]:
                t = (a[0] - z) / (a[0] - b[0])
                return self.leg_r * (a[1] + (b[1] - a[1]) * t)
        return self.leg_r * 0.5

    def arm_radius(self, x: float) -> float:
        """x = distance from the body centre line along the T-pose arm."""
        x0 = self.sx
        pts = [(x0 - 0.04, 1.12), (x0 + 0.35 * self.ua, 0.95), (x0 + self.ua, 0.78),
               (x0 + self.ua + 0.4 * self.la, 0.76), (x0 + self.ua + self.la, 0.58)]
        if x <= pts[0][0]:
            return self.arm_r * pts[0][1]
        for a, b in zip(pts, pts[1:]):
            if x <= b[0]:
                t = (x - a[0]) / (b[0] - a[0])
                return self.arm_r * (a[1] + (b[1] - a[1]) * t)
        return self.arm_r * 0.58

    # --- skinning functions -------------------------------------------------------------------
    def w_torso(self, p: Vector) -> Weights:
        z = p.z
        bw = 0.05 * self.torso
        if z > self.shoulder_z + 0.2 * self.neck_len:  # collar and above
            return chain(z, [self.neck_top - 0.2 * self.neck_len], ["Neck", "Head"], 0.5 * self.neck_len)
        return chain(z, [self.waist_z - 0.2 * self.torso, self.chest_z - 0.15 * self.torso, self.shoulder_z + 0.1 * self.neck_len],
                     ["Hips", "Spine", "Chest", "Neck"], bw)

    def w_leg(self, p: Vector) -> Weights:
        side = "R" if p.x > 0 else "L"
        t = -p.z
        return chain(t, [-(self.hip_z + 0.01), -self.knee_z, -(self.ankle_z + 0.02)],
                     ["Hips", f"UpperLeg_{side}", f"LowerLeg_{side}", f"Foot_{side}"], 0.04 * self.hip_z)

    def w_arm(self, p: Vector) -> Weights:
        side = "R" if p.x > 0 else "L"
        x = abs(p.x)
        return chain(x, [self.sx - 0.03, self.sx + self.ua, self.sx + self.ua + self.la],
                     ["Chest", f"UpperArm_{side}", f"LowerArm_{side}", f"Hand_{side}"], 0.04 * self.ua + 0.006)

    def w_head(self, _p: Vector) -> Weights:
        return {"Head": 1.0}


class Skin:
    """Accumulates verts/faces with per-vertex bone weights and a material *role* per face."""

    def __init__(self) -> None:
        self.v: list[Vector] = []
        self.w: list[Weights] = []
        self.f: list[tuple[int, ...]] = []
        self.fm: list[str] = []

    def vert(self, p, w: Weights | WFun) -> int:
        p = Vector(p)
        self.v.append(p)
        self.w.append(w(p) if callable(w) else dict(w))
        return len(self.v) - 1

    def face(self, idx, mat: str) -> None:
        self.f.append(tuple(idx))
        self.fm.append(mat)

    # --- primitives ---------------------------------------------------------------------------
    def tube(self, rings: list[dict], mat: str, w: Weights | WFun, seg: int = 8, cap0: bool = True, cap1: bool = True,
             arc: tuple[float, float] | None = None, flip: bool = False, jag: float = 0.0) -> None:
        """Lofted tube through `rings` ({c, u, v, ru, rv}). `arc=(a0, a1)` makes an open sheet over that angle range (radians)."""
        a0, a1 = arc if arc else (0.0, 2 * math.pi)
        closed = arc is None
        n = seg if closed else seg + 1
        grid: list[list[int]] = []
        for ri, rg in enumerate(rings):
            c, u, v = Vector(rg["c"]), Vector(rg["u"]), Vector(rg["v"])
            ru, rv = rg["ru"], rg["rv"]
            row = []
            for j in range(n):
                a = a0 + (a1 - a0) * (j / seg)
                # `jag` ragged hem: alternate the last ring up/down (torn cloak edge)
                off = Vector((0, 0, jag * (1.0 if j % 2 else -0.6))) if (jag and ri == len(rings) - 1) else Vector()
                row.append(self.vert(c + off + u * (ru * math.cos(a)) + v * (rv * math.sin(a)), w))
            grid.append(row)
        # orientation: normal of (a_j -> a_j+1 -> b_j+1) must point outward
        d = Vector(rings[-1]["c"]) - Vector(rings[0]["c"])
        nrm = Vector(rings[0]["u"]).cross(Vector(rings[0]["v"]))
        fwd = (nrm.dot(d) >= 0) != flip
        for i in range(len(rings) - 1):
            for j in range(seg if closed else seg):
                j2 = (j + 1) % n
                a, b, c2, d2 = grid[i][j], grid[i][j2], grid[i + 1][j2], grid[i + 1][j]
                self.face((a, b, c2, d2) if fwd else (d2, c2, b, a), mat)
        if closed:
            if cap0:
                self.face(grid[0] if not fwd else grid[0][::-1], mat)
            if cap1:
                self.face(grid[-1][::-1] if not fwd else grid[-1], mat)

    def ellipsoid(self, c, radii, mat: str, w: Weights | WFun, seg: int = 10, rings: int = 6,
                  keep: Callable[[Vector], bool] | None = None, jitter: float = 0.0, rng: random.Random | None = None,
                  rot: Matrix | None = None) -> None:
        """UV ellipsoid. `keep(local_unit_dir)` drops faces whose centroid fails (open hoods, hair caps)."""
        c = Vector(c)
        rows: list[list[int]] = []
        local: dict[int, Vector] = {}
        top = self._pole(c, radii, 1, w, rot, local)
        for i in range(1, rings):
            phi = math.pi * i / rings
            row = []
            for j in range(seg):
                th = 2 * math.pi * j / seg
                d = Vector((math.sin(phi) * math.cos(th), math.sin(phi) * math.sin(th), math.cos(phi)))
                f = 1.0 + ((rng or random).uniform(-jitter, jitter) if jitter else 0.0)
                idx = self._ev(c, radii, d, f, w, rot)
                local[idx] = d
                row.append(idx)
            rows.append(row)
        bot = self._pole(c, radii, -1, w, rot, local)

        def ok(ids) -> bool:
            if keep is None:
                return True
            m = sum((local[i] for i in ids), Vector()) / len(ids)
            return keep(m)

        for j in range(seg):
            j2 = (j + 1) % seg
            for ids in ((top, rows[0][j2], rows[0][j]),):
                if ok(ids):
                    self.face(ids, mat)
            for i in range(len(rows) - 1):
                ids = (rows[i][j], rows[i][j2], rows[i + 1][j2], rows[i + 1][j])
                if ok(ids):
                    self.face(ids, mat)
            ids = (bot, rows[-1][j], rows[-1][j2])
            if ok(ids):
                self.face(ids, mat)

    def _pole(self, c, radii, sgn, w, rot, local) -> int:
        d = Vector((0, 0, sgn))
        idx = self._ev(c, radii, d, 1.0, w, rot)
        local[idx] = d
        return idx

    def _ev(self, c, radii, d, f, w, rot) -> int:
        off = Vector((d.x * radii[0] * f, d.y * radii[1] * f, d.z * radii[2] * f))
        if rot is not None:
            off = rot @ off
        return self.vert(c + off, w)

    def box(self, c, size, mat: str, w: Weights | WFun, taper_top: float = 1.0) -> None:
        c = Vector(c)
        hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
        ids = {}
        for sx in (-1, 1):
            for sy in (-1, 1):
                for sz in (-1, 1):
                    k = taper_top if sz > 0 else 1.0
                    ids[(sx, sy, sz)] = self.vert(c + Vector((sx * hx * k, sy * hy * k, sz * hz)), w)
        q = lambda *k: tuple(ids[x] for x in k)  # noqa: E731
        for quad in ((q((-1, -1, -1), (-1, 1, -1), (1, 1, -1), (1, -1, -1))),
                     (q((-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1))),
                     (q((-1, -1, -1), (1, -1, -1), (1, -1, 1), (-1, -1, 1))),
                     (q((1, -1, -1), (1, 1, -1), (1, 1, 1), (1, -1, 1))),
                     (q((1, 1, -1), (-1, 1, -1), (-1, 1, 1), (1, 1, 1))),
                     (q((-1, 1, -1), (-1, -1, -1), (-1, -1, 1), (-1, 1, 1)))):
            self.face(quad, mat)

    def cone(self, base, r, h, mat: str, w: Weights | WFun, seg: int = 6, tip=(0, 0, 0), top_r: float = 0.003) -> None:
        base = Vector(base)
        rings = [{"c": base, "u": (1, 0, 0), "v": (0, 1, 0), "ru": r, "rv": r},
                 {"c": base + Vector((0, 0, h)) + Vector(tip), "u": (1, 0, 0), "v": (0, 1, 0), "ru": top_r, "rv": top_r}]
        self.tube(rings, mat, w, seg, cap0=True, cap1=False)

    # --- output -------------------------------------------------------------------------------
    def to_object(self, name: str, mats: dict[str, bpy.types.Material]) -> bpy.types.Object:
        bm = bmesh.new()
        lay = bm.verts.layers.deform.verify()
        groups = {b: i for i, b in enumerate(BONES)}
        verts = []
        for p, w in zip(self.v, self.w):
            bv = bm.verts.new(p)
            tot = sum(w.values()) or 1.0
            for b, val in w.items():
                if val / tot >= 0.02:
                    bv[lay][groups[b]] = val / tot
            verts.append(bv)
        roles: list[str] = []
        for ids, m in zip(self.f, self.fm):
            if len(set(ids)) < 3:
                continue
            try:
                face = bm.faces.new([verts[i] for i in ids])
            except ValueError:
                continue  # duplicate face
            if m not in roles:
                roles.append(m)
            face.material_index = roles.index(m)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        bmesh.ops.triangulate(bm, faces=bm.faces[:])
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        for p in me.polygons:
            p.use_smooth = False
        for r in roles:
            me.materials.append(mats[r])
        obj = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(obj)
        for b in BONES:
            obj.vertex_groups.new(name=b)
        return obj


def ring_x(c, ru, rv):
    """Ring in the XY plane (torso/legs, axis Z)."""
    return {"c": c, "u": (1, 0, 0), "v": (0, 1, 0), "ru": ru, "rv": rv}


def ring_yz(c, ru, rv):
    """Ring in the YZ plane (arms, axis X); u = Y (front-back), v = Z."""
    return {"c": c, "u": (0, 1, 0), "v": (0, 0, 1), "ru": ru, "rv": rv}


def ring_xz(c, ru, rv):
    """Ring in the XZ plane (feet, axis Y); u = X (width), v = Z."""
    return {"c": c, "u": (1, 0, 0), "v": (0, 0, 1), "ru": ru, "rv": rv}


# --- armature ----------------------------------------------------------------------------------

def bone_layout(d: Dims) -> dict[str, tuple[Vector, Vector, str | None]]:
    V = Vector
    lx = d.leg_x
    ay = 0.0
    out: dict[str, tuple[Vector, Vector, str | None]] = {
        "Hips": (V((0, 0, d.hip_z)), V((0, 0, d.waist_z)), None),
        "Spine": (V((0, 0, d.waist_z)), V((0, 0, d.chest_z)), "Hips"),
        "Chest": (V((0, 0, d.chest_z)), V((0, 0, d.shoulder_z)), "Spine"),
        "Neck": (V((0, 0, d.shoulder_z)), V((0, 0, d.neck_top)), "Chest"),
        "Head": (V((0, 0, d.neck_top)), V((0, 0, d.head_top)), "Neck"),
    }
    for side, s in (("L", -1), ("R", 1)):
        x0, x1, x2 = d.sx, d.sx + d.ua, d.sx + d.ua + d.la
        out[f"UpperArm_{side}"] = (V((s * x0, ay, d.az)), V((s * x1, ay, d.az)), "Chest")
        out[f"LowerArm_{side}"] = (V((s * x1, ay, d.az)), V((s * x2, ay, d.az)), f"UpperArm_{side}")
        out[f"Hand_{side}"] = (V((s * x2, ay, d.az)), V((s * (x2 + d.hand_len), ay, d.az)), f"LowerArm_{side}")
        out[f"UpperLeg_{side}"] = (V((s * lx, 0, d.hip_z)), V((s * lx, 0, d.knee_z)), "Hips")
        out[f"LowerLeg_{side}"] = (V((s * lx, 0, d.knee_z)), V((s * lx, 0, d.ankle_z)), f"UpperLeg_{side}")
        out[f"Foot_{side}"] = (V((s * lx, -0.2 * d.foot_len, d.ankle_z)), V((s * lx, 0.75 * d.foot_len, d.foot_h * 0.5)), f"LowerLeg_{side}")
    return out


def make_armature(name: str, d: Dims) -> bpy.types.Object:
    arm = bpy.data.armatures.new(name)
    obj = bpy.data.objects.new(name, arm)
    bpy.context.scene.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    lay = bone_layout(d)
    for b in BONES:
        h, t, parent = lay[b]
        eb = arm.edit_bones.new(b)
        eb.head, eb.tail = h, t
        eb.roll = 0.0
    for b in BONES:
        parent = lay[b][2]
        if parent:
            arm.edit_bones[b].parent = arm.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    obj.show_in_front = True
    return obj


def bind(mesh: bpy.types.Object, arm: bpy.types.Object) -> None:
    mesh.parent = arm
    mod = mesh.modifiers.new("Armature", "ARMATURE")
    mod.object = arm
