#!/usr/bin/env python3
"""Generates the dialogue portraits with mflux (Z-Image-Turbo, 4-bit) into game/assets/portraits/.

One image per named NPC (<id>.png) and six per villager template (<template>_<n>.png), 768x768,
fixed seeds. Style prefix: tools/art/style.txt; per-character text: tools/art/looks.json.
Prompts are recorded in tools/art/prompts.json. Usage (from the repo root, with .venv-art):
  .venv-art/bin/python tools/art/portraits.py [--only id ...] [--retry id ...] [--sheet-only]
--retry bumps the seed of that file (stored in tools/art/seed_bumps.json) and regenerates it.
First run: .venv-art/bin/mflux-save --model z-image-turbo --quantize 4 --path build/art/zimage-q4
"""
import argparse
import json
import subprocess
import sys
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / "tools/art"
OUT = ROOT / "game/assets/portraits"
MODEL = ROOT / "build/art/zimage-q4"
SIZE = 768
STEPS = 8


def base_seed(name: str) -> int:
    return zlib.crc32(name.encode()) % 1_000_000


def jobs(looks: dict, style: str) -> dict[str, str]:
    out: dict[str, str] = {}
    bg = looks["background"]
    for nid, (setting, desc) in looks["named"].items():
        out[nid] = f"{style}, {bg[setting]}, {desc}"
    for tid, (setting, descs) in looks["villagers"].items():
        for i, desc in enumerate(descs, 1):
            out[f"{tid}_{i}"] = f"{style}, {bg[setting]}, {desc}"
    return out


def generate(name: str, prompt: str, seed: int) -> bool:
    (OUT / f"{name}.png").unlink(missing_ok=True)  # mflux would write <name>_1.png instead of overwriting
    cmd = [str(ROOT / ".venv-art/bin/mflux-generate-z-image-turbo"), "--model", str(MODEL), "--prompt", prompt,
           "--steps", str(STEPS), "--seed", str(seed), "--width", str(SIZE), "--height", str(SIZE), "--output", str(OUT / f"{name}.png")]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        print(f"FAILED {name}: {r.stderr[-300:]}", file=sys.stderr)
    return r.returncode == 0


def contact_sheet(names: list[str]) -> Path:
    from PIL import Image, ImageDraw
    cell, cols = 256, 6
    rows = (len(names) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * cell, rows * (cell + 18)), (30, 26, 22))
    draw = ImageDraw.Draw(sheet)
    for i, n in enumerate(names):
        p = OUT / f"{n}.png"
        x, y = (i % cols) * cell, (i // cols) * (cell + 18)
        if p.exists():
            sheet.paste(Image.open(p).convert("RGB").resize((cell, cell)), (x, y))
        draw.text((x + 4, y + cell + 3), n, fill=(230, 220, 200))
    dest = ROOT / "docs/reports/m1_portraits/contact_sheet.png"
    dest.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(dest)
    return dest


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*", default=[])
    ap.add_argument("--retry", nargs="*", default=[])
    ap.add_argument("--sheet-only", action="store_true")
    a = ap.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    looks = json.loads((ART / "looks.json").read_text())
    style = (ART / "style.txt").read_text().strip()
    all_jobs = jobs(looks, style)
    bump_path = ART / "seed_bumps.json"
    bumps = json.loads(bump_path.read_text()) if bump_path.exists() else {}
    for n in a.retry:
        bumps[n] = int(bumps.get(n, 0)) + 1
    bump_path.write_text(json.dumps(bumps, indent=1, sort_keys=True) + "\n")
    todo = a.retry or a.only or list(all_jobs)
    prompts = {}
    if not a.sheet_only:
        for n in todo:
            seed = base_seed(n) + 7919 * int(bumps.get(n, 0))
            print(f"{n} seed={seed}", flush=True)
            if generate(n, all_jobs[n], seed):
                prompts[n] = {"seed": seed, "prompt": all_jobs[n]}
    rec = ART / "prompts.json"
    old = json.loads(rec.read_text()) if rec.exists() else {}
    old.update(prompts)
    rec.write_text(json.dumps(old, indent=1, sort_keys=True) + "\n")
    print("contact sheet:", contact_sheet(list(all_jobs)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
