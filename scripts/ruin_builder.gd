extends RefCounted
## Builds ruins stone by stone: walls laid in courses along a drawn path,
## pillars of stacked drums, arches of wedge stones, and stairs.
##
## Every stone is a softly rounded block, so the pieces read as handmade and
## the gaps between them catch shadow. Age takes stones away from the top
## down, unevenly along a wall and from the crown of an arch outward, and
## drops some of them on the ground below. Everything is seeded, so the same
## piece at the same age always comes out the same.

const MeshUtil := preload("res://scripts/mesh_util.gd")

const ROUND := 0.035         # rounding radius of stone edges, meters
const GAP := 0.01            # joint between stones: tight, dry-laid
const WALL_THICK := 0.5


class Stones:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var idx := PackedInt32Array()



## A rounded block: half extents h, oriented by basis, colour c (alpha 1 = stone).
static func block(st: Stones, center: Vector3, basis: Basis, size: Vector3, c: Color, rounding := ROUND) -> void:
	var h := size * 0.5
	var r := minf(rounding, minf(h.x, minf(h.y, h.z)) * 0.6)
	var inner := Vector3(h.x - r, h.y - r, h.z - r)
	var first := st.verts.size()
	var tmpl: PackedVector3Array = _template()
	for p in tmpl:
		var s := p * h
		var q := s.clamp(-inner, inner)
		var n := (s - q).normalized()
		st.verts.append(center + basis * (q + n * r))
		st.normals.append((basis * n).normalized())
		st.colors.append(c)
	for t in _template_idx():
		st.idx.append(first + t)

## An upright drum: radius rad, height ht, bevelled top and bottom edges.
static func drum(st: Stones, bottom: Vector3, basis: Basis, rad: float, ht: float, c: Color) -> void:
	var sides := 14
	var b := minf(0.035, ht * 0.2)
	var rings := [[0.0, rad - b], [b, rad], [ht - b, rad], [ht, rad - b]]
	var first := st.verts.size()
	for ring in rings:
		for s in sides:
			var a := TAU * s / sides
			var dir := Vector3(cos(a), 0.0, sin(a))
			var y: float = ring[0]
			var rr: float = ring[1]
			var n := dir
			if y == 0.0:
				n = (dir - Vector3.UP).normalized()
			elif y == ht:
				n = (dir + Vector3.UP).normalized()
			st.verts.append(bottom + basis * (dir * rr + Vector3(0.0, y, 0.0)))
			st.normals.append((basis * n).normalized())
			st.colors.append(c)
	for r in 3:
		for s in sides:
			var a0 := first + r * sides + s
			var a1 := first + r * sides + (s + 1) % sides
			st.idx.append_array([a0, a1, a0 + sides, a1, a1 + sides, a0 + sides])
	# caps
	for cap in [0, 3]:
		var centre := st.verts.size()
		var y := 0.0 if cap == 0 else ht
		st.verts.append(bottom + basis * Vector3(0.0, y, 0.0))
		st.normals.append((basis * (Vector3.DOWN if cap == 0 else Vector3.UP)).normalized())
		st.colors.append(c)
		for s in sides:
			var a0: int = first + cap * sides + s
			var a1: int = first + cap * sides + (s + 1) % sides
			if cap == 0:
				st.idx.append_array([centre, a1, a0])
			else:
				st.idx.append_array([centre, a0, a1])

## A plain box of mortar behind the stones, showing in the joints. Its edges
## are sharp, so neighbouring boxes meet as one flat face with no grooves.
static func core(st: Stones, center: Vector3, basis: Basis, size: Vector3) -> void:
	block(st, center, basis, size, Color(0.0, 0.0, 0.0, 0.0), 0.003)

static func finish(st: Stones) -> ArrayMesh:
	if st.idx.is_empty():
		return null
	var m := ArrayMesh.new()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = st.verts
	arr[Mesh.ARRAY_NORMAL] = st.normals
	arr[Mesh.ARRAY_COLOR] = st.colors
	arr[Mesh.ARRAY_INDEX] = st.idx
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


static var _tmpl: PackedVector3Array
static var _tmpl_idx: PackedInt32Array


## A cube surface in [-1,1]^3, each face a 3x3 grid, wound outward.
static func _template() -> PackedVector3Array:
	if _tmpl.is_empty():
		_build_template()
	return _tmpl


static func _template_idx() -> PackedInt32Array:
	if _tmpl.is_empty():
		_build_template()
	return _tmpl_idx


