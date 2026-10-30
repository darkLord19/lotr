extends GutTest
## M1-T16 acceptance: play two scripted in-game days on the real systems, save, throw everything
## away, load, and check (a) the serialised state is identical and (b) the world then evolves
## exactly like a run that never reloaded.

const GatewayScript: GDScript = preload("res://autoload/llm_gateway.gd")
const DIR: String = "user://test_saves_flow"
const NPC: String = "barliman_butterbur"
const SLOT: String = "slot_1"
const WEATHER_SEED: int = 4242
const PLAYER_POS: Vector3 = Vector3(12.5, 3.25, -40.125)
const PLAYER_YAW: float = 1.5707963267948966
const DAYS_PLAYED: int = 2
const FOLLOW_UP_DAYS: int = 3
const STEP_MINUTES: int = 30

var saved_dir: String
var saved_autosave: bool
var saved_now: int
var saved_mode: StringName
var gw: Node
var gw_calls: int = 0
var survival: Survival
var sim: OffscreenSim
var rumours: RumourNetwork
var weather: WeatherDayNight
var graph: RoadGraph


func before_each() -> void:
	saved_dir = SaveSystem.save_dir
	saved_autosave = SaveSystem.autosave_enabled
	saved_now = WorldClock.now
	saved_mode = WorldClock.mode
	SaveSystem.save_dir = DIR
	_wipe()
	SaveSystem.clear_pending_extras()


func after_each() -> void:
	if survival != null:
		survival.detach()
		survival = null
	_free_services()
	_wipe()
	SaveSystem.save_dir = saved_dir
	SaveSystem.autosave_enabled = saved_autosave
	SaveSystem.clear_pending_extras()
	WorldState.reset()
	WorldState.poi_info = {}
	Timeline.deserialise({})
	WorldClock.now = saved_now
	WorldClock.set_mode(saved_mode)


func _wipe() -> void:
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	for f in dir.get_files():
		dir.remove(f)


# --- fixtures -----------------------------------------------------------------

func _build_services() -> void:
	graph = RoadGraph.new()
	graph.load_region()
	sim = OffscreenSim.new()
	sim.bind(WorldClock, WorldState, Timeline, graph)
	sim.load_tracks()
	add_child(sim)
	rumours = RumourNetwork.new()
	rumours.graph = graph
	add_child(rumours)
	weather = WeatherDayNight.new()
	add_child(weather)


func _free_services() -> void:
	for n: Node in [sim, rumours, weather]:
		if n != null and is_instance_valid(n):
			remove_child(n)  # runs _exit_tree now: unregisters and drops the timeline guard
			n.free()
	sim = null
	rumours = null
	weather = null


func _new_game() -> void:
	var look: Dictionary = NewGame.load_appearance()
	var hair: String = ""
	for h: Dictionary in NewGame.load_appearance()["hair_styles"]:
		if "hobbit" in (h["races"] as Array):
			hair = str(h["id"])
			break
	var result: Dictionary = NewGame.new().new_game({
		"name": "Tolman", "race": "hobbit", "origin": "hobbiton_gardener",
		"background_trait": str(NewGame.load_traits()[0]["id"]),
		"palette": str((look["palettes"] as Array)[0]["id"]), "hair": hair, "mode": "A"})
	assert_eq(result["error"], OK, str(result["message"]))


func _make_gateway() -> void:
	gw = GatewayScript.new()
	gw.api_key_override = "test-key"
	gw.log_enabled = false
	gw_calls = 0
	gw.transport_factory = func() -> LLMTransport:
		var m := MockTransport.new()
		var script: Array[String] = []
		if gw_calls == 0:
			var meta: Dictionary = {"options": ["Ask about riders"], "intents": [{"type": "give_item", "item_id": "ale_mug"}], "mood": "warm"}
			script.append(MockTransport.delta("Evening! Strange folk on the road, lately.\n---META---\n" + JSON.stringify(meta)))
		else:
			script.append(MockTransport.delta(JSON.stringify({"summary": "Tolman asked about the news. Black riders were mentioned.",
					"learned": [{"fact": "A hobbit called Tolman asked about black riders at the Pony.", "spreadable": true}]})))
		script.append(MockTransport.sse("[DONE]"))
		gw_calls += 1
		m.canned = script
		return m
	add_child_autofree(gw)


