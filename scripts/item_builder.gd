extends RefCounted
## Small things for the island, generated: lights (fire pit, torch, candles,
## lantern), camp gear (tent, backpack, chest, pot, picnic blanket),
## tools (spade, pick, axe in a chopping block), odds and ends (bottles,
## books, basket, barrel, woodpile, sign), and dead wood (a fallen, rotting
## log and an old stump).
##
## The look follows hand-painted stylized props: chunky shapes with bevelled
## edges that catch the light, every material painted in its own way. All
## wood (planks, staves, posts, handles, logs) is built by wood_builder.gd and
## drawn with wood.gdshader, the same as the stumps; the fire pit's stones
## are generated stones (rock_builder.gd). Everything else is put together
## from rounded boxes, turned (lathe) shapes, bevelled plates and simple
## primitives, merged into one mesh drawn with item.gdshader. Per vertex:
##   colour alpha  which colour a part takes: its own baked colour, the
##                 style's first or second colour, or a warm glow
##   UV            where on the part, in metres (across, along its length),
##                 for weave, grain and seams
##   UV2           x the material (metal, cloth, leather, ...), y how much it
##                 is an edge (bevels are painted worn and light)
## Flames are animated cards (flame.gdshader) with a flickering light.
##
## Everything is built at real size for size 1 and stands on y = 0. Tools
## (spade, pick, axe) are built lying along +y from their foot, everything
## on the z >= 0 side, so the prop layer can lay them down or lean them
## against whatever stands by (see prop_layer.tool_pose).

const MeshUtil := preload("res://scripts/mesh_util.gd")
const TreeBuilder := preload("res://scripts/tree_builder.gd")
const WoodBuilder := preload("res://scripts/wood_builder.gd")
const RockBuilder := preload("res://scripts/rock_builder.gd")

## Vertex alpha: which colour a part takes.
const FIXED := 1.0
const COL_A := 0.75
const COL_B := 0.5
const GLOW := 0.25

## Materials (UV2.x), read by item.gdshader.
const PAINT := 0.0
const METAL := 1.0
const CLOTH := 2.0
const LEATHER := 3.0
const GLASS := 4.0
const WICKER := 5.0
const PAPER := 6.0
const WAX := 7.0

static var _item_mat: ShaderMaterial
static var _flame_mat: ShaderMaterial
static var _rock_mat: ShaderMaterial


class Kit:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var i := PackedInt32Array()
	## The material the next parts are made of.
	var mat := PAINT

	func _put(p: Vector3, nrm: Vector3, col: Color, t: Vector2, edge: float) -> int:
		v.append(p)
		n.append(nrm)
		c.append(col)
		uv.append(t)
		uv2.append(Vector2(mat, edge))
		return v.size() - 1

	## Wind a triangle so it faces `want`.
	func _tri(a: int, b: int, cc: int, want: Vector3) -> void:
		if MeshUtil.face_normal(v[a], v[b], v[cc]).dot(want) < 0.0:
			i.append_array([a, cc, b])
		else:
			i.append_array([a, b, cc])

	## A primitive mesh, placed by xf, in colour col (alpha picks the slot).
	func add(prim: PrimitiveMesh, xf: Transform3D, col: Color) -> void:
		var arr := prim.get_mesh_arrays()
		var pv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var pn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var pi: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		# the part's own long axis carries the grain or weave
		var box := prim.get_aabb()
		var axes := [0, 1, 2]
		axes.sort_custom(func(a, b): return box.size[a] > box.size[b])
		var base := v.size()
		var nb := xf.basis.inverse().transposed()
		for k in pv.size():
			var lp := pv[k]
			_put(xf * lp, (nb * pn[k]).normalized(), col, Vector2(lp[axes[1]], lp[axes[0]]), 0.0)
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
		cone(a, b, r, r, col, sides)

	## A tapering rod from a (radius ra) to b (radius rb).
	func cone(a: Vector3, b: Vector3, ra: float, rb: float, col: Color, sides := 8) -> void:
		var d := b - a
		var up := d.normalized()
		var side := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
		var bs := Basis(side, up, side.cross(up))
		cyl(rb, ra, d.length(), Transform3D(bs, (a + b) * 0.5), col, sides)

	## A box with rounded, bevelled edges: the faces flat, the bevels painted
	## as worn edges.
	func rbox(size: Vector3, bevel: float, xf: Transform3D, col: Color) -> void:
		var h := size * 0.5
		var b := minf(bevel, minf(h.x, minf(h.y, h.z)) * 0.95)
		var inner := h - Vector3.ONE * b
		var axes := [0, 1, 2]
		axes.sort_custom(func(p, q): return size[p] > size[q])
		var nb := xf.basis.inverse().transposed()
		for ax in 3:
			for s: float in [-1.0, 1.0]:
				var u_ax := (ax + 1) % 3
				var v_ax := (ax + 2) % 3
				var us := [-h[u_ax], -h[u_ax] + b * 0.35, -inner[u_ax], inner[u_ax], h[u_ax] - b * 0.35, h[u_ax]]
				var vs := [-h[v_ax], -h[v_ax] + b * 0.35, -inner[v_ax], inner[v_ax], h[v_ax] - b * 0.35, h[v_ax]]
				var ids := []
				for jv in 6:
					for iu in 6:
						var q := Vector3.ZERO
						q[ax] = s * h[ax]
						q[u_ax] = us[iu]
						q[v_ax] = vs[jv]
						var core := q.clamp(-inner, inner)
						var dir := q - core
						var nrm := dir.normalized() if dir.length() > 1e-6 else Vector3.ZERO
						if nrm == Vector3.ZERO:
							nrm[ax] = s
						var p := core + nrm * b
						var big := maxf(absf(nrm.x), maxf(absf(nrm.y), absf(nrm.z)))
						var edge := clampf((1.0 - big) / 0.25, 0.0, 1.0)
						ids.append(_put(xf * p, (nb * nrm).normalized(), col, Vector2(p[axes[1]], p[axes[0]]), edge))
				var face_n := Vector3.ZERO
				face_n[ax] = s
				var want := xf.basis * face_n
				for jv in 5:
					for iu in 5:
						var a: int = ids[jv * 6 + iu]
						var bb: int = ids[jv * 6 + iu + 1]
						var cc: int = ids[(jv + 1) * 6 + iu + 1]
						var d: int = ids[(jv + 1) * 6 + iu]
						_tri(a, bb, cc, want)
						_tri(a, cc, d, want)

	## A flat strap from a to b, `width` wide across `face` (the way it faces
	## out), `thick` deep: belts, bands, woven strips.
	func band(a: Vector3, b: Vector3, face: Vector3, width: float, thick: float, col: Color, bevel := -1.0) -> void:
		var along := (b - a).normalized()
		var out := (face - along * face.dot(along)).normalized()
		var across := out.cross(along)
		var bs := Basis(along, across, out)
		rbox(Vector3(a.distance_to(b), width, thick), thick * 0.45 if bevel < 0.0 else bevel, Transform3D(bs, (a + b) * 0.5), col)

	## A turned shape: `profile` from the bottom up, each Vector3(radius,
	## height, edge), spun round y in `sides`. A point given twice makes a
	## crisp corner there.
	func lathe(profile: Array, sides: int, xf: Transform3D, col: Color) -> void:
		var count := profile.size()
		var nb := xf.basis.inverse().transposed()
		var rows := []
		for k in count:
			var p: Vector3 = profile[k]
			var prev: Vector3 = profile[maxi(k - 1, 0)]
			var next: Vector3 = profile[mini(k + 1, count - 1)]
			# the outward normal of the profile here: from the segment before
			# and after, or one alone at a doubled corner
			var t := Vector2.ZERO
			var before := Vector2(p.x - prev.x, p.y - prev.y)
			var after := Vector2(next.x - p.x, next.y - p.y)
			if k > 0 and before.length() > 1e-5 and (after.length() < 1e-5 or k == count - 1 or (k + 1 < count and (profile[k + 1] as Vector3).is_equal_approx(p))):
				t = before.normalized()
			elif after.length() > 1e-5 and (k == 0 or (profile[k - 1] as Vector3).is_equal_approx(p)):
				t = after.normalized()
			else:
				t = (before.normalized() + after.normalized()).normalized()
			var n2 := Vector2(t.y, -t.x)
			var row := []
			for s in sides + 1:
				var a := TAU * s / sides
				var dir := Vector3(cos(a), 0.0, sin(a))
				var pos := dir * p.x + Vector3(0, p.y, 0)
				var nrm := (dir * n2.x + Vector3(0, n2.y, 0)).normalized()
				row.append(_put(xf * pos, (nb * nrm).normalized(), col, Vector2(a * maxf(p.x, 0.01), p.y), p.z))
			rows.append(row)
		for k in count - 1:
			var p0: Vector3 = profile[k]
			var p1: Vector3 = profile[k + 1]
			if p0.is_equal_approx(p1):
				continue
			for s in sides:
				var a: int = rows[k][s]
				var b: int = rows[k][s + 1]
				var cc: int = rows[k + 1][s + 1]
				var d: int = rows[k + 1][s]
				var mid := (v[a] + v[cc]) * 0.5
				var ax := xf * Vector3(0, (p0.y + p1.y) * 0.5, 0)
				var seg := Vector2(p1.x - p0.x, p1.y - p0.y).normalized()
				var want_l := Vector3(cos(TAU * (s + 0.5) / sides) * seg.y, -seg.x, sin(TAU * (s + 0.5) / sides) * seg.y)
				var want := xf.basis * want_l
				if want.length() < 1e-5:
					want = mid - ax
				_tri(a, b, cc, want)
				_tri(a, cc, d, want)

	## A bevelled plate: `outline` in its own x-y plane, `thick` deep in z,
	## placed by xf.
	func plate(outline: PackedVector2Array, thick: float, bevel: float, xf: Transform3D, col: Color) -> void:
		var g := MeshUtil.extrude(outline, thick, bevel)
		var pv: PackedVector3Array = g.v
		var uvs: PackedVector2Array = g.uv
		var edge: PackedFloat32Array = g.e
		var idx: PackedInt32Array = g.i
		var nrm := MeshUtil.normals(pv, idx)
		var nb := xf.basis.inverse().transposed()
		var base := v.size()
		for k in pv.size():
			_put(xf * pv[k], (nb * nrm[k]).normalized(), col, uvs[k], edge[k])
		for t in idx:
			i.append(base + t)

	## A cloth sheet over a grid of points (rows of columns), its outside in
	## col, its inside in `inside`; uv in metres down and across.
	func sheet(grid: Array, col: Color, inside: Color, out_dir: Vector3, hem := true) -> void:
		var rows := grid.size()
		var cols: int = (grid[0] as Array).size()
		for side: float in [1.0, -1.0]:
			var ids := []
			for r in rows:
				var acc := 0.0
				for q in cols:
					var p: Vector3 = grid[r][q]
					if q > 0:
						acc += p.distance_to(grid[r][q - 1])
					var down := (grid[mini(r + 1, rows - 1)][q] as Vector3) - (grid[maxi(r - 1, 0)][q] as Vector3)
					var right := (grid[r][mini(q + 1, cols - 1)] as Vector3) - (grid[r][maxi(q - 1, 0)] as Vector3)
					var nrm := down.cross(right).normalized()
					if nrm.dot(out_dir) < 0.0:
						nrm = -nrm
					var edge := 1.0 if hem and (r == rows - 1) else 0.0
					ids.append(_put(p + nrm * side * 0.004, nrm * side, col if side > 0.0 else inside, Vector2(acc, float(r) / (rows - 1) * 1.4), edge))
			for r in rows - 1:
				for q in cols - 1:
					var a: int = ids[r * cols + q]
					var b: int = ids[r * cols + q + 1]
					var cc: int = ids[(r + 1) * cols + q + 1]
					var d: int = ids[(r + 1) * cols + q]
					var want := n[a] + n[cc]
					_tri(a, b, cc, want)
					_tri(a, cc, d, want)

	func mesh() -> ArrayMesh:
		var m := ArrayMesh.new()
		if i.is_empty():
			return m
		MeshUtil.add_surface(m, v, n, uv, c, i, uv2)
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


