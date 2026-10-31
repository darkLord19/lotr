"""Shared launcher bits: find Blender and make sure its Python can import numpy (the glTF exporter needs it).

The apt Blender on Linux ships without numpy; we install a cp312 wheel into build/blender_pylib and put it
on PYTHONPATH. Blender builds that bundle numpy (macOS, official Linux tarball) don't need this.
"""
from __future__ import annotations

import os
import subprocess
import sys

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
PYLIB = os.path.join(REPO, "build", "blender_pylib")


def blender_env() -> dict[str, str]:
    env = dict(os.environ)
    probe = subprocess.run(["blender", "-b", "-noaudio", "--python-expr", "import numpy; print('NUMPY_OK')"],
                           capture_output=True, text=True, env=env)
    if "NUMPY_OK" not in probe.stdout:
        if not os.path.isdir(os.path.join(PYLIB, "numpy")):
            subprocess.run([sys.executable, "-m", "pip", "install", "-q", "--target", PYLIB, "--python-version", "3.12",
                            "--only-binary=:all:", "--implementation", "cp", "numpy"], check=True)
        env["PYTHONPATH"] = PYLIB + os.pathsep + env.get("PYTHONPATH", "")
    return env
