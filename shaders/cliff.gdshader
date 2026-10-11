shader_type spatial;
render_mode cull_back;

// The island's body: grass hanging over the rim, a band of dark soil, then
// layered rock that turns cooler and darker toward the underside.
// uv.x is the depth below the rim in meters.

#include "res://shaders/noise.gdshaderinc"

varying vec3 wpos;
varying float rim_depth;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	rim_depth = UV.x;
}

float rock_bump(vec3 p) {
	return fbm3(p * 1.6) * 0.18 + vnoise3(p * 6.0) * 0.03;
}

void fragment() {
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);

	float thickness = 0.8 + 0.7 * fbm2(wpos.xz * 0.12 + vec2(4.0, 2.0));
	float strata = wpos.y * thickness + fbm3(wpos * vec3(0.25, 0.6, 0.25)) * 2.2;
	float layer = floor(strata);
	float pick = hash12(vec2(layer, 3.1));
	vec3 rock_a = srgb(vec3(0.62, 0.52, 0.42));
	vec3 rock_b = srgb(vec3(0.50, 0.46, 0.44));
	vec3 rock_c = srgb(vec3(0.70, 0.60, 0.47));
	vec3 rock = pick < 0.33 ? rock_a : (pick < 0.66 ? rock_b : rock_c);
	rock *= 0.78 + 0.38 * fbm3(wpos * 2.0);
	float f = fract(strata);
	rock *= mix(0.62, 1.0, smoothstep(0.0, 0.07, f) * smoothstep(1.0, 0.93, f));
	// cooler and darker as it hangs deeper
	rock = mix(rock, rock * srgb(vec3(0.72, 0.76, 0.86)), smoothstep(-2.0, -8.0, wpos.y));

	float wobble = fbm3(wpos * 3.0) - 0.5;
	vec3 soil = srgb(vec3(0.32, 0.22, 0.15)) * (0.75 + 0.35 * fbm3(wpos * 5.0));
	float soil_amt = 1.0 - smoothstep(0.28, 0.5, rim_depth + wobble * 0.25);
	vec3 col = mix(rock, soil, soil_amt);

	// grass and roots spilling over the edge
	float hang = 1.0 - smoothstep(0.03, 0.16, rim_depth + (vnoise2(wpos.xz * 9.0) - 0.5) * 0.16);
	col = mix(col, grass_tint(wpos.xz) * 0.7, hang);

	// moss settles on ledges
	float moss = smoothstep(0.25, 0.8, wn.y + (moss_field(wpos) - 0.5) * 0.9);
	col = mix(col, moss_tint(wpos) * 0.85, moss * 0.85 * (1.0 - soil_amt));

	float e = 0.03;
	float h0 = rock_bump(wpos);
	vec3 g = vec3(rock_bump(wpos + vec3(e, 0.0, 0.0)), rock_bump(wpos + vec3(0.0, e, 0.0)), rock_bump(wpos + vec3(0.0, 0.0, e))) - h0;
	g /= e;
	wn = normalize(wn - (g - wn * dot(g, wn)) * 0.8);
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);

	// the overhang underneath sees little sky
	col *= mix(0.6, 1.0, smoothstep(-0.7, 0.3, wn.y));
	ALBEDO = weathered(col * 0.88, wn.y, wpos);
	ROUGHNESS = weathered_rough(0.92, wn.y, wpos);
	SPECULAR = weathered_spec(0.25, wn.y, wpos);
}
