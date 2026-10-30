class_name MusicLogic
extends RefCounted
## Music decision state machine, free of nodes and audio so GUT can drive it.
## inputs (region, settlement, time, weather, rider perception) -> chosen cue + per-stem gains.
## Priority: rider danger > inn interior > time-of-day/weather variant of the area's character.

enum Threat { NONE, UNEASE, ALERT, HUNTED }

const NO_RIDER_STATE: int = -1
const CUE_DANGER: StringName = &"danger"
const CUE_CHASE: StringName = &"danger_chase"
const CUE_INN: StringName = &"inn"
const STEM_STRINGS: StringName = &"strings"
const HOURS_PER_DAY: float = 24.0
const FALLBACK_FADE_S: float = 6.0


class Inputs extends RefCounted:
	var region: StringName = &""
	var settlement: StringName = &""
	## Non-settlement area id (e.g. old_forest) for the "wild" character; empty in open country.
	var area: StringName = &""
	var in_inn: bool = false
	var hour: float = 12.0
	var weather_state: StringName = &"clear"
	## Distance to the nearest Black Rider; INF when none is around.
	var rider_distance_m: float = INF
	## RiderAI.State of that rider, or NO_RIDER_STATE.
	var rider_state: int = -1
	## RiderPerception.EyeState: how aware of the player the riders are.
	var eye_state: int = RiderPerception.EyeState.HIDDEN


class Decision extends RefCounted:
	var cue: StringName = &""
	var threat: int = Threat.NONE
	## stem id -> target gain 0..1 for every stem in the config (0 when unused by the cue).
	var stem_gains: Dictionary = {}
	## How long the caller should take to ease stems to these gains.
	var fade_seconds: float = FALLBACK_FADE_S


var cfg: Dictionary = {}
var current_cue: StringName = &""

var _cue_age: float = 0.0
var _danger_hold: float = 0.0
var _fade: float = FALLBACK_FADE_S
var _fade_left: float = 0.0


func _init(p_cfg: Dictionary = {}) -> void:
	cfg = p_cfg if not p_cfg.is_empty() else AudioFade.load_config().get("music", {}) as Dictionary


# --- pure helpers --------------------------------------------------------------

static func threat_level(inp: Inputs, music_cfg: Dictionary) -> int:
	var t: Dictionary = music_cfg.get("threat", {}) as Dictionary
	var state: int = inp.rider_state
	if state == RiderAI.State.APPROACH or state == RiderAI.State.INTERROGATE \
			or inp.eye_state == RiderPerception.EyeState.SNIFFED:
		return Threat.HUNTED
	# Proximity is a hard override: a rider this close is danger music even if it has not noticed us.
	if state == RiderAI.State.SNIFF or inp.eye_state == RiderPerception.EyeState.SEEN \
			or inp.rider_distance_m <= float(t.get("danger_distance_m", 60.0)):
		return Threat.ALERT
	if inp.rider_distance_m <= float(t.get("unease_distance_m", 150.0)):
		return Threat.UNEASE
	return Threat.NONE


## day | grey | dusk | night. Dawn is treated as `dawn_period` (soft, low-sun music).
static func period_for(inp: Inputs, music_cfg: Dictionary) -> StringName:
	var p: Dictionary = music_cfg.get("periods", {}) as Dictionary
	var h: float = fposmod(inp.hour, HOURS_PER_DAY)
	var dawn: float = float(p.get("dawn_start_hour", 5.0))
	var day: float = float(p.get("day_start_hour", 7.0))
	var dusk: float = float(p.get("dusk_start_hour", 18.5))
	var night: float = float(p.get("night_start_hour", 21.0))
	if h >= night or h < dawn:
		return &"night"
	if h < day:
		return StringName(str(music_cfg.get("dawn_period", "dusk")))
	if h >= dusk:
		return &"dusk"
	var grey: Array = music_cfg.get("grey_weather_states", []) as Array
	return &"grey" if grey.has(String(inp.weather_state)) else &"day"


