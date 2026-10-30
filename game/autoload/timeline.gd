extends Node
# Drives canon: timeline events and itinerary steps fire on the world clock.
# Mode A fires everything on time. Mode B holds `waits_for_player` events until the
# player is in their trigger_area (or window_end), then shifts transitive dependents
# by the same delay so cause and effect keep their spacing.

const EVENTS_DIR: String = "res://content/timeline/events"
const ITINERARIES_DIR: String = "res://content/timeline/itineraries"
# Itinerary actions that put the character at a place (others are in transit).
const ARRIVE_ACTIONS: Array[String] = ["camp", "arrive", "stay", "rest"]

var clock: Node
var state: Node

# id -> event Dictionary (normalised, see _normalise)
var _events: Dictionary = {}
# Insertion index per id, for a stable order among simultaneous events.
var _index: Dictionary = {}
# id -> current due time (minutes); shifted by upstream delays.
var _due: Dictionary = {}
# id -> minutes the event was delayed beyond its due time when it fired.
var _delays: Dictionary = {}
# id -> game minute it actually fired.
var _fired: Dictionary = {}
# ids currently waiting for the player (derived each pass; saved for inspection).
var _held: Dictionary = {}
# Unfired ids ordered by (due, index).
var _pending: Array[String] = []
var _processing: bool = false


func _ready() -> void:
	load_content_dirs()
	bind(WorldClock, WorldState)


# Wires to a clock and state; tests bind fresh instances instead of the autoloads.
func bind(clock_node: Node, state_node: Node) -> void:
	clock = clock_node
	state = state_node
	if not clock.minute_passed.is_connected(_on_minute_passed):
		clock.minute_passed.connect(_on_minute_passed)
	if not EventBus.entity_moved.is_connected(_on_entity_moved):
		EventBus.entity_moved.connect(_on_entity_moved)


# --- loading ---------------------------------------------------------------

func load_content_dirs(events_dir: String = EVENTS_DIR, itineraries_dir: String = ITINERARIES_DIR) -> void:
	for path in _json_files(events_dir):
		var data: Variant = _read_json(path)
		if data is Array:
			add_events(data)
		elif data is Dictionary:
			add_events([data])
	for path in _json_files(itineraries_dir):
		var data: Variant = _read_json(path)
		if data is Dictionary:
			add_itinerary(data)


func add_events(list: Array) -> void:
	for raw: Variant in list:
		if raw is Dictionary:
			_add_event(_normalise(raw))
	_resort()


func add_itinerary(it: Dictionary) -> void:
	var character: String = str(it.get("character", ""))
	for raw: Variant in it.get("steps", []):
		if not (raw is Dictionary):
			continue
		var step: Dictionary = raw
		var companions: Array = step.get("companions", [])
		var actors: Array = [character]
		actors.append_array(companions)
		var effects: Array = (step.get("effects", []) as Array).duplicate(true)
		var dest: String = str(step.get("at_poi", ""))
		if str(step.get("action", "")) in ARRIVE_ACTIONS and dest != "":
			for a: Variant in actors:
				effects.append({"move_entity": {"id": a, "poi": dest}})
		var ev: Dictionary = {
			"id": step.get("id", "%s_%s" % [character, step.get("at", "")]),
			"at": step.get("at", ""),
			"type": "itinerary_step",
			"location": dest,
			"actors": actors,
			"effects": effects,
			"depends_on": step.get("depends_on", []),
			"step": step,
		}
		_add_event(_normalise(ev))
	_resort()


func clear() -> void:
	_events = {}
	_index = {}
	_due = {}
	_delays = {}
	_fired = {}
	_held = {}
	_pending = []


func _normalise(raw: Dictionary) -> Dictionary:
	var ev: Dictionary = raw.duplicate(true)
	ev["id"] = str(ev.get("id", ""))
	var at: int = GameDate.parse(str(ev.get("at", "")))
	ev["at_min"] = at
	# Keep the window as a length so shifting the event shifts the window too.
	var window_len: int = -1
	var we: Variant = ev.get("window_end", null)
	if we != null and str(we) != "":
		var we_min: int = GameDate.parse(str(we))
		if we_min != GameDate.INVALID and at != GameDate.INVALID:
			window_len = maxi(we_min - at, 0)
	ev["window_len"] = window_len
	ev["waits_for_player"] = bool(ev.get("waits_for_player", false))
	ev["depends_on"] = ev.get("depends_on", [])
	ev["effects"] = ev.get("effects", [])
	return ev


