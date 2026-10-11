extends RefCounted
## Stones of every size, generated: boulders, pebbles and stepping stones
## are one shape with different settings.
##
## A stone is what is left of a ball when flat cuts take slices off it (the
## idea behind Rock Forge's "blocks sliced by cutting planes"), after the
## hand-painted stylized rocks: flat faces meeting in crisp ridges. The
## shape is cut for real, a convex block clipped by each plane in turn, so
## every face is flat and every ridge sharp. Each face is drawn as a fan
## from its middle, and every vertex knows how far it lies from the face's
## rim (UV: share of the way, and the distance from the middle to that rim),
## so the shader can paint a thin worn line along every ridge.
##
## More angular stones get fewer, bigger faces; worn ones more, smaller
## faces with their normals rounded toward the stone's middle. A flat cut
## underneath lets it sit on the ground.
##
## The style (see STYLE) sets the size, how much stones vary, how angular,
## flat and long they are, and the moss, texture and colour, which the
## shader (rock.gdshader) reads per stone.

const MeshUtil := preload("res://scripts/mesh_util.gd")

const STYLE := {
	"size": 1.4,          # metres across
	"variation": 0.3,     # how much one stone differs in size from the next
	"angular": 0.5,       # 0 a worn pebble .. 1 a hewn block with sharp facets
	"flat": 0.25,         # 0 as tall as wide .. 1 a slab
	"long": 0.2,          # 0 round .. 1 twice as long as wide
	"moss": 0.5,
	"texture": 0.5,       # cracks and layers in the stone
	"tint": [0.5, 0.51, 0.53],
}

static var _meshes := {}   # style and variant -> ArrayMesh
static var _icos := {}     # subdivisions -> [unit vertices, indices], for the trees


static func style_of(base: Dictionary, s) -> Dictionary:
	var out := base.duplicate(true)
	if s is Dictionary:
		for k in s:
			out[k] = s[k]
	return out


## The stone for a style and a variant, one metre across, resting on y = 0.
## Shapes are cached: many pebbles share a handful of them.
static func mesh(style: Dictionary, variant: int, detail := 3) -> ArrayMesh:
	var shape := style.duplicate()
	for look in ["moss", "texture", "tint", "size", "variation"]:
		shape.erase(look)
	var key := "%s|%d" % [str(shape), variant]
	if _meshes.has(key):
		return _meshes[key]
	var m := _build(style, variant)
	_meshes[key] = m
	return m


static func _build(style: Dictionary, seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 7919 + 13
	var angular: float = style.angular
	# a rough ball to start from: a cube with its corners and edges cut off
	var faces := _cube(1.3)
	var t := (1.0 + sqrt(5.0)) * 0.5
	for p in [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0), Vector3(0, -1, t), Vector3(0, 1, t),
			Vector3(0, -1, -t), Vector3(0, 1, -t), Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]:
		faces = _clip(faces, (p as Vector3).normalized(), 1.12)
	# the cuts: fewer and bigger the more angular, each at its own depth
	var count := int(round(lerpf(30.0, 15.0, angular)))
	for c in count:
		var n := Vector3(rng.randfn(), rng.randfn() * 0.8, rng.randfn()).normalized()
		faces = _clip(faces, n, rng.randf_range(lerpf(0.9, 0.78, angular), 1.0))
	faces = _clip(faces, Vector3.DOWN, 0.55)   # the flat underside
	# a slab is worn flat on top too, where feet and weather have smoothed it
	if float(style.flat) > 0.5:
		faces = _clip(faces, Vector3.UP, lerpf(1.1, 0.55, (float(style.flat) - 0.5) * 2.0))
	# stretched long or flat, then one metre across, resting on y = 0
	var stretch := Vector3(1.0 + float(style.long) * 0.9, lerpf(0.95, 0.2, float(style.flat)), 1.0)
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for f in faces:
		for k in (f as Array).size():
			f[k] = (f[k] as Vector3) * stretch
			lo = lo.min(f[k])
			hi = hi.max(f[k])
	var across := maxf(hi.x - lo.x, hi.z - lo.z)
	var mid := Vector3((lo.x + hi.x) * 0.5, lo.y, (lo.z + hi.z) * 0.5)
	var centre := Vector3(0, (hi.y - lo.y) * 0.5 / across, 0)
	for f in faces:
		for k in (f as Array).size():
			f[k] = ((f[k] as Vector3) - mid) / across
	# worn stones have their faces' normals rounded toward the middle
	var round := (1.0 - angular) * 0.55
	var verts := PackedVector3Array()
	var nrm := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var idx := PackedInt32Array()
	for fi in faces.size():
		var f: Array = faces[fi]
		var m := f.size()
		var c := Vector3.ZERO
		for p in f:
			c += p
		c /= m
		var fn := Vector3.ZERO
		for k in m:
			fn += (f[k] as Vector3).cross(f[(k + 1) % m])
		if fn.length() < 1e-9:
			continue
		fn = fn.normalized()
		if fn.dot(c - centre) < 0.0:
			fn = -fn
		var shade := fposmod(sin(float(fi + seed * 3) * 12.9898) * 43758.5453, 1.0)
		var col := Color(1.0, shade, 1.0, 1.0)
		for k in m:
			var a: Vector3 = f[k]
			var b: Vector3 = f[(k + 1) % m]
			var ab := b - a
			# how far the middle lies from this rim
			var h := (c - a - ab * (c - a).dot(ab) / maxf(ab.length_squared(), 1e-12)).length()
			if ab.length() < 1e-6 or h < 1e-6:
				continue
			var base := verts.size()
			for q in [[c, 1.0], [a, 0.0], [b, 0.0]]:
				var p: Vector3 = q[0]
				verts.append(p)
				nrm.append(fn.lerp((p - centre).normalized(), round).normalized())
				uvs.append(Vector2(float(q[1]), h))
				colors.append(col)
			if MeshUtil.face_normal(c, a, b).dot(fn) < 0.0:
				idx.append_array([base, base + 2, base + 1])
			else:
				idx.append_array([base, base + 1, base + 2])
	var out := ArrayMesh.new()
	MeshUtil.add_surface(out, verts, nrm, uvs, colors, idx)
	return out


