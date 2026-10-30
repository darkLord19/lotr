class_name StyleMaterials
extends RefCounted
# Builds the terrain/water/sky materials and environment from config/style.json, so changing the
# look never means touching code. Colours in the JSON are sRGB hex; shaders want linear.

const TERRAIN_SHADER: String = "res://world/shaders/terrain_toon.gdshader"
const WATER_SHADER: String = "res://world/shaders/water_toon.gdshader"
const SKY_SHADER: String = "res://world/shaders/sky_toon.gdshader"
const RAMP_STOPS: int = 3


static func style(path: String, default: Variant = null) -> Variant:
	return Config.get_value("style." + path, default)


static func lin(hex: String) -> Vector3:
	var c: Color = Color(hex).srgb_to_linear()
	return Vector3(c.r, c.g, c.b)


static func lin_color(hex: String) -> Color:
	return Color(hex).srgb_to_linear()


static func _ramp(palette: String) -> PackedVector3Array:
	var out := PackedVector3Array()
	var pal: Dictionary = style("palettes." + palette, {})
	for layer in style("layers", []):
		var stops: Array = pal.get(layer, [])
		for i in RAMP_STOPS:
			out.append(lin(String(stops[i])) if i < stops.size() else Vector3.ONE)
	return out


static func terrain_material(heights: TerrainHeights) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(TERRAIN_SHADER) as Shader
	var sh: Dictionary = style("shader", {})
	var tex := ImageTexture.create_from_image(heights.splat)
	m.set_shader_parameter("splat", tex)
	m.set_shader_parameter("region_size", heights.size_m())
	m.set_shader_parameter("ramp_shire", _ramp("shire"))
	m.set_shader_parameter("ramp_bree", _ramp("bree"))
	m.set_shader_parameter("bree_blend", Vector2(float(style("blend.bree_x_start_m", 0.0)), float(style("blend.bree_x_end_m", 1.0))))
	m.set_shader_parameter("bands", float(sh.get("bands", 4)))
	m.set_shader_parameter("band_softness", float(sh.get("band_softness", 0.25)))
	m.set_shader_parameter("light_wrap", float(sh.get("light_wrap", 0.2)))
	var rim: Array = sh.get("rim_color", [1, 1, 1])
	m.set_shader_parameter("rim_color", Vector3(rim[0], rim[1], rim[2]))
	m.set_shader_parameter("rim_strength", float(sh.get("rim_strength", 0.1)))
	m.set_shader_parameter("rim_power", float(sh.get("rim_power", 3.0)))
	m.set_shader_parameter("detail_wavelength", float(sh.get("detail_wavelength_m", 70.0)))
	m.set_shader_parameter("detail_strength", float(sh.get("detail_strength", 0.2)))
	m.set_shader_parameter("breakup", float(sh.get("breakup", 0.5)))
	m.set_shader_parameter("breakup_edge", float(sh.get("breakup_edge", 0.14)))
	m.set_shader_parameter("gold_wavelength", float(sh.get("gold_wavelength_m", 500.0)))
	var gt: Array = sh.get("gold_threshold", [0.4, 0.6])
	m.set_shader_parameter("gold_threshold", Vector2(gt[0], gt[1]))
	var rs: Array = sh.get("rock_slope", [0.5, 0.9])
	m.set_shader_parameter("rock_slope", Vector2(rs[0], rs[1]))
	return m


static func water_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(WATER_SHADER) as Shader
	var w: Dictionary = style("water", {})
	m.set_shader_parameter("shallow_color", lin(String(w.get("shallow", "#66bbb0"))))
	m.set_shader_parameter("deep_color", lin(String(w.get("deep", "#2a6f92"))))
	m.set_shader_parameter("foam_color", lin(String(w.get("foam", "#ffffff"))))
	m.set_shader_parameter("sky_color", lin(String(style("sky.horizon", "#f6cf9c"))))
	for key in ["alpha", "bands", "foam_width", "ripple_scale", "ripple_speed", "sky_reflect"]:
		m.set_shader_parameter(key, float(w.get(key, 0.0)))
	return m


