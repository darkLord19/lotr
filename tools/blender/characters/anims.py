"""Procedural keyframed animations, written as separate Blender actions (exported to glTF as separate animations).

Poses are authored as Euler degrees (rx, ry, rz) per bone in *armature axes* (x right, y forward, z up), composed
R = Rx @ Ry @ Rz, relative to the T-pose rest. `apply` converts them to each bone's local rotation, so the same pose
tables drive every race whatever its bone lengths. Positive rx swings a hanging limb forward; arms lower with
ry = side * angle (side = +1 for the character's right, +X).

Looping clips (idle walk run crouch_walk sniff) repeat; sit/sleep/faint are non-looping *holds* whose last pose
stays (the engine blends into them). talk_gesture/eat/sniff only key the upper body so they can layer over any gait.
"""
from __future__ import annotations

import math
from collections.abc import Callable

import bpy
from mathutils import Euler, Matrix, Vector

from .rig import BONES, Dims

FPS = 30
KEY_STEP = 2
LOWER = 74.0  # arms hang this many degrees below the T-pose
UPPER_BODY = ["Spine", "Chest", "Neck", "Head", "UpperArm_L", "LowerArm_L", "Hand_L", "UpperArm_R", "LowerArm_R", "Hand_R"]

LOOPING = {"idle", "walk", "run", "crouch_walk", "sniff"}
Pose = dict[str, list[float]]


class Ctx:
    def __init__(self, d: Dims, style: dict):
        self.d = d
        self.style = style
        self.T = d.hip_z - d.ankle_z  # leg length hip joint to ankle


def sd(x: float) -> float:
    x = max(0.0, min(1.0, x))
    return x * x * (3 - 2 * x)


def new_pose() -> Pose:
    return {b: [0.0, 0.0, 0.0] for b in BONES}


def add(p: Pose, bone: str, rx: float = 0.0, ry: float = 0.0, rz: float = 0.0) -> None:
    v = p[bone]
    v[0] += rx
    v[1] += ry
    v[2] += rz


def sides():
    return (("L", -1), ("R", 1))


def base_pose(c: Ctx, arm_hang: float = 1.0, flex: float = 9.0) -> Pose:
    p = new_pose()
    for sn, s in sides():
        add(p, f"UpperArm_{sn}", ry=s * LOWER * arm_hang)
        add(p, f"LowerArm_{sn}", rz=s * flex)
    return p


def squat(p: Pose, c: Ctx, drop: float) -> float:
    """Bend both legs so the hips sink by `drop` metres with the feet staying under them. Returns hip dz."""
    a = math.degrees(math.acos(max(-1.0, min(1.0, 1.0 - drop / c.T))))
    for sn, _ in sides():
        add(p, f"UpperLeg_{sn}", rx=a)
        add(p, f"LowerLeg_{sn}", rx=-2 * a)
        add(p, f"Foot_{sn}", rx=a)
    return -drop


# --- clips: each returns (pose, hips_offset) for phase u in [0, 1] ---------------------------------

def a_idle(u: float, c: Ctx):
    ph = 2 * math.pi * u
    p = base_pose(c)
    add(p, "Chest", rx=-1.2 * math.sin(ph))
    add(p, "Spine", rx=0.8 * math.sin(ph + 0.4), rz=0.8 * math.sin(ph))
    add(p, "Head", rz=3.0 * math.sin(ph), rx=1.5 * math.sin(2 * ph + 1.0))
    add(p, "Hips", ry=1.2 * math.sin(ph), rz=0.8 * math.sin(ph + 1))
    for sn, s in sides():
        add(p, f"UpperArm_{sn}", rx=1.4 * math.sin(ph + s), ry=0.8 * s * math.sin(ph))
    add(p, "UpperLeg_R", ry=-0.6 * math.sin(ph))
    return p, Vector((0, 0, -0.003 * c.d.k * math.sin(2 * ph)))


