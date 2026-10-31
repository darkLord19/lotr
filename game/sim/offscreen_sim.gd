class_name OffscreenSim
extends Node
## Abstract simulation of itinerary characters while they are off-screen. Every game minute each
## character on a "depart" leg moves along the road graph so that it reaches the next step's POI
## exactly at that step's (current, possibly shifted) due time. Positions go into WorldState with
## the same API the Timeline uses (move_entity), so there is a single truth.
##
## Division of labour with the Timeline:
##  - the Timeline owns *when* steps fire and teleports characters to a step's POI for camp/arrive/
##    stay/rest steps; the sim only moves characters *between* a fired depart step and its arrival.
##  - the sim registers a Timeline hold guard: an event that places a character somewhere cannot
##    fire while that character is still on the road (so in mode A a step "fires on arrival" and
##    its dependents shift by the lateness, instead of teleporting a walker).
## Seam for scene work: a spawned 3D body should call `report_body_progress()` with its real
## position; while a body exists for a character, call `set_body_driven(id, true)` so the sim stops
## moving it (the body then owns the abstract position).

signal leg_started(character: String, from_poi: String, to_poi: String)
signal leg_finished(character: String, poi: String, late_minutes: int)

# Defaults mirror game/config/sim.json; used only if the config is missing a key.
const DEFAULT_SPEEDS: Dictionary = {
	"walk": {"max": 12.0, "run": 24.0},
	"ride": {"max": 30.0, "run": 45.0},
}
const DEFAULT_MODE: String = "walk"
const DEFAULT_ARRIVE_EPSILON_M: float = 0.5

var clock: Node
var state: Node
var timeline: Node
var graph: RoadGraph

# character id -> {"id", "steps": Array[Dictionary], "cursor": int, "leg": Dictionary}
var tracks: Dictionary = {}
# Human-readable content problems (impossible speeds, unreachable legs).
var content_warnings: Array[String] = []
# Deviation log: {"kind": "dialogue"|"late_arrival", "character", ...}
var deviations: Array[Dictionary] = []

var _in_dialogue: Dictionary = {}
var _open_pauses: Dictionary = {}
var _body_driven: Dictionary = {}
var _arrived_this_tick: bool = false


const SAVE_KEY: String = "offscreen_sim"


# Registers on entering the tree only, so private instances built by unit tests stay out of the save.
func _ready() -> void:
	SaveSystem.register_participant(SAVE_KEY, serialise, deserialise)


func _exit_tree() -> void:
	SaveSystem.unregister_participant(SAVE_KEY, serialise)
	if timeline != null:
		timeline.remove_hold_guard(_is_blocked)


# Wires to a clock/state/timeline; tests bind fresh instances instead of the autoloads.
func bind(clock_node: Node, state_node: Node, timeline_node: Node, road_graph: RoadGraph) -> void:
	clock = clock_node
	state = state_node
	timeline = timeline_node
	graph = road_graph
	if not clock.minute_passed.is_connected(_on_minute_passed):
		clock.minute_passed.connect(_on_minute_passed)
	if not EventBus.dialogue_started.is_connected(_on_dialogue_started):
		EventBus.dialogue_started.connect(_on_dialogue_started)
		EventBus.dialogue_ended.connect(_on_dialogue_ended)
	timeline.add_hold_guard(_is_blocked)


# Builds one track per itinerary character from the Timeline's loaded content.
func load_tracks() -> void:
	tracks = {}
	for c in timeline.itinerary_characters():
		var steps: Array = timeline.itinerary_steps(c)
		# Stable by time so file order never decides which step comes first.
		var order: Array[Dictionary] = []
		for s: Variant in steps:
			order.append(s)
		order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return GameDate.parse(str(a.get("at", ""))) < GameDate.parse(str(b.get("at", ""))))
		tracks[c] = {"id": c, "steps": order, "cursor": 0, "leg": {}}


# --- public queries ---------------------------------------------------------

# {"poi", "pos"} when at a place, else {"edge": [a, b], "t", "pos"}; {} for unknown entities.
func abstract_position(id: String) -> Dictionary:
	var loc: Dictionary = state.entity_location(id)
	if loc["pos"] == null:
		return {}
	if loc["poi"] != "":
		return {"poi": loc["poi"], "pos": loc["pos"]}
	var stored: Variant = state.get_entity_data(id, "abstract")
	if stored is Dictionary and (stored as Dictionary).has("edge"):
		var ref: Dictionary = (stored as Dictionary).duplicate()
		ref["pos"] = loc["pos"]
		return ref
	return {"pos": loc["pos"]}


