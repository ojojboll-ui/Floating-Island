shader_type spatial;
render_mode cull_disabled, unshaded, depth_draw_never, shadows_disabled;

// Spray over a waterfall's lip: a soft white haze, thickest right at the
// edge and fading both up the water and down the fall, torn into wisps that
// stream outward with the water. uv.y runs across the band (0 out on the
// water, 1 down the fall); uv.x is 1 at the open ends of a fall.

#include "res://shaders/noise.gdshaderinc"

uniform vec3 tint : source_color = vec3(0.93, 0.97, 0.98);

varying vec3 wpos;
varying vec2 band;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	band = UV;
}

void fragment() {
	// peak a little before the edge row (0.5), soft on both sides
	float across = smoothstep(0.0, 0.45, band.y) * (1.0 - smoothstep(0.55, 1.0, band.y));
	float wisps = fbm3(vec3(wpos.x * 3.0, wpos.y * 2.0 + TIME * 1.6, wpos.z * 3.0));
	float fine = vnoise3(wpos * 9.0 + vec3(0.0, TIME * 2.5, 0.0));
	float haze = across * smoothstep(0.15, 0.65, wisps * 0.8 + fine * 0.35);
	haze *= 1.0 - band.x * 0.7;
	ALBEDO = tint;
	ALPHA = clamp(haze * 0.95, 0.0, 1.0);
}