def _gait(u: float, c: Ctx, amp: float, knee: float, arm: float, elbow: float, bob: float, lean: float, twist: float,
          sq: float = 0.0, air: float = 0.0):
    st = c.style
    amp *= st.get("stride", 1.0)
    arm *= st.get("arms", 1.0)
    ph = 2 * math.pi * u
    p = base_pose(c)
    dz = squat(p, c, sq) if sq else 0.0
    for sn, s in sides():
        q = ph + (0.0 if sn == "R" else math.pi)
        swing = amp * math.sin(q)
        fl = knee * max(0.0, math.cos(q)) ** 1.2 + 4.0
        add(p, f"UpperLeg_{sn}", rx=swing)
        add(p, f"LowerLeg_{sn}", rx=-fl)
        # keep the foot roughly level; toe-off lifts the heel
        add(p, f"Foot_{sn}", rx=-(swing - fl) * 0.85 + 8.0 * max(0.0, -math.sin(q)) * (amp / 28.0))
        asw = -arm * math.sin(q)
        add(p, f"UpperArm_{sn}", rx=asw)
        add(p, f"LowerArm_{sn}", rz=s * (elbow + 0.5 * elbow * max(0.0, asw / max(arm, 1e-3))))
    add(p, "Hips", rz=twist * math.sin(ph), ry=1.5 * math.sin(ph) * st.get("sway", 1.0), rx=-lean * 0.4)
    add(p, "Spine", rz=-twist * 1.2 * math.sin(ph), rx=-lean * 0.35)
    add(p, "Chest", rz=-twist * 0.8 * math.sin(ph), rx=-lean * 0.25)
    add(p, "Head", rz=twist * 0.9 * math.sin(ph), rx=lean * 0.7 + 1.5 * math.sin(2 * ph))
    b = bob * c.d.hip_z * 0.045 * st.get("bob", 1.0)
    hz = dz - b * (1 + math.cos(2 * ph)) / 2 + air * c.d.hip_z * 0.05 * (1 + math.cos(2 * ph + math.pi)) / 2
    return p, Vector((0, 0, hz))


def a_walk(u: float, c: Ctx):
    if c.style.get("rider"):
        p, off = _gait(u, c, 15, 22, 4, 26, 0.4, 3, 2.5)
        for sn, s in sides():
            add(p, f"UpperArm_{sn}", rx=14)
            add(p, f"LowerArm_{sn}", rz=s * 20)
        add(p, "Head", rx=10)
        add(p, "Neck", rx=-6)
        return p, off
    return _gait(u, c, 28, 42, 24, 12, 1.0, 3, 5)


def a_run(u: float, c: Ctx):
    p, off = _gait(u, c, 48, 92, 46, 78, 1.3, 14, 9, air=1.0)
    return p, off


def a_crouch_walk(u: float, c: Ctx):
    p, off = _gait(u, c, 17, 30, 12, 34, 0.5, 20, 4, sq=0.2 * c.T)
    for sn, s in sides():
        add(p, f"UpperArm_{sn}", rx=18)
    add(p, "Head", rx=-14)  # eyes up while the back is bent
    return p, off


def a_sit(u: float, c: Ctx):
    e = sd(u / 0.42)
    ph = 2 * math.pi * u
    p = base_pose(c)
    for sn, s in sides():
        add(p, f"UpperLeg_{sn}", rx=84 * e, ry=s * 3 * e)
        add(p, f"LowerLeg_{sn}", rx=-92 * e)
        add(p, f"Foot_{sn}", rx=8 * e)
        add(p, f"UpperArm_{sn}", rx=26 * e)
        add(p, f"LowerArm_{sn}", rz=s * 38 * e)
    add(p, "Spine", rx=-3 * e + 0.8 * math.sin(2 * ph) * e)
    add(p, "Chest", rx=2 * e)
    add(p, "Head", rx=-2 * e)
    return p, Vector((0, 0, -c.d.thigh * e + 0.0))


