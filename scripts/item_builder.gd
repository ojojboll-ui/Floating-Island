extends RefCounted
## Small things for the island, generated: lights (fire pit, torch, candles,
## lantern), camp gear (tent, backpack, chest, pot, picnic blanket),
## tools (spade, pick, axe in a chopping block), odds and ends (bottles,
## books, mushroom basket, barrel, woodpile, sign), and dead wood (a fallen,
## rotting log and an old stump).
##
## Each is put together from simple rounded shapes in the chunky, stylized
## way of low-poly camping packs, merged into one mesh. Vertex colour says
## what colour a part takes (alpha, read by item.gdshader): its own baked
## colour, the style's first or second colour, or a warm glow. Flames are
## animated cards (flame.gdshader) with a flickering light.
##
## Everything is built at real size for size 1 and stands on y = 0.

const MeshUtil := preload("res://scripts/mesh_util.gd")
const TreeBuilder := preload("res://scripts/tree_builder.gd")
const WoodBuilder := preload("res://scripts/wood_builder.gd")

## Vertex alpha: which colour a part takes.
const FIXED := 1.0
const COL_A := 0.75
const COL_B := 0.5
const GLOW := 0.25

static var _item_mat: ShaderMaterial
static var _flame_mat: ShaderMaterial


class Kit:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var i := PackedInt32Array()

	## A primitive mesh, placed by xf, in colour col (alpha picks the slot).
	func add(prim: PrimitiveMesh, xf: Transform3D, col: Color) -> void:
		var arr := prim.get_mesh_arrays()
		var pv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var pn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var pi: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var base := v.size()
		var nb := xf.basis.inverse().transposed()
		for k in pv.size():
			v.append(xf * pv[k])
			n.append((nb * pn[k]).normalized())
			c.append(col)
		for k in pi:
			i.append(base + k)

	func box(size: Vector3, xf: Transform3D, col: Color) -> void:
		var m := BoxMesh.new()
		m.size = size
		add(m, xf, col)

	func cyl(r_top: float, r_bot: float, h: float, xf: Transform3D, col: Color, sides := 10) -> void:
		var m := CylinderMesh.new()
		m.top_radius = r_top
		m.bottom_radius = r_bot
		m.height = h
		m.radial_segments = sides
		m.rings = 1
		add(m, xf, col)

	func ball(r: float, xf: Transform3D, col: Color, segs := 10) -> void:
		var m := SphereMesh.new()
		m.radius = r
		m.height = r * 2.0
		m.radial_segments = segs
		m.rings = maxi(4, segs / 2)
		add(m, xf, col)

	func ring(inner: float, outer: float, xf: Transform3D, col: Color) -> void:
		var m := TorusMesh.new()
		m.inner_radius = inner
		m.outer_radius = outer
		m.rings = 16
		m.ring_segments = 6
		add(m, xf, col)

	## A rod from a to b.
	func rod(a: Vector3, b: Vector3, r: float, col: Color, sides := 6) -> void:
		var d := b - a
		var up := d.normalized()
		var side := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
		var bs := Basis(side, up, side.cross(up))
		cyl(r, r, d.length(), Transform3D(bs, (a + b) * 0.5), col, sides)

	## A tapering rod from a (radius ra) to b (radius rb).
	func cone(a: Vector3, b: Vector3, ra: float, rb: float, col: Color, sides := 8) -> void:
		var d := b - a
		var up := d.normalized()
		var side := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
		var bs := Basis(side, up, side.cross(up))
		cyl(rb, ra, d.length(), Transform3D(bs, (a + b) * 0.5), col, sides)

	## A flat plate: an outline in its own x-y plane, `thick` deep in z,
	## bowed by `cup` (the middle pushed back), placed by xf.
	func slab(outline: PackedVector2Array, thick: float, cup: float, xf: Transform3D, col: Color) -> void:
		var n_out := outline.size()
		var half := thick * 0.5
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for p in outline:
			lo = lo.min(p)
			hi = hi.max(p)
		var mid := (lo + hi) * 0.5
		var w := maxf(hi.x - lo.x, 0.001) * 0.5
		var bow := func(p: Vector2) -> float:
			var t := (p.x - mid.x) / w
			return cup * (1.0 - t * t)
		var nb := xf.basis.inverse().transposed()
		var centre := Vector2.ZERO
		for p in outline:
			centre += p
		centre /= n_out
		for face in [1.0, -1.0]:
			var c0 := v.size()
			v.append(xf * Vector3(centre.x, centre.y, face * half - bow.call(centre)))
			n.append((nb * Vector3(0, 0, face)).normalized())
			c.append(col)
			for p in outline:
				v.append(xf * Vector3(p.x, p.y, face * half - bow.call(p)))
				n.append((nb * Vector3(0, 0, face)).normalized())
				c.append(col)
			for k2 in n_out:
				var a := c0 + 1 + k2
				var b2 := c0 + 1 + (k2 + 1) % n_out
				if face > 0.0:
					i.append_array([c0, a, b2])
				else:
					i.append_array([c0, b2, a])
		# the rim
		for k2 in n_out:
			var p0 := outline[k2]
			var p1 := outline[(k2 + 1) % n_out]
			var edge := (p1 - p0).normalized()
			var nrm := (nb * Vector3(edge.y, -edge.x, 0)).normalized()
			var base := v.size()
			for q in [[p0, half], [p1, half], [p1, -half], [p0, -half]]:
				var pp: Vector2 = q[0]
				v.append(xf * Vector3(pp.x, pp.y, float(q[1]) - bow.call(pp)))
				n.append(nrm)
				c.append(col)
			i.append_array([base, base + 2, base + 1, base, base + 3, base + 2])

	## End grain: concentric rings on a disc facing `normal`.
	func rings(at: Vector3, normal: Vector3, r: float, light: Color, dark: Color, count := 4) -> void:
		var up := normal.normalized()
		var side := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
		var other := up.cross(side)
		var sides := 14
		var centre := v.size()
		v.append(at)
		n.append(up)
		c.append(Color(light.r, light.g, light.b, FIXED))
		var prev := []
		for k in sides:
			prev.append(centre)
		for ring_k in range(1, count + 1):
			var t := float(ring_k) / count
			var col := light.lerp(dark, 0.55 if ring_k % 2 == 0 else 0.0)
			if ring_k == count:
				col = dark
			var this := []
			for s in sides:
				var a := TAU * s / sides
				v.append(at + (side * cos(a) + other * sin(a)) * r * t)
				n.append(up)
				c.append(Color(col.r, col.g, col.b, FIXED))
				this.append(v.size() - 1)
			for s in sides:
				var s2 := (s + 1) % sides
				if ring_k == 1:
					i.append_array([centre, this[s2], this[s]])
				else:
					i.append_array([prev[s], this[s2], this[s], prev[s], prev[s2], this[s2]])
			prev = this

	func mesh() -> ArrayMesh:
		var m := ArrayMesh.new()
		if i.is_empty():
			return m
		MeshUtil.add_surface(m, v, n, PackedVector2Array(), c, i)
		return m