## Which style colours the wood of each kind of thing takes: [bark or
## worked wood, cut wood]. Missing a second, it is the first, paler.
const WOOD_COLOURS := {
	"log": ["color_a", "wood_color"], "stump": ["color_a", "wood_color"],
	"block": ["color_b", "color_a"], "woodpile": ["color_b", "color_a"], "logpile": ["color_b", "color_a"],
	"tent": ["color_b"], "pot": ["color_b"],
}
const TOOLS := ["spade", "pick", "axe"]


## The node for a style: what (gen), with its colours, glow and extras.
static func build(gen: String, st: Dictionary, seed: int, extra := {}) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 6151 + gen.hash()
	var k := Kit.new()
	var w := WoodBuilder.Wood.new()
	w.rng.seed = rng.seed + 11
	var rocks: Array = []    # [transform, variant]
	var root := Node3D.new()
	var flames: Array = []   # [position, height]
	var light := Vector3.INF
	match gen:
		"firepit":
			_firepit(k, w, rng, rocks)
			flames = [[Vector3(0, 0.12, 0), 0.62], [Vector3(0.09, 0.1, 0.05), 0.42], [Vector3(-0.08, 0.1, -0.06), 0.46]]
			light = Vector3(0, 0.5, 0)
		"torch":
			_torch(k, w, rng)
			flames = [[Vector3(0, 1.42, 0), 0.38]]
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
			_tent(k, w, rng)
		"backpack":
			_backpack(k)
		"chest":
			_chest(k, w)
		"pot":
			_pot(k, w, bool(extra.get("over_fire", false)))
		"blanket":
			_blanket(k, rng)
		"spade":
			_spade(k, w)
		"pick":
			_pick(k, w)
		"axe":
			_axe(k, w, Transform3D(Basis(), Vector3(0, 0.078, 0.022)))
		"block":
			_block(k, w, rng)
		"bottles":
			_bottles(k, rng)
		"books":
			_books(k, rng)
		"basket":
			_basket(k, rng)
		"barrel":
			_barrel(k, w)
		"woodpile":
			_woodpile(k, w, rng)
		"logpile":
			_logpile(k, w, rng)
		"sign":
			_sign(k, w, rng)
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
	var box := body.mesh.get_aabb() if body.mesh.get_surface_count() > 0 else AABB()
	if not w.empty():
		var keys: Array = WOOD_COLOURS.get(gen, ["color_a"])
		var bark: Array = st.get(keys[0], [0.42, 0.32, 0.24])
		var wood: Array
		if keys.size() > 1:
			wood = st.get(keys[1], [0.86, 0.68, 0.45])
		else:
			# worked wood: its cut ends the same wood, paler
			var pale := Color(bark[0], bark[1], bark[2]).lerp(Color(0.95, 0.84, 0.64), 0.55)
			wood = [pale.r, pale.g, pale.b]
		if gen == "firepit":
			bark = [0.36, 0.27, 0.2]
			wood = [0.8, 0.62, 0.42]
		var moss := float(st.get("moss", 0.15)) if keys.size() > 1 or gen == "firepit" else 0.0
		var wm := WoodBuilder.instance(w, bark, wood, moss)
		root.add_child(wm)
		root.set_meta("shaded", wm)
		box = wm.mesh.get_aabb() if box.size == Vector3.ZERO else box.merge(wm.mesh.get_aabb())
	for r in rocks:
		var mi := _rock(r[0], r[1])
		root.add_child(mi)
		box = box.merge(mi.transform * mi.mesh.get_aabb())
	root.set_meta("tall", maxf(box.end.y, 0.05))
	# a tool's length, foot to tip, for leaning it
	root.set_meta("reach", box.end.y)
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


