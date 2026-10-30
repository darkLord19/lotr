class_name VillagerSchedule
extends RefCounted
## Lightweight daily routine for ordinary villagers: home -> work -> (home) -> inn -> home.
## A pure function of (villager, template, game time): nothing is stored, nothing is simulated
## off-screen. Callers evaluate it only for settlements near the player (see `positions_near`),
## so far-away villagers cost nothing and simply "are where the clock says" when you arrive.
##
## Villager: {"id", "settlement", "home": poi, "work": poi, "inn": poi}; an empty "work"/"inn"
## means that stage is skipped (the villager stays where the previous stage left them).
## Template (minutes since midnight): work_start, work_end, inn_start, inn_end. Templates live in
## game/config/sim.json under sim.villager_templates, keyed by settlement faction.

const MINUTES_PER_DAY: int = 1440
const DEFAULT_TEMPLATE_KEY: String = "default"
const DEFAULT_TRANSIT_MINUTES: int = 20
const DEFAULT_JITTER_MINUTES: int = 30
const DEFAULT_RADIUS_M: float = 600.0
const FALLBACK_TEMPLATE: Dictionary = {"work_start": 480, "work_end": 1020, "inn_start": 1080, "inn_end": 1260}

enum Stage { HOME, WORK, INN }


static func template_for(faction: String) -> Dictionary:
	var all: Dictionary = Config.get_value("sim.villager_templates", {})
	if all.has(faction):
		return all[faction]
	return all.get(DEFAULT_TEMPLATE_KEY, FALLBACK_TEMPLATE)


# Per-villager shift so a whole village does not move in lockstep. Deterministic from the id.
static func jitter_minutes(villager_id: String, max_jitter: int) -> int:
	if max_jitter <= 0:
		return 0
	return posmod(villager_id.hash(), 2 * max_jitter + 1) - max_jitter


# Ordered day segments [{"start": minute, "stage": Stage}] covering 0..1440 (first starts at 0).
static func segments(tpl: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = [{"start": 0, "stage": Stage.HOME}]
	var ws: int = int(tpl["work_start"])
	var we: int = int(tpl["work_end"])
	var is_: int = int(tpl["inn_start"])
	var ie: int = int(tpl["inn_end"])
	out.append({"start": ws, "stage": Stage.WORK})
	if is_ > we:
		out.append({"start": we, "stage": Stage.HOME})
		out.append({"start": is_, "stage": Stage.INN})
	else:
		out.append({"start": we, "stage": Stage.INN})
	out.append({"start": ie, "stage": Stage.HOME})
	return out


static func stage_poi(villager: Dictionary, stage: int, fallback: String) -> String:
	var poi: String = fallback
	match stage:
		Stage.WORK:
			poi = str(villager.get("work", ""))
		Stage.INN:
			poi = str(villager.get("inn", ""))
		_:
			poi = str(villager.get("home", ""))
	return poi if poi != "" else fallback


# {"stage": Stage, "poi": String, "from_poi": String, "pos": Vector3, "moving": bool}
static func state_at(villager: Dictionary, tpl: Dictionary, now: int, graph: RoadGraph) -> Dictionary:
	var jitter: int = jitter_minutes(str(villager.get("id", "")),
			int(Config.get_value("sim.villager_jitter_minutes", DEFAULT_JITTER_MINUTES)))
	var transit: int = int(Config.get_value("sim.villager_transit_minutes", DEFAULT_TRANSIT_MINUTES))
	var m: int = posmod(now - jitter, MINUTES_PER_DAY)
	var segs: Array[Dictionary] = segments(tpl)
	var idx: int = 0
	for i in range(segs.size()):
		if m >= int(segs[i]["start"]):
			idx = i
	var home: String = str(villager.get("home", ""))
	# A stage the villager lacks (no inn) collapses onto the previous stage's place.
	var pois: Array[String] = []
	var prev_poi: String = home
	for s in segs:
		prev_poi = stage_poi(villager, int(s["stage"]), prev_poi)
		pois.append(prev_poi)
	var cur: String = pois[idx]
	var before: String = pois[(idx - 1 + segs.size()) % segs.size()]
	var into: int = m - int(segs[idx]["start"])
	var pos: Vector3 = graph.poi_pos(cur)
	var moving: bool = false
	if cur != before and into < transit:
		moving = true
		pos = graph.poi_pos(before).lerp(pos, float(into) / float(maxi(transit, 1)))
	return {"stage": segs[idx]["stage"], "poi": cur, "from_poi": before, "pos": pos, "moving": moving}


# Villagers of the settlements within `radius` of the player only. Returns id -> state_at().
static func positions_near(villagers: Array, player_pos: Vector3, now: int, graph: RoadGraph,
		radius: float = -1.0) -> Dictionary:
	var r: float = radius if radius >= 0.0 else float(Config.get_value("sim.villager_radius_m", DEFAULT_RADIUS_M))
	var near: Array[String] = graph.settlements_near(player_pos, r)
	var out: Dictionary = {}
	for raw: Variant in villagers:
		var v: Dictionary = raw
		var sid: String = str(v.get("settlement", ""))
		if sid not in near:
			continue
		var faction: String = str((graph.settlement_info(sid)).get("faction", ""))
		out[str(v.get("id", ""))] = state_at(v, template_for(faction), now, graph)
	return out