static func _fixed(r: float, g: float, b: float) -> Color:
	return Color(r, g, b, FIXED)


static func _a(shade := 1.0) -> Color:
	return Color(shade, shade, shade, COL_A)


static func _b(shade := 1.0) -> Color:
	return Color(shade, shade, shade, COL_B)


static func _glow(shade := 1.0) -> Color:
	return Color(shade, shade, shade, GLOW)


static func _at(p: Vector3, rot := Vector3.ZERO) -> Transform3D:
	return Transform3D(Basis.from_euler(rot), p)


## The node for a style: what (gen), with its colours, glow and extras.
static func build(gen: String, st: Dictionary, seed: int, extra := {}) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 6151 + gen.hash()
	var k := Kit.new()
	# stylized wood (stumps, logs, blocks, piles) goes to its own mesh
	var w := WoodBuilder.Wood.new()
	w.rng.seed = rng.seed + 11
	var root := Node3D.new()
	var flames: Array = []   # [position, height]
	var light := Vector3.INF
	match gen:
		"firepit":
			_firepit(k, rng)
			flames = [[Vector3(0, 0.12, 0), 0.62], [Vector3(0.09, 0.1, 0.05), 0.42], [Vector3(-0.08, 0.1, -0.06), 0.46]]
			light = Vector3(0, 0.5, 0)
		"torch":
			_torch(k, rng)
			flames = [[Vector3(0, 1.4, 0), 0.38]]
			light = Vector3(0, 1.55, 0)
		"candles":
			var tops := _candles(k, rng)
			for t in tops:
				flames.append([t, 0.07])
			light = Vector3(0, 0.3, 0)
		"lantern":
			_lantern(k)
			flames = [[Vector3(0, 0.12, 0), 0.1]]
			light = Vector3(0, 0.2, 0)
		"tent":
			_tent(k, rng)
		"backpack":
			_backpack(k)
		"chest":
			_chest(k)
		"pot":
			_pot(k, bool(extra.get("over_fire", false)))
		"blanket":
			_blanket(k, rng)
		"spade":
			_spade(k)
		"pick":
			_pick(k)
		"axe":
			# lying flat in the grass: edge to the side, handle along the ground
			_axe(k, Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)), Vector3(0, 0.03, 0)))
		"block":
			_block(k, w, rng)
		"bottles":
			_bottles(k, rng)
		"books":
			_books(k, rng)
		"basket":
			_basket(k, rng)
		"barrel":
			_barrel(k)
		"woodpile":
			_woodpile(k, w, rng)
		"logpile":
			_logpile(k, w, rng)
		"sign":
			_sign(k)
		"log":
			_log(k, w, st, rng)
		"stump":
			_stump(k, w, st, rng)
	var body := MeshInstance3D.new()
	body.mesh = k.mesh()
	body.material_override = item_material()
	_colours(body, st)
	root.add_child(body)
	root.set_meta("shaded", body)
	var glow: float = float(st.get("glow", 1.0))
	for f in flames:
		root.add_child(_flame(f[0], f[1]))
	if light != Vector3.INF and glow > 0.01:
		var l := OmniLight3D.new()
		l.position = light
		l.light_color = Color(1.0, 0.62, 0.3)
		l.light_energy = 1.4 * glow
		l.omni_range = 4.5 if gen in ["firepit", "torch"] else 2.6
		l.omni_attenuation = 1.6
		l.shadow_enabled = gen == "firepit"
		l.set_meta("flicker", l.light_energy)
		root.add_child(l)
	var tall := body.mesh.get_aabb().end.y if body.mesh.get_surface_count() > 0 else 0.0
	if not w.empty():
		# dead wood: bark is the first colour, fungi the second; the camp's wood
		# things: cut wood first, bark second
		var dead := gen in ["log", "stump"]
		var bark: Array = st.get("color_a" if dead else "color_b", [0.42, 0.32, 0.24])
		var wood: Array = st.get("wood_color", [0.86, 0.68, 0.45]) if dead else st.get("color_a", [0.86, 0.68, 0.45])
		var wm := WoodBuilder.instance(w, bark, wood, float(st.get("moss", 0.15)))
		root.add_child(wm)
		root.set_meta("shaded", wm)
		tall = maxf(tall, wm.mesh.get_aabb().end.y)
	root.set_meta("tall", maxf(tall, 0.05))
	return root


