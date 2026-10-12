shader_type spatial;
render_mode cull_back;

// Bark with vertical grain. Moss, the same as on the stones, gathers on the
// upper side of branches and round the foot, as much as the Mossa dial says.

#include "res://shaders/noise.gdshaderinc"

instance uniform float ground_y = 0.0;
instance uniform vec3 tint = vec3(1.0);
instance uniform float height = 1.0;
instance uniform vec3 bark = vec3(0.40, 0.29, 0.21);
// the Mossa dial: moss as on the stones, on what faces the sky and round
// the very foot
instance uniform float moss_amount = 0.2;

uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform bool has_normal = false;

varying vec3 wpos;

void fragment() {
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float grain = vnoise3(wpos * vec3(9.0, 1.4, 9.0));
	float knots = fbm3(wpos * 2.5);
	vec3 col = srgb(bark) * (0.65 + 0.45 * grain) * (0.85 + 0.3 * knots);
	// moss as on the stones (the Mossa dial): on branch tops that face the
	// sky, not up the trunk, and round the very foot
	float foot = smoothstep(0.09, 0.0, wpos.y - ground_y + (fbm3(wpos * 4.0) - 0.5) * 0.06);
	moss_fuzz(wpos, wpos, moss_cover(wpos, wn, moss_amount, foot * moss_amount * 1.5), col);
	ALBEDO = weathered(col, wn.y, wpos);
	if (has_normal) {
		// the Quaternius bark normal (CC0): twice round the trunk, stretched along it
		NORMAL_MAP = texture(normal_tex, UV * vec2(2.0, 0.6)).rgb;
		NORMAL_MAP_DEPTH = 1.4;
	}
	ROUGHNESS = weathered_rough(0.9, wn.y, wpos);
	SPECULAR = weathered_spec(0.2, wn.y, wpos);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
