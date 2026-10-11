shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, alpha_to_coverage;

// Leaves, needles, ferns, flowers and grass tufts from the Quaternius kit.
// Keeps the kit's painted texture, adds wind that grows toward the top, a
// little light through the leaves, and a per-plant tint so a stand of the
// same model does not look stamped.

#include "res://shaders/noise.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform float sway = 1.0;          // how much this kind of plant moves
uniform float backlight = 0.5;
// some kit textures come in autumn colours; this can turn them green
uniform vec4 recolor = vec4(1.0, 1.0, 1.0, 0.0);
// tall grass takes the lawn's own colour, so it reads as the same grass grown long
uniform bool lawn_colour = false;

instance uniform vec3 tint = vec3(1.0);
instance uniform float height = 1.0;    // model height, in its own units
instance uniform float ground_y = 0.0;

varying float up;
varying vec3 wpos;
varying float wup;

void vertex() {
	up = clamp(VERTEX.y / max(height, 0.01), 0.0, 1.0);
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float gust = vnoise2(w.xz * 0.15 + vec2(TIME * 0.3, TIME * 0.2));
	vec2 push = vec2(sin(TIME * 1.3 + w.x * 0.4 + w.z * 0.3) * 0.5 + gust - 0.5, cos(TIME * 1.1 + w.z * 0.4) * 0.4);
	float flutter = sin(TIME * 5.0 + w.x * 7.0 + w.y * 5.0) * 0.15;
	VERTEX.xz += (push + flutter) * up * up * sway * 0.05 * height * wind_sway();
	wup = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz).y;
	wpos = w;
}

void fragment() {
	vec4 t = texture(albedo_tex, UV);
	vec3 base = mix(t.rgb, vec3(dot(t.rgb, vec3(0.3, 0.55, 0.15))) * recolor.rgb * 2.2, recolor.a);
	if (lawn_colour) {
		vec3 lawn = grass_tint(wpos.xz);
		base = mix(lawn * 0.55, lawn * 1.3 + srgb(vec3(0.07, 0.07, 0.0)), smoothstep(0.0, 1.0, up)) / mix(0.7, 1.05, up);
	}
	ALBEDO = weathered(base * tint * mix(0.7, 1.05, up), max(abs(wup), up), wpos);
	t.rgb = base;
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.4;
	ALPHA_ANTIALIASING_EDGE = 0.3;
	ROUGHNESS = weathered_rough(0.8, 0.0, wpos);
	SPECULAR = weathered_spec(0.25, 0.0, wpos);
	BACKLIGHT = t.rgb * backlight;
}
