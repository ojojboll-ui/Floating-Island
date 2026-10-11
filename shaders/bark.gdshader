shader_type spatial;
render_mode cull_back;

// Bark with vertical grain. Moss creeps up from the ground and gathers on
// the upper side of branches, using the same moss field as the ground.

#include "res://shaders/noise.gdshaderinc"

instance uniform float ground_y = 0.0;
instance uniform vec3 tint = vec3(1.0);
instance uniform float height = 1.0;
instance uniform vec3 bark = vec3(0.40, 0.29, 0.21);
instance uniform float moss_more = 0.0;

uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform bool has_normal = false;

varying vec3 wpos;

void fragment() {
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float grain = vnoise3(wpos * vec3(9.0, 1.4, 9.0));
	float knots = fbm3(wpos * 2.5);
	vec3 col = srgb(bark) * (0.65 + 0.45 * grain) * (0.85 + 0.3 * knots);
	// moss only on branch tops that truly face the sky, not up the trunk
	float up_moss = smoothstep(0.6 - moss_more * 0.7, 0.95 - moss_more * 0.5, wn.y + (moss_field(wpos) - 0.5) * 0.5);
	// moss only around the very foot, broken unevenly
	float foot = smoothstep(0.28, 0.0, wpos.y - ground_y + (fbm3(wpos * 4.0) - 0.5) * 0.18);
	col = mix(col, moss_tint(wpos) * 0.8, clamp(up_moss * 0.7 + foot * 0.85, 0.0, 1.0));
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
