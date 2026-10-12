// Shared world-space noise. Ground, grass, cliffs, rocks and bark all call
// these same functions, so a moss patch or a dry spot carries on across the
// seam from one object to the next. That is most of what makes the pieces
// look grown together instead of placed.

vec3 srgb(vec3 c) {
	return pow(c, vec3(2.2));
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
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

float fbm2(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise2(p);
		p = p * 2.03 + vec2(17.1, 9.3);
		a *= 0.5;
	}
	return s / 0.9375;
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

// Grass colour for a spot on the island. The ground under the blades and the
// blades themselves both read it, so they always agree.
vec3 grass_tint(vec2 xz) {
	float broad = fbm2(xz * 0.16);
	float dry = fbm2(xz * 0.7 + vec2(3.7, 1.1));
	vec3 lush = vec3(0.30, 0.52, 0.14);
	vec3 fresh = vec3(0.50, 0.68, 0.20);
	vec3 straw = vec3(0.74, 0.70, 0.34);
	vec3 c = mix(lush, fresh, smoothstep(0.35, 0.68, broad));
	c = mix(c, straw, smoothstep(0.58, 0.8, dry) * 0.55);
	return srgb(c);
}

// Where moss wants to grow, 0..1, the same answer on every surface.
float moss_field(vec3 wp) {
	return smoothstep(0.4, 0.66, fbm3(wp * 0.55));
}

vec3 moss_tint(vec3 wp) {
	float n = fbm3(wp * 1.7);
	return srgb(mix(vec3(0.30, 0.44, 0.12), vec3(0.46, 0.55, 0.16), n));
}

// Cobblestones from a jittered cell grid. Returns (gap, stone random,
// dome): gap is the distance to the nearest joint, dome a 0..1 height that
// rounds each stone.
vec3 cobbles(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float f1 = 8.0;
	float f2 = 8.0;
	vec2 id = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(hash12(i + g), hash12(i + g + vec2(17.3, 5.1))) * 0.8 + 0.1;
			vec2 r = g + o - f;
			float d = dot(r, r);
			if (d < f1) {
				f2 = f1;
				f1 = d;
				id = i + g;
			} else if (d < f2) {
				f2 = d;
			}
		}
	}
	float gap = sqrt(f2) - sqrt(f1);
	return vec3(gap, hash12(id + vec2(3.1, 7.7)), smoothstep(0.0, 0.35, gap));
}

// One web of caustic lines: the joints of a cell pattern whose points
// drift in small circles, so the web slowly breathes.
float caustic_web(vec2 p, float t) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float f1 = 8.0;
	float f2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			float h = hash12(i + g);
			vec2 o = 0.5 + 0.38 * vec2(sin(t * 0.9 + 6.283 * h), cos(t * 0.7 + 6.283 * hash12(i + g + vec2(7.0, 3.0))));
			float d = length(g + o - f);
			if (d < f1) {
				f2 = f1;
				f1 = d;
			} else if (d < f2) {
				f2 = d;
			}
		}
	}
	return 1.0 - smoothstep(0.0, 0.14, f2 - f1);
}

// Light focused by ripples onto a shallow bed: two webs, warped so the
// lines wobble, the bright where they cross.
float caustics(vec2 p, float t) {
	vec2 warp = vec2(vnoise2(p * 0.6 + vec2(t * 0.15, 0.0)), vnoise2(p * 0.6 + vec2(5.2, -t * 0.12))) - 0.5;
	vec2 q = p + warp * 0.9;
	float a = caustic_web(q, t);
	float b = caustic_web(q * 1.37 + vec2(3.1, 1.7), t * 1.21);
	return a * a * 0.7 + b * b * 0.45 + a * b * 0.8;
}

// Loose stones lying about. One possible stone per cell: each has its own
// size or is missing altogether, is turned and squashed so no two match,
// and has a wobbled outline so none is a disc. Returns (dome 0..1, stone
// random). Technique after Terragen's "fake stones" and layered Voronoi.
vec2 stone_layer(vec2 p, float fill) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float best = 0.0;
	float id = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 c = i + g;
			if (hash12(c + vec2(1.7, 9.2)) > fill) {
				continue;
			}
			float r = mix(0.22, 0.55, hash12(c + vec2(4.1, 2.3)));
			vec2 o = 0.5 + (vec2(hash12(c), hash12(c + vec2(8.3, 1.9))) - 0.5) * (1.0 - r);
			vec2 d = g + o - f;
			float a = hash12(c + vec2(2.2, 6.6)) * 6.283;
			d = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * d;
			d.x *= mix(0.75, 1.35, hash12(c + vec2(5.5, 3.3)));
			float dist = length(d) / r + (vnoise2(d * 6.0 + c * 3.1) - 0.5) * 0.3;
			float dome = sqrt(max(0.0, 1.0 - dist * dist));
			if (dome > best) {
				best = dome;
				id = hash12(c + vec2(0.7, 0.3));
			}
		}
	}
	return vec2(best, id);
}

// Big stones and small ones, gathering thicker in some patches than others.
vec2 loose_stones(vec2 xz) {
	float clump = vnoise2(xz * 0.35);
	vec2 big = stone_layer(xz / 0.6, mix(0.25, 0.7, clump));
	vec2 small = stone_layer(xz / 0.22 + vec2(13.1, 7.7), mix(0.35, 0.8, clump));
	small.x *= 0.7;
	return big.x >= small.x ? big : small;
}

