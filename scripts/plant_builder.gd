extends RefCounted
## Things the kit does not have, built in code: reeds with cattails, water
## lilies, and koi. Sizes are real-world, about one meter of reeds.

const MeshUtil := preload("res://scripts/mesh_util.gd")


class Builder:
	var verts := PackedVector3Array()
	var nrm := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var idx := PackedInt32Array()

	func add(p: Vector3, n: Vector3, uv: Vector2, c: Color) -> int:
		verts.append(p)
		nrm.append(n)
		uvs.append(uv)
		colors.append(c)
		return verts.size() - 1



static func _mesh(b: Builder) -> ArrayMesh:
	var m := ArrayMesh.new()
	MeshUtil.add_surface(m, b.verts, b.nrm, b.uvs, b.colors, b.idx)
	return m


static func _lin(r: float, g: float, b: float, a := 1.0) -> Color:
	return Color(pow(r, 2.2), pow(g, 2.2), pow(b, 2.2), a)


## A tapered strip from `base` rising `h`, leaning along `lean`, `rows` long.
static func _blade(b: Builder, base: Vector3, h: float, w: float, lean: Vector3, side: Vector3, col: Color, rows := 5) -> void:
	var first := b.verts.size()
	var up := (Vector3.UP + lean.normalized() * 0.3).normalized()
	for r in rows:
		var t := float(r) / (rows - 1)
		var c := base + Vector3(0.0, h * t, 0.0) + lean * t * t
		var half := w * (1.0 - t * 0.85) * 0.5
		b.add(c - side * half, up, Vector2(0.0, t), col)
		b.add(c + side * half, up, Vector2(1.0, t), col)
	for r in rows - 1:
		var a := first + r * 2
		b.idx.append_array([a, a + 2, a + 1, a + 1, a + 2, a + 3])