## A cube's faces, `h` from its middle, each a loop of corners.
static func _cube(h: float) -> Array:
	var out: Array = []
	for ax in 3:
		for s in [-1.0, 1.0]:
			var u := (ax + 1) % 3
			var w := (ax + 2) % 3
			var face: Array = []
			for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var p := Vector3.ZERO
				p[ax] = s * h
				p[u] = corner.x * h
				p[w] = corner.y * h
				face.append(p)
			out.append(face)
	return out


## A convex block (its faces, loops of corners) cut by the plane n.p = d:
## what lies beyond is taken away and the cut closed with a new face.
static func _clip(faces: Array, n: Vector3, d: float) -> Array:
	var out: Array = []
	var cut: Array = []
	for f in faces:
		var poly: Array = f
		var kept: Array = []
		var m := poly.size()
		for k in m:
			var a: Vector3 = poly[k]
			var b: Vector3 = poly[(k + 1) % m]
			var da := n.dot(a) - d
			var db := n.dot(b) - d
			if da <= 0.0:
				kept.append(a)
			if (da <= 0.0) != (db <= 0.0):
				var p := a.lerp(b, da / (da - db))
				kept.append(p)
				cut.append(p)
		if kept.size() >= 3:
			out.append(kept)
	# the new face: the cut's points, each once, in order round their middle
	var uniq: Array = []
	for p in cut:
		var seen := false
		for q in uniq:
			if (q as Vector3).distance_squared_to(p) < 1e-10:
				seen = true
				break
		if not seen:
			uniq.append(p)
	if uniq.size() >= 3:
		var c := Vector3.ZERO
		for p in uniq:
			c += p
		c /= uniq.size()
		var u := n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized()
		var w := n.cross(u)
		uniq.sort_custom(func(p: Vector3, q: Vector3) -> bool:
			return atan2((p - c).dot(w), (p - c).dot(u)) < atan2((q - c).dot(w), (q - c).dot(u)))
		out.append(uniq)
	return out


## A sphere of near-even triangles: an icosahedron split `n` times.
static func _icosphere(n: int) -> Array:
	if _icos.has(n):
		return _icos[n]
	var t := (1.0 + sqrt(5.0)) * 0.5
	var verts := PackedVector3Array([
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)])
	for k in verts.size():
		verts[k] = verts[k].normalized()
	var faces := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2],
		[10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11],
		[6, 2, 10], [8, 6, 7], [9, 8, 1]]
	for _split in n:
		var mids := {}
		var next := []
		for f in faces:
			var m := []
			for e in 3:
				var a: int = f[e]
				var b: int = f[(e + 1) % 3]
				var key := Vector2i(mini(a, b), maxi(a, b))
				if not mids.has(key):
					verts.append(((verts[a] + verts[b]) * 0.5).normalized())
					mids[key] = verts.size() - 1
				m.append(mids[key])
			next.append([f[0], m[0], m[2]])
			next.append([f[1], m[1], m[0]])
			next.append([f[2], m[2], m[1]])
			next.append([m[0], m[1], m[2]])
		faces = next
	var idx := PackedInt32Array()
	for f in faces:
		# wound for Godot's front faces
		idx.append_array([f[0], f[2], f[1]])
	_icos[n] = [verts, idx]
	return _icos[n]
