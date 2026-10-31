class_name RumourNetwork
extends Node
## Spreads rumours between settlements along the road graph. The truth lives in
## WorldState.rumours (rumour id -> POIs where it is known); this node only adds POIs to it, in
## exactly the shape NPCFacts.heard_rumours() reads (it matches the NPC's own POI or any POI
## registered in WorldState.poi_info with the same settlement). Each settlement is represented
## by one hub POI, so "the rumour reached Bree" means the Prancing Pony hub holds it.
##
## Each game day (WorldClock.day_passed) every settlement that knows a rumour rolls once per
## uninformed neighbour, so a rumour moves at most one hop per day. Travellers add a second,
## faster channel: an entity arriving in a settlement carries what it heard where it was before.

const DYNAMIC_FLAG: String = "rumour_net.dynamic"  ## rumour id -> {text, strength, max_hops, origin}
const INGESTED_FLAG: String = "rumour_net.ingested"  ## rumour ids already made from learned facts
const SUBJECT_FLAG_PREFIX: String = "rumour_subject."
const SUBJECT_PLACEHOLDER: String = "{player}"
const LEARNED_ID_PREFIX: String = "learned_"
const SAVE_KEY: String = "rumour_network"
const HASH_MASK: int = 0xffffff  ## keeps learned-rumour ids short; collisions only merge two identical-ish facts

var graph: RoadGraph = null
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

# settlement id -> hub POI id; settlement id -> {neighbour id -> route length in metres}
var _hub: Dictionary = {}
var _near: Dictionary = {}
# entity id -> {"settlement": String, "carry": Array[String]}
var _travellers: Dictionary = {}


func _init() -> void:
	rng.randomize()


func _ready() -> void:
	if graph == null:
		graph = RoadGraph.new()
		graph.load_region()
	rebuild()
	register_pois()
	WorldClock.day_passed.connect(_on_day_passed)
	EventBus.entity_moved.connect(_on_entity_moved)
	EventBus.flag_changed.connect(_on_flag_changed)
	SaveSystem.register_participant(SAVE_KEY, serialise, deserialise)


func _exit_tree() -> void:
	SaveSystem.unregister_participant(SAVE_KEY, serialise)


func seed_rng(value: int) -> void:
	rng.seed = value


# --- save/load -----------------------------------------------------------------

## The rumours themselves live in WorldState; this adds what only the network remembers: who
## carries what, and the RNG, so a reload continues the same spread instead of re-rolling it.
## RNG values are strings because JSON numbers (doubles) cannot hold a full 64-bit state.
func serialise() -> Dictionary:
	return {"travellers": _travellers.duplicate(true), "rng_seed": str(rng.seed), "rng_state": str(rng.state)}


func deserialise(d: Dictionary) -> void:
	_travellers = {}
	for id: String in (d.get("travellers", {}) as Dictionary):
		var t: Dictionary = d["travellers"][id]
		var carry: Array[String] = []
		for r: Variant in t.get("carry", []):
			carry.append(str(r))
		_travellers[id] = {"settlement": str(t.get("settlement", "")), "carry": carry}
	if d.has("rng_seed"):
		rng.seed = str(d["rng_seed"]).to_int()
		rng.state = str(d.get("rng_state", "0")).to_int()
	else:
		rng.randomize()


# --- settlement graph --------------------------------------------------------

## (Re)derives hubs and neighbours from `graph`. Two settlements are neighbours when the shortest
## road between their hubs does not pass through a third settlement, so rumours walk the road
## village by village instead of jumping across the map.
func rebuild() -> void:
	_hub = {}
	_near = {}
	var best_d: Dictionary = {}
	var ids: Array[String] = graph.poi_ids()
	ids.sort()
	for poi: String in ids:
		var s: String = graph.settlement_of(poi)
		if s == "" or not graph.is_routable(poi):
			continue
		var c: Vector3 = (graph.settlement_info(s) as Dictionary).get("center", Vector3.ZERO)
		var p: Vector3 = graph.poi_pos(poi)
		var d: float = Vector2(p.x, p.z).distance_to(Vector2(c.x, c.z))
		if not best_d.has(s) or d < float(best_d[s]):
			best_d[s] = d
			_hub[s] = poi
	var names: Array = _hub.keys()
	names.sort()
	for s: String in names:
		_near[s] = {}
	for i in range(names.size()):
		for j in range(i + 1, names.size()):
			var a: String = names[i]
			var b: String = names[j]
			var r: Dictionary = graph.route(_hub[a], _hub[b])
			if r.is_empty() or not _is_direct(r, a, b):
				continue
			(_near[a] as Dictionary)[b] = float(r["length"])
			(_near[b] as Dictionary)[a] = float(r["length"])


func _is_direct(r: Dictionary, a: String, b: String) -> bool:
	var nodes: Array = r["nodes"]
	for k in range(1, nodes.size() - 1):
		var s: String = graph.settlement_of(str(nodes[k]))
		if s != "" and s != a and s != b:
			return false
	return true