# Plays the scripted days through the real systems.
func _play_two_days() -> void:
	var start: int = WorldClock.now
	var skills := Skills.new()
	var inv := Inventory.new(WorldState.PLAYER_ID)
	var forage := Foraging.new([{"id": "m1", "item": "mushrooms", "pos": [0, 0, 0], "yield": 2}], inv, skills)
	forage.rng.seed = 11

	# Day 1: walk to Bree (teleport), chat, forage.
	WorldClock.advance(120)
	WorldState.move_entity(WorldState.PLAYER_ID, "prancing_pony")
	WorldState.spawn_entity(NPC, "npc", "prancing_pony")
	_make_gateway()
	var mind := NPCMind.new(NPC)
	mind.gateway = gw
	mind.rng.seed = 3
	var turn: Dictionary = {}
	mind.say("Any news?", func(_p: String) -> void: pass, func(t: Dictionary) -> void: turn.merge(t))
	assert_eq(turn.get("source"), "llm", "the mock transport answered")
	var memory: Dictionary = {}
	mind.end_conversation(func(r: Dictionary) -> void: memory.merge(r))
	assert_true(memory.get("ok", false), "summary stored")
	assert_true(forage.forage("m1")["ok"])
	WorldClock.advance(240)

	# Sleep through the night; the autosave on sleep must fire.
	SaveSystem.autosave_enabled = true
	survival.sleep(8.0, "bed")
	assert_true(FileAccess.file_exists(SaveSystem.slot_path("autosave_1")), "sleeping autosaves")
	SaveSystem.autosave_enabled = false

	# Day 2: a rider catches the player on the road, then more travelling.
	WorldState.move_entity(WorldState.PLAYER_ID, PLAYER_POS)
	WorldState.set_entity_data(WorldState.PLAYER_ID, "yaw", PLAYER_YAW)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var caught: Dictionary = SoftFailure.new(WorldState, WorldClock, rng).apply("Tolman", "hobbit")
	assert_gt(int(caught["minutes"]), 0)
	_advance_to(start + DAYS_PLAYED * WorldClock.MINUTES_PER_DAY)
	weather.set_weather_seed(WEATHER_SEED)


func _advance_to(target: int) -> void:
	while WorldClock.now < target:
		WorldClock.advance(mini(STEP_MINUTES, target - WorldClock.now))


# What a continued run produces: when each following event fired, plus the whole state.
func _follow_up() -> Dictionary:
	var next_ids: Array[String] = Timeline.upcoming_ids().slice(0, 6)
	_advance_to(WorldClock.now + FOLLOW_UP_DAYS * WorldClock.MINUTES_PER_DAY)
	var times: Dictionary = {}
	for id in next_ids:
		times[id] = Timeline.fired_time(id)
	return {"ids": next_ids, "times": times, "state": _canonical(SaveSystem.build_save())}


# JSON has no int/float distinction, so compare through one JSON round trip of both sides.
func _canonical(d: Dictionary) -> String:
	var text: String = JSON.stringify(d, "", true, true)
	return JSON.stringify(JSON.parse_string(text), "", true, true)


# Path of the first difference between two canonical JSON texts, to make failures readable.
func _first_diff(a_text: String, b_text: String) -> String:
	return _diff(JSON.parse_string(a_text), JSON.parse_string(b_text), "")


func _diff(a: Variant, b: Variant, path: String) -> String:
	if a is Dictionary and b is Dictionary:
		for k: Variant in (a as Dictionary):
			if not (b as Dictionary).has(k):
				return "%s/%s missing in second" % [path, k]
			var d: String = _diff(a[k], b[k], "%s/%s" % [path, k])
			if d != "":
				return d
		for k: Variant in (b as Dictionary):
			if not (a as Dictionary).has(k):
				return "%s/%s missing in first" % [path, k]
		return ""
	if a is Array and b is Array:
		if (a as Array).size() != (b as Array).size():
			return "%s size %d vs %d" % [path, (a as Array).size(), (b as Array).size()]
		for i in (a as Array).size():
			var d: String = _diff(a[i], b[i], "%s[%d]" % [path, i])
			if d != "":
				return d
		return ""
	return "" if a == b else "%s: %s vs %s" % [path, a, b]


func _reset_everything() -> void:
	_free_services()
	WorldState.reset()
	WorldClock.now = 0
	WorldClock.set_mode(&"B")
	Timeline.deserialise({})
	_build_services()


# --- tests --------------------------------------------------------------------

