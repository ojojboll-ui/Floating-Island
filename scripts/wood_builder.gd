extends RefCounted
## Stylized wood, after hand-sculpted game props: bark in long plates split
## by deep grooves, a bark rim standing proud round every cut face, the cut
## itself pale with a spiral of rings, roots that flare out of a stump's foot
## and taper to points along the ground, knots with their own little cut
## faces, and splintered ends where wood was broken rather than cut.
##
## Everything goes into one Wood accumulator drawn with wood.gdshader.
## Vertex colour carries what the shader needs:
##   r  how deep in a groove (darker)
##   g  what surface: 0 bark, 0.3 a knot's eye, 0.5 the bark rim round a cut, 0.75 a split
##      face, 1 a cut end
##   b  a random shade per bark plate
## UV is round-and-along for bark and split faces (grain), and centred polar
## coordinates (-1..1 across) for cut ends (rings).

const MeshUtil := preload("res://scripts/mesh_util.gd")

const BARK := 0.0
const EYE := 0.3
const RIM := 0.5
const SPLIT := 0.75
const CUT := 1.0

static var _mat: ShaderMaterial


static func material() -> ShaderMaterial:
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = load("res://shaders/wood.gdshader")
	return _mat


class Wood:
	var v := PackedVector3Array()
	var uv := PackedVector2Array()
	var c := PackedColorArray()
	var i := PackedInt32Array()
	var rng := RandomNumberGenerator.new()

	func put(p: Vector3, t: Vector2, col: Color) -> int:
		v.append(p)
		uv.append(t)
		c.append(col)
		return v.size() - 1

	func empty() -> bool:
		return i.is_empty()

	func mesh() -> ArrayMesh:
		var m := ArrayMesh.new()
		if i.is_empty():
			return m
		MeshUtil.add_surface(m, v, MeshUtil.normals(v, i), uv, c, i)
		return m

	## A bark tube along `path`, `radii` thick, split into `plates` plates by
	## grooves `groove` deep (a share of the radius). `end_jag` pushes some
	## plates on past the last ring (a broken, splintered end) and `top_jag`
	## lifts some above it (a stump's broken rim). Returns the last ring's
	## vertex positions, for a cap.
	func trunk(path: Array[Vector3], radii: Array[float], plates: int, groove: float, end_jag := 0.0) -> Array:
		var n := path.size()
		var sides := plates * 6
		# plate boundaries, unevenly spaced, and a shade for each plate
		var bounds: Array[float] = []
		var shade: Array[float] = []
		for p in plates:
			bounds.append((p + rng.randf_range(-0.25, 0.25)) / plates)
			shade.append(rng.randf())
		var jag: Array[float] = []
		for p in plates:
			jag.append(rng.randf() * end_jag if rng.randf() < 0.65 else 0.0)
		var wander := rng.randf() * TAU
		var t0 := (path[1] - path[0]).normalized()
		var u := t0.cross(Vector3.RIGHT if absf(t0.x) < 0.9 else Vector3.FORWARD).normalized()
		var first := v.size()
		var along := 0.0
		var last_ring: Array = []
		for k in n:
			var t := (path[mini(k + 1, n - 1)] - path[maxi(k - 1, 0)]).normalized()
			u = (u - t * u.dot(t)).normalized()
			var w := t.cross(u)
			if k > 0:
				along += path[k].distance_to(path[k - 1])
			var drift := sin(along * 1.7 + wander) * 0.03 + sin(along * 4.1 + wander * 2.0) * 0.015
			for s in sides:
				var a := float(s) / sides
				var info := _plate(a - drift, bounds)
				var x: float = info[1]
				var p: int = info[0]
				# deep, narrow grooves; each plate gently rounded between them
				var g := 1.0 - smoothstep(0.0, 0.16, x) * smoothstep(1.0, 0.84, x)
				var r := radii[k] * (1.0 - g * groove + 0.035 * sin(PI * x))
				var ang := TAU * a
				var pos := path[k] + (u * cos(ang) + w * sin(ang)) * r
				if k == n - 1 and end_jag > 0.0:
					# splinters: a plate juts on, drawn to a point at its middle
					pos += t * jag[p] * sin(PI * x)
				put(pos, Vector2(a, along), Color(g, BARK, shade[p], 1.0))
				if k == n - 1:
					last_ring.append(pos)
		for k in n - 1:
			for s in sides:
				var a := first + k * sides + s
				var b := first + k * sides + (s + 1) % sides
				i.append_array([a, a + sides, b, b, a + sides, b + sides])
		return last_ring

	## Which plate a point round the trunk (0..1) falls in, and how far
	## across it (0..1).
	func _plate(a: float, bounds: Array[float]) -> Array:
		a = fposmod(a, 1.0)
		var m := bounds.size()
		for p in m:
			var lo: float = bounds[p]
			var hi: float = bounds[(p + 1) % m] + (1.0 if p == m - 1 else 0.0)
			var aa := a if a >= lo else a + 1.0
			if aa >= lo and aa < hi:
				return [p, (aa - lo) / (hi - lo)]
		return [0, 0.5]

	## A cut face closing `ring` (a trunk's last ring): a bark rim standing
	## round it, and the pale cut sunk `inset` below, its rings in a spiral.
	## `level`, if given, is where the cut lies along `axis` from `centre`
	## (a broken rim stands above it).
	func cap(ring: Array, centre: Vector3, axis: Vector3, rim: float, inset: float) -> void:
		var n := ring.size()
		var radius := 0.0
		for p in ring:
			radius = maxf(radius, ((p as Vector3) - centre).length())
		var low := INF
		for p in ring:
			low = minf(low, ((p as Vector3) - centre).dot(axis))
		var plane := centre + axis * minf(low, 0.0)
		var side := axis.cross(Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT).normalized()
		var other := axis.cross(side)
		# each band has vertices of its own, so the rim's top, its inner wall
		# and the cut meet in sharp edges instead of smoothed ones (smoothed
		# normals across a sharp edge speckle the shadows)
		var outer := []
		var lip_top := []
		var lip_wall := []
		var wall_low := []
		var cut_edge := []
		for p in ring:
			var q: Vector3 = p
			var flat := q - axis * (q - centre).dot(axis)
			var rel := flat - centre
			var lip := centre + rel * (1.0 - rim) + axis * (plane - centre).dot(axis)
			var sunk := lip - axis * inset
			var polar := Vector2(rel.dot(side), rel.dot(other)) / maxf(radius * (1.0 - rim), 0.001)
			outer.append(put(q, Vector2.ZERO, Color(0.2, RIM, 0.5, 1.0)))
			lip_top.append(put(lip, Vector2.ZERO, Color(0.35, RIM, 0.5, 1.0)))
			lip_wall.append(put(lip, Vector2.ZERO, Color(0.35, RIM, 0.5, 1.0)))
			wall_low.append(put(sunk, Vector2.ZERO, Color(0.5, RIM, 0.5, 1.0)))
			cut_edge.append(put(sunk, polar, Color(0.0, CUT, 0.5, 1.0)))
		for s in n:
			var s2 := (s + 1) % n
			i.append_array([outer[s], lip_top[s], outer[s2], outer[s2], lip_top[s], lip_top[s2]])
			i.append_array([lip_wall[s], wall_low[s], lip_wall[s2], lip_wall[s2], wall_low[s], wall_low[s2]])
		var mid := put(plane - axis * inset, Vector2.ZERO, Color(0.0, CUT, 0.5, 1.0))
		for s in n:
			i.append_array([mid, cut_edge[(s + 1) % n], cut_edge[s]])

	## A knot's eye: an oval swelling in the bark, `r` across and longer
	## along the grain, ringed round a dark sunken heart, where a branch
	## once grew and the bark closed over it.
	func eye(at: Vector3, out: Vector3, along: Vector3, r: float) -> void:
		out = out.normalized()
		along = (along - out * along.dot(out)).normalized()
		var across := out.cross(along)
		var first_i := i.size()
		var sides := 16
		# rings from the heart out: [reach, height above the bark]
		var rings := [[0.0, -0.1], [0.22, 0.08], [0.5, 0.32], [0.8, 0.3], [1.0, 0.14], [1.4, 0.0]]
		var ids := []
		for k in rings.size():
			var reach: float = rings[k][0]
			var hgt: float = rings[k][1]
			var ring := []
			var count := 1 if k == 0 else sides
			for s in count:
				var a := TAU * s / sides
				var d := along * cos(a) * 1.5 + across * sin(a)
				var p := at + d * r * reach + out * r * hgt
				var polar := Vector2(cos(a), sin(a)) * reach / 1.4
				# the outermost ring is plain bark, so the eye grows out of it
				var col := Color(0.0, BARK, 0.5, 1.0) if k == rings.size() - 1 else Color(0.0, EYE, 0.5, 1.0)
				ring.append(put(p, polar, col))
			ids.append(ring)
		for s in sides:
			var s2 := (s + 1) % sides
			i.append_array([ids[0][0], ids[1][s], ids[1][s2]])
		for k in range(1, rings.size() - 1):
			for s in sides:
				var s2 := (s + 1) % sides
				i.append_array([ids[k][s], ids[k + 1][s], ids[k][s2], ids[k][s2], ids[k + 1][s], ids[k + 1][s2]])
		# every face turned to look out of the bark
		for t in range(first_i, i.size(), 3):
			var p0 := v[i[t]]
			var p1 := v[i[t + 1]]
			var p2 := v[i[t + 2]]
			if MeshUtil.face_normal(p0, p1, p2).dot(out) < 0.0:
				var keep := i[t + 1]
				i[t + 1] = i[t + 2]
				i[t + 2] = keep

	## A knot: a short broken stub out of the bark, its end cut and ringed.
	func knot(at: Vector3, out: Vector3, r: float) -> void:
		var path: Array[Vector3] = [at - out * r * 0.6, at + out * r * 0.6, at + out * r * 1.3]
		var ring := trunk(path, [r * 1.4, r * 1.05, r] as Array[float], 3, 0.06)
		cap(ring, path[2], out.normalized(), 0.18, r * 0.12)

	## A root out of a stump's foot: from inside the trunk out and down to
	## the ground, tapering to a rounded point.
	func root(foot: Vector3, out: Vector3, length: float, r0: float, ground: float) -> void:
		var path: Array[Vector3] = []
		var radii: Array[float] = []
		var steps := 9
		var start := foot + Vector3.UP * r0 * 1.2
		for s in steps:
			var t := float(s) / (steps - 1)
			var p := start + out * length * t
			# arching out of the trunk, then lying along the ground
			p.y = lerpf(start.y, ground + r0 * 0.25 * (1.0 - t), smoothstep(0.0, 0.7, t))
			p += out.cross(Vector3.UP) * sin(t * PI * 1.3 + r0 * 9.0) * length * 0.06
			path.append(p)
			var taper := pow(1.0 - t, 0.8)
			radii.append(maxf(r0 * taper, r0 * 0.08))
		radii[steps - 1] = r0 * 0.02
		trunk(path, radii, 4, 0.12)

	## A split piece of a round: `angle` wide, `r` from the heart to the
	## bark, `len` long along z, placed by xf at its heart. Bark round its
	## back, split faces with long grain, cut ends showing arcs of rings.
	func split(xf: Transform3D, len: float, r: float, angle: float) -> void:
		var arc := 8
		var hz := len * 0.5
		var first_i := i.size()
		var pts: Array[Vector2] = []
		for s in arc + 1:
			var a := PI * 0.5 - angle * 0.5 + angle * s / arc
			pts.append(Vector2(cos(a), sin(a)) * r)
		var shade := rng.randf()
		# the two ends
		for z in [-hz, hz]:
			var c0 := put(xf * Vector3(0, 0, z), Vector2.ZERO, Color(0, CUT, shade, 1))
			var ring := []
			for p in pts:
				ring.append(put(xf * Vector3(p.x, p.y, z), p / r, Color(0, CUT, shade, 1)))
			for s in arc:
				if z > 0.0:
					i.append_array([c0, ring[s], ring[s + 1]])
				else:
					i.append_array([c0, ring[s + 1], ring[s]])
		# the bark round the back, a groove or two in it
		for s in arc:
			var g := 0.8 if s == arc / 3 or s == arc * 2 / 3 else 0.1
			var q := []
			for p in [[pts[s], -hz], [pts[s + 1], -hz], [pts[s + 1], hz], [pts[s], hz]]:
				var pp: Vector2 = p[0]
				q.append(put(xf * Vector3(pp.x * 1.02, pp.y * 1.02, float(p[1])), Vector2(float(s) / arc, float(p[1])), Color(g, BARK, shade, 1)))
			i.append_array([q[0], q[1], q[2], q[0], q[2], q[3]])
		# the split faces, heart to bark
		for side in [0, arc]:
			var p: Vector2 = pts[side]
			var f := []
			for q in [[Vector2.ZERO, -hz], [p, -hz], [p, hz], [Vector2.ZERO, hz]]:
				var pp: Vector2 = q[0]
				f.append(put(xf * Vector3(pp.x, pp.y, float(q[1])), Vector2(pp.length() / r * 0.5 + shade, float(q[1])), Color(0, SPLIT, shade, 1)))
			i.append_array([f[0], f[2], f[1], f[0], f[3], f[2]])
		# every face turned to look out of the piece
		var inside := xf * Vector3(0, r * 0.55, 0)
		for t in range(first_i, i.size(), 3):
			var a := v[i[t]]
			var b := v[i[t + 1]]
			var cc := v[i[t + 2]]
			if MeshUtil.face_normal(a, b, cc).dot((a + b + cc) / 3.0 - inside) < 0.0:
				var keep := i[t + 1]
				i[t + 1] = i[t + 2]
				i[t + 2] = keep


## A MeshInstance for the accumulated wood, in the given colours.
static func instance(w: Wood, bark: Array, wood: Array, moss: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = w.mesh()
	mi.material_override = material()
	# thin bark edges (a broken rim, splinters) shadow themselves in speckles
	# when only their front faces cast
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	mi.set_instance_shader_parameter("bark_color", Vector3(bark[0], bark[1], bark[2]))
	mi.set_instance_shader_parameter("wood_color", Vector3(wood[0], wood[1], wood[2]))
	mi.set_instance_shader_parameter("moss", moss)
	return mi