static func item_material() -> ShaderMaterial:
	if _item_mat == null:
		_item_mat = ShaderMaterial.new()
		_item_mat.shader = load("res://shaders/item.gdshader")
	return _item_mat


static func _colours(gi: GeometryInstance3D, st: Dictionary) -> void:
	var a: Array = st.get("color_a", [0.6, 0.4, 0.3])
	var b: Array = st.get("color_b", [0.5, 0.5, 0.5])
	gi.set_instance_shader_parameter("color_a", Vector3(a[0], a[1], a[2]))
	gi.set_instance_shader_parameter("color_b", Vector3(b[0], b[1], b[2]))
	gi.set_instance_shader_parameter("glow", float(st.get("glow", 1.0)))


static func _flame(at: Vector3, h: float) -> MeshInstance3D:
	if _flame_mat == null:
		_flame_mat = ShaderMaterial.new()
		_flame_mat.shader = load("res://shaders/flame.gdshader")
	var q := QuadMesh.new()
	q.size = Vector2(h * 0.6, h)
	q.center_offset = Vector3(0.0, h * 0.5, 0.0)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = _flame_mat
	mi.position = at
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_instance_shader_parameter("seed", at.x * 13.0 + at.z * 7.0 + h)
	return mi


# --- lights ---------------------------------------------------------------------

static func _firepit(k: Kit, rng: RandomNumberGenerator) -> void:
	for s in 9:
		var a := TAU * s / 9.0 + rng.randf_range(-0.1, 0.1)
		var r := rng.randf_range(0.09, 0.13)
		var g := rng.randf_range(0.42, 0.55)
		k.ball(r, Transform3D(Basis.from_euler(Vector3(0, rng.randf() * TAU, 0)).scaled(Vector3(1.3, 0.75, 1.0)), Vector3(cos(a) * 0.42, r * 0.5, sin(a) * 0.42)), _fixed(g, g, g * 1.03), 8)
	# logs leaning into a little cone
	for s in 4:
		var a := TAU * s / 4.0 + 0.4
		var foot := Vector3(cos(a) * 0.3, 0.03, sin(a) * 0.3)
		k.rod(foot, Vector3(0, 0.3, 0) + foot * 0.15, 0.045, _fixed(0.36, 0.24, 0.16))
	# embers
	k.cyl(0.24, 0.27, 0.04, _at(Vector3(0, 0.02, 0)), _glow(0.9), 12)
	k.cyl(0.33, 0.36, 0.02, _at(Vector3(0, 0.005, 0)), _fixed(0.13, 0.11, 0.1), 12)


static func _torch(k: Kit, rng: RandomNumberGenerator) -> void:
	var lean := Vector3(rng.randf_range(-0.04, 0.04), 1.0, rng.randf_range(-0.04, 0.04)).normalized()
	k.rod(Vector3.ZERO + Vector3.DOWN * 0.15, lean * 1.3, 0.03, _a())
	k.cyl(0.055, 0.045, 0.16, _at(lean * 1.32), _fixed(0.2, 0.15, 0.1))
	k.ring(0.03, 0.05, _at(lean * 1.22), _fixed(0.3, 0.3, 0.32))


static func _candles(k: Kit, rng: RandomNumberGenerator) -> Array:
	var tops: Array = []
	k.cyl(0.17, 0.15, 0.025, _at(Vector3(0, 0.012, 0)), _b(), 14)
	for c in 3:
		var a := TAU * c / 3.0 + rng.randf() * 0.5
		var p := Vector3(cos(a), 0, sin(a)) * 0.07
		var h := rng.randf_range(0.1, 0.24)
		k.cyl(0.03, 0.032, h, _at(p + Vector3(0, 0.025 + h * 0.5, 0)), _a(), 10)
		# a drip of wax down the side
		k.ball(0.012, _at(p + Vector3(0.028, 0.025 + h * 0.75, 0)), _a(0.95), 6)
		tops.append(p + Vector3(0, 0.025 + h + 0.005, 0))
	return tops


static func _lantern(k: Kit) -> void:
	var metal := _a()
	k.cyl(0.11, 0.12, 0.04, _at(Vector3(0, 0.02, 0)), metal, 6)
	k.cyl(0.085, 0.085, 0.22, _at(Vector3(0, 0.15, 0)), _glow(0.75), 6)
	for s in 6:
		var a := TAU * s / 6.0 + TAU / 12.0
		k.rod(Vector3(cos(a) * 0.095, 0.03, sin(a) * 0.095), Vector3(cos(a) * 0.095, 0.27, sin(a) * 0.095), 0.009, metal, 4)
	k.cyl(0.02, 0.13, 0.1, _at(Vector3(0, 0.32, 0)), metal, 6)
	k.ring(0.035, 0.05, _at(Vector3(0, 0.41, 0), Vector3(PI * 0.5, 0, 0)), metal)


# --- camp ----------------------------------------------------------------------

