extends GutTest

const NOON: float = 12.0
const MIDNIGHT: float = 0.0
const DAWN_HOUR: float = 6.0
const HUNTED: int = 3

var cfg: Dictionary


func before_each() -> void:
	cfg = AudioFade.load_config().get("ambience", {}) as Dictionary


func _g(loc: StringName, hour: float, weather: StringName = &"clear", rain: float = -1.0, threat: int = 0) -> Dictionary:
	return AmbienceLogic.layer_gains(AmbienceLogic.Inputs.make(loc, hour, weather, rain, threat), cfg)


func test_daylight_ramps_and_wraps() -> void:
	assert_eq(AmbienceLogic.daylight(NOON, cfg), 1.0)
	assert_eq(AmbienceLogic.daylight(MIDNIGHT, cfg), 0.0)
	var mid_dawn: float = AmbienceLogic.daylight(6.0, cfg)
	assert_between(mid_dawn, 0.01, 0.99)
	assert_eq(AmbienceLogic.daylight(MIDNIGHT + 24.0, cfg), 0.0, "hours wrap")


func test_birds_by_day_crickets_by_night() -> void:
	var day: Dictionary = _g(&"field", NOON)
	var night: Dictionary = _g(&"field", MIDNIGHT)
	assert_gt(float(day[&"birds"]), 0.0)
	assert_eq(float(day[&"crickets"]), 0.0)
	assert_eq(float(night[&"birds"]), 0.0)
	assert_gt(float(night[&"crickets"]), 0.0)


func test_dawn_chorus_is_louder_than_midday() -> void:
	assert_gt(float(_g(&"forest_edge", 7.5)[&"birds"]), float(_g(&"forest_edge", NOON)[&"birds"]) * 0.99)


func test_rain_layer_follows_weather_and_silences_wildlife() -> void:
	var rainy: Dictionary = _g(&"field", NOON, &"light_rain")
	var clear: Dictionary = _g(&"field", NOON, &"clear")
	assert_gt(float(rainy[&"rain"]), 0.0)
	assert_eq(float(clear[&"rain"]), 0.0)
	assert_lt(float(rainy[&"birds"]), float(clear[&"birds"]) * 0.2)
	var heavy: Dictionary = _g(&"field", NOON, &"light_rain", 1.0)
	assert_gt(float(heavy[&"rain"]), float(rainy[&"rain"]), "explicit intensity overrides the state default")
	assert_eq(float(heavy[&"birds"]), 0.0)


func test_location_selects_layers() -> void:
	assert_gt(float(_g(&"river", NOON)[&"river"]), 0.9)
	assert_eq(float(_g(&"field", NOON)[&"river"]), 0.0)
	var inn: Dictionary = _g(&"inn_interior", NOON, &"light_rain")
	assert_eq(float(inn[&"inn"]), 1.0)
	assert_lt(float(inn[&"wind"]), 0.1)
	assert_lt(float(inn[&"rain"]), float(_g(&"field", NOON, &"light_rain")[&"rain"]), "rain is muffled indoors")
	assert_gt(float(_g(&"forest_edge", NOON)[&"wind"]), float(_g(&"settlement", NOON)[&"wind"]))


func test_unknown_location_falls_back_and_gains_stay_in_range() -> void:
	var g: Dictionary = _g(&"nowhere", NOON)
	assert_eq(g, _g(&"field", NOON))
	for loc: String in (cfg["locations"] as Dictionary):
		for h: float in [0.0, 5.0, 6.5, 12.0, 19.0, 22.0]:
			for w: String in (cfg["weather_scale"] as Dictionary):
				var gains: Dictionary = _g(StringName(loc), h, StringName(w))
				for layer: StringName in gains:
					assert_between(float(gains[layer]), 0.0, 1.0)


func test_heartbeat_only_when_hunted() -> void:
	assert_eq(float(_g(&"field", NOON, &"clear", -1.0, 0)[&"heartbeat"]), 0.0)
	assert_eq(float(_g(&"field", NOON, &"clear", -1.0, 2)[&"heartbeat"]), 0.0)
	assert_gt(float(_g(&"field", NOON, &"clear", -1.0, HUNTED)[&"heartbeat"]), 0.0)


func test_fog_dampens_wind_and_birds() -> void:
	assert_lt(float(_g(&"field", NOON, &"fog")[&"wind"]), float(_g(&"field", NOON, &"overcast")[&"wind"]))
	assert_lt(float(_g(&"field", NOON, &"fog")[&"birds"]), float(_g(&"field", NOON, &"clear")[&"birds"]))