## A generated stone, drawn like the island's other stones.
static func _rock(xf: Transform3D, variant: int) -> MeshInstance3D:
	if _rock_mat == null:
		_rock_mat = ShaderMaterial.new()
		_rock_mat.shader = load("res://shaders/rock.gdshader")
	var st := {"angular": 0.75, "flat": 0.45, "long": 0.35}
	var mi := MeshInstance3D.new()
	mi.mesh = RockBuilder.mesh(st, variant % 8, 3)
	mi.transform = xf
	mi.material_override = _rock_mat
	var g := 0.5 + 0.05 * (variant % 3)
	mi.set_instance_shader_parameter("stone", Vector3(g, g, g * 1.03))
	mi.set_instance_shader_parameter("moss_amount", 0.05)
	mi.set_instance_shader_parameter("texture_amount", 0.5)
	return mi


# --- lights ---------------------------------------------------------------------

## A ring of stones round a little cone of logs on glowing embers.
static func _firepit(k: Kit, w: WoodBuilder.Wood, rng: RandomNumberGenerator, rocks: Array) -> void:
	for s in 9:
		var a := TAU * s / 9.0 + rng.randf_range(-0.1, 0.1)
		var size := rng.randf_range(0.22, 0.3)
		var turn := Basis.from_euler(Vector3(0, rng.randf() * TAU, 0)).scaled(Vector3(size, size * 0.85, size))
		rocks.append([Transform3D(turn, Vector3(cos(a) * 0.43, -0.02, sin(a) * 0.43)), rng.randi()])
	# logs leaning into a little cone, their tops burnt off
	for s in 4:
		var a := TAU * s / 4.0 + 0.4 + rng.randf_range(-0.2, 0.2)
		var foot := Vector3(cos(a) * 0.32, 0.03, sin(a) * 0.32)
		var top := Vector3(0, 0.3, 0) + foot * 0.12
		var r := rng.randf_range(0.04, 0.05)
		var ring := w.trunk([foot - (top - foot).normalized() * 0.04, foot.lerp(top, 0.5), top] as Array[Vector3], [r, r, r * 0.9] as Array[float], 5, 0.14)
		w.cap(ring, top, (top - foot).normalized(), 0.12, 0.004)
	# embers on a bed of ash
	k.mat = PAINT
	k.cyl(0.24, 0.27, 0.04, _at(Vector3(0, 0.02, 0)), _glow(0.9), 12)
	k.cyl(0.33, 0.36, 0.02, _at(Vector3(0, 0.005, 0)), _fixed(0.13, 0.11, 0.1), 12)
	for e in 7:
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.04, 0.2)
		k.ball(rng.randf_range(0.025, 0.04), Transform3D(Basis().scaled(Vector3(1.2, 0.6, 1.0)), Vector3(cos(a) * d, 0.045, sin(a) * d)), _glow(rng.randf_range(0.6, 1.0)), 6)


## A torch: a whittled pole, a band of iron, and a head of pitch-soaked
## rags wound round it.
static func _torch(k: Kit, w: WoodBuilder.Wood, rng: RandomNumberGenerator) -> void:
	var lean := Vector3(rng.randf_range(-0.04, 0.04), 1.0, rng.randf_range(-0.04, 0.04)).normalized()
	w.pole([Vector3.DOWN * 0.15, lean * 0.6, lean * 1.3] as Array[Vector3], 0.026, 6, 0, 1.2)
	k.mat = CLOTH
	var bs := Basis(Quaternion(Vector3.UP, lean))
	k.lathe([Vector3(0.0, 0.0, 0), Vector3(0.036, 0.0, 0.6), Vector3(0.05, 0.03, 0), Vector3(0.046, 0.06, 0.4), Vector3(0.054, 0.09, 0),
		Vector3(0.05, 0.13, 0.4), Vector3(0.042, 0.16, 0.6), Vector3(0.0, 0.17, 0)], 9, Transform3D(bs, lean * 1.24), _fixed(0.2, 0.15, 0.11))
	k.mat = METAL
	k.lathe([Vector3(0.034, 0.0, 1), Vector3(0.036, 0.004, 0), Vector3(0.036, 0.026, 0), Vector3(0.034, 0.03, 1)], 10, Transform3D(bs, lean * 1.2), _fixed(0.3, 0.3, 0.33))


static func _candles(k: Kit, rng: RandomNumberGenerator) -> Array:
	var tops: Array = []
	# a little dish with a raised lip
	k.mat = METAL
	k.lathe([Vector3(0, 0, 0), Vector3(0.15, 0.0, 0.5), Vector3(0.17, 0.012, 1), Vector3(0.175, 0.03, 1), Vector3(0.16, 0.03, 1),
		Vector3(0.15, 0.016, 0), Vector3(0.0, 0.016, 0)], 16, _at(Vector3.ZERO), _b())
	k.mat = WAX
	for c in 3:
		var a := TAU * c / 3.0 + rng.randf() * 0.5
		var p := Vector3(cos(a), 0, sin(a)) * 0.07 + Vector3(0, 0.016, 0)
		var h := rng.randf_range(0.1, 0.24)
		var r := 0.03
		# melted down at the top round the wick
		k.lathe([Vector3(r * 1.06, 0.0, 0), Vector3(r, 0.01, 0), Vector3(r, h - 0.012, 0), Vector3(r * 0.92, h, 0.8),
			Vector3(r * 0.6, h - 0.006, 0.3), Vector3(0.0, h - 0.01, 0)], 12, _at(p), _a())
		# drips of wax down the side
		for d in rng.randi_range(1, 3):
			var da := rng.randf() * TAU
			var dl := rng.randf_range(0.03, 0.08)
			var at := p + Vector3(cos(da) * r * 0.95, h - 0.01, sin(da) * r * 0.95)
			k.rod(at, at + Vector3(0, -dl, 0), 0.007, _a(0.97), 5)
			k.ball(0.009, _at(at + Vector3(0, -dl, 0)), _a(0.97), 6)
		k.mat = PAINT
		k.rod(p + Vector3(0, h - 0.012, 0), p + Vector3(0, h + 0.012, 0), 0.0025, _fixed(0.1, 0.08, 0.07), 4)
		k.mat = WAX
		tops.append(p + Vector3(0, h + 0.008, 0))
	return tops


## A lantern: an iron frame of six panes round a candle, a peaked roof and
## a ring to hang it by.
static func _lantern(k: Kit) -> void:
	k.mat = METAL
	var metal := _a()
	k.lathe([Vector3(0, 0, 0), Vector3(0.115, 0.0, 1), Vector3(0.12, 0.012, 1), Vector3(0.12, 0.035, 1), Vector3(0.1, 0.045, 1), Vector3(0.0, 0.045, 0)], 6, _at(Vector3.ZERO, Vector3(0, TAU / 12.0, 0)), metal)
	k.mat = PAINT
	k.cyl(0.088, 0.088, 0.22, _at(Vector3(0, 0.155, 0), Vector3(0, TAU / 12.0, 0)), _glow(0.75), 6)
	k.mat = METAL
	for s in 6:
		var a := TAU * s / 6.0
		k.band(Vector3(cos(a) * 0.094, 0.04, sin(a) * 0.094), Vector3(cos(a) * 0.094, 0.27, sin(a) * 0.094), Vector3(cos(a), 0, sin(a)), 0.016, 0.008, metal)
	k.lathe([Vector3(0, 0.26, 0), Vector3(0.125, 0.26, 1), Vector3(0.13, 0.275, 1), Vector3(0.09, 0.31, 0), Vector3(0.03, 0.36, 0.5),
		Vector3(0.028, 0.38, 1), Vector3(0.0, 0.385, 0)], 6, _at(Vector3.ZERO, Vector3(0, TAU / 12.0, 0)), metal)
	k.ring(0.032, 0.046, _at(Vector3(0, 0.42, 0), Vector3(PI * 0.5, 0, 0)), metal)