static func _build_template() -> void:
	var n := 3
	var faces := [
		[Vector3.RIGHT, Vector3.BACK, Vector3.UP], [Vector3.LEFT, Vector3.FORWARD, Vector3.UP],
		[Vector3.UP, Vector3.RIGHT, Vector3.BACK], [Vector3.DOWN, Vector3.RIGHT, Vector3.FORWARD],
		[Vector3.BACK, Vector3.LEFT, Vector3.UP], [Vector3.FORWARD, Vector3.RIGHT, Vector3.UP],
	]
	for f in faces:
		var normal: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var first := _tmpl.size()
		for j in n + 1:
			for i in n + 1:
				var a := -1.0 + 2.0 * i / n
				var b := -1.0 + 2.0 * j / n
				_tmpl.append(normal + u * a + v * b)
		# wind so the face points along its normal (clockwise seen from outside)
		var p0 := _tmpl[first]
		var p1 := _tmpl[first + 1]
		var p2 := _tmpl[first + n + 1]
		var flip := MeshUtil.face_normal(p0, p1, p2).dot(normal) < 0.0
		for j in n:
			for i in n:
				var a0 := first + j * (n + 1) + i
				var a1 := a0 + 1
				var a2 := a0 + n + 1
				var a3 := a2 + 1
				if flip:
					_tmpl_idx.append_array([a0, a2, a1, a1, a2, a3])
				else:
					_tmpl_idx.append_array([a0, a1, a2, a1, a3, a2])


static func _stone_tint(rng: RandomNumberGenerator) -> Color:
	var warm := rng.randf()
	var light := rng.randf_range(0.82, 1.08)
	var c := Color(0.60, 0.58, 0.55).lerp(Color(0.66, 0.60, 0.50), warm) * light
	return Color(c.r, c.g, c.b, 1.0)


## A lying stone on the ground near a ruin, as if fallen from it.
static func _fallen(st: Stones, data, rng: RandomNumberGenerator, at: Vector2, size: Vector3) -> void:
	var y: float = data.sample_height(at.x, at.y)
	var basis := Basis.from_euler(Vector3(rng.randf_range(-0.35, 0.35), rng.randf() * TAU, rng.randf_range(-0.35, 0.35)))
	block(st, Vector3(at.x, y + size.y * 0.3, at.y), basis, size, _stone_tint(rng))


# --- walls ---------------------------------------------------------------------

## Smooth a drawn path and resample it evenly.
static func smooth_path(points: PackedVector2Array, step := 0.2) -> PackedVector2Array:
	var p := points
	for pass_i in 2:
		if p.size() < 3:
			break
		var q := PackedVector2Array([p[0]])
		for k in p.size() - 1:
			q.append(p[k].lerp(p[k + 1], 0.25))
			q.append(p[k].lerp(p[k + 1], 0.75))
		q.append(p[p.size() - 1])
		p = q
	var out := PackedVector2Array()
	if p.size() < 2:
		return p
	out.append(p[0])
	var carry := 0.0
	for k in p.size() - 1:
		var a := p[k]
		var b := p[k + 1]
		var seg := a.distance_to(b)
		var d := step - carry
		while d <= seg:
			out.append(a.lerp(b, d / seg))
			d += step
		carry = seg - (d - step)
	if out[out.size() - 1].distance_to(p[p.size() - 1]) > step * 0.3:
		out.append(p[p.size() - 1])
	return out


static func path_length(p: PackedVector2Array) -> float:
	var l := 0.0
	for k in p.size() - 1:
		l += p[k].distance_to(p[k + 1])
	return l


## Point and direction at arc length s along the path.
static func _along(p: PackedVector2Array, s: float) -> Array:
	var acc := 0.0
	for k in p.size() - 1:
		var seg := p[k].distance_to(p[k + 1])
		if acc + seg >= s or k == p.size() - 2:
			var t := clampf((s - acc) / maxf(seg, 0.0001), 0.0, 1.0)
			return [p[k].lerp(p[k + 1], t), (p[k + 1] - p[k]).normalized()]
		acc += seg
	return [p[0], Vector2.RIGHT]


