shader_type spatial;
// Stylized river water for ribbon meshes: UV.x runs 0..1 across the river, UV.y is metres along it.
// Unshaded: the warm low sun would otherwise multiply the blue to grey; bands carry the depth cue.
render_mode cull_disabled, depth_draw_opaque, unshaded;

uniform vec3 shallow_color = vec3(0.37, 0.72, 0.69);
uniform vec3 deep_color = vec3(0.16, 0.44, 0.57);
uniform vec3 foam_color = vec3(0.95, 0.94, 0.88);
uniform vec3 sky_color = vec3(0.9, 0.8, 0.65);
uniform float alpha = 0.86;
uniform float bands = 3.0;
uniform float foam_width = 0.14;
uniform float ripple_scale = 0.045;
uniform float ripple_speed = 0.35;
uniform float sky_reflect = 0.35;

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

void fragment() {
	float across = abs(UV.x * 2.0 - 1.0);
	vec2 flow = vec2(UV.x * 40.0, UV.y - TIME * ripple_speed * 6.0) * ripple_scale * 4.0;
	float r = vnoise(flow * 3.0) * 0.6 + vnoise(flow * 7.0 + 11.0) * 0.4;
	float depth_t = clamp(1.0 - across * across + (r - 0.5) * 0.35, 0.0, 1.0);
	depth_t = floor(depth_t * bands) / bands;
	vec3 col = mix(shallow_color, deep_color, depth_t);
	// Foam: a ragged band along each bank plus sparse streaks in the current.
	float edge_noise = vnoise(vec2(UV.y * 0.35, TIME * 0.4 + UV.x * 3.0));
	float foam = smoothstep(1.0 - foam_width - 0.1 * edge_noise, 1.0 - foam_width * 0.5, across);
	foam = max(foam, step(0.9, r) * 0.35);
	col = mix(col, foam_color, foam);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	col = mix(col, sky_color, fres * sky_reflect);
	ALBEDO = col;
	ALPHA = mix(alpha, 1.0, foam);
	ROUGHNESS = 0.9;
}
