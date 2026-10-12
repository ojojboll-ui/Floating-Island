shader_type spatial;
render_mode cull_back;

// Bark with vertical grain. Moss, the same as on the stones, gathers on the
// upper side of branches and round the foot, as much as the Mossa dial says.

#include "res://shaders/noise.gdshaderinc"

instance uniform float ground_y = 0.0;
instance uniform vec3 tint = vec3(1.0);
instance uniform float height = 1.0;
instance uniform vec3 bark = vec3(0.40, 0.29, 0.21);
// the Mossa dial: moss as on the stones, on what faces the sky and round
// the very foot
instance uniform float moss_amount = 0.2;
// how high moss creeps up the trunk at full Mossa: the first fork
instance uniform float moss_climb = 1.5;
// the Struktur and Relief dials
instance uniform float texture_amount = 0.5;
instance uniform float relief = 0.5;

uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform bool has_normal = false;

varying vec3 wpos;

void fragment() {
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float grain = vnoise3(wpos * vec3(9.0, 1.4, 9.0));
	float knots = fbm3(wpos * 2.5);
	// Struktur: how strongly the grain and knots show
	float strength = texture_amount * 2.0;
	vec3 col = srgb(bark) * (1.0 + ((0.65 + 0.45 * grain) * (0.85 + 0.3 * knots) - 1.0) * strength);
	// moss as on the stones (the Mossa dial): on branch tops that face the
	// sky, round the very foot, and with more Mossa creeping up the trunk,
	// in ever smaller patches, as far as the first fork at full Mossa
	float h = wpos.y - ground_y;
	float foot = smoothstep(0.09, 0.0, h + (fbm3(wpos * 4.0) - 0.5) * 0.06);
	float climb = moss_climb * smoothstep(0.3, 1.0, moss_amount);
	float up = h / max(climb, 0.01);
	// patches: solid low down, ever fewer and smaller higher up, a last few
	// flecks by the fork
	float blotch = fbm3(wpos * vec3(3.5, 1.6, 3.5)) * 0.75 + vnoise3(wpos * 11.0) * 0.25;
	float patches = smoothstep(0.46, 0.54, blotch + 0.38 - up * 0.4);
	float trunk_moss = (1.0 - smoothstep(0.92, 1.08, up)) * patches * step(0.05, climb);
	vec2 mf = moss_fuzz(wpos, wpos, moss_cover(wpos, wn, moss_amount, max(foot * moss_amount * 1.5, trunk_moss)), col);
	// Relief: the grain as a height, tipping the normal (from screen
	// derivatives), moss lying softer over it
	float bump_h = (grain * 0.6 + knots * 0.4) * 0.012 * relief * (1.0 - mf.x * 0.7);
	vec3 dpdx = dFdx(wpos);
	vec3 dpdy = dFdy(wpos);
	vec3 r1 = cross(dpdy, wn);
	vec3 r2 = cross(wn, dpdx);
	float det = dot(dpdx, r1);
	vec3 bn = normalize(abs(det) * wn - sign(det) * (dFdx(bump_h) * r1 + dFdy(bump_h) * r2));
	NORMAL = normalize((VIEW_MATRIX * vec4(bn, 0.0)).xyz);
	ALBEDO = weathered(col, wn.y, wpos);
	if (has_normal) {
		// the Quaternius bark normal (CC0): twice round the trunk, stretched along it
		NORMAL_MAP = texture(normal_tex, UV * vec2(2.0, 0.6)).rgb;
		NORMAL_MAP_DEPTH = 2.8 * relief;
	}
	ROUGHNESS = weathered_rough(0.9, wn.y, wpos);
	SPECULAR = weathered_spec(0.2, wn.y, wpos);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
