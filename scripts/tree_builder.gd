extends RefCounted
## A broadleaf tree grown from a seed: a flared, curving trunk that forks
## twice, and fluffy leaf clouds at the branch tips. The leaves are many small
## alpha-cut cards whose normals point out from their cloud's centre, which is
## what makes the canopy light like one soft shape instead of a thousand flat
## quads.

const MeshUtil := preload("res://scripts/mesh_util.gd")

static var _bark_normal: ImageTexture


static func build(ground: Vector3, seed: int) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var bark := {"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array(), "i": PackedInt32Array()}
	var tips := []
	_branch(bark, rng, Vector3(0.0, -0.45, 0.0), Vector3(0.08, 1.0, 0.03).normalized(), 2.5, 0.4, 0, tips)
	_fill_canopy(tips)

	var root := Node3D.new()
	root.position = ground

	var trunk_mesh := ArrayMesh.new()
	MeshUtil.add_surface(trunk_mesh, bark.v, bark.n, bark.uv, PackedColorArray(), bark.i)
	var trunk := MeshInstance3D.new()
	trunk.mesh = trunk_mesh
	var bark_mat := ShaderMaterial.new()
	bark_mat.shader = load("res://shaders/bark.gdshader")
	if _bark_normal == null:
		var img := Image.load_from_file(ProjectSettings.globalize_path("res://assets/quaternius/Bark_NormalTree_Normal.png"))
		if img:
			img.generate_mipmaps()
			_bark_normal = ImageTexture.create_from_image(img)
	if _bark_normal:
		bark_mat.set_shader_parameter("normal_tex", _bark_normal)
		bark_mat.set_shader_parameter("has_normal", true)
	trunk.material_override = bark_mat
	root.add_child(trunk)
	trunk.set_instance_shader_parameter("ground_y", ground.y)

	var leaves := MeshInstance3D.new()
	leaves.mesh = _leaf_mesh(rng, tips)
	var leaf_mat := ShaderMaterial.new()
	leaf_mat.shader = load("res://shaders/leaves.gdshader")
	leaves.material_override = leaf_mat
	root.add_child(leaves)

	# a dark core in each leaf cloud, so gaps between cards show shade
	# instead of sky
	var core_mat := StandardMaterial3D.new()
	core_mat.albedo_color = Color(0.1, 0.2, 0.07)
	core_mat.roughness = 1.0
	for tip in tips:
		var sphere := SphereMesh.new()
		sphere.radius = tip[1] * 0.62
		sphere.height = tip[1] * 1.1
		sphere.radial_segments = 16
		sphere.rings = 8
		var core := MeshInstance3D.new()
		core.mesh = sphere
		core.material_override = core_mat
		core.position = tip[0]
		root.add_child(core)
	return root


static func _branch(b: Dictionary, rng: RandomNumberGenerator, start: Vector3, dir: Vector3,
		length: float, radius: float, depth: int, tips: Array) -> void:
	var segs := 6
	var pts: Array[Vector3] = [start]
	var radii: Array[float] = [radius]
	var p := start
	var d := dir
	for s in segs:
		var wander := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.2, 0.5), rng.randf_range(-1.0, 1.0))
		d = (d + wander * 0.09).normalized()
		p += d * length / segs
		pts.append(p)
		radii.append(radius * lerpf(1.0, 0.6, float(s + 1) / segs))
	_tube(b, pts, radii, depth == 0)
	if depth >= 3:
		tips.append([p + d * 0.2, rng.randf_range(1.0, 1.3)])
		return
	var kids := 3 if depth == 0 else 2
	var spin := rng.randf() * TAU
	for c in kids:
		var a := spin + TAU * c / kids + rng.randf_range(-0.3, 0.3)
		var out := Vector3(cos(a), 0.0, sin(a))
		var cd := (d * 0.5 + out * 0.75 + Vector3(0.0, 0.35, 0.0)).normalized()
		_branch(b, rng, pts[-1] - d * 0.08, cd, length * rng.randf_range(0.6, 0.75), radii[-1] * 0.9, depth + 1, tips)
	if depth == 2:
		tips.append([p + Vector3(0.0, 0.3, 0.0), rng.randf_range(0.8, 1.0)])


