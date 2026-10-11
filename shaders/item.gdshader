shader_type spatial;
render_mode cull_back, diffuse_lambert_wrap;

// Small things (item_builder.gd). Vertex colour alpha says what colour a
// part takes: 1 its own baked colour, 0.75 the style's first colour, 0.5
// its second, 0.25 a warm glow (embers, a lantern's glass); the rgb shades
// it. Soft wrapped light and a little grain keep them in the island's
// painted look; rain, snow and wind treat them like everything else.

#include "res://shaders/noise.gdshaderinc"

instance uniform vec3 color_a = vec3(0.6, 0.4, 0.3);
instance uniform vec3 color_b = vec3(0.5, 0.5, 0.5);
instance uniform float glow = 1.0;
instance uniform vec3 tint = vec3(1.0);
instance uniform float height = 1.0;
instance uniform float ground_y = 0.0;

varying vec4 vcol;
varying vec3 wpos;

void vertex() {
	vcol = COLOR;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float slot = vcol.a;
	vec3 col;
	float emit = 0.0;
	if (slot > 0.87) {
		col = srgb(vcol.rgb);
	} else if (slot > 0.62) {
		col = srgb(color_a) * vcol.r;
	} else if (slot > 0.37) {
		col = srgb(color_b) * vcol.r;
	} else {
		// glowing: embers flicker
		float flick = 0.75 + 0.25 * sin(TIME * 9.0 + wpos.x * 13.0) * sin(TIME * 5.3 + wpos.z * 7.0);
		col = srgb(vec3(1.0, 0.55, 0.2)) * vcol.r;
		emit = 2.2 * glow * flick;
	}
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	col *= 0.94 + 0.12 * (vnoise3(wpos * 18.0) - 0.5);
	ALBEDO = weathered(col * tint, wn.y, wpos);
	EMISSION = col * emit;
	ROUGHNESS = weathered_rough(0.8, wn.y, wpos);
	SPECULAR = weathered_spec(0.3, wn.y, wpos);
}
