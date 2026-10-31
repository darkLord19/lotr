class_name WeatherModel
extends RefCounted
# Pure day/night + weather model: sample(minute) is a function of (seed, minute, config) only,
# so a save needs just the seed. No nodes, no autoloads; all tunables come from config/weather.json.

const CONFIG_PATH: String = "res://config/weather.json"
const STYLE_PATH: String = "res://config/style.json"
const CONFIG_ROOT_KEY: String = "weather"

const MINUTES_PER_DAY: int = 1440
const MINUTES_PER_HOUR: int = 60
# Hour at which the sun is on the eastern horizon (equal day and night: no seasons in the model).
const SUNRISE_HOUR: float = 6.0
const HOURS_PER_DAY: float = 24.0
# Cloud scatters sunlight toward white; this is how strongly full cloud does it.
const CLOUD_WHITEN: float = 0.5

# Salts keep the independent random draws for the same (seed, day) uncorrelated.
const SALT_STATE: int = 1
const SALT_DAWN_FOG: int = 2
# 32-bit integer mixing constants (GDScript ints are 64-bit, so we mask to stay deterministic).
const MASK_32: int = 0xFFFFFFFF
const MIX_MUL: int = 0x45d9f3b
const MIX_SEED_MUL: int = 0x9E3779B1
const MIX_DAY_MUL: int = 0x85EBCA6B
const MIX_SALT_MUL: int = 0xC2B2AE35
const MIX_SHIFT: int = 16
const UNIT_DIVISOR: float = 4294967296.0

const STATE_ORDER: Array[StringName] = [&"clear", &"overcast", &"light_rain", &"fog"]
# Profile keys that blend linearly between two weather states.
const PROFILE_KEYS: Array[String] = ["cloud", "rain", "fog_density", "sun_dim", "ambient_mul", "concealment_bonus", "fear_aura_multiplier"]

var weather_seed: int = 0
var cfg: Dictionary = {}


# Everything the world needs at one instant.
class Snapshot extends RefCounted:
	var state: StringName = &"clear"
	var day: int = 0
	var hour: float = 0.0
	# Unit vectors pointing FROM the ground TO the body; lights shine along the negative.
	var sun_dir_to: Vector3 = Vector3.UP
	var moon_dir_to: Vector3 = Vector3.DOWN
	var sun_elevation_deg: float = 0.0
	var sun_energy: float = 0.0
	var sun_color: Color = Color.WHITE
	var moon_energy: float = 0.0
	var moon_color: Color = Color.WHITE
	var ambient_color: Color = Color.WHITE
	var ambient_energy: float = 1.0
	var sky_top: Color = Color.WHITE
	var sky_horizon: Color = Color.WHITE
	var fog_density: float = 0.0
	var fog_color: Color = Color.WHITE
	# 0..1 dawn-mist strength; water-side places (the Brandywine) can scale local fog by this.
	var river_mist: float = 0.0
	var rain_intensity: float = 0.0
	var cloud_cover: float = 0.0
	# Gameplay modifiers for RiderPerception callers.
	var concealment_bonus: float = 0.0
	var fear_aura_multiplier: float = 1.0

	# Flat float view, used by tests to assert continuity.
	func scalars() -> Dictionary:
		var d: Dictionary = {
			"sun_x": sun_dir_to.x, "sun_y": sun_dir_to.y, "sun_z": sun_dir_to.z,
			"moon_x": moon_dir_to.x, "moon_y": moon_dir_to.y, "moon_z": moon_dir_to.z,
			"sun_energy": sun_energy, "moon_energy": moon_energy, "ambient_energy": ambient_energy,
			"fog_density": fog_density, "river_mist": river_mist, "rain": rain_intensity,
			"cloud": cloud_cover, "concealment": concealment_bonus, "fear": fear_aura_multiplier,
		}
		var colors: Dictionary = {"sun_c": sun_color, "moon_c": moon_color, "amb_c": ambient_color,
			"sky_top": sky_top, "sky_hor": sky_horizon, "fog_c": fog_color}
		for k: String in colors:
			var c: Color = colors[k]
			d[k + "_r"] = c.r
			d[k + "_g"] = c.g
			d[k + "_b"] = c.b
		return d