## openings: arches set into the wall, each [centre along the wall, arch
## radius, spring height above the wall's foot, which wedge stones stand].
## Stones inside the arch, and round its two pillars, are left out, so the
## arch makes a doorway; stones resting on a wedge that has fallen fall too.
## holes: doors and windows, each {s, hw, bottom, spring, sill}. Courses are
## trimmed to clean jambs either side, a round head of wedge stones spans
## the top and a window gets a sill. If age has taken the wall from beside
## the head, the head and everything over the hole come down.
## keep_top: something stands on this wall, so its top does not crumble.
## top_abs: if set, no stone rises above this world height (a wall under a
## floor, built up to meet it).
static func wall(data, path: PackedVector2Array, seed: int, height: float, age: float, openings: Array = [],
		keep_top := false, holes: Array = [], top_abs := NAN, into: Stones = null) -> ArrayMesh:
	if path.size() < 2:
		return null
	var own := into == null
	var st: Stones = Stones.new() if own else into
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.frequency = 0.3
	var length := path_length(path)
	# how far the top has fallen at each point along the wall
	var top := func(s: float) -> float:
		var wear := clampf(noise.get_noise_1d(s) * 0.9 + 0.55, 0.0, 1.0)
		var ends := 1.0 - minf(s, length - s) / maxf(length * 0.5, 0.01)
		wear = clampf(wear + ends * 0.35, 0.0, 1.0)
		if keep_top:
			return height
		return height * (1.0 - 0.9 * smoothstep(0.0, 1.0, wear * age * 1.5))
	# how high the doorway reaches at each point along the wall (0 = no doorway)
	var doorway := func(s: float) -> float:
		var h := 0.0
		for o in openings:
			var ds := s - float(o[0])
			var r: float = o[1]
			var spring: float = o[2]
			# round the pillars, up to their capitals
			if absf(ds) < r + 0.5:
				h = maxf(h, spring + 0.02)
			# inside the arch ring
			var outer := r + 0.24
			if absf(ds) < outer:
				h = maxf(h, spring + sqrt(outer * outer - ds * ds))
		return h
	# whether the wedge stone this part of the wall rests on has fallen
	var unsupported := func(s: float) -> bool:
		for o in openings:
			var ds := s - float(o[0])
			var r: float = o[1]
			if absf(ds) < r + 0.21:
				var keep: Array = o[3]
				var ang := acos(clampf(ds / (r + 0.06), -1.0, 1.0))
				var k := clampi(int((1.0 - ang / PI) * keep.size()), 0, keep.size() - 1)
				if not keep[k]:
					return true
		return false
	# Doors and windows as zones cut out of the courses: [s0, s1, y0, y1].
	# Each has straight jambs up to its spring and a round head above, made
	# of small wedge stones; the round part is cut out as a stack of thin
	# slices that follow the ring's outer edge. The core is cut to the
	# opening itself, so the ring and the wall cover what is left.
	# Courses run level, as on a real wall built on a slope; they start at the
	# lowest point and the bottom ones sink into rising ground. `lift` is how
	# far the local foot stands above that start. Holes and arches are
	# reckoned from the local foot, so their zones are lifted into course
	# heights.
	var ground_min := INF
	var ground_max := -INF
	for p in path:
		var gh: float = data.sample_height(p.x, p.y)
		ground_min = minf(ground_min, gh)
		ground_max = maxf(ground_max, gh)
	var ground_ref := ground_min - 0.12
	var lift := func(s: float) -> float:
		var q: Vector2 = _along(path, clampf(s, 0.0, length))[0]
		return data.sample_height(q.x, q.y) - 0.12 - ground_ref
	var zones := []
	var core_zones := []
	var rings := []
	var ring := 0.2
	for h in holes:
		var s: float = h.s
		var first_zone := zones.size()
		var first_core := core_zones.size()
		var hw: float = h.hw
		var y0: float = h.bottom
		var spring: float = h.spring
		var outer := hw + ring
		var crown := spring + outer
		var held: bool = top.call(s - outer - 0.1) > crown + 0.1 and top.call(s + outer + 0.1) > crown + 0.1
		if held:
			zones.append([s - hw, s + hw, y0, spring])
			core_zones.append([s - hw, s + hw, y0, spring])
			var slices := 8
			for k in slices:
				var a := spring + outer * k / slices
				var b := spring + outer * (k + 1) / slices
				var wo := sqrt(maxf(outer * outer - (a - spring) * (a - spring), 0.0))
				zones.append([s - wo, s + wo, a, b])
				if a - spring < hw:
					var wi := sqrt(maxf(hw * hw - (a - spring) * (a - spring), 0.0))
					core_zones.append([s - wi, s + wi, a, b])
			rings.append([s, hw, spring])
		else:
			# nothing holds up the wall over it any more
			zones.append([s - outer, s + outer, y0, INF])
			core_zones.append([s - hw, s + hw, y0, INF])
		if h.sill:
			zones.append([s - hw - 0.1, s + hw + 0.1, y0 - 0.14, y0])
		var l: float = lift.call(s)
		for k in range(first_zone, zones.size()):
			zones[k][2] += l
			zones[k][3] += l
		for k in range(first_core, core_zones.size()):
			core_zones[k][2] += l
			core_zones[k][3] += l
	var tall := height + ground_max - ground_min
	if not is_nan(top_abs):
		tall = top_abs - ground_ref
	var y := 0.0
	var thick := WALL_THICK
	while y < tall - 0.05:
		var ch := rng.randf_range(0.22, 0.3)
		var s := -rng.randf_range(0.0, 0.3)
		while s < length:
			var len := rng.randf_range(0.34, 0.62)
			var pieces := [[maxf(s, 0.0), minf(s + len, length)]]
			s = s + len
			# trim against doors and windows, so they get straight jambs
			for z in zones:
				if y >= z[3] or y + ch <= z[2]:
					continue
				var next := []
				for pc in pieces:
					if pc[1] <= z[0] or pc[0] >= z[1]:
						next.append(pc)
						continue
					if pc[0] < z[0]:
						next.append([pc[0], z[0]])
					if pc[1] > z[1]:
						next.append([z[1], pc[1]])
				pieces = next
			for pc in pieces:
				var s0: float = pc[0]
				var s1: float = pc[1]
				if s1 - s0 < 0.05:
					continue
				var mid := (s0 + s1) * 0.5
				var at: Array = _along(path, mid)
				var p: Vector2 = at[0]
				var dir: Vector2 = at[1]
				var l: float = lift.call(mid)
				if y + ch < l + 0.03:
					continue   # wholly under the ground here
				var yl := y - l   # height above the local foot
				# on a bend, straight stones open wedge gaps on the outside of the
				# curve: lengthen them by how much the wall turns along them
				var d0: Vector2 = _along(path, maxf(s0 - 0.1, 0.0))[1]
				var d1: Vector2 = _along(path, minf(s1 + 0.1, length))[1]
				var bend := absf(d0.angle_to(d1)) * thick
				var size := Vector3(s1 - s0 - GAP, ch - GAP, thick + rng.randf_range(-0.025, 0.02))
				size.x += bend
				var basis := Basis(Vector3.UP, atan2(-dir.y, dir.x)).rotated(Vector3.UP, rng.randf_range(-0.012, 0.012))
				if yl + ch * 0.5 < doorway.call(mid):
					continue
				var sh := ch
				if not is_nan(top_abs) and ground_ref + y + ch > top_abs + 0.02:
					# the last course is cut down to meet the floor above
					sh = top_abs - ground_ref - y
					if sh < 0.08:
						continue
					size.y = sh - GAP
				var standing: bool = yl + ch * 0.5 < top.call(mid)
				if standing and doorway.call(mid) > 0.0 and unsupported.call(mid):
					standing = false
				if standing:
					var out := Vector2(-dir.y, dir.x) * rng.randf_range(-0.01, 0.01)
					block(st, Vector3(p.x + out.x, ground_ref + y + sh * 0.5, p.y + out.y), basis, size, _stone_tint(rng))
				elif rng.randf() < 0.3 * age:
					var side := 1.0 if rng.randf() < 0.5 else -1.0
					var drop := p + Vector2(-dir.y, dir.x) * side * rng.randf_range(0.45, 1.3) + dir * rng.randf_range(-0.3, 0.3)
					if data.sample_sdf(drop.x, drop.y) > 0.2:
						_fallen(st, data, rng, drop, size * 0.9)
		y += ch
	# round heads over doors and windows: small wedge stones round the arc
	for rg in rings:
		var at: Array = _along(path, rg[0])
		var p: Vector2 = at[0]
		var dir: Vector2 = at[1]
		var u := Vector3(dir.x, 0.0, dir.y)
		var ground: float = data.sample_height(p.x, p.y) - 0.12
		var hw: float = rg[1]
		var r := hw + ring * 0.5
		var count := maxi(5, int(round(PI * r / 0.17)) | 1)
		for k in count:
			var ang := PI * (1.0 - (k + 0.5) / count)
			var radial := u * cos(ang) + Vector3.UP * sin(ang)
			var tangent := u * -sin(ang) + Vector3.UP * cos(ang)
			var depth := tangent.cross(radial).normalized()
			var centre := Vector3(p.x, ground + float(rg[2]), p.y) + radial * r
			block(st, centre, Basis(tangent, radial, depth), Vector3(PI * r / count - GAP, ring - GAP, thick + 0.02), _stone_tint(rng))
	for h in holes:
		if not h.sill:
			continue
		var at: Array = _along(path, h.s)
		var p: Vector2 = at[0]
		var dir: Vector2 = at[1]
		var ground: float = data.sample_height(p.x, p.y) - 0.12
		block(st, Vector3(p.x, ground + float(h.bottom) - 0.07, p.y), Basis(Vector3.UP, atan2(-dir.y, dir.x)), Vector3(float(h.hw) * 2.0 + 0.2, 0.13, thick + 0.12), _stone_tint(rng))
	# a dark mortar core, so the gaps show joints and not daylight
	var step := 0.2
	# stop short of the ends, where the stones should show and not the core
	var s := 0.18
	while s < length - 0.18:
		var s1 := minf(s + step, length - 0.18)
		var at: Array = _along(path, (s + s1) * 0.5)
		var p: Vector2 = at[0]
		var dir: Vector2 = at[1]
		var ground: float = data.sample_height(p.x, p.y) - 0.12
		# kept below the top course, which may stand half a stone lower
		var h: float = minf(top.call(s), top.call(s1)) - 0.2
		if not is_nan(top_abs):
			h = minf(h, top_abs - ground - 0.05)
		var bottom: float = maxf(doorway.call(s), doorway.call(s1))
		if bottom > 0.0 and (unsupported.call(s) or unsupported.call(s1)):
			h = 0.0
		if bottom > 0.0:
			bottom += 0.05
		# the core stops where doors and windows go through, cut to their
		# exact edges so the jamb stones keep their backing
		var lc: float = ground - ground_ref   # this strip's foot, in course heights
		var boxes := [[s, s1, bottom + lc, h + lc]]
		for z in core_zones:
			var next := []
			for bx in boxes:
				var a: float = bx[0]
				var b: float = bx[1]
				if b <= z[0] or a >= z[1] or bx[3] <= z[2] or bx[2] >= z[3]:
					next.append(bx)
					continue
				# beside the zone: whole height
				if a < z[0]:
					next.append([a, z[0], bx[2], bx[3]])
				if b > z[1]:
					next.append([z[1], b, bx[2], bx[3]])
				# within its width: below and above it only
				var ia := maxf(a, z[0])
				var ib := minf(b, z[1])
				if bx[2] < z[2]:
					next.append([ia, ib, bx[2], z[2]])
				if bx[3] > z[3]:
					next.append([ia, ib, z[3], bx[3]])
			boxes = next
		var basis := Basis(Vector3.UP, atan2(-dir.y, dir.x))
		for bx in boxes:
			var w: float = bx[1] - bx[0]
			var hh: float = bx[3] - bx[2]
			if w > 0.02 and hh > 0.1:
				var c: Vector2 = _along(path, (bx[0] + bx[1]) * 0.5)[0]
				core(st, Vector3(c.x, ground_ref + (bx[2] + bx[3]) * 0.5, c.y), basis, Vector3(w, hh, thick - 0.05))
		s = s1
	return finish(st) if own else null


