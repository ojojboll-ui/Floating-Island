extends RefCounted
## The small plants, generated: ferns, flowers, clover, mushrooms and tall
## grass. Each is built one unit tall (clover: one unit across) and scaled
## by the record's size, from a style the panel's dials set (see
## prop_catalog.gd).
##
## Vertex colour carries what the shader (plant.gdshader) needs, so one mesh
## can be shared by every colour of the same shape:
##   r  which part: 0 stem and leaf, 0.5 petal or cap, 1 flower centre or
##      seed head
##   g  shade: 0 deep down, 1 in the light
##   b  a random per piece
##   a  how much it sways in the wind
##
## Shapes after common procedural tricks: fern fronds are a curved spine with
## paired leaflets shrinking toward the tip; flowers a ring of petals on a
## stem; mushroom caps a lathed profile; grass a tuft of tapering blades.

const MeshUtil := preload("res://scripts/mesh_util.gd")

static var _cache := {}


class B:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var i := PackedInt32Array()

	func add(p: Vector3, nrm: Vector3, col: Color) -> int:
		v.append(p)
		n.append(nrm)
		c.append(col)
		return v.size() - 1

	func tri(a: int, b: int, d: int) -> void:
		i.append_array([a, b, d])

	func mesh() -> ArrayMesh:
		var m := ArrayMesh.new()
		if i.is_empty():
			return m
		MeshUtil.add_surface(m, v, n, PackedVector2Array(), c, i)
		return m


## The mesh for a kind of plant, a style and a variant; shapes are cached.
static func mesh(gen: String, style: Dictionary, variant: int) -> ArrayMesh:
	var shape := style.duplicate()
	for look in ["size", "variation", "color_a", "color_b", "color_c", "spots"]:
		shape.erase(look)
	var key := "%s|%s|%d" % [gen, str(shape), variant % 8]
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = (variant % 8) * 977 + gen.hash()
	var b := B.new()
	match gen:
		"fern":
			_fern(b, style, rng)
		"flower":
			_flowers(b, style, rng)
		"clover":
			_clover(b, style, rng)
		"mushroom":
			_mushrooms(b, style, rng)
		"grass":
			_grass(b, style, rng)
	var m := b.mesh()
	_cache[key] = m
	return m


static func _part(part: float, shade: float, rnd: float, sway: float) -> Color:
	return Color(part, clampf(shade, 0.0, 1.0), rnd, clampf(sway, 0.0, 1.0))


## A thin tube up a polyline, for stems.
static func _stem(b: B, pts: Array[Vector3], r0: float, r1: float, rnd: float, sway0: float, sway1: float) -> void:
	var sides := 4
	var first := b.v.size()
	var n := pts.size()
	for k in n:
		var t := float(k) / (n - 1)
		var d := (pts[mini(k + 1, n - 1)] - pts[maxi(k - 1, 0)]).normalized()
		var u := d.cross(Vector3.RIGHT if absf(d.x) < 0.9 else Vector3.FORWARD).normalized()
		var w := d.cross(u)
		for s in sides:
			var a := TAU * s / sides
			var nrm := u * cos(a) + w * sin(a)
			b.add(pts[k] + nrm * lerpf(r0, r1, t), nrm, _part(0.0, 0.3 + 0.6 * t, rnd, lerpf(sway0, sway1, t)))
	for k in n - 1:
		for s in sides:
			var a := first + k * sides + s
			var c := first + k * sides + (s + 1) % sides
			b.tri(a, a + sides, c)
			b.tri(c, a + sides, c + sides)


## A flat blade from `base` along `dir`, `w` wide, curling down by `droop`.
static func _blade(b: B, base: Vector3, dir: Vector3, length: float, w: float, droop: float, part: float, rnd: float, rows := 5, sway_base := 0.0) -> void:
	var side := dir.cross(Vector3.UP)
	if side.length() < 0.01:
		side = Vector3.RIGHT
	side = side.normalized()
	var first := b.v.size()
	var p := base
	var d := dir.normalized()
	for r in rows:
		var t := float(r) / (rows - 1)
		var nrm := side.cross(d).normalized()
		if nrm.y < 0.0:
			nrm = -nrm
		var half := w * 0.5 * sin(PI * clampf(t * 0.85 + 0.15, 0.0, 1.0)) * (1.0 - t * 0.6)
		if r == rows - 1:
			half = 0.0
		var col := _part(part, 0.25 + 0.75 * t, rnd, sway_base + t)
		b.add(p - side * half, nrm, col)
		b.add(p + side * half, nrm, col)
		p += d * length / (rows - 1)
		d = (d + Vector3.DOWN * droop / rows).normalized()
	for r in rows - 1:
		var a := first + r * 2
		b.tri(a, a + 2, a + 1)
		b.tri(a + 1, a + 2, a + 3)