func _init(p_seed: int = 0, p_cfg: Dictionary = {}) -> void:
	cfg = p_cfg if not p_cfg.is_empty() else load_config()
	weather_seed = p_seed if p_seed != 0 else int(cfg.get("default_seed", 0))


# weather.json, with an optional style.json "weather" section deep-merged on top (art-direction
# overrides). A missing style file is normal early in the project.
static func load_config() -> Dictionary:
	var base: Dictionary = _read_json(CONFIG_PATH)
	var out: Dictionary = (base.get(CONFIG_ROOT_KEY, {}) as Dictionary).duplicate(true)
	var style: Dictionary = _read_json(STYLE_PATH)
	if style.get(CONFIG_ROOT_KEY, null) is Dictionary:
		_deep_merge(out, style[CONFIG_ROOT_KEY] as Dictionary)
	return out


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


static func _deep_merge(dst: Dictionary, src: Dictionary) -> void:
	for k: Variant in src:
		if dst.get(k, null) is Dictionary and src[k] is Dictionary:
			_deep_merge(dst[k] as Dictionary, src[k] as Dictionary)
		else:
			dst[k] = src[k]


# --- save support --------------------------------------------------------------

func get_weather_seed() -> int:
	return weather_seed


func serialise() -> Dictionary:
	return {"weather_seed": weather_seed}


func deserialise(d: Dictionary) -> void:
	weather_seed = int(d.get("weather_seed", weather_seed))


# --- deterministic schedule -----------------------------------------------------

# Uniform [0,1) draw that depends only on (seed, day, salt).
func _rand(day: int, salt: int) -> float:
	var x: int = ((weather_seed & MASK_32) * MIX_SEED_MUL + (day & MASK_32) * MIX_DAY_MUL + salt * MIX_SALT_MUL) & MASK_32
	x = (((x >> MIX_SHIFT) ^ x) * MIX_MUL) & MASK_32
	x = (((x >> MIX_SHIFT) ^ x) * MIX_MUL) & MASK_32
	x = (x >> MIX_SHIFT) ^ x
	return float(x & MASK_32) / UNIT_DIVISOR


# Weather holds for a multi-day "spell" so it does not flip every midnight.
func state_for_day(day: int) -> StringName:
	var spell_days: int = maxi(int(cfg.get("spell_days", 1)), 1)
	var spell: int = floori(float(day) / float(spell_days))
	var weights: Dictionary = cfg.get("state_weights", {}) as Dictionary
	var total: float = 0.0
	for s: StringName in STATE_ORDER:
		total += float(weights.get(String(s), 0.0))
	if total <= 0.0:
		return &"clear"
	var roll: float = _rand(spell, SALT_STATE) * total
	for s: StringName in STATE_ORDER:
		roll -= float(weights.get(String(s), 0.0))
		if roll < 0.0:
			return s
	return STATE_ORDER[STATE_ORDER.size() - 1]


func has_dawn_fog(day: int) -> bool:
	var chance: float = float((cfg.get("dawn_fog", {}) as Dictionary).get("chance", 0.0))
	return _rand(day, SALT_DAWN_FOG) < chance


func _profile(state: StringName) -> Dictionary:
	return (cfg.get("states", {}) as Dictionary).get(String(state), {}) as Dictionary


# Weather profile at a minute: blends yesterday's and today's state over a window centred on
# midnight, so the schedule is continuous. Returns {profile, state (the dominant one)}.
func _blended_profile(minute: float, forced: StringName) -> Dictionary:
	if forced != &"":
		return {"profile": _profile(forced), "state": forced}
	var day: int = floori(minute / MINUTES_PER_DAY)
	var t: float = minute - day * MINUTES_PER_DAY
	var window: float = clampf(float(cfg.get("transition_minutes", 0.0)), 1.0, float(MINUTES_PER_DAY))
	var half: float = window * 0.5
	var from_day: int = day
	var to_day: int = day
	var w: float = 0.0
	if t < half:
		from_day = day - 1
		w = smoothstep(0.0, 1.0, 0.5 + t / window)
	elif t > MINUTES_PER_DAY - half:
		to_day = day + 1
		w = smoothstep(0.0, 1.0, (t - (MINUTES_PER_DAY - half)) / window)
	var a: StringName = state_for_day(from_day)
	var b: StringName = state_for_day(to_day)
	var pa: Dictionary = _profile(a)
	var pb: Dictionary = _profile(b)
	var out: Dictionary = {}
	for k: String in PROFILE_KEYS:
		out[k] = lerpf(float(pa.get(k, 0.0)), float(pb.get(k, 0.0)), w)
	return {"profile": out, "state": b if w >= 0.5 else a}