static func _tent(k: Kit, rng: RandomNumberGenerator) -> void:
	var prism := PrismMesh.new()
	prism.size = Vector3(1.9, 1.35, 2.2)
	k.add(prism, _at(Vector3(0, 0.675, 0)), _a())
	# the doorway: a dark triangle, its flaps tied back
	var door := PrismMesh.new()
	door.size = Vector3(0.8, 0.95, 0.02)
	k.add(door, _at(Vector3(0, 0.475, 1.105)), _fixed(0.12, 0.1, 0.09))
	for sgn in [-1.0, 1.0]:
		var flap := PrismMesh.new()
		flap.size = Vector3(0.4, 0.85, 0.04)
		k.add(flap, _at(Vector3(sgn * 0.52, 0.43, 1.12), Vector3(0, 0, sgn * 0.12)), _a(0.85))
	# ridge pole ends and pegs with guy lines
	for z in [-1.18, 1.18]:
		k.rod(Vector3(0, 0, z), Vector3(0, 1.45, z), 0.025, _b())
		k.rod(Vector3(0, 1.4, z), Vector3(0, 0, z * 1.6), 0.006, _fixed(0.85, 0.82, 0.72), 4)
		k.rod(Vector3(0, 0.05, z * 1.6), Vector3(0, -0.1, z * 1.6), 0.02, _b(), 4)
	for x in [-1.05, 1.05]:
		for z in [-0.9, 0.9]:
			k.rod(Vector3(x, 0.05, z), Vector3(x, -0.1, z), 0.018, _b(), 4)
	# a bedroll peeking out
	k.cyl(0.12, 0.12, 0.5, _at(Vector3(0.2, 0.12, 0.85), Vector3(0, 0, PI * 0.5)), _fixed(0.55, 0.32, 0.25), 10)


static func _backpack(k: Kit) -> void:
	k.box(Vector3(0.36, 0.48, 0.24), _at(Vector3(0, 0.26, 0), Vector3(-0.12, 0, 0)), _a())
	k.box(Vector3(0.38, 0.14, 0.27), _at(Vector3(0, 0.47, 0.02), Vector3(-0.12, 0, 0)), _a(0.85))
	k.box(Vector3(0.26, 0.17, 0.08), _at(Vector3(0, 0.2, 0.15), Vector3(-0.12, 0, 0)), _a(0.9))
	for x in [-0.21, 0.21]:
		k.box(Vector3(0.07, 0.18, 0.15), _at(Vector3(x, 0.18, 0.0), Vector3(-0.12, 0, 0)), _a(0.9))
	# the bedroll strapped on top
	k.cyl(0.08, 0.08, 0.46, _at(Vector3(0, 0.6, -0.04), Vector3(0, 0, PI * 0.5)), _b(), 10)
	for x in [-0.12, 0.12]:
		k.ring(0.075, 0.088, _at(Vector3(x, 0.6, -0.04), Vector3(0, 0, PI * 0.5)), _fixed(0.3, 0.2, 0.13))
	# shoulder straps down the back
	for x in [-0.1, 0.1]:
		k.box(Vector3(0.05, 0.42, 0.03), _at(Vector3(x, 0.26, -0.14), Vector3(-0.12, 0, 0)), _fixed(0.3, 0.2, 0.13))


static func _chest(k: Kit) -> void:
	k.box(Vector3(0.75, 0.38, 0.46), _at(Vector3(0, 0.19, 0)), _a())
	k.cyl(0.23, 0.23, 0.75, Transform3D(Basis.from_euler(Vector3(0, 0, PI * 0.5)).scaled(Vector3(1, 1, 0.6)), Vector3(0, 0.38, 0)), _a(0.92), 12)
	for x in [-0.3, 0.0, 0.3]:
		k.box(Vector3(0.05, 0.4, 0.48), _at(Vector3(x, 0.2, 0)), _b())
		k.ring(0.225, 0.25, Transform3D(Basis.from_euler(Vector3(0, 0, PI * 0.5)).scaled(Vector3(0.2, 1, 0.62)), Vector3(x, 0.38, 0)), _b())
	k.box(Vector3(0.09, 0.11, 0.03), _at(Vector3(0, 0.33, 0.24)), _fixed(0.75, 0.62, 0.3))


static func _pot(k: Kit, over_fire: bool) -> void:
	var iron := _fixed(0.12, 0.12, 0.13)
	var y := 0.55 if over_fire else 0.16
	k.ball(0.17, Transform3D(Basis().scaled(Vector3(1, 0.85, 1)), Vector3(0, y, 0)), iron, 14)
	k.cyl(0.15, 0.16, 0.06, _at(Vector3(0, y + 0.13, 0)), iron, 14)
	k.cyl(0.14, 0.14, 0.01, _at(Vector3(0, y + 0.16, 0)), _a(), 14)   # stew
	k.ring(0.155, 0.175, _at(Vector3(0, y + 0.165, 0)), iron)
	if over_fire:
		# a tripod over the fire, the pot hanging from a chain
		var top := Vector3(0, 1.35, 0)
		for s in 3:
			var a := TAU * s / 3.0 + 0.3
			k.rod(Vector3(cos(a) * 0.7, -0.05, sin(a) * 0.7), top + Vector3(cos(a), 0.12, sin(a)) * 0.1, 0.03, _b())
		k.rod(top, Vector3(0, y + 0.3, 0), 0.008, iron, 4)
		k.ring(0.17, 0.185, _at(Vector3(0, y + 0.22, 0), Vector3(PI * 0.5, 0, 0)), iron)
	else:
		for s in 3:
			var a := TAU * s / 3.0
			k.rod(Vector3(cos(a) * 0.1, 0.06, sin(a) * 0.1), Vector3(cos(a) * 0.12, 0.0, sin(a) * 0.12), 0.018, iron, 4)
		k.ring(0.15, 0.165, _at(Vector3(0, y + 0.2, 0), Vector3(PI * 0.5, 0, 0)), iron)


