extends GutTest

const State := RiderAI.State
const FRAME: float = 0.5

var ai: RiderAI


func before_each() -> void:
	ai = RiderAI.new()
	ai.facing = Vector3(0, 0, -1)
	ai.patrol_target = Vector3(0, 0, -200)


func _far() -> RiderPerception.Target:
	return RiderPerception.Target.make(Vector3(500, 0, 500))


func _run(seconds: float, target: RiderPerception.Target) -> void:
	var t: float = 0.0
	while t < seconds:
		ai.step(FRAME, target, false)
		t += FRAME


func test_patrols_toward_timeline_position() -> void:
	_run(2.0, _far())
	assert_eq(ai.state, State.PATROL)
	assert_lt(ai.position.z, 0.0, "moved toward patrol target")
	assert_eq(ai.eye_state(), RiderPerception.EyeState.HIDDEN)


func test_detection_starts_sniff_and_rider_stops() -> void:
	var t: RiderPerception.Target = RiderPerception.Target.make(Vector3(0, 0, -20))
	ai.step(FRAME, t, false)
	assert_eq(ai.state, State.SNIFF)
	var pos: Vector3 = ai.position
	ai.step(FRAME, t, false)
	assert_eq(ai.position, pos, "stands still while sniffing")


func test_sniff_lasts_six_seconds_then_approaches() -> void:
	var t: RiderPerception.Target = RiderPerception.Target.make(Vector3(0, 0, -100))
	# Sniffed only: put player 5 m behind so scan sweeps do not matter.
	t.position = Vector3(0, 0, 5)
	ai.step(FRAME, t, false)
	assert_eq(ai.state, State.SNIFF)
	_run(5.0, t)
	assert_eq(ai.state, State.SNIFF, "still sniffing before 6 s")
	_run(1.0, t)
	assert_eq(ai.state, State.APPROACH)


func test_player_slips_away_during_sniff_returns_to_patrol() -> void:
	var near: RiderPerception.Target = RiderPerception.Target.make(Vector3(0, 0, 5))
	ai.step(FRAME, near, false)
	_run(7.0, _far())
	assert_eq(ai.state, State.PATROL)


func test_approach_reaches_interrogate_and_emits_caught_once() -> void:
	watch_signals(ai)
	var t: RiderPerception.Target = RiderPerception.Target.make(Vector3(0, 0, 12))
	ai.step(FRAME, t, false)
	_run(7.0, t)
	assert_eq(ai.state, State.APPROACH)
	_run(10.0, t)
	assert_eq(ai.state, State.INTERROGATE)
	assert_signal_emit_count(ai, "caught", 1)
	_run(3.0, t)
	assert_signal_emit_count(ai, "caught", 1)


func test_approach_gives_up_when_player_lost() -> void:
	var t: RiderPerception.Target = RiderPerception.Target.make(Vector3(0, 0, 12))
	ai.step(FRAME, t, false)
	_run(7.0, t)
	assert_eq(ai.state, State.APPROACH)
	var hidden: RiderPerception.Target = RiderPerception.Target.make(Vector3(0, 0, 400))
	_run(9.0, hidden)
	assert_eq(ai.state, State.PATROL)


func test_release_returns_to_patrol() -> void:
	var t: RiderPerception.Target = RiderPerception.Target.make(Vector3(0, 0, 12))
	ai.step(FRAME, t, false)
	_run(20.0, t)
	assert_eq(ai.state, State.INTERROGATE)
	ai.release()
	assert_eq(ai.state, State.PATROL)


func test_interrogation_hobbit_more_intense() -> void:
	var hobbit: Array[Dictionary] = RiderInterrogation.build("hobbit")
	var other: Array[Dictionary] = RiderInterrogation.build("man")
	assert_gt(hobbit.size(), other.size())
	assert_gt(other.size(), 0)
	var joined: String = ""
	for b: Dictionary in hobbit:
		joined += str(b["text"])
	assert_string_contains(joined, "Baggins")
