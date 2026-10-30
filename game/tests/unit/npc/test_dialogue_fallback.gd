extends GutTest

var rng := RandomNumberGenerator.new()
var saved_now: int


func before_each() -> void:
	rng.seed = 7
	saved_now = WorldClock.now
	NPCTestHelper.reset_world("3018-09-29T21:00")


func after_each() -> void:
	WorldState.reset()
	WorldClock.now = saved_now


func _respond(kind: String, date: String = "3018-09-29T21:00", used: Array = []) -> Dictionary:
	return DialogueFallback.respond(NPCTestHelper.NPC, NPCTestHelper.card(), GameDate.parse(date), kind, used, rng)


func test_classify() -> void:
	assert_eq(DialogueFallback.classify("", true), "greeting")
	assert_eq(DialogueFallback.classify("Any news?", true), "news")
	assert_eq(DialogueFallback.classify("Farewell", false), "farewell")
	assert_eq(DialogueFallback.classify("Trade", false), "smalltalk")
	assert_eq(DialogueFallback.classify("Hello there", true), "greeting")


func test_fixed_options_and_source() -> void:
	var r: Dictionary = _respond("greeting")
	assert_eq(r["options"], ["Ask about news", "Trade", "Farewell"])
	assert_eq(r["source"], "fallback")
	assert_ne(r["speech"], "")


func test_lines_are_date_filtered() -> void:
	# The 29 Sept evening greeting must never appear in early summer.
	for i in 30:
		assert_false(_respond("greeting", "3018-06-01")["speech"].contains("strange news and stranger folk"))
	var seen: bool = false
	for i in 60:
		seen = seen or _respond("greeting", "3018-09-29T21:00")["speech"].contains("strange news and stranger folk")
	assert_true(seen)


func test_rumour_line_requires_rumour_and_date() -> void:
	assert_eq(_respond("news")["kind"], "smalltalk", "no rumour known: falls back to small talk")
	WorldState.spread_rumour("black_riders_asking_for_baggins", "prancing_pony")
	var r: Dictionary = _respond("news")
	assert_eq(r["kind"], "news")
	assert_true(r["speech"].contains("West-gate"))
	assert_eq(r["intents"], [{"type": "share_rumour", "rumour_id": "black_riders_asking_for_baggins"}])
	assert_eq(_respond("news", "3018-09-29T19:00")["kind"], "smalltalk", "the line is dated after the riders arrive")


func test_farewell_ends_conversation() -> void:
	assert_eq(_respond("farewell")["intents"], [{"type": "end_conversation"}])


func test_no_immediate_repeat() -> void:
	var used: Array = []
	var first: String = _respond("smalltalk", "3018-09-29T21:00", used)["speech"]
	var second: String = _respond("smalltalk", "3018-09-29T21:00", used)["speech"]
	assert_ne(first, second)


func test_requires_flag_and_until() -> void:
	assert_eq(DialogueFallback._entry_text({"text": "x", "requires_flag": "f"}, 0), "")
	WorldState.set_flag("f")
	assert_eq(DialogueFallback._entry_text({"text": "x", "requires_flag": "f"}, 0), "x")
	assert_eq(DialogueFallback._entry_text({"text": "x", "until": "3018-09-01"}, GameDate.parse("3018-09-02")), "")
	assert_eq(DialogueFallback._entry_text("plain", 0), "plain")


func test_npc_without_fallback_file_still_answers() -> void:
	var r: Dictionary = DialogueFallback.respond("nobody_here", {}, 0, "greeting", [], rng)
	assert_eq(r["speech"], Config.get_value("npc.no_fallback_line"))
