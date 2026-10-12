shader_type spatial;
render_mode cull_back;

// Stones, generated (rock_builder.gd), painted like hand-made stylized
// rocks: flat cut faces, each in its own tone of grey, lighter on top, the
// ridges where two faces meet worn pale (how sharply the stone turns comes
// per vertex from the builder), the hollows dark, a fine crack here and
// there. Moss lies over the tops and in the hollows but not on the ridges.
//
// Per stone: its colour, how much moss (and how damp it lies: by water or in
// a tree's shade there is more), and how much fine texture.

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
varying vec4 vcol;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vcol = COLOR;
	// object space at a metre's scale, so the cracks keep their size on any stone
	opos = VERTEX * length(MODEL_MATRIX[0].xyz);
}

// The nearest cell in a 3D Voronoi pattern: distance to its edge (x) and
// two ids for it (y, z), for faint plates within a face.
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

void fragment() {
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float amount = 0.25 + 0.75 * texture_amount;
	// the ridges where two faces meet are worn pale, as on hand-painted
	// rocks: how far this spot lies from its face's rim comes from the
	// builder (UV: share of the way from the rim to the middle, and that
	// distance), the line a little ragged, as if chipped
	float scale = length(MODEL_MATRIX[0].xyz);
	float to_rim = UV.x * UV.y * scale;
	float width = scale * (0.004 + 0.011 * vnoise3(opos * 7.0) + 0.006 * vnoise3(opos * 23.0)) * (0.6 + 0.5 * texture_amount);
	float ridge = use_tex ? 0.0 : (1.0 - smoothstep(width * 0.4, width, to_rim)) * mix(0.35, 1.0, smoothstep(0.3, 0.55, vnoise3(opos * 3.5)));
	float hollow = 0.0;
	float halo = use_tex ? 0.0 : 1.0 - smoothstep(0.0, width * 5.0, to_rim);
	// each cut face its own tone, faint plates within it
	vec3 plate = cells(opos * vec3(1.6, 2.2, 1.6));
	vec3 base = srgb(stone) * 0.72;
	vec3 col = base * mix(0.82, 1.12, vcol.g) * (0.95 + 0.08 * (plate.y - 0.5) * amount);
	// soft mottling, cooler and warmer
	float mott = fbm3(opos * 2.2);
	col *= mix(vec3(0.92, 0.95, 1.02), vec3(1.05, 1.02, 0.98), mott) * (0.86 + 0.26 * mott);
	// cracks: a broken net of splits along the edges of stone cells, here
	// and there, each a dark line with a pale chipped lip, and finer
	// hairlines between
	vec3 cr = cells(opos * vec3(2.4, 3.2, 2.4) + 5.0);
	float show = smoothstep(0.36, 0.5, vnoise3(opos * 1.7 + 3.0)) * amount;
	float split = (1.0 - smoothstep(0.01, 0.024, cr.x)) * show;
	float lip = max((1.0 - smoothstep(0.024, 0.06, cr.x)) * show - split, 0.0);
	float hair = abs(vnoise3(opos * 5.0 + 2.0) - 0.5);
	float fine = (1.0 - smoothstep(0.004, 0.014, hair)) * step(0.58, vnoise3(opos * 2.0 + 8.0)) * amount;
	// and a finer net in other places
	vec3 cr2 = cells(opos * vec3(6.0, 7.5, 6.0) + 17.0);
	float show2 = smoothstep(0.5, 0.62, vnoise3(opos * 2.6 + 11.0)) * amount;
	split = max(split, (1.0 - smoothstep(0.012, 0.03, cr2.x)) * show2 * 0.8);
	col *= 1.0 - split * 0.65 - fine * 0.3;
	col *= 1.0 + lip * 0.2;
	// pits and chips: small dark dents scattered over the faces
	float pit = smoothstep(0.78, 0.86, vnoise3(opos * 14.0)) * amount;
	col *= 1.0 - pit * 0.25;
	// lighter on top, as painted, and the light ridges
	col *= 0.86 + 0.22 * smoothstep(-0.3, 0.9, wn.y);
	// the worn ridge, brightest along the tops, a soft rounding into the face
	col *= 1.0 + halo * halo * 0.14;
	col = mix(col, col * 1.5 + vec3(0.05), ridge * (0.3 + 0.25 * amount) * (0.55 + 0.45 * smoothstep(-0.4, 0.8, wn.y)));
	col *= 1.0 - hollow * 0.35;
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

	// moss: in broad drifts over the tops, in the hollows and the seams, more
	// the damper the stone lies; never on the worn ridges
	float wet_moss = clamp(moss_amount + moss_boost * 0.45, 0.0, 1.2);
	float field = moss_field(wpos);
	float drift = fbm3(wpos * 1.6 + 4.0) * 0.8 + field * 0.3;
	float on_top = smoothstep(0.9 - wet_moss * 0.45, 1.06 - wet_moss * 0.35, wn.y * 0.55 + drift * 0.6 + (fbm3(wpos * 4.0) - 0.5) * 0.35);
	float in_hollows = hollow * smoothstep(0.4, 1.0, wet_moss) * 0.5;
	float moss = clamp(on_top + in_hollows + seam * (0.3 + wet_moss * 0.6), 0.0, 1.0) * step(0.01, wet_moss + seam);
	moss *= 1.0 - ridge * 0.9;
	// a speckled edge, as painted
	moss = smoothstep(0.3, 0.6, moss + (vnoise3(wpos * 6.0) - 0.5) * 0.15 + (vnoise3(wpos * 26.0) - 0.5) * 0.3);
	col = mix(col, moss_tint(wpos) * (0.5 + 0.55 * fbm3(wpos * 3.0)), moss * 0.92);
	// soil and shade down in the seam
	col = mix(col, srgb(vec3(0.3, 0.24, 0.17)), seam * seam * 0.45);
	col *= 1.0 - seam * 0.35;

	float foot = smoothstep(0.12, -0.02, wpos.y - ground_y + (fbm3(wpos * 4.0) - 0.5) * 0.1);
	col = mix(col, mix(grass_tint(wpos.xz) * 0.55, srgb(vec3(0.36, 0.27, 0.19)), 0.4), foot);

	ALBEDO = weathered(col, wn.y, wpos);
	ROUGHNESS = weathered_rough(mix(0.95, 0.85, moss), wn.y, wpos);
	SPECULAR = weathered_spec(0.14, wn.y, wpos);
}
