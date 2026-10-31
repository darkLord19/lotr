extends GutTest

const WorldClockScript: GDScript = preload("res://autoload/world_clock.gd")
const WorldStateScript: GDScript = preload("res://autoload/world_state.gd")
const TimelineScript: GDScript = preload("res://autoload/timeline.gd")
const FIX: String = "res://tests/fixtures/timeline"

var clock: Node
var ws: Node
var tl: Node


func before_each() -> void:
	clock = autofree(WorldClockScript.new())
	ws = autofree(WorldStateScript.new())
	tl = autofree(TimelineScript.new())
	tl.bind(clock, ws)
	clock.now = GameDate.parse("3018-09-22T08:00")
	ws.spawn_entity("player", "player", "elsewhere")


func _run_to(iso: String) -> void:
	clock.advance(GameDate.parse(iso) - clock.now)


func _basic_only() -> void:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIX + "/events/basic.json"))
	tl.add_events(raw)


func test_missing_content_dirs_are_tolerated() -> void:
	tl.load_content_dirs("res://nope/events", "res://nope/itins")
	assert_eq(tl.event_count(), 0)
	clock.advance(100)
	pass_test("no crash")


func test_order_is_by_time_not_file_order() -> void:
	_basic_only()
	var fired: Array[String] = []
	EventBus.timeline_event_fired.connect(func(id: String) -> void: fired.append(id))
	ws.move_entity("player", "shed")  # mode A anyway
	_run_to("3018-09-22T12:00")
	assert_eq(fired, ["ev_a", "ev_e", "ev_b", "ev_c", "ev_d"] as Array[String])
	assert_true(ws.get_flag("a") and ws.get_flag("b") and ws.get_flag("c") and ws.get_flag("d"))
	assert_eq(ws.item_count("player", "ale_mug"), 1)
	assert_true(ws.has_knowledge("gaffer", "k1"))
	assert_true(ws.rumour_known_at("rum1", "hobbiton"))


func test_mode_a_fires_on_time_ignoring_waits() -> void:
	_basic_only()
	clock.set_mode(&"A")
	_run_to("3018-09-22T10:00")
	assert_true(tl.is_fired("ev_b"))
	assert_eq(tl.fired_time("ev_b"), GameDate.parse("3018-09-22T10:00"))
	assert_eq(tl.delay_of("ev_b"), 0)
	assert_false(tl.is_fired("ev_c"))
	_run_to("3018-09-22T10:30")
	assert_true(tl.is_fired("ev_c"))


func test_mode_b_holds_then_fires_and_shifts_dependents() -> void:
	_basic_only()
	clock.set_mode(&"B")
	_run_to("3018-09-22T11:30")
	assert_true(tl.is_fired("ev_a"))
	assert_false(tl.is_fired("ev_b"))
	assert_true(tl.is_held("ev_b"))
	assert_false(tl.is_fired("ev_c"), "dependents wait even though their time passed")
	# Player arrives at 11:30 -> fires immediately, delay 90 min.
	ws.move_entity("player", "shed")
	assert_true(tl.is_fired("ev_b"))
	assert_eq(tl.fired_time("ev_b"), GameDate.parse("3018-09-22T11:30"))
	assert_eq(tl.delay_of("ev_b"), 90)
	assert_eq(tl.due_time("ev_c"), GameDate.parse("3018-09-22T12:00"))
	assert_eq(tl.due_time("ev_d"), GameDate.parse("3018-09-22T12:30"))
	assert_false(tl.is_fired("ev_c"))
	_run_to("3018-09-22T11:59")
	assert_false(tl.is_fired("ev_c"))
	_run_to("3018-09-22T12:00")
	assert_true(tl.is_fired("ev_c"))
	assert_false(tl.is_fired("ev_d"))
	_run_to("3018-09-22T12:30")
	assert_true(tl.is_fired("ev_d"))
	assert_eq(tl.delay_of("ev_c"), 0, "shifted events are on their new time, not delayed again")


func test_mode_b_fires_normally_if_player_already_there() -> void:
	_basic_only()
	clock.set_mode(&"B")
	ws.move_entity("player", "shed")
	_run_to("3018-09-22T10:00")
	assert_true(tl.is_fired("ev_b"))
	assert_eq(tl.delay_of("ev_b"), 0)


func test_settlement_and_radius_areas() -> void:
	ws.register_poi("shed", Vector3(100, 0, 100), "hobbiton")
	ws.register_poi("market", Vector3(130, 5, 140), "hobbiton")
	ws.register_poi("far", Vector3(900, 0, 900), "elsewhere_town")
	tl.add_events([
		{"id": "s", "at": "3018-09-22T08:05", "waits_for_player": true, "trigger_area": {"settlement": "hobbiton"}},
		{"id": "r", "at": "3018-09-22T08:05", "waits_for_player": true, "trigger_area": {"poi": "shed", "radius": 60}},
	])
	clock.set_mode(&"B")
	ws.move_entity("player", "far")
	clock.advance(10)
	assert_false(tl.is_fired("s") or tl.is_fired("r"))
	ws.move_entity("player", Vector3(130, 0, 140))  # 50 m from shed, no poi
	assert_true(tl.is_fired("r"))
	assert_false(tl.is_fired("s"))
	ws.move_entity("player", "market")
	assert_true(tl.is_fired("s"))


