extends GutTest
## Runs the real content (itineraries + region) through Timeline + OffscreenSim on private
## clock/state instances, so nothing here touches the autoloads' state.

const WorldClockScript: GDScript = preload("res://autoload/world_clock.gd")
const WorldStateScript: GDScript = preload("res://autoload/world_state.gd")
const TimelineScript: GDScript = preload("res://autoload/timeline.gd")

# Required by the plan: abstract positions must match canon POIs within this distance.
const CANON_TOLERANCE_M: float = 50.0
# One minute before the first itinerary step (09-20 00:00) so it fires with zero delay.
const CONTENT_START: String = "3018-09-19T23:59"
const FRODO_PARTY: Array[String] = ["frodo", "sam", "pippin", "merry"]

var clock: Node
var ws: Node
var tl: Node
var sim: OffscreenSim
var graph: RoadGraph


func _build(start_iso: String, load_content: bool = true) -> void:
	clock = autofree(WorldClockScript.new())
	ws = autofree(WorldStateScript.new())
	tl = autofree(TimelineScript.new())
	tl.bind(clock, ws)
	graph = RoadGraph.new()
	graph.load_region()
	for id in graph.poi_ids():
		ws.register_poi(id, graph.poi_pos(id), graph.settlement_of(id))
	if load_content:
		tl.load_content_dirs()
	sim = autofree(OffscreenSim.new())
	sim.bind(clock, ws, tl, graph)
	sim.load_tracks()
	clock.now = GameDate.parse(start_iso)
	ws.spawn_entity("player", "player", "bag_end")


func _run_to(iso: String) -> void:
	clock.advance(GameDate.parse(iso) - clock.now)


func _dist(id: String, poi: String) -> float:
	var pos: Variant = ws.entity_location(id)["pos"]
	assert_not_null(pos, "%s has no position" % id)
	if pos == null:
		return INF
	return (pos as Vector3).distance_to(graph.poi_pos(poi))


# The POI a character should be at the instant a step fires: departing = origin, otherwise the place.
func _canon_poi(step: Dictionary) -> String:
	return str(step["from"]) if str(step["action"]) == "depart" else str(step["at_poi"])


func test_frodo_party_matches_canon_at_every_step_time() -> void:
	_build(CONTENT_START)
	_run_to("3018-09-23T12:00")
	var steps: Array = tl.itinerary_steps("frodo")
	steps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return GameDate.parse(a["at"]) < GameDate.parse(b["at"]))
	var end: int = GameDate.parse("3018-09-30T06:00")
	var checked: int = 0
	for step: Dictionary in steps:
		var t: int = GameDate.parse(str(step["at"]))
		if t < clock.now or t > end:
			continue
		var poi: String = _canon_poi(step)
		clock.advance(t - clock.now)
		if graph.is_abstract(poi) or (str(step["action"]) == "depart" and graph.is_abstract(str(step["from"]))):
			# Abstract place: the Timeline places them at its (map-less) POI, nothing to measure on roads.
			continue
		for who in FRODO_PARTY:
			if who == "merry" and t < GameDate.parse("3018-09-26T06:00"):
				continue  # Merry joins at Crickhollow
			if who in ["sam", "pippin"] or who == "frodo" or who == "merry":
				assert_lt(_dist(who, poi), CANON_TOLERANCE_M, "%s at %s (%s)" % [who, step["id"], step["at"]])
		checked += 1
	assert_gt(checked, 10, "most steps are measurable")
	assert_eq(sim.content_warnings, [] as Array[String], "real content needs no clamped speeds")
	_run_to("3018-09-30T06:00")
	assert_true(tl.is_fired("party_arrives_pony"), "mode A: the party enters the Pony on time")
	assert_eq(ws.entity_location("frodo")["poi"], "prancing_pony")


func test_khamul_is_at_bagshot_row_on_the_evening_of_the_23rd() -> void:
	_build(CONTENT_START)
	_run_to("3018-09-23T19:00")
	assert_eq(ws.entity_location("black_rider_khamul")["poi"], "bagshot_row")
	assert_lt(_dist("black_rider_khamul", "bagshot_row"), CANON_TOLERANCE_M)
	assert_true(tl.is_fired("rider_questions_gaffer"))


