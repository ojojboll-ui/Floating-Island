shader_type spatial;
render_mode cull_disabled;

// Water lily pads and their flowers. Pads bob a little on the ripples; veins
// run out from the centre. Vertex colour: rgb colour, a = 1 on the pad.

#include "res://shaders/noise.gdshaderinc"

instance uniform vec3 tint = vec3(1.0);
instance uniform float height = 1.0;
instance uniform float ground_y = 0.0;

varying vec3 local;
varying float pad;

void vertex() {
	local = VERTEX;
	pad = COLOR.a;
	vec3 w = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	VERTEX.y += sin(TIME * 1.1 + w.x * 1.7 + w.z * 1.3) * 0.006;
}

void fragment() {
	vec3 c = COLOR.rgb * tint;
	if (pad > 0.5) {
		float ang = atan(local.z, local.x);
		float r = length(local.xz);
		float vein = smoothstep(0.85, 1.0, abs(sin(ang * 9.0)));
		c *= mix(1.0, 0.82, vein * smoothstep(0.02, 0.08, r));
		c *= 0.9 + 0.2 * vnoise2(local.xz * 30.0);
		ROUGHNESS = 0.35;
		SPECULAR = 0.45;
	} else {
		ROUGHNESS = 0.7;
		SPECULAR = 0.25;
		BACKLIGHT = c * 0.5;
	}
	ALBEDO = c;
}
