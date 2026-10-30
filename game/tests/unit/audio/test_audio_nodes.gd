extends GutTest
## The thin player nodes: run headless on the dummy audio driver, so we check the wiring
## (inputs -> eased gains), not the sound.

const NOON: float = 12.0
const SETTLE_SECONDS: float = 30.0
const FRAME: float = 0.5


func _settle(tick: Callable) -> void:
	var t: float = 0.0
	while t < SETTLE_SECONDS:
		tick.call(FRAME)
		t += FRAME


func test_ambience_eases_toward_targets() -> void:
	var amb: Ambience = Ambience.new()
	add_child_autofree(amb)
	amb.hour_override = NOON
	amb.set_location(&"river")
	amb.tick(FRAME)
	assert_lt(float(amb.gains[&"river"]), 1.0, "gain ramps rather than jumping")
	assert_gt(float(amb.gains[&"river"]), 0.0)
	_settle(amb.tick)
	assert_almost_eq(float(amb.gains[&"river"]), float(amb.targets[&"river"]), 0.001)
	amb.set_weather(&"light_rain")
	_settle(amb.tick)
	assert_gt(float(amb.gains[&"rain"]), 0.0)


func test_music_director_follows_rider_reports() -> void:
	var md: MusicDirector = MusicDirector.new()
	add_child_autofree(md)
	md.hour_override = NOON
	md.set_place(&"eriador_west", &"hobbiton")
	_settle(md.tick)
	assert_eq(md.decision.cue, &"pastoral_day")
	assert_gt(float(md.gains[&"harp"]), 0.5)
	md.report_rider(25.0, RiderAI.State.APPROACH, RiderPerception.EyeState.SEEN)
	_settle(md.tick)
	assert_eq(md.decision.cue, MusicLogic.CUE_CHASE)
	assert_gt(float(md.gains[&"strings"]), 0.9)
	assert_lt(float(md.gains[&"harp"]), 0.01)
	md.clear_rider()
	_settle(md.tick)
	assert_eq(md.decision.cue, &"pastoral_day")