# --- camp ----------------------------------------------------------------------

## A ridge tent of canvas sagging a little between its poles, the front
## tied open on a dark inside, guy ropes out to pegs.
static func _tent(k: Kit, w: WoodBuilder.Wood, rng: RandomNumberGenerator) -> void:
	var half_w := 0.95
	var ridge := 1.35
	var half_l := 1.1
	var over := 0.08
	var canvas := _a()
	var inside := _fixed(0.16, 0.13, 0.1)
	k.mat = CLOTH
	# the two roof sheets, from the ridge down to the hem
	for sx: float in [-1.0, 1.0]:
		var grid := []
		var rows := 6
		var cols := 9
		for r in rows:
			var t := float(r) / (rows - 1)
			var row := []
			for q in cols:
				var u := float(q) / (cols - 1)
				var z := lerpf(-half_l - over, half_l + over, u)
				var p := Vector3(sx * half_w * t, ridge * (1.0 - t), z)
				# sagging between the poles, the hem a touch scalloped
				var sag := sin(PI * t) * (0.035 + 0.035 * sin(PI * clampf(u, 0.0, 1.0)))
				p += Vector3(-sx * 0.55, -0.83, 0).normalized() * sag
				if r == rows - 1:
					p.y += 0.03 * absf(sin(u * PI * 3.0))
				row.append(p)
			grid.append(row)
		k.sheet(grid, canvas, inside, Vector3(sx, 0.6, 0))
	# the back wall, closed
	var back := []
	for r in 5:
		var t := float(r) / 4.0
		var row := []
		for q in 5:
			var s := lerpf(-1.0, 1.0, float(q) / 4.0)
			row.append(Vector3(s * half_w * t * 0.97, ridge * (1.0 - t), -half_l + 0.02 * sin(PI * t)))
		back.append(row)
	k.sheet(back, _a(0.93), inside, Vector3(0, 0, -1))
	# the front: two flaps tied back to either side of a dark doorway
	for sx: float in [-1.0, 1.0]:
		var flap := []
		for r in 5:
			var t := float(r) / 4.0
			var row := []
			for q in 3:
				var s := float(q) / 2.0
				# from the wall's edge in to the doorway, wider at the foot
				var x := sx * lerpf(half_w * t * 0.97, half_w * t * lerpf(0.97, 0.45, 1.0) + 0.04, s)
				row.append(Vector3(x, ridge * (1.0 - t), half_l - 0.02 * sin(PI * t)))
			flap.append(row)
		k.sheet(flap, _a(0.93), inside, Vector3(0, 0, 1))
		# the flap rolled up and tied at the doorway's side
		k.cone(Vector3(sx * 0.12, ridge * 0.86, half_l + 0.02), Vector3(sx * 0.46, 0.04, half_l + 0.03), 0.03, 0.05, _a(0.86), 8)
		k.mat = CLOTH
		k.ring(0.04, 0.055, Transform3D(Basis(Quaternion(Vector3.UP, (Vector3(sx * 0.34, -0.8, 0)).normalized())), Vector3(sx * 0.3, 0.5, half_l + 0.03)), _fixed(0.85, 0.8, 0.68))
	# the doorway's dark inside
	k.mat = PAINT
	k.plate(PackedVector2Array([Vector2(-0.44, 0.0), Vector2(0.44, 0.0), Vector2(0.0, ridge * 0.92)]), 0.01, 0.0, _at(Vector3(0, 0.0, half_l - 0.05)), inside)
	# a bedroll peeking out
	k.mat = CLOTH
	k.lathe([Vector3(0, 0, 0), Vector3(0.11, 0.0, 0.6), Vector3(0.12, 0.02, 0), Vector3(0.12, 0.48, 0), Vector3(0.11, 0.5, 0.6), Vector3(0, 0.5, 0)], 10,
		Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0.45, 0.12, 0.8)), _fixed(0.55, 0.32, 0.25))
	# the poles at each end, pegs and guy ropes
	for z: float in [-half_l - 0.04, half_l + 0.04]:
		w.pole([Vector3(0, -0.1, z), Vector3(0, ridge + 0.14, z)] as Array[Vector3], 0.026, 6, 1)
		var peg := Vector3(0, 0, z * 1.62)
		k.mat = CLOTH
		k.rod(Vector3(0, ridge + 0.08, z), peg + Vector3(0, 0.05, 0), 0.006, _fixed(0.85, 0.8, 0.68), 4)
		w.pole([peg + Vector3(0, -0.1, 0), peg + Vector3(0, 0.07, -signf(z) * 0.02)] as Array[Vector3], 0.016, 5, 1)
	for x: float in [-half_w - 0.06, half_w + 0.06]:
		for z: float in [-0.85, 0.0, 0.85]:
			w.pole([Vector3(x, -0.1, z), Vector3(x + signf(x) * 0.02, 0.06, z)] as Array[Vector3], 0.013, 5, 1)


## A canvas rucksack: a soft body and lid, a pocket, leather straps with
## iron buckles and a bedroll strapped on top.
static func _backpack(k: Kit) -> void:
	var lean := Basis(Vector3.RIGHT, -0.12)
	var at := func(p: Vector3) -> Vector3: return lean * p
	k.mat = CLOTH
	k.rbox(Vector3(0.36, 0.46, 0.24), 0.07, Transform3D(lean, at.call(Vector3(0, 0.25, 0))), _a())
	k.rbox(Vector3(0.38, 0.13, 0.27), 0.05, Transform3D(lean, at.call(Vector3(0, 0.45, 0.012))), _a(0.86))
	k.rbox(Vector3(0.25, 0.16, 0.08), 0.035, Transform3D(lean, at.call(Vector3(0, 0.2, 0.135))), _a(0.9))
	for x: float in [-0.205, 0.205]:
		k.rbox(Vector3(0.07, 0.18, 0.15), 0.03, Transform3D(lean, at.call(Vector3(x, 0.18, 0.0))), _a(0.9))
	# the bedroll strapped on top
	k.lathe([Vector3(0, 0, 0), Vector3(0.075, 0.0, 0.6), Vector3(0.085, 0.015, 0), Vector3(0.085, 0.445, 0), Vector3(0.075, 0.46, 0.6), Vector3(0, 0.46, 0)], 12,
		Transform3D(lean * Basis(Vector3.BACK, PI * 0.5), at.call(Vector3(0.23, 0.6, -0.03))), _b())
	k.mat = LEATHER
	var strap := _fixed(0.36, 0.22, 0.13)
	for x: float in [-0.12, 0.12]:
		k.ring(0.083, 0.098, Transform3D(lean * Basis(Vector3.BACK, PI * 0.5), at.call(Vector3(x, 0.6, -0.03))), strap)
		# down over the lid to a buckle on the pocket
		k.band(at.call(Vector3(x * 0.6, 0.52, 0.15)), at.call(Vector3(x * 0.6, 0.28, 0.185)), lean * Vector3(0, 0, 1), 0.03, 0.008, strap)
	for x: float in [-0.1, 0.1]:
		k.band(at.call(Vector3(x, 0.48, -0.13)), at.call(Vector3(x, 0.05, -0.13)), lean * Vector3(0, 0, -1), 0.05, 0.012, strap)
	k.mat = METAL
	for x: float in [-0.072, 0.072]:
		k.rbox(Vector3(0.04, 0.035, 0.01), 0.004, Transform3D(lean, at.call(Vector3(x, 0.3, 0.19))), _fixed(0.62, 0.55, 0.38))