# --- ferns ---------------------------------------------------------------------

static func _fern(b: B, st: Dictionary, rng: RandomNumberGenerator) -> void:
	var fronds := int(st.fronds)
	var arch: float = st.arch
	var width: float = st.width
	var spin := rng.randf() * TAU
	for f in fronds:
		var az := spin + TAU * f / fronds + rng.randf_range(-0.25, 0.25)
		var out := Vector3(cos(az), 0.0, sin(az))
		var rise := deg_to_rad(rng.randf_range(55.0, 75.0))
		var d := (out * cos(rise) + Vector3.UP * sin(rise)).normalized()
		var length := rng.randf_range(0.85, 1.15) * 1.25
		var p := Vector3.ZERO
		var segs := 12
		var spine: Array[Vector3] = [p]
		var rnd := rng.randf()
		for s in segs:
			var t := float(s + 1) / segs
			# the frond arches over: its direction tips down as it grows
			d = (d + Vector3.DOWN * arch * 0.32 + out * 0.04).normalized()
			p += d * length / segs
			spine.append(p)
			# a pair of leaflets at every step, shortest at the tip
			var side := d.cross(Vector3.UP)
			if side.length() < 0.01:
				side = out.cross(Vector3.UP)
			side = side.normalized()
			var leaf_len := width * 0.42 * sin(PI * clampf(t * 0.9 + 0.1, 0.0, 1.0)) * (1.0 - t * 0.5)
			for sgn in [-1.0, 1.0]:
				var ld: Vector3 = (side * float(sgn) + d * 0.55 + Vector3.UP * 0.1).normalized()
				_blade(b, p, ld, leaf_len, leaf_len * 0.55, 0.4, 0.0, rnd, 3, t * 0.6)
		_stem(b, spine, 0.012, 0.004, rnd, 0.0, 0.6)


# --- flowers -------------------------------------------------------------------

static func _flowers(b: B, st: Dictionary, rng: RandomNumberGenerator) -> void:
	var stems := int(st.stems)
	var petals := int(st.petals)
	var bloom: float = st.bloom
	var cup: float = st.cup
	for s in stems:
		var a := rng.randf() * TAU
		var spread := 0.18 * sqrt(rng.randf()) * (1.0 if stems > 1 else 0.0)
		var foot := Vector3(cos(a), 0.0, sin(a)) * spread
		var h := rng.randf_range(0.7, 1.0)
		var lean := Vector3(rng.randfn(), 0.0, rng.randfn()) * 0.08 + foot * 0.4
		var pts: Array[Vector3] = []
		for k in 6:
			var t := k / 5.0
			pts.append(foot + Vector3(0.0, h * t, 0.0) + lean * t * t)
		var rnd := rng.randf()
		_stem(b, pts, 0.014, 0.009, rnd, 0.0, 1.0)
		# a leaf or two on the stem
		for l in 2:
			var at := pts[1 + l]
			var la := rng.randf() * TAU
			_blade(b, at, Vector3(cos(la), 0.6, sin(la)), 0.22, 0.07, 0.6, 0.0, rnd, 4, 0.3 + l * 0.2)
		# the head: petals round a centre, cupped up by `cup`
		var top := pts[pts.size() - 1]
		var r := 0.13 * bloom * rng.randf_range(0.85, 1.15)
		var face := (Vector3.UP + lean * 2.0).normalized()
		var bs := Basis.looking_at(-face, Vector3.FORWARD if absf(face.y) > 0.9 else Vector3.UP)
		var spin := rng.randf() * TAU
		for p in petals:
			var pa := spin + TAU * p / petals
			var out := bs * Vector3(cos(pa), sin(pa), 0.0)
			var dir := (out * cos(cup * 1.1) + face * sin(cup * 1.1)).normalized()
			_petal(b, top, dir, face, r, TAU / petals, rnd)
		# the centre: a little dome
		var c0 := b.add(top + face * r * 0.18, face, _part(1.0, 1.0, rnd, 1.0))
		var ring := []
		for k in 6:
			var ka := TAU * k / 6.0
			var off := bs * Vector3(cos(ka), sin(ka), 0.0) * r * 0.28
			ring.append(b.add(top + off + face * 0.01, (face + off.normalized() * 0.5).normalized(), _part(1.0, 0.8, rnd, 1.0)))
		for k in 6:
			b.tri(c0, ring[(k + 1) % 6], ring[k])


