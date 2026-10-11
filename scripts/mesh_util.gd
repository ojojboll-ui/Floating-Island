extends RefCounted
## Small helpers for building ArrayMeshes by hand.
## Winding follows Godot: front faces are clockwise seen from outside.


static func face_normal(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	return (c - a).cross(b - a)


## Area-weighted vertex normals over shared indices.
static func normals(verts: PackedVector3Array, indices: PackedInt32Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(verts.size())
	out.fill(Vector3.ZERO)
	for t in range(0, indices.size(), 3):
		var a := indices[t]
		var b := indices[t + 1]
		var c := indices[t + 2]
		var n := face_normal(verts[a], verts[b], verts[c])
		out[a] += n
		out[b] += n
		out[c] += n
	for k in out.size():
		out[k] = out[k].normalized()
	return out


## Like normals(), but vertices at the same position share one normal, so UV
## seams in primitive meshes do not show up as creases.
static func normals_by_position(verts: PackedVector3Array, indices: PackedInt32Array) -> PackedVector3Array:
	var acc := {}
	for t in range(0, indices.size(), 3):
		var a := verts[indices[t]]
		var b := verts[indices[t + 1]]
		var c := verts[indices[t + 2]]
		var n := face_normal(a, b, c)
		for p in [a, b, c]:
			var key := Vector3i((p * 1000.0).round())
			acc[key] = acc.get(key, Vector3.ZERO) + n
	var out := PackedVector3Array()
	out.resize(verts.size())
	for k in verts.size():
		var key := Vector3i((verts[k] * 1000.0).round())
		out[k] = (acc[key] as Vector3).normalized()
	return out


static func add_surface(mesh: ArrayMesh, verts: PackedVector3Array, nrm: PackedVector3Array,
		uvs: PackedVector2Array, colors: PackedColorArray, indices: PackedInt32Array,
		uv2s: PackedVector2Array = PackedVector2Array()) -> void:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = nrm
	if uvs.size() > 0:
		arr[Mesh.ARRAY_TEX_UV] = uvs
	if colors.size() > 0:
		arr[Mesh.ARRAY_COLOR] = colors
	if uv2s.size() > 0:
		arr[Mesh.ARRAY_TEX_UV2] = uv2s
	arr[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