# --- pillars, arches, stairs -----------------------------------------------------

## A column: square plinth, a shaft of drums, a capital. Age breaks it off
## partway and lays a drum or two in the grass.
static func pillar(data, at: Vector2, seed: int, height: float, age: float, st: Stones = null, keep_top := false) -> ArrayMesh:
	var own := st == null
	if own:
		st = Stones.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var ground: float = data.sample_height(at.x, at.y) - 0.1
	var yaw := Basis(Vector3.UP, rng.randf() * TAU)
	var plinth := 0.3
	block(st, Vector3(at.x, ground + plinth * 0.5, at.y), yaw, Vector3(0.95, plinth, 0.95), _stone_tint(rng))
	var capital := 0.24
	var shaft := height - plinth - capital
	var drums := maxi(2, int(round(shaft / 0.6)))
	var dh := shaft / drums
	var broken := height
	if not keep_top:
		broken = lerpf(height, plinth + dh * rng.randf_range(0.6, 2.2), age * rng.randf_range(0.6, 1.0))
	var y := ground + plinth
	for d in drums:
		var turn := yaw.rotated(Vector3.UP, rng.randf() * TAU)
		if y - ground + dh * 0.5 < broken:
			drum(st, Vector3(at.x, y, at.y), turn, 0.34 - d * 0.008, dh - 0.015, _stone_tint(rng))
		elif rng.randf() < 0.6 * age:
			var lie := at + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.7, 1.6)
			var gy: float = data.sample_height(lie.x, lie.y)
			var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, PI * 0.5)
			drum(st, Vector3(lie.x, gy + 0.26, lie.y) - b * Vector3(0.0, dh * 0.5, 0.0), b, 0.32, dh - 0.02, _stone_tint(rng))
		y += dh
	if y - ground + capital * 0.5 < broken:
		block(st, Vector3(at.x, y + capital * 0.5, at.y), yaw, Vector3(0.88, capital, 0.88), _stone_tint(rng))
	return finish(st) if own else null


