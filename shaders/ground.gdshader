shader_type spatial;
render_mode cull_back;

// The island top. Vertex colour holds the painted weights (r laid stone,
// g sand, b moss, a dirt), uv.y the loose stones; grass is the rest. Each
// material also has its own noise "height", and the one standing tallest
// wins, so borders break up into tufts and pebbles instead of fading like a
// cross-dissolve.

#include "res://shaders/noise.gdshaderinc"

varying vec3 wpos;
varying vec4 weights;
varying float coast;
varying float rocks;  // loose stones weight
varying vec2 wet;   // water level, water amount

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	weights = COLOR;
	coast = UV.x;
	rocks = UV.y;
	wet = UV2;
}

// A loose stone's height: flat-topped with rounded shoulders, its face
// roughened by grain so it reads as stone rather than a smooth bead.
float stone_height(vec2 xz) {
	vec2 s = loose_stones(xz);
	float body = smoothstep(0.0, 0.55, s.x);
	return body * (0.08 + fbm2(xz * 16.0 + s.y * 40.0) * 0.035);
}

float surface_bump(vec2 xz, float stone, float loose) {
	float b = fbm2(xz * 5.0) * 0.03;
	if (stone > 0.0) {
		b += stone * cobbles(xz / 0.3).z * 0.05;
	}
	if (loose > 0.001) {
		b += loose * stone_height(xz);
	}
	return b;
}

// How strongly one of the three views bids to show the stones: how squarely
// it faces the surface, plus the height of the stone it would show here.
// Views turned away from the surface are not even asked.
float view_bid(vec2 p, float facing, float loose, float laid) {
	if (facing < 0.03) {
		return -1.0;
	}
	float h = 0.0;
	if (loose > 0.001) {
		h = max(h, loose_stones(p).x * loose);
	}
	if (laid > 0.001) {
		h = max(h, cobbles(p / 0.3).z * laid);
	}
	return facing + h * 0.5;
}

