shader_type spatial;
render_mode cull_back;

// Small things (item_builder.gd), painted like hand-made stylized props.
// Vertex colour alpha says what colour a part takes: 1 its own baked colour,
// 0.75 the style's first colour, 0.5 its second, 0.25 a warm glow (embers, a
// lantern's glass); the rgb shades it. UV2.x is the material, UV2.y how much
// the spot is an edge: bevels are worn light, the way painted props pick out
// their edges. UV runs over each part in metres for weave, grain and seams.
// Thin round parts (rods, rivets, rims) are found by how fast the normal
// turns across the screen, and catch the light too on metal, leather, glass.
// Every material is lighter on top and darker toward the ground, as painted.

#include "res://shaders/noise.gdshaderinc"

instance uniform vec3 color_a = vec3(0.6, 0.4, 0.3);
instance uniform vec3 color_b = vec3(0.5, 0.5, 0.5);
instance uniform float glow = 1.0;
instance uniform vec3 tint = vec3(1.0);
instance uniform float height = 1.0;
instance uniform float ground_y = 0.0;

varying vec4 vcol;
varying vec3 wpos;
varying vec3 opos;
varying vec2 info;

void vertex() {
	vcol = COLOR;
	info = UV2;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	opos = VERTEX;
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
	vec3 view = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	int mat = int(info.x + 0.5);
	float edge = clamp(info.y, 0.0, 1.0);
	// how sharply the surface turns here, in 1/metres: thin rods and rims
	float curv = length(fwidth(wn)) / max(length(fwidth(wpos)), 1e-5);
	float round_edge = smoothstep(25.0, 90.0, curv);
	vec2 p = UV;
	float rough = 0.8;
	float spec = 0.3;
	float metal = 0.0;
	if (emit > 0.0) {
		rough = 0.9;
	} else if (mat == 1) {
		// metal: hammered in soft patches, scuffed, its edges and rims bright
		float patches = fbm3(opos * 9.0);
		col *= 0.78 + 0.4 * patches;
		float scratch = abs(vnoise2(vec2(p.x * 40.0 + p.y * 9.0, p.y * 3.0)) - 0.5);
		col *= 1.0 + (1.0 - smoothstep(0.0, 0.03, scratch)) * 0.25;
		float e = max(edge, round_edge * 0.8);
		col = mix(col, col * 1.7 + vec3(0.1, 0.1, 0.11), e * 0.85);
		rough = mix(0.5, 0.32, e);
		spec = 0.55;
		metal = 0.35;
	} else if (mat == 2) {
		// cloth: a fine weave, soft folds, seams now and then, hems lighter
		float weave = sin(p.x * 520.0) * sin(p.y * 520.0);
		col *= 0.95 + 0.05 * weave;
		col *= 0.9 + 0.16 * fbm2(p * vec2(3.0, 2.0) + opos.xz);
		float seam = fract(p.x / 0.62 + 0.5);
		col *= 1.0 - 0.18 * (1.0 - smoothstep(0.0, 0.025, min(seam, 1.0 - seam)));
		col = mix(col, col * 1.18 + 0.02, edge * 0.7);
		rough = 0.95;
		spec = 0.12;
	} else if (mat == 3) {
		// leather: mottled darker and lighter, a scratch or two, worn pale at
		// its edges and seams
		float mottle = fbm3(opos * 14.0);
		col *= 0.75 + 0.45 * mottle;
		float scratch = abs(vnoise2(vec2(p.x * 30.0 - p.y * 18.0, p.y * 4.0)) - 0.5);
		col *= 1.0 + (1.0 - smoothstep(0.0, 0.02, scratch)) * step(0.6, vnoise3(opos * 6.0)) * 0.35;
		float e = max(edge, round_edge * 0.5);
		col = mix(col, col * 1.55 + 0.03, e * 0.75);
		rough = 0.58;
		spec = 0.35;
	} else if (mat == 4) {
		// glass: glossy, lit through, a bright rim where it turns away
		float rim = pow(1.0 - clamp(dot(wn, view), 0.0, 1.0), 3.0);
		col *= 0.8 + 0.3 * fbm3(opos * 6.0);
		col = mix(col, col * 1.8 + 0.15, max(rim * 0.6, max(edge, round_edge) * 0.5));
		emit = 0.0;
		rough = 0.14;
		spec = 0.7;
	} else if (mat == 5) {
		// wicker: fibres along each strip, its edges worn lighter
		float fib = vnoise2(vec2(p.x * 160.0, p.y * 6.0));
		col *= 0.88 + 0.2 * fib;
		col = mix(col, col * 1.3 + 0.03, edge * 0.7);
		rough = 0.85;
		spec = 0.2;
	} else if (mat == 6) {
		// pages: a block of fine lines
		float lines = sin(opos.y * 900.0);
		col *= 0.93 + 0.07 * lines;
		col = mix(col, col * 0.85, edge * 0.5);
		rough = 0.9;
		spec = 0.15;
	} else if (mat == 7) {
		// wax: soft and a little lit through
		col *= 1.02 + 0.06 * fbm3(opos * 20.0);
		col = mix(col, col * 1.12, edge);
		rough = 0.45;
		spec = 0.3;
	} else {
		// painted: soft and a touch uneven, its bevels lighter
		col *= 0.94 + 0.12 * (vnoise3(wpos * 18.0) - 0.5);
		col = mix(col, col * 1.25 + 0.02, edge * 0.6);
	}
	// lighter on top, darker toward the ground, as painted
	col *= 0.86 + 0.2 * clamp(wn.y * 0.5 + 0.5, 0.0, 1.0);
	col *= mix(0.72, 1.0, smoothstep(0.0, 0.22, wpos.y - ground_y));
	ALBEDO = weathered(col * tint, wn.y, wpos);
	EMISSION = col * emit;
	ROUGHNESS = weathered_rough(rough, wn.y, wpos);
	SPECULAR = weathered_spec(spec, wn.y, wpos);
	METALLIC = metal;
}