## How many wedge stones an arch of this radius has.
static func arch_count(radius: float) -> int:
	return maxi(5, int(round(PI * radius / 0.32)) | 1)


## Which wedge stones of an arch still stand at this age. A stone only
## stands if every stone below it on its side stands too, and the keystone
## only if both its neighbours do, so nothing is ever left hanging in the
## air. `hold` makes an arch last longer (one held in a wall).
static func arch_keep(count: int, seed: int, age: float, hold := 0.0) -> Array:
	var noise := FastNoiseLite.new()
	noise.seed = seed
	var own := []
	for k in count:
		var t := (k + 0.5) / count
		var decay := absf(t - 0.5) * 2.0 + noise.get_noise_1d(k * 7.0) * 0.25
		own.append(decay > age * (1.2 - hold) - 0.2 - hold * 0.2)
	var keep := []
	keep.resize(count)
	var mid := count / 2
	var standing := true
	for k in mid:
		standing = standing and own[k]
		keep[k] = standing
	standing = true
	for k in range(count - 1, mid, -1):
		standing = standing and own[k]
		keep[k] = standing
	keep[mid] = own[mid] and (mid == 0 or keep[mid - 1]) and (mid == count - 1 or keep[mid + 1])
	return keep


## Lay the wedge stones of an arch. Fallen ones end up on the ground.
static func _arch_ring(st: Stones, data, rng: RandomNumberGenerator, mid: Vector2, spring: float, u: Vector3,
		radius: float, keep: Array, depth_size: float) -> void:
	var count := keep.size()
	var ring := 0.36
	for k in count:
		var t := (k + 0.5) / count
		var ang := PI * (1.0 - t)
		var radial := u * cos(ang) + Vector3.UP * sin(ang)
		var centre := Vector3(mid.x, spring, mid.y) + radial * (radius + ring * 0.5 - 0.15)
		var tangent := u * -sin(ang) + Vector3.UP * cos(ang)
		var depth := tangent.cross(radial).normalized()
		var size := Vector3(PI * (radius + ring * 0.5) / count - GAP, ring, depth_size)
		if keep[k]:
			block(st, centre, Basis(tangent, radial, depth), size, _stone_tint(rng))
		elif rng.randf() < 0.5:
			var drop := Vector2(centre.x, centre.z) + Vector2(depth.x, depth.z) * rng.randf_range(-1.0, 1.0)
			if data.sample_sdf(drop.x, drop.y) > 0.2:
				_fallen(st, data, rng, drop, size * 0.9)