static func _blanket(k: Kit, rng: RandomNumberGenerator) -> void:
	var n := 6
	var cell := 0.25
	for j in n:
		for i in n:
			var col := _a() if (i + j) % 2 == 0 else _fixed(0.95, 0.93, 0.88)
			k.box(Vector3(cell, 0.012, cell), _at(Vector3((i - n * 0.5 + 0.5) * cell, 0.006 + rng.randf() * 0.003, (j - n * 0.5 + 0.5) * cell)), col)
	# a little feast: a loaf, apples and a jug
	k.ball(0.09, Transform3D(Basis().scaled(Vector3(1.5, 0.8, 1)), Vector3(0.3, 0.06, -0.2)), _fixed(0.72, 0.48, 0.25), 10)
	for a in 3:
		k.ball(0.04, _at(Vector3(-0.25 + a * 0.08, 0.05, 0.25)), _fixed(0.8, 0.15, 0.1), 8)
	k.cyl(0.05, 0.07, 0.18, _at(Vector3(-0.3, 0.1, -0.25)), _b(), 10)


# --- tools ---------------------------------------------------------------------

## A spade, as in a garden shed: a pointed, shield-shaped steel blade with
## a tread along its top, a steel socket up the shaft, a long wooden shaft,
## and at the top a steel fork that opens into a D round a wooden grip.
## Stuck in the ground at a slight slant, its point buried.
static func _spade(k: Kit) -> void:
	var tilt := Basis.from_euler(Vector3(0.12, 0, 0.06))
	var at := func(p: Vector3) -> Vector3: return tilt * (p + Vector3(0, 0.1, 0))
	var wood := _a()
	var steel := _fixed(0.48, 0.5, 0.52)
	var dark := _fixed(0.3, 0.31, 0.33)
	# the blade: square shoulders, straight sides drawing in to a point
	var blade := PackedVector2Array([Vector2(-0.1, 0.0), Vector2(0.1, 0.0), Vector2(0.095, -0.15), Vector2(0.07, -0.24),
		Vector2(0.03, -0.3), Vector2(0.0, -0.32), Vector2(-0.03, -0.3), Vector2(-0.07, -0.24), Vector2(-0.095, -0.15)])
	k.slab(blade, 0.008, 0.02, Transform3D(tilt, at.call(Vector3(0, 0.2, 0))), steel)
	# the tread rolled over along its top
	k.add(_cylm(0.012, 0.012, 0.2), Transform3D(tilt * Basis.from_euler(Vector3(0, 0, PI * 0.5)), at.call(Vector3(0, 0.2, -0.004))), dark)
	# the socket: a steel tube up the shaft, wide at the blade
	k.cone(at.call(Vector3(0, 0.12, 0.01)), at.call(Vector3(0, 0.42, 0.006)), 0.032, 0.022, steel)
	# the shaft
	k.rod(at.call(Vector3(0, 0.4, 0.006)), at.call(Vector3(0, 1.02, 0.006)), 0.019, wood, 8)
	# the fork: a steel sleeve, then two arms opening into a D
	k.cone(at.call(Vector3(0, 0.98, 0.006)), at.call(Vector3(0, 1.06, 0.006)), 0.023, 0.026, steel)
	var fork := Vector3(0, 1.06, 0.006)
	for sx in [-1.0, 1.0]:
		var out := Vector3(sx * 0.065, 1.16, 0.006)
		var top := Vector3(sx * 0.06, 1.24, 0.006)
		k.rod(at.call(fork), at.call(out), 0.009, steel, 5)
		k.rod(at.call(out), at.call(top), 0.009, steel, 5)
	k.add(_cylm(0.019, 0.019, 0.13), Transform3D(tilt * Basis.from_euler(Vector3(0, 0, PI * 0.5)), at.call(Vector3(0, 1.24, 0.006))), wood)
	# earth heaped round where it went in
	k.ball(0.1, Transform3D(Basis().scaled(Vector3(1.4, 0.45, 1.1)), Vector3(0, 0.0, 0)), _fixed(0.36, 0.27, 0.19), 8)


## A pick lying in the grass: a long wooden handle, and a steel head that
## curves gently down to a point at each end.
static func _pick(k: Kit) -> void:
	var wood := _a()
	var steel := _fixed(0.42, 0.43, 0.46)
	var y := 0.035
	k.rod(Vector3(-0.5, 0.025, 0), Vector3(0.38, y, 0.0), 0.022, wood, 8)
	k.box(Vector3(0.07, 0.06, 0.07), _at(Vector3(0.38, y + 0.005, 0)), steel)
	for sz in [-1.0, 1.0]:
		var mid := Vector3(0.39, y + 0.01, sz * 0.17)
		var tip := Vector3(0.35, y - 0.005, sz * 0.32)
		k.cone(Vector3(0.38, y + 0.01, sz * 0.03), mid, 0.03, 0.022, steel, 6)
		k.cone(mid, tip, 0.022, 0.004, steel, 6)


## An axe along +y from its head (the head at the origin, the edge to +x):
## a long, slightly curved hickory handle and a dark steel head with a
## bright bevel.
static func _axe(k: Kit, xf: Transform3D) -> void:
	var wood := _a()
	var steel := _fixed(0.2, 0.2, 0.22)
	var bright := _fixed(0.62, 0.64, 0.66)
	# the handle, in three bends, swelling a little at the knob
	var p0 := xf * Vector3(0, -0.04, 0)
	var p1 := xf * Vector3(-0.015, 0.28, 0)
	var p2 := xf * Vector3(0.0, 0.56, 0)
	var p3 := xf * Vector3(0.025, 0.72, 0)
	k.rod(p0, p1, 0.018, wood)
	k.rod(p1, p2, 0.017, wood)
	k.rod(p2, p3, 0.02, wood)
	k.ball(0.025, Transform3D(xf.basis, p3), wood, 6)
	# the head: a wedge, thick at the eye, thin at the edge
	# the head: a flat steel plate flaring from the eye to a long edge
	var outline := PackedVector2Array([Vector2(-0.02, 0.03), Vector2(0.06, 0.035), Vector2(0.15, 0.07),
		Vector2(0.155, -0.065), Vector2(0.06, -0.03), Vector2(-0.02, -0.03)])
	k.slab(outline, 0.022, 0.0, Transform3D(xf.basis, xf * Vector3(0, 0, 0)), steel)
	k.box(Vector3(0.05, 0.065, 0.04), Transform3D(xf.basis, xf * Vector3(-0.005, 0.0, 0)), steel)
	var bevel := PackedVector2Array([Vector2(0.125, 0.06), Vector2(0.155, 0.07), Vector2(0.16, -0.065), Vector2(0.13, -0.055)])
	k.slab(bevel, 0.024, 0.0, Transform3D(xf.basis, xf * Vector3(0, 0, 0)), bright)


