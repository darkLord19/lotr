extends GutTest

const WorldStateScript: GDScript = preload("res://autoload/world_state.gd")
const WorldClockScript: GDScript = preload("res://autoload/world_clock.gd")

var ws: Node
var clock: Node
var rng: RandomNumberGenerator


func before_each() -> void:
	ws = autofree(WorldStateScript.new())
	clock = autofree(WorldClockScript.new())
	clock.now = 1000
	rng = RandomNumberGenerator.new()
	rng.seed = 12345


func _sf() -> SoftFailure:
	return SoftFailure.new(ws, clock, rng)


func test_time_advances_within_range() -> void:
	for seed_i in range(20):
		clock.now = 1000
		rng.seed = seed_i
		var s: Dictionary = _sf().apply("Bob", "hobbit")
		assert_between(int(s["minutes"]), 120, 360)
		assert_eq(clock.now, 1000 + int(s["minutes"]))


func test_same_seed_same_duration() -> void:
	rng.seed = 7
	var a: int = int(_sf().apply("Bob", "hobbit")["minutes"])
	clock.now = 1000
	rng.seed = 7
	var b: int = int(_sf().apply("Bob", "hobbit")["minutes"])
	assert_eq(a, b)


func test_black_breath_set_and_expires() -> void:
	var sf: SoftFailure = _sf()
	assert_eq(sf.stamina_multiplier(), 1.0)
	sf.apply("Bob", "hobbit")
	var until: int = int(ws.get_flag(SoftFailure.BLACK_BREATH_FLAG))
	assert_eq(until, clock.now + 12 * 60)
	assert_true(sf.black_breath_active())
	assert_eq(sf.stamina_multiplier(), 0.5)
	clock.now = until - 1
	assert_true(sf.black_breath_active())
	clock.now = until
	assert_false(sf.black_breath_active())
	assert_eq(sf.stamina_multiplier(), 1.0)


func test_debuff_survives_save_roundtrip() -> void:
	var sf: SoftFailure = _sf()
	sf.apply("Bob", "hobbit")
	var json: Variant = JSON.parse_string(JSON.stringify(ws.serialise()))
	ws.deserialise(json)
	assert_true(sf.black_breath_active())


func test_shire_rumour_added() -> void:
	_sf().apply("Bob", "hobbit")
	assert_true(ws.rumour_known_at("player_found_senseless", "bywater"))
	assert_eq(ws.get_flag("rumour_subject.player_found_senseless"), "Bob")
	assert_true(NPCContent.rumours().has("player_found_senseless"), "rumour id exists in content")


func test_hobbits_are_never_robbed() -> void:
	ws.inventories[WorldState.PLAYER_ID] = {"apple": 3}
	for i in range(30):
		rng.seed = i
		assert_eq((_sf().apply("Bob", "hobbit")["robbed"] as Array).size(), 0)
	assert_eq(ws.item_count(WorldState.PLAYER_ID, "apple"), 3)


func test_non_hobbit_robbery_happens_sometimes() -> void:
	var robbed: int = 0
	for i in range(200):
		ws.inventories[WorldState.PLAYER_ID] = {"apple": 3}
		rng.seed = i
		if (_sf().apply("Bob", "man")["robbed"] as Array).size() > 0:
			robbed += 1
			assert_eq(ws.item_count(WorldState.PLAYER_ID, "apple"), 0)
	assert_between(robbed, 5, 80, "~15% of 200")


func test_emits_player_failed() -> void:
	watch_signals(EventBus)
	_sf().apply("Bob", "hobbit")
	assert_signal_emitted(EventBus, "player_failed")