## WorldState.poi_info is normally filled by the world loader; this lets headless tests and
## tools get the same settlement matching without a world scene. Existing entries are kept.
func register_pois() -> void:
	for poi: String in graph.poi_ids():
		if not WorldState.poi_info.has(poi):
			WorldState.register_poi(poi, graph.poi_pos(poi), graph.settlement_of(poi))


func hub_of(settlement: String) -> String:
	return str(_hub.get(settlement, ""))


func settlement_ids() -> Array[String]:
	var out: Array[String] = []
	out.assign(_hub.keys())
	out.sort()
	return out


func neighbours_of(settlement: String) -> Dictionary:
	return (_near.get(settlement, {}) as Dictionary).duplicate()


## Settlement a POI belongs to; POIs outside every settlement (roadside camps) return "".
func settlement_of(poi: String) -> String:
	var s: String = graph.settlement_of(poi)
	if s == "":
		s = str((WorldState.poi_info.get(poi, {}) as Dictionary).get("settlement", ""))
	return s


## Settlements whose hub currently holds the rumour (plus any whose other POIs hold it).
func settlements_knowing(rumour_id: String) -> Array[String]:
	var out: Array[String] = []
	for poi: Variant in WorldState.rumours.get(rumour_id, []):
		var s: String = settlement_of(str(poi))
		if s != "" and s not in out:
			out.append(s)
	out.sort()
	return out


# --- spreading ---------------------------------------------------------------

## Chance that a settlement knowing a rumour passes it to one neighbour `distance_m` away today.
## Strength raises it linearly; distance divides it, so a stout rumour still crawls over long roads.
static func spread_probability(strength: int, distance_m: float) -> float:
	var per: float = float(Config.get_value("rumours.spread.p_per_strength", 0.3))
	var scale: float = maxf(float(Config.get_value("rumours.spread.distance_scale_m", 2000.0)), 1.0)
	var cap: float = float(Config.get_value("rumours.spread.p_max", 0.95))
	return clampf(float(strength) * per / (1.0 + distance_m / scale), 0.0, cap)


## One game day of spreading. Returns [[rumour_id, poi], ...] for everything that spread.
## Sources are read before any destination is written, so a rumour moves one hop per call.
func step_day() -> Array:
	ingest_learned_facts()
	var added: Array = []
	var ids: Array = WorldState.rumours.keys()
	ids.sort()
	for rid: String in ids:
		var info: Dictionary = rumour_info(rid)
		var known: Array[String] = settlements_knowing(rid)
		var origin: String = settlement_of(str(info.get("origin_poi", "")))
		if origin == "" and not known.is_empty():
			origin = known[0]
		var hops: Dictionary = _hops_from(origin)
		var max_hops: int = int(info.get("max_hops", Config.get_value("rumours.spread.default_max_hops", 4)))
		var strength: int = int(info.get("strength", Config.get_value("rumours.spread.default_strength", 2)))
		var reached: Array[String] = []
		for s: String in known:
			var near: Dictionary = _near.get(s, {})
			var order: Array = near.keys()
			order.sort()
			for n: String in order:
				if n in known or n in reached:
					continue
				if int(hops.get(n, max_hops + 1)) > max_hops:
					continue
				if rng.randf() < spread_probability(strength, float(near[n])):
					reached.append(n)
		for n in reached:
			added.append([rid, hub_of(n)])
	for pair: Array in added:
		WorldState.spread_rumour(str(pair[0]), str(pair[1]))
	return added


# Fewest settlement hops from `origin` (breadth-first); unreachable settlements are absent.
func _hops_from(origin: String) -> Dictionary:
	var hops: Dictionary = {}
	if origin == "" or not _near.has(origin):
		return hops
	hops[origin] = 0
	var queue: Array[String] = [origin]
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		for n: Variant in _near[cur]:
			if not hops.has(n):
				hops[n] = int(hops[cur]) + 1
				queue.append(str(n))
	return hops


## First day (1-based) on which `target_poi` held the rumour, simulating `days` days from the
## current WorldState; used by tests and tools to measure spread speed. -1 if it never arrived.
func simulate_days(rumour_id: String, target_poi: String, days: int) -> int:
	for day in range(1, days + 1):
		step_day()
		if WorldState.rumour_known_at(rumour_id, target_poi):
			return day
	return -1


# --- rumour metadata and text --------------------------------------------------

## Content rumour or dynamic (learned) rumour: {text, strength, max_hops, origin_poi, ...}.
static func rumour_info(rumour_id: String) -> Dictionary:
	var dyn: Dictionary = WorldState.get_flag(DYNAMIC_FLAG, {})
	if dyn.has(rumour_id):
		return (dyn[rumour_id] as Dictionary).duplicate()
	return (NPCContent.rumours().get(rumour_id, {}) as Dictionary).duplicate()


