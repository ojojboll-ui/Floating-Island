shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;

// The ghost of what the brush will place: see-through, brighter at its
// outline, green where it may go and red where it may not. Leaf cards cut
// out the same leaf shapes as leaves.gdshader, so a ghost tree reads as a
// crown and not a cloud of squares.

uniform vec3 tint = vec3(0.85, 1.0, 0.8);
uniform float alpha = 0.4;
uniform bool leaf_cut = false;

varying float rnd;

float leaf(vec2 uv, vec2 at, float ang, vec2 size) {
	vec2 d = uv - at;
	float c = cos(ang);
	float s = sin(ang);
	d = vec2(c * d.x + s * d.y, -s * d.x + c * d.y) / size;
	float w = 1.0 - d.y * d.y;
	return w - abs(d.x) * 1.6;
}

void vertex() {
	rnd = COLOR.g;
}

void fragment() {
	if (leaf_cut) {
		float a = -1.0;
		for (int k = 0; k < 5; k++) {
			float ang = float(k) * 1.2566 + rnd * 6.28;
			vec2 at = vec2(0.5) + vec2(sin(ang), -cos(ang)) * 0.2;
			a = max(a, leaf(UV, at, ang, vec2(0.11, 0.24)));
		}
		a = max(a, leaf(UV, vec2(0.5), rnd * 3.0, vec2(0.12, 0.22)));
		if (a < 0.0) {
			discard;
		}
	}
	float rim = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
	ALBEDO = tint * (0.7 + 0.6 * rim);
	ALPHA = alpha * (0.55 + 0.9 * rim * rim);
}