func test_mid_leg_position_is_on_the_road_at_the_right_fraction() -> void:
	_build(CONTENT_START)
	_run_to("3018-09-24T01:00")  # 5 of the 6 hours between leaving Bag End and Woody End
	var route: Dictionary = graph.route("bag_end", "woody_end_camp")
	var expect: Vector3 = graph.locate(route, float(route["length"]) * 300.0 / 360.0)["pos"]
	var ap: Dictionary = sim.abstract_position("frodo")
	assert_true(ap.has("edge"), "between places, position is edge + t")
	assert_true(ap.has("t") and ap.has("pos"))
	assert_lt((ap["pos"] as Vector3).distance_to(expect), 20.0)
	assert_eq(ap["pos"], ws.entity_location("frodo")["pos"], "one truth: WorldState")
	assert_lt((ws.entity_location("sam")["pos"] as Vector3).distance_to(ap["pos"]), 0.01, "companions travel as a group")
	assert_true(sim.is_in_transit("pippin"))
	_run_to("3018-09-24T12:00")
	var rest: Dictionary = sim.abstract_position("frodo")
	assert_eq(rest["poi"], "woody_end_camp", "camping keeps still")
	assert_false(sim.is_travelling("frodo"))


func test_arrival_does_not_double_move() -> void:
	_build(CONTENT_START)
	var moves: Array[String] = []
	var counter: Callable = func(id: String, _where: Variant) -> void:
		if id == "frodo":
			moves.append(id)
	_run_to("3018-09-24T01:58")
	EventBus.entity_moved.connect(counter)
	_run_to("3018-09-24T02:05")
	EventBus.entity_moved.disconnect(counter)
	# Arrival step at 02:00: the final road step plus (at most) the arrival placement, never a per-minute stream after it.
	assert_lte(moves.size(), 3)
	assert_eq(tl.fired_time("frodo_camps_woody_end"), GameDate.parse("3018-09-24T02:00"))
	assert_eq(tl.delay_of("frodo_camps_woody_end"), 0, "on-time arrival is not a delay")


func test_mode_b_party_holds_west_of_bree_then_enters_with_the_player() -> void:
	_build(CONTENT_START)
	clock.set_mode(&"B")
	_run_to("3018-09-30T06:00")
	assert_false(tl.is_fired("party_arrives_pony"))
	assert_true(sim.is_holding("frodo"), "parked at the waiting point")
	assert_lt(_dist("frodo", "bree_waiting_point"), CANON_TOLERANCE_M)
	assert_lt(_dist("sam", "bree_waiting_point"), CANON_TOLERANCE_M)
	assert_false(tl.is_fired("frodo_at_bree_west_gate"), "not through the gate yet")
	var original_raid: int = GameDate.parse("3018-09-30T01:30")
	var original_leave: int = GameDate.parse("3018-09-30T09:30")
	assert_eq(tl.due_time("pony_raided"), original_raid, "nothing shifted while waiting inside the window")
	# The player walks into Bree.
	ws.move_entity("player", "prancing_pony")
	var entered_at: int = clock.now
	clock.advance(60)
	assert_true(tl.is_fired("frodo_at_bree_west_gate"))
	assert_true(tl.is_fired("party_arrives_pony"))
	assert_true(ws.get_flag("party_in_bree"))
	assert_eq(ws.entity_location("frodo")["poi"], "prancing_pony")
	assert_gt(tl.fired_time("party_arrives_pony"), entered_at, "the party needed time to walk in")
	var delay: int = tl.delay_of("party_arrives_pony")
	assert_gt(delay, 0)
	assert_eq(tl.due_time("pony_raided"), original_raid + delay, "later steps shift by the same delay")
	assert_eq(tl.due_time("frodo_leaves_bree"), original_leave + delay)
	assert_false(sim.is_holding("frodo"))


func test_mode_b_party_does_not_wait_if_the_player_is_already_in_bree() -> void:
	_build(CONTENT_START)
	clock.set_mode(&"B")
	ws.move_entity("player", "prancing_pony")
	_run_to("3018-09-30T06:00")
	assert_true(tl.is_fired("party_arrives_pony"))
	assert_eq(tl.delay_of("party_arrives_pony"), 0)
	assert_false(sim.is_holding("frodo"))


