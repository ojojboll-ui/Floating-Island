shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_disabled, depth_draw_never, shadows_disabled;

// Falling water: streaks stretched along the fall and scrolling down it,
// foamy white where it tips over the lip, thinning to nothing below.
// uv.y runs 0 at the lip to 1 at the bottom.

#include "res://shaders/noise.gdshaderinc"

varying vec3 wpos;
varying float fall;
varying float side;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	fall = UV.y;
	side = UV.x;
}

void fragment() {
	float coarse = vnoise3(vec3(wpos.x * 4.0, wpos.z * 4.0, (wpos.y + TIME * 4.5) * 0.3));
	float fine = vnoise3(vec3(wpos.x * 11.0, wpos.z * 11.0, (wpos.y + TIME * 6.5) * 0.8));
	float s = coarse * 0.65 + fine * 0.35;
	// over the lip the sheet is still clear pond water; it whitens as it
	// bends and breaks up into the fall
	float clear = smoothstep(0.03, 0.0, fall);
	float lip = smoothstep(0.16, 0.02, fall) * (1.0 - clear);
	float white = clamp(smoothstep(0.5, 0.78, s) + lip * 0.75, 0.0, 1.0) * (1.0 - clear * 0.8);
	vec3 water = mix(srgb(vec3(0.62, 0.88, 0.88)), srgb(vec3(0.42, 0.80, 0.74)), clear);
	ALBEDO = mix(water, vec3(0.97), white);
	EMISSION = ALBEDO * 0.18;
	ROUGHNESS = 0.35;
	BACKLIGHT = vec3(0.3);
	float fade = 1.0 - smoothstep(0.35, 1.0, fall);
	// the open sides of the sheet fray out instead of ending in a hard line
	float sides = 1.0 - side * smoothstep(0.35, 0.75, s + 0.25);
	ALPHA = clamp((0.55 + 0.5 * s + lip * 0.4) * fade, 0.0, 1.0) * mix(1.0, 0.7, clear) * sides;
}