static func _petal(b: B, at: Vector3, dir: Vector3, face: Vector3, r: float, gap: float, rnd: float) -> void:
	var side := dir.cross(face).normalized()
	var w := r * clampf(gap * 0.9, 0.25, 1.1)
	var nrm := (face + dir * 0.2).normalized()
	var a := b.add(at + dir * r * 0.15, nrm, _part(0.5, 0.75, rnd, 1.0))
	var l := b.add(at + dir * r * 0.55 + side * w * 0.5, nrm, _part(0.5, 0.95, rnd, 1.0))
	var t := b.add(at + dir * r + face * r * 0.05, nrm, _part(0.5, 1.0, rnd, 1.0))
	var rr := b.add(at + dir * r * 0.55 - side * w * 0.5, nrm, _part(0.5, 0.95, rnd, 1.0))
	b.tri(a, l, t)
	b.tri(a, t, rr)


# --- clover --------------------------------------------------------------------

static func _clover(b: B, st: Dictionary, rng: RandomNumberGenerator) -> void:
	var count := int(st.count)
	var heads: float = st.heads
	for k in count:
		var a := rng.randf() * TAU
		var at := Vector3(cos(a), 0.0, sin(a)) * 0.5 * sqrt(rng.randf())
		var h := rng.randf_range(0.08, 0.18)
		var rnd := rng.randf()
		var top := at + Vector3(rng.randfn() * 0.02, h, rng.randfn() * 0.02)
		_stem(b, [at, top] as Array[Vector3], 0.006, 0.005, rnd, 0.0, 0.6)
		var spin := rng.randf() * TAU
		var leaf_r := rng.randf_range(0.08, 0.11)
		for l in 3:
			var la := spin + TAU * l / 3.0
			var dir := Vector3(cos(la), 0.15, sin(la)).normalized()
			_heart(b, top, dir, leaf_r, rnd)
		if rng.randf() < heads:
			# a round white flower head on its own taller stalk
			var ht := at + Vector3(0.03, h * 1.6, 0.02)
			_stem(b, [at, ht] as Array[Vector3], 0.005, 0.004, rnd, 0.0, 0.8)
			_ball(b, ht, 0.035, 0.5, rnd)


## A clover leaflet: a rounded heart lying nearly flat.
static func _heart(b: B, at: Vector3, dir: Vector3, r: float, rnd: float) -> void:
	var side := dir.cross(Vector3.UP).normalized()
	var c := b.add(at, Vector3.UP, _part(0.0, 0.7, rnd, 0.6))
	var ring := []
	for k in 9:
		var t := float(k) / 8.0
		var a := lerpf(-PI * 0.5, PI * 0.5, t)
		# two lobes at the far end: a notch in the middle
		var reach := r * (0.75 + 0.25 * absf(sin(a * 2.0)))
		var p := at + (dir * cos(a) * 1.1 + side * sin(a) * 0.9) * reach + Vector3.UP * 0.006
		ring.append(b.add(p, Vector3.UP, _part(0.0, 0.85 + 0.15 * sin(t * PI), rnd, 0.7)))
	for k in 8:
		b.tri(c, ring[k], ring[k + 1])


static func _ball(b: B, at: Vector3, r: float, part: float, rnd: float) -> void:
	var first := b.v.size()
	var rings := 4
	var sides := 6
	for i in rings + 1:
		var phi := PI * i / rings
		for s in sides:
			var a := TAU * s / sides
			var nrm := Vector3(sin(phi) * cos(a), cos(phi), sin(phi) * sin(a))
			b.add(at + nrm * r, nrm, _part(part, 0.6 + 0.4 * nrm.y, rnd, 1.0))
	for i in rings:
		for s in sides:
			var a := first + i * sides + s
			var c := first + i * sides + (s + 1) % sides
			b.tri(a, c, a + sides)
			b.tri(c, c + sides, a + sides)


# --- mushrooms -----------------------------------------------------------------