## A sea chest of planks with a rounded lid, iron bands, corner caps and a lock.
static func _chest(k: Kit, w: WoodBuilder.Wood) -> void:
	var wx := 0.75
	var dz := 0.46
	var hy := 0.36
	# front and back: three planks each, laid along
	for z: float in [-dz * 0.5 + 0.02, dz * 0.5 - 0.02]:
		for p in 3:
			w.plank(Vector3(wx - 0.02, hy / 3.0 - 0.006, 0.04), 0.012, _at(Vector3(0, hy / 6.0 + p * hy / 3.0, z)))
	# the ends: two planks each, standing
	for x: float in [-wx * 0.5 + 0.02, wx * 0.5 - 0.02]:
		for p in 2:
			w.plank(Vector3(hy - 0.006, dz * 0.5 - 0.03, 0.04), 0.012, Transform3D(Basis(Vector3.UP, Vector3.BACK, Vector3.RIGHT), Vector3(x, hy * 0.5, -dz * 0.25 + 0.015 + p * (dz * 0.5 - 0.03))))
	# the lid: five planks round a half barrel, closed by two half discs
	var rr := dz * 0.5
	for p in 5:
		var a0 := PI * p / 5.0
		var a1 := PI * (p + 1) / 5.0
		var a := (a0 + a1) * 0.5
		var e0 := Vector3(0, sin(a0) * rr * 0.62, cos(a0) * rr)
		var e1 := Vector3(0, sin(a1) * rr * 0.62, cos(a1) * rr)
		var nrm := Vector3(0, sin(a) / 0.62, cos(a)).normalized()
		var at := Vector3(0, hy, 0) + (e0 + e1) * 0.5 - nrm * 0.02
		w.plank(Vector3(wx - 0.03, e0.distance_to(e1) + 0.004, 0.04), 0.012, Transform3D(Basis(Vector3.RIGHT, -atan2(nrm.y, nrm.z)), at))
	var half := PackedVector2Array()
	for s in 11:
		var a := PI * s / 10.0
		half.append(Vector2(cos(a) * rr, sin(a) * rr * 0.62))
	for x: float in [-wx * 0.5 + 0.012, wx * 0.5 - 0.012]:
		w.board(half, 0.03, 0.01, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(x, hy, 0)))
	# iron: bands over the lid and down the front, corner caps, a lock
	k.mat = METAL
	var iron := _b()
	for x: float in [-0.27, 0.27]:
		var prev := Vector3.INF
		for s in 9:
			var a := PI * s / 8.0
			var p := Vector3(x, hy + sin(a) * (rr + 0.012) * 0.62 + 0.006, cos(a) * (rr + 0.012))
			if prev != Vector3.INF:
				k.band(prev, p, Vector3(0, p.y - hy, p.z), 0.05, 0.01, iron)
			prev = p
		for z: float in [-dz * 0.5 - 0.004, dz * 0.5 + 0.004]:
			k.band(Vector3(x, hy + 0.01, z), Vector3(x, 0.0, z), Vector3(0, 0, signf(z)), 0.05, 0.01, iron)
			for y: float in [0.06, 0.18, 0.3]:
				k.ball(0.009, _at(Vector3(x, y, z + signf(z) * 0.006)), iron, 6)
	for x: float in [-wx * 0.5, wx * 0.5]:
		for z: float in [-dz * 0.5, dz * 0.5]:
			k.rbox(Vector3(0.07, 0.07, 0.07), 0.012, _at(Vector3(x - signf(x) * 0.025, 0.03, z - signf(z) * 0.025)), iron)
	k.rbox(Vector3(0.1, 0.12, 0.02), 0.008, _at(Vector3(0, hy - 0.02, dz * 0.5 + 0.01)), _fixed(0.72, 0.6, 0.3))
	k.mat = PAINT
	k.cyl(0.008, 0.008, 0.005, _at(Vector3(0, hy - 0.01, dz * 0.5 + 0.021), Vector3(PI * 0.5, 0, 0)), _fixed(0.08, 0.07, 0.06), 6)


static func _pot(k: Kit, w: WoodBuilder.Wood, over_fire: bool) -> void:
	k.mat = METAL
	var iron := _fixed(0.16, 0.16, 0.18)
	var y := 0.55 if over_fire else 0.12
	k.lathe([Vector3(0.0, -0.13, 0), Vector3(0.09, -0.125, 0), Vector3(0.155, -0.07, 0), Vector3(0.175, 0.0, 0), Vector3(0.16, 0.1, 0),
		Vector3(0.15, 0.13, 0), Vector3(0.168, 0.145, 1), Vector3(0.17, 0.16, 1), Vector3(0.15, 0.16, 1), Vector3(0.14, 0.14, 0), Vector3(0.135, 0.09, 0), Vector3(0.0, 0.09, 0)], 16, _at(Vector3(0, y, 0)), iron)
	# stew, bubbling
	k.mat = PAINT
	k.cyl(0.139, 0.139, 0.01, _at(Vector3(0, y + 0.118, 0)), _a(), 16)
	for b in 4:
		var a := TAU * b / 4.0 + 0.3
		k.ball(0.02, Transform3D(Basis().scaled(Vector3(1, 0.5, 1)), Vector3(cos(a) * 0.07, y + 0.124, sin(a) * 0.06)), _a(1.15), 6)
	k.mat = METAL
	k.ring(0.165, 0.178, _at(Vector3(0, y + 0.2, 0), Vector3(PI * 0.5, 0, 0)), iron)
	if over_fire:
		# a tripod over the fire, the pot hanging from a chain
		var top := Vector3(0, 1.35, 0)
		for s in 3:
			var a := TAU * s / 3.0 + 0.3
			w.pole([Vector3(cos(a) * 0.7, -0.05, sin(a) * 0.7), top + Vector3(cos(a), 0.12, sin(a)) * 0.12] as Array[Vector3], 0.028, 6, 1)
		var links := 9
		for l in links:
			var t := (l + 0.5) / links
			var p := top.lerp(Vector3(0, y + 0.37, 0), t)
			k.ring(0.008, 0.016, _at(p, Vector3(PI * 0.5, (l % 2) * PI * 0.5, 0)).scaled_local(Vector3(1, 1, 1.6)), iron)
	else:
		for s in 3:
			var a := TAU * s / 3.0
			k.cone(Vector3(cos(a) * 0.1, y - 0.1, sin(a) * 0.1), Vector3(cos(a) * 0.12, 0.0, sin(a) * 0.12), 0.02, 0.014, iron, 5)


static func _blanket(k: Kit, rng: RandomNumberGenerator) -> void:
	var n := 6
	var cell := 0.25
	k.mat = CLOTH
	for j in n:
		for i in n:
			var col := _a() if (i + j) % 2 == 0 else _fixed(0.95, 0.93, 0.88)
			k.rbox(Vector3(cell + 0.002, 0.012, cell + 0.002), 0.004, _at(Vector3((i - n * 0.5 + 0.5) * cell, 0.006 + rng.randf() * 0.003, (j - n * 0.5 + 0.5) * cell)), col)
	# a little feast: a loaf, apples and a jug
	k.mat = PAINT
	k.ball(0.09, Transform3D(Basis().scaled(Vector3(1.5, 0.8, 1)), Vector3(0.3, 0.06, -0.2)), _fixed(0.72, 0.48, 0.25), 12)
	for s in 3:
		k.band(Vector3(0.3 - 0.08 + s * 0.07, 0.125, -0.25), Vector3(0.3 - 0.06 + s * 0.07, 0.125, -0.15), Vector3.UP, 0.012, 0.006, _fixed(0.9, 0.72, 0.45))
	for a in 3:
		var p := Vector3(-0.25 + a * 0.08, 0.05, 0.25)
		k.ball(0.04, _at(p), _fixed(0.8, 0.15, 0.1), 10)
		k.rod(p + Vector3(0, 0.03, 0), p + Vector3(0.005, 0.055, 0), 0.004, _fixed(0.35, 0.25, 0.12), 4)
	k.lathe([Vector3(0, 0, 0), Vector3(0.06, 0.0, 0.5), Vector3(0.075, 0.06, 0), Vector3(0.06, 0.15, 0), Vector3(0.042, 0.19, 0.5), Vector3(0.048, 0.205, 1),
		Vector3(0.04, 0.205, 1), Vector3(0, 0.19, 0)], 12, _at(Vector3(-0.3, 0.012, -0.25)), _b())
	k.ring(0.035, 0.05, _at(Vector3(-0.36, 0.12, -0.25), Vector3(PI * 0.5, 0, 0)), _b())


