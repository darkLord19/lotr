shader_type sky;
// Painterly sky: three-stop gradient, banded cloud layer lit from the sun side, warm sun glow.

uniform vec3 zenith = vec3(0.25, 0.47, 0.8);
uniform vec3 horizon = vec3(0.96, 0.81, 0.61);
uniform vec3 ground = vec3(0.7, 0.6, 0.47);
uniform float horizon_curve = 0.45;
uniform vec3 sun_dir = vec3(-0.9, 0.27, 0.3);
uniform vec3 sun_glow = vec3(1.0, 0.72, 0.4);
uniform float sun_glow_power = 14.0;
uniform float sun_disc_size = 0.012;
uniform vec3 cloud_lit = vec3(1.0, 0.94, 0.83);
uniform vec3 cloud_shade = vec3(0.65, 0.66, 0.78);
uniform float cloud_cover = 0.52;
uniform float cloud_scale = 1.6;
uniform float cloud_softness = 0.12;
uniform float cloud_speed = 0.004;
uniform float cloud_bands = 3.0;

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

float fbm(vec2 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + 17.0;
		a *= 0.5;
	}
	return s;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 col = h >= 0.0 ? mix(horizon, zenith, pow(clamp(h, 0.0, 1.0), horizon_curve)) : mix(horizon, ground, clamp(-h * 4.0, 0.0, 1.0));
	float sd = max(dot(d, normalize(sun_dir)), 0.0);
	col += sun_glow * pow(sd, sun_glow_power) * 0.55;
	if (h > 0.0) {
		// Flat cloud deck: dividing by height squashes clouds toward the horizon for perspective.
		vec2 uv = d.xz / (h + 0.18) * cloud_scale + vec2(TIME * cloud_speed, 0.0);
		float dens = fbm(uv);
		float cover = smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover + cloud_softness, dens);
		// A second sample shifted toward the sun decides which side of a cloud is lit.
		vec2 toward_sun = normalize(sun_dir.xz + vec2(0.0001)) * 0.12;
		float lit_d = fbm(uv + toward_sun);
		float lit = clamp((dens - lit_d) * 6.0 + 0.5, 0.0, 1.0);
		lit = floor(lit * cloud_bands + 0.5) / cloud_bands;
		vec3 ccol = mix(cloud_shade, cloud_lit, lit);
		ccol += sun_glow * pow(sd, 6.0) * 0.25;
		float fade = smoothstep(0.0, 0.12, h);
		col = mix(col, ccol, cover * fade);
	}
	float disc = smoothstep(sun_disc_size * 1.4, sun_disc_size, acos(clamp(sd, -1.0, 1.0)));
	col = mix(col, vec3(1.0, 0.96, 0.85) * 1.6, disc * step(0.0, h + 0.02));
	COLOR = col;
}
