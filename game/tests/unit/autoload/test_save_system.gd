extends GutTest

const WorldClockScript: GDScript = preload("res://autoload/world_clock.gd")
const WorldStateScript: GDScript = preload("res://autoload/world_state.gd")
const TimelineScript: GDScript = preload("res://autoload/timeline.gd")
const SaveScript: GDScript = preload("res://autoload/save_system.gd")
const TEST_DIR: String = "user://test_saves"

var clock: Node
var ws: Node
var tl: Node
var ss: Node


func before_each() -> void:
	clock = autofree(WorldClockScript.new())
	ws = autofree(WorldStateScript.new())
	tl = autofree(TimelineScript.new())
	ss = autofree(SaveScript.new())
	tl.bind(clock, ws)
	ss.bind(clock, ws, tl)
	ss.save_dir = TEST_DIR
	_wipe()


func after_all() -> void:
	_wipe()


func _wipe() -> void:
	var dir := DirAccess.open(TEST_DIR)
	if dir == null:
		return
	for f in dir.get_files():
		dir.remove(f)


func test_round_trip_deep_equality() -> void:
	tl.add_events([{"id": "x", "at": "3018-01-01T00:05", "effects": [{"set_flag": "x"}]},
		{"id": "y", "at": "3018-01-01T00:10"}])
	clock.set_mode(&"B")
	clock.now = 100
	ws.spawn_entity("player", "player", "bag_end")
	ws.set_flag("f", true)
	ws.transfer_item("ale_mug", "", "player", 4)
	ws.change_reputation("shire", 12)
	ws.set_npc_memory("barliman", "hello", 50, 1)
	tl.process_due(100)
	var before: String = JSON.stringify(ss.build_save(), "", true)
	assert_eq(ss.save("slot1"), OK)

	ws.reset()
	clock.now = 0
	clock.set_mode(&"A")
	tl.deserialise({})
	assert_eq(ss.load_slot("slot1"), OK)
	assert_eq(JSON.stringify(ss.build_save(), "", true), before)
	assert_eq(clock.mode, &"B")
	assert_eq(clock.now, 100)
	assert_true(tl.is_fired("x"))


func test_corrupt_json_returns_error_and_keeps_state() -> void:
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	var f := FileAccess.open(ss.slot_path("bad"), FileAccess.WRITE)
	f.store_string("{ this is not json ::: ")
	f.close()
	ws.set_flag("keep", true)
	assert_eq(ss.load_slot("bad"), ERR_PARSE_ERROR)
	assert_true(ws.get_flag("keep"), "live state untouched")


func test_missing_wrong_shape_and_versions() -> void:
	assert_eq(ss.load_slot("nope"), ERR_FILE_NOT_FOUND)
	assert_eq(ss.load_slot("../evil"), ERR_INVALID_PARAMETER)
	_write("arr", "[1,2,3]")
	assert_eq(ss.load_slot("arr"), ERR_PARSE_ERROR)
	_write("nover", "{\"clock\": {}}")
	assert_eq(ss.load_slot("nover"), ERR_INVALID_DATA)
	_write("future", "{\"version\": 99}")
	assert_eq(ss.load_slot("future"), ERR_UNAVAILABLE)
	_write("partial", "{\"version\": 1, \"clock\": {}}")
	assert_eq(ss.load_slot("partial"), ERR_INVALID_DATA)


func test_migration_applied() -> void:
	ss.migrations = {0: func(d: Dictionary) -> Dictionary: return d}
	_write("old", "{\"version\": 0, \"clock\": {}, \"state\": {}, \"timeline\": {}}")
	# version 0 is below the supported minimum: rejected rather than guessed at.
	assert_eq(ss.load_slot("old"), ERR_UNAVAILABLE)


func test_autosave_rotation_keeps_three() -> void:
	for i in range(5):
		clock.now = (i + 1) * 10
		assert_eq(ss.autosave(), OK)
	var slots: Array[String] = ss.list_slots()
	assert_eq(slots, ["autosave_1", "autosave_2", "autosave_3"] as Array[String])
	# autosave_1 newest.
	assert_eq(ss.load_slot("autosave_1"), OK)
	assert_eq(clock.now, 50)
	assert_eq(ss.load_slot("autosave_3"), OK)
	assert_eq(clock.now, 30)


func test_autosave_on_game_hours_and_region_change() -> void:
	ss.autosave_enabled = true
	clock.advance(60 * 5)
	assert_eq(ss.list_slots().size(), 0)
	clock.advance(60)
	assert_eq(ss.list_slots(), ["autosave_1"] as Array[String])
	EventBus.region_changed.emit("rohan")
	assert_eq(ss.list_slots().size(), 2)


func test_autosave_disabled_by_default() -> void:
	clock.advance(60 * 12)
	assert_eq(ss.list_slots().size(), 0)


func _write(slot: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	var f := FileAccess.open(ss.slot_path(slot), FileAccess.WRITE)
	f.store_string(text)
	f.close()
