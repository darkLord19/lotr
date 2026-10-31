extends GutTest
## M1-T17 canon run: mode A, no player interaction, the whole content window on the real systems.

const WorldClockScript: GDScript = preload("res://autoload/world_clock.gd")
const WorldStateScript: GDScript = preload("res://autoload/world_state.gd")
const TimelineScript: GDScript = preload("res://autoload/timeline.gd")

const RUN_START: String = "3018-09-19T23:59"
const RUN_END: String = "3018-10-07T00:00"

var clock: Node
var ws: Node
var tl: Node
var sim: OffscreenSim
var fired: Array[String] = []
var fired_at: Dictionary = {}


func before_all() -> void:
	clock = WorldClockScript.new()
	ws = WorldStateScript.new()
	tl = TimelineScript.new()
	tl.bind(clock, ws)
	var graph := RoadGraph.new()
	graph.load_region()
	for id in graph.poi_ids():
		ws.register_poi(id, graph.poi_pos(id), graph.settlement_of(id))
	tl.load_content_dirs()
	sim = OffscreenSim.new()
	sim.bind(clock, ws, tl, graph)
	sim.load_tracks()
	clock.now = GameDate.parse(RUN_START)
	clock.set_mode(&"A")
	# Far from every waiting event: the player never takes part.
	ws.spawn_entity("player", "player", "bag_end")
	_connect_fire_log()
	clock.advance(GameDate.parse(RUN_END) - clock.now)


func _connect_fire_log() -> void:
	# Timeline emits through EventBus (an autoload), which fires for every Timeline instance.
	EventBus.timeline_event_fired.connect(_on_fired)


func _on_fired(id: String) -> void:
	if not fired_at.has(id):
		fired.append(id)
		fired_at[id] = clock.now


func after_all() -> void:
	if EventBus.timeline_event_fired.is_connected(_on_fired):
		EventBus.timeline_event_fired.disconnect(_on_fired)
	sim.free()
	tl.free()
	ws.free()
	clock.free()


func test_events_fire_in_nondecreasing_time_order() -> void:
	assert_gt(fired.size(), 50, "most of the content window should have fired")
	var last: int = 0
	for id in fired:
		assert_gte(int(fired_at[id]), last, "%s fired out of order" % id)
		last = int(fired_at[id])


func test_every_event_fires_by_the_end_of_the_window() -> void:
	var missing: Array[String] = []
	for id in tl.upcoming_ids():
		missing.append(str(id))
	assert_eq(missing.size(), 0, "events still pending at window end: %s" % [missing])


func test_party_arrives_at_the_pony_on_canon_evening() -> void:
	assert_true(fired_at.has("party_arrives_pony"))
	var t: int = int(fired_at["party_arrives_pony"])
	assert_gte(t, GameDate.parse("3018-09-29T20:00"))
	assert_lte(t, GameDate.parse("3018-09-30T00:00"), "mode A must not delay the arrival by more than a few hours")


func test_party_leaves_the_map_east_edge_on_09_30_and_weathertop_is_after() -> void:
	assert_true(fired_at.has("frodo_off_map"))
	assert_lte(int(fired_at["frodo_off_map"]), GameDate.parse("3018-10-06T23:00"))
	assert_gte(int(fired_at["frodo_off_map"]), GameDate.parse("3018-09-30T00:00"))
	assert_true(fired_at.has("weathertop_attack"))
	assert_gt(int(fired_at["weathertop_attack"]), int(fired_at["frodo_off_map"]))


func test_raids_happen_in_the_small_hours_of_09_30() -> void:
	for id in ["pony_raided", "crickhollow_raided"]:
		if not fired_at.has(id):
			continue
		assert_gte(int(fired_at[id]), GameDate.parse("3018-09-29T20:00"), id)
		assert_lte(int(fired_at[id]), GameDate.parse("3018-09-30T12:00"), id)