## Two pillars and a round arch of wedge stones between them. The crown
## goes first with age, then the stones on either side.
static func arch(data, a: Vector2, b: Vector2, seed: int, height: float, age: float) -> ArrayMesh:
	var st := Stones.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var span := a.distance_to(b)
	if span < 0.8:
		return null
	pillar(data, a, seed + 1, height, age * 0.4, st, true)
	pillar(data, b, seed + 2, height, age * 0.4, st, true)
	var ga: float = data.sample_height(a.x, a.y)
	var gb: float = data.sample_height(b.x, b.y)
	var spring := maxf(ga, gb) - 0.1 + height
	var dir := (b - a).normalized()
	var radius := span * 0.5
	var keep := arch_keep(arch_count(radius), seed, age)
	_arch_ring(st, data, rng, (a + b) * 0.5, spring, Vector3(dir.x, 0.0, dir.y), radius, keep, 0.55)
	return finish(st)


## A flight of steps from a toward b. It follows the ground if that rises
## enough, and otherwise climbs on its own, as ruined stairs do. Each step is
## laid like the walls, in courses of stones with staggered joints, and
## topped with a tread stone. Age takes the top steps first and chips the
## rest.
static func stairs(data, a: Vector2, b: Vector2, seed: int, age: float, keep_top := false, height := 0.0) -> ArrayMesh:
	var st := Stones.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var run := a.distance_to(b)
	if run < 0.5:
		return null
	var shape := _stair_shape(data, a, b, height)
	var count: int = shape[0]
	var rise: float = shape[1]
	var ga: float = data.sample_height(a.x, a.y)
	var dir := (b - a).normalized()
	var across := Vector2(-dir.y, dir.x)
	var basis := Basis(Vector3.UP, atan2(-dir.y, dir.x))
	var width := 1.3
	var depth := run / count
	var lost := int(round(count * age * rng.randf_range(0.2, 0.55)))
	if keep_top:
		lost = 0
	for i in count:
		var t := (i + 0.5) / count
		var p := a.lerp(b, t)
		var ground: float = data.sample_height(p.x, p.y) - 0.15
		var top := ga + rise * (i + 1)
		if i >= count - lost:
			if rng.randf() < 0.6:
				_fallen(st, data, rng, p + across * rng.randf_range(-1.2, 1.2), Vector3(0.5, 0.2, 0.35))
			continue
		# age chips the steps narrower from one side
		var w := width * (1.0 - age * rng.randf_range(0.0, 0.3))
		var shift := (width - w) * 0.5 * (1.0 if rng.randf() < 0.5 else -1.0)
		var tread := 0.14
		var y := ground
		var course := 0
		while y < top - tread - 0.08:
			var ch := minf(rng.randf_range(0.2, 0.28), top - tread - y)
			# stones across the step, joints offset course to course
			var x := -w * 0.5 - (rng.randf_range(0.0, 0.25) if course % 2 == 1 else 0.0)
			while x < w * 0.5:
				var len := rng.randf_range(0.35, 0.6)
				var x0 := maxf(x, -w * 0.5)
				var x1 := minf(x + len, w * 0.5)
				x += len
				if x1 - x0 < 0.12:
					continue
				var c := p + across * (shift + (x0 + x1) * 0.5)
				block(st, Vector3(c.x, y + ch * 0.5, c.y), basis, Vector3(depth - GAP, ch - GAP, x1 - x0 - GAP), _stone_tint(rng))
			y += ch
			course += 1
		# the tread: one or two long slabs, a little proud of the riser
		var slabs := 1 if w < 0.9 else 2
		for k in slabs:
			var x0 := -w * 0.5 + w * k / slabs
			var x1 := -w * 0.5 + w * (k + 1) / slabs
			var c := p + across * (shift + (x0 + x1) * 0.5) - dir * 0.03
			block(st, Vector3(c.x, top - tread * 0.5, c.y), basis.rotated(Vector3.UP, rng.randf_range(-0.03, 0.03)), Vector3(depth + 0.05, tread - GAP, x1 - x0 - GAP), _stone_tint(rng))
		# the dark core inside, so joints read as joints
		var cc := p + across * shift
		if top - tread - ground > 0.2:
			core(st, Vector3(cc.x, (ground + top - tread) * 0.5, cc.y), basis, Vector3(depth - 0.05, top - tread - ground - 0.05, w - 0.05))
	return finish(st)


