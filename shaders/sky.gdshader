shader_type sky;

// The sky all round the floating island, from pastel day through a peach
// dusk to a deep blue night. The island floats, so the camera mostly looks
// at the sky *below* the horizon; that half gets its own gradient instead
// of a dark ground. The weather script sets the colours and the sun and
// moon for the hour; this shader draws them.
//
// Stars, their twinkle and the shooting stars follow the technique of
// GDQuest's Stylized Sky (MIT, github.com/gdquest-demos/godot-4-stylized-sky),
// with Inigo Quilez's Voronoi (MIT); written here without textures.

uniform vec3 top_color : source_color = vec3(0.42, 0.60, 0.84);
uniform vec3 horizon_color : source_color = vec3(0.98, 0.91, 0.82);
// the horizon the island is lit by: the ambient light comes from the cubemap
// pass, which keeps the old wide warm band so the rock stays warm in shade
uniform vec3 light_horizon : source_color = vec3(0.98, 0.91, 0.82);
uniform vec3 bottom_color : source_color = vec3(0.47, 0.66, 0.90);
uniform vec3 sun_dir = vec3(0.0, 0.6, -0.8);    // towards the sun
uniform vec3 sun_color : source_color = vec3(1.0, 0.92, 0.8);
uniform float sun_glow = 0.35;
uniform vec3 moon_dir = vec3(0.0, -0.6, 0.8);   // towards the moon
uniform float moon_phase = 0.5;                  // 0 new, 0.5 full, 1 new
uniform float night = 0.0;                       // 0 day .. 1 deep night
uniform float overcast = 0.0;                    // rain and snow grey it all out
uniform float high_clouds = 0.3;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 hash2(vec2 p) {
	return vec2(hash(p), hash(p + vec2(17.3, 5.1)));
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		s += a * vnoise(p);
		p = p * 2.07 + vec2(11.3, 4.7);
		a *= 0.5;
	}
	return s;
}

// Stars: one point per Voronoi cell, some bright, most faint, twinkling.
float stars(vec3 dir, float t) {
	// an octahedral map keeps the stars evenly spread over the whole sphere
	vec3 a = abs(dir);
	vec2 p = dir.xz / (a.x + a.y + a.z);
	if (dir.y < 0.0) {
		p = (1.0 - abs(p.yx)) * sign(p);
	}
	p *= 120.0;
	vec2 i = floor(p);
	vec2 f = fract(p);
	float light = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = hash2(i + g);
			float d = length(g + o - f);
			float bright = pow(hash(i + g + vec2(3.3, 9.1)), 18.0);
			float twinkle = 0.65 + 0.35 * sin(t * (1.5 + 3.0 * o.x) + o.y * 40.0);
			light += smoothstep(0.08 + bright * 0.06, 0.0, d) * (0.04 + bright * 1.6) * twinkle;
		}
	}
	return light;
}

// A shooting star now and then: a short bright streak with a fading tail.
float shooting_star(vec3 dir, float t) {
	float light = 0.0;
	for (int k = 0; k < 3; k++) {
		float period = 9.0 + float(k) * 4.0;
		float cycle = floor(t / period + float(k) * 0.37);
		float phase = fract(t / period + float(k) * 0.37);
		if (phase > 0.08) {
			continue;
		}
		vec2 seed = vec2(cycle, float(k));
		float az = hash(seed) * 6.283;
		float el = 0.15 + hash(seed + 1.7) * 0.9;
		vec3 start = normalize(vec3(cos(az) * cos(el), sin(el), sin(az) * cos(el)));
		vec3 along = normalize(cross(start, vec3(0.0, 1.0, 0.0)) * (hash(seed + 3.1) < 0.5 ? 1.0 : -1.0) - vec3(0.0, 0.4, 0.0));
		float progress = phase / 0.08;
		vec3 head = normalize(start + along * progress * 0.35);
		vec3 tail_dir = -along;
		vec3 rel = dir - head;
		float behind = dot(rel, tail_dir);
		float side = length(rel - tail_dir * behind);
		float tail = smoothstep(0.12, 0.0, behind) * step(0.0, behind);
		light += smoothstep(0.0025, 0.0, side) * tail * sin(progress * 3.14159);
	}
	return light;
}