void fragment() {
	vec2 xz = wpos.xz;
	// Stones are laid out across the face they sit on: seen from above on
	// gentle ground, from the side on hillsides, so they never smear. Where
	// two views meet, each bids with how squarely it faces the surface plus
	// the height of the stone it would show there, and the higher bid wins.
	// The seam then runs around stones instead of cutting through them.
	vec3 gn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float w_rocks = clamp(rocks, 0.0, 1.0);
	vec3 tw = pow(abs(gn), vec3(4.0));
	tw /= tw.x + tw.y + tw.z;
	// the three asked in a loop, so the browser builds view_bid once, not
	// three times over (see weathered in noise.gdshaderinc)
	float bid_y = 0.0;
	float bid_x = 0.0;
	float bid_z = 0.0;
	for (int k = 0; k < LOOPS(3); k++) {
		vec2 p = k == 0 ? xz : (k == 1 ? wpos.zy : wpos.xy);
		float b = view_bid(p, k == 0 ? tw.y : (k == 1 ? tw.x : tw.z), w_rocks, weights.r);
		if (k == 0) {
			bid_y = b;
		} else if (k == 1) {
			bid_x = b;
		} else {
			bid_z = b;
		}
	}
	vec2 face = xz;
	// the world directions the two face coordinates run along
	vec3 face_u = vec3(1.0, 0.0, 0.0);
	vec3 face_v = vec3(0.0, 0.0, 1.0);
	if (bid_x > bid_y && bid_x >= bid_z) {
		face = wpos.zy;
		face_u = vec3(0.0, 0.0, 1.0);
		face_v = vec3(0.0, 1.0, 0.0);
	} else if (bid_z > bid_y && bid_z > bid_x) {
		face = wpos.xy;
		face_u = vec3(1.0, 0.0, 0.0);
		face_v = vec3(0.0, 1.0, 0.0);
	}
	float w_grass = max(0.0, 1.0 - (weights.r + weights.g + weights.b + weights.a + w_rocks));
	vec2 ls = vec2(0.0);
	if (w_rocks > 0.001) {
		ls = loose_stones(face);
	}
	// Each material bids with its painted weight plus a height of its own;
	// the highest bid shows. Stones bid with their domes, so a stone patch
	// frays into single cobbles at its edge.
	// Every noise here lies in 0..1, so each bid has a ceiling (its weight
	// plus the most its noise can add). A material whose ceiling stays below
	// the leader's bid by the band can never show: its noise, cobbles and
	// colour are not worked out at all. On a lawn that is all but the grass.
	float band = 0.1;
	float s_grass = w_grass + fbm2(xz * 2.2 + vec2(9.2, 1.0)) * 0.8;
	float top = s_grass;
	float s_stone = -1.0;
	vec3 cb = vec3(0.0);
	if (weights.r + 0.85 > top - band) {
		cb = cobbles(face / 0.3);
		s_stone = weights.r + (cb.z * 0.6 + fbm2(xz * 3.0 + vec2(1.3, 4.0)) * 0.3) - 0.05;
		top = max(top, s_stone);
	}
	float s_sand = -1.0;
	if (weights.g + 0.7 > top - band) {
		s_sand = weights.g + fbm2(xz * 1.6 + vec2(7.1, 2.0)) * 0.5 + vnoise2(xz * 7.0) * 0.3 - 0.1;
		top = max(top, s_sand);
	}
	float s_moss = -1.0;
	if (weights.b + 0.75 > top - band) {
		s_moss = weights.b + fbm2(xz * 2.8 + vec2(3.9, 8.0)) * 0.8 - 0.05;
		top = max(top, s_moss);
	}
	float s_dirt = -1.0;
	if (weights.a + 0.72 > top - band) {
		s_dirt = weights.a + fbm2(xz * 2.0 + vec2(5.5, 6.0)) * 0.8 - 0.08;
		top = max(top, s_dirt);
	}
	// loose stones bid with their domes too: a full patch shows gravelly soil
	// between the stones, its edge thins out to single stones in the grass
	float s_rocks = -1.0;
	if (w_rocks + ls.x * 0.7 + 0.03 > top - band) {
		s_rocks = w_rocks + ls.x * 0.7 + fbm2(xz * 2.5 + vec2(2.7, 3.1)) * 0.15 - 0.12;
		top = max(top, s_rocks);
	}
	float b_grass = max(s_grass - top + band, 0.0);
	float b_stone = max(s_stone - top + band, 0.0);
	float b_sand = max(s_sand - top + band, 0.0);
	float b_moss = max(s_moss - top + band, 0.0);
	float b_dirt = max(s_dirt - top + band, 0.0);
	float b_rocks = max(s_rocks - top + band, 0.0);
	float total = b_grass + b_stone + b_sand + b_moss + b_dirt + b_rocks;

	// and only the materials that show are coloured
	float fine = vnoise2(xz * 9.0);
	// noise more than one material reads, each worked out once
	vec3 moss = vec3(0.0);
	if (b_stone > 0.0 || b_moss > 0.0 || b_rocks > 0.0) {
		moss = moss_tint(wpos);
	}
	float n4 = 0.0;
	if (b_stone > 0.0 || b_dirt > 0.0) {
		n4 = fbm2(xz * 4.0);
	}
	vec3 col = vec3(0.0);
	if (b_grass > 0.0) {
		vec3 c_grass = grass_tint(xz) * (0.62 + 0.12 * fine);
		col += c_grass * b_grass;
	}
	if (b_stone > 0.0) {
		vec3 c_stone = mix(srgb(vec3(0.58, 0.56, 0.52)), srgb(vec3(0.66, 0.6, 0.5)), cb.y) * (0.75 + 0.35 * n4);
		// joints between cobbles fill with moss and soil
		vec3 joint = mix(moss * 0.6, srgb(vec3(0.3, 0.24, 0.18)), fine);
		c_stone = mix(joint, c_stone, smoothstep(0.03, 0.09, cb.x));
		col += c_stone * b_stone;
	}
	if (b_sand > 0.0) {
		vec3 c_sand = srgb(vec3(0.80, 0.70, 0.52)) * (0.82 + 0.2 * fbm2(xz * 3.0)) * (0.93 + 0.1 * vnoise2(xz * 30.0));
		col += c_sand * b_sand;
	}
	if (b_moss > 0.0) {
		vec3 c_moss = moss * (0.8 + 0.2 * fine);
		col += c_moss * b_moss;
	}
	if (b_dirt > 0.0) {
		vec3 c_dirt = srgb(vec3(0.46, 0.34, 0.23)) * (0.8 + 0.3 * n4);
		col += c_dirt * b_dirt;
	}
	if (b_rocks > 0.0) {
		// stone: each its own grey or brown, grainy, some with hairline cracks,
		// darker at the foot where it sinks into the soil, moss on the bigger tops
		vec3 rock = mix(srgb(vec3(0.5, 0.49, 0.47)), srgb(vec3(0.58, 0.52, 0.43)), ls.y);
		rock *= 0.68 + 0.45 * fbm2(face * 16.0 + ls.y * 40.0);
		vec3 crack = cobbles(face / 0.12 + ls.y * 20.0);
		rock *= mix(1.0, mix(0.7, 1.0, smoothstep(0.0, 0.04, crack.x)), step(0.6, crack.y) * step(0.5, ls.y));
		rock *= mix(0.5, 1.0, smoothstep(0.0, 0.5, ls.x));
		rock = mix(rock, moss * 0.85, smoothstep(0.55, 0.95, ls.x) * moss_field(wpos + vec3(ls.y * 9.0)) * 0.7);
		vec3 soil = srgb(vec3(0.36, 0.28, 0.2)) * (0.75 + 0.3 * fbm2(face * 5.0));
		vec3 c_rocks = mix(soil, rock, smoothstep(0.0, 0.1, ls.x));
		col += c_rocks * b_rocks;
	}
	col /= total;
	float stone_amt = b_stone / total;
	float loose_amt = b_rocks / total;

	// Under water the bed is soft soil; just above it the bank is dark and
	// damp.
	float above = wpos.y - wet.x;
	float has_water = step(0.001, wet.y);
	float under = has_water * smoothstep(0.02, -0.04, above);
	float damp = has_water * (1.0 - smoothstep(0.0, 0.22, above + (fine - 0.5) * 0.06));
	if (under > 0.0) {
		vec3 bed = srgb(vec3(0.36, 0.27, 0.19)) * (0.7 + 0.35 * fbm2(xz * 3.5));
		col = mix(col, bed, under);
	}
	col *= mix(1.0, 0.62, damp * (1.0 - under));
	stone_amt = mix(stone_amt, 0.0, under);
	loose_amt = mix(loose_amt, 0.0, under);

	// the rolled rim catches a little less sky
	col *= mix(0.85, 1.0, smoothstep(0.0, 0.6, coast));

	// fine surface relief from the same noise, bent into the normal
	float e = 0.02;
	// (the three heights in a loop: one copy of the bump for the browser)
	float h0 = 0.0;
	float hu = 0.0;
	float hv = 0.0;
	for (int k = 0; k < LOOPS(3); k++) {
		vec2 o = k == 1 ? vec2(e, 0.0) : (k == 2 ? vec2(0.0, e) : vec2(0.0));
		float h = surface_bump(face + o, stone_amt, loose_amt);
		if (k == 0) {
			h0 = h;
		} else if (k == 1) {
			hu = h;
		} else {
			hv = h;
		}
	}
	vec3 slope = face_u * (hu - h0) / e + face_v * (hv - h0) / e;
	vec3 wn = gn;
	wn = normalize(wn - (slope - wn * dot(slope, wn)));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);

	// under water stays as it is; above, snow settles and rain darkens
	float dry = 1.0 - under;
	float snow = snow_on(wn.y, wpos);
	ALBEDO = mix(col, weathered(col, snow, wpos), dry);
	ROUGHNESS = mix(mix(mix(0.95, 0.8, stone_amt), 0.98, loose_amt), 0.45, damp * (1.0 - under));
	ROUGHNESS = mix(ROUGHNESS, weathered_rough(ROUGHNESS, snow), dry);
	SPECULAR = mix(mix(0.3, 0.12, loose_amt), weathered_spec(mix(0.3, 0.12, loose_amt), snow), dry);
}
