shader_type spatial;
render_mode cull_back, specular_schlick_ggx;

// Ponds and streams. What lies below is seen through the surface, bent by
// the ripples and tinted by how much water the eye looks through: clear and
// pale at the edge, deep teal in the middle. Where the bank rises to meet
// the surface a ring of foam laps at it. On a slope the ripples run
// downhill, so a stream visibly flows.

#include "res://shaders/noise.gdshaderinc"

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

varying vec3 wpos;
varying vec3 wnormal;
varying float coast;     // distance to the island's edge
varying vec2 pull;       // toward the lip of a fall, strongest at the edge

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	coast = UV.y;
	pull = UV2;
}

float ripples(vec2 p, vec2 flow) {
	float t = TIME;
	return vnoise2(p * 1.6 - flow * t * 1.6) * 0.6
		+ vnoise2(p * 5.3 + vec2(t * 0.21, -t * 0.17) - flow * t * 5.3) * 0.3
		+ vnoise2(p * 11.0 + vec2(-t * 0.4, t * 0.33)) * 0.1;
}

void fragment() {
	// downhill along the surface; still ponds just drift a little
	vec2 slope = wnormal.xz;
	float steep = smoothstep(0.04, 0.25, length(slope));
	vec2 flow = (length(slope) > 0.0001 ? normalize(slope) : vec2(0.0)) * steep * 0.9 + vec2(0.03, 0.02);
	// near a fall the water speeds up toward the lip
	flow += pull * 1.6;
	float rush = clamp(length(pull), 0.0, 1.0);
	steep = max(steep, rush * 0.8);

	float e = 0.02;
	float h0 = ripples(wpos.xz, flow);
	float hx = ripples(wpos.xz + vec2(e, 0.0), flow);
	float hz = ripples(wpos.xz + vec2(0.0, e), flow);
	float bumpiness = mix(0.012, 0.03, steep);
	vec3 n = normalize(vec3(-(hx - h0) / e * bumpiness, 1.0, -(hz - h0) / e * bumpiness));
	// rain: rings spreading where drops land, two sizes overlapping, more
	// of them the harder it rains; a stream carries them off downstream
	float rain_crest = 0.0;
	if (rain_amount > 0.01) {
		vec2 rp = wpos.xz * 3.2 - flow * TIME * 1.5;
		vec2 ra = rain_rings(rp, TIME * 1.6);
		vec2 rb = rain_rings(rp * 1.7 + 13.0, TIME * 1.9 + 0.5);
		float re = 0.01;
		vec2 rx = rain_rings(rp + vec2(re, 0.0), TIME * 1.6) + rain_rings((rp + vec2(re, 0.0)) * 1.7 + 13.0, TIME * 1.9 + 0.5);
		vec2 rz = rain_rings(rp + vec2(0.0, re), TIME * 1.6) + rain_rings((rp + vec2(0.0, re)) * 1.7 + 13.0, TIME * 1.9 + 0.5);
		float r0 = ra.x + rb.x;
		float strength = rain_amount * 0.012;
		n = normalize(n + vec3(-(rx.x - r0) / re, 0.0, -(rz.x - r0) / re) * strength);
		rain_crest = max(ra.y, rb.y) * rain_amount;
	}
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	// how much water the eye looks through to reach the ground
	float depth = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	behind.xyz /= behind.w;
	float thick = max(0.0, VERTEX.z - behind.z);

	float murk = 1.0 - exp(-thick * 1.2);
	vec2 bent = SCREEN_UV + n.xz * 0.025 * clamp(thick * 4.0, 0.0, 1.0);
	vec3 below = textureLod(screen_tex, bent, 0.0).rgb;
	// caustics on the bed: find where the eye ray meets the ground and lay
	// the moving web there, bright in the shallows, fading with depth
	vec3 bed = (INV_VIEW_MATRIX * vec4(behind.xyz, 1.0)).xyz;
	float under = max(0.0, wpos.y - bed.y);
	float light = caustics(bed.xz * 1.7, TIME * 0.8);
	light *= smoothstep(0.0, 0.05, under) * exp(-under * 1.4) * (1.0 - steep * 0.6);
	below += below * srgb(vec3(1.0, 0.97, 0.88)) * light * 2.6 + srgb(vec3(0.85, 0.95, 0.92)) * light * 0.18;
	vec3 shallow = srgb(vec3(0.42, 0.80, 0.74));
	vec3 deep = srgb(vec3(0.06, 0.30, 0.34));
	vec3 tint = mix(shallow, deep, murk);
	vec3 seen = mix(below * mix(vec3(1.0), tint * 1.7, clamp(murk * 1.6, 0.0, 1.0)), tint * 0.55, murk * 0.7);

	// a soft, broken line of foam lapping at the bank
	float lap = (vnoise2(wpos.xz * 4.0 + vec2(TIME * 0.3, -TIME * 0.2)) - 0.5) * 0.08;
	float foam = smoothstep(0.07, 0.015, thick + lap) * smoothstep(0.0, 0.015, thick);
	foam *= smoothstep(0.35, 0.6, vnoise2(wpos.xz * 9.0 + vec2(-TIME * 0.4, TIME * 0.25))) * 0.7;
	// by the lip the bank line gives way to the rush of water going over
	foam *= 1.0 - smoothstep(0.0, 0.6, rush) * 0.9;
	foam += steep * smoothstep(0.6, 0.85, h0) * 0.45;
	// churned white right at the lip, so the surface runs into the fall
	foam += rush * smoothstep(0.55, 0.0, coast) * smoothstep(0.3, 0.7, vnoise2(wpos.xz * 6.0 - pull * TIME * 3.0)) * 0.8;
	// the crests of rain rings catch the light
	foam += rain_crest * 0.35;
	foam = clamp(foam, 0.0, 1.0);

	ALBEDO = vec3(0.92, 0.95, 0.95) * foam;
	EMISSION = seen * (1.0 - foam);
	ROUGHNESS = mix(0.04, 0.85, foam);
	SPECULAR = 0.5;
	ALPHA = 1.0;
}