func test_dialogue_pauses_travel_and_the_party_hurries_to_catch_up() -> void:
	_build(CONTENT_START)
	_run_to("3018-09-24T00:00")
	var before: Vector3 = ws.entity_location("frodo")["pos"]
	EventBus.dialogue_started.emit("sam")  # talking to a companion stops the whole group
	clock.advance(60)
	assert_eq(ws.entity_location("frodo")["pos"], before, "paused while talking")
	assert_eq(ws.entity_location("sam")["pos"], before)
	EventBus.dialogue_ended.emit("sam")
	var dialogue_logs: Array = sim.deviations.filter(func(d: Dictionary) -> bool: return d["kind"] == "dialogue")
	assert_eq(dialogue_logs.size(), 1)
	assert_eq(dialogue_logs[0]["minutes"], 60)
	# One hour lost, but the run speed is high enough to make it up by the original arrival time.
	var route: Dictionary = graph.route("bag_end", "woody_end_camp")
	var normal_pace: float = float(route["length"]) / 360.0
	clock.advance(1)
	var after: Vector3 = ws.entity_location("frodo")["pos"]
	assert_gt(before.distance_to(after), normal_pace * 1.5, "hurrying, faster than the scheduled pace")
	_run_to("3018-09-24T02:00")
	assert_true(tl.is_fired("frodo_camps_woody_end"))
	assert_eq(tl.delay_of("frodo_camps_woody_end"), 0)


func test_long_dialogue_makes_the_arrival_step_wait_and_shifts_dependents() -> void:
	_build(CONTENT_START)
	_run_to("3018-09-24T00:00")
	EventBus.dialogue_started.emit("frodo")
	clock.advance(180)
	EventBus.dialogue_ended.emit("frodo")
	assert_false(tl.is_fired("frodo_camps_woody_end"), "a step cannot fire before arrival, even past its time")
	assert_true(tl.is_held("frodo_camps_woody_end") or not tl.is_fired("frodo_camps_woody_end"))
	var gildor_meeting_due: int = tl.due_time("gildor_meeting")
	_run_to("3018-09-24T12:00")
	assert_true(tl.is_fired("frodo_camps_woody_end"))
	var late: int = tl.delay_of("frodo_camps_woody_end")
	assert_gt(late, 0)
	# Remaining third of the road at the 24 m/min run cap.
	var route: Dictionary = graph.route("bag_end", "woody_end_camp")
	var expected_late: int = 60 + int(ceil(float(route["length"]) / 3.0 / 24.0))  # resumed 60 min after the 02:00 due time
	assert_between(late, expected_late - 3, expected_late + 3)
	var arrivals: Array = sim.deviations.filter(func(d: Dictionary) -> bool: return d["kind"] == "late_arrival")
	assert_eq(arrivals.size(), 1)
	assert_eq(ws.entity_location("frodo")["poi"], "woody_end_camp")
	assert_eq(tl.due_time("gildor_meeting"), gildor_meeting_due, "unrelated dependents of later steps are untouched until they fire")


func test_impossible_leg_logs_a_warning_and_arrives_late_at_run_speed() -> void:
	_build("3018-01-01T00:00", false)
	graph.load_dict({"id": "t", "pois": [{"id": "a", "pos": [0, 0, 0]}, {"id": "b", "pos": [1000, 0, 0]}],
			"road_graph": {"edges": [["a", "b", "road"]]}})
	tl.add_itinerary({"character": "runner", "steps": [
		{"id": "r_stay", "at": "3018-01-01T00:00", "action": "stay", "at_poi": "a"},
		{"id": "r_go", "at": "3018-01-01T01:00", "action": "depart", "from": "a", "to": "b", "mode": "walk"},
		{"id": "r_there", "at": "3018-01-01T01:10", "action": "arrive", "at_poi": "b"}]})
	sim.load_tracks()
	_run_to("3018-01-01T03:00")
	assert_eq(sim.content_warnings.size(), 1)
	assert_true(tl.is_fired("r_there"))
	# 1000 m at the 24 m/min walking run cap needs 42 minutes, not 10.
	assert_between(tl.fired_time("r_there") - GameDate.parse("3018-01-01T01:00"), 41, 44)


func test_unroutable_leg_is_warned_and_left_to_the_timeline() -> void:
	_build("3018-01-01T00:00", false)
	graph.load_dict({"id": "t", "pois": [{"id": "a", "pos": [0, 0, 0]}, {"id": "ghost", "pos": [50, 0, 0], "abstract": true}],
			"road_graph": {"edges": []}})
	tl.add_itinerary({"character": "wisp", "steps": [
		{"id": "w_stay", "at": "3018-01-01T00:00", "action": "stay", "at_poi": "a"},
		{"id": "w_go", "at": "3018-01-01T01:00", "action": "depart", "from": "a", "to": "ghost"},
		{"id": "w_there", "at": "3018-01-01T02:00", "action": "arrive", "at_poi": "ghost"}]})
	sim.load_tracks()
	_run_to("3018-01-01T02:00")
	assert_eq(sim.content_warnings.size(), 1)
	assert_eq(ws.entity_location("wisp")["poi"], "ghost", "Timeline still places them")
