shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap;

// The generated small plants (plant_gen.gd): ferns, flowers, clover,
// mushrooms and tall grass. Vertex colour says which part a vertex belongs
// to (r: 0 green, 0.25 mushroom stem, 0.5 petal or cap, 1 centre or seed
// head), how much light it gets (g), a random (b) and how much it sways
// (a); the colours themselves are per plant, from the panel's pickers.

#include "res://shaders/noise.gdshaderinc"

instance uniform vec3 color_a = vec3(0.3, 0.52, 0.16);   // leaves and stems
instance uniform vec3 color_b = vec3(0.85, 0.5, 0.7);    // petals, caps
instance uniform vec3 color_c = vec3(0.95, 0.8, 0.3);    // centres, spots, seed heads
instance uniform float spots = 0.0;
instance uniform float lawn = 0.0;                       // tall grass takes the lawn's colour
instance uniform vec3 tint = vec3(1.0);
instance uniform float height = 1.0;
instance uniform float ground_y = 0.0;

varying vec4 vcol;
varying vec3 wpos;
varying vec3 opos;

void vertex() {
	vcol = COLOR;
	opos = VERTEX;
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float gust = vnoise2(w.xz * 0.15 + vec2(TIME * 0.3, TIME * 0.2));
	vec2 push = vec2(sin(TIME * 1.4 + w.x * 0.5 + w.z * 0.3) * 0.5 + gust - 0.5, cos(TIME * 1.2 + w.z * 0.5) * 0.4);
	float flutter = sin(TIME * 5.0 + COLOR.b * 30.0) * 0.12;
	float sway = COLOR.a * COLOR.a;
	vec3 move = vec3(push.x + flutter, 0.0, push.y) * sway * 0.07 * length(MODEL_MATRIX[1].xyz) * wind_sway();
	VERTEX += (inverse(MODEL_MATRIX) * vec4(move, 0.0)).xyz;
	wpos = w + move;
}

void fragment() {
	float part = vcol.r;
	vec3 base;
	if (part < 0.12) {
		base = srgb(color_a);
		base = mix(base, grass_tint(wpos.xz) * 1.1, lawn);
	} else if (part < 0.37) {
		base = srgb(mix(vec3(0.93, 0.88, 0.78), color_a, 0.12));
	} else if (part < 0.75) {
		base = srgb(color_b);
		if (spots > 0.0) {
			// round spots on a cap, from cells in its own space
			vec3 q = opos * 18.0;
			vec3 cell = floor(q);
			float d = 9.0;
			for (int z = -1; z <= 1; z++) for (int y = -1; y <= 1; y++) for (int x = -1; x <= 1; x++) {
				vec3 g = cell + vec3(float(x), float(y), float(z));
				vec3 o = vec3(hash13(g), hash13(g + 7.1), hash13(g + 13.7));
				d = min(d, length(g + o - q) / (0.3 + 0.35 * hash13(g + 3.3)));
			}
			base = mix(base, srgb(color_c), (1.0 - smoothstep(0.75, 0.95, d)) * step(hash13(cell + 1.9), spots));
		}
	} else {
		base = srgb(color_c);
	}
	base *= tint;
	// deep down in shade, light toward the tips; a little per-piece variation
	base *= mix(0.5, 1.08, vcol.g) * (0.92 + 0.16 * vcol.b);
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	ALBEDO = weathered(base, max(wn.y, vcol.g * 0.6), wpos);
	ROUGHNESS = weathered_rough(part > 0.37 && part < 0.75 ? 0.55 : 0.8, wn.y, wpos);
	SPECULAR = weathered_spec(0.3, wn.y, wpos);
	// light glows through leaves and petals, not through caps
	BACKLIGHT = base * (part < 0.12 ? 0.45 : (part > 0.37 && spots <= 0.0 ? 0.35 : 0.05));
}
