shader_type spatial;
render_mode cull_disabled, world_vertex_coords, diffuse_lambert_wrap;

// Grass blades. Each tuft reads the terrain texture at its root: the height
// to stand at, whether it is on land, how much of the ground there is grass,
// and whether something already stands there. Tufts that should not grow are
// folded to nothing. Colour comes from the same grass_tint() as the ground
// below, darker at the root, so a tuft fades into the soil it stands in.

#include "res://shaders/noise.gdshaderinc"

// r surface height, g distance to coast, b occupied, a grass weight
uniform sampler2D terrain : filter_linear, repeat_disable;
uniform float terrain_size = 32.0;
uniform float terrain_res = 161.0;

varying vec3 wpos;
varying vec3 wnormal;
varying float along;
varying float shade;

vec4 terrain_at(vec2 xz) {
	vec2 uv = (xz / terrain_size + 0.5) * (terrain_res - 1.0) / terrain_res + 0.5 / terrain_res;
	return textureLod(terrain, uv, 0.0);
}

void vertex() {
	vec2 root = INSTANCE_CUSTOM.xy;
	float chance = INSTANCE_CUSTOM.z;
	vec4 t = terrain_at(root);
	float lush = fbm2(root * 0.22) ;
	float density = clamp(t.a * 1.4 - 0.4, 0.0, 1.0) * (1.0 - t.b) * (0.35 + 0.8 * lush) * step(0.02, t.g);
	// only sheer walls stay bare; hillsides keep their grass
	float sx = terrain_at(root + vec2(0.1, 0.0)).r - terrain_at(root - vec2(0.1, 0.0)).r;
	float sz = terrain_at(root + vec2(0.0, 0.1)).r - terrain_at(root - vec2(0.0, 0.1)).r;
	density *= 1.0 - smoothstep(3.0, 5.0, length(vec2(sx, sz)) / 0.2);
	float grows = step(chance, density);
	float tall = mix(0.75, 1.25, INSTANCE_CUSTOM.w) * mix(0.55, 1.0, smoothstep(0.0, 0.5, t.g)) * (0.55 + 0.6 * density);
	tall *= grows;

	along = UV.y;
	shade = COLOR.r;
	// fold non-growing tufts into their root point
	VERTEX.xz = root + (VERTEX.xz - root) * grows;
	// stand on the ground at the root; blades stay upright on slopes
	VERTEX.y = VERTEX.y * tall + t.r - 0.02;

	float gust = vnoise2(VERTEX.xz * 0.18 + vec2(TIME * 0.35, TIME * 0.21));
	float sway = sin(TIME * 1.7 + VERTEX.x * 0.8 + VERTEX.z * 0.6) * 0.35 + gust * 1.1 - 0.4;
	VERTEX.xz += vec2(1.0, 0.45) * sway * along * along * 0.07 * tall * wind_sway();
	wpos = VERTEX;
	wnormal = NORMAL;
}

void fragment() {
	vec3 base = grass_tint(wpos.xz);
	vec3 col = mix(base * 0.5, base * 1.18 + srgb(vec3(0.06, 0.06, 0.0)), smoothstep(0.0, 1.0, along));
	// snow catches on the tips first, then buries the tufts
	float s = snow_on(0.6 + along * 0.4, wpos);
	col *= mix(1.0, 0.75, wetness);
	ALBEDO = mix(col * (0.88 + shade * 0.24), vec3(0.92, 0.94, 0.97), s * (0.5 + 0.5 * along));
	vec3 n = normalize(mix(wnormal, vec3(0.0, 1.0, 0.0), 0.65));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	ROUGHNESS = weathered_rough(0.8, 0.0, wpos);
	SPECULAR = weathered_spec(0.25, 0.0, wpos);
	BACKLIGHT = srgb(vec3(0.35, 0.45, 0.12)) * along;
}
