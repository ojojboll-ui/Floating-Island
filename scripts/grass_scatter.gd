extends RefCounted
## Grass for one tile: a fixed, even scatter of tufts at full density. The
## grass shader reads the terrain texture to decide, per tuft, how high to
## stand it and whether it grows at all, so sculpting and painting move and
## thin the lawn without rebuilding anything here.

const IslandData := preload("res://scripts/island_data.gd")
const SPACING := 0.1

static var _clump: ArrayMesh


static func build_tile(ti: int, tj: int, material: Material) -> MultiMeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + tj * 97 + ti
	var span: float = IslandData.TILE * IslandData.CELL
	var x0: float = -IslandData.SIZE * 0.5 + ti * span
	var z0: float = -IslandData.SIZE * 0.5 + tj * span
	var n := int(round(span / SPACING))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	if _clump == null:
		_clump = _clump_mesh()
	mm.mesh = _clump
	mm.instance_count = n * n
	var k := 0
	for j in n:
		for i in n:
			var x := x0 + (i + rng.randf()) * SPACING
			var z := z0 + (j + rng.randf()) * SPACING
			var basis := Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(rng.randf_range(0.8, 1.2), 1.0, rng.randf_range(0.8, 1.2)))
			mm.set_instance_transform(k, Transform3D(basis, Vector3(x, 0.0, z)))
			# root position, chance to grow, and height variation
			mm.set_instance_custom_data(k, Color(x, z, rng.randf(), rng.randf()))
			k += 1
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.custom_aabb = AABB(Vector3(x0, IslandData.MIN_HEIGHT - 1.0, z0), Vector3(span, IslandData.MAX_HEIGHT - IslandData.MIN_HEIGHT + 2.0, span))
	return node


## A tuft of six tapered blades leaning outward. uv.y is height along the
## blade, colour.r a per-blade shade so the tuft is not one flat green.
static func _clump_mesh() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var verts := PackedVector3Array()
	var nrm := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var idx := PackedInt32Array()
	for b in 6:
		var ang := rng.randf() * TAU
		var radial := Vector3(cos(ang), 0.0, sin(ang))
		var off := radial * rng.randf_range(0.0, 0.06)
		var lean := radial * rng.randf_range(0.04, 0.13)
		var face := ang + PI * 0.5 + rng.randf_range(-0.6, 0.6)
		var side := Vector3(cos(face), 0.0, sin(face))
		var h := rng.randf_range(0.16, 0.3)
		var w := rng.randf_range(0.024, 0.036)
		var shade := rng.randf()
		var up := (lean.normalized() * 0.4 + Vector3.UP).normalized()
		var base := verts.size()
		for k in 3:
			var t := k / 3.0
			var c := off + Vector3(0.0, h * t, 0.0) + lean * t * t
			var half := w * (1.0 - t * 0.7) * 0.5
			verts.append(c - side * half)
			verts.append(c + side * half)
			uvs.append(Vector2(0.0, t))
			uvs.append(Vector2(1.0, t))
		verts.append(off + Vector3(0.0, h, 0.0) + lean)
		uvs.append(Vector2(0.5, 1.0))
		for k in 7:
			nrm.append(up)
			colors.append(Color(shade, 0.0, 0.0))
		for k in 2:
			var a := base + 2 * k
			idx.append_array([a, a + 2, a + 1, a + 1, a + 2, a + 3])
		idx.append_array([base + 4, base + 6, base + 5])
	var mesh := ArrayMesh.new()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_INDEX] = idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh
