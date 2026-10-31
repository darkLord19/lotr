extends GutTest

const SEED: int = 12345
const DAY_COUNT: int = 40
# Largest per-minute change allowed in any output; sun/moon sweeps are ~0.005 per minute, so
# anything near this would be a visible pop.
const MAX_STEP: float = 0.02
const NOON: float = 12.0 * 60.0
const MIDNIGHT: float = 0.0
const EPS: float = 0.0001

var model: WeatherModel


func before_each() -> void:
	model = WeatherModel.new(SEED)


func test_deterministic_for_seed() -> void:
	var other := WeatherModel.new(SEED)
	for d in DAY_COUNT:
		assert_eq(model.state_for_day(d), other.state_for_day(d))
	var a: Dictionary = model.sample(5000.0).scalars()
	var b: Dictionary = other.sample(5000.0).scalars()
	assert_eq(a, b)


func test_different_seeds_differ() -> void:
	var other := WeatherModel.new(SEED + 1)
	var diff: int = 0
	for d in DAY_COUNT:
		if model.state_for_day(d) != other.state_for_day(d):
			diff += 1
	assert_gt(diff, 0, "schedules should depend on the seed")


func test_all_states_occur() -> void:
	var seen: Dictionary = {}
	for d in 400:
		seen[model.state_for_day(d)] = true
	for s in WeatherModel.STATE_ORDER:
		assert_true(seen.has(s), "state %s never scheduled" % s)


func test_continuous_across_days() -> void:
	for start_day in [0, 7, 21]:
		var prev: Dictionary = model.sample(float(start_day * WeatherModel.MINUTES_PER_DAY)).scalars()
		for m in range(1, 3 * WeatherModel.MINUTES_PER_DAY):
			var cur: Dictionary = model.sample(float(start_day * WeatherModel.MINUTES_PER_DAY + m)).scalars()
			for k: String in cur:
				if absf(float(cur[k]) - float(prev[k])) > MAX_STEP:
					fail_test("%s jumped %f at day %d minute %d" % [k, float(cur[k]) - float(prev[k]), start_day, m])
					return
			prev = cur
	pass_test("no jumps")


func test_continuous_with_forced_dawn_fog() -> void:
	var prev: Dictionary = model.sample(0.0, &"clear", true).scalars()
	for m in range(1, WeatherModel.MINUTES_PER_DAY):
		var cur: Dictionary = model.sample(float(m), &"clear", true).scalars()
		for k: String in cur:
			if absf(float(cur[k]) - float(prev[k])) > MAX_STEP:
				fail_test("%s jumped at minute %d" % [k, m])
				return
		prev = cur
	pass_test("no jumps")


func test_day_night_energy_bounds() -> void:
	var sun_max: float = float((model.cfg["sun"] as Dictionary)["energy_max"])
	var moon_max: float = float((model.cfg["moon"] as Dictionary)["energy_max"])
	for m in range(0, WeatherModel.MINUTES_PER_DAY, 10):
		var s: WeatherModel.Snapshot = model.sample(float(m), &"clear")
		assert_between(s.sun_energy, 0.0, sun_max + EPS)
		assert_between(s.moon_energy, 0.0, moon_max + EPS)
	var noon: WeatherModel.Snapshot = model.sample(NOON, &"clear")
	var night: WeatherModel.Snapshot = model.sample(MIDNIGHT, &"clear")
	assert_almost_eq(noon.sun_energy, sun_max * 1.0, 0.1, "clear noon is near full sun")
	assert_eq(noon.moon_energy, 0.0)
	assert_eq(night.sun_energy, 0.0)
	assert_gt(night.moon_energy, 0.0, "night is moonlit, not black")
	assert_gt(night.ambient_energy, 0.0, "night has readable ambient")
	assert_gt(noon.ambient_energy, night.ambient_energy)


func test_sun_geometry() -> void:
	var noon: WeatherModel.Snapshot = model.sample(NOON, &"clear")
	assert_gt(noon.sun_dir_to.y, 0.5)
	assert_almost_eq(noon.sun_dir_to.length(), 1.0, EPS)
	var dawn: WeatherModel.Snapshot = model.sample(6.0 * 60.0, &"clear")
	assert_gt(dawn.sun_dir_to.x, 0.9, "sun rises in the east (+X)")
	var dusk: WeatherModel.Snapshot = model.sample(18.0 * 60.0, &"clear")
	assert_lt(dusk.sun_dir_to.x, -0.9, "sun sets in the west")
	var night: WeatherModel.Snapshot = model.sample(MIDNIGHT, &"clear")
	assert_gt(night.moon_dir_to.y, 0.5, "moon is high at midnight")


func test_golden_hour_is_warmer_than_noon() -> void:
	var golden: WeatherModel.Snapshot = model.sample(18.0 * 60.0 - 40.0, &"clear")
	var noon: WeatherModel.Snapshot = model.sample(NOON, &"clear")
	assert_gt(golden.sun_color.r - golden.sun_color.b, noon.sun_color.r - noon.sun_color.b)


func test_rain_modifiers() -> void:
	var clear: WeatherModel.Snapshot = model.sample(NOON, &"clear")
	var rainy: WeatherModel.Snapshot = model.sample(NOON, &"light_rain")
	assert_eq(clear.rain_intensity, 0.0)
	assert_gt(rainy.rain_intensity, 0.0)
	assert_gt(rainy.concealment_bonus, clear.concealment_bonus)
	assert_gt(rainy.fear_aura_multiplier, clear.fear_aura_multiplier)
	assert_eq(clear.fear_aura_multiplier, 1.0, "clear weather leaves the fear aura unchanged")
	assert_lt(rainy.sun_energy, clear.sun_energy)


func test_fog_state_is_thicker() -> void:
	var clear: WeatherModel.Snapshot = model.sample(NOON, &"clear")
	var fog: WeatherModel.Snapshot = model.sample(NOON, &"fog")
	assert_gt(fog.fog_density, clear.fog_density * 5.0)


func test_dawn_fog_bump() -> void:
	var at_dawn: WeatherModel.Snapshot = model.sample(6.5 * 60.0, &"clear", true)
	var at_noon: WeatherModel.Snapshot = model.sample(NOON, &"clear", true)
	assert_gt(at_dawn.river_mist, 0.9)
	assert_eq(at_noon.river_mist, 0.0)
	assert_gt(at_dawn.fog_density, at_noon.fog_density)


func test_seed_round_trip() -> void:
	var data: Dictionary = model.serialise()
	var json: Variant = JSON.parse_string(JSON.stringify(data))
	var restored := WeatherModel.new(999)
	restored.deserialise(json as Dictionary)
	assert_eq(restored.get_weather_seed(), SEED)
	for d in DAY_COUNT:
		assert_eq(restored.state_for_day(d), model.state_for_day(d))
	assert_eq(restored.sample(7777.0).scalars(), model.sample(7777.0).scalars())