# --- tools ---------------------------------------------------------------------

## A spade, after hand-painted props: a pointed steel blade with a nick in
## its edge and a rolled tread, a steel socket, a long shaft and a T grip
## bound with cloth. Lying along +y from the blade's point.
static func _spade(k: Kit, w: WoodBuilder.Wood) -> void:
	var z := 0.032
	var steel := _b()
	k.mat = METAL
	var blade := PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.06, 0.05), Vector2(0.098, 0.13), Vector2(0.104, 0.29), Vector2(0.03, 0.3), Vector2(-0.03, 0.3),
		Vector2(-0.104, 0.29), Vector2(-0.102, 0.2), Vector2(-0.088, 0.18), Vector2(-0.096, 0.165), Vector2(-0.098, 0.13), Vector2(-0.06, 0.05)])
	k.plate(blade, 0.012, 0.004, _at(Vector3(0, 0, z)), steel)
	k.rbox(Vector3(0.23, 0.022, 0.03), 0.009, _at(Vector3(0, 0.3, z)), _b(0.85))
	k.lathe([Vector3(0.034, 0.0, 1), Vector3(0.036, 0.01, 0.5), Vector3(0.03, 0.08, 0), Vector3(0.025, 0.15, 0), Vector3(0.027, 0.16, 1),
		Vector3(0.023, 0.165, 0), Vector3(0, 0.165, 0)], 10, _at(Vector3(0, 0.29, z)), steel)
	# the shaft, and the grip across its top
	w.pole([Vector3(0, 0.44, z), Vector3(0, 0.75, z), Vector3(0, 1.0, z)] as Array[Vector3], 0.02, 6, 0)
	w.pole([Vector3(-0.085, 1.0, z), Vector3(0, 1.0, z), Vector3(0.085, 1.0, z)] as Array[Vector3], 0.024, 6, 2)
	# cloth bound round where they meet, crossed over the front and back
	k.mat = CLOTH
	var cloth := _fixed(0.9, 0.84, 0.68)
	k.cyl(0.027, 0.03, 0.06, _at(Vector3(0, 0.955, z)), cloth, 10)
	k.cyl(0.03, 0.03, 0.07, _at(Vector3(0, 1.0, z), Vector3(0, 0, PI * 0.5)), cloth, 10)
	for side: float in [1.0, -1.0]:
		for d: float in [1.0, -1.0]:
			k.band(Vector3(-0.05 * d, 0.95, z + side * 0.03), Vector3(0.05 * d, 1.035, z + side * 0.03), Vector3(0, 0, side), 0.02, 0.008, cloth)


## A pick: a long handle and a steel head that sweeps down to a point at
## each end, lashed on with crossed leather straps. Lying along +y from the
## handle's end.
static func _pick(k: Kit, w: WoodBuilder.Wood) -> void:
	var z := 0.034
	w.pole([Vector3(0, 0.0, z), Vector3(0, 0.4, z), Vector3(0, 0.8, z)] as Array[Vector3], 0.022, 6, 2, 1.12)
	k.mat = METAL
	var steel := _b()
	var hy := 0.7
	k.rbox(Vector3(0.08, 0.09, 0.062), 0.012, _at(Vector3(0, hy, z)), steel)
	for sx: float in [-1.0, 1.0]:
		var prev := Vector3(sx * 0.035, hy + 0.01, z)
		var r_prev := 0.03
		for s in range(1, 8):
			var t := s / 7.0
			# rising a little out of the eye, then sweeping down to the point
			var p := Vector3(sx * (0.035 + 0.32 * t), hy + 0.01 + 0.05 * sin(t * PI * 0.7) - 0.13 * t * t, z)
			var r := lerpf(0.028, 0.004, pow(t, 1.3))
			k.cone(prev, p, r_prev, r, steel, 6)
			prev = p
			r_prev = r
	k.mat = LEATHER
	var strap := _fixed(0.4, 0.24, 0.12)
	for side: float in [1.0, -1.0]:
		for d: float in [1.0, -1.0]:
			k.band(Vector3(-0.055 * d, hy - 0.06, z + side * 0.033), Vector3(0.055 * d, hy + 0.06, z + side * 0.033), Vector3(0, 0, side), 0.022, 0.008, strap)


## An axe along +y from its head (the head at the origin, the edge to +x):
## a long, gently curved handle swelling to a knob, and a steel head with a
## flaring bit and a bright, freshly ground edge.
static func _axe(k: Kit, w: WoodBuilder.Wood, xf: Transform3D) -> void:
	var path: Array[Vector3] = [xf * Vector3(0, -0.05, 0), xf * Vector3(-0.012, 0.25, 0), xf * Vector3(0.0, 0.5, 0), xf * Vector3(0.022, 0.66, 0)]
	w.pole(path, 0.017, 6, 2, 1.3)
	k.mat = METAL
	var steel := _b()
	var outline := PackedVector2Array([Vector2(-0.03, 0.035), Vector2(0.04, 0.035), Vector2(0.09, 0.05), Vector2(0.15, 0.085), Vector2(0.158, 0.03),
		Vector2(0.16, -0.02), Vector2(0.152, -0.075), Vector2(0.09, -0.045), Vector2(0.04, -0.035), Vector2(-0.03, -0.035)])
	k.plate(outline, 0.022, 0.006, xf, steel)
	k.rbox(Vector3(0.065, 0.074, 0.042), 0.01, Transform3D(xf.basis, xf * Vector3(-0.005, 0.0, 0)), steel)
	var bevel := PackedVector2Array([Vector2(0.128, 0.072), Vector2(0.15, 0.085), Vector2(0.158, 0.03), Vector2(0.16, -0.02), Vector2(0.152, -0.075), Vector2(0.13, -0.064), Vector2(0.138, -0.02), Vector2(0.137, 0.03)])
	k.plate(bevel, 0.0235, 0.003, xf, _b(1.6))


# --- odds and ends -------------------------------------------------------------

## Bottles of coloured glass, each with a shoulder, a neck, a lip and a cork.
static func _bottles(k: Kit, rng: RandomNumberGenerator) -> void:
	for b in 3:
		var a := TAU * b / 3.0 + rng.randf() * 0.4
		var p := Vector3(cos(a), 0, sin(a)) * 0.08
		var h := rng.randf_range(0.16, 0.24)
		var r := rng.randf_range(0.036, 0.046)
		var col := _a() if b != 1 else _b()
		k.mat = GLASS
		k.lathe([Vector3(0, 0.0, 0), Vector3(r * 0.9, 0.0, 0.6), Vector3(r, 0.01, 0), Vector3(r, h, 0), Vector3(r * 0.75, h + 0.03, 0),
			Vector3(0.016, h + 0.06, 0), Vector3(0.015, h + 0.085, 0), Vector3(0.019, h + 0.09, 1), Vector3(0.019, h + 0.1, 1), Vector3(0.012, h + 0.1, 0)], 12, _at(p), col)
		k.mat = PAINT
		k.lathe([Vector3(0, h + 0.09, 0), Vector3(0.013, h + 0.09, 0), Vector3(0.015, h + 0.118, 0.6), Vector3(0.012, h + 0.122, 0.6), Vector3(0, h + 0.122, 0)], 8, _at(p), _fixed(0.72, 0.52, 0.32))


