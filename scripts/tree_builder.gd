extends RefCounted
## Trees, generated from a style, after the parametric model of Weber and
## Penn ("Creation and Rendering of Realistic Trees", 1995), the model
## behind Blender's Sapling add-on, simplified for a stylized look:
##
##   the trunk rises with a little lean and as crooked as Krokighet asks;
##   main branches leave it from Stambas up, spaced round it by the golden
##   angle (137.5 degrees), each at Grenvinkel from the trunk;
##   how long a main branch is depends on where it sits, after the crown
##   shape: long low down for a spruce, long in the middle for a round
##   crown, long high up for an umbrella;
##   every branch splits again, Förgrening times over, each generation
##   Grenlängd as long as the one it grows from.
##
## Leaves are clouds of small alpha-cut cards round the branch tips, their
## normals pointing out from the cloud and the crown, which is what makes a
## crown light like one soft shape (the Quaternius look). A spruce gets
## flat, drooping tiers of needles along its branches instead.
##
## A tree knows what stands round it (env): `top` gives the height of a
## stone, wall or pillar under a point, and the trunk and every branch steer
## round them as they grow, so a tree beside a boulder bends away from it
## instead of growing through it. Trees of one kind planted on top of each
## other grow from a shared foot and lean apart (`lean`, `base`), so their
## crowns run together into one.

const MeshUtil := preload("res://scripts/mesh_util.gd")
const RockBuilder := preload("res://scripts/rock_builder.gd")

const GOLDEN := 2.39996   # radians

static var _bark_normal: ImageTexture


