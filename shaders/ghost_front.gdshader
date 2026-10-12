shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, blend_mix, shadows_disabled;

// The ghost of a door or window: drawn over the wall it would open in, so
// it shows however the stones stand round it. Green where it fits, red
// where it does not; brighter toward its edge.

uniform vec3 tint = vec3(0.8, 1.0, 0.78);
uniform float alpha = 0.45;

void fragment() {
	float rim = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
	ALBEDO = tint;
	ALPHA = alpha * (0.6 + 0.6 * rim);
}