## Display text with the {player} placeholder resolved from flag rumour_subject.<id>.
static func resolve_text(rumour_id: String) -> String:
	var text: String = str(rumour_info(rumour_id).get("text", ""))
	if text.contains(SUBJECT_PLACEHOLDER):
		var subject: String = str(WorldState.get_flag(SUBJECT_FLAG_PREFIX + rumour_id, ""))
		if subject.is_empty():
			subject = str(Config.get_value("rumours.unknown_subject", "someone"))
		text = text.replace(SUBJECT_PLACEHOLDER, subject)
	return text


# --- learned facts -> rumours --------------------------------------------------

## Turns spreadable facts recorded by NPCMemory (flag learned_facts.<npc_id>) into rumours that
## start in that NPC's settlement. Idempotent. Returns the ids created by this call.
func ingest_learned_facts() -> Array[String]:
	var created: Array[String] = []
	var keys: Array = WorldState.flags.keys()
	keys.sort()
	for key: String in keys:
		if key.begins_with(NPCMemory.LEARNED_FLAG_PREFIX):
			created.append_array(_ingest_npc(key.substr(NPCMemory.LEARNED_FLAG_PREFIX.length())))
	return created


func _ingest_npc(npc_id: String) -> Array[String]:
	var created: Array[String] = []
	var facts: Array = WorldState.get_flag(NPCMemory.LEARNED_FLAG_PREFIX + npc_id, [])
	var done: Array = (WorldState.get_flag(INGESTED_FLAG, []) as Array).duplicate()
	var dyn: Dictionary = (WorldState.get_flag(DYNAMIC_FLAG, {}) as Dictionary).duplicate(true)
	for f: Variant in facts:
		var fact: String = str(f)
		var rid: String = "%s%s_%x" % [LEARNED_ID_PREFIX, npc_id, fact.hash() & HASH_MASK]
		if rid in done:
			continue
		var origin: String = _origin_for_npc(npc_id)
		if origin == "":
			continue  # the NPC is nowhere on the map yet; try again on a later call
		done.append(rid)
		dyn[rid] = {"text": fact, "origin_poi": origin, "origin_npc": npc_id,
				"strength": int(Config.get_value("rumours.learned.strength", 2)),
				"max_hops": int(Config.get_value("rumours.learned.max_hops", 3))}
		created.append(rid)
	if not created.is_empty():
		WorldState.set_flag(DYNAMIC_FLAG, dyn)
		WorldState.set_flag(INGESTED_FLAG, done)
		for rid in created:
			WorldState.spread_rumour(rid, str(dyn[rid]["origin_poi"]))
	return created


# The settlement hub if the NPC is in a settlement (so the whole village hears it), else the NPC's own POI.
func _origin_for_npc(npc_id: String) -> String:
	var poi: String = str(WorldState.entity_location(npc_id).get("poi", ""))
	if poi == "":
		poi = str(NPCContent.load_card(npc_id).get("home_poi", ""))
	if poi == "":
		return ""
	var s: String = settlement_of(poi)
	return hub_of(s) if s != "" and hub_of(s) != "" else poi


# --- travellers ----------------------------------------------------------------

## An entity arrived at `poi`. Entering a settlement different from the last one delivers the
## rumours it picked up there to this one (chance rises with strength); then it picks up what
## this settlement knows. POIs outside settlements (roadside camps) change nothing.
func note_arrival(entity_id: String, poi: String) -> Array[String]:
	var delivered: Array[String] = []
	var s: String = settlement_of(poi)
	if s == "" or hub_of(s) == "":
		return delivered
	var state: Dictionary = _travellers.get(entity_id, {"settlement": "", "carry": []})
	if state["settlement"] != s:
		for rid: String in state["carry"]:
			if WorldState.rumour_known_at(rid, hub_of(s)) or s in settlements_knowing(rid):
				continue
			var strength: int = int(rumour_info(rid).get("strength", Config.get_value("rumours.spread.default_strength", 2)))
			var p: float = clampf(float(strength) * float(Config.get_value("rumours.traveller.carry_p_per_strength", 0.2)),
					0.0, float(Config.get_value("rumours.traveller.carry_p_max", 0.9)))
			if rng.randf() < p:
				WorldState.spread_rumour(rid, hub_of(s))
				delivered.append(rid)
		var carry: Array[String] = []
		var ids: Array = WorldState.rumours.keys()
		ids.sort()
		for rid: String in ids:
			if s in settlements_knowing(rid) and carry.size() < int(Config.get_value("rumours.traveller.carry_max_rumours", 6)):
				carry.append(rid)
		state = {"settlement": s, "carry": carry}
	_travellers[entity_id] = state
	return delivered


func _on_day_passed(_now: int) -> void:
	step_day()


func _on_entity_moved(id: String, where: Variant) -> void:
	if where is String:
		note_arrival(id, where)


# NPCMemory records learned facts after the memory is stored, so react to that flag.
func _on_flag_changed(flag: String, _value: Variant) -> void:
	if flag.begins_with(NPCMemory.LEARNED_FLAG_PREFIX):
		_ingest_npc(flag.substr(NPCMemory.LEARNED_FLAG_PREFIX.length()))
