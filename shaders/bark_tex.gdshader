shader_type spatial;
render_mode cull_disabled;

// Textured bark from the Quaternius kit, with the same moss as everything
// else: creeping up from the ground and gathering on the upper side of
// branches.

#include "res://shaders/noise.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform bool has_normal = false;

instance uniform vec3 tint = vec3(1.0);
instance uniform float height = 1.0;
instance uniform float ground_y = 0.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 t = texture(albedo_tex, UV);
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 col = t.rgb * mix(vec3(1.0), tint, 0.4);
	// moss only on branch tops that truly face the sky, not up the trunk
	float up_moss = smoothstep(0.6, 0.95, wn.y + (moss_field(wpos) - 0.5) * 0.5);
	// moss only around the very foot, broken unevenly
	float foot = smoothstep(0.28, 0.0, wpos.y - ground_y + (fbm3(wpos * 4.0) - 0.5) * 0.18);
	col = mix(col, moss_tint(wpos) * 0.8, clamp(up_moss * 0.6 + foot * 0.8, 0.0, 1.0));
	ALBEDO = weathered(col, wn.y, wpos);
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.3;
	if (has_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}
	ROUGHNESS = weathered_rough(0.92, wn.y, wpos);
	SPECULAR = weathered_spec(0.2, wn.y, wpos);
}
