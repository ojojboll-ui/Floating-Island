shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap;

// Reeds and cattails. Vertex colour carries the colour (green blades, brown
// heads); uv.y runs up each stem, so the tips sway and the roots stay put.

#include "res://shaders/noise.gdshaderinc"

instance uniform vec3 tint = vec3(1.0);
instance uniform float height = 1.0;
instance uniform float ground_y = 0.0;

varying float along;
varying vec3 wpos;

void vertex() {
	along = UV.y;
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float gust = vnoise2(w.xz * 0.2 + vec2(TIME * 0.35, TIME * 0.25));
	float s = sin(TIME * 1.4 + w.x * 0.9 + w.z * 0.7) * 0.4 + gust - 0.45;
	VERTEX.xz += vec2(1.0, 0.5) * s * along * along * 0.12 * wind_sway();
	wpos = w;
}

void fragment() {
	vec3 c = COLOR.rgb * tint;
	// darker and wetter toward the water
	c *= mix(0.55, 1.1, smoothstep(0.0, 0.7, along));
	ALBEDO = c;
	ROUGHNESS = weathered_rough(0.75, 0.0, wpos);
	SPECULAR = weathered_spec(0.25, 0.0, wpos);
	BACKLIGHT = c * 0.4 * along;
}
