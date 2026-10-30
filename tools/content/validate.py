#!/usr/bin/env python3
"""Validate game/content against its JSON Schemas, then run cross-reference checks.

Usage: .venv/bin/python tools/content/validate.py [--root DIR] [--schemas DIR]
Prints CONTENT_OK (exit 0) or one ERROR line per problem (exit 1).
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import sys
from fnmatch import fnmatch
from pathlib import Path
from typing import Any

from jsonschema import Draft202012Validator
from referencing import Registry, Resource
from referencing.jsonschema import DRAFT202012

REPO = Path(__file__).resolve().parents[2]
DEFAULT_ROOT = REPO / "game" / "content"
DEFAULT_SCHEMAS = DEFAULT_ROOT / "schemas"

# file location (relative to content root) -> schema file
LOCATIONS: list[tuple[str, str]] = [
    ("calendar.json", "calendar"),
    ("lore_cards/characters/*.json", "lore_card"),
    ("lore_cards/templates/*.json", "template_card"),
    ("timeline/events/*.json", "timeline_event"),
    ("timeline/itineraries/*.json", "itinerary"),
    ("regions/*.json", "region"),
    ("items/*.json", "item"),
    ("rumours/*.json", "rumour"),
    ("origins/*.json", "origin"),
    ("background_traits.json", "background_trait"),
    ("appearance.json", "appearance"),
    ("dialogue_fallbacks/*.json", "dialogue_fallback"),
]

DATE_MIN = dt.datetime(3018, 1, 1)
DATE_MAX = dt.datetime(3021, 12, 31, 23, 59)


class Report:
    def __init__(self) -> None:
        self.errors: list[str] = []
        self.warnings: list[str] = []

    def error(self, file: str, path: str, msg: str) -> None:
        self.errors.append(f"ERROR {file} {path}: {msg}")

    def warn(self, file: str, path: str, msg: str) -> None:
        self.warnings.append(f"WARN {file} {path}: {msg}")


def parse_date(s: str) -> dt.datetime:
    """Parse 'YYYY-MM-DD' or 'YYYY-MM-DDTHH:MM' (year = T.A.). Raises ValueError."""
    if "T" in s:
        return dt.datetime.strptime(s, "%Y-%m-%dT%H:%M")
    return dt.datetime.strptime(s, "%Y-%m-%d")


def shire_date(when: dt.datetime, cal: dict[str, Any]) -> str:
    """Reference implementation of the calendar.json lookup (mirrors what GDScript must do)."""
    year = when.year
    doy0 = (when.date() - dt.date(year, 1, 1)).days
    leap = year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)
    sr_year = year + cal["sr_year_offset"]
    if leap and doy0 == 59:
        return f"{cal['leap_day_name']}, S.R. {sr_year}"
    if leap and doy0 > 59:
        doy0 -= 1
    index = doy0 + cal["shire_index_shift"]
    if index >= cal["year_rollover_index"]:
        index -= cal["days_in_year"]
        sr_year += 1
    for p in cal["periods"]:
        if p["first_index"] <= index < p["first_index"] + p["length"]:
            if p["intercalary"]:
                return f"{p['name']}, S.R. {sr_year}"
            return f"{p['name']} {index - p['first_index'] + 1}, S.R. {sr_year}"
    raise ValueError(f"no calendar period for index {index}")


def jpath(parts: Any) -> str:
    out = "$"
    for p in parts:
        out += f"[{p}]" if isinstance(p, int) else f".{p}"
    return out


def load_validators(schema_dir: Path) -> dict[str, Draft202012Validator]:
    raw: dict[str, Any] = {}
    for f in sorted(schema_dir.glob("*.json")):
        raw[f.name] = json.loads(f.read_text())
    registry: Registry = Registry()
    for name, schema in raw.items():
        registry = registry.with_resource(name, Resource.from_contents(schema, DRAFT202012))
    out: dict[str, Draft202012Validator] = {}
    for name, schema in raw.items():
        if name.endswith(".schema.json"):
            Draft202012Validator.check_schema(schema)
            out[name.removesuffix(".schema.json")] = Draft202012Validator(schema, registry=registry)
    return out


def check_dates(rep: Report, file: str, doc: Any, kind: str) -> None:
    """Every date string must parse and lie in 3018-01-01..3021-12-31."""
    def chk(path: str, s: Any) -> None:
        if not isinstance(s, str):
            return
        try:
            d = parse_date(s)
        except ValueError:
            rep.error(file, path, f"date '{s}' does not parse")
            return
        if not (DATE_MIN <= d <= DATE_MAX):
            rep.error(file, path, f"date '{s}' outside 3018-01-01..3021-12-31")

    def walk_knowledge(base: str, entries: Any) -> None:
        for i, k in enumerate(entries or []):
            chk(f"{base}[{i}].known_from", k.get("known_from"))

    if kind == "timeline_event":
        for i, e in enumerate(doc):
            chk(f"$[{i}].at", e.get("at"))
            chk(f"$[{i}].window_end", e.get("window_end"))
    elif kind == "itinerary":
        for i, s in enumerate(doc["steps"]):
            chk(f"$.steps[{i}].at", s.get("at"))
    elif kind in ("lore_card", "template_card"):
        walk_knowledge("$.knowledge", doc.get("knowledge"))
    elif kind == "rumour":
        for i, r in enumerate(doc):
            chk(f"$[{i}].start", r.get("start"))
    elif kind == "origin":
        for i, o in enumerate(doc):
            chk(f"$[{i}].start_date", o.get("start_date"))
    elif kind == "dialogue_fallback":
        groups = {k: doc.get(k, []) for k in ("greetings", "farewells", "smalltalk")}
        for rid, lines in doc.get("rumour_lines", {}).items():
            groups[f"rumour_lines.{rid}"] = lines
        for name, lines in groups.items():
            for i, ln in enumerate(lines):
                if isinstance(ln, dict):
                    chk(f"$.{name}[{i}].from", ln.get("from"))
                    chk(f"$.{name}[{i}].until", ln.get("until"))


def check_calendar(rep: Report, file: str, cal: dict[str, Any]) -> None:
    expect = 0
    for i, p in enumerate(cal["periods"]):
        if p["first_index"] != expect:
            rep.error(file, f"$.periods[{i}].first_index", f"expected {expect} (periods must be contiguous)")
        expect = p["first_index"] + p["length"]
    if expect != cal["days_in_year"]:
        rep.error(file, "$.periods", f"periods cover {expect} days, expected {cal['days_in_year']}")


def validate(root: Path = DEFAULT_ROOT, schema_dir: Path = DEFAULT_SCHEMAS) -> Report:
    rep = Report()
    validators = load_validators(schema_dir)
    docs: dict[str, tuple[str, Any]] = {}  # relative file -> (kind, data)

    for f in sorted(root.rglob("*.json")):
        rel = f.relative_to(root).as_posix()
        if rel.startswith("schemas/"):
            continue
        kind = next((k for pat, k in LOCATIONS if fnmatch(rel, pat) and ("/" in pat or "/" not in rel)), None)
        if kind is None:
            rep.warn(rel, "$", "no schema for this location; skipped")
            continue
        try:
            data = json.loads(f.read_text())
        except json.JSONDecodeError as e:
            rep.error(rel, "$", f"invalid JSON: {e}")
            continue
        errs = sorted(validators[kind].iter_errors(data), key=lambda e: list(e.absolute_path))
        for e in errs:
            rep.error(rel, jpath(e.absolute_path), e.message)
        if errs:
            continue
        docs[rel] = (kind, data)
        check_dates(rep, rel, data, kind)
        if kind == "calendar":
            check_calendar(rep, rel, data)

    cross_refs(rep, root, docs)
    return rep


def cross_refs(rep: Report, root: Path, docs: dict[str, tuple[str, Any]]) -> None:
    npcs: dict[str, set[str]] = {}       # card id -> knowledge ids
    items: set[str] = set()
    rumours: set[str] = set()
    pois: set[str] = set()
    settlements: set[str] = set()
    ids: dict[str, str] = {}             # events + itinerary steps share one namespace
    have_region = False
    factions: set[str] = set()

    def dup(kind: str, ident: str, file: str, path: str, seen: dict[str, str]) -> None:
        key = f"{kind}:{ident}"
        if key in seen:
            rep.error(file, path, f"duplicate {kind} id '{ident}' (also in {seen[key]})")
        else:
            seen[key] = file

    seen: dict[str, str] = {}
    for file, (kind, data) in docs.items():
        if kind in ("lore_card", "template_card"):
            dup("npc", data["id"], file, "$.id", seen)
            npcs[data["id"]] = set()
            kids = [k["id"] for k in data.get("knowledge", [])]
            for i, k in enumerate(kids):
                if kids.count(k) > 1:
                    rep.error(file, f"$.knowledge[{i}].id", f"duplicate knowledge id '{k}'")
            npcs[data["id"]] = set(kids)
            if data.get("faction"):
                factions.add(data["faction"])
        elif kind == "item":
            for i, it in enumerate(data):
                dup("item", it["id"], file, f"$[{i}].id", seen)
                items.add(it["id"])
        elif kind == "rumour":
            for i, r in enumerate(data):
                dup("rumour", r["id"], file, f"$[{i}].id", seen)
                rumours.add(r["id"])
        elif kind == "region":
            have_region = True
            for i, p in enumerate(data["pois"]):
                dup("poi", p["id"], file, f"$.pois[{i}].id", seen)
                pois.add(p["id"])
            for s in data["settlements"]:
                settlements.add(s["id"])
        elif kind == "timeline_event":
            for i, e in enumerate(data):
                dup("event", e["id"], file, f"$[{i}].id", seen)
                ids[e["id"]] = file
        elif kind == "itinerary":
            for i, s in enumerate(data["steps"]):
                dup("event", s["id"], file, f"$.steps[{i}].id", seen)
                ids[s["id"]] = file

    def need(file: str, path: str, ident: str | None, pool: set[str], what: str) -> None:
        if ident is not None and ident not in pool:
            rep.error(file, path, f"unknown {what} '{ident}'")

    # POI checks only make sense once a region exists (M1-T02 adds the first one).
    poi_or_settlement = pois | settlements

    def need_poi(file: str, path: str, ident: str | None) -> None:
        if have_region:
            need(file, path, ident, pois, "poi")

    def need_place(file: str, path: str, ident: str | None) -> None:
        if have_region:
            need(file, path, ident, poi_or_settlement, "poi/settlement")

    deps: dict[str, list[str]] = {}
    for file, (kind, data) in docs.items():
        if kind == "dialogue_fallback":
            need(file, "$.npc", data["npc"], set(npcs), "npc")
            if Path(file).stem != data["npc"]:
                rep.error(file, "$.npc", f"file name must match npc id '{data['npc']}'")
            for rid in data["rumour_lines"]:
                if rumours and rid not in rumours:
                    rep.warn(file, f"$.rumour_lines.{rid}", f"unknown rumour '{rid}'")
        elif kind in ("lore_card", "template_card"):
            for i, it in enumerate(data.get("inventory_can_give", [])):
                need(file, f"$.inventory_can_give[{i}]", it, items, "item")
            if kind == "lore_card":
                need_poi(file, "$.home_poi", data.get("home_poi"))
                portrait = data.get("portrait")
                if portrait and portrait.startswith("res://"):
                    if not (root.parent / portrait.removeprefix("res://")).exists():
                        rep.warn(file, "$.portrait", f"portrait file missing: {portrait}")
        elif kind == "rumour":
            for i, r in enumerate(data):
                need_poi(file, f"$[{i}].origin_poi", r["origin_poi"])
        elif kind == "region":
            for i, p in enumerate(data["pois"]):
                s = p.get("settlement")
                if s is not None and s not in settlements:
                    rep.error(file, f"$.pois[{i}].settlement", f"unknown settlement '{s}'")
            for i, n in enumerate(data["road_graph"]["nodes"]):
                need(file, f"$.road_graph.nodes[{i}]", n, pois, "poi")
            nodes = set(data["road_graph"]["nodes"])
            for i, edge in enumerate(data["road_graph"]["edges"]):
                for j in (0, 1):
                    need(file, f"$.road_graph.edges[{i}][{j}]", edge[j], nodes, "road_graph node")
        elif kind == "origin":
            for i, o in enumerate(data):
                need_poi(file, f"$[{i}].start_poi", o["start_poi"])
                for j, it in enumerate(o["items"]):
                    need(file, f"$[{i}].items[{j}].item", it["item"], items, "item")
                for j, k in enumerate(o["known_by"]):
                    need(file, f"$[{i}].known_by[{j}].npc", k["npc"], set(npcs), "npc")
                for fac in o["reputation_offset"]:
                    need(file, f"$[{i}].reputation_offset.{fac}", fac, factions, "faction")
        elif kind == "background_trait":
            for i, t in enumerate(data):
                for fac in t["effects"]["reputation"]:
                    need(file, f"$[{i}].effects.reputation.{fac}", fac, factions, "faction")
        elif kind == "timeline_event":
            for i, e in enumerate(data):
                base = f"$[{i}]"
                need_place(file, f"{base}.location", e.get("location"))
                for j, a in enumerate(e.get("actors", [])):
                    need(file, f"{base}.actors[{j}]", a, set(npcs), "npc")
                for j, fx in enumerate(e.get("effects", [])):
                    ak = fx.get("add_knowledge")
                    if ak:
                        npc = ak["npc"]
                        if npc not in npcs:
                            rep.error(file, f"{base}.effects[{j}].add_knowledge.npc", f"unknown npc '{npc}'")
                        elif ak["knowledge_id"] not in npcs[npc]:
                            rep.error(file, f"{base}.effects[{j}].add_knowledge.knowledge_id",
                                      f"unknown knowledge '{ak['knowledge_id']}' on '{npc}'")
                    mv = fx.get("move_entity")
                    if mv:
                        if mv["id"] != "player":
                            need(file, f"{base}.effects[{j}].move_entity.id", mv["id"], set(npcs), "npc")
                        for key in ("poi", "to"):
                            if key in mv:
                                need_place(file, f"{base}.effects[{j}].move_entity.{key}", mv[key])
                    gi = fx.get("give_item")
                    if gi:
                        need(file, f"{base}.effects[{j}].give_item.item", gi["item"], items, "item")
                    sr = fx.get("spread_rumour")
                    if sr:
                        need(file, f"{base}.effects[{j}].spread_rumour.rumour_id", sr["rumour_id"], rumours, "rumour")
                        need_poi(file, f"{base}.effects[{j}].spread_rumour.poi", sr["poi"])
                r = e.get("rumour")
                if r:
                    need(file, f"{base}.rumour.id", r["id"], rumours, "rumour")
                    need_poi(file, f"{base}.rumour.origin_poi", r["origin_poi"])
                ta = e.get("trigger_area", {})
                if have_region and "settlement" in ta:
                    need(file, f"{base}.trigger_area.settlement", ta["settlement"], settlements, "settlement")
                if "poi" in ta:
                    need_poi(file, f"{base}.trigger_area.poi", ta["poi"])
                deps[e["id"]] = e.get("depends_on", [])
                for j, d in enumerate(e.get("depends_on", [])):
                    need(file, f"{base}.depends_on[{j}]", d, set(ids), "event")
        elif kind == "itinerary":
            need(file, "$.character", data["character"], set(npcs), "npc")
            prev: dt.datetime | None = None
            for i, s in enumerate(data["steps"]):
                base = f"$.steps[{i}]"
                for key in ("from", "to", "at_poi"):
                    need_poi(file, f"{base}.{key}", s.get(key))
                for j, c in enumerate(s.get("companions", [])):
                    need(file, f"{base}.companions[{j}]", c, set(npcs), "npc")
                for j, d in enumerate(s.get("depends_on", [])):
                    need(file, f"{base}.depends_on[{j}]", d, set(ids), "event")
                deps[s["id"]] = s.get("depends_on", [])
                try:
                    t = parse_date(s["at"])
                except ValueError:
                    continue
                if prev is not None and t < prev:
                    rep.error(file, f"{base}.at", f"step '{s['id']}' ({s['at']}) is earlier than the previous step")
                prev = t

    # depends_on cycles (DFS, report each cycle once)
    state: dict[str, int] = {}

    def visit(n: str, stack: list[str]) -> None:
        state[n] = 1
        for m in deps.get(n, []):
            if m not in deps:
                continue
            if state.get(m) == 1:
                cyc = stack[stack.index(m):] + [m] if m in stack else [n, m]
                rep.error(ids.get(n, "?"), "$", "depends_on cycle: " + " -> ".join(cyc))
            elif state.get(m) is None:
                visit(m, stack + [m])
        state[n] = 2

    for n in list(deps):
        if state.get(n) is None:
            visit(n, [n])


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", type=Path, default=DEFAULT_ROOT)
    ap.add_argument("--schemas", type=Path, default=DEFAULT_SCHEMAS)
    args = ap.parse_args()
    rep = validate(args.root, args.schemas)
    for w in rep.warnings:
        print(w)
    for e in rep.errors:
        print(e)
    if rep.errors:
        print(f"{len(rep.errors)} error(s)")
        return 1
    print("CONTENT_OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
