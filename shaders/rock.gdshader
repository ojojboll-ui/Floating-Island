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
// stones this one is stacked with: centre and radius, w 0 for none, so the
// seam where they meet fills with moss and soil and sits in shade
instance uniform vec4 touch_a = vec4(0.0);
instance uniform vec4 touch_b = vec4(0.0);

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

// Slate, after the Quaternius rock texture: angular plates of all sizes,
// each lying flat at its own slight tilt and in its own shade of
// blue-grey, with a soft pale ridge where it meets the next, a fine dark
// crack here and there inside it, and moss specks caught in the joins.
// Big plates come from one Voronoi pattern; some of them split again into
// smaller ones from a finer pattern. Returns the distance to the nearest
// edge (x) and an id for the plate (y).
vec3 cells(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	vec3 best = vec3(0.0);
	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 g = vec3(float(x), float(y), float(z));
				vec3 o = vec3(hash13(i + g), hash13(i + g + 17.3), hash13(i + g + 41.7));
				float d = length(g + o - f);
				if (d < d1) {
					d2 = d1;
					d1 = d;
					best = i + g;
				} else if (d < d2) {
					d2 = d;
				}
			}
		}
	}
	return vec3(d2 - d1, hash13(best), hash13(best + 3.3));
}

vec2 slate(vec3 p) {
	// a slight shear, so the plates are not the same in every direction
	vec3 q = vec3(p.x + p.y * 0.35, p.y * 1.25, p.z - p.y * 0.2);
	vec3 big = cells(q * 1.15);
	vec3 small = cells(q * 2.6 + 11.0);
	// about half the big plates split into smaller ones
	float split = step(0.5, big.z);
	float edge = big.x / 1.15;
	float id = big.y;
	if (split > 0.5) {
		edge = min(edge, small.x / 2.6 * 1.3);
		id = mix(big.y, small.y, 0.6);
	}
	return vec2(edge, id);
}

void fragment() {
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	mat3 turn = mat3(normalize(MODEL_MATRIX[0].xyz), normalize(MODEL_MATRIX[1].xyz), normalize(MODEL_MATRIX[2].xyz));
	vec2 sl = slate(opos);
	float edge = sl.x;
	float id = sl.y;
	float amount = 0.25 + 0.75 * texture_amount;
	// each plate lies flat at its own tilt: facets, not bumps
	vec3 tilt = vec3(hash12(vec2(id, 2.1)), hash12(vec2(id, 5.7)), hash12(vec2(id, 9.3))) - 0.5;
	vec3 tw = turn * tilt;
	vec3 bn = normalize(wn + (tw - wn * dot(tw, wn)) * 1.3 * amount);

	vec3 base = srgb(stone);
	// each plate its own shade, from slate blue to a pale lavender grey
	vec3 col = base * mix(vec3(0.68, 0.74, 0.9), vec3(1.15, 1.13, 1.14), smoothstep(0.0, 1.0, id)) * (0.9 + 0.15 * fbm3(opos * 1.3));
	// the pale ridge along every join, soft on the plate's side
	float ridge = 1.0 - smoothstep(0.005, 0.05, edge);
	float halo = 1.0 - smoothstep(0.0, 0.24, edge);
	// the worn plate rounds over toward the join: it lightens, then the ridge
	col = mix(col, col * 1.28 + 0.04, halo * halo * amount * 0.65);
	col = mix(col, col * 1.4 + 0.06, ridge * amount * 0.5);
	// a fine dark crack here and there, inside the plates
	float hair = abs(vnoise3(opos * 5.0 + 2.0) - 0.5);
	float crack = (1.0 - smoothstep(0.0, 0.012, hair)) * step(0.62, vnoise3(opos * 1.6 + 8.0)) * amount;
	col *= 1.0 - crack * 0.45;
	// moss specks caught in the joins
	float speck = smoothstep(0.72, 0.8, vnoise3(opos * 40.0)) * smoothstep(0.4, 1.0, halo) * smoothstep(0.2, 0.7, moss_amount + moss_boost * 0.4);
	col = mix(col, moss_tint(wpos) * 0.75, speck * 0.0);
	float h0 = 0.0;
	if (use_tex) {
		col = texture(albedo_tex, UV).rgb * (0.85 + 0.25 * fbm3(wpos * 3.0));
	}
	col *= tint;

	// the seam with a stone stacked on or under this one
	float seam = 0.0;
	for (int k = 0; k < 2; k++) {
		vec4 t = k == 0 ? touch_a : touch_b;
		if (t.w > 0.0) {
			float dist = length(wpos - t.xyz) - t.w * 0.8;
			seam = max(seam, 1.0 - smoothstep(0.0, 0.14 + 0.08 * fbm3(wpos * 5.0), dist));
		}
	}

	// moss: in broad drifts over the tops, gathered in the seams and cracks,
	// more the damper the stone lies
	float wet_moss = clamp(moss_amount + moss_boost * 0.45, 0.0, 1.2);
	float field = moss_field(wpos);
	float drift = fbm3(wpos * 1.6 + 4.0) * 0.8 + field * 0.3;
	// by the stone's own shape, not its bumps, so the moss lies in sheets
	float on_top = smoothstep(0.9 - wet_moss * 0.55, 1.05 - wet_moss * 0.4, wn.y * 0.8 + drift * 0.5);
	float in_cracks = halo * smoothstep(0.4, 1.0, wet_moss) * 0.35;
	float moss = clamp(on_top + in_cracks + seam * (0.3 + wet_moss * 0.6), 0.0, 1.0) * step(0.01, wet_moss + seam);
	// a soft, slightly fuzzy edge, not speckles
	moss = smoothstep(0.3, 0.6, moss + (vnoise3(wpos * 6.0) - 0.5) * 0.12);
	col = mix(col, moss_tint(wpos) * (0.5 + 0.55 * fbm3(wpos * 3.0)), moss * 0.92);
	// soil and shade down in the seam
	col = mix(col, srgb(vec3(0.3, 0.24, 0.17)), seam * seam * 0.45);
	col *= 1.0 - seam * 0.35;

	float foot = smoothstep(0.12, -0.02, wpos.y - ground_y + (fbm3(wpos * 4.0) - 0.5) * 0.1);
	col = mix(col, mix(grass_tint(wpos.xz) * 0.55, srgb(vec3(0.36, 0.27, 0.19)), 0.4), foot);

	NORMAL = normalize((VIEW_MATRIX * vec4(bn, 0.0)).xyz);
	ALBEDO = weathered(col, bn.y, wpos);
	ROUGHNESS = weathered_rough(mix(0.96, 0.8, moss), bn.y, wpos);
	SPECULAR = weathered_spec(0.18, bn.y, wpos);
}