func is_travelling(id: String) -> bool:
	return tracks.has(id) and not (tracks[id]["leg"] as Dictionary).is_empty()


# True when `id` is on the road, either leading a leg or riding along as a companion.
func is_in_transit(id: String) -> bool:
	if is_travelling(id):
		return true
	return _leader_of(id) != ""


func is_holding(id: String) -> bool:
	return is_travelling(id) and bool((tracks[id]["leg"] as Dictionary).get("holding", false))


func set_body_driven(id: String, driven: bool) -> void:
	_body_driven[id] = driven


# A 3D body reports where it really is; the abstract position follows (one truth). The sim
# derives the new distance along the leg from the nearest point of the route.
func report_body_progress(id: String, world_pos: Vector3) -> void:
	if not is_travelling(id):
		return
	var leg: Dictionary = tracks[id]["leg"]
	var route: Dictionary = leg["route"]
	var best_s: float = float(leg["s"])
	var best_d: float = INF
	var cum: Array = route["cum"]
	var nodes: Array = route["nodes"]
	for i in range(1, nodes.size()):
		var a: Vector3 = graph.poi_pos(str(nodes[i - 1]))
		var b: Vector3 = graph.poi_pos(str(nodes[i]))
		var ab: Vector3 = b - a
		var len2: float = ab.length_squared()
		var t: float = clampf((world_pos - a).dot(ab) / len2, 0.0, 1.0) if len2 > 0.0 else 0.0
		var d: float = world_pos.distance_to(a + ab * t)
		if d < best_d:
			best_d = d
			best_s = float(cum[i - 1]) + t * (float(cum[i]) - float(cum[i - 1]))
	leg["s"] = best_s


# --- tick -------------------------------------------------------------------

func _on_minute_passed(now: int) -> void:
	tick(now)


func tick(now: int) -> void:
	_arrived_this_tick = false
	var leader_refs: Dictionary = {}
	for c: String in tracks:
		var track: Dictionary = tracks[c]
		if (track["leg"] as Dictionary).is_empty():
			_try_start_leg(track, now)
		if not (track["leg"] as Dictionary).is_empty():
			var ref: Dictionary = _advance(track, now)
			if not ref.is_empty():
				leader_refs[c] = ref
	_move_followers(leader_refs)
	# A step the guard was holding may be releasable now; do not wait a minute (that would
	# register as a 1-minute delay and shift dependents even for an on-time arrival).
	if _arrived_this_tick:
		timeline.process_due(now)


# Starts the next leg when a depart step has fired.
func _try_start_leg(track: Dictionary, now: int) -> void:
	var steps: Array = track["steps"]
	while int(track["cursor"]) < steps.size():
		var i: int = int(track["cursor"])
		var step: Dictionary = steps[i]
		if not timeline.is_fired(str(step["id"])):
			return
		track["cursor"] = i + 1
		if str(step.get("action", "")) != "depart":
			continue
		var next: Dictionary = steps[i + 1] if i + 1 < steps.size() else {}
		if not next.is_empty() and timeline.is_fired(str(next["id"])):
			continue  # joined late (e.g. loaded save): this leg is already over
		var leg: Dictionary = _build_leg(track, step, next, now)
		if not leg.is_empty():
			track["leg"] = leg
			leg_started.emit(str(track["id"]), str(step.get("from", "")), str(step.get("to", "")))
		return


func _build_leg(track: Dictionary, step: Dictionary, next: Dictionary, now: int) -> Dictionary:
	var c: String = str(track["id"])
	var from_poi: String = str(step.get("from", ""))
	var to_poi: String = str(step.get("to", ""))
	var origin: String = from_poi
	if graph.is_abstract(from_poi):
		# Off-map origin: the party emerges at the closest point of the road network.
		origin = graph.nearest_routable(graph.poi_pos(from_poi))
	var route: Dictionary = graph.route(origin, to_poi)
	if route.is_empty():
		_warn("%s: no road route %s -> %s (step %s); the Timeline will place them on arrival"
				% [c, from_poi, to_poi, step.get("id", "?")])
		return {}
	var mode: String = str(step.get("mode", DEFAULT_MODE))
	var arrive_id: String = str(next.get("id", ""))
	var started: int = int(timeline.fired_time(str(step["id"])))
	if started == GameDate.INVALID:
		started = now
	if arrive_id == "":
		_warn("%s: depart step %s has no following step" % [c, step.get("id", "?")])
	else:
		var allowed: int = int(timeline.due_time(arrive_id)) - started
		var needed: float = float(route["length"]) / float(maxi(allowed, 1))
		if needed > _speed(mode, "max"):
			_warn("%s: %s -> %s needs %.1f m/min on '%s' (max %.1f); will arrive late"
					% [c, from_poi, to_poi, needed, mode, _speed(mode, "max")])
	var companions: Array = []
	for comp: Variant in step.get("companions", []):
		companions.append(str(comp))
	var hold: Dictionary = _find_hold(c, to_poi, route)
	return {
		"depart_id": str(step["id"]), "arrive_id": arrive_id, "to": to_poi, "mode": mode,
		"route": route, "s": 0.0, "companions": companions, "holding": false,
		"hold_node": hold.get("node", ""), "hold_events": hold.get("events", []),
		"origin_abstract": origin != from_poi,
	}


