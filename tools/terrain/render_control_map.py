"""Renders the eriador_west control map (M1-T02) to build/maps and docs/reports."""
from __future__ import annotations

import shutil
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).parent))
import check_region as cr  # noqa: E402

OUT = cr.ROOT / "build/maps/eriador_west_control.png"
COPY = cr.ROOT / "docs/reports/eriador_west_control.png"
WIDTH = 2048
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
FONT_BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
FACTION = {"shire": (60, 140, 60), "buckland": (40, 110, 150), "bree": (170, 90, 40)}
ROAD = {"road": ((150, 110, 60), 5), "path": ((170, 140, 90), 2), "ferry": ((40, 60, 160), 3), "bridge": ((90, 60, 30), 5)}


def render(region: dict) -> Image.Image:
    w_m, h_m = region["size_m"]
    k = WIDTH / w_m
    h = round(h_m * k)
    S = 2  # supersample for smooth lines
    img = Image.new("RGB", (WIDTH * S, h * S), (150, 190, 110))
    d = ImageDraw.Draw(img, "RGBA")

    def px(p: list[float]) -> tuple[float, float]:
        return (p[0] * k * S, p[1] * k * S)

    for hl in region.get("hills", []):
        cx, cz = px(hl["center"])
        r = hl["radius"] * k * S
        col = (120, 105, 80) if hl.get("enterable") is False else (130, 165, 95)
        for i in range(6, 0, -1):
            rr = r * i / 6
            d.ellipse([cx - rr, cz - rr, cx + rr, cz + rr], fill=col + (40,))
    for f in region.get("forests", []):
        poly = [px(p) for p in f["polygon"]]
        d.polygon(poly, fill=(30, 90, 40, 190) if f.get("enterable", True) else (20, 55, 35, 230),
                  outline=(10, 40, 20) if f.get("enterable", True) else (160, 30, 30), width=3 * S)
    for s in region["settlements"]:
        cx, cz = px(s["center"])
        r = s["radius"] * k * S
        d.ellipse([cx - r, cz - r, cx + r, cz + r], fill=FACTION[s["faction"]] + (70,), outline=FACTION[s["faction"]] + (255,), width=2 * S)
    for rv in region.get("rivers", []):
        d.line([px(p) for p in rv["points"]], fill=(60, 120, 200), width=max(2, round(rv["width"] * k * S)), joint="curve")
    for rd in region.get("roads", []):
        col, wd = ROAD[rd["kind"]]
        d.line([px(p) for p in rd["points"]], fill=col, width=wd * S, joint="curve")
    for wl in region.get("walls", []):
        pts = [px(p) for p in wl["points"]]
        if wl.get("closed"):
            pts.append(pts[0])
        d.line(pts, fill=(60, 40, 20), width=3 * S, joint="curve")
    pos = {p["id"]: p for p in region["pois"]}
    for a, b, kind in region["road_graph"]["edges"]:
        d.line([px([pos[a]["pos"][0], pos[a]["pos"][2]]), px([pos[b]["pos"][0], pos[b]["pos"][2]])], fill=(255, 255, 255, 70), width=S)

    img = img.resize((WIDTH, h), Image.LANCZOS)
    d = ImageDraw.Draw(img, "RGBA")
    font = ImageFont.truetype(FONT, 12)
    big = ImageFont.truetype(FONT_BOLD, 16)
    # Label offsets (px) for crowded clusters; default is up-right.
    off = {
        "bag_end": (-6, -30), "bagshot_row": (-95, 4), "hobbiton_hill": (-40, -22), "party_field": (-30, 8),
        "mill": (-20, 12), "bywater": (-20, -26), "green_dragon": (6, 4), "frogmorton": (-30, -26),
        "floating_log": (6, 4), "stock": (-34, -26), "golden_perch": (6, 4), "bamfurlong": (-20, -20),
        "maggots_farm": (-50, 8), "bucklebury_ferry": (-110, 4), "brandy_hall": (8, -4), "crickhollow": (8, -4),
        "hedge_gate": (-40, -26), "old_forest_edge": (6, 2), "bombadil_house": (8, -6),
        "brandywine_bridge": (-50, -26), "bree_waiting_point": (-130, 12), "bree_west_gate": (-100, -34),
        "prancing_pony": (-120, 24), "bree_south_gate": (-110, 12), "bill_ferny_house": (-40, 24),
        "bree_hill": (-20, -36), "staddle": (10, 4), "combe": (-10, -28), "east_map_edge": (-115, 12),
        "gildor_camp": (6, 2), "woody_end_camp": (-110, 2), "three_farthing_stone": (-60, -28),
    }
    for p in region["pois"]:
        x, y = p["pos"][0] * k, p["pos"][2] * k
        col = (200, 40, 40) if not p.get("abstract") else (150, 60, 200)
        d.ellipse([x - 4, y - 4, x + 4, y + 4], fill=col, outline=(0, 0, 0))
        dx, dy = off.get(p["id"], (6, -6))
        lx, ly = x + dx, y + dy
        label = p["name"] + (" (abstract)" if p.get("abstract") else "")
        tb = d.textbbox((lx, ly), label, font=font)
        d.rectangle([tb[0] - 2, tb[1] - 1, tb[2] + 2, tb[3] + 1], fill=(255, 255, 240, 200))
        d.text((lx, ly), label, font=font, fill=(0, 0, 0))
    for rv in region.get("rivers", []):
        mid = rv["points"][len(rv["points"]) // 2 if rv["id"] == "brandywine" else 6]
        d.text((mid[0] * k + 12, mid[1] * k - 24 if rv["id"] == "the_water" else mid[1] * k - 300 * k), rv["id"].replace("_", " ").title(), font=big, fill=(20, 60, 140))
    for f in region.get("forests", []):
        cx = sum(p[0] for p in f["polygon"]) / len(f["polygon"]) * k
        cz = sum(p[1] for p in f["polygon"]) / len(f["polygon"]) * k
        name = f["id"].replace("_", " ").title() + ("" if f.get("enterable", True) else " (closed)")
        d.text((cx - 60, cz), name, font=big, fill=(230, 245, 220))
    for hl in region["hills"]:
        if hl["id"] in ("barrow_downs", "green_hill_country", "tuckborough_downs", "north_ridge"):
            d.text((hl["center"][0] * k - 50, hl["center"][1] * k - 10), hl["id"].replace("_", " ").title() + (" (closed)" if hl.get("enterable") is False else ""), font=big, fill=(70, 50, 30))
    # Legend
    ly = h - 70
    d.rectangle([10, ly - 6, 560, h - 8], fill=(255, 255, 240, 220))
    items = [("East Road / road", ROAD["road"][0]), ("path", ROAD["path"][0]), ("river", (60, 120, 200)), ("ferry", ROAD["ferry"][0])]
    for i, (t, c) in enumerate(items):
        d.line([20, ly + 8 + i * 14, 50, ly + 8 + i * 14], fill=c, width=4)
        d.text((58, ly + 2 + i * 14), t, font=font, fill=(0, 0, 0))
    for i, (t, c) in enumerate(FACTION.items()):
        d.rectangle([220, ly + 4 + i * 14, 236, ly + 14 + i * 14], fill=c)
        d.text((244, ly + 2 + i * 14), f"{t} settlement", font=font, fill=(0, 0, 0))
    d.text((380, ly + 2), "N  ^  (north up)", font=font, fill=(0, 0, 0))
    d.text((380, ly + 18), "red outline = not enterable", font=font, fill=(0, 0, 0))
    d.text((380, ly + 34), "8192 m x 4096 m, 1 px = 4 m", font=font, fill=(0, 0, 0))
    return img


def main() -> int:
    img = render(cr.load_region())
    OUT.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUT)
    COPY.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(OUT, COPY)
    print(f"wrote {OUT} ({img.width}x{img.height}) and {COPY}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
