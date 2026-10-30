class_name WeatherDayNight
extends Node3D
# Applies WeatherModel output to a sun, a moon, a WorldEnvironment (sky, fog, ambient) and a
# camera-following rain emitter. Missing child nodes are created, so dropping this one node into a
# scene is enough; assign the exports to drive your own nodes instead.

signal weather_state_changed(state: StringName)

@export var sun: DirectionalLight3D
@export var moon: DirectionalLight3D
@export var world_environment: WorldEnvironment
@export var rain: GPUParticles3D
## Debug/capture overrides; empty means "follow the seeded schedule".
@export var forced_state: StringName = &""
@export var forced_dawn_fog: bool = false
## Fixed minute (game time) instead of WorldClock.now; negative = follow the clock.
@export var minute_override: int = -1

# A light this dim is hidden outright so its shadow pass costs nothing.
const LIGHT_VISIBLE_MIN: float = 0.002
const SUN_ANGULAR_DISTANCE: float = 1.2
const MOON_ANGULAR_DISTANCE: float = 2.0
const SUN_SHADOW_MAX_DISTANCE: float = 120.0
const SKY_GROUND_DARKEN: float = 0.5
const SKY_CURVE: float = 0.15
const RAIN_AABB_HEIGHT: float = 30.0
const SAVE_KEY: String = "weather"

var model: WeatherModel
var current: WeatherModel.Snapshot
var _sky_mat: ProceduralSkyMaterial
var _env: Environment
var _last_minute: float = -1.0
var _last_state: StringName = &""
var _dirty: bool = true
var _rain_cfg: Dictionary = {}


func _ready() -> void:
	model = WeatherModel.new()
	_rain_cfg = model.cfg.get("rain", {}) as Dictionary
	_ensure_nodes()
	apply(_current_minute())
	SaveSystem.register_participant(SAVE_KEY, serialise, deserialise)


func _exit_tree() -> void:
	SaveSystem.unregister_participant(SAVE_KEY, serialise)


func _process(_delta: float) -> void:
	var m: float = _current_minute()
	if _dirty or not is_equal_approx(m, _last_minute):
		apply(m)
	_follow_camera()


# --- public API -------------------------------------------------------------------

func get_weather_seed() -> int:
	return model.get_weather_seed()


func set_weather_seed(s: int) -> void:
	model.weather_seed = s
	_dirty = true


# Only the seed needs saving: the whole schedule is a pure function of it.
func serialise() -> Dictionary:
	return model.serialise()


func deserialise(d: Dictionary) -> void:
	model.deserialise(d)
	_dirty = true


# For RiderPerception callers: add to concealment / multiply fear_strength by these.
func get_concealment_bonus() -> float:
	return current.concealment_bonus if current != null else 0.0


func get_fear_aura_multiplier() -> float:
	return current.fear_aura_multiplier if current != null else 1.0


func force(state: StringName, dawn_fog: bool = false) -> void:
	forced_state = state
	forced_dawn_fog = dawn_fog
	_dirty = true


# --- internals --------------------------------------------------------------------

func _current_minute() -> float:
	return float(minute_override) if minute_override >= 0 else float(WorldClock.now)


func apply(minute: float) -> void:
	_dirty = false
	_last_minute = minute
	current = model.sample(minute, forced_state, forced_dawn_fog)
	_apply_light(sun, current.sun_dir_to, current.sun_energy, current.sun_color)
	_apply_light(moon, current.moon_dir_to, current.moon_energy, current.moon_color)
	_sky_mat.sky_top_color = current.sky_top
	_sky_mat.sky_horizon_color = current.sky_horizon
	_sky_mat.ground_horizon_color = current.sky_horizon
	_sky_mat.ground_bottom_color = current.sky_horizon.darkened(SKY_GROUND_DARKEN)
	_env.ambient_light_color = current.ambient_color
	_env.ambient_light_energy = current.ambient_energy
	_env.fog_enabled = current.fog_density > 0.0
	_env.fog_density = current.fog_density
	_env.fog_light_color = current.fog_color
	_apply_rain(current.rain_intensity)
	if current.state != _last_state:
		_last_state = current.state
		weather_state_changed.emit(current.state)


