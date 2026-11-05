shader_type spatial;
render_mode cull_disabled, world_vertex_coords, diffuse_lambert_wrap, alpha_to_coverage;

// Leaf cards with soft edges (Grafik, Mjuka bladkanter): alpha to coverage
// smooths them with MSAA, but such leaves leave the depth prepass, so they
// cost about 2 ms more in a wood and the ambient occlusion no longer shades
// them.

#define SOFT_EDGES
#include "res://shaders/leaves.gdshaderinc"