## The tree for a style, `height` metres tall, its foot at the origin.
static func build(style: Dictionary, height: float, seed: int, env := {}) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 7349 + 3
	var g := {"rng": rng, "st": style, "needles": bool(style.get("needles", false)),
		"bark": {"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array(), "i": PackedInt32Array()},
		"clusters": [], "height": height, "top": env.get("top", Callable())}
	var trunk_len := height * (0.92 if g.needles else 0.6)
	var lean := Vector3(rng.randfn(), 0.0, rng.randfn()) * 0.08 * (1.0 - float(style.crown) * 0.5)
	# a merged neighbour of the same kind: lean away from it
	lean += (env.get("lean", Vector3.ZERO) as Vector3) * 0.75
	var foot: Vector3 = Vector3(0.0, -0.3, 0.0) + (env.get("base", Vector3.ZERO) as Vector3)
	_branch(g, 0, foot, (Vector3.UP + lean).normalized(), trunk_len + 0.3, float(style.trunk) * height / 6.0)
	_lift_clusters(g)
	if g.needles and float(style.leaves) > 0.01:
		# the spire: a last tuft at the very top
		g.clusters.append([Vector3(0.0, trunk_len + 0.1, 0.0), float(style.leaf_size) * 0.4, Vector3.UP, 1.6])

	var root := Node3D.new()
	var trunk := MeshInstance3D.new()
	var bm := ArrayMesh.new()
	MeshUtil.add_surface(bm, g.bark.v, g.bark.n, g.bark.uv, PackedColorArray(), g.bark.i)
	trunk.mesh = bm
	trunk.material_override = _bark_material()
	var b: Array = style.bark_color
	trunk.set_instance_shader_parameter("bark", Vector3(b[0], b[1], b[2]))
	root.add_child(trunk)

	if float(style.leaves) > 0.01 and not (g.clusters as Array).is_empty():
		var leaves := MeshInstance3D.new()
		leaves.mesh = _leaf_mesh(g)
		var lm := ShaderMaterial.new()
		lm.shader = load("res://shaders/leaves.gdshader")
		leaves.material_override = lm
		var c: Array = style.leaf_color
		leaves.set_instance_shader_parameter("leaf_color", Vector3(c[0], c[1], c[2]))
		leaves.set_instance_shader_parameter("needles", 1.0 if g.needles else 0.0)
		root.add_child(leaves)
	# fruit, berries or blossom on the crown's skin
	var fruit := float(style.get("fruit", 0.0))
	if fruit > 0.01 and not g.needles and not (g.clusters as Array).is_empty():
		var fm := MeshInstance3D.new()
		fm.mesh = _fruit_mesh(g, fruit, float(style.get("fruit_size", 1.0)), bool(style.get("blossom", false)))
		var mat := StandardMaterial3D.new()
		var fc: Array = style.get("fruit_color", [0.8, 0.12, 0.1])
		mat.albedo_color = Color(fc[0], fc[1], fc[2])
		mat.roughness = 0.5 if not style.get("blossom", false) else 0.85
		if style.get("blossom", false):
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mat.backlight_enabled = true
			mat.backlight = Color(fc[0], fc[1], fc[2]) * 0.5
		fm.material_override = mat
		root.add_child(fm)
	return root


static func _bark_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/bark.gdshader")
	if _bark_normal == null:
		var img := Image.load_from_file(ProjectSettings.globalize_path("res://assets/quaternius/Bark_NormalTree_Normal.png"))
		if img:
			img.generate_mipmaps()
			_bark_normal = ImageTexture.create_from_image(img)
	if _bark_normal:
		mat.set_shader_parameter("normal_tex", _bark_normal)
		mat.set_shader_parameter("has_normal", true)
	return mat


## How long a main branch is at height t (0 at the trunk's foot, 1 at its
## top), after the crown shape: 0 a spruce's cone, 0.5 round, 1 an umbrella.
static func _crown(t: float, crown: float) -> float:
	var x := clampf(t, 0.0, 1.0)
	var cone := 1.0 - x * 0.9
	var round := 0.3 + 0.7 * sin(PI * x)
	var umbrella := 0.2 + 0.8 * pow(x, 0.6)
	if crown < 0.5:
		return lerpf(cone, round, crown * 2.0)
	return lerpf(round, umbrella, (crown - 0.5) * 2.0)


static func _branch(g: Dictionary, level: int, start: Vector3, dir: Vector3, length: float, radius: float) -> void:
	var rng: RandomNumberGenerator = g.rng
	var st: Dictionary = g.st
	var bend: float = st.bend
	var levels: int = int(st.levels)
	var segs := 10 if level == 0 else maxi(3, 7 - level * 2)
	var pts: Array[Vector3] = [start]
	var radii: Array[float] = [radius]
	var p := start
	var d := dir
	var tip_ratio := 0.15 if level == 0 else 0.3
	for s in segs:
		var wander := Vector3(rng.randfn(), rng.randfn() * 0.4, rng.randfn()) * (0.03 + 0.22 * bend)
		if level == 0:
			d = (d + wander * (0.15 if g.needles else 0.6) + Vector3.UP * 0.06).normalized()
		elif g.needles:
			# spruce boughs droop toward their tips
			d = (d + wander * 0.3 + Vector3.DOWN * 0.07).normalized()
		else:
			# branches reach up toward the light as they grow
			d = (d + wander + Vector3.UP * (0.09 - bend * 0.05)).normalized()
		var r_here := radius * lerpf(1.0, tip_ratio, float(s + 1) / segs)
		if (g.top as Callable).is_valid():
			# steer round stones and walls: away from any that stand beside the
			# next step, up and out of any it would grow into
			var push := _avoid(g.top, p + d * length / segs, r_here + 0.2)
			if push != Vector3.ZERO:
				d = (d + push * (0.7 if level == 0 else 1.0)).normalized()
			elif level == 0:
				# clear of it: the trunk straightens up again, as a tree does
				d = (d + Vector3.UP * 0.45).normalized()
		p += d * length / segs
		pts.append(p)
		radii.append(r_here)
	_tube(g.bark, pts, radii, level == 0)

	var leafy := float(st.leaves) > 0.01
	if g.needles and level == 1 and leafy:
		# a tier of needles along the bough, smaller toward its tip
		var count := maxi(2, int(length / (0.22 * float(st.leaf_size))))
		for k in count:
			var u := (k + 0.5) / count
			g.clusters.append([_along(pts, u) + Vector3.DOWN * 0.05, float(st.leaf_size) * 0.7 * lerpf(1.1, 0.6, u), d, 0.5])
	if level >= levels:
		if leafy and not g.needles:
			var r := float(st.leaf_size) * (0.55 + 0.25 * rng.randf()) * clampf(length / 1.2, 0.7, 1.3)
			g.clusters.append([p + d * 0.15, r, d, 1.0])
		return

	var kids := int(st.branches) if level == 0 else maxi(2, int(round(float(st.branches) * 0.5)))
	var from: float = float(st.branch_start) if level == 0 else 0.3
	var spin := rng.randf() * TAU
	var height: float = g.height
	for k in kids:
		var t := lerpf(from, 0.97, (k + rng.randf_range(0.2, 0.8)) / kids)
		var at := _along(pts, t)
		var r_at := lerpf(radius, radius * tip_ratio, t)
		var az := spin + k * GOLDEN + rng.randf_range(-0.3, 0.3)
		var down := deg_to_rad(float(st.angle) + rng.randf_range(-8.0, 8.0))
		if g.needles and level == 0:
			# low boughs spread flatter, high ones point up a little
			down = deg_to_rad(float(st.angle) + (0.4 - t) * 25.0)
		var cd := (d * cos(down) + _perpendicular(d, az) * sin(down)).normalized()
		var cl: float
		if level == 0:
			# main branches measured against the whole height
			cl = height * 0.62 * float(st.branch_len) * _crown(t, float(st.crown))
		else:
			cl = length * float(st.branch_len) * (1.0 - 0.5 * t)
		cl *= rng.randf_range(0.85, 1.1)
		if cl < 0.12:
			continue
		var cr := r_at * lerpf(0.72, 0.45, t)
		_branch(g, level + 1, at - d * 0.04, cd, cl, cr)
	if leafy and not g.needles and level == levels - 1 and float(st.leaves) > 0.55:
		# fuller crowns: leaves on the branch itself as well as its twigs
		g.clusters.append([_along(pts, 0.8), float(st.leaf_size) * 0.6, d, 0.8])


## Which way to turn at q to keep clear of whatever stands round it: away
## from probes, `reach` and twice that out, that meet something taller than
## q; and upward if q itself is inside something.
static func _avoid(top: Callable, q: Vector3, reach: float) -> Vector3:
	var push := Vector3.ZERO
	for k in 8:
		var a := TAU * k / 8.0
		var dir := Vector3(cos(a), 0.0, sin(a))
		for ring in [1.0, 2.0]:
			var p: Vector3 = q + dir * reach * float(ring)
			var h: float = top.call(p)
			if h > q.y - 0.1:
				push -= dir * (1.0 / float(ring))
	var here: float = top.call(q)
	if here > q.y - 0.05:
		push += Vector3.UP * 1.5
	return push.limit_length(2.0) * 0.6


## Leaf clouds that ended up in a stone or a wall rise out of it.
static func _lift_clusters(g: Dictionary) -> void:
	if not (g.top as Callable).is_valid():
		return
	for cl in g.clusters:
		var c: Vector3 = cl[0]
		var r: float = cl[1]
		var h: float = (g.top as Callable).call(c)
		if h > c.y - r * 0.6:
			cl[0] = Vector3(c.x, h + r * 0.6, c.z)


static func _along(pts: Array[Vector3], t: float) -> Vector3:
	var x := clampf(t, 0.0, 1.0) * (pts.size() - 1)
	var i := mini(int(x), pts.size() - 2)
	return pts[i].lerp(pts[i + 1], x - i)


## A unit vector at right angles to d, turned `az` round it.
static func _perpendicular(d: Vector3, az: float) -> Vector3:
	var u := d.cross(Vector3.RIGHT if absf(d.x) < 0.9 else Vector3.FORWARD).normalized()
	var v := d.cross(u)
	return (u * cos(az) + v * sin(az)).normalized()


## Rings along a polyline. The trunk's lowest rings flare into root buttresses.
static func _tube(b: Dictionary, pts: Array[Vector3], radii: Array[float], flare: bool) -> void:
	var sides := 10 if flare else 7
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


## Leaf cards round every cluster: [centre, radius, branch direction, roundness].
static func _leaf_mesh(g: Dictionary) -> ArrayMesh:
	var rng: RandomNumberGenerator = g.rng
	var st: Dictionary = g.st
	var clusters: Array = g.clusters
	var centre := Vector3.ZERO
	for c in clusters:
		centre += c[0]
	centre /= clusters.size()
	var reach := 0.01
	for c in clusters:
		reach = maxf(reach, (c[0] as Vector3).distance_to(centre) + float(c[1]))
	# as many cards as Lövmängd asks for, at most a few thousand a tree
	var want := 0.0
	for c in clusters:
		want += 130.0 * float(c[1]) * float(c[1])
	var per := float(st.leaves) * minf(1.0, 3500.0 / maxf(want * float(st.leaves), 1.0))

	var verts := PackedVector3Array()
	var nrm := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var idx := PackedInt32Array()
	for cl in clusters:
		var c: Vector3 = cl[0]
		var r: float = cl[1]
		var flat: float = cl[3]
		var count := int(130.0 * r * r * per) + 1
		for n in count:
			var dir := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
			var p := c + dir * r * sqrt(rng.randf_range(0.3, 1.0))
			p.y = c.y + (p.y - c.y) * 0.8 * flat
			var size := rng.randf_range(0.7, 1.0) * clampf(r * 1.3, 0.5, 1.3)
			var q := Basis(Quaternion(Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized(), rng.randf() * TAU))
			if g.needles:
				# needle sprays lie flat along the bough
				q = Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(0.5, 1.2) * (1.0 if rng.randf() < 0.5 else -1.0))
			var ax := q.x * size * 0.5
			var ay := q.y * size * 0.5
			var n_local := (p - c).normalized()
			var n_canopy := (p - centre).normalized()
			var normal := (n_local + n_canopy).normalized()
			if g.needles:
				normal = (normal + Vector3.UP * 1.5).normalized()
			# 0 deep inside the crown, 1 at its sunny outer skin
			var outer := clampf(p.distance_to(centre) / reach, 0.0, 1.0)
			outer *= 0.6 + 0.4 * smoothstep(-1.0, 1.0, (p.y - centre.y) / reach)
			if g.needles:
				outer = clampf(0.35 + (p.y - c.y) * 2.0 + n_local.length() * 0.3, 0.0, 1.0)
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