static func _mushrooms(b: B, st: Dictionary, rng: RandomNumberGenerator) -> void:
	var count := int(st.count)
	var capw: float = st.cap_width
	var shape: float = st.cap_shape
	for k in count:
		var big := 1.0 if k == 0 else rng.randf_range(0.45, 0.8)
		var a := rng.randf() * TAU
		var at := Vector3(cos(a), 0.0, sin(a)) * (0.0 if k == 0 else rng.randf_range(0.25, 0.5))
		var h := big * rng.randf_range(0.85, 1.0)
		var lean := Vector3(rng.randfn(), 0.0, rng.randfn()) * 0.06 + at * 0.15
		var rnd := rng.randf()
		var pts: Array[Vector3] = []
		for s in 5:
			var t := s / 4.0
			pts.append(at + Vector3(0.0, h * t, 0.0) + lean * t)
		var sr := 0.075 * big * (0.6 + capw * 0.4)
		_stem_part(b, pts, sr * 1.15, sr * 0.9, rnd)
		_cap(b, pts[4], 0.32 * capw * big, shape, rnd)


## A mushroom stem: part 0 but light, with no sway to speak of.
static func _stem_part(b: B, pts: Array[Vector3], r0: float, r1: float, rnd: float) -> void:
	var sides := 8
	var first := b.v.size()
	for k in pts.size():
		var t := float(k) / (pts.size() - 1)
		for s in sides:
			var a := TAU * s / sides
			var nrm := Vector3(cos(a), 0.0, sin(a))
			b.add(pts[k] + nrm * lerpf(r0, r1, t), nrm, _part(0.25, 0.5 + 0.4 * t, rnd, 0.1 * t))
	for k in pts.size() - 1:
		for s in sides:
			var a := first + k * sides + s
			var c := first + k * sides + (s + 1) % sides
			b.tri(a, a + sides, c)
			b.tri(c, a + sides, c + sides)


## A lathed cap: flat and wide (shape 0) to a tall bell (1), and its gills.
static func _cap(b: B, top: Vector3, r: float, shape: float, rnd: float) -> void:
	var sides := 14
	var rings := 6
	var first := b.v.size()
	var height := r * lerpf(0.35, 1.2, shape)
	for i in rings + 1:
		var t := float(i) / rings
		var phi := t * PI * 0.5 * lerpf(1.15, 1.0, shape)
		var rr := sin(phi) * r
		var y := cos(phi) * height - height * 0.15
		for s in sides:
			var a := TAU * s / sides
			var nrm := Vector3(sin(phi) * cos(a) * height, cos(phi) * r, sin(phi) * sin(a) * height).normalized()
			b.add(top + Vector3(cos(a) * rr, y, sin(a) * rr), nrm, _part(0.5, 0.65 + 0.35 * cos(phi), rnd, 0.1))
	for i in rings:
		for s in sides:
			var a := first + i * sides + s
			var c := first + i * sides + (s + 1) % sides
			b.tri(a, c, a + sides)
			b.tri(c, c + sides, a + sides)
	# the gills: a darker disc under the rim
	var under := top + Vector3(0.0, -height * 0.15 + cos(PI * 0.5 * lerpf(1.15, 1.0, shape)) * height, 0.0)
	var c0 := b.add(under + Vector3.UP * height * 0.12, Vector3.DOWN, _part(0.25, 0.15, rnd, 0.1))
	var rim := first + rings * sides
	for s in sides:
		b.tri(c0, rim + s, rim + (s + 1) % sides)


# --- tall grass ----------------------------------------------------------------

static func _grass(b: B, st: Dictionary, rng: RandomNumberGenerator) -> void:
	var blades := int(st.blades)
	var bend: float = st.bend
	var width: float = st.width
	var spread: float = st.spread
	var heads: float = st.heads
	for k in blades:
		var a := rng.randf() * TAU
		var foot := Vector3(cos(a), 0.0, sin(a)) * spread * 0.25 * sqrt(rng.randf())
		var lean := Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(0.1, 0.5) * (0.4 + spread)
		var dir := (Vector3.UP + lean).normalized()
		var h := rng.randf_range(0.6, 1.0)
		var rnd := rng.randf()
		_blade(b, foot, dir, h, 0.045 * width, bend * 1.6, 0.0, rnd, 6)
		if rng.randf() < heads * 0.5:
			# a seed head on a fine stalk above the blades
			var top := foot + dir * h * 1.1 + lean * 0.2
			_stem(b, [foot, foot + (top - foot) * 0.6 + Vector3(0, 0.02, 0), top] as Array[Vector3], 0.004, 0.003, rnd, 0.0, 1.0)
			var hd := (top - foot).normalized()
			for s in 4:
				var p := top + hd * (0.03 + s * 0.035)
				_ball(b, p, 0.018 - s * 0.003, 1.0, rnd)