## Old leather-bound books in a stack: raised frames tooled into the
## covers, rounded spines, cream pages, iron corners, now and then a strap.
static func _books(k: Kit, rng: RandomNumberGenerator) -> void:
	var y := 0.0
	var colors := [_a(), _b(), _fixed(0.2, 0.28, 0.45), _fixed(0.3, 0.2, 0.32)]
	var count := rng.randi_range(2, 4)
	for b in count:
		var t := rng.randf_range(0.045, 0.07)
		var sx := rng.randf_range(0.2, 0.26)
		var sz := rng.randf_range(0.15, 0.19)
		var turn := Basis(Vector3.UP, rng.randf_range(-0.35, 0.35))
		var at := func(p: Vector3) -> Transform3D: return Transform3D(turn, turn * p + Vector3(0, y, 0))
		var col: Color = colors[b % 4]
		k.mat = LEATHER
		var cover := 0.01
		for cy: float in [cover * 0.5, t - cover * 0.5]:
			k.rbox(Vector3(sx + 0.012, cover, sz + 0.012), 0.004, at.call(Vector3(0, cy, 0)), col)
		k.rbox(Vector3(0.026, t, sz + 0.014), 0.012, at.call(Vector3(-sx * 0.5 - 0.004, t * 0.5, 0)), col)
		# the tooled frame on the front cover
		var fx := sx * 0.5 - 0.022
		var fz := sz * 0.5 - 0.022
		var frame := Color(col.r * 0.72, col.g * 0.72, col.b * 0.72, col.a)
		for fz_s: float in [-fz, fz]:
			k.rbox(Vector3(fx * 2.0 + 0.008, 0.005, 0.008), 0.0025, at.call(Vector3(0, t + 0.001, fz_s)), frame)
		for fx_s: float in [-fx, fx]:
			k.rbox(Vector3(0.008, 0.005, fz * 2.0 + 0.008), 0.0025, at.call(Vector3(fx_s, t + 0.001, 0)), frame)
		if rng.randf() < 0.35:
			# a strap round the cover, fastened with a stud
			k.rbox(Vector3(0.032, t + 0.006, sz + 0.02), 0.004, at.call(Vector3(sx * 0.18, t * 0.5, 0)), Color(col.r * 0.8, col.g * 0.8, col.b * 0.8, col.a))
		k.mat = PAPER
		k.rbox(Vector3(sx - 0.006, t - cover * 2.0 + 0.002, sz - 0.004), 0.003, at.call(Vector3(0.004, t * 0.5, 0)), _fixed(0.88, 0.8, 0.64))
		k.mat = METAL
		for cz: float in [-1.0, 1.0]:
			var corner := PackedVector2Array([Vector2(0, 0), Vector2(-0.04, 0), Vector2(0, -0.04)])
			k.plate(corner, 0.005, 0.0015, at.call(Vector3(sx * 0.5 + 0.007, t + 0.001, cz * (sz * 0.5 + 0.007))) * Transform3D(Basis(Vector3.RIGHT, PI * 0.5) * Basis(Vector3.BACK, 0.0 if cz > 0.0 else -PI * 0.5)), _fixed(0.6, 0.56, 0.48))
		y += t + 0.002


## A wicker basket, after hand-made ones: wide flat strips woven in and out
## between upright stakes, a rolled rim, an arched handle; empty.
static func _basket(k: Kit, rng: RandomNumberGenerator) -> void:
	var rx := 0.21
	var rz := 0.15
	var h := 0.16
	var stakes := 18
	var rows := 4
	k.mat = WICKER
	var edge_at := func(a: float, y: float, push: float) -> Vector3:
		var flare := lerpf(0.86, 1.0, y / h)
		return Vector3(cos(a) * (rx * flare + push), y, sin(a) * (rz * flare + push))
	for s in stakes:
		var a := TAU * s / stakes
		var lo: Vector3 = edge_at.call(a, 0.01, 0.0)
		var hi: Vector3 = edge_at.call(a, h, 0.0)
		k.band(lo, hi, Vector3(cos(a) / rx, 0, sin(a) / rz), 0.026, 0.006, _a(0.86))
	# the strips: each row in and out between the stakes in a smooth wave,
	# the next row the other way about
	var sub := 3
	for r in rows:
		var y := (r + 0.5) * h / rows
		var shade := rng.randf_range(0.94, 1.06)
		for s in stakes * sub:
			var t0 := float(s) / sub
			var t1 := float(s + 1) / sub
			var push0 := 0.0045 * cos(PI * (t0 + r))
			var push1 := 0.0045 * cos(PI * (t1 + r))
			var a0 := TAU * t0 / stakes - 0.006
			var a1 := TAU * t1 / stakes + 0.006
			var am := (a0 + a1) * 0.5
			k.band(edge_at.call(a0, y, push0), edge_at.call(a1, y, push1), Vector3(cos(am) / rx, 0, sin(am) / rz), h / rows - 0.003, 0.006, _a(shade))
	# the rolled rim
	for s in stakes * 4:
		var a0 := TAU * s / (stakes * 4) - 0.01
		var a1 := TAU * (s + 1) / (stakes * 4) + 0.01
		var am := (a0 + a1) * 0.5
		k.band(edge_at.call(a0, h + 0.008, 0.002), edge_at.call(a1, h + 0.008, 0.002), Vector3(cos(am) / rx, 0.3, sin(am) / rz), 0.022, 0.016, _a(0.92), 0.007)
	# the floor
	k.lathe([Vector3(0, 0.0, 0), Vector3(1.0, 0.0, 0.5), Vector3(1.0, 0.014, 0.5), Vector3(0, 0.014, 0)], 18,
		Transform3D(Basis().scaled(Vector3(rx * 0.86, 1.0, rz * 0.86)), Vector3.ZERO), _a(0.8))
	# the handle arching over, two strips side by side
	for off: float in [-0.012, 0.012]:
		var prev := Vector3.INF
		for s in 21:
			var t := float(s) / 20.0
			var a := PI * t
			var p := Vector3(-cos(a) * (rx * 0.97), h + sin(a) * 0.2, off)
			if prev != Vector3.INF:
				var d := (p - prev).normalized() * 0.003
				k.band(prev - d, p + d, Vector3(0, 0, 1), 0.016, 0.01, _a(0.95))
			prev = p


