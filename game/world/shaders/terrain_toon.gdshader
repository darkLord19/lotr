shader_type spatial;
// Toon/painterly terrain: banded sun lighting, a 3-stop colour ramp per splat layer, noisy layer
// edges and a soft rim. All values arrive from config/style.json via StyleMaterials.
render_mode cull_disabled, specular_disabled, diffuse_lambert;

const int LAYERS = 7; // grass, grass_alt, path, field, riverbank, forest_floor, rock

uniform sampler2D splat : filter_linear, repeat_disable;
uniform vec2 region_size = vec2(8192.0, 4096.0);
uniform vec3 ramp_shire[21];
uniform vec3 ramp_bree[21];
uniform vec2 bree_blend = vec2(6800.0, 7350.0);
uniform float bands = 4.0;
uniform float band_softness = 0.25;
uniform float light_wrap = 0.2;
uniform vec3 rim_color = vec3(1.0, 0.8, 0.6);
uniform float rim_strength = 0.12;
uniform float rim_power = 3.0;
uniform float detail_wavelength = 70.0;
uniform float detail_strength = 0.2;
uniform float breakup = 0.5;
uniform float breakup_edge = 0.14;
uniform float gold_wavelength = 520.0;
uniform vec2 gold_threshold = vec2(0.42, 0.62);
uniform vec2 rock_slope = vec2(0.5, 0.95);

varying vec3 world_pos;
varying vec3 world_normal;

// Written in fragment(), read in light(): the three ramp stops of the blended layer mix.
varying vec3 g_shade;
varying vec3 g_mid;
varying vec3 g_lit;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
			mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

float edge(float w, float n) {
	return smoothstep(0.5 - breakup_edge, 0.5 + breakup_edge, w + (n - 0.5) * breakup);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = NORMAL;
}

void fragment() {
	vec4 s = texture(splat, world_pos.xz / region_size);
	float n_mid = vnoise(world_pos.xz / detail_wavelength);
	float n_fine = vnoise(world_pos.xz / (detail_wavelength * 0.23));
	float n = n_mid * 0.65 + n_fine * 0.35;

	float slope = sqrt(max(1.0 - world_normal.y * world_normal.y, 0.0)) / max(world_normal.y, 0.05);
	float rock = smoothstep(rock_slope.x, rock_slope.y, slope);

	// Priority stacking as in tools/terrain/build_heightmap.py, so weights always sum to 1.
	float rem = 1.0;
	float w_path = edge(s.r, n) * rem; rem -= w_path;
	float w_bank = edge(s.g, n) * rem; rem -= w_bank;
	float w_rock = rock * rem; rem -= w_rock;
	float w_forest = edge(s.b, n) * rem; rem -= w_forest;
	float w_field = edge(s.a, n) * rem; rem -= w_field;
	float gold = smoothstep(gold_threshold.x, gold_threshold.y, vnoise(world_pos.xz / gold_wavelength));
	float w[LAYERS] = float[](rem * (1.0 - gold), rem * gold, w_path, w_field, w_bank, w_forest, w_rock);

	float pm = smoothstep(bree_blend.x, bree_blend.y, world_pos.x);
	vec3 c0 = vec3(0.0);
	vec3 c1 = vec3(0.0);
	vec3 c2 = vec3(0.0);
	for (int l = 0; l < LAYERS; l++) {
		c0 += w[l] * mix(ramp_shire[l * 3], ramp_bree[l * 3], pm);
		c1 += w[l] * mix(ramp_shire[l * 3 + 1], ramp_bree[l * 3 + 1], pm);
		c2 += w[l] * mix(ramp_shire[l * 3 + 2], ramp_bree[l * 3 + 2], pm);
	}
	float mottle = 1.0 + (n - 0.5) * 2.0 * detail_strength;
	g_shade = c0 * mottle;
	g_mid = c1 * mottle;
	g_lit = c2 * mottle;

	ALBEDO = g_mid;
	ROUGHNESS = 1.0;
	EMISSION = rim_color * rim_strength * pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
}

void light() {
	float ndl = clamp((dot(NORMAL, LIGHT) + light_wrap) / (1.0 + light_wrap), 0.0, 1.0) * ATTENUATION;
	float t = ndl * bands;
	float lv = min(floor(t), bands - 1.0);
	float step_up = lv < bands - 1.0 ? smoothstep(1.0 - band_softness, 1.0, fract(t)) : 0.0;
	float q = (lv + step_up) / (bands - 1.0);
	vec3 col = q < 0.5 ? mix(g_shade, g_mid, q * 2.0) : mix(g_mid, g_lit, q * 2.0 - 1.0);
	// Diffuse is multiplied by ALBEDO (= g_mid) afterwards, so divide it out to land on the ramp colour.
	DIFFUSE_LIGHT += LIGHT_COLOR * col / max(g_mid, vec3(0.02)) / PI;
}