# Mode-B waiting: if `character` is due to enter a settlement through a waits_for_player event and
# the settlement has a configured waiting point on the route, the sim parks there until released.
func _find_hold(character: String, dest: String, route: Dictionary) -> Dictionary:
	var settlement: String = graph.settlement_of(dest)
	var points: Dictionary = Config.get_value("sim.hold_points", {})
	if settlement == "" or not points.has(settlement):
		return {}
	var node: String = str(points[settlement])
	var at: float = graph.distance_to_node(route, node)
	if at <= 0.0 or at >= float(route["length"]):
		return {}
	var events: Array = []
	for id in timeline.waiting_event_ids(character):
		var area: Variant = (timeline.get_event(id) as Dictionary).get("trigger_area", null)
		if area is Dictionary and (str(area.get("settlement", "")) == settlement or str(area.get("poi", "")) == dest):
			events.append(id)
	return {"node": node, "events": events} if not events.is_empty() else {}


# One minute of travel. Returns the position ref written (for followers), or {} if none.
func _advance(track: Dictionary, now: int) -> Dictionary:
	var c: String = str(track["id"])
	var leg: Dictionary = track["leg"]
	if _body_driven.get(c, false):
		return {}
	if _group_in_dialogue(c, leg):
		return {}
	var route: Dictionary = leg["route"]
	var length: float = float(route["length"])
	var s: float = float(leg["s"])
	var limit: float = length
	var holding: bool = false
	if str(leg["hold_node"]) != "" and _hold_wanted(leg):
		limit = graph.distance_to_node(route, str(leg["hold_node"]))
		holding = true
	var mode: String = str(leg["mode"])
	var step_m: float = _speed(mode, "max")
	var arrive_id: String = str(leg["arrive_id"])
	if arrive_id != "":
		var deadline: int = int(timeline.due_time(arrive_id))
		# Pace so the remaining distance is covered by the deadline; when late the pace rises
		# until the run cap, which is the "hurry to catch up" after a deviation.
		var minutes_left: int = maxi(deadline - (now - 1), 1)
		step_m = minf((length - s) / float(minutes_left), _speed(mode, "run"))
	s = minf(s + step_m, limit)
	leg["s"] = s
	leg["holding"] = holding and s >= limit
	if length - s <= _arrive_epsilon():
		return _finish_leg(track, now)
	var ref: Dictionary = graph.locate(route, s)
	_write_position(c, ref)
	return ref


func _finish_leg(track: Dictionary, now: int) -> Dictionary:
	var c: String = str(track["id"])
	var leg: Dictionary = track["leg"]
	var to_poi: String = str(leg["to"])
	var ref: Dictionary = {"poi": to_poi, "pos": graph.poi_pos(to_poi)}
	_write_position(c, ref)
	var late: int = 0
	var arrive_id: String = str(leg["arrive_id"])
	if arrive_id != "":
		late = maxi(now - int(timeline.due_time(arrive_id)), 0)
	if late > 0:
		_log_deviation({"kind": "late_arrival", "character": c, "step": arrive_id, "late_minutes": late, "at": now})
	track["leg"] = {}
	_arrived_this_tick = true
	# Followers must be placed with the leader on this same tick.
	for comp: Variant in leg["companions"]:
		_place_follower(str(comp), ref)
	leg_finished.emit(c, to_poi, late)
	return {}


func _write_position(id: String, ref: Dictionary) -> void:
	if not state.has_entity(id):
		state.spawn_entity(id, "npc", ref["poi"] if ref.has("poi") else ref["pos"])
	var loc: Dictionary = state.entity_location(id)
	if ref.has("poi"):
		if loc["poi"] != ref["poi"]:
			state.move_entity(id, ref["poi"])
		state.set_entity_data(id, "abstract", {})
	else:
		state.move_entity(id, ref["pos"])
		state.set_entity_data(id, "abstract", {"edge": ref["edge"], "t": ref["t"]})


