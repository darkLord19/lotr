extends GutTest

const Threat := MusicLogic.Threat
const RState := RiderAI.State
const Eye := RiderPerception.EyeState
const FRAME: float = 1.0
const NOON: float = 12.0
const NIGHT: float = 23.0
const DUSK: float = 19.0
const DAWN: float = 6.0

var cfg: Dictionary
var logic: MusicLogic


func before_each() -> void:
	cfg = AudioFade.load_config().get("music", {}) as Dictionary
	logic = MusicLogic.new(cfg)


func _inp(hour: float = NOON) -> MusicLogic.Inputs:
	var i: MusicLogic.Inputs = MusicLogic.Inputs.new()
	i.region = &"eriador_west"
	i.hour = hour
	return i


func _run(inp: MusicLogic.Inputs, seconds: float) -> MusicLogic.Decision:
	var d: MusicLogic.Decision = null
	var t: float = 0.0
	while t < seconds:
		d = logic.update(inp, FRAME)
		t += FRAME
	return d


func test_calm_cue_by_time_of_day() -> void:
	assert_eq(MusicLogic.calm_cue(_inp(NOON), cfg), &"pastoral_day")
	assert_eq(MusicLogic.calm_cue(_inp(DUSK), cfg), &"pastoral_dusk")
	assert_eq(MusicLogic.calm_cue(_inp(DAWN), cfg), &"pastoral_dusk")
	assert_eq(MusicLogic.calm_cue(_inp(NIGHT), cfg), &"night")


func test_rain_and_fog_use_grey_variant_by_day_only() -> void:
	var i: MusicLogic.Inputs = _inp(NOON)
	i.weather_state = &"light_rain"
	assert_eq(MusicLogic.calm_cue(i, cfg), &"pastoral_grey")
	i.weather_state = &"fog"
	assert_eq(MusicLogic.calm_cue(i, cfg), &"pastoral_grey")
	i.hour = NIGHT
	assert_eq(MusicLogic.calm_cue(i, cfg), &"night", "night music ignores weather")


func test_settlement_and_area_choose_character() -> void:
	var i: MusicLogic.Inputs = _inp()
	i.settlement = &"bree"
	assert_eq(MusicLogic.calm_cue(i, cfg), &"town_day")
	i.settlement = &""
	i.area = &"old_forest"
	assert_eq(MusicLogic.calm_cue(i, cfg), &"wild_day")
	i.area = &"unknown_place"
	assert_eq(MusicLogic.calm_cue(i, cfg), &"pastoral_day", "falls back to the region/default character")


func test_inn_overrides_time_and_place() -> void:
	var i: MusicLogic.Inputs = _inp(NIGHT)
	i.settlement = &"bree"
	i.in_inn = true
	var d: MusicLogic.Decision = _run(i, 1.0)
	assert_eq(d.cue, &"inn")
	assert_eq(d.stem_gains[&"fiddle"], 1.0)
	assert_eq(d.stem_gains[&"strings"], 0.0)


func test_threat_levels_from_rider_states() -> void:
	var i: MusicLogic.Inputs = _inp()
	assert_eq(MusicLogic.threat_level(i, cfg), Threat.NONE)
	i.rider_distance_m = 120.0
	assert_eq(MusicLogic.threat_level(i, cfg), Threat.UNEASE)
	i.rider_state = RState.PATROL
	assert_eq(MusicLogic.threat_level(i, cfg), Threat.UNEASE, "patrolling at range is only unease")
	i.rider_state = RState.SNIFF
	assert_eq(MusicLogic.threat_level(i, cfg), Threat.ALERT)
	i.rider_state = RState.APPROACH
	assert_eq(MusicLogic.threat_level(i, cfg), Threat.HUNTED)
	i.rider_state = RState.INTERROGATE
	assert_eq(MusicLogic.threat_level(i, cfg), Threat.HUNTED)
	i.rider_state = RState.PATROL
	i.eye_state = Eye.SEEN
	assert_eq(MusicLogic.threat_level(i, cfg), Threat.ALERT)
	i.eye_state = Eye.SNIFFED
	assert_eq(MusicLogic.threat_level(i, cfg), Threat.HUNTED)


