"""Build every procedural asset into game/assets/models/<category>/*.glb (+ _lod1/_lod2 files + manifest.json).

  .venv/bin/python tools/blender/build_all.py [--only nature,shire] [--name substr]   # launcher, runs Blender per category in parallel
  blender -b -P tools/blender/build_all.py -- --only nature [--name substr]            # one category in-process
"""
from __future__ import annotations

import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CATEGORIES = ["nature", "shire", "bree", "props"]


def _args(argv: list[str]) -> dict[str, str]:
    out = {}
    for a in argv:
        if a.startswith("--"):
            k, _, v = a[2:].partition("=")
            out[k] = v or "true"
    return out


def build(only: list[str], name: str | None) -> int:
    sys.path.insert(0, HERE)
    import importlib
    import traceback

    from lib import geo, style

    failed = 0
    for cat in only:
        mod = importlib.import_module(f"gen.{cat}")
        entries, roles = [], None
        for spec in mod.specs():
            if name and name not in spec.name:
                continue
            region = "bree" if spec.category == "bree" else "shire"
            roles = style.roles(region)
            geo.reset_scene()
            try:
                b = geo.Builder(spec.name, spec.seed)
                spec.fn(b, roles)
                entries.append(geo.export_asset(b, spec.category, spec.kind, spec.lods))
            except Exception:
                failed += 1
                print(f"BUILD_FAIL {spec.name}")
                traceback.print_exc()
        if entries and not name:
            geo.write_manifest(cat, entries)
        print(f"BUILT {cat}: {len(entries)} assets, tris LOD0 total {sum(e['tris'][0] for e in entries)}")
    return failed


def main() -> int:
    if "--" in sys.argv:
        a = _args(sys.argv[sys.argv.index("--") + 1:])
    else:
        a = _args(sys.argv[1:])
    only = a["only"].split(",") if "only" in a else CATEGORIES
    try:
        import bpy  # noqa: F401
        have_bpy = True
    except ImportError:
        have_bpy = False
    if have_bpy:
        return 1 if build(only, a.get("name")) else 0
    sys.path.insert(0, HERE)
    from runner import blender_env
    env = blender_env()
    procs = []
    for cat in only:
        cmd = ["blender", "-b", "-noaudio", "-P", os.path.join(HERE, "build_all.py"), "--", f"--only={cat}"]
        if "name" in a:
            cmd.append(f"--name={a['name']}")
        procs.append((cat, subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, env=env)))
    rc = 0
    for cat, p in procs:
        out = p.communicate()[0]
        lines = [l for l in out.splitlines() if l.startswith(("BUILT", "BUILD_FAIL", "Traceback", "  File", "  ", "Error", "TypeError", "AttributeError", "ValueError", "KeyError"))
                 or "Error" in l]
        print(f"--- {cat} (exit {p.returncode})")
        print("\n".join(lines))
        rc |= 1 if (p.returncode or "BUILD_FAIL" in out) else 0
    return rc


if __name__ == "__main__":
    sys.exit(main())
