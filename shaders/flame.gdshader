shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// A stylized flame on a card that always faces the camera round its
// upright axis: a teardrop licked upward by noise, white-yellow at its
// heart, orange to red at its edge, flickering.

#include "res://shaders/noise.gdshaderinc"

instance uniform float seed = 0.0;

void vertex() {
	// turn the card to face the camera, keeping it upright
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)), 0.0),
		vec4(0.0, 1.0, 0.0, 0.0),
		vec4(normalize(cross(INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0))), 0.0),
		MODEL_MATRIX[3]);
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(s, 0.0, 0.0, 0.0), vec4(0.0, s, 0.0, 0.0), vec4(0.0, 0.0, s, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	vec2 uv = UV;
	float t = TIME * 2.2 + seed;
	float y = 1.0 - uv.y;
	// sway and lick: the flame's middle wanders, its edge is torn by noise
	float x = (uv.x - 0.5) + sin(t * 1.7 + y * 4.0) * 0.06 * y + (vnoise2(vec2(uv.x * 4.0, y * 3.0 - t * 1.6)) - 0.5) * 0.18 * y;
	// a teardrop: wide at the foot, drawn to a point
	float width = 0.42 * (1.0 - y) * smoothstep(0.0, 0.25, y + 0.06) + 0.02;
	width *= 0.85 + 0.15 * sin(t * 3.1);
	float shape = 1.0 - smoothstep(width * 0.55, width, abs(x));
	shape *= smoothstep(1.0, 0.7, y + (vnoise2(vec2(uv.x * 6.0, t)) - 0.5) * 0.25);
	float core = 1.0 - smoothstep(0.0, width * 0.55, abs(x));
	core *= smoothstep(0.75, 0.2, y);
	vec3 col = mix(vec3(1.0, 0.25, 0.04), vec3(1.0, 0.62, 0.16), smoothstep(0.0, 0.6, shape));
	col = mix(col, vec3(1.0, 0.85, 0.5), core * 0.6);
	ALBEDO = col * shape * 1.5;
	ALPHA = shape;
}
