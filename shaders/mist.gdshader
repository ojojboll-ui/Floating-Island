shader_type fog;

// Mist, after fairy-tale woods at dusk: a heavy layer lying low over the
// ground, drifting and winding in slow tendrils (fbm noise, its coordinates
// warped by more noise that drifts with time), thicker in hollows, a few
// wisps rising higher, and spilling over the island's edge. The terrain
// texture gives the ground under each point, so the mist follows hills.
//
// Volumetric fog only scatters the light that reaches it, so at night it
// would go black; it glows a little of its own (`glow`, raised at night) in
// a pale moonlit white, as in the pictures it is after.

// value noise, as in noise.gdshaderinc (which a fog shader cannot include:
// it uses screen derivatives)
float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}
float vnoise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i);
	float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
	return mix(
		mix(mix(n000, n100, u.x), mix(n010, n110, u.x), u.y),
		mix(mix(n001, n101, u.x), mix(n011, n111, u.x), u.y),
		u.z);
}
float fbm3(vec3 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise3(p);
		p = p * 2.03 + vec3(17.1, 9.3, 4.7);
		a *= 0.5;
	}
	return s / 0.9375;
}

// r surface height, g distance to the coast
uniform sampler2D terrain : filter_linear, repeat_disable;
uniform float terrain_size = 32.0;
uniform float terrain_res = 161.0;
uniform float density = 0.4;
uniform vec3 albedo : source_color = vec3(0.9, 0.92, 0.95);
uniform vec3 glow_color : source_color = vec3(0.78, 0.84, 0.95);
uniform float glow = 0.0;
uniform float thickness = 0.9;   // metres the layer lies deep
uniform float drift = 1.0;       // how fast it winds along

vec4 ground_at(vec2 xz) {
	vec2 uv = (xz / terrain_size + 0.5) * (terrain_res - 1.0) / terrain_res + 0.5 / terrain_res;
	return textureLod(terrain, uv, 0.0);
}

void fog() {
	vec3 p = WORLD_POSITION;
	vec4 g = ground_at(p.xz);
	float coast = g.g;
	// beyond the coast the mist pours over the edge and hangs down
	float base = g.r - max(-coast, 0.0) * 0.9;
	float above = p.y - base;
	float t = TIME * 0.05 * drift;
	// tendrils: noise along the ground, its coordinates bent by a slower noise
	vec3 q = p * vec3(0.24, 0.8, 0.24);
	vec3 warp = vec3(fbm3(q * 0.7 + vec3(t, 0.0, t * 0.6)), fbm3(q * 0.7 + vec3(3.1, t * 0.4, -t)), fbm3(q * 0.7 + vec3(-t * 0.8, 7.7, 1.9))) - 0.5;
	float n = fbm3(q + warp * 2.6 + vec3(-t * 1.6, t * 0.3, t * 0.9));
	float strands = smoothstep(0.32, 0.68, n);
	// how deep the layer lies here: deeper in places, a few wisps rising
	float deep = thickness * (0.55 + 0.9 * fbm3(p * 0.18 + vec3(t * 0.5, 0.0, 2.0)));
	float layer = 1.0 - smoothstep(deep * 0.25, deep, above);
	float wisps = smoothstep(0.66, 0.82, n) * (1.0 - smoothstep(deep, deep * 2.8, above)) * 0.5;
	float d = max(layer * mix(0.06, 1.0, strands * strands), wisps);
	// not under the ground, thinning away from the island and toward the
	// volume's sides
	d *= smoothstep(-0.25, 0.1, above);
	d *= smoothstep(-3.0, 0.0, coast);
	vec3 edge = min(UVW, 1.0 - UVW);
	d *= smoothstep(0.0, 0.08, min(edge.x, edge.z));
	DENSITY = density * d;
	ALBEDO = albedo;
	EMISSION = glow_color * glow;
}