## Where the arch opening sits in a wall: [spring height, radius]. The arch
## keeps the height it was drawn with; the wall makes way for it.
static func opening_shape(span: float, arch_height: float) -> Array:
	return [arch_height, span * 0.5]


## How strongly a wall holds the arch set in it against age.
const WALL_HOLD := 0.3


## An arch laid into a wall between arc lengths s0 and s1: the same pillars
## and wedge stones as a free arch, at the height it was drawn with, the
## ring as deep as the wall. The wall's stones stop short of them (see wall()).
static func arch_in_wall(data, path: PackedVector2Array, s0: float, s1: float, seed: int, height: float, age: float) -> ArrayMesh:
	var st := Stones.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var a: Vector2 = _along(path, s0)[0]
	var b: Vector2 = _along(path, s1)[0]
	var mid: Vector2 = _along(path, (s0 + s1) * 0.5)[0]
	var radius := (s1 - s0) * 0.5
	# the jambs: full pillars, which the wall leans against and age leaves be
	pillar(data, a, seed + 1, height, 0.0, st, true)
	pillar(data, b, seed + 2, height, 0.0, st, true)
	var spring := maxf(data.sample_height(a.x, a.y), data.sample_height(b.x, b.y)) - 0.1 + height
	var dir := (b - a).normalized()
	var keep := arch_keep(arch_count(radius), seed, age, WALL_HOLD)
	_arch_ring(st, data, rng, mid, spring, Vector3(dir.x, 0.0, dir.y), radius, keep, WALL_THICK + 0.04)
	return finish(st)


## [steps, rise per step] for a flight from a to b climbing `height` (or, for
## 0, just following the ground). Steps get no taller than 0.3 m: a steep
## climb gets more, shallower steps.
static func _stair_shape(data, a: Vector2, b: Vector2, height: float) -> Array:
	var ga: float = data.sample_height(a.x, a.y)
	var gb: float = data.sample_height(b.x, b.y)
	var count := maxi(2, int(round(a.distance_to(b) / 0.4)))
	var total := maxf(height, gb - ga)
	if height <= 0.0:
		total = gb - ga
		if absf(total / count) < 0.17:
			total = 0.17 * count
	count = maxi(count, int(ceil(total / 0.3)))
	return [count, total / count]


## The height a flight of stairs reaches, the same reckoning stairs() uses.
static func stairs_top(data, a: Vector2, b: Vector2, height := 0.0) -> float:
	var shape := _stair_shape(data, a, b, height)
	return data.sample_height(a.x, a.y) + float(shape[0]) * float(shape[1])


const FLOOR_CELL := 0.5


