extends GutTest
# new_game() must produce the right position, date, inventory, reputation and
# seeded memories for every origin.

const SCENE: PackedScene = preload("res://ui/char_creation/char_creation.tscn")

var _saved_poi_info: Dictionary


func before_each() -> void:
	_saved_poi_info = WorldState.poi_info.duplicate(true)
	# Tolerate a missing region loader: register any origin POI nobody has.
	for o: Dictionary in NewGame.load_origins():
		var poi: String = str(o["start_poi"])
		if not WorldState.poi_info.has(poi):
			WorldState.register_poi(poi, Vector3(float(poi.hash() % 1000), 0.0, 5.0))


func after_each() -> void:
	WorldState.poi_info = _saved_poi_info
	WorldState.reset()
	SaveSystem.autosave_enabled = false
	WorldClock.set_mode(&"A")


func _params(origin: Dictionary, mode: String = "A", trait_id: String = "cautious") -> Dictionary:
	return {"name": "Tester", "race": origin["race"], "origin": origin["id"], "background_trait": trait_id,
		"palette": "brown_earth", "hair": "short", "mode": mode}


func test_every_origin_builds_expected_state() -> void:
	var trait_data: Dictionary = NewGame.find_by_id(NewGame.load_traits(), "cautious")
	var effects: Dictionary = trait_data["effects"]
	var origins: Array[Dictionary] = NewGame.load_origins()
	assert_eq(origins.size(), 5)
	for o in origins:
		var result: Dictionary = NewGame.new().new_game(_params(o))
		assert_eq(result["error"], OK, "%s: %s" % [o["id"], result["message"]])
		var loc: Dictionary = WorldState.entity_location(WorldState.PLAYER_ID)
		assert_eq(loc["poi"], o["start_poi"], "%s poi" % o["id"])
		assert_not_null(loc["pos"], "%s resolves to a position" % o["id"])
		assert_eq(WorldClock.now, GameDate.parse(str(o["start_date"])), "%s date" % o["id"])
		for it: Dictionary in o["items"]:
			assert_eq(WorldState.item_count(WorldState.PLAYER_ID, str(it["item"])), int(it["count"]), "%s item %s" % [o["id"], it["item"]])
		for faction: String in o["reputation_offset"]:
			var expected: int = int(o["reputation_offset"][faction]) + int((effects["reputation"] as Dictionary).get(faction, 0))
			assert_eq(WorldState.get_reputation(faction), expected, "%s rep %s" % [o["id"], faction])
		var skills: Dictionary = WorldState.get_entity(WorldState.PLAYER_ID)["data"]["skills"]
		var bonus: Dictionary = o["skill_bonus"]
		var extra: float = float((effects["skills"] as Dictionary).get(bonus["skill"], 0.0))
		assert_almost_eq(float(skills[bonus["skill"]]), float(bonus["amount"]) + extra, 0.001, "%s skill" % o["id"])
		assert_eq((o["known_by"] as Array).size(), 2)
		for k: Dictionary in o["known_by"]:
			var mem: Dictionary = WorldState.get_npc_memory(str(k["npc"]))
			assert_eq(mem["summary"], k["memory"], "%s memory %s" % [o["id"], k["npc"]])
			assert_eq(mem["disposition"], clampi(int(k["disposition"]) + int(effects["first_impression"]), -10, 10))
			assert_lte(int(mem["last_talk"]), WorldClock.now)


func test_mode_and_autosave_and_timeline_reset() -> void:
	var o: Dictionary = NewGame.load_origins()[0]
	Timeline.add_events([{"id": "stale_event_xyz", "at": "3018-09-25T00:00"}])
	var result: Dictionary = NewGame.new().new_game(_params(o, "B"))
	assert_eq(result["error"], OK)
	assert_eq(WorldClock.mode, &"B")
	assert_true(SaveSystem.autosave_enabled)
	assert_false(Timeline.has_event("stale_event_xyz"))
	assert_gt(Timeline.event_count(), 0, "timeline reloaded from content")
	assert_true(WorldState.get_flag("origin." + str(o["id"])))


func test_trait_first_impression_shifts_disposition() -> void:
	var o: Dictionary = NewGame.load_origins()[0]
	var base: Dictionary = o["known_by"][0]
	NewGame.new().new_game(_params(o, "A", "kind"))
	var kind: int = int(NewGame.find_by_id(NewGame.load_traits(), "kind")["effects"]["first_impression"])
	assert_eq(WorldState.get_npc_memory(str(base["npc"]))["disposition"], clampi(int(base["disposition"]) + kind, -10, 10))


func test_invalid_params_rejected_without_touching_state() -> void:
	var o: Dictionary = NewGame.load_origins()[0]
	WorldState.set_flag("marker")
	for bad: Dictionary in [{"name": ""}, {"origin": "nope"}, {"race": "man"}, {"background_trait": "x"}, {"palette": "x"}, {"hair": "long"}, {"mode": "C"}]:
		var p: Dictionary = _params(o)
		p.merge(bad, true)
		assert_ne(NewGame.new().new_game(p)["error"], OK, str(bad))
	assert_true(WorldState.get_flag("marker"), "failed validation leaves state alone")


func test_creation_scene_emits_params() -> void:
	var ui: CharCreation = autofree(SCENE.instantiate())
	ui.start_game_on_confirm = false
	add_child(ui)
	await get_tree().process_frame
	watch_signals(ui)
	ui.choose_race("man")
	ui.choose_origin("staddle_farmer")
	ui.choose_palette(3)
	ui.confirm()
	assert_signal_emitted(ui, "creation_confirmed")
	var p: Dictionary = get_signal_parameters(ui, "creation_confirmed")[0]
	assert_eq(p["origin"], "staddle_farmer")
	assert_eq(p["race"], "man")
	assert_eq(p["palette"], "dark_loam")
	assert_eq(p["mode"], "A")
	assert_eq(NewGame.new().new_game(p)["error"], OK, "the emitted params are accepted by NewGame")
