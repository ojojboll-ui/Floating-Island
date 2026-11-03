shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// The mist for the lighter look (the web build), where there is no
// volumetric fog to draw mist.gdshader in: the same low, winding layer, drawn
// as a stack of sheets that each follow the ground at their own height above
// it (weather.gd builds them: UV2.x is a sheet's share of the way up, UV2.y
// how deep a slab of air it stands for). Each sheet asks the same question
// as the fog shader does, how thick the mist is here, with cheaper noise.

// r surface height, g distance to the coast
uniform sampler2D terrain : filter_linear, repeat_disable;
uniform float terrain_size = 32.0;
uniform float terrain_res = 161.0;
uniform float density = 0.4;
uniform vec3 lit_color : source_color = vec3(0.9, 0.92, 0.95);
uniform float thickness = 0.9;
uniform float drift = 1.0;

varying vec3 wpos;
varying float above;
varying float slab;

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}
float vnoise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash13(i), hash13(i + vec3(1.0, 0.0, 0.0)), u.x), mix(hash13(i + vec3(0.0, 1.0, 0.0)), hash13(i + vec3(1.0, 1.0, 0.0)), u.x), u.y),
		mix(mix(hash13(i + vec3(0.0, 0.0, 1.0)), hash13(i + vec3(1.0, 0.0, 1.0)), u.x), mix(hash13(i + vec3(0.0, 1.0, 1.0)), hash13(i + vec3(1.0, 1.0, 1.0)), u.x), u.y),
		u.z);
}
float fbm(vec3 p, int octaves) {
	float s = 0.0;
	float a = 0.5;
	float n = 0.0;
	for (int i = 0; i < octaves; i++) {
		s += a * vnoise3(p);
		n += a;
		p = p * 2.03 + vec3(17.1, 9.3, 4.7);
		a *= 0.5;
	}
	return s / n;
}

vec4 ground_at(vec2 xz) {
	vec2 uv = (xz / terrain_size + 0.5) * (terrain_res - 1.0) / terrain_res + 0.5 / terrain_res;
	return textureLod(terrain, uv, 0.0);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec4 g = ground_at(wpos.xz);
	// beyond the coast the mist pours over the edge and hangs down
	float base = g.r - max(-g.g, 0.0) * 0.9;
	// the sheets crowd near the ground, where the mist is thickest
	above = thickness * 3.0 * UV2.x;
	slab = thickness * 3.0 * UV2.y;
	wpos.y = base + above;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(wpos, 1.0)).xyz;
}

void fragment() {
	vec3 p = wpos;
	vec4 g = ground_at(p.xz);
	float coast = g.g;
	float t = TIME * 0.05 * drift;
	vec3 q = p * vec3(0.24, 0.8, 0.24);
	vec3 warp = vec3(fbm(q * 0.7 + vec3(t, 0.0, t * 0.6), 2), 0.5, fbm(q * 0.7 + vec3(-t * 0.8, 7.7, 1.9), 2)) - 0.5;
	float n = fbm(q + warp * 2.6 + vec3(-t * 1.6, t * 0.3, t * 0.9), 3);
	float strands = smoothstep(0.32, 0.68, n);
	float deep = thickness * (0.55 + 0.9 * vnoise3(p * 0.18 + vec3(t * 0.5, 0.0, 2.0)));
	float layer = 1.0 - smoothstep(deep * 0.25, deep, above);
	float wisps = smoothstep(0.66, 0.82, n) * (1.0 - smoothstep(deep, deep * 2.8, above)) * 0.5;
	float d = max(layer * mix(0.06, 1.0, strands * strands), wisps);
	d *= smoothstep(-2.5, 0.0, coast);
	// a sheet seen on edge stands for a longer path through its air, but its
	// rim must not show as a line: where it bends down over the coast too
	vec3 view = normalize(p - CAMERA_POSITION_WORLD);
	vec3 sheet = normalize(cross(dFdx(p), dFdy(p)));
	float facing = abs(dot(view, sheet));
	float path = slab / max(facing, 0.3);
	float alpha = 1.0 - exp(-density * d * path * 1.1);
	alpha *= smoothstep(0.08, 0.35, facing);
	ALBEDO = lit_color;
	ALPHA = clamp(alpha, 0.0, 0.85);
}