func test_window_end_forces_fire() -> void:
	tl.add_events(JSON.parse_string(FileAccess.get_file_as_string(FIX + "/events/window.json")))
	clock.set_mode(&"B")
	_run_to("3018-09-22T11:14")
	assert_false(tl.is_fired("ev_w"))
	clock.advance(1)
	assert_true(tl.is_fired("ev_w"))
	assert_eq(tl.fired_time("ev_w"), GameDate.parse("3018-09-22T11:15"))
	assert_eq(tl.delay_of("ev_w"), 60)
	assert_eq(tl.due_time("ev_after_w"), GameDate.parse("3018-09-22T11:45"))


func test_shifted_window_moves_with_event() -> void:
	tl.add_events([
		{"id": "p", "at": "3018-09-22T09:00", "waits_for_player": true, "trigger_area": {"poi": "nowhere"}, "window_end": "3018-09-22T10:00"},
		{"id": "q", "at": "3018-09-22T09:30", "depends_on": ["p"], "waits_for_player": true,
			"trigger_area": {"poi": "nowhere"}, "window_end": "3018-09-22T09:50"},
	])
	clock.set_mode(&"B")
	_run_to("3018-09-22T10:00")
	assert_true(tl.is_fired("p"))
	assert_eq(tl.due_time("q"), GameDate.parse("3018-09-22T10:30"))
	_run_to("3018-09-22T10:49")
	assert_false(tl.is_fired("q"))
	_run_to("3018-09-22T10:50")
	assert_true(tl.is_fired("q"), "window length (20 min) preserved after shift")


func test_save_load_mid_hold_preserves_state() -> void:
	_basic_only()
	clock.set_mode(&"B")
	_run_to("3018-09-22T10:45")
	assert_true(tl.is_held("ev_b"))
	var saved: Dictionary = JSON.parse_string(JSON.stringify(tl.serialise()))
	assert_true("ev_a" in saved["held"] or "ev_b" in saved["held"])

	var tl2: Node = autofree(TimelineScript.new())
	var ws2: Node = autofree(WorldStateScript.new())
	tl2.bind(clock, ws2)
	ws2.spawn_entity("player", "player", "elsewhere")
	tl2.add_events(JSON.parse_string(FileAccess.get_file_as_string(FIX + "/events/basic.json")))
	tl2.deserialise(saved)
	assert_true(tl2.is_fired("ev_a"))
	assert_true(tl2.is_held("ev_b"))
	assert_false(tl2.is_fired("ev_b"))
	assert_eq(tl2.upcoming_ids().size(), 3)  # b, c, d
	ws2.move_entity("player", "shed")
	tl2.process_due(clock.now)
	assert_true(tl2.is_fired("ev_b"))
	assert_eq(tl2.delay_of("ev_b"), 45)
	assert_eq(tl2.due_time("ev_c"), GameDate.parse("3018-09-22T11:15"))


func test_save_load_preserves_shifts_and_delays() -> void:
	_basic_only()
	clock.set_mode(&"B")
	_run_to("3018-09-22T10:45")
	ws.move_entity("player", "shed")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(tl.serialise()))
	var tl2: Node = autofree(TimelineScript.new())
	tl2.bind(clock, ws)
	tl2.add_events(JSON.parse_string(FileAccess.get_file_as_string(FIX + "/events/basic.json")))
	tl2.deserialise(saved)
	assert_eq(tl2.delay_of("ev_b"), 45)
	assert_eq(tl2.due_time("ev_d"), GameDate.parse("3018-09-22T11:45"))
	assert_true(tl2.is_fired("ev_b"))


func test_itinerary_steps_become_events() -> void:
	tl.load_content_dirs("res://nope", FIX + "/itineraries")
	assert_eq(tl.event_count(), 2)
	assert_eq(tl.get_event("frodo_leaves")["type"], "itinerary_step")
	ws.spawn_entity("frodo", "npc", "bag_end")
	_run_to("3018-09-22T21:00")
	assert_true(tl.is_fired("frodo_camps"))
	assert_eq(ws.entity_location("frodo")["poi"], "woody_end_camp")
	assert_eq(ws.entity_location("sam")["poi"], "woody_end_camp", "unknown actors are created at the destination")


func test_bad_events_skipped() -> void:
	tl.add_events([{"id": "", "at": "3018-09-22"}, {"id": "nodate"}, {"id": "ok", "at": "3018-09-22T09:00"}, {"id": "ok", "at": "3018-09-22T10:00"}])
	assert_eq(tl.event_count(), 1)


func test_clear_flag_effect() -> void:
	ws.set_flag("lit", true)
	tl.add_events([{"id": "snuff", "at": "3018-09-22T09:00", "effects": [{"clear_flag": "lit"}, {"set_flag": "dark"}]}])
	_run_to("3018-09-22T09:30")
	assert_false(bool(ws.get_flag("lit")))
	assert_true(bool(ws.get_flag("dark")))
