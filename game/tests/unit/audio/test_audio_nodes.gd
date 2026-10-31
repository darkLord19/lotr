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


func test_one_shot_sfx_helpers() -> void:
	var host := Node3D.new()
	add_child_autofree(host)
	var stream: AudioStream = AudioFade.load_stream("res://assets/audio/sfx/door.ogg")
	assert_not_null(stream)
	var p2d: AudioStreamPlayer = AudioFade.play_one_shot(host, "res://assets/audio/sfx/door.ogg")
	assert_not_null(p2d)
	var p3d: AudioStreamPlayer3D = AudioFade.play_one_shot_3d(host, "res://assets/audio/sfx/door.ogg", Vector3(1, 0, 1))
	assert_not_null(p3d)
	assert_eq(p3d.global_position, Vector3(1, 0, 1))


func test_player_surface_detection() -> void:
	var pc := PlayerController.new()
	add_child_autofree(pc)
	pc.global_position = Vector3(950, 0, 2200)
	assert_eq(pc.get_surface_type(), "grass")
	# Near Green Dragon inn (1700, 2390)
	pc.global_position = Vector3(1702, 0, 2391)
	assert_eq(pc.get_surface_type(), "wood")


func test_rider_screech_on_transition() -> void:
	var node := RiderAINode.new()
	add_child_autofree(node)
	node.ai._set_state(RiderAI.State.SNIFF)
	assert_eq(node.ai.state, RiderAI.State.SNIFF)
	# Trigger transition to APPROACH
	node.ai._set_state(RiderAI.State.APPROACH)
	assert_eq(node.ai.state, RiderAI.State.APPROACH)
	# Screech player child was created
	var found_screech: bool = false
	for child: Node in node.get_children():
		if child is AudioStreamPlayer3D:
			found_screech = true
			break
	assert_true(found_screech)


func test_music_director_whole_cue_crossfade() -> void:
	var md := MusicDirector.new()
	add_child_autofree(md)
	md.use_whole_cues = true
	md.hour_override = NOON
	md.set_place(&"eriador_west", &"hobbiton")
	_settle(md.tick)

	assert_eq(md.current_cue, &"pastoral_day")
	assert_eq(md.get_cue_file(md.current_cue), "shire_day.ogg")
	assert_almost_eq(md.cue_gain, 1.0, 0.001)

	# Transition to chase cue on rider attack
	md.report_rider(20.0, RiderAI.State.APPROACH, RiderPerception.EyeState.SEEN)
	md.tick(FRAME)
	assert_eq(md.current_cue, MusicLogic.CUE_CHASE)
	assert_eq(md.outgoing_cue, &"pastoral_day")
	assert_eq(md.get_cue_file(md.current_cue), "rider_dread.ogg")

	_settle(md.tick)
	assert_almost_eq(md.cue_gain, 1.0, 0.001)
	assert_almost_eq(md.outgoing_cue_gain, 0.0, 0.001)