// The moon as a lit sphere: the phase moves the light round it, with
// darker maria and a little earthshine on the unlit part.
vec3 moon(vec3 dir) {
	float size = 0.035;
	vec3 md = normalize(moon_dir);
	vec3 right = normalize(cross(md, vec3(0.0, 1.0, 0.0)));
	vec3 up = cross(right, md);
	vec2 q = vec2(dot(dir, right), dot(dir, up)) / size;
	float r2 = dot(q, q);
	if (dot(dir, md) < 0.0 || r2 > 1.2) {
		return vec3(0.0);
	}
	vec3 n = vec3(q, sqrt(max(1.0 - r2, 0.0)));
	float a = moon_phase * 6.283;
	vec3 l = vec3(sin(a), 0.0, -cos(a));
	float lit = smoothstep(-0.06, 0.06, dot(n, l));
	float maria = smoothstep(0.45, 0.65, fbm(q * 2.2 + 5.0));
	vec3 surface = mix(vec3(0.95, 0.94, 0.88), vec3(0.72, 0.72, 0.70), maria);
	float disc = smoothstep(1.0, 0.92, r2);
	vec3 col = surface * (lit * 1.6 + 0.04) * disc;
	// a soft halo, stronger the fuller the moon
	float full = 1.0 - abs(moon_phase - 0.5) * 2.0;
	col += vec3(0.6, 0.7, 0.9) * smoothstep(1.2, 0.95, r2) * (1.0 - disc) * 0.15 * full;
	return col;
}

void sky() {
	vec3 dir = EYEDIR;
	float y = dir.y;
	vec3 c;
	// a narrow pale band at the horizon: a low camera sees mostly this band,
	// so a wide one turned the whole picture cream
	if (AT_CUBEMAP_PASS) {
		if (y > 0.0) {
			c = mix(light_horizon, top_color, pow(smoothstep(0.0, 1.0, y), 0.55));
		} else {
			c = mix(light_horizon, bottom_color, pow(smoothstep(0.0, 0.75, -y), 0.45));
		}
	} else if (y > 0.0) {
		c = mix(horizon_color, top_color, 1.0 - exp(-y * 13.0));
	} else {
		c = mix(horizon_color, bottom_color, 1.0 - exp(y * 10.0));
	}
	vec3 sd = normalize(sun_dir);
	float d = max(dot(dir, sd), 0.0);
	float clear = 1.0 - overcast * 0.85;
	c += sun_color * (pow(d, 12.0) * sun_glow * 0.4 + pow(d, 200.0) * sun_glow) * clear;
	c += sun_color * smoothstep(0.9995, 0.9998, d) * 4.0 * step(0.0, sd.y + 0.05) * clear;

	if (!AT_CUBEMAP_PASS && !AT_HALF_RES_PASS && !AT_QUARTER_RES_PASS) {
		// thin high clouds drifting, lit by the sun or silvered by the moon
		if (high_clouds > 0.0 && y > -0.2) {
			vec2 p = dir.xz / (abs(y) + 0.25) * 1.3 + vec2(TIME * 0.006, TIME * 0.003);
			float wisp = smoothstep(0.55 - high_clouds * 0.25, 0.85, fbm(p * vec2(1.0, 2.6)));
			vec3 lit = mix(vec3(1.0, 0.97, 0.94), sun_color * 1.1, 0.3);
			lit = mix(lit, vec3(0.25, 0.3, 0.42), night);
			c = mix(c, lit, wisp * 0.55 * smoothstep(-0.2, 0.15, y));
		}
		float starry = night * clear;
		if (starry > 0.01) {
			c += vec3(0.9, 0.92, 1.0) * stars(dir, TIME) * starry * starry * (y > 0.0 ? 1.0 : 0.6);
			c += vec3(1.0, 0.96, 0.85) * shooting_star(dir, TIME) * starry * 2.0;
		}
		c += moon(dir) * smoothstep(-0.1, 0.3, night) * clear;
	}
	// rain and snow wash the sky to a soft grey
	c = mix(c, vec3(dot(c, vec3(0.3, 0.55, 0.15))) * vec3(0.92, 0.95, 1.0), overcast * 0.75);
	COLOR = c;
}