# --- odds and ends -------------------------------------------------------------

static func _bottles(k: Kit, rng: RandomNumberGenerator) -> void:
	for b in 3:
		var a := TAU * b / 3.0 + rng.randf() * 0.4
		var p := Vector3(cos(a), 0, sin(a)) * 0.08
		var h := rng.randf_range(0.18, 0.26)
		var col := _a() if b != 1 else _b()
		k.cyl(0.04, 0.042, h, _at(p + Vector3(0, h * 0.5, 0)), col, 10)
		k.cyl(0.015, 0.04, 0.05, _at(p + Vector3(0, h + 0.025, 0)), col, 10)
		k.cyl(0.016, 0.016, 0.04, _at(p + Vector3(0, h + 0.07, 0)), col, 8)
		k.cyl(0.017, 0.017, 0.02, _at(p + Vector3(0, h + 0.095, 0)), _fixed(0.6, 0.45, 0.3), 8)


static func _books(k: Kit, rng: RandomNumberGenerator) -> void:
	var y := 0.0
	var colors := [_a(), _b(), _fixed(0.25, 0.35, 0.5), _fixed(0.62, 0.5, 0.3)]
	for b in 4:
		var t := rng.randf_range(0.035, 0.06)
		var sz := Vector3(rng.randf_range(0.2, 0.26), t, rng.randf_range(0.15, 0.19))
		var turn := Vector3(0, rng.randf_range(-0.3, 0.3), 0)
		k.box(sz, _at(Vector3(0, y + t * 0.5, 0), turn), colors[b])
		k.box(sz * Vector3(0.94, 0.8, 1.02) - Vector3(0, 0, 0.0), _at(Vector3(0.01, y + t * 0.5, 0.004), turn), _fixed(0.93, 0.9, 0.82))
		y += t


static func _basket(k: Kit, rng: RandomNumberGenerator) -> void:
	k.cyl(0.19, 0.14, 0.17, _at(Vector3(0, 0.085, 0)), _a(), 12)
	k.ring(0.17, 0.2, _at(Vector3(0, 0.17, 0)), _a(0.8))
	k.ring(0.17, 0.19, _at(Vector3(0, 0.17, 0), Vector3(PI * 0.5, 0, 0)), _a(0.85))
	for m in 6:
		var a := rng.randf() * TAU
		var p := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.0, 0.11) + Vector3(0, 0.18, 0)
		k.cyl(0.015, 0.02, 0.05, _at(p), _fixed(0.92, 0.88, 0.78), 6)
		k.ball(0.045, Transform3D(Basis().scaled(Vector3(1, 0.6, 1)), p + Vector3(0, 0.03, 0)), _b(rng.randf_range(0.85, 1.0)), 8)


static func _barrel(k: Kit) -> void:
	# three staves high: swelling out at the middle
	k.cyl(0.3, 0.26, 0.24, _at(Vector3(0, 0.12, 0)), _a(), 14)
	k.cyl(0.3, 0.3, 0.24, _at(Vector3(0, 0.36, 0)), _a(), 14)
	k.cyl(0.26, 0.3, 0.24, _at(Vector3(0, 0.6, 0)), _a(), 14)
	for y in [0.06, 0.34, 0.66]:
		k.ring(0.27 if y != 0.34 else 0.3, 0.305 if y == 0.34 else 0.28, _at(Vector3(0, y, 0)), _b())
	k.rings(Vector3(0, 0.721, 0), Vector3.UP, 0.25, Color(0.6, 0.45, 0.3), Color(0.4, 0.28, 0.18), 3)


static func _sign(k: Kit) -> void:
	k.rod(Vector3(0, -0.15, 0), Vector3(0, 1.05, 0), 0.035, _a(0.85))
	k.box(Vector3(0.55, 0.22, 0.04), _at(Vector3(0.12, 0.88, 0.04), Vector3(0, 0, 0.06)), _a())
	k.box(Vector3(0.4, 0.035, 0.005), _at(Vector3(0.1, 0.9, 0.062), Vector3(0, 0, 0.06)), _fixed(0.22, 0.16, 0.11))
	k.box(Vector3(0.3, 0.03, 0.005), _at(Vector3(0.08, 0.84, 0.062), Vector3(0, 0, 0.06)), _fixed(0.22, 0.16, 0.11))