static func reeds(seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var b := Builder.new()
	for k in rng.randi_range(12, 18):
		var ang := rng.randf() * TAU
		var radial := Vector3(cos(ang), 0.0, sin(ang))
		var base := radial * rng.randf_range(0.0, 0.14)
		var h := rng.randf_range(0.6, 1.15)
		var lean := radial * rng.randf_range(0.05, 0.25) * h
		var face := ang + PI * 0.5 + rng.randf_range(-0.5, 0.5)
		var side := Vector3(cos(face), 0.0, sin(face))
		var col := _lin(0.30, 0.44, 0.14).lerp(_lin(0.50, 0.58, 0.22), rng.randf())
		_blade(b, base, h, rng.randf_range(0.02, 0.035), lean, side, col)
	# cattails: a stem and a brown velvet head near the top
	for k in rng.randi_range(2, 4):
		var ang := rng.randf() * TAU
		var radial := Vector3(cos(ang), 0.0, sin(ang))
		var base := radial * rng.randf_range(0.0, 0.1)
		var h := rng.randf_range(0.85, 1.2)
		var lean := radial * rng.randf_range(0.02, 0.08)
		var side := Vector3(-radial.z, 0.0, radial.x)
		_blade(b, base, h, 0.012, lean, side, _lin(0.42, 0.48, 0.2), 4)
		var head := base + Vector3(0.0, h * 0.82, 0.0) + lean * 0.67
		var brown := _lin(0.36, 0.22, 0.12)
		var first := b.verts.size()
		for ring in 2:
			for s in 8:
				var a := TAU * s / 8.0
				var n := Vector3(cos(a), 0.0, sin(a))
				b.add(head + n * 0.022 + Vector3(0.0, ring * 0.13, 0.0), n, Vector2(0.0, 0.8 + ring * 0.1), brown)
		for s in 8:
			var a0 := first + s
			var a1 := first + (s + 1) % 8
			b.idx.append_array([a0, a0 + 8, a1, a1, a0 + 8, a1 + 8])
	return _mesh(b)


## A lily pad with its notch, about 1 m across (scale it down), and maybe a
## flower. Colour alpha marks the pad (1) from the flower (0).
static func lily(seed: int, flower: bool) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var b := Builder.new()
	var green := _lin(0.28, 0.48, 0.16).lerp(_lin(0.40, 0.55, 0.18), rng.randf())
	var centre := b.add(Vector3(0.0, 0.0, 0.0), Vector3.UP, Vector2.ZERO, green)
	var notch := 0.32
	var segs := 26
	for s in segs + 1:
		var a := notch + (TAU - 2.0 * notch) * s / segs
		var r := 0.5 * (1.0 + 0.04 * sin(a * 5.0 + rng.randf()))
		b.add(Vector3(cos(a) * r, 0.025, sin(a) * r), Vector3.UP, Vector2(0.0, 0.0), green)
	for s in segs:
		b.idx.append_array([centre, centre + 1 + s, centre + 2 + s])
	if flower:
		var petal := _lin(0.96, 0.78, 0.84) if rng.randf() < 0.6 else _lin(0.97, 0.95, 0.92)
		petal.a = 0.0
		var heart := _lin(0.98, 0.82, 0.25, 0.0)
		var at := Vector3(rng.randf_range(-0.12, 0.12), 0.03, rng.randf_range(-0.12, 0.12))
		for layer in 2:
			var count := 8
			for k in count:
				var a := TAU * (k + layer * 0.5) / count
				var dir := Vector3(cos(a), 0.0, sin(a))
				var side := Vector3(-dir.z, 0.0, dir.x)
				var tilt := 0.9 - layer * 0.35
				var tip := at + (dir * cos(tilt) + Vector3.UP * sin(tilt)) * (0.17 - layer * 0.04)
				var n := (Vector3.UP - dir * 0.5).normalized()
				var i0 := b.add(at, n, Vector2(0.0, 0.0), petal)
				var i1 := b.add(at + dir * 0.05 + side * 0.04 + Vector3(0.0, 0.03, 0.0), n, Vector2(0.0, 0.5), petal)
				var i2 := b.add(tip, n, Vector2(0.0, 1.0), petal)
				var i3 := b.add(at + dir * 0.05 - side * 0.04 + Vector3(0.0, 0.03, 0.0), n, Vector2(0.0, 0.5), petal)
				b.idx.append_array([i0, i1, i2, i0, i2, i3])
		var h0 := b.add(at + Vector3(0.0, 0.05, 0.0), Vector3.UP, Vector2.ZERO, heart)
		for k in 6:
			var a := TAU * k / 6.0
			b.add(at + Vector3(cos(a) * 0.03, 0.035, sin(a) * 0.03), Vector3.UP, Vector2.ZERO, heart)
		for k in 6:
			b.idx.append_array([h0, h0 + 1 + k, h0 + 1 + (k + 1) % 6])
	return _mesh(b)


## A small koi, nose toward +z, about 22 cm long.
static func fish() -> ArrayMesh:
	var b := Builder.new()
	var rings := 9
	var sides := 10
	var z0 := -0.12
	var z1 := 0.1
	for r in rings:
		var t := float(r) / (rings - 1)
		var z := lerpf(z0, z1, t)
		# widest a little ahead of the middle, pointed at the nose, thin at the tail
		var radius := sin(pow(t, 0.8) * PI) * 0.032 + 0.004
		for s in sides:
			var a := TAU * s / sides
			var n := Vector3(cos(a) * 0.8, sin(a), 0.0).normalized()
			b.add(Vector3(cos(a) * radius * 0.75, sin(a) * radius, z), n, Vector2(t, 0.0), Color.WHITE)
	for r in rings - 1:
		for s in sides:
			var a0 := r * sides + s
			var a1 := r * sides + (s + 1) % sides
			b.idx.append_array([a0, a1, a0 + sides, a1, a1 + sides, a0 + sides])
	# a forked tail fin in the vertical plane
	var root := b.add(Vector3(0.0, 0.0, z0 + 0.005), Vector3.RIGHT, Vector2.ZERO, Color.WHITE)
	var top := b.add(Vector3(0.0, 0.045, z0 - 0.07), Vector3.RIGHT, Vector2.ZERO, Color.WHITE)
	var mid := b.add(Vector3(0.0, 0.0, z0 - 0.045), Vector3.RIGHT, Vector2.ZERO, Color.WHITE)
	var bottom := b.add(Vector3(0.0, -0.045, z0 - 0.07), Vector3.RIGHT, Vector2.ZERO, Color.WHITE)
	b.idx.append_array([root, top, mid, root, mid, bottom])
	return _mesh(b)