# Smooth 0..1 bump over [start_hour, end_hour] that is exactly 0 at both ends.
func _dawn_bump(hour: float) -> float:
	var df: Dictionary = cfg.get("dawn_fog", {}) as Dictionary
	var start: float = float(df.get("start_hour", 0.0))
	var end: float = float(df.get("end_hour", 0.0))
	if end <= start or hour <= start or hour >= end:
		return 0.0
	var s: float = sin(PI * (hour - start) / (end - start))
	return s * s


# --- sampling ---------------------------------------------------------------------

# forced_state / forced_dawn_fog override the schedule (debug, cutscenes, captures).
func sample(minute: float, forced_state: StringName = &"", forced_dawn_fog: bool = false) -> Snapshot:
	var snap := Snapshot.new()
	var day: int = floori(minute / MINUTES_PER_DAY)
	var hour: float = (minute - day * MINUTES_PER_DAY) / MINUTES_PER_HOUR
	snap.day = day
	snap.hour = hour

	var blend: Dictionary = _blended_profile(minute, forced_state)
	var prof: Dictionary = blend["profile"] as Dictionary
	snap.state = blend["state"] as StringName
	var cloud: float = float(prof.get("cloud", 0.0))
	snap.cloud_cover = cloud
	snap.rain_intensity = float(prof.get("rain", 0.0))
	snap.concealment_bonus = float(prof.get("concealment_bonus", 0.0))
	snap.fear_aura_multiplier = float(prof.get("fear_aura_multiplier", 1.0))
	var sun_dim: float = float(prof.get("sun_dim", 0.0))
	var ambient_mul: float = float(prof.get("ambient_mul", 1.0))

	# Celestial geometry: +X east, +Z south, +Y up; the sun rises east and sets west.
	var sun_cfg: Dictionary = cfg.get("sun", {}) as Dictionary
	var angle: float = (hour - SUNRISE_HOUR) / HOURS_PER_DAY * TAU
	var y: float = sin(angle) * sin(deg_to_rad(float(sun_cfg.get("max_elevation_deg", 45.0))))
	var horiz: float = sqrt(maxf(1.0 - y * y, 0.0))
	snap.sun_dir_to = Vector3(cos(angle) * horiz, y, sin(angle) * horiz)
	# The moon is simply opposite the sun: no phases, but always up when the sun is down.
	snap.moon_dir_to = -snap.sun_dir_to
	var elev: float = rad_to_deg(asin(clampf(y, -1.0, 1.0)))
	snap.sun_elevation_deg = elev

	# Sun.
	var fade_start: float = float(sun_cfg.get("fade_start_deg", -6.0))
	var sun_vis: float = smoothstep(fade_start, float(sun_cfg.get("fade_end_deg", 8.0)), elev)
	snap.sun_energy = float(sun_cfg.get("energy_max", 1.0)) * sun_vis * (1.0 - sun_dim)
	# Twilight rose -> horizon orange at 0 deg -> neutral by the end of golden hour.
	var sun_col: Color = _col(sun_cfg, "color_twilight").lerp(_col(sun_cfg, "color_horizon"), smoothstep(fade_start, 0.0, elev))
	sun_col = sun_col.lerp(_col(sun_cfg, "color_day"), smoothstep(0.0, float(sun_cfg.get("golden_end_deg", 25.0)), elev))
	snap.sun_color = sun_col.lerp(Color.WHITE, cloud * CLOUD_WHITEN)

	# Moon.
	var moon_cfg: Dictionary = cfg.get("moon", {}) as Dictionary
	var moon_vis: float = smoothstep(float(moon_cfg.get("rise_deg", 0.0)), float(moon_cfg.get("full_deg", 12.0)), -elev)
	snap.moon_energy = float(moon_cfg.get("energy_max", 0.3)) * moon_vis * (1.0 - sun_vis) * (1.0 - cloud * float(moon_cfg.get("cloud_dim", 0.5)))
	snap.moon_color = _col(moon_cfg, "color")

	# Ambient and sky share the same daylight / dusk factors.
	var amb: Dictionary = cfg.get("ambient", {}) as Dictionary
	var daylight: float = smoothstep(float(amb.get("daylight_start_deg", -8.0)), float(amb.get("daylight_end_deg", 15.0)), elev)
	var twi_w: float = maxf(float(sun_cfg.get("twilight_width_deg", 12.0)), 0.001)
	var dusk: float = smoothstep(0.0, 1.0, 1.0 - clampf(absf(elev) / twi_w, 0.0, 1.0))
	snap.ambient_energy = lerpf(float(amb.get("energy_night", 0.4)), float(amb.get("energy_day", 1.0)), daylight) * ambient_mul
	var amb_col: Color = _col(amb, "color_night").lerp(_col(amb, "color_day"), daylight)
	snap.ambient_color = amb_col.lerp(_col(amb, "color_dusk"), dusk * float(amb.get("dusk_mix", 0.4)))

	var sky: Dictionary = cfg.get("sky", {}) as Dictionary
	var top: Color = _col(sky, "night_top").lerp(_col(sky, "day_top"), daylight).lerp(_col(sky, "dusk_top"), dusk)
	var hor: Color = _col(sky, "night_horizon").lerp(_col(sky, "day_horizon"), daylight).lerp(_col(sky, "dusk_horizon"), dusk)
	var grey_mix: float = cloud * float(sky.get("overcast_mix", 0.8))
	var bright: float = float(sky.get("overcast_brightness", 0.8))
	snap.sky_top = top.lerp(_grey(top, bright), grey_mix)
	snap.sky_horizon = hor.lerp(_grey(hor, bright), grey_mix)

	# Fog: weather density plus the dawn-mist bump.
	var dawn: float = _dawn_bump(hour) if (forced_dawn_fog or has_dawn_fog(day)) else 0.0
	# Rain already limits visibility; mist on top would double-count.
	dawn *= 1.0 - clampf(snap.rain_intensity, 0.0, 1.0)
	snap.river_mist = dawn
	var fog_cfg: Dictionary = cfg.get("fog", {}) as Dictionary
	var dens: float = float(prof.get("fog_density", 0.0)) + dawn * float((cfg.get("dawn_fog", {}) as Dictionary).get("extra_density", 0.0))
	# Unlit night fog reads thicker than it is; thin it a little.
	snap.fog_density = dens * lerpf(float(fog_cfg.get("night_density_scale", 1.0)), 1.0, daylight)
	# Thick fog is its own pale haze; thin fog just takes the horizon colour.
	var fog_amt: float = clampf(dens / maxf(float(fog_cfg.get("full_extra_density", 0.01)), 0.0001), 0.0, 1.0)
	var haze: Color = _col(fog_cfg, "haze_color") * lerpf(float(fog_cfg.get("night_floor", 0.1)), 1.0, daylight)
	haze.a = 1.0
	snap.fog_color = snap.sky_horizon.lerp(haze, fog_amt)
	return snap


static func _col(d: Dictionary, key: String) -> Color:
	var a: Array = d.get(key, [1.0, 1.0, 1.0]) as Array
	return Color(float(a[0]), float(a[1]), float(a[2]), float(a[3]) if a.size() > 3 else 1.0)


# Desaturated copy keeping perceived brightness: overcast skies are grey, not dark.
static func _grey(c: Color, brightness: float) -> Color:
	var l: float = c.get_luminance() * brightness
	return Color(l, l, l, 1.0)