static func _cylm(rt: float, rb: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = rt
	m.bottom_radius = rb
	m.height = h
	m.radial_segments = 8
	m.rings = 1
	return m


static func _boxm(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


# --- dead wood -----------------------------------------------------------------

## Shelf fungi along a log's side or up a stump.
static func _fungi(k: Kit, rng: RandomNumberGenerator, count: int, place: Callable) -> void:
	for f in count:
		var at: Array = place.call(rng)
		var p: Vector3 = at[0]
		var out: Vector3 = at[1]
		var r := rng.randf_range(0.04, 0.08)
		var b := Basis.looking_at(-out, Vector3.UP if absf(out.y) < 0.9 else Vector3.RIGHT)
		k.add(_half_disc(r), Transform3D(b, p + out * r * 0.3), _b(rng.randf_range(0.85, 1.05)))


static func _half_disc(r: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = r * 0.85
	m.bottom_radius = r
	m.height = r * 0.35
	m.radial_segments = 10
	m.rings = 1
	return m


## A chopping block: a short round of trunk in bark plates, its top cut
## pale and ringed inside a bark rim, an axe struck into it, split wood
## lying round its foot.
static func _block(k: Kit, w: WoodBuilder.Wood, rng: RandomNumberGenerator) -> void:
	var r := 0.24
	var h := 0.5
	var path: Array[Vector3] = []
	var radii: Array[float] = []
	for s in 5:
		var t := s / 4.0
		path.append(Vector3(0, lerpf(-0.06, h, t), 0))
		radii.append(r * (1.0 + 0.1 * (1.0 - smoothstep(0.0, 0.35, t))))
	var ring := w.trunk(path, radii, 9, 0.13)
	w.cap(ring, path[4], Vector3.UP, 0.09, 0.015)
	var ea := rng.randf() * TAU
	w.eye(Vector3(0, h * 0.4, 0) + Vector3(cos(ea), 0, sin(ea)) * r * 1.0, Vector3(cos(ea), 0, sin(ea)), Vector3.UP, r * 0.2)
	# the axe, struck into the top: its edge driven in at a slant, the handle
	# reaching up and out the other way, 35 degrees above level
	var up := deg_to_rad(35.0)
	var handle := Vector3(cos(up), sin(up), 0.0)
	var edge := Vector3(sin(up), -cos(up), 0.0)
	var ab := Basis(edge, handle, edge.cross(handle)).rotated(Vector3.UP, 0.6)
	var at := Vector3(-0.02, h - 0.015, 0.0) - ab.x * 0.085
	_axe(k, Transform3D(ab, at))
	# split wood round its foot, lying on a split face
	for s in 6:
		var a := rng.randf_range(-0.8, 1.6)
		var d := rng.randf_range(0.38, 0.62)
		var lie := Basis.from_euler(Vector3(0, a + rng.randf_range(-0.6, 0.6), 0)) * Basis(Vector3.BACK, PI * 0.5 + 0.9)
		w.split(Transform3D(lie, Vector3(cos(a) * d, 0.0, sin(a) * d)), rng.randf_range(0.32, 0.42), rng.randf_range(0.1, 0.14), 1.8)


## A woodpile: split logs packed tight in rows on two bearers between two
## posts, ends out, each lying bark up, bark down or on its side as it was
## thrown on, under a slab roof.
static func _woodpile(k: Kit, w: WoodBuilder.Wood, rng: RandomNumberGenerator) -> void:
	var width := 1.2
	var rows := 5
	var per := 7
	var len := 0.42
	var step := width / per
	var r := step * 1.08
	var row_h := step * 0.9
	var base := 0.08
	for z in [-len * 0.3, len * 0.3]:
		k.rod(Vector3(-width * 0.55, base * 0.5, z), Vector3(width * 0.55, base * 0.5, z), 0.045, _b(0.8), 6)
	var top := base + rows * row_h
	for x in [-width * 0.5 - 0.05, width * 0.5 + 0.05]:
		k.rod(Vector3(x, -0.1, 0), Vector3(x, top + 0.05, 0), 0.035, _b(0.8), 6)
	for row in rows:
		for p in per:
			var x := (p - (per - 1) * 0.5) * step + rng.randf_range(-0.01, 0.01)
			var spin: float = [0.0, PI, PI * 0.5, -PI * 0.5][rng.randi() % 4] + rng.randf_range(-0.25, 0.25)
			var turn := Basis.from_euler(Vector3(0, rng.randf_range(-0.05, 0.05), 0)) * Basis(Vector3.BACK, spin)
			var centre := Vector3(x, base + row * row_h + row_h * 0.5, rng.randf_range(-0.02, 0.02))
			var at := centre - turn * Vector3(0, r * 0.5, 0)
			w.split(Transform3D(turn, at), len + rng.randf_range(-0.04, 0.04), r * rng.randf_range(0.95, 1.05), rng.randf_range(1.6, 2.2))
	k.box(Vector3(width + 0.25, 0.03, len + 0.2), _at(Vector3(0, top + 0.07, 0), Vector3(0.1, 0, 0)), _b(0.85))


## A pile of round logs stacked in a triangle, each row resting in the
## hollows of the one below, bark in plates, cut ends ringed in a rim.
static func _logpile(k: Kit, w: WoodBuilder.Wood, rng: RandomNumberGenerator) -> void:
	var rows := 4
	var r := 0.09
	var len := 0.75
	for row in rows:
		var n := rows - row
		for p in n:
			var rr := r * rng.randf_range(0.9, 1.05)
			var x := (p - (n - 1) * 0.5) * r * 2.02
			var y := r + row * r * 1.74
			var l := len + rng.randf_range(-0.06, 0.06)
			var dz := rng.randf_range(-0.03, 0.03)
			var a := Vector3(x, y, dz - l * 0.5)
			var b := Vector3(x, y, dz + l * 0.5)
			var path: Array[Vector3] = [a, a.lerp(b, 0.5), b]
			var ring_b := w.trunk(path, [rr, rr * 0.98, rr * 0.96] as Array[float], 6, 0.12)
			w.cap(ring_b, b, Vector3.BACK, 0.12, 0.008)
			var back: Array[Vector3] = [b, a.lerp(b, 0.5), a]
			var ring_a := w.trunk(back, [rr * 0.96, rr * 0.98, rr] as Array[float], 6, 0.0)
			w.cap(ring_a, a, Vector3.FORWARD, 0.12, 0.008)
	for x in [-(rows * r * 1.01) - 0.03, rows * r * 1.01 + 0.03]:
		k.rod(Vector3(x, -0.1, 0), Vector3(x, r * 1.6, 0), 0.025, _b(0.7), 6)


## A fallen, rotting log, after stylized props: bark in long plates split by
## deep grooves, gently bent and tapering, one end sawn and ringed inside a
## bark rim, the other broken off in splinters, a knot or two, moss on top
## and shelf fungi down its side.
static func _log(k: Kit, w: WoodBuilder.Wood, st: Dictionary, rng: RandomNumberGenerator) -> void:
	var length := 2.1
	var r0 := 0.22 * float(st.thick)
	var path: Array[Vector3] = []
	var radii: Array[float] = []
	var bend := rng.randf_range(-0.18, 0.18)
	var n := 10
	for s in n:
		var t := float(s) / (n - 1)
		path.append(Vector3(lerpf(-length * 0.5, length * 0.5, t), r0 * 0.82, sin(t * PI) * bend))
		radii.append(r0 * lerpf(1.06, 0.8, t) * (1.0 + 0.05 * sin(t * 9.0 + bend * 20.0)))
	var broken := w.trunk(path, radii, 10, 0.16, r0 * 1.4)
	# the sawn end: the path reversed, ringed inside a rim
	var back: Array[Vector3] = [path[1], path[0]]
	var sawn := w.trunk(back, [radii[1], radii[0]] as Array[float], 10, 0.0)
	w.cap(sawn, path[0], (path[0] - path[1]).normalized(), 0.1, 0.02)
	# the broken end shows its heart sunk deep among the splinters
	w.cap(broken, path[n - 1], (path[n - 1] - path[n - 2]).normalized(), 0.22, r0 * 0.3)
	# knots
	for kk in 2:
		var t := rng.randf_range(0.25, 0.75)
		var at := TreeBuilder._along(path, t)
		var a := rng.randf_range(0.6, 2.4)
		var out := Vector3(0, sin(a), cos(a) * (1.0 if rng.randf() < 0.5 else -1.0)).normalized()
		w.knot(at + out * radii[int(t * (n - 1))] * 0.85, out, r0 * 0.22)
	# knot eyes down its sides
	for e in 3:
		var t := rng.randf_range(0.15, 0.85)
		var at := TreeBuilder._along(path, t)
		var a := rng.randf_range(-0.9, 0.9) + (PI if e % 2 == 1 else 0.0)
		var out := Vector3(0, sin(a) * 0.6 + 0.3, cos(a)).normalized()
		w.eye(at + out * radii[int(t * (n - 1))] * 0.96, out, Vector3.RIGHT, r0 * rng.randf_range(0.3, 0.4))
	var fungi := int(round(float(st.fungi) * 8.0))
	_fungi(k, rng, fungi, func(g: RandomNumberGenerator) -> Array:
		var t := g.randf_range(0.1, 0.9)
		var side := 1.0 if g.randf() < 0.5 else -1.0
		var c := TreeBuilder._along(path, t)
		var r := radii[int(t * (n - 1))]
		var out := Vector3(0, g.randf_range(-0.2, 0.3), side).normalized()
		return [c + out * r * 0.95, out])


## An old stump, after stylized props: a short trunk in deep-grooved bark
## plates flaring at its foot into roots that run out over the ground and
## taper to points, its top broken into a jagged rim round a sunken cut
## with a spiral of rings, a knot on its side, moss and fungi.
static func _stump(k: Kit, w: WoodBuilder.Wood, st: Dictionary, rng: RandomNumberGenerator) -> void:
	var r0 := 0.3 * float(st.thick)
	var h := 0.55
	var path: Array[Vector3] = []
	var radii: Array[float] = []
	for s in 7:
		var t := s / 6.0
		path.append(Vector3(0, lerpf(-0.12, h, t), 0))
		radii.append(r0 * (1.0 + 0.55 * pow(1.0 - smoothstep(0.0, 0.5, t), 2.0)) * (1.0 + 0.03 * sin(t * 7.0)))
	var ring := w.trunk(path, radii, 9, 0.18, r0 * 0.35)
	w.cap(ring, path[6], Vector3.UP, 0.1, 0.03)
	# roots running out from its foot
	var count := 6
	var spin := rng.randf() * TAU
	for s in count:
		var a := spin + TAU * s / count + rng.randf_range(-0.25, 0.25)
		var out := Vector3(cos(a), 0, sin(a))
		w.root(out * r0 * 0.55, out, r0 * rng.randf_range(1.7, 2.6), r0 * rng.randf_range(0.4, 0.55), -0.02)
	# a knot on its side
	var ka := rng.randf() * TAU
	var kout := Vector3(cos(ka), 0.25, sin(ka)).normalized()
	w.knot(Vector3(0, h * 0.7, 0) + Vector3(cos(ka), 0, sin(ka)) * r0 * 0.95, kout, r0 * 0.12)
	var ea := ka + PI * rng.randf_range(0.7, 1.3)
	w.eye(Vector3(0, h * 0.45, 0) + Vector3(cos(ea), 0, sin(ea)) * r0 * 1.02, Vector3(cos(ea), 0, sin(ea)), Vector3.UP, r0 * 0.22)
	var fungi := int(round(float(st.fungi) * 6.0))
	_fungi(k, rng, fungi, func(g: RandomNumberGenerator) -> Array:
		var fa := g.randf() * TAU
		var out := Vector3(cos(fa), 0.1, sin(fa)).normalized()
		return [Vector3(0, g.randf_range(0.12, h * 0.8), 0) + out * r0 * 1.0, out])
