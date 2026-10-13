shader_type spatial;
render_mode cull_disabled, world_vertex_coords, diffuse_lambert_wrap, alpha_to_coverage;

// Leaf cards. Each card draws a small spray of leaves; colour.r says how far
// out in the canopy the card sits (dark inside, sunlit outside) and colour.g
// is a per-card random for hue and flutter.

#include "res://shaders/noise.gdshaderinc"

instance uniform vec3 leaf_color = vec3(0.46, 0.66, 0.20);
instance uniform float needles = 0.0;

varying float outer;
varying float rnd;
varying vec3 wnormal;
varying vec3 wleaf;

float leaf(vec2 uv, vec2 at, float ang, vec2 size) {
	vec2 d = uv - at;
	float c = cos(ang);
	float s = sin(ang);
	d = vec2(c * d.x + s * d.y, -s * d.x + c * d.y) / size;
	// pointed at both ends: narrow the width as |y| grows
	float w = 1.0 - d.y * d.y;
	return w - abs(d.x) * 1.6;
}

void vertex() {
	outer = COLOR.r;
	rnd = COLOR.g;
	vec3 p = VERTEX;
	float sway = sin(TIME * 1.2 + p.x * 0.45 + p.y * 0.3) + 0.6 * vnoise2(p.xz * 0.2 + TIME * 0.3);
	float flutter = sin(TIME * 5.5 + rnd * 40.0) * 0.5;
	VERTEX += vec3(sway * 0.05, flutter * 0.02, sway * 0.03) * (0.4 + outer) * wind_sway();
	// the whole crown streams with the wind, the outer leaves most, and they
	// shiver faster as it rises
	VERTEX += wind_dir() * wind_lean() * (0.15 + outer) * 0.22;
	VERTEX.y += sin(TIME * (7.0 + wind_strength * 9.0) + rnd * 60.0) * 0.012 * wind_strength * outer;
	wleaf = VERTEX;
	wnormal = NORMAL;
}

void fragment() {
	float a = -1.0;
	if (needles > 0.5) {
		// a spray of needles: thin blades fanning from the card's middle
		for (int k = 0; k < 9; k++) {
			float ang = float(k) * 0.698 + rnd * 6.28;
			vec2 at = vec2(0.5) + vec2(sin(ang), -cos(ang)) * 0.24;
			a = max(a, leaf(UV, at, ang, vec2(0.035, 0.27)));
		}
	} else {
		for (int k = 0; k < 5; k++) {
			float ang = float(k) * 1.2566 + rnd * 6.28;
			vec2 at = vec2(0.5) + vec2(sin(ang), -cos(ang)) * 0.2;
			a = max(a, leaf(UV, at, ang, vec2(0.11, 0.24)));
		}
		a = max(a, leaf(UV, vec2(0.5), rnd * 3.0, vec2(0.12, 0.22)));
	}
	ALPHA = clamp(a * 6.0 + 0.5, 0.0, 1.0);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALPHA_ANTIALIASING_EDGE = 0.3;

	// the tree's own colour: sunlit at the crown's skin, deep and cool inside
	vec3 light = srgb(leaf_color);
	vec3 dark = light * vec3(0.22, 0.34, 0.42);
	vec3 warm = light * vec3(1.3, 1.08, 0.8) + vec3(0.04, 0.03, 0.0);
	vec3 col = mix(dark, light, smoothstep(0.15, 0.95, outer));
	col = mix(col, warm, rnd * rnd * 0.35 * outer);
	ALBEDO = weathered(col, normalize(wnormal).y * 0.8 + outer * 0.3, wleaf);

	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(wnormal), 0.0)).xyz);
	ROUGHNESS = weathered_rough(0.75, 0.0, wleaf);
	SPECULAR = weathered_spec(0.3, 0.0, wleaf);
	BACKLIGHT = light * 0.8 * (0.3 + 0.7 * outer);
}