func _apply_light(light: DirectionalLight3D, dir_to_body: Vector3, energy: float, color: Color) -> void:
	light.visible = energy > LIGHT_VISIBLE_MIN
	light.light_energy = energy
	light.light_color = color
	# Lights shine along -Z; the body is above, so the light travels opposite to dir_to_body.
	# A purely vertical body would make looking_at degenerate, so fall back to a side up vector.
	var up: Vector3 = Vector3.UP if absf(dir_to_body.y) < 0.999 else Vector3.FORWARD
	light.global_transform.basis = Basis.looking_at(-dir_to_body, up)


func _apply_rain(intensity: float) -> void:
	var visible_min: float = float(_rain_cfg.get("min_visible_intensity", 0.02))
	rain.emitting = intensity > visible_min
	# Fewer drops in light rain without rebuilding the particle buffer.
	rain.amount_ratio = clampf(intensity, 0.0, 1.0)


func _follow_camera() -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	# Rain only needs to exist around the viewer; sit above them, aligned to world axes.
	var height: float = float(_rain_cfg.get("emitter_height_m", 12.0))
	rain.global_position = cam.global_position + Vector3.UP * height


func _ensure_nodes() -> void:
	if sun == null:
		sun = DirectionalLight3D.new()
		sun.name = "Sun"
		sun.shadow_enabled = true
		sun.directional_shadow_max_distance = SUN_SHADOW_MAX_DISTANCE
		add_child(sun)
	sun.light_angular_distance = SUN_ANGULAR_DISTANCE
	if moon == null:
		moon = DirectionalLight3D.new()
		moon.name = "Moon"
		moon.shadow_enabled = true
		moon.directional_shadow_max_distance = SUN_SHADOW_MAX_DISTANCE
		add_child(moon)
	moon.light_angular_distance = MOON_ANGULAR_DISTANCE
	if world_environment == null:
		world_environment = WorldEnvironment.new()
		world_environment.name = "WorldEnvironment"
		add_child(world_environment)
	_env = world_environment.environment
	if _env == null:
		_env = Environment.new()
		world_environment.environment = _env
	_env.background_mode = Environment.BG_SKY
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	if _env.sky == null:
		_env.sky = Sky.new()
	_sky_mat = _env.sky.sky_material as ProceduralSkyMaterial
	if _sky_mat == null:
		_sky_mat = ProceduralSkyMaterial.new()
		_env.sky.sky_material = _sky_mat
	_sky_mat.sky_curve = SKY_CURVE
	if rain == null:
		rain = _build_rain()
		add_child(rain)


func _build_rain() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Rain"
	var half: float = float(_rain_cfg.get("area_half_extent_m", 14.0))
	var fall: float = float(_rain_cfg.get("fall_speed", 22.0))
	p.amount = int(_rain_cfg.get("max_particles", 2500))
	p.lifetime = float(_rain_cfg.get("lifetime_s", 0.7))
	# World-space particles so drops do not swing with the camera.
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-half, -RAIN_AABB_HEIGHT, -half), Vector3(half * 2.0, RAIN_AABB_HEIGHT, half * 2.0))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(half, 0.1, half)
	pm.direction = Vector3.DOWN
	pm.spread = 0.0
	pm.initial_velocity_min = fall
	pm.initial_velocity_max = fall
	pm.gravity = Vector3.ZERO
	p.process_material = pm
	var size: Array = _rain_cfg.get("streak_size", [0.012, 0.45]) as Array
	var mesh := BoxMesh.new()
	mesh.size = Vector3(float(size[0]), float(size[1]), float(size[0]))
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var rc: Array = _rain_cfg.get("color", [0.8, 0.85, 1.0, 0.4]) as Array
	mat.albedo_color = Color(float(rc[0]), float(rc[1]), float(rc[2]), float(rc[3]))
	mesh.material = mat
	p.draw_pass_1 = mesh
	p.emitting = false
	return p
