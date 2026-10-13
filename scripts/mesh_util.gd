extends RefCounted
## Small helpers for building ArrayMeshes by hand.
## Winding follows Godot: front faces are clockwise seen from outside.


## Where a raw asset file is (the Quaternius files, read as they are): in the
## project when run from the editor, or in the assets folder shipped beside
## an exported program (the folder is .gdignore'd, so it is not packed).
static func asset(rel: String) -> String:
	if OS.has_feature("template"):
		return OS.get_executable_path().get_base_dir().path_join("assets").path_join(rel)
	return "res://assets/" + rel


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


## A flat shape cut from a board: `outline` (in x-y, either winding) made
## `thick` deep in z, its rim bevelled `bevel` deep on both faces. Each band
## (faces, bevels, the side) has vertices of its own, so they meet in crisp
## edges. Returns {v, uv, e, i}: positions, uv (across, along x), how much
## each vertex is an edge (1 on the bevels), and triangles wound outward.
static func extrude(outline: PackedVector2Array, thick: float, bevel: float) -> Dictionary:
	var pts := outline.duplicate()
	var area := 0.0
	for k in pts.size():
		var a := pts[k]
		var b := pts[(k + 1) % pts.size()]
		area += a.x * b.y - b.x * a.y
	if area < 0.0:
		pts.reverse()
	var n := pts.size()
	var h := thick * 0.5
	var b := minf(bevel, h * 0.9)
	# outward normal of each edge, and the outline drawn in by the bevel
	var out: Array[Vector2] = []
	for k in n:
		var d := (pts[(k + 1) % n] - pts[k]).normalized()
		out.append(Vector2(d.y, -d.x))
	var inner := PackedVector2Array()
	var vnorm: Array[Vector2] = []
	for k in n:
		var np := out[(k - 1 + n) % n]
		var nn := out[k]
		var bis := (np + nn).normalized()
		vnorm.append(bis)
		inner.append(pts[k] - bis * b / maxf(bis.dot(nn), 0.35))
	var centre := Vector2.ZERO
	for p in inner:
		centre += p
	centre /= n
	# plain arrays, which the helpers below can add to (packed ones are copied)
	var vs: Array = []
	var uvs: Array = []
	var es: Array = []
	var ids: Array = []
	var put := func(p: Vector3, edge: float) -> int:
		vs.append(p)
		uvs.append(Vector2(p.y if edge < 0.2 else p.z + p.y * 0.3, p.x))
		es.append(edge)
		return vs.size() - 1
	var tri := func(a: int, bb: int, c: int, want: Vector3) -> void:
		if face_normal(vs[a], vs[bb], vs[c]).dot(want) < 0.0:
			ids.append_array([a, c, bb])
		else:
			ids.append_array([a, bb, c])
	for s: float in [1.0, -1.0]:
		var z := s * h
		# the face
		var c0: int = put.call(Vector3(centre.x, centre.y, z), 0.0)
		var face := []
		for p in inner:
			face.append(put.call(Vector3(p.x, p.y, z), 0.0))
		for k in n:
			tri.call(c0, face[k], face[(k + 1) % n], Vector3(0, 0, s))
		# the bevel round it
		var top := []
		var low := []
		for k in n:
			top.append(put.call(Vector3(inner[k].x, inner[k].y, z), 1.0))
			low.append(put.call(Vector3(pts[k].x, pts[k].y, z - s * b), 1.0))
		for k in n:
			var k2 := (k + 1) % n
			var want := Vector3(out[k].x, out[k].y, s).normalized()
			tri.call(top[k], low[k], low[k2], want)
			tri.call(top[k], low[k2], top[k2], want)
	# the side
	var up := []
	var dn := []
	for k in n:
		up.append(put.call(Vector3(pts[k].x, pts[k].y, h - b), 0.4))
		dn.append(put.call(Vector3(pts[k].x, pts[k].y, -(h - b)), 0.4))
	for k in n:
		var k2 := (k + 1) % n
		var want := Vector3(out[k].x, out[k].y, 0.0)
		tri.call(up[k], dn[k], dn[k2], want)
		tri.call(up[k], dn[k2], up[k2], want)
	return {"v": PackedVector3Array(vs), "uv": PackedVector2Array(uvs), "e": PackedFloat32Array(es), "i": PackedInt32Array(ids)}