func _add_event(ev: Dictionary) -> void:
	var id: String = ev["id"]
	if id == "" or int(ev["at_min"]) == GameDate.INVALID:
		push_warning("Timeline: skipping event with missing id or bad date: %s" % str(ev.get("id", "?")))
		return
	if _events.has(id):
		push_warning("Timeline: duplicate event id %s ignored" % id)
		return
	_index[id] = _events.size()
	_events[id] = ev
	_due[id] = ev["at_min"]
	_pending.append(id)


func _resort() -> void:
	_pending.sort_custom(func(a: String, b: String) -> bool:
		if _due[a] != _due[b]:
			return _due[a] < _due[b]
		return _index[a] < _index[b])


func _json_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for sub in dir.get_directories():
		out.append_array(_json_files(dir_path.path_join(sub)))
	for f in dir.get_files():
		if f.ends_with(".json"):
			out.append(dir_path.path_join(f))
	out.sort()
	return out


func _read_json(path: String) -> Variant:
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		push_warning("Timeline: bad JSON in %s" % path)
		return null
	return json.data


# --- queries ---------------------------------------------------------------

func has_event(id: String) -> bool:
	return _events.has(id)


func get_event(id: String) -> Dictionary:
	return _events.get(id, {})


func is_fired(id: String) -> bool:
	return _fired.has(id)


func is_held(id: String) -> bool:
	return _held.has(id)


func due_time(id: String) -> int:
	return int(_due.get(id, GameDate.INVALID))


func delay_of(id: String) -> int:
	return int(_delays.get(id, 0))


func fired_time(id: String) -> int:
	return int(_fired.get(id, GameDate.INVALID))


# Unfired events in due order (current, possibly shifted, times).
func upcoming_ids() -> Array[String]:
	return _pending.duplicate()


func event_count() -> int:
	return _events.size()


# --- firing ----------------------------------------------------------------

func _on_minute_passed(now: int) -> void:
	process_due(now)


# Re-check holds the moment the player arrives rather than waiting for the next minute.
func _on_entity_moved(id: String, _where: Variant) -> void:
	if id == "player" and clock != null and not _held.is_empty():
		process_due(int(clock.now))


func process_due(now: int) -> void:
	if _processing:
		return
	_processing = true
	var progress: bool = true
	while progress:
		progress = false
		_held = {}
		for id in _pending:
			if int(_due[id]) > now:
				break
			if not _deps_done(id):
				continue
			if _should_hold(id, now):
				_held[id] = true
				continue
			_fire(id, now)
			progress = true
			break  # shifts may have reordered _pending
	_processing = false


func _deps_done(id: String) -> bool:
	for dep: Variant in (_events[id] as Dictionary)["depends_on"]:
		var d: String = str(dep)
		if _events.has(d) and not _fired.has(d):
			return false
	return true


func _should_hold(id: String, now: int) -> bool:
	var ev: Dictionary = _events[id]
	if not bool(ev["waits_for_player"]) or clock == null or clock.mode != &"B":
		return false
	var wl: int = int(ev["window_len"])
	if wl >= 0 and now >= int(_due[id]) + wl:
		return false
	var area: Variant = ev.get("trigger_area", null)
	if area is Dictionary and _player_in_area(area):
		return false
	return true


func _player_in_area(area: Dictionary) -> bool:
	var loc: Dictionary = state.entity_location("player")
	var poi: String = loc["poi"]
	var want_poi: String = str(area.get("poi", ""))
	if want_poi != "":
		if poi == want_poi:
			return true
		var radius: float = float(area.get("radius", 0.0))
		var pos: Variant = loc["pos"]
		if radius > 0.0 and pos is Vector3 and state.poi_info.has(want_poi):
			var target: Vector3 = (state.poi_info[want_poi] as Dictionary)["pos"]
			var p: Vector3 = pos
			# Horizontal distance: height shouldn't decide whether you were "there".
			return Vector2(p.x, p.z).distance_to(Vector2(target.x, target.z)) <= radius
	var want_settlement: String = str(area.get("settlement", ""))
	if want_settlement != "" and poi != "" and state.poi_info.has(poi):
		return (state.poi_info[poi] as Dictionary)["settlement"] == want_settlement
	return false


