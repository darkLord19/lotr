class_name AmbienceLogic
extends RefCounted
## Pure decision function for the ambience bed: (location, time, weather, threat) -> target gain
## (0..1) per layer. No nodes, no audio, so GUT can drive it directly.

const LAYERS: Array[StringName] = [&"wind", &"birds", &"crickets", &"river", &"inn", &"rain", &"heartbeat"]
const WEATHER_LAYERS: Array[StringName] = [&"wind", &"birds", &"crickets"]
const DEFAULT_WEATHER: StringName = &"clear"
const HOURS_PER_DAY: float = 24.0


class Inputs extends RefCounted:
	## settlement | field | river | forest_edge | inn_interior
	var location: StringName = &"field"
	var hour: float = 12.0
	## WeatherModel state name: clear | overcast | light_rain | fog
	var weather_state: StringName = &"clear"
	## 0..1 from WeatherModel.Snapshot.rain_intensity; negative means "derive from the state name".
	var rain_intensity: float = -1.0
	## MusicLogic.Threat value; only HUNTED (and optionally ALERT) bring the heartbeat in.
	var threat: int = 0

	static func make(loc: StringName, h: float, weather: StringName = &"clear", rain: float = -1.0, thr: int = 0) -> Inputs:
		var i: Inputs = Inputs.new()
		i.location = loc
		i.hour = h
		i.weather_state = weather
		i.rain_intensity = rain
		i.threat = thr
		return i


## 1 in full daylight, 0 at night, smooth ramps over dawn and dusk. Wraps midnight safely.
static func daylight(hour: float, cfg: Dictionary) -> float:
	var d: Dictionary = cfg.get("daylight", {}) as Dictionary
	var h: float = fposmod(hour, HOURS_PER_DAY)
	var dawn: float = float(d.get("dawn_start_hour", 5.0))
	var day: float = float(d.get("day_start_hour", 7.0))
	var dusk: float = float(d.get("dusk_start_hour", 18.5))
	var night: float = float(d.get("night_start_hour", 20.5))
	if h < dawn or h >= night:
		return 0.0
	if h < day:
		return smoothstep(dawn, day, h)
	if h < dusk:
		return 1.0
	return 1.0 - smoothstep(dusk, night, h)


static func rain_amount(inp: Inputs, cfg: Dictionary) -> float:
	if inp.rain_intensity >= 0.0:
		return clampf(inp.rain_intensity, 0.0, 1.0)
	var by_state: Dictionary = cfg.get("rain_by_state", {}) as Dictionary
	return clampf(float(by_state.get(inp.weather_state, 0.0)), 0.0, 1.0)


static func layer_gains(inp: Inputs, cfg: Dictionary) -> Dictionary:
	var locations: Dictionary = cfg.get("locations", {}) as Dictionary
	var fallback_loc: StringName = StringName(str(cfg.get("default_location", "field")))
	var loc: Dictionary = (locations.get(inp.location, locations.get(fallback_loc, {})) as Dictionary)
	var scales: Dictionary = cfg.get("weather_scale", {}) as Dictionary
	var scale: Dictionary = (scales.get(inp.weather_state, scales.get(DEFAULT_WEATHER, {})) as Dictionary)
	var day: float = daylight(inp.hour, cfg)
	var rain: float = rain_amount(inp, cfg)
	var gains: Dictionary = {}
	for layer: StringName in LAYERS:
		gains[layer] = 0.0

	gains[&"wind"] = float(loc.get("wind", 0.0)) * float(scale.get("wind", 1.0))
	# Heavy rain silences birds and crickets regardless of the weather state's own scale.
	var quiet: float = 1.0 - rain
	var chorus: float = _dawn_chorus(inp.hour, cfg)
	gains[&"birds"] = float(loc.get("birds", 0.0)) * float(scale.get("birds", 1.0)) * day * quiet * (1.0 + chorus)
	gains[&"crickets"] = float(loc.get("crickets", 0.0)) * float(scale.get("crickets", 1.0)) * (1.0 - day) * quiet
	gains[&"river"] = float(loc.get("river", 0.0))
	gains[&"inn"] = float(loc.get("inn", 0.0))
	gains[&"rain"] = float(loc.get("rain", 0.0)) * rain * float(cfg.get("rain_gain", 1.0))
	gains[&"heartbeat"] = _heartbeat(inp.threat, cfg)

	for layer: StringName in LAYERS:
		gains[layer] = clampf(float(gains[layer]), 0.0, 1.0)
	return gains


static func _dawn_chorus(hour: float, cfg: Dictionary) -> float:
	var c: Dictionary = cfg.get("dawn_chorus", {}) as Dictionary
	var start: float = float(c.get("start_hour", 5.0))
	var end: float = float(c.get("end_hour", 8.0))
	var h: float = fposmod(hour, HOURS_PER_DAY)
	if h < start or h >= end:
		return 0.0
	return float(c.get("bonus", 0.0))


static func _heartbeat(threat: int, cfg: Dictionary) -> float:
	var hb: Dictionary = cfg.get("heartbeat", {}) as Dictionary
	var min_threat: int = int(hb.get("min_threat", 3))
	if threat >= min_threat:
		return float(hb.get("gain", 0.0))
	if threat == min_threat - 1:
		return float(hb.get("alert_gain", 0.0))
	return 0.0
