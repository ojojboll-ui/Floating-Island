shader_type spatial;
render_mode cull_disabled;

// Koi. The body swishes side to side more toward the tail; the speed of the
// swish follows how fast the fish swims. Patches of orange, white and a
// little black come from noise in the fish's own coordinates.

#include "res://shaders/noise.gdshaderinc"

instance uniform float seed = 0.0;
instance uniform float swim = 1.0;

varying vec3 local;

void vertex() {
	local = VERTEX;
	// +z is the nose; the tail is at negative z
	float tail = clamp(-VERTEX.z / 0.14, 0.0, 1.0);
	VERTEX.x += sin(TIME * (6.0 + swim * 6.0) + seed * 10.0 - VERTEX.z * 18.0) * 0.025 * tail * tail * (0.4 + swim);
}

void fragment() {
	float n = vnoise2(local.xz * 22.0 + seed * 13.0);
	float m = vnoise2(local.xz * 35.0 + seed * 7.0 + 3.0);
	vec3 orange = srgb(vec3(0.95, 0.42, 0.12));
	vec3 white = srgb(vec3(0.95, 0.93, 0.88));
	vec3 black = srgb(vec3(0.08, 0.07, 0.07));
	vec3 c = mix(white, orange, step(0.28 + 0.2 * fract(seed * 3.7), n));
	c = mix(c, black, step(0.82, m) * step(0.5, fract(seed * 5.3)));
	ALBEDO = c;
	ROUGHNESS = 0.35;
	SPECULAR = 0.5;
}
