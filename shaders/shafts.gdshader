shader_type spatial;
// Light shafts from the sun, added over the 3D view before the tonemap.
//
// The radial blur from Mitchell, "Volumetric Light Scattering as a
// Post-Process" (GPU Gems 3, ch. 13), the idea behind the CC0 "Screen Space
// God Rays" shader on godotshaders.com. That one renders an occlusion pass
// in a second viewport; here the depth buffer is the occlusion: only open
// sky shines, so the island, the trees and the clouds cut the light into
// shafts. A full-screen quad, drawn after everything and added on top.
render_mode unshaded, blend_add, depth_test_disabled, depth_draw_never, cull_disabled, skip_vertex_transform, fog_disabled;

uniform sampler2D depth : hint_depth_texture, filter_nearest, repeat_disable;

uniform vec2 sun_uv = vec2(0.5, 0.0);
uniform float sun_on = 0.0;
uniform vec3 sun_color : source_color = vec3(1.0, 0.9, 0.7);
uniform float aspect = 1.777;
uniform float rays = 0.0;
uniform float ray_length = 0.6;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 0.5, 1.0);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	// march toward the sun, gathering the open sky near it; the march starts
	// at a random offset so its steps melt into fine noise, not bands
	const int N = 24;
	vec2 stride = (sun_uv - uv) * ray_length / float(N);
	vec2 p = uv + stride * hash(FRAGCOORD.xy + fract(TIME) * 61.0);
	float decay = 1.0;
	vec3 sum = vec3(0.0);
	for (int k = 0; k < N; k++) {
		p += stride;
		vec2 q = clamp(p, vec2(0.001), vec2(0.999));
		// reverse z: the sky is at depth 0
		float sky = step(textureLod(depth, q, 0.0).r, 0.000001);
		vec2 d = (p - sun_uv) * vec2(aspect, 1.0);
		// the light gathers right round the sun, so it falls in streaks rather
		// than a veil over everything (no copy of the screen is read: only
		// where the sky is open, and how near the sun)
		sum += vec3(sky * exp(-dot(d, d) * 14.0) * decay);
		decay *= 0.925;
	}
	// the decay series sums to about 12 when every step is open sky
	ALBEDO = sum / 12.0 * sun_color * rays * sun_on * 1.1;
}