## A barrel of staves swelling at the middle, their ends standing proud
## round a head of boards, iron hoops with rivets, a bung on top.
static func _barrel(k: Kit, w: WoodBuilder.Wood) -> void:
	var h := 0.74
	var path: Array[Vector3] = []
	var radii: Array[float] = []
	for s in 7:
		var t := s / 6.0
		path.append(Vector3(0, h * t, 0))
		radii.append(0.25 + 0.05 * sin(PI * t))
	var ring := w.trunk(path, radii, 12, 0.05, 0.0, WoodBuilder.PLANED)
	var start := w.first_ring
	w.cap(ring, path[6], Vector3.UP, 0.11, 0.035, WoodBuilder.PLANED)
	w.cap(start, path[0], Vector3.DOWN, 0.11, 0.02, WoodBuilder.PLANED)
	# the head: three boards across
	var hr := 0.25 * 0.89 - 0.006
	for b in 3:
		var y0 := -hr + b * hr * 2.0 / 3.0 + 0.003
		var y1 := y0 + hr * 2.0 / 3.0 - 0.006
		var outline := PackedVector2Array()
		for s in 9:
			var yy := lerpf(y0, y1, s / 8.0)
			outline.append(Vector2(sqrt(maxf(hr * hr - yy * yy, 0.0)), yy))
		for s in 9:
			var yy := lerpf(y1, y0, s / 8.0)
			outline.append(Vector2(-sqrt(maxf(hr * hr - yy * yy, 0.0)), yy))
		w.board(outline, 0.014, 0.004, Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, h - 0.035 + 0.006, 0)))
	w.pole([Vector3(0.1, h - 0.03, 0.05), Vector3(0.1, h + 0.012, 0.05)] as Array[Vector3], 0.026, 5, 1)
	# iron hoops
	k.mat = METAL
	var iron := _b()
	for hy: float in [0.08, 0.27, h - 0.27, h - 0.08]:
		var t: float = hy / h
		var r := 0.25 + 0.05 * sin(PI * t) + 0.006
		var tall := 0.045 if hy < 0.1 or hy > h - 0.1 else 0.035
		k.lathe([Vector3(r - 0.004, -tall * 0.5, 1), Vector3(r + 0.004, -tall * 0.5 + 0.004, 1), Vector3(r + 0.006, 0.0, 0),
			Vector3(r + 0.004, tall * 0.5 - 0.004, 1), Vector3(r - 0.004, tall * 0.5, 1)], 24, _at(Vector3(0, hy, 0)), iron)
		for s in 6:
			var a := TAU * (s + 0.5) / 6.0
			k.ball(0.008, Transform3D(Basis().scaled(Vector3(1, 1, 1)), Vector3(cos(a) * (r + 0.007), hy, sin(a) * (r + 0.007))), _b(0.8), 6)


## A woodpile: split logs packed tight in rows on two bearers between two
## posts, ends out, each lying bark up, bark down or on its side as it was
## thrown on, under a roof of boards.
static func _woodpile(k: Kit, w: WoodBuilder.Wood, rng: RandomNumberGenerator) -> void:
	var width := 1.2
	var rows := 5
	var per := 7
	var len := 0.42
	var step := width / per
	var r := step * 1.08
	var row_h := step * 0.9
	var base := 0.08
	for z: float in [-len * 0.3, len * 0.3]:
		w.pole([Vector3(-width * 0.55, base * 0.5, z), Vector3(width * 0.55, base * 0.5, z)] as Array[Vector3], 0.045, 6, 2)
	var top := base + rows * row_h
	for x: float in [-width * 0.5 - 0.05, width * 0.5 + 0.05]:
		w.pole([Vector3(x, -0.1, 0), Vector3(x, top + 0.05, 0)] as Array[Vector3], 0.035, 6, 1)
	for row in rows:
		for p in per:
			var x := (p - (per - 1) * 0.5) * step + rng.randf_range(-0.01, 0.01)
			var spin: float = [0.0, PI, PI * 0.5, -PI * 0.5][rng.randi() % 4] + rng.randf_range(-0.25, 0.25)
			var turn := Basis.from_euler(Vector3(0, rng.randf_range(-0.05, 0.05), 0)) * Basis(Vector3.BACK, spin)
			var centre := Vector3(x, base + row * row_h + row_h * 0.5, rng.randf_range(-0.02, 0.02))
			var at := centre - turn * Vector3(0, r * 0.5, 0)
			w.split(Transform3D(turn, at), len + rng.randf_range(-0.04, 0.04), r * rng.randf_range(0.95, 1.05), rng.randf_range(1.6, 2.2))
	# the roof: boards across, sloping to the back
	var boards := 4
	var deep := len + 0.22
	for b in boards:
		var z := lerpf(-deep * 0.5, deep * 0.5, (b + 0.5) / boards)
		w.plank(Vector3(width + 0.28, deep / boards - 0.008, 0.03), 0.008,
			Transform3D(Basis(Vector3.RIGHT, PI * 0.5 + 0.1), Vector3(rng.randf_range(-0.02, 0.02), top + 0.075 + z * 0.1, z)))


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
	for x: float in [-(rows * r * 1.01) - 0.03, rows * r * 1.01 + 0.03]:
		w.pole([Vector3(x, -0.1, 0), Vector3(x, r * 1.6, 0)] as Array[Vector3], 0.025, 5, 1)


## A signpost, after hand-painted props: a round post cut pale at its top,
## and one to three boards nailed across it: arrows, swallowtails or plain,
## each set a little askew.
static func _sign(k: Kit, w: WoodBuilder.Wood, rng: RandomNumberGenerator) -> void:
	var post_r := 0.045
	var top := rng.randf_range(1.05, 1.25)
	w.pole([Vector3(0, -0.15, 0), Vector3(0, top * 0.5, 0), Vector3(0, top, 0)] as Array[Vector3], post_r, 7, 1)
	var count := rng.randi_range(1, 3)
	var y := top - 0.16
	var thick := 0.035
	for b in count:
		var length := rng.randf_range(0.48, 0.62)
		var tall := rng.randf_range(0.13, 0.18)
		var dir := 1.0 if rng.randf() < 0.5 else -1.0
		var shape := rng.randi() % 3
		var x0 := -0.12
		var x1 := length - 0.12
		var hy := tall * 0.5
		var outline := PackedVector2Array()
		match shape:
			0:
				# an arrow
				outline = PackedVector2Array([Vector2(x0, -hy), Vector2(x1 - tall * 0.45, -hy), Vector2(x1, 0.0), Vector2(x1 - tall * 0.45, hy), Vector2(x0, hy)])
			1:
				# a swallowtail at the far end
				outline = PackedVector2Array([Vector2(x0, -hy), Vector2(x1, -hy * 1.05), Vector2(x1 - tall * 0.35, 0.0), Vector2(x1, hy * 1.05), Vector2(x0, hy)])
			_:
				# plain, its corners worn off
				outline = PackedVector2Array([Vector2(x0, -hy), Vector2(x1 - 0.02, -hy), Vector2(x1, -hy + 0.02), Vector2(x1, hy - 0.02), Vector2(x1 - 0.02, hy), Vector2(x0, hy)])
		var tilt := rng.randf_range(-0.08, 0.08)
		var face := Basis(Vector3.UP, 0.0 if dir > 0.0 else PI) * Basis(Vector3.BACK, tilt)
		var at := Vector3(0, y, 0) + Basis(Vector3.UP, 0.0 if dir > 0.0 else PI) * Vector3(0, 0, post_r + thick * 0.5)
		w.board(outline, thick, 0.009, Transform3D(face, at))
		# a nail where it crosses the post
		k.mat = METAL
		var nail := at + face * Vector3(0, 0, thick * 0.5)
		k.lathe([Vector3(0, 0, 0), Vector3(0.011, 0.0, 1), Vector3(0.01, 0.005, 1), Vector3(0, 0.007, 0)], 6,
			Transform3D(face * Basis(Vector3.RIGHT, PI * 0.5), nail), _fixed(0.3, 0.24, 0.2))
		y -= tall + rng.randf_range(0.02, 0.06)


static func _cylm(rt: float, rb: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = rt
	m.bottom_radius = rb
	m.height = h
	m.radial_segments = 8
	m.rings = 1
	return m


# --- dead wood -----------------------------------------------------------------

## Shelf fungi along a log's side or up a stump.
static func _fungi(k: Kit, rng: RandomNumberGenerator, count: int, place: Callable) -> void:
	k.mat = PAINT
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
	_axe(k, w, Transform3D(ab, at))
	# split wood round its foot, lying on a split face
	for s in 6:
		var a := rng.randf_range(-0.8, 1.6)
		var d := rng.randf_range(0.38, 0.62)
		var lie := Basis.from_euler(Vector3(0, a + rng.randf_range(-0.6, 0.6), 0)) * Basis(Vector3.BACK, PI * 0.5 + 0.9)
		w.split(Transform3D(lie, Vector3(cos(a) * d, 0.0, sin(a) * d)), rng.randf_range(0.32, 0.42), rng.randf_range(0.1, 0.14), 1.8)


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