// Weather, set by the weather script for every surface at once.
global uniform float snow_cover;
global uniform float wetness;
global uniform float wind_strength;
global uniform float rain_amount;

// Rain rings on water: in each cell a drop lands at its own moment, and a
// ring spreads out from it and fades. Returns (height for the normal,
// brightness of the ring crest).
vec2 rain_rings(vec2 p, float t) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float h = 0.0;
	float crest = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 c = i + g;
			vec2 o = vec2(hash12(c), hash12(c + vec2(4.7, 1.3)));
			float life = fract(t * (0.9 + 0.5 * hash12(c + 9.1)) + hash12(c + 2.3));
			float d = length(g + o - f);
			float r = life * 0.75;
			float ring = exp(-pow((d - r) * 18.0, 2.0)) * (1.0 - life) * (1.0 - life);
			h += sin((d - r) * 40.0) * ring;
			crest = max(crest, ring);
		}
	}
	return vec2(h, crest);
}

// How much snow lies on a surface facing `up` (world normal y) at wp:
// it settles on what faces the sky, thickest on flat tops, in drifts.
float snow_on(float up, vec3 wp) {
	if (snow_cover <= 0.001) {
		return 0.0;
	}
	float drift = fbm3(wp * 1.3) - 0.5;
	return smoothstep(0.55, 0.85, up + drift * 0.5 - (1.0 - snow_cover) * 0.6) * smoothstep(0.0, 0.25, snow_cover);
}

// A surface's colour under the weather: snow on top, darker when wet.
vec3 weathered(vec3 col, float up, vec3 wp) {
	float s = snow_on(up, wp);
	vec3 snow = vec3(0.93, 0.95, 0.98) * (0.9 + 0.1 * vnoise3(wp * 9.0));
	col *= mix(1.0, 0.62, wetness * (1.0 - s));
	return mix(col, snow, s);
}

// Roughness under the weather: wet surfaces shine, snow is matte.
float weathered_rough(float r, float up, vec3 wp) {
	float s = snow_on(up, wp);
	r = mix(r, 0.16, wetness * 0.9 * (1.0 - s));
	return mix(r, 0.9, s);
}

// Specular under the weather: wet surfaces reflect the sky like a film of
// water.
float weathered_spec(float sp, float up, vec3 wp) {
	return mix(sp, 0.65, wetness * (1.0 - snow_on(up, wp)));
}

// Wind as a multiplier for anything that sways.
float wind_sway() {
	return 0.4 + wind_strength * 1.8;
}

// The nearest cell in a 3D Voronoi pattern: distance to its edge (x) and
// two ids for it (y, z).
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

// Moss, the same on stones, roots and trees. moss_cover: where it lies for
// `amount` (a Mossa dial, 0..1), in broad drifts over whatever faces up,
// plus `extra` (hollows, seams, a tree's foot).
float moss_cover(vec3 wp, vec3 wn, float amount, float extra) {
	float field = moss_field(wp);
	float drift = fbm3(wp * 1.6 + 4.0) * 0.8 + field * 0.3;
	float on_top = smoothstep(0.9 - amount * 0.45, 1.06 - amount * 0.35, wn.y * 0.55 + drift * 0.6 + (fbm3(wp * 4.0) - 0.5) * 0.35);
	return clamp(on_top + extra, 0.0, 1.0) * step(0.01, amount + extra);
}

// moss_fuzz: the moss itself, laid over col where `cover` says. It is a
// fuzz of shoots packed tight, each claiming the ground round it from its
// neighbours (Voronoi cells, domed at their tips), in three sizes that each
// fade in only once bigger than a pixel, so there is grain at any distance
// and none of it shimmers; under it soft swells. `op` is a position that
// stays put on the thing (object space in metres). Returns (how much moss,
// after its edge frays, and its height for bumping the normal).
vec2 moss_fuzz(vec3 wp, vec3 op, float cover, inout vec3 col) {
	if (cover <= 0.0) {
		return vec2(0.0);
	}
	float dome = smoothstep(0.25, 0.75, fbm3(op * 4.0 + 31.0));
	float tip = 0.0;
	float seen = 0.0;
	for (int k = 0; k < 3; k++) {
		float freq = 48.0 * pow(2.2, float(k));
		vec3 sh = cells(op * freq + 13.0 * float(k + 1));
		float vis = 1.0 - smoothstep(0.3, 0.9, length(fwidth(op * freq)));
		tip += (smoothstep(0.0, 0.65, sh.x) - 0.5) * vis * (0.7 + 0.15 * float(k));
		seen += vis * (0.7 + 0.15 * float(k));
	}
	tip = tip / max(seen, 1.0);
	float moss = smoothstep(0.3, 0.6, cover + (dome - 0.5) * 0.2 + (vnoise3(wp * 6.0) - 0.5) * 0.12 + tip * 0.3);
	// darker down between the shoots, the tips catching the light a little
	// yellower, drifts of greener and yellower moss
	vec3 moss_col = moss_tint(wp) * (0.5 + 0.55 * fbm3(wp * 3.0));
	moss_col *= mix(vec3(0.94, 0.98, 1.04), vec3(1.06, 1.03, 0.92), fbm3(op * 2.0 + 5.0));
	moss_col *= mix(0.82, 1.06, dome) * (1.0 + tip * 0.55);
	moss_col += srgb(vec3(0.75, 0.8, 0.3)) * max(tip, 0.0) * 0.12;
	col = mix(col, moss_col, moss * 0.95);
	return vec2(moss, dome * 0.6 + tip * 0.8);
}