## A floor painted in 0.5 m cells. On the ground it is a paving of
## flagstones following the terrain. Raised, it is a slab of flags on a dark
## bed, with a low broken parapet round its open edges and walls under
## them down to the ground. Age lifts out flags.
static func paving(terrain, cells: Array, level: float, raised: bool, seed: int, age: float, held: Callable) -> ArrayMesh:
	var st := Stones.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var have := {}
	for c in cells:
		have[Vector2i(c[0], c[1])] = true
	var flat := Basis.IDENTITY
	for key in have:
		var cell: Vector2i = key
		var centre := (Vector2(cell) + Vector2(0.5, 0.5)) * FLOOR_CELL
		var hole := rng.randf() < age * (0.3 if raised else 0.22)
		var turn := Basis(Vector3.UP, rng.randf_range(-0.06, 0.06))
		var flag := Vector3(FLOOR_CELL - GAP - rng.randf_range(0.0, 0.04), 0.12, FLOOR_CELL - GAP - rng.randf_range(0.0, 0.04))
		if raised:
			# the bed under the flags, seen from below as a dark slab
			core(st, Vector3(centre.x, level - 0.2, centre.y), flat, Vector3(FLOOR_CELL - 0.04, 0.22, FLOOR_CELL - 0.04))
			if not hole:
				block(st, Vector3(centre.x, level - 0.05 + rng.randf_range(-0.015, 0.015), centre.y), turn, flag, _stone_tint(rng))
			# parapet along open edges
			for side in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if have.has(cell + side):
					continue
				var edge := centre + Vector2(side) * (FLOOR_CELL * 0.5 - 0.12)
				var along := Vector2(-side.y, side.x)
				var basis := Basis(Vector3.UP, atan2(-along.y, along.x))
				# a band of edge stones in front of the dark bed
				var band := centre + Vector2(side) * (FLOOR_CELL * 0.5 - 0.14)
				block(st, Vector3(band.x, level - 0.2, band.y), basis, Vector3(FLOOR_CELL - GAP, 0.22, 0.28), _stone_tint(rng))
				for course in 2:
					if rng.randf() < age * (0.35 + course * 0.4):
						continue
					block(st, Vector3(edge.x, level + 0.13 + course * 0.24, edge.y), basis, Vector3(FLOOR_CELL - GAP, 0.22, 0.24), _stone_tint(rng))
		elif not hole:
			var y: float = terrain.sample_height(centre.x, centre.y)
			block(st, Vector3(centre.x, y - 0.03, centre.y), turn, flag, _stone_tint(rng))
	if raised:
		# walls under the open edges, from the ground up to the floor, so a
		# storey stands on walls like a little tower. Edges are gathered into
		# straight runs so the courses run on; an edge something else already
		# holds up (a wall, a stair) is left open.
		var runs := {}   # "axis|line|side" -> Array of cell indices along it
		for key in have:
			var cell: Vector2i = key
			for side in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if have.has(cell + side):
					continue
				var centre := (Vector2(cell) + Vector2(0.5, 0.5)) * FLOOR_CELL
				var edge_mid := centre + Vector2(side) * (FLOOR_CELL * 0.5 - WALL_THICK * 0.5)
				if held.call(edge_mid, level):
					continue
				var along_x: bool = side.y != 0
				var line := cell.y if along_x else cell.x
				var id := "%s|%d|%d" % ["x" if along_x else "z", line, side.x + side.y]
				if not runs.has(id):
					runs[id] = []
				runs[id].append(cell.x if along_x else cell.y)
		var k := 0
		for id in runs:
			var parts: PackedStringArray = id.split("|")
			var along_x := parts[0] == "x"
			var line := int(parts[1])
			var sign := int(parts[2])
			var idx: Array = runs[id]
			idx.sort()
			var start: int = idx[0]
			for n in idx.size():
				var last := n == idx.size() - 1
				if not last and idx[n + 1] == idx[n] + 1:
					continue
				var stop: int = idx[n] + 1
				# the wall's centre line, half a wall in from the edge
				var off := (line + (1.0 if sign > 0 else 0.0)) * FLOOR_CELL - sign * WALL_THICK * 0.5
				var p0: Vector2
				var p1: Vector2
				# reach half a wall past each end, so runs meet at the corners of a
				# stepped outline instead of leaving slits
				var e0 := start * FLOOR_CELL - WALL_THICK * 0.5
				var e1 := stop * FLOOR_CELL + WALL_THICK * 0.5
				if along_x:
					p0 = Vector2(e0, off)
					p1 = Vector2(e1, off)
				else:
					p0 = Vector2(off, e0)
					p1 = Vector2(off, e1)
				k += 1
				wall(terrain, PackedVector2Array([p0, p1]), seed + k * 17, level, age, [], true, [], level - 0.32, st)
				if not last:
					start = idx[n + 1]
	return finish(st)