## Area beats settlement beats region: standing in the Old Forest next to a village is still "wild".
static func character_for(inp: Inputs, music_cfg: Dictionary) -> StringName:
	var area_map: Dictionary = music_cfg.get("area_character", {}) as Dictionary
	var settle_map: Dictionary = music_cfg.get("settlement_character", {}) as Dictionary
	var region_map: Dictionary = music_cfg.get("region_character", {}) as Dictionary
	if inp.settlement != &"" and settle_map.has(String(inp.settlement)):
		return StringName(str(settle_map[String(inp.settlement)]))
	if inp.area != &"" and area_map.has(String(inp.area)):
		return StringName(str(area_map[String(inp.area)]))
	if inp.region != &"" and region_map.has(String(inp.region)):
		return StringName(str(region_map[String(inp.region)]))
	return StringName(str(music_cfg.get("default_character", "pastoral")))


## The calm cue (no rider involvement) for these inputs.
static func calm_cue(inp: Inputs, music_cfg: Dictionary) -> StringName:
	if inp.in_inn:
		return CUE_INN
	var characters: Dictionary = music_cfg.get("characters", {}) as Dictionary
	var table: Dictionary = (characters.get(String(character_for(inp, music_cfg)), {}) as Dictionary)
	var period: String = String(period_for(inp, music_cfg))
	return StringName(str(table.get(period, table.get("day", "pastoral_day"))))


static func is_danger_cue(cue: StringName) -> bool:
	return cue == CUE_DANGER or cue == CUE_CHASE


# --- state machine -------------------------------------------------------------

func update(inp: Inputs, delta: float) -> Decision:
	var threat: int = threat_level(inp, cfg)
	var tcfg: Dictionary = cfg.get("threat", {}) as Dictionary
	if threat >= Threat.ALERT:
		_danger_hold = float(tcfg.get("danger_hold_seconds", 8.0))
	else:
		_danger_hold = maxf(0.0, _danger_hold - delta)

	var desired: StringName
	if threat >= Threat.ALERT or _danger_hold > 0.0:
		# During the hold-over after the rider lets go we stay on plain danger, never the chase cue.
		desired = CUE_CHASE if threat == Threat.HUNTED else CUE_DANGER
	else:
		desired = calm_cue(inp, cfg)
	_switch_if_allowed(desired, delta, tcfg)
	return _decision(threat, inp)


func _switch_if_allowed(desired: StringName, delta: float, tcfg: Dictionary) -> void:
	_cue_age += delta
	_fade_left -= delta
	if _fade_left <= 0.0:
		_fade = _default_fade()
	if desired == current_cue:
		return
	var first: bool = current_cue == &""
	var danger_change: bool = is_danger_cue(desired) or is_danger_cue(current_cue)
	# Calm-to-calm changes wait out a minimum dwell so a threshold-hugging hour or weather flicker
	# cannot make the music churn; anything involving danger is immediate.
	if not (first or danger_change or _cue_age >= float(tcfg.get("min_cue_seconds", 12.0))):
		return
	var fade_cfg: Dictionary = cfg.get("fade", {}) as Dictionary
	if is_danger_cue(desired) and not is_danger_cue(current_cue):
		_fade = float(fade_cfg.get("danger_in_seconds", 1.5))
	elif is_danger_cue(current_cue) and not is_danger_cue(desired):
		_fade = float(fade_cfg.get("danger_out_seconds", 7.0))
	else:
		_fade = _default_fade()
	_fade_left = _fade
	current_cue = desired
	_cue_age = 0.0


func _default_fade() -> float:
	return float((cfg.get("fade", {}) as Dictionary).get("default_seconds", FALLBACK_FADE_S))


func _decision(threat: int, _inp: Inputs) -> Decision:
	var d: Decision = Decision.new()
	d.cue = current_cue
	d.threat = threat
	d.fade_seconds = _fade
	var cues: Dictionary = cfg.get("cues", {}) as Dictionary
	var cue_gains: Dictionary = cues.get(String(current_cue), {}) as Dictionary
	for stem: String in (cfg.get("stems", {}) as Dictionary):
		d.stem_gains[StringName(stem)] = float(cue_gains.get(stem, 0.0))
	if threat == Threat.UNEASE and not is_danger_cue(current_cue):
		# A rider is somewhere near but unaware: dim the warm layers and let low strings creep in.
		var tcfg: Dictionary = cfg.get("threat", {}) as Dictionary
		var duck: float = float(tcfg.get("unease_duck", 0.7))
		for stem: StringName in d.stem_gains:
			d.stem_gains[stem] = float(d.stem_gains[stem]) * duck
		d.stem_gains[STEM_STRINGS] = float(tcfg.get("unease_strings_gain", 0.3))
	return d