func _place_follower(id: String, ref: Dictionary) -> void:
	# A companion with its own active leg is driven by its own itinerary (e.g. Farmer Maggot).
	if is_travelling(id):
		return
	_write_position(id, ref)


func _move_followers(leader_refs: Dictionary) -> void:
	for leader: String in leader_refs:
		var leg: Dictionary = tracks[leader]["leg"]
		for comp: Variant in leg["companions"]:
			_place_follower(str(comp), leader_refs[leader])


func _hold_wanted(leg: Dictionary) -> bool:
	for id: Variant in leg["hold_events"]:
		if timeline.would_hold(str(id)):
			return true
	return false


# --- Timeline guard ---------------------------------------------------------

# True while an event would place a character who is still walking: it must wait for arrival.
func _is_blocked(event_id: String) -> bool:
	var ev: Dictionary = timeline.get_event(event_id)
	for effect: Variant in ev.get("effects", []):
		if effect is Dictionary and (effect as Dictionary).has("move_entity"):
			var target: String = str(((effect as Dictionary)["move_entity"] as Dictionary).get("id", ""))
			if is_in_transit(target):
				return true
	return false


func _leader_of(id: String) -> String:
	for c: String in tracks:
		var leg: Dictionary = tracks[c]["leg"]
		if not leg.is_empty() and id in (leg["companions"] as Array):
			return c
	return ""


# --- deviations (dialogue) --------------------------------------------------

func _on_dialogue_started(npc_id: String) -> void:
	_in_dialogue[npc_id] = true
	for c: String in tracks:
		var leg: Dictionary = tracks[c]["leg"]
		if not leg.is_empty() and (c == npc_id or npc_id in (leg["companions"] as Array)) and not _open_pauses.has(c):
			_open_pauses[c] = {"npc": npc_id, "since": int(clock.now), "s": float(leg["s"])}


func _on_dialogue_ended(npc_id: String) -> void:
	_in_dialogue.erase(npc_id)
	for c: String in _open_pauses.keys():
		var p: Dictionary = _open_pauses[c]
		if p["npc"] == npc_id:
			_open_pauses.erase(c)
			_log_deviation({"kind": "dialogue", "character": c, "with": npc_id, "since": p["since"],
					"until": int(clock.now), "minutes": int(clock.now) - int(p["since"])})


func _group_in_dialogue(id: String, leg: Dictionary) -> bool:
	if _in_dialogue.is_empty():
		return false
	if _in_dialogue.has(id):
		return true
	for comp: Variant in leg["companions"]:
		if _in_dialogue.has(str(comp)):
			return true
	return false


func _log_deviation(entry: Dictionary) -> void:
	deviations.append(entry)
	print("[OffscreenSim] deviation: %s" % JSON.stringify(entry))


# --- helpers ----------------------------------------------------------------

func _warn(msg: String) -> void:
	content_warnings.append(msg)
	push_warning("OffscreenSim content warning: " + msg)


func _speed(mode: String, kind: String) -> float:
	var def: Dictionary = DEFAULT_SPEEDS.get(mode, DEFAULT_SPEEDS[DEFAULT_MODE])
	return float(Config.get_value("sim.speeds_m_per_min.%s.%s" % [mode, kind], def[kind]))


func _arrive_epsilon() -> float:
	return float(Config.get_value("sim.arrive_epsilon_m", DEFAULT_ARRIVE_EPSILON_M))


# --- save/load --------------------------------------------------------------

func serialise() -> Dictionary:
	var out: Dictionary = {}
	for c: String in tracks:
		out[c] = {"cursor": tracks[c]["cursor"], "leg": (tracks[c]["leg"] as Dictionary).duplicate(true)}
	return {"tracks": out, "deviations": deviations.duplicate(true)}


func deserialise(d: Dictionary) -> void:
	load_tracks()
	var saved: Dictionary = d.get("tracks", {})
	for c: String in saved:
		if tracks.has(c):
			tracks[c]["cursor"] = int(saved[c].get("cursor", 0))
			tracks[c]["leg"] = (saved[c].get("leg", {}) as Dictionary).duplicate(true)
	deviations = []
	for entry: Variant in d.get("deviations", []):
		var e: Dictionary = (entry as Dictionary).duplicate()
		# JSON hands integers back as floats; minutes must stay ints.
		for k: String in ["at", "late_minutes"]:
			if e.has(k):
				e[k] = int(e[k])
		deviations.append(e)
	# Dialogue pauses and body ownership belong to live scenes, which re-announce themselves.
	_in_dialogue = {}
	_open_pauses = {}
	_body_driven = {}
