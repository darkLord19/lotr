extends GutTest

var map: MapScreen
var saved_now: int


func before_each() -> void:
	saved_now = WorldClock.now
	for r in WorldClock.pause_reasons():
		WorldClock.resume(r)
	WorldState.reset()
	map = MapScreen.new()
	add_child_autofree(map)


func after_each() -> void:
	WorldState.reset()
	WorldState.poi_info = {}
	WorldClock.now = saved_now
	for r in WorldClock.pause_reasons():
		WorldClock.resume(r)


func test_initial_state_hidden() -> void:
	assert_false(map.visible)
	assert_false(map.is_open())
	assert_false(WorldClock.is_paused())


func test_open_and_close_pauses_world_clock() -> void:
	map.open()
	assert_true(map.visible)
	assert_true(map.is_open())
	assert_true(WorldClock.is_paused())
	assert_has(WorldClock.pause_reasons(), MapScreen.PAUSE_REASON)

	map.close()
	assert_false(map.visible)
	assert_false(map.is_open())
	assert_false(WorldClock.is_paused())


func test_toggle_inverts_visibility() -> void:
	assert_false(map.is_open())
	map.toggle()
	assert_true(map.is_open())
	map.toggle()
	assert_false(map.is_open())


func test_poi_markers_loaded_from_region() -> void:
	assert_gt(map.pois.size(), 0, "pois should load from eriador_west.json")
	var has_bag_end: bool = false
	for p: Dictionary in map.pois:
		if p.get("id") == "bag_end":
			has_bag_end = true
			break
	assert_true(has_bag_end, "bag_end should be present in pois")


func test_player_marker_coordinates_and_status() -> void:
	WorldState.spawn_entity(WorldState.PLAYER_ID, "player", Vector3(1000.0, 0.0, 2000.0), "eriador_west")
	map.refresh()
	assert_string_contains(map._status_label.text, "1000")
	assert_string_contains(map._status_label.text, "2000")