## Branch tips alone leave a dent in the middle of the crown. Add leaf clouds
## at the centre and just above it, so the crown reads as one rounded mass.
static func _fill_canopy(tips: Array) -> void:
	var centre := Vector3.ZERO
	var r := 0.0
	for tip in tips:
		centre += tip[0]
		r += tip[1]
	centre /= tips.size()
	r /= tips.size()
	tips.append([centre + Vector3(0.0, 0.7, 0.0), r * 1.35])
	tips.append([centre + Vector3(0.0, -0.1, 0.0), r * 1.2])


## Rings along a polyline. The trunk's lowest rings flare into root buttresses.
static func _tube(b: Dictionary, pts: Array[Vector3], radii: Array[float], flare: bool) -> void:
	var sides := 10
	var n := pts.size()
	var base: int = b.v.size()
	var t0 := (pts[1] - pts[0]).normalized()
	var u := t0.cross(Vector3.RIGHT if absf(t0.x) < 0.9 else Vector3.UP).normalized()
	for k in n:
		var t := (pts[mini(k + 1, n - 1)] - pts[maxi(k - 1, 0)]).normalized()
		u = (u - t * u.dot(t)).normalized()
		var v := t.cross(u)
		for s in sides + 1:
			var a := TAU * s / sides
			var r := radii[k]
			if flare and k <= 1:
				var amount := 1.0 if k == 0 else 0.3
				r *= 1.0 + amount * (0.55 + 0.45 * sin(a * 5.0))
			var nrm := u * cos(a) + v * sin(a)
			b.v.append(pts[k] + nrm * r)
			b.n.append(nrm)
			b.uv.append(Vector2(float(s) / sides, float(k)))
	for k in n - 1:
		for s in sides:
			var i0 := base + k * (sides + 1) + s
			var i1 := i0 + 1
			var i2 := i0 + sides + 1
			var i3 := i2 + 1
			b.i.append_array([i0, i2, i1, i1, i2, i3])


static func _leaf_mesh(rng: RandomNumberGenerator, tips: Array) -> ArrayMesh:
	var centre := Vector3.ZERO
	for tip in tips:
		centre += tip[0]
	centre /= tips.size()
	var reach := 0.0
	for tip in tips:
		reach = maxf(reach, (tip[0] as Vector3).distance_to(centre) + tip[1])

	var verts := PackedVector3Array()
	var nrm := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var idx := PackedInt32Array()
	for tip in tips:
		var c: Vector3 = tip[0]
		var r: float = tip[1]
		var count := int(130.0 * r * r)
		for n in count:
			var dir := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
			var p := c + dir * r * sqrt(rng.randf_range(0.3, 1.0))
			p.y = c.y + (p.y - c.y) * 0.8
			var size := rng.randf_range(0.5, 0.75)
			var q := Basis(Quaternion(Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized(), rng.randf() * TAU))
			var ax := q.x * size * 0.5
			var ay := q.y * size * 0.5
			var n_local := (p - c).normalized()
			var n_canopy := (p - centre).normalized()
			var normal := (n_local + n_canopy).normalized()
			# 0 deep inside the canopy, 1 at its sunny outer skin
			var outer := clampf((p.distance_to(centre)) / reach, 0.0, 1.0)
			outer *= 0.6 + 0.4 * smoothstep(-1.0, 1.0, (p.y - centre.y) / reach)
			var col := Color(outer, rng.randf(), 0.0, 1.0)
			var base := verts.size()
			verts.append_array([p - ax - ay, p + ax - ay, p + ax + ay, p - ax + ay])
			uvs.append_array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
			for k in 4:
				nrm.append(normal)
				colors.append(col)
			idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	var mesh := ArrayMesh.new()
	MeshUtil.add_surface(mesh, verts, nrm, uvs, colors, idx)
	return mesh