func _fire(id: String, now: int) -> void:
	var ev: Dictionary = _events[id]
	var delay: int = maxi(now - int(_due[id]), 0)
	_pending.erase(id)
	_fired[id] = now
	_held.erase(id)
	if delay > 0:
		_delays[id] = delay
		_shift_dependents(id, delay)
	for effect: Variant in ev["effects"]:
		if effect is Dictionary:
			_apply_effect(effect)
	var rumour: Variant = ev.get("rumour", null)
	if rumour is Dictionary:
		state.spread_rumour(str((rumour as Dictionary).get("id", "")), str((rumour as Dictionary).get("origin_poi", "")))
	EventBus.timeline_event_fired.emit(id)


func _shift_dependents(id: String, delay: int) -> void:
	var seen: Dictionary = {}
	var frontier: Array[String] = [id]
	while not frontier.is_empty():
		var cur: String = frontier.pop_back()
		for other: String in _events:
			if seen.has(other) or _fired.has(other):
				continue
			if cur in ((_events[other] as Dictionary)["depends_on"] as Array):
				seen[other] = true
				_due[other] = int(_due[other]) + delay
				frontier.append(other)
	if not seen.is_empty():
		_resort()


func _apply_effect(effect: Dictionary) -> void:
	for key: String in effect:
		var v: Variant = effect[key]
		match key:
			"set_flag":
				if v is Dictionary:
					state.set_flag(str(v.get("flag", "")), v.get("value", true))
				else:
					state.set_flag(str(v), true)
			"clear_flag":
				state.set_flag(str(v), false)
			"add_knowledge":
				state.add_knowledge(str(v.get("npc", "")), str(v.get("knowledge_id", "")))
			"move_entity":
				var to: Variant = v.get("poi", v.get("to", ""))
				if v.has("pos"):
					var p: Array = v["pos"]
					to = Vector3(p[0], p[1], p[2])
				if not state.has_entity(str(v.get("id", ""))):
					state.spawn_entity(str(v.get("id", "")), str(v.get("kind", "npc")), to)
				else:
					state.move_entity(str(v.get("id", "")), to)
			"give_item":
				state.transfer_item(str(v.get("item", "")), str(v.get("from", "")), str(v.get("to", "")), int(v.get("count", 1)))
			"spread_rumour":
				state.spread_rumour(str(v.get("rumour_id", v.get("id", ""))), str(v.get("poi", "")))
			_:
				push_warning("Timeline: unknown effect '%s'" % key)


# --- save/load -------------------------------------------------------------

# Only deviations from the content are saved: what fired, delays, shifted due times
# and current holds. Content itself is reloaded from disk.
func serialise() -> Dictionary:
	var shifted: Dictionary = {}
	for id: String in _due:
		if not _fired.has(id) and int(_due[id]) != int((_events[id] as Dictionary)["at_min"]):
			shifted[id] = _due[id]
	return {"fired": _fired.duplicate(), "delays": _delays.duplicate(), "shifted": shifted, "held": _held.keys()}


func deserialise(d: Dictionary) -> void:
	_fired = {}
	_delays = {}
	_held = {}
	for id: String in (d.get("fired", {}) as Dictionary):
		_fired[id] = int(d["fired"][id])
	for id: String in (d.get("delays", {}) as Dictionary):
		_delays[id] = int(d["delays"][id])
	for id: String in _events:
		_due[id] = (_events[id] as Dictionary)["at_min"]
	for id: String in (d.get("shifted", {}) as Dictionary):
		if _events.has(id):
			_due[id] = int(d["shifted"][id])
	for id: Variant in d.get("held", []):
		_held[str(id)] = true
	_pending = []
	for id: String in _events:
		if not _fired.has(id):
			_pending.append(id)
	_resort()
