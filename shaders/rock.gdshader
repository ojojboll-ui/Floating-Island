shader_type spatial;
render_mode cull_back;

// Stones, generated (rock_builder.gd). The look follows the Quaternius rock
// texture: grey-blue stone split into plates by pale cracks, with moss lying
// in the hollows and on the tops. Here the cracks are the edges of a 3D
// Voronoi pattern in object space, so they wrap the stone without seams and
// stay put however it is turned; the moss comes from the shared moss field.
//
// Per stone: its colour, how much moss (and how damp it lies: by water or in
// a tree's shade there is more), and how strongly cracked and layered.

#include "res://shaders/noise.gdshaderinc"

uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap_anisotropic;
uniform bool use_tex = false;

instance uniform float ground_y = 0.0;
instance uniform vec3 tint = vec3(1.0);
instance uniform float height = 1.0;
instance uniform vec3 stone = vec3(0.56, 0.55, 0.52);
instance uniform float moss_amount = 0.5;
instance uniform float moss_boost = 0.0;
instance uniform float texture_amount = 0.5;

varying vec3 wpos;
varying vec3 opos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// object space at a metre's scale, so the cracks keep their size on any stone
	opos = VERTEX * length(MODEL_MATRIX[0].xyz);
}

// distance to the nearest cell centre and to the edge between the two
// nearest cells, in a 3D Voronoi pattern
vec2 voronoi(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 g = vec3(float(x), float(y), float(z));
				vec3 o = vec3(hash13(i + g), hash13(i + g + 17.3), hash13(i + g + 41.7));
				float d = length(g + o - f);
				if (d < d1) {
					d2 = d1;
					d1 = d;
				} else if (d < d2) {
					d2 = d;
				}
			}
		}
	}
	return vec2(d1, d2 - d1);
}

float bump(vec3 p, float edge) {
	return fbm3(p * 2.2) * 0.1 + vnoise3(p * 8.0) * 0.02 - (1.0 - smoothstep(0.0, 0.06, edge)) * 0.05 * texture_amount;
}

void fragment() {
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec2 cell = voronoi(opos * 3.2 + vec3(hash13(floor(wpos * 0.1)) * 9.0));
	float e = 0.02;
	float h0 = bump(wpos, cell.y);
	vec3 g = vec3(bump(wpos + vec3(e, 0.0, 0.0), cell.y), bump(wpos + vec3(0.0, e, 0.0), cell.y), bump(wpos + vec3(0.0, 0.0, e), cell.y)) - h0;
	g /= e;
	vec3 bn = normalize(wn - (g - wn * dot(g, wn)) * 0.9);

	vec3 base = srgb(stone);
	// each plate a slightly different grey, cooler or warmer
	float plate = hash13(floor(opos * 3.2 + 0.5));
	vec3 col = base * mix(vec3(0.82, 0.88, 1.04), vec3(1.1, 1.03, 0.93), plate) * (0.75 + 0.4 * fbm3(opos * 2.0));
	// layers running through the stone
	float layer = smoothstep(0.35, 0.5, abs(fract(opos.y * 4.0 + fbm3(opos * 1.5) * 0.8) - 0.5));
	col *= mix(1.0, 0.86 + 0.14 * layer, texture_amount);
	// the cracks: pale lines along the plate edges, dark in their depth
	float crack = 1.0 - smoothstep(0.015, 0.07, cell.y);
	col = mix(col, col * 1.45 + 0.06, crack * texture_amount * 0.8);
	col *= mix(1.0, 0.45, (1.0 - smoothstep(0.0, 0.02, cell.y)) * texture_amount);
	if (use_tex) {
		col = texture(albedo_tex, UV).rgb * (0.85 + 0.25 * fbm3(wpos * 3.0));
	}
	col *= tint;

	// moss: on the tops and in the cracks, more the damper the stone lies
	float wet_moss = clamp(moss_amount + moss_boost * 0.45, 0.0, 1.2);
	float field = moss_field(wpos);
	float on_top = smoothstep(0.95 - wet_moss * 0.9, 1.1 - wet_moss * 0.6, bn.y + (field - 0.5) * 0.7);
	float in_cracks = crack * smoothstep(0.3, 0.9, wet_moss) * 0.6;
	// broken into patches, never a cap
	float patches = smoothstep(0.32, 0.62, fbm3(wpos * 3.5) + (field - 0.5) * 0.5 + wet_moss * 0.25);
	float moss = clamp(on_top * patches + in_cracks, 0.0, 1.0) * step(0.01, wet_moss);
	col = mix(col, moss_tint(wpos) * (0.65 + 0.45 * fbm3(wpos * 9.0)), moss * 0.92);

	float foot = smoothstep(0.12, -0.02, wpos.y - ground_y + (fbm3(wpos * 4.0) - 0.5) * 0.1);
	col = mix(col, mix(grass_tint(wpos.xz) * 0.55, srgb(vec3(0.36, 0.27, 0.19)), 0.4), foot);

	NORMAL = normalize((VIEW_MATRIX * vec4(bn, 0.0)).xyz);
	ALBEDO = weathered(col, bn.y, wpos);
	ROUGHNESS = weathered_rough(mix(0.96, 0.8, moss), bn.y, wpos);
	SPECULAR = weathered_spec(0.18, bn.y, wpos);
}