def a_sleep(u: float, c: Ctx):
    d = c.d
    e = sd(u / 0.45)
    p = base_pose(c, flex=6)
    add(p, "Hips", rx=90 * e)
    add(p, "Head", rz=14 * e)
    for sn, s in sides():
        add(p, f"UpperArm_{sn}", ry=-s * 8 * e)
        add(p, f"UpperLeg_{sn}", ry=s * 4 * e)
        add(p, f"LowerLeg_{sn}", rx=-6 * e)
    add(p, "UpperLeg_R", rx=-6 * e)
    lie = d.hip_z - (d.hip_hd + 0.02)
    return p, Vector((0, 0.05 * d.hip_z * e, -lie * e))


def a_faint(u: float, c: Ctx):
    d = c.d
    e1 = sd(u / 0.16)          # knees go
    e2 = sd((u - 0.14) / 0.30)  # topple back
    e2 = e2 * e2 * (3 - 2 * e2) if e2 < 1 else 1.0
    p = base_pose(c)
    dz = squat(p, c, 0.15 * c.T * e1 * (1 - e2))
    add(p, "Hips", rx=90 * e2)
    add(p, "Head", rx=-14 * e1, rz=24 * e2)
    for sn, s in sides():
        add(p, f"UpperArm_{sn}", ry=-s * 42 * e2, rx=-10 * e2)
        add(p, f"LowerArm_{sn}", rz=s * 14 * e2)
        add(p, f"UpperLeg_{sn}", ry=s * 9 * e2)
    add(p, "LowerLeg_R", rx=-18 * e2)
    add(p, "UpperLeg_R", rx=14 * e2)
    lie = d.hip_z - (d.hip_hd + 0.02)
    return p, Vector((0, -0.08 * d.hip_z * e2, dz * (1 - e2) - lie * e2))


def a_eat(u: float, c: Ctx):
    g = max(0.0, min(1.0, 1.7 * math.sin(math.pi * 2 * u) ** 2))
    g = sd(g)
    ph = 2 * math.pi * u
    p = base_pose(c)
    add(p, "UpperArm_R", rx=34 * g, ry=-14 * g)
    add(p, "LowerArm_R", rz=112 * g)
    add(p, "Hand_R", rz=10 * g)
    add(p, "UpperArm_L", rx=8 * g)
    add(p, "Head", rx=-5 * g + 3.0 * math.sin(ph * 6) * g)
    add(p, "Spine", rx=-2 * g)
    return p, Vector()


def a_talk(u: float, c: Ctx):
    g = math.sin(math.pi * u) ** 2
    ph = 2 * math.pi * u
    p = base_pose(c)
    add(p, "UpperArm_R", rx=30 * g, ry=-30 * g)
    add(p, "LowerArm_R", rz=72 * g + 16 * g * math.sin(ph * 3))
    add(p, "Hand_R", rx=12 * g * math.sin(ph * 3 + 1), rz=6 * g)
    add(p, "UpperArm_L", rx=14 * g * math.sin(ph * 2 + 1), ry=-12 * g)
    add(p, "LowerArm_L", rz=-(38 * g))
    add(p, "Head", rx=4 * g * math.sin(ph * 2), rz=6 * g * math.sin(ph))
    add(p, "Chest", rz=3 * g * math.sin(ph))
    return p, Vector()


def a_pick_up(u: float, c: Ctx):
    e = sd(u / 0.34) if u < 0.52 else 1.0 - sd((u - 0.52) / 0.36)
    p = base_pose(c)
    dz = squat(p, c, 0.3 * c.T * e)
    add(p, "Spine", rx=-24 * e)
    add(p, "Chest", rx=-16 * e)
    add(p, "Head", rx=22 * e)
    add(p, "UpperArm_R", rx=62 * e, ry=-10 * e)
    add(p, "LowerArm_R", rz=16 * e)
    add(p, "UpperArm_L", rx=-26 * e)
    add(p, "Hips", rx=-6 * e)
    return p, Vector((0, 0.04 * c.d.hip_z * e, dz))