func test_proximity_gives_danger_priority_even_in_inn() -> void:
	var i: MusicLogic.Inputs = _inp()
	i.in_inn = true
	i.rider_distance_m = 40.0
	i.rider_state = RState.PATROL
	var d: MusicLogic.Decision = _run(i, 1.0)
	assert_eq(d.threat, Threat.ALERT)
	assert_eq(d.cue, MusicLogic.CUE_DANGER)
	assert_gt(float(d.stem_gains[&"strings"]), float(d.stem_gains[&"fiddle"]))


func test_hunted_uses_chase_cue_with_fast_fade_in() -> void:
	var i: MusicLogic.Inputs = _inp()
	_run(i, 1.0)
	i.rider_distance_m = 30.0
	i.rider_state = RState.APPROACH
	var d: MusicLogic.Decision = _run(i, 1.0)
	assert_eq(d.cue, MusicLogic.CUE_CHASE)
	assert_eq(d.fade_seconds, float((cfg["fade"] as Dictionary)["danger_in_seconds"]))
	assert_eq(d.stem_gains[&"flute"], 0.0, "calm layers drop out in the chase")


func test_danger_holds_then_releases_slowly() -> void:
	var i: MusicLogic.Inputs = _inp()
	i.rider_distance_m = 30.0
	i.rider_state = RState.SNIFF
	_run(i, 2.0)
	i.rider_distance_m = INF
	i.rider_state = MusicLogic.NO_RIDER_STATE
	var hold: float = float((cfg["threat"] as Dictionary)["danger_hold_seconds"])
	var d: MusicLogic.Decision = _run(i, hold - 2.0)
	assert_eq(d.cue, MusicLogic.CUE_DANGER, "still dangerous during the hold-over")
	d = _run(i, 4.0)
	assert_eq(d.cue, &"pastoral_day", "returns to the calm cue once the hold has run out")
	assert_eq(d.fade_seconds, float((cfg["fade"] as Dictionary)["danger_out_seconds"]))


func test_unease_ducks_calm_stems_and_adds_strings() -> void:
	var i: MusicLogic.Inputs = _inp()
	var calm: MusicLogic.Decision = _run(i, 1.0)
	i.rider_distance_m = 100.0
	var uneasy: MusicLogic.Decision = _run(i, 1.0)
	assert_eq(uneasy.cue, calm.cue, "unease is a mix change, not a cue change")
	assert_lt(float(uneasy.stem_gains[&"harp"]), float(calm.stem_gains[&"harp"]))
	assert_gt(float(uneasy.stem_gains[&"strings"]), 0.0)


func test_calm_changes_respect_minimum_dwell() -> void:
	var i: MusicLogic.Inputs = _inp(NOON)
	_run(i, 1.0)
	i.hour = DUSK
	var d: MusicLogic.Decision = _run(i, 3.0)
	assert_eq(d.cue, &"pastoral_day", "too soon to switch")
	d = _run(i, float((cfg["threat"] as Dictionary)["min_cue_seconds"]))
	assert_eq(d.cue, &"pastoral_dusk")


func test_every_cue_only_names_known_stems_and_characters_name_known_cues() -> void:
	var stems: Dictionary = cfg["stems"] as Dictionary
	var cues: Dictionary = cfg["cues"] as Dictionary
	for cue: String in cues:
		for stem: String in (cues[cue] as Dictionary):
			assert_true(stems.has(stem), "%s uses unknown stem %s" % [cue, stem])
	for ch: String in (cfg["characters"] as Dictionary):
		for period: String in ((cfg["characters"] as Dictionary)[ch] as Dictionary):
			var cue_name: String = str(((cfg["characters"] as Dictionary)[ch] as Dictionary)[period])
			assert_true(cues.has(cue_name), "%s/%s -> unknown cue %s" % [ch, period, cue_name])


func test_fade_helper_ramps_linearly_and_clamps() -> void:
	assert_almost_eq(AudioFade.step(0.0, 1.0, 1.0, 4.0), 0.25, 0.0001)
	assert_eq(AudioFade.step(0.9, 1.0, 10.0, 4.0), 1.0)
	assert_eq(AudioFade.step(0.3, 0.0, 1.0, 0.0), 0.0, "zero fade time snaps")
