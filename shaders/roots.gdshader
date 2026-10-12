shader_type spatial;
render_mode cull_back;

// Roots, stylized: a painted colour with soft light and shade, and as much
// of the Quaternius twisted-tree bark (CC0) as the Bark dial asks for. They keep their
// own colour (moss only as much as their Mossa dial says); soil clings where hanging
// roots leave the rock; hanging roots sway in the wind toward their tips.
// Vertex colour red is how far along the root a point is, green is 1 where
// the root hangs free.

#include "res://shaders/noise.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;

instance uniform vec3 tint = vec3(0.45, 0.3, 0.2);
instance uniform float bark = 0.35;
// the Mossa dial: moss as on the stones
instance uniform float moss_amount = 0.0;
// the Struktur and Relief dials
instance uniform float texture_amount = 0.5;
instance uniform float relief = 0.5;

varying vec3 wpos;
varying float along;
varying float hanging;

void vertex() {
	along = COLOR.r;
	hanging = COLOR.g;
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float reach = along * along * hanging;
	float t = TIME * 0.9;
	vec3 sway = vec3(sin(t + w.x * 0.4 + w.z * 0.2), 0.0, sin(t * 0.8 + w.z * 0.4 + 1.3)) * reach * 0.12 * wind_sway();
	VERTEX += (inverse(MODEL_MATRIX) * vec4(sway, 0.0)).xyz;
	wpos = w + sway;
}

void fragment() {
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 base = srgb(tint);
	vec3 tex = texture(albedo_tex, UV).rgb;
	// painted: the tint, lifted where the bark's ridges are and cut by fine
	// grooves running along the root
	float ridge = smoothstep(0.15, 0.6, dot(tex, vec3(0.3, 0.59, 0.11)));
	// seven grooves round, wandering along the root; whole turns, so no seam
	float groove = smoothstep(-0.4, 0.7, sin(UV.x * TAU * 7.0 + (vnoise2(vec2(UV.y * 1.3, 0.5)) - 0.5) * 5.0));
	// Struktur: how strongly the ridges and grooves show
	vec3 painted = base * (1.0 + ((0.72 + 0.5 * ridge) * mix(0.78, 1.0, groove) - 1.0) * texture_amount * 2.0);
	// textured: the bark itself, recoloured by the tint
	vec3 barky = tex * base / srgb(vec3(0.45, 0.3, 0.2)) * 0.9;
	vec3 col = mix(painted, barky, bark);
	// soft light from above, the stylized way
	col *= mix(0.78, 1.08, wn.y * 0.5 + 0.5);
	// soil still clinging where a hanging root leaves the rock
	float soil = smoothstep(0.15, 0.0, along + (fbm3(wpos * 3.0) - 0.5) * 0.1) * hanging;
	col = mix(col, srgb(vec3(0.3, 0.21, 0.14)), soil * 0.7);
	// moss as on the stones (the Mossa dial), less on roots hanging free
	vec2 mf = moss_fuzz(wpos, wpos, moss_cover(wpos, wn, moss_amount * (1.0 - hanging * 0.7), 0.0), col);
	// Relief: the grooves as a height, tipping the normal (from screen
	// derivatives), moss lying softer over them
	float bump_h = (groove * 0.7 + ridge * 0.3) * 0.008 * relief * (1.0 - mf.x * 0.7);
	vec3 dpdx = dFdx(wpos);
	vec3 dpdy = dFdy(wpos);
	vec3 r1 = cross(dpdy, wn);
	vec3 r2 = cross(wn, dpdx);
	float det = dot(dpdx, r1);
	vec3 bn = normalize(abs(det) * wn - sign(det) * (dFdx(bump_h) * r1 + dFdy(bump_h) * r2));
	NORMAL = normalize((VIEW_MATRIX * vec4(bn, 0.0)).xyz);
	ALBEDO = weathered(col, wn.y, wpos);
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = mix(0.7, 1.8, bark) * relief * 2.0;
	ROUGHNESS = weathered_rough(0.85, wn.y, wpos);
	SPECULAR = weathered_spec(0.25, wn.y, wpos);
}