func test_two_days_save_reset_load_equals_uninterrupted_run() -> void:
	_new_game()
	# Survival first, so its minute handler runs before the sim's in both runs: a faint
	# advances the clock re-entrantly, which makes handler order observable.
	survival = Survival.new()
	_build_services()
	_play_two_days()
	assert_true(Timeline.serialise()["fired"].size() > 0, "canon events fired during the two days")
	assert_ne(WorldState.get_flag(SoftFailure.BLACK_BREATH_FLAG, 0), 0, "rider soft failure applied")

	var before: String = _canonical(SaveSystem.build_save())
	assert_eq(SaveSystem.save(SLOT), OK)
	var raw: Dictionary = SaveSystem.read_save(SLOT)["data"]
	for key in ["rumour_network", "offscreen_sim", "weather"]:
		assert_true((raw["extras"] as Dictionary).has(key), "extras has %s" % key)
	assert_eq(int(raw["meta"]["clock_now"]), WorldClock.now)

	# Run A: never reloaded.
	var expected: Dictionary = _follow_up()
	assert_gt(expected["ids"].size(), 0, "there are upcoming events to compare")
	var fired_in_follow_up: int = 0
	for t: Variant in (expected["times"] as Dictionary).values():
		if int(t) != GameDate.INVALID:
			fired_in_follow_up += 1
	assert_gt(fired_in_follow_up, 0, "the comparison covers events that actually fire")

	_reset_everything()
	assert_eq(SaveSystem.load_slot(SLOT), OK)
	var after: String = _canonical(SaveSystem.build_save())
	assert_eq(_first_diff(before, after), "", "serialised state survives save/reset/load")
	assert_eq(weather.get_weather_seed(), WEATHER_SEED)
	assert_eq(WorldState.entity_location(WorldState.PLAYER_ID)["pos"], PLAYER_POS)
	assert_almost_eq(float(WorldState.get_entity_data(WorldState.PLAYER_ID, "yaw")), PLAYER_YAW, 1e-9)

	# Run B: from the loaded state.
	var actual: Dictionary = _follow_up()
	assert_eq(actual["ids"], expected["ids"])
	assert_eq(actual["times"], expected["times"], "next timeline events fire at the same minutes")
	assert_eq(_first_diff(actual["state"], expected["state"]), "", "and the whole world ends up identical")


func test_extras_wait_for_a_participant_that_registers_after_load() -> void:
	_new_game()
	_build_services()
	weather.set_weather_seed(WEATHER_SEED)
	assert_eq(SaveSystem.save(SLOT), OK)
	_free_services()
	assert_eq(SaveSystem.load_slot(SLOT), OK, "loading from the menu: no world yet")
	weather = WeatherDayNight.new()
	add_child(weather)
	assert_eq(weather.get_weather_seed(), WEATHER_SEED, "handed over when it registered")


func test_participant_without_saved_entry_is_reset() -> void:
	_new_game()
	_build_services()
	assert_eq(SaveSystem.save(SLOT), OK)
	# A save written before this participant existed must still clear its live state.
	var seen: Array = []
	SaveSystem.register_participant("late_one", func() -> Dictionary: return {"v": 1}, func(d: Dictionary) -> void: seen.append(d))
	assert_eq(SaveSystem.load_slot(SLOT), OK)
	SaveSystem.unregister_participant("late_one")
	assert_eq(seen, [{}])


func test_unregister_only_removes_own_registration() -> void:
	var a: Callable = func() -> Dictionary: return {"who": "a"}
	var b: Callable = func() -> Dictionary: return {"who": "b"}
	var noop: Callable = func(_d: Dictionary) -> void: pass
	SaveSystem.register_participant("dup", a, noop)
	SaveSystem.register_participant("dup", b, noop)
	SaveSystem.unregister_participant("dup", a)
	assert_true("dup" in SaveSystem.participant_keys(), "stale owner cannot unregister its successor")
	SaveSystem.unregister_participant("dup", b)
	assert_false("dup" in SaveSystem.participant_keys())


func test_save_without_extras_or_meta_still_loads() -> void:
	_new_game()
	var data: Dictionary = SaveSystem.build_save()
	data.erase("extras")
	DirAccess.make_dir_recursive_absolute(DIR)
	var f := FileAccess.open(SaveSystem.slot_path("old"), FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	assert_eq(SaveSystem.load_slot("old"), OK)
	assert_eq(SaveSystem.slot_info("old")["player"], "")


func test_region_change_autosaves() -> void:
	_new_game()
	SaveSystem.autosave_enabled = true
	EventBus.region_changed.emit("eriador_west")
	assert_true(FileAccess.file_exists(SaveSystem.slot_path("autosave_1")))


func test_latest_slot_prefers_newest_save() -> void:
	_new_game()
	assert_eq(SaveSystem.latest_slot(), "")
	assert_eq(SaveSystem.save("slot_2"), OK)
	OS.delay_msec(20)
	assert_eq(SaveSystem.autosave(), OK)
	assert_eq(SaveSystem.latest_slot(), "autosave_1")
	OS.delay_msec(20)
	assert_eq(SaveSystem.save("slot_1"), OK)
	assert_eq(SaveSystem.latest_slot(), "slot_1")
