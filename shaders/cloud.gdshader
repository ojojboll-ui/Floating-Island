shader_type spatial;
render_mode cull_back, diffuse_lambert_wrap, specular_disabled, shadows_disabled;

// Cotton-ball clouds: each puff is a sphere pushed in and out by noise so it
// reads as cauliflower rather than a ball, lit with soft wrap lighting, a
// shaded underside and a faint glow of their own. The weather script tints
// them for the hour (peach at dusk, silver-blue at night) and greys them
// for rain.

#include "res://shaders/noise.gdshaderinc"

uniform vec3 lit_color : source_color = vec3(0.95, 0.95, 0.96);
uniform vec3 shade_color : source_color = vec3(0.70, 0.76, 0.88);
uniform vec3 glow : source_color = vec3(0.05, 0.055, 0.07);

varying vec3 wnormal;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX += NORMAL * (fbm3(wp * 0.9 + vec3(0.0, TIME * 0.03, 0.0)) - 0.5) * 0.7;
	wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float under = smoothstep(0.2, -0.8, wnormal.y);
	ALBEDO = mix(lit_color, shade_color, under);
	ROUGHNESS = 1.0;
	BACKLIGHT = vec3(0.25);
	EMISSION = glow * mix(1.0, 0.6, under);
}
