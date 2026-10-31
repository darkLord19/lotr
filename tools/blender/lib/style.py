"""Single Python-side source of look parameters for the Blender asset generators.

Loads game/config/style.json (the game reads the same file) and falls back to the defaults below
when it is missing or a key is absent, so generators never fail on a half-written config.
Asset colour roles (wood, thatch, plaster...) are derived from the style.json terrain ramps where
that makes sense (foliage from grass/forest_floor, stone from rock, earth from path) and from
ROLE_DEFAULTS otherwise. style.json may override any role under style.assets.<region>.<role>.
"""
from __future__ import annotations

import json
import os

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
STYLE_PATH = os.path.join(REPO, "game", "config", "style.json")

DEFAULT_PALETTES: dict[str, dict[str, list[str]]] = {
    "shire": {
        "grass": ["#2c6a26", "#5aa832", "#a6d85a"],
        "grass_alt": ["#7a7a28", "#c2b040", "#f2dc72"],
        "path": ["#5e4026", "#9a6c3e", "#c89a60"],
        "forest_floor": ["#1c4420", "#37702e", "#6aa044"],
        "rock": ["#585a58", "#8c8a82", "#c2bca8"],
    },
    "bree": {
        "grass": ["#3a4630", "#626e4c", "#9aa27c"],
        "grass_alt": ["#4c4636", "#7c7058", "#aa9e82"],
        "path": ["#443a30", "#756656", "#a39482"],
        "forest_floor": ["#2a3426", "#46523a", "#728060"],
        "rock": ["#44464a", "#757880", "#a8abb0"],
    },
}

# Roles that are not terrain layers. Shire = warm saturated, Bree = muted browns/greys.
ROLE_DEFAULTS: dict[str, dict[str, str]] = {
    "shire": {
        "bark": "#5a4128", "bark_light": "#7e5d3a", "wood": "#9a6c3e", "wood_dark": "#5e4026",
        "thatch": "#d2ad52", "thatch_dark": "#a58433", "plaster": "#efe2bc", "plaster_dark": "#d6c594",
        "brick": "#b0583a", "roof_tile": "#a8482e", "slate": "#6a6e78", "metal": "#4a4a4e",
        "glass": "#f2cf78", "birch": "#ece7d8", "birch_dark": "#3a3630", "cloth": "#c04a3a",
        "door_green": "#2f8a3a", "door_red": "#b02e2e", "door_yellow": "#e0b82e", "door_blue": "#3a70b0",
        "brass": "#e0b040", "soil": "#5a3e26", "water": "#5fb8b0", "hay": "#e0c868",
        "flower_yellow": "#f4d020", "flower_white": "#f6f2e6", "flower_purple": "#9a58c8", "flower_red": "#d83a2a",
        "food_crust": "#c88a44", "food_cheese": "#f0c850", "food_apple": "#c8322a", "ale": "#c88a28",
    },
    "bree": {
        "bark": "#4a3a2c", "bark_light": "#6a5a48", "wood": "#6e5a46", "wood_dark": "#3e3228",
        "thatch": "#8e7e58", "thatch_dark": "#6a5c40", "plaster": "#b9b09a", "plaster_dark": "#9a9280",
        "brick": "#7a5448", "roof_tile": "#72483a", "slate": "#4c4e56", "metal": "#3a3a3e",
        "glass": "#d8b878", "birch": "#d8d4c6", "birch_dark": "#33302a", "cloth": "#8a5048",
        "door_green": "#3e5a3c", "door_red": "#6e3a34", "door_yellow": "#a88a3c", "door_blue": "#46586e",
        "brass": "#b89038", "soil": "#46382a", "water": "#6a8a8c", "hay": "#b4a066",
        "flower_yellow": "#d0b030", "flower_white": "#d8d4c6", "flower_purple": "#7a5a98", "flower_red": "#a8403a",
        "food_crust": "#b07c40", "food_cheese": "#d8b04a", "food_apple": "#a83a2e", "ale": "#a87428",
    },
}


def _load() -> dict:
    try:
        with open(STYLE_PATH, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError):
        return {}
    return data.get("style", data) if isinstance(data, dict) else {}


STYLE: dict = _load()


def ramp(region: str, layer: str) -> list[str]:
    """Three-stop colour ramp [dark, mid, light] for a terrain layer in a region."""
    pal = STYLE.get("palettes", {}).get(region, {})
    if isinstance(pal.get(layer), list) and len(pal[layer]) >= 3:
        return list(pal[layer])
    return list(DEFAULT_PALETTES[region][layer])


def roles(region: str) -> dict[str, str]:
    """Flat colour-role dict for a region ('shire' or 'bree')."""
    r = dict(ROLE_DEFAULTS[region])
    for layer in ("grass", "grass_alt", "path", "forest_floor", "rock"):
        for i, name in enumerate(("dark", "mid", "light")):
            r[f"{layer}_{name}"] = ramp(region, layer)[i]
    for k, v in STYLE.get("assets", {}).get(region, {}).items():
        r[k] = v
    return r


def mix(a: str, b: str, t: float) -> str:
    """Linear blend of two sRGB hex colours (done in sRGB; good enough for palette shading)."""
    ca, cb = _rgb(a), _rgb(b)
    return "#%02x%02x%02x" % tuple(round(ca[i] + (cb[i] - ca[i]) * t) for i in range(3))


def shade(c: str, f: float) -> str:
    """f < 1 darkens, f > 1 lightens toward white."""
    rgb = _rgb(c)
    if f <= 1:
        return "#%02x%02x%02x" % tuple(round(v * f) for v in rgb)
    t = f - 1
    return "#%02x%02x%02x" % tuple(round(v + (255 - v) * t) for v in rgb)


def _rgb(h: str) -> tuple[int, int, int]:
    h = h.lstrip("#")
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


def to_linear(h: str) -> tuple[float, float, float]:
    out = []
    for v in _rgb(h):
        c = v / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return out[0], out[1], out[2]
