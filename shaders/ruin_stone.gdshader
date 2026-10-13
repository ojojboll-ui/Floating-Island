shader_type spatial;
render_mode cull_back;

// Ruin stones. Vertex colour is each stone's own tint (alpha 0 marks the
// mortar core, a shade darker in the joints). Grain and pits from world
// noise, and moss that spreads over the tops and down the faces as the ruin
// ages, from the same moss field as the ground, rocks and bark.

#include "res://shaders/noise.gdshaderinc"

uniform float age = 0.4;

varying vec3 wpos;
varying vec4 tint;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	tint = COLOR;
}

float relief(vec3 p) {
	return fbm3(p * 3.5) * 0.6 + vnoise3(p * 11.0) * 0.4;
}

void fragment() {
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float e = 0.015;
	float h0 = relief(wpos);
	vec3 g = vec3(relief(wpos + vec3(e, 0.0, 0.0)), relief(wpos + vec3(0.0, e, 0.0)), relief(wpos + vec3(0.0, 0.0, e))) - h0;
	vec3 bn = normalize(wn - (g / e - wn * dot(g / e, wn)) * 0.04);

	vec3 col;
	if (tint.a < 0.5) {
		// mortar: lime and earth, a shade darker than the stones so the joints
		// read, with a fine gritty grain, greening a little with age
		col = srgb(vec3(0.38, 0.35, 0.30)) * (0.85 + 0.3 * vnoise3(wpos * 14.0));
		col *= 0.86 + 0.28 * hash13(floor(wpos * 180.0)) * 0.5 + 0.14 * vnoise3(wpos * 60.0);
		col = mix(col, moss_tint(wpos) * 0.7, age * 0.4);
	} else {
		col = srgb(tint.rgb) * (0.78 + 0.32 * h0);
		// weathering darkens the pits and the lower courses
		col *= mix(0.85, 1.0, smoothstep(0.3, 0.6, h0));
		float on_top = smoothstep(0.35, 0.85, bn.y + (moss_field(wpos) - 0.5) * 0.8);
		float creep = smoothstep(0.55, 0.8, moss_field(wpos * 1.3) + age * 0.35) * smoothstep(-0.2, 0.4, bn.y);
		float moss = clamp((on_top * (0.25 + age) + creep * age) * smoothstep(0.0, 0.3, age + 0.1), 0.0, 1.0);
		col = mix(col, moss_tint(wpos) * 0.85, moss);
	}
	NORMAL = normalize((VIEW_MATRIX * vec4(bn, 0.0)).xyz);
	ALBEDO = weathered(col, bn.y, wpos);
	ROUGHNESS = weathered_rough(0.95, bn.y, wpos);
	SPECULAR = weathered_spec(0.15, bn.y, wpos);
}
