shader_type canvas_item;
// The finish laid over the picture after Godot's own tonemap: white
// balance and split toning, a vignette, film grain, colour fringes toward
// the corners and a little sharpening. The light shafts are shafts.gdshader,
// in the 3D view, where the depth buffer can tell sky from island.

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap, repeat_disable;

uniform float aspect = 1.777;

uniform float temperature = 0.0;       // -1 cold .. 1 warm
uniform float tint = 0.0;              // -1 green .. 1 magenta
uniform vec3 shadow_tint : source_color = vec3(1.0);
uniform vec3 highlight_tint : source_color = vec3(1.0);
uniform float vignette = 0.25;
uniform float grain = 0.0;
uniform float aberration = 0.0;
uniform float sharpen = 0.0;

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// a tint picked as a colour, kept at its own brightness so only the hue moves
vec3 hue_of(vec3 c) {
	return c / max(luma(c), 0.02);
}

vec3 fetch(vec2 uv) {
	if (aberration <= 0.0) {
		return texture(screen, uv).rgb;
	}
	vec2 mid = uv - 0.5;
	vec2 off = mid * dot(mid, mid) * aberration * 0.05;
	return vec3(texture(screen, uv - off).r, texture(screen, uv).g, texture(screen, uv + off).b);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 c = fetch(uv);

	if (sharpen > 0.0) {
		vec2 px = SCREEN_PIXEL_SIZE;
		vec3 around = texture(screen, uv + vec2(px.x, 0.0)).rgb + texture(screen, uv - vec2(px.x, 0.0)).rgb
			+ texture(screen, uv + vec2(0.0, px.y)).rgb + texture(screen, uv - vec2(0.0, px.y)).rgb;
		c += (c - around * 0.25) * sharpen * 1.5;
	}

	// white balance
	c *= vec3(1.0 + temperature * 0.16 + tint * 0.05, 1.0 + temperature * 0.02 - tint * 0.1, 1.0 - temperature * 0.2 + tint * 0.05);

	// split toning: one hue into the shadows, another into the highlights
	float l = luma(c);
	c *= mix(vec3(1.0), hue_of(shadow_tint), (1.0 - smoothstep(0.0, 0.55, l)) * 0.5);
	c *= mix(vec3(1.0), hue_of(highlight_tint), smoothstep(0.45, 1.0, l) * 0.5);

	// vignette, round on the screen whatever its shape
	vec2 mid = (uv - 0.5) * vec2(aspect / 1.777, 1.0);
	c *= 1.0 - vignette * smoothstep(0.25, 0.95, length(mid) * 1.3);

	// grain, strongest in the midtones as on film
	if (grain > 0.0) {
		float n = hash(FRAGCOORD.xy + floor(TIME * 24.0) * vec2(37.0, 17.0)) - 0.5;
		c += n * grain * 0.16 * (0.35 + 2.6 * l * (1.0 - l));
	}

	COLOR = vec4(max(c, vec3(0.0)), 1.0);
}
