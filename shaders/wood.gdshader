shader_type spatial;
render_mode cull_back;

// Stylized wood (wood_builder.gd): bark in long plates with dark grooves
// and a fine grain along them, a lighter worn rim round each cut, cut ends
// pale with a spiral of rings, split faces with long grain. Moss gathers on
// top and in the grooves.

#include "res://shaders/noise.gdshaderinc"

instance uniform vec3 bark_color = vec3(0.42, 0.32, 0.24);
instance uniform vec3 wood_color = vec3(0.86, 0.68, 0.45);
instance uniform float moss = 0.3;

varying vec4 vcol;
varying vec3 wpos;

void vertex() {
	vcol = COLOR;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float kind = vcol.g;
	vec3 col;
	float groove = vcol.r;
	if (kind < 0.15) {
		// bark: each plate its own shade, darker into the grooves, a fine
		// grain of lines along it, its crest a touch lighter
		col = srgb(bark_color) * mix(0.82, 1.12, vcol.b);
		float grain = vnoise2(vec2(UV.x * 90.0, UV.y * 1.3 + UV.x * 3.0));
		col *= 1.0 - 0.3 * (1.0 - smoothstep(0.22, 0.4, grain));
		// a darker crack now and then along a plate
		float crack = vnoise2(vec2(UV.x * 160.0, UV.y * 0.6));
		col *= 1.0 - 0.35 * (1.0 - smoothstep(0.06, 0.12, crack));
		col *= mix(1.08, 0.38, smoothstep(0.1, 0.9, groove));
	} else if (kind < 0.4) {
		// a knot's eye: rings round a dark sunken heart, the bark a touch
		// lighter on its swell
		float r = length(UV);
		float s = fract(r * 4.5 + vnoise2(UV * 4.0) * 0.2);
		float line = 1.0 - smoothstep(0.0, 0.14, min(s, 1.0 - s));
		col = srgb(mix(bark_color, wood_color, 0.25)) * 1.1 * (1.0 - line * 0.55);
		col *= mix(0.35, 1.0, smoothstep(0.08, 0.2, r));
	} else if (kind < 0.62) {
		// the rim round a cut: bark worn pale at its edge
		col = srgb(mix(bark_color, wood_color, 0.35)) * mix(1.05, 0.8, groove);
	} else if (kind < 0.87) {
		// a split face: pale wood, long grain
		float grain = vnoise2(vec2(UV.x * 30.0, UV.y * 2.5));
		col = srgb(wood_color) * (0.92 + 0.12 * vcol.b) * (1.0 - 0.14 * (1.0 - smoothstep(0.25, 0.42, grain)));
	} else {
		// a cut end: rings in a spiral round the heart, darker toward the bark
		vec2 p = UV;
		float r = length(p);
		float a = atan(p.y, p.x) / TAU;
		float rings = 5.5;
		float s = fract(r * rings - a + vnoise2(p * 3.0) * 0.15);
		float line = 1.0 - smoothstep(0.0, 0.11, min(s, 1.0 - s));
		col = srgb(wood_color) * (1.06 - 0.16 * smoothstep(0.55, 1.0, r));
		col *= 1.0 - line * 0.28;
		// the heart, and a check or two cracking out from it
		col *= 1.0 - (1.0 - smoothstep(0.0, 0.09, r)) * 0.35;
		float check = abs(fract(a * 3.0 + 0.13) - 0.5);
		col *= 1.0 - (1.0 - smoothstep(0.0, 0.012 + r * 0.01, check)) * step(0.25, r) * step(r, 0.8) * 0.4;
	}
	// moss on top of bark and in its grooves
	if (kind < 0.15) {
		float field = moss_field(wpos);
		float up = smoothstep(0.35, 0.9, wn.y + (field - 0.5) * 0.6);
		float patches = smoothstep(0.5, 0.7, fbm3(wpos * 2.4) + moss * 0.3);
		float m = clamp(up * patches + groove * 0.4 * up, 0.0, 1.0) * clamp(moss * 1.2, 0.0, 1.0);
		col = mix(col, moss_tint(wpos) * (0.7 + 0.35 * fbm3(wpos * 8.0)), clamp(m, 0.0, 0.92));
	}
	ALBEDO = weathered(col, wn.y, wpos);
	ROUGHNESS = weathered_rough(0.85, wn.y, wpos);
	SPECULAR = weathered_spec(0.25, wn.y, wpos);
}
