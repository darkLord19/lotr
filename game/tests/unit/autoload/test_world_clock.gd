extends GutTest

const WorldClockScript: GDScript = preload("res://autoload/world_clock.gd")

var clock: Node


func before_each() -> void:
	clock = autofree(WorldClockScript.new())
	clock.now = 0


func test_pause_stack() -> void:
	assert_false(clock.is_paused())
	clock.pause(&"dialogue")
	clock.pause(&"menu")
	assert_true(clock.is_paused())
	clock.resume(&"dialogue")
	assert_true(clock.is_paused(), "menu still pauses")
	clock.resume(&"menu")
	assert_false(clock.is_paused())
	clock.resume(&"menu")  # unknown: ignored
	assert_false(clock.is_paused())


func test_process_respects_pause_and_scale() -> void:
	clock.time_scale = 2.0
	clock._process(1.0)
	assert_eq(clock.now, 2)
	clock.pause(&"menu")
	clock._process(10.0)
	assert_eq(clock.now, 2)
	clock.resume(&"menu")
	clock.time_scale = 0.5
	clock._process(1.0)  # 0.5 min carried
	assert_eq(clock.now, 2)
	clock._process(1.0)
	assert_eq(clock.now, 3)


func test_advance_emits_all_hour_and_day_signals() -> void:
	watch_signals(clock)
	clock.advance(1500)
	assert_eq(clock.now, 1500)
	assert_signal_emit_count(clock, "minute_passed", 1500)
	assert_signal_emit_count(clock, "hour_passed", 25)
	assert_signal_emit_count(clock, "day_passed", 1)


func test_advance_signal_order() -> void:
	var log: Array[String] = []
	clock.minute_passed.connect(func(n: int) -> void: if n % 60 == 59 or n % 60 == 0: log.append("m%d" % n))
	clock.hour_passed.connect(func(n: int) -> void: log.append("h%d" % n))
	clock.advance(121)
	assert_eq(log, ["m59", "m60", "h60", "m119", "m120", "h120"] as Array[String])


func test_mode_persists_through_serialise() -> void:
	clock.set_mode(&"B")
	clock.now = 12345
	var d: Dictionary = JSON.parse_string(JSON.stringify(clock.serialise()))
	var other: Node = autofree(WorldClockScript.new())
	other.deserialise(d)
	assert_eq(other.mode, &"B")
	assert_eq(other.now, 12345)


func test_bad_mode_ignored() -> void:
	clock.set_mode(&"Z")
	assert_eq(clock.mode, &"A")