def a_sniff(u: float, c: Ctx):
    ph = 2 * math.pi * u
    g = sd(min(u / 0.12, 1.0)) * sd(min((1 - u) / 0.12, 1.0))
    p = base_pose(c)
    for sn, s in sides():
        add(p, f"UpperArm_{sn}", rx=14)
        add(p, f"LowerArm_{sn}", rz=s * 20)
    add(p, "Head", rz=44 * g * math.sin(ph), rx=-4 + 14 * g + 3 * math.sin(ph * 7) * g)
    add(p, "Neck", rz=22 * g * math.sin(ph), rx=-8 * g)
    add(p, "Chest", rx=-9 * g, rz=8 * g * math.sin(ph))
    add(p, "Spine", rx=-5 * g)
    return p, Vector()


CLIPS: dict[str, tuple[float, Callable, list[str] | None]] = {
    # name: (duration s, fn, bones keyed (None = all bones + hips offset))
    "idle": (3.0, a_idle, None),
    "walk": (1.0, a_walk, None),
    "run": (0.66, a_run, None),
    "crouch_walk": (1.3, a_crouch_walk, None),
    "sit": (2.4, a_sit, None),
    "sleep": (3.0, a_sleep, None),
    "faint": (2.8, a_faint, None),
    "pick_up": (1.9, a_pick_up, None),
    "eat": (2.4, a_eat, UPPER_BODY),
    "talk_gesture": (2.4, a_talk, UPPER_BODY),
    "sniff": (3.2, a_sniff, UPPER_BODY),
}
HUMAN_CLIPS = ["idle", "walk", "run", "sit", "talk_gesture", "crouch_walk", "sleep", "eat", "pick_up", "faint"]
RIDER_CLIPS = ["idle", "walk", "sniff"]


def euler_matrix(rx: float, ry: float, rz: float) -> Matrix:
    mx = Matrix.Rotation(math.radians(rx), 3, "X")
    my = Matrix.Rotation(math.radians(ry), 3, "Y")
    mz = Matrix.Rotation(math.radians(rz), 3, "Z")
    return mx @ my @ mz


def natural_speeds(d: Dims, style: dict) -> dict[str, float]:
    """Ground speed (m/s) at which the walk/run/crouch cycles have no foot slide: 2 steps/cycle x stride 2*T*sin(amp)."""
    T = d.hip_z - d.ankle_z
    st = style.get("stride", 1.0)

    def v(amp: float, dur: float, sq: float = 0.0) -> float:
        t = T - sq
        return 4.0 * t * math.sin(math.radians(amp * st)) / dur

    rider = style.get("rider")
    return {"walk": v(15 if rider else 28, CLIPS["walk"][0]), "run": v(48, CLIPS["run"][0]),
            "crouch_walk": v(17, CLIPS["crouch_walk"][0], 0.2 * T)}


def build_actions(arm: bpy.types.Object, d: Dims, style: dict, names: list[str]) -> None:
    c = Ctx(d, style)
    d.k = d.k  # (kept for clarity: Ctx reads d.k for sub-millimetre idle motion)
    arm.animation_data_create()
    rest = {pb.name: pb.bone.matrix_local.to_3x3() for pb in arm.pose.bones}
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
    for name in names:
        dur, fn, bones = CLIPS[name]
        act = bpy.data.actions.new(name)
        act.use_fake_user = True
        arm.animation_data.action = act
        n_frames = int(round(dur * FPS))
        frames = list(range(0, n_frames, KEY_STEP)) + [n_frames]
        prev: dict[str, object] = {}
        for f in frames:
            pose, off = fn(min(f / n_frames, 1.0), c)
            for b in (bones or BONES):
                pb = arm.pose.bones[b]
                B = rest[b]
                q = (B.inverted() @ euler_matrix(*pose[b]) @ B).to_quaternion()
                if b in prev and prev[b].dot(q) < 0:
                    q.negate()
                prev[b] = q
                pb.rotation_quaternion = q
                pb.keyframe_insert("rotation_quaternion", frame=f, group=b)
                if b == "Hips" and bones is None:
                    pb.location = rest[b].inverted() @ off
                    pb.keyframe_insert("location", frame=f, group=b)
        act.frame_range = (0, n_frames)
    # leave the rig in rest pose with no action bound (the exporter uses the stored actions)
    arm.animation_data.action = None
    for pb in arm.pose.bones:
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.location = (0, 0, 0)