## Fruit or blossom: small balls (or flat five-petalled flowers) set into
## the outer skin of the leaf clouds, more on the sunny outside.
static func _fruit_mesh(g: Dictionary, amount: float, size: float, blossom: bool) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(g.rng.seed) + 77
	var ico: Array = RockBuilder._icosphere(1)
	var unit: PackedVector3Array = ico[0]
	var tri: PackedInt32Array = ico[1]
	var verts := PackedVector3Array()
	var nrm := PackedVector3Array()
	var idx := PackedInt32Array()
	var centre := Vector3.ZERO
	for cl in g.clusters:
		centre += cl[0]
	centre /= g.clusters.size()
	for cl in g.clusters:
		var c: Vector3 = cl[0]
		var r: float = cl[1]
		var count := int(amount * (2.0 + r * 5.0) * (3.0 if blossom else 1.0) + rng.randf())
		for n in count:
			var dir := Vector3(rng.randfn(), rng.randfn() * 0.7 - 0.2, rng.randfn()).normalized()
			# prefer the side facing out of the crown
			if dir.dot((c - centre).normalized()) < -0.3:
				dir = -dir
			var at := c + dir * r * rng.randf_range(0.82, 1.0)
			var fr := (0.06 if blossom else 0.11) * size * rng.randf_range(0.8, 1.2)
			var base := verts.size()
			if blossom:
				# a flat flower facing out: five petals round a disc
				var b := Basis.looking_at(-dir, Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT)
				verts.append(at)
				nrm.append(dir)
				for p in 10:
					var a := TAU * p / 10.0
					var rr := fr * (1.0 if p % 2 == 0 else 0.45)
					verts.append(at + b * (Vector3(cos(a), sin(a), 0.0) * rr))
					nrm.append(dir)
				for p in 10:
					idx.append_array([base, base + 1 + p, base + 1 + (p + 1) % 10])
			else:
				for v in unit:
					verts.append(at + Vector3(v.x, v.y * 0.9, v.z) * fr)
					nrm.append(v)
				for i in tri:
					idx.append(base + i)
	var mesh := ArrayMesh.new()
	if idx.is_empty():
		return mesh
	MeshUtil.add_surface(mesh, verts, nrm, PackedVector2Array(), PackedColorArray(), idx)
	return mesh