# Unit vector pointing from the ground towards the sun. Azimuth is a compass bearing
# (0 = north = -Z, 90 = east = +X); the sun sets in the west, hence ~255 for golden hour.
static func sun_direction() -> Vector3:
	var az: float = deg_to_rad(float(style("sun.azimuth_deg", 255.0)))
	var el: float = deg_to_rad(float(style("sun.elevation_deg", 16.0)))
	return Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el)).normalized()


static func sky_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(SKY_SHADER) as Shader
	var s: Dictionary = style("sky", {})
	m.set_shader_parameter("zenith", lin(String(s.get("zenith", "#3f78c8"))))
	m.set_shader_parameter("horizon", lin(String(s.get("horizon", "#f6cf9c"))))
	m.set_shader_parameter("ground", lin(String(s.get("ground", "#b59a78"))))
	m.set_shader_parameter("sun_glow", lin(String(s.get("sun_glow", "#ffb868"))))
	m.set_shader_parameter("cloud_lit", lin(String(s.get("cloud_color_lit", "#fff0d4"))))
	m.set_shader_parameter("cloud_shade", lin(String(s.get("cloud_color_shade", "#a7a9c8"))))
	m.set_shader_parameter("sun_dir", sun_direction())
	for key in ["horizon_curve", "sun_glow_power", "sun_disc_size", "cloud_cover", "cloud_scale", "cloud_softness", "cloud_speed", "cloud_bands"]:
		m.set_shader_parameter(key, float(s.get(key, 0.0)))
	return m


static func environment() -> Environment:
	var e := Environment.new()
	var cfg: Dictionary = style("environment", {})
	var sky := Sky.new()
	sky.sky_material = sky_material()
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = lin_color(String(style("palettes.shire.ambient", "#8aa4c8")))
	e.ambient_light_energy = float(cfg.get("ambient_energy", 0.5))
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC if String(cfg.get("tonemap", "filmic")) == "filmic" else Environment.TONE_MAPPER_LINEAR
	e.tonemap_exposure = float(cfg.get("exposure", 1.0))
	e.fog_enabled = true
	e.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	e.fog_light_color = lin_color(String(style("palettes.shire.fog", "#f3d9a8")))
	e.fog_density = float(cfg.get("fog_density", 0.001))
	e.fog_aerial_perspective = float(cfg.get("fog_aerial_perspective", 0.5))
	e.fog_sky_affect = float(cfg.get("fog_sky_affect", 0.8))
	e.fog_height = float(cfg.get("fog_height_m", 0.0))
	e.fog_height_density = float(cfg.get("fog_height_density", 0.0))
	return e


static func configure_sun(sun: DirectionalLight3D) -> void:
	var cfg: Dictionary = style("sun", {})
	sun.light_color = lin_color(String(cfg.get("color", "#ffd9a0")))
	sun.light_energy = float(cfg.get("energy", 1.2))
	sun.shadow_enabled = bool(cfg.get("shadows", true))
	sun.directional_shadow_max_distance = float(cfg.get("shadow_max_distance_m", 600.0))
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	# The light node's -Z is the direction light travels, i.e. away from the sun.
	sun.transform = Transform3D(Basis.looking_at(-sun_direction(), Vector3.UP), sun.transform.origin)


# Fog follows the settlement palette by x, so Bree reads greyer than the Shire.
static func fog_color_at(x: float) -> Color:
	var t: float = smoothstep(float(style("blend.bree_x_start_m", 0.0)), float(style("blend.bree_x_end_m", 1.0)), x)
	var a: Color = lin_color(String(style("palettes.shire.fog", "#ffffff")))
	var b: Color = lin_color(String(style("palettes.bree.fog", "#ffffff")))
	return a.lerp(b, t)
