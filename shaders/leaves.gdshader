shader_type spatial;
render_mode cull_disabled, world_vertex_coords, diffuse_lambert_wrap;

// Leaf cards with cut-out edges (leaves.gdshaderinc). They go through the
// depth prepass, so the ambient occlusion shades the leaves behind others.

#include "res://shaders/leaves.gdshaderinc"
